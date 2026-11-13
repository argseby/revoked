package routes

import (
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"regexp"
	"slices"
	"strings"

	"revoked/cmd/revoked/services"
	"revoked/util"

	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/apis"
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tools/filesystem"
)

const (
	// Enough to remove everything a full list could hold in one write.
	maxSealedEntries = 2 * util.MaxSealedLiveEntries
	maxSealedWraps   = 500
	// The passkeys collection's own limit on a credential id.
	maxSealedCredentialID = 1400
	// sealedResetConfirmation must be sent to start over: it destroys data
	// nobody can recover, so a stray or replayed call must not be enough.
	sealedResetConfirmation = "delete my encrypted records"
)

var (
	sealedRecordID = regexp.MustCompile(`^[a-z0-9]{15}$`)
)

// decodeSealed accepts only the exact encoding the app produces. Go's decoder
// skips newlines and tolerates spare trailing bits where Dart's refuses them, so
// without this a stolen device could get an entry past this server that no client
// can parse, and the list could never be repaired.
func decodeSealed(s string) ([]byte, bool) {
	raw, err := base64.URLEncoding.Strict().DecodeString(s)
	if err != nil || base64.URLEncoding.EncodeToString(raw) != s {
		return nil, false
	}
	return raw, true
}

func (e sealedEntry) toChainEntry(userID string) (util.SealedChainEntry, bool) {
	hpke, ok1 := decodeSealed(e.HpkePublicKey)
	signing, ok2 := decodeSealed(e.SigningPublicKey)
	previous, ok3 := decodeSealed(e.PreviousHash)
	anchor, ok4 := decodeSealed(e.AnchorSignature)
	signature, ok5 := decodeSealed(e.Signature)
	return util.SealedChainEntry{
		User:             userID,
		Seq:              e.Seq,
		Action:           e.Action,
		Kind:             e.Kind,
		Label:            e.Label,
		CredentialID:     e.CredentialId,
		HpkePublicKey:    hpke,
		SigningPublicKey: signing,
		TargetSeq:        e.TargetSeq,
		PreviousHash:     previous,
		SignerSeq:        e.SignerSeq,
		AnchorSignature:  anchor,
		Signature:        signature,
	}, ok1 && ok2 && ok3 && ok4 && ok5
}

// loadSealedChain rebuilds a person's device list from what was checked when it
// was appended.
func loadSealedChain(tx core.App, userID string) (*util.SealedChain, error) {
	d := util.Fields.DeviceKey
	rows, err := tx.FindRecordsByFilter(util.Coll.DeviceKeys,
		d.User+" = {:u}", d.Seq, 0, 0, dbx.Params{"u": userID})
	if err != nil {
		return nil, err
	}
	chain := &util.SealedChain{}
	for _, row := range rows {
		entry, _ := sealedEntry{
			HpkePublicKey:    row.GetString(d.HpkePublicKey),
			SigningPublicKey: row.GetString(d.SigningPublicKey),
			PreviousHash:     row.GetString(d.PreviousHash),
			AnchorSignature:  row.GetString(d.AnchorSignature),
			Signature:        row.GetString(d.Signature),
			Seq:              row.GetInt(d.Seq),
			Action:           row.GetString(d.Action),
			Kind:             row.GetString(d.Kind),
			Label:            row.GetString(d.Label),
			CredentialId:     row.GetString(d.CredentialId),
			TargetSeq:        row.GetInt(d.TargetSeq),
			SignerSeq:        row.GetInt(d.SignerSeq),
		}.toChainEntry(userID)
		chain.Load(entry)
	}
	return chain, nil
}

// sealedRefusal carries a refusal out of a transaction, so everything the
// transaction did rolls back before the error is written.
type sealedRefusal struct {
	status int
	appErr *util.AppError
	extra  map[string]any
}

func (r *sealedRefusal) Error() string { return r.appErr.ErrorCode }

func refuse(status int, appErr *util.AppError) *sealedRefusal {
	return &sealedRefusal{status: status, appErr: appErr}
}

func writeSealedResult(re *core.RequestEvent, err error) error {
	var refusal *sealedRefusal
	if errors.As(err, &refusal) {
		body := map[string]any{
			"code":    refusal.appErr.ErrorCode,
			"message": refusal.appErr.ErrorText,
			"status":  refusal.status,
		}
		for k, v := range refusal.extra {
			body[k] = v
		}
		return re.JSON(refusal.status, body)
	}
	return err
}

// SealedRoute serves end-to-end encrypted records. The server never decrypts
// anything here, and clients trust nothing it says: each one checks the device
// list and wraps for itself (E2EE.md §4). The server enforces what a client
// cannot do alone: versions move one at a time, a record and its key land
// together, nothing is written under a key someone was removed from, and only
// a device on the list can change it. A session is not enough for that last one,
// because it can be stolen and a device's signing key can't be taken from here.
//
// An API key has no devices and can hold no key, so these are for people only.
func SealedRoute(app core.App) {
	app.OnServe().BindFunc(func(e *core.ServeEvent) error {
		e.Router.GET("/api/sealed/state", func(re *core.RequestEvent) error {
			if !authorizeSealed(re) {
				return nil
			}
			return sealedState(app, re)
		})
		e.Router.POST("/api/sealed/devices", func(re *core.RequestEvent) error {
			if !authorizeSealed(re) {
				return nil
			}
			return appendSealedDevices(app, re)
		})
		e.Router.POST("/api/sealed/workspaces/{id}/epochs", func(re *core.RequestEvent) error {
			if !authorizeSealed(re) {
				return nil
			}
			return startSealedEpoch(app, re)
		})
		e.Router.POST("/api/sealed/workspaces/{id}/grants", func(re *core.RequestEvent) error {
			if !authorizeSealed(re) {
				return nil
			}
			return grantSealedAccess(app, re)
		})
		e.Router.GET("/api/sealed/workspaces/{id}/members", func(re *core.RequestEvent) error {
			if !authorizeSealed(re) {
				return nil
			}
			return sealedMembers(app, re)
		})
		e.Router.POST("/api/sealed/account/epochs", func(re *core.RequestEvent) error {
			if !authorizeSealed(re) {
				return nil
			}
			return startAccountEpoch(app, re)
		})
		e.Router.POST("/api/sealed/records", func(re *core.RequestEvent) error {
			if !authorizeSealed(re) {
				return nil
			}
			return createSealedRecord(app, re)
		}).Bind(apis.BodyLimit(sealedBodyLimit()))
		e.Router.PUT("/api/sealed/records/{id}", func(re *core.RequestEvent) error {
			if !authorizeSealed(re) {
				return nil
			}
			return writeSealedRecord(app, re)
		}).Bind(apis.BodyLimit(sealedBodyLimit()))
		e.Router.POST("/api/sealed/records/{id}/unseal", func(re *core.RequestEvent) error {
			if !authorizeSealed(re) {
				return nil
			}
			return unsealRecord(app, re)
		}).Bind(apis.BodyLimit(sealedBodyLimit()))
		e.Router.GET("/api/sealed/records/{id}/links", func(re *core.RequestEvent) error {
			if !authorizeSealed(re) {
				return nil
			}
			return sealedRecordLinks(app, re)
		})
		e.Router.GET("/api/sealed/links/{id}", func(re *core.RequestEvent) error {
			if !authorizeSealed(re) {
				return nil
			}
			return sealedLinkState(app, re)
		})
		e.Router.PUT("/api/sealed/links/{id}", func(re *core.RequestEvent) error {
			if !authorizeSealed(re) {
				return nil
			}
			return writeSealedLink(app, re)
		})
		e.Router.POST("/api/sealed/sessions/revoke", func(re *core.RequestEvent) error {
			if !authorizeSealed(re) {
				return nil
			}
			return revokeOtherSessions(app, re)
		})
		e.Router.POST("/api/sealed/reset", func(re *core.RequestEvent) error {
			if !authorizeSealed(re) {
				return nil
			}
			return resetSealing(app, re)
		})
		return e.Next()
	})
}

func authorizeSealed(re *core.RequestEvent) bool {
	if re.Auth == nil {
		return denyGate(re, http.StatusUnauthorized, &util.Errors.NotAuthenticated)
	}
	if re.Auth.Collection().Name != util.Coll.Users {
		return denyGate(re, http.StatusForbidden, &util.Errors.ApiKeyNotPermitted)
	}
	if !allowRequest(re, sealedLimiter, re.Auth.Id) {
		_ = rateLimitedResponse(re)
		return false
	}
	return true
}

type sealedEntry struct {
	Seq              int    `json:"seq"`
	Action           string `json:"action"`
	Kind             string `json:"kind"`
	Label            string `json:"label"`
	CredentialId     string `json:"credentialId"`
	HpkePublicKey    string `json:"hpkePublicKey"`
	SigningPublicKey string `json:"signingPublicKey"`
	TargetSeq        int    `json:"targetSeq"`
	PreviousHash     string `json:"previousHash"`
	SignerSeq        int    `json:"signerSeq"`
	AnchorSignature  string `json:"anchorSignature"`
	Signature        string `json:"signature"`
}

// sealedGrant is a workspace key handed to another member's device. chainSeq is
// how far the granter's list had got, recipientChainSeq the recipient's.
type sealedGrant struct {
	User              string `json:"user"`
	DeviceSeq         int    `json:"deviceSeq"`
	Wrap              string `json:"wrap"`
	SignerSeq         int    `json:"signerSeq"`
	ChainSeq          int    `json:"chainSeq"`
	RecipientChainSeq int    `json:"recipientChainSeq"`
	Signature         string `json:"signature"`
}

type sealedWrap struct {
	Workspace string `json:"workspace"`
	Epoch     int    `json:"epoch"`
	DeviceSeq int    `json:"deviceSeq"`
	Wrap      string `json:"wrap"`
	SignerSeq int    `json:"signerSeq"`
	ChainSeq  int    `json:"chainSeq"`
	Signature string `json:"signature"`
}

// sealedDeviceList is a person's device list as stored, for a client to check.
func sealedDeviceList(app core.App, userID string) ([]map[string]any, error) {
	d := util.Fields.DeviceKey
	rows, err := app.FindRecordsByFilter(util.Coll.DeviceKeys,
		d.User+" = {:u}", d.Seq, 0, 0, dbx.Params{"u": userID})
	if err != nil {
		return nil, err
	}
	devices := make([]map[string]any, 0, len(rows))
	for _, row := range rows {
		devices = append(devices, map[string]any{
			"user":             row.GetString(d.User),
			"seq":              row.GetInt(d.Seq),
			"action":           row.GetString(d.Action),
			"kind":             row.GetString(d.Kind),
			"label":            row.GetString(d.Label),
			"credentialId":     row.GetString(d.CredentialId),
			"hpkePublicKey":    row.GetString(d.HpkePublicKey),
			"signingPublicKey": row.GetString(d.SigningPublicKey),
			"targetSeq":        row.GetInt(d.TargetSeq),
			"previousHash":     row.GetString(d.PreviousHash),
			"signerSeq":        row.GetInt(d.SignerSeq),
			"anchorSignature":  row.GetString(d.AnchorSignature),
			"signature":        row.GetString(d.Signature),
		})
	}

	return devices, nil
}

func sealedState(app core.App, re *core.RequestEvent) error {
	devices, err := sealedDeviceList(app, re.Auth.Id)
	if err != nil {
		return re.InternalServerError("Failed to read devices.", err)
	}

	m := util.Fields.WorkspaceMember
	memberships, err := app.FindRecordsByFilter(util.Coll.WorkspaceMembers,
		m.User+" = {:u}", "", 0, 0, dbx.Params{"u": re.Auth.Id})
	if err != nil {
		return re.InternalServerError("Failed to read workspaces.", err)
	}

	e := util.Fields.WorkspaceKeyEpoch
	w := util.Fields.WorkspaceKeyWrap
	workspaces := []map[string]any{}
	for _, member := range memberships {
		workspace := member.GetString(m.Workspace)
		epochRows, err := app.FindRecordsByFilter(util.Coll.WorkspaceKeyEpochs,
			e.Workspace+" = {:w}", e.Epoch, 0, 0, dbx.Params{"w": workspace})
		if err != nil {
			return re.InternalServerError("Failed to read keys.", err)
		}
		if len(epochRows) == 0 {
			continue
		}
		epochs := make([]map[string]any, 0, len(epochRows))
		for _, row := range epochRows {
			epochs = append(epochs, map[string]any{
				"epoch":       row.GetInt(e.Epoch),
				"priorWrap":   row.GetString(e.PriorWrap),
				"rotationDue": row.GetBool(e.RotationDue),
			})
		}
		wrapRows, err := app.FindRecordsByFilter(util.Coll.WorkspaceKeyWraps,
			w.Workspace+" = {:w} && "+w.User+" = {:u}", w.Epoch, 0, 0,
			dbx.Params{"w": workspace, "u": re.Auth.Id})
		if err != nil {
			return re.InternalServerError("Failed to read keys.", err)
		}
		wraps := make([]map[string]any, 0, len(wrapRows))
		for _, row := range wrapRows {
			wraps = append(wraps, map[string]any{
				"epoch":             row.GetInt(w.Epoch),
				"deviceSeq":         row.GetInt(w.DeviceSeq),
				"wrap":              row.GetString(w.Wrap),
				"signerSeq":         row.GetInt(w.SignerSeq),
				"chainSeq":          row.GetInt(w.ChainSeq),
				"signature":         row.GetString(w.Signature),
				"granter":           row.GetString(w.Granter),
				"recipientChainSeq": row.GetInt(w.RecipientChainSeq),
			})
		}
		workspaces = append(workspaces, map[string]any{
			"workspace": workspace,
			"epochs":    epochs,
			"wraps":     wraps,
		})
	}

	account, err := accountKeyState(app, re.Auth.Id)
	if err != nil {
		return re.InternalServerError("Failed to read keys.", err)
	}
	// null, not {}, before any device made one: the router's JSON encoder
	// writes a nil map as an empty object, which reads as a key that exists.
	var accountJSON any
	if account != nil {
		accountJSON = account
	}

	return re.JSON(http.StatusOK, map[string]any{
		"devices":    devices,
		"workspaces": workspaces,
		"account":    accountJSON,
	})
}

// sealedMembers serves every member's device list, so a device can check each
// one for itself and remember where it starts before ever handing anyone a key
// (design/e2ee-sharing.md §2.3). Public keys only: no wrap, no value. canRead is
// the server's word on who may hold the workspace key, and only that.
func sealedMembers(app core.App, re *core.RequestEvent) error {
	workspace := re.Request.PathValue("id")
	if _, member := util.WorkspaceMemberOf(app, workspace, re.Auth.Id); !member {
		return appErrorResponse(re, http.StatusNotFound, &util.Errors.WorkspaceNotFound)
	}
	m := util.Fields.WorkspaceMember
	rows, err := app.FindRecordsByFilter(util.Coll.WorkspaceMembers,
		m.Workspace+" = {:w}", m.Created, 0, 0, dbx.Params{"w": workspace})
	if err != nil {
		return re.InternalServerError("Failed to read members.", err)
	}
	epoch := 0
	if current := services.CurrentKeyEpoch(app, workspace); current != nil {
		epoch = current.GetInt(util.Fields.WorkspaceKeyEpoch.Epoch)
	}
	members := make([]map[string]any, 0, len(rows))
	for _, row := range rows {
		userID := row.GetString(m.User)
		devices, err := sealedDeviceList(app, userID)
		if err != nil {
			return re.InternalServerError("Failed to read devices.", err)
		}
		entry := map[string]any{
			"user":     userID,
			"isSelf":   userID == re.Auth.Id,
			"canRead":  services.MemberCanReadRecords(row),
			"canGrant": services.MemberCanAdminister(row),
			"holdsKey": epoch > 0 && services.HoldsWorkspaceKey(app, workspace, userID, epoch),
			"devices":  devices,
		}
		if user, err := app.FindRecordById(util.Coll.Users, userID); err == nil && user != nil {
			entry["email"] = user.GetString(util.Fields.User.Email)
		}
		members = append(members, entry)
	}
	return re.JSON(http.StatusOK, map[string]any{"members": members, "epoch": epoch})
}

// accountKeyState is the caller's own key in the shape of a workspace row, under
// its scope name, or nil before any device has made one.
func accountKeyState(app core.App, userID string) (map[string]any, error) {
	e := util.Fields.AccountKeyEpoch
	epochRows, err := app.FindRecordsByFilter(util.Coll.AccountKeyEpochs,
		e.User+" = {:u}", e.Epoch, 0, 0, dbx.Params{"u": userID})
	if err != nil || len(epochRows) == 0 {
		return nil, err
	}
	epochs := make([]map[string]any, 0, len(epochRows))
	for _, row := range epochRows {
		epochs = append(epochs, map[string]any{
			"epoch":       row.GetInt(e.Epoch),
			"priorWrap":   row.GetString(e.PriorWrap),
			"rotationDue": row.GetBool(e.RotationDue),
		})
	}
	w := util.Fields.AccountKeyWrap
	wrapRows, err := app.FindRecordsByFilter(util.Coll.AccountKeyWraps,
		w.User+" = {:u}", w.Epoch, 0, 0, dbx.Params{"u": userID})
	if err != nil {
		return nil, err
	}
	wraps := make([]map[string]any, 0, len(wrapRows))
	for _, row := range wrapRows {
		wraps = append(wraps, map[string]any{
			"epoch":     row.GetInt(w.Epoch),
			"deviceSeq": row.GetInt(w.DeviceSeq),
			"wrap":      row.GetString(w.Wrap),
			"signerSeq": row.GetInt(w.SignerSeq),
			"chainSeq":  row.GetInt(w.ChainSeq),
			"signature": row.GetString(w.Signature),
		})
	}
	return map[string]any{
		"workspace": util.SealedAccountScope(userID),
		"epochs":    epochs,
		"wraps":     wraps,
	}, nil
}

func validSealedEntry(entry sealedEntry) bool {
	if entry.Seq < 1 || entry.SignerSeq < 1 || len(entry.Label) > 255 {
		return false
	}
	if _, ok := entry.toChainEntry(""); !ok {
		return false
	}
	switch entry.Action {
	case util.SealedActionAdd:
		if entry.TargetSeq != 0 {
			return false
		}
		switch entry.Kind {
		case util.SealedKindDevice, util.SealedKindRecovery:
			return entry.CredentialId == ""
		case util.SealedKindPasskey:
			return entry.CredentialId != "" && len(entry.CredentialId) <= maxSealedCredentialID
		}
		return false
	case util.SealedActionRemove:
		return entry.TargetSeq >= 1 && entry.CredentialId == ""
	}
	return false
}

// appendSealedDevices adds to a person's device list and hands keys to the
// devices in it, in one transaction: a device that joins without its keys could
// never read anything, and retrying would then trip over its own entry.
func appendSealedDevices(app core.App, re *core.RequestEvent) error {
	var body struct {
		Entries []sealedEntry `json:"entries"`
		Wraps   []sealedWrap  `json:"wraps"`
	}
	if err := re.BindBody(&body); err != nil {
		return appErrorResponse(re, http.StatusBadRequest, &util.Errors.SealedInvalid)
	}
	if len(body.Entries) == 0 || len(body.Entries) > maxSealedEntries || len(body.Wraps) > maxSealedWraps {
		return appErrorResponse(re, http.StatusBadRequest, &util.Errors.SealedInvalid)
	}
	for _, entry := range body.Entries {
		if !validSealedEntry(entry) {
			return appErrorResponse(re, http.StatusBadRequest, &util.Errors.SealedInvalid)
		}
	}

	d := util.Fields.DeviceKey
	userID := re.Auth.Id
	err := app.RunInTransaction(func(tx core.App) error {
		collection, err := tx.FindCollectionByNameOrId(util.Coll.DeviceKeys)
		if err != nil {
			return err
		}
		chain, err := loadSealedChain(tx, userID)
		if err != nil {
			return err
		}

		for _, entry := range body.Entries {
			if entry.Seq != chain.NextSeq() {
				return refuse(http.StatusConflict, &util.Errors.SealedVersionConflict)
			}
			checked, ok := entry.toChainEntry(userID)
			if !ok || chain.Append(checked) != nil {
				return refuse(http.StatusBadRequest, &util.Errors.SealedInvalid)
			}
			row := core.NewRecord(collection)
			row.Set(d.User, userID)
			row.Set(d.Seq, entry.Seq)
			row.Set(d.Action, entry.Action)
			row.Set(d.Kind, entry.Kind)
			row.Set(d.Label, entry.Label)
			row.Set(d.CredentialId, entry.CredentialId)
			row.Set(d.HpkePublicKey, entry.HpkePublicKey)
			row.Set(d.SigningPublicKey, entry.SigningPublicKey)
			row.Set(d.TargetSeq, entry.TargetSeq)
			row.Set(d.PreviousHash, entry.PreviousHash)
			row.Set(d.SignerSeq, entry.SignerSeq)
			row.Set(d.AnchorSignature, entry.AnchorSignature)
			row.Set(d.Signature, entry.Signature)
			if err := tx.Save(row); err != nil {
				return err
			}
			if entry.Action == util.SealedActionRemove {
				if err := withdrawDeviceWraps(tx, userID, entry.TargetSeq); err != nil {
					return err
				}
			}
		}

		return saveSealedWraps(tx, userID, body.Wraps, chain)
	})
	if err != nil {
		return writeSealedResult(re, err)
	}

	services.RecordAudit(app, services.AuditEntry{
		Action:     util.AuditActionUpdate,
		Collection: util.Coll.DeviceKeys,
		RecordId:   userID,
		User:       userID,
		Ip:         re.Request.RemoteAddr,
		UserAgent:  re.Request.UserAgent(),
	})
	return re.JSON(http.StatusOK, map[string]any{"ok": true})
}

// withdrawDeviceWraps removes a device's copies of every workspace key, and
// makes a new epoch due wherever it held one: the device may have kept the key.
func withdrawDeviceWraps(tx core.App, userID string, deviceSeq int) error {
	w := util.Fields.WorkspaceKeyWrap
	rows, err := tx.FindRecordsByFilter(util.Coll.WorkspaceKeyWraps,
		w.User+" = {:u} && "+w.DeviceSeq+" = {:d}", "", 0, 0,
		dbx.Params{"u": userID, "d": deviceSeq})
	if err != nil {
		return err
	}
	due := map[string]bool{}
	for _, row := range rows {
		due[row.GetString(w.Workspace)] = true
		if err := tx.Delete(row); err != nil {
			return err
		}
	}
	for workspace := range due {
		if err := services.MarkKeyRotationDue(tx, workspace); err != nil {
			return err
		}
	}

	a := util.Fields.AccountKeyWrap
	held, err := tx.FindRecordsByFilter(util.Coll.AccountKeyWraps,
		a.User+" = {:u} && "+a.DeviceSeq+" = {:d}", "", 0, 0,
		dbx.Params{"u": userID, "d": deviceSeq})
	if err != nil {
		return err
	}
	for _, row := range held {
		if err := tx.Delete(row); err != nil {
			return err
		}
	}
	if len(held) > 0 {
		return services.MarkAccountKeyRotationDue(tx, userID)
	}
	return nil
}

// saveSealedWraps stores keys handed to the caller's own live devices, each signed
// by a device on the list. Phase 1 has no way to hand a key to another person, so
// naming anyone else's device is not a path that exists.
func saveSealedWraps(tx core.App, userID string, wraps []sealedWrap, chain *util.SealedChain) error {
	if len(wraps) == 0 {
		return nil
	}
	collection, err := tx.FindCollectionByNameOrId(util.Coll.WorkspaceKeyWraps)
	if err != nil {
		return err
	}
	w := util.Fields.WorkspaceKeyWrap
	e := util.Fields.WorkspaceKeyEpoch
	accountScope := util.SealedAccountScope(userID)
	for _, wrap := range wraps {
		if wrap.Workspace == accountScope {
			if err := saveAccountWrap(tx, userID, wrap, chain); err != nil {
				return err
			}
			continue
		}
		if strings.HasPrefix(wrap.Workspace, util.SealedAccountScope("")) {
			// Someone else's account key: never theirs to hand out.
			return refuse(http.StatusBadRequest, &util.Errors.SealedInvalid)
		}
		if _, member := util.WorkspaceMemberOf(tx, wrap.Workspace, userID); !member {
			return refuse(http.StatusForbidden, &util.Errors.NotWorkspaceMember)
		}
		signature, ok := decodeSealed(wrap.Signature)
		_, wrapOk := decodeSealed(wrap.Wrap)
		if !ok || !wrapOk || !chain.IsLive(wrap.DeviceSeq) || !chain.IsLive(wrap.SignerSeq) ||
			wrap.ChainSeq < 1 || wrap.ChainSeq > chain.HeadSeq() ||
			!util.VerifySealedSignature(chain.Entry(wrap.SignerSeq).SigningPublicKey,
				util.SealedWrapPayload(wrap.Workspace, wrap.Epoch,
					chain.Entry(wrap.DeviceSeq).HpkePublicKey, wrap.Wrap, wrap.ChainSeq),
				signature) {
			return refuse(http.StatusBadRequest, &util.Errors.SealedInvalid)
		}
		epoch, _ := tx.FindFirstRecordByFilter(util.Coll.WorkspaceKeyEpochs,
			e.Workspace+" = {:w} && "+e.Epoch+" = {:e}",
			dbx.Params{"w": wrap.Workspace, "e": wrap.Epoch})
		if epoch == nil {
			return refuse(http.StatusBadRequest, &util.Errors.SealedInvalid)
		}
		// Never replaced: overwriting a device's only copy of a key is how a stolen
		// session would destroy it for good.
		existing, _ := tx.FindFirstRecordByFilter(util.Coll.WorkspaceKeyWraps,
			w.Workspace+" = {:w} && "+w.Epoch+" = {:e} && "+w.User+" = {:u} && "+w.DeviceSeq+" = {:d}",
			dbx.Params{"w": wrap.Workspace, "e": wrap.Epoch, "u": userID, "d": wrap.DeviceSeq})
		if existing != nil {
			return refuse(http.StatusConflict, &util.Errors.SealedVersionConflict)
		}
		row := core.NewRecord(collection)
		row.Set(w.Workspace, wrap.Workspace)
		row.Set(w.Epoch, wrap.Epoch)
		row.Set(w.User, userID)
		row.Set(w.DeviceSeq, wrap.DeviceSeq)
		row.Set(w.Wrap, wrap.Wrap)
		row.Set(w.SignerSeq, wrap.SignerSeq)
		row.Set(w.ChainSeq, wrap.ChainSeq)
		row.Set(w.Signature, wrap.Signature)
		if err := tx.Save(row); err != nil {
			return err
		}
	}
	return nil
}

// checkWrapSignature accepts a wrap only for a live device on the caller's own
// list, signed by another live one over exactly what it hands over.
func checkWrapSignature(wrap sealedWrap, chain *util.SealedChain) bool {
	signature, ok := decodeSealed(wrap.Signature)
	_, wrapOk := decodeSealed(wrap.Wrap)
	return ok && wrapOk && chain.IsLive(wrap.DeviceSeq) && chain.IsLive(wrap.SignerSeq) &&
		wrap.ChainSeq >= 1 && wrap.ChainSeq <= chain.HeadSeq() &&
		util.VerifySealedSignature(chain.Entry(wrap.SignerSeq).SigningPublicKey,
			util.SealedWrapPayload(wrap.Workspace, wrap.Epoch,
				chain.Entry(wrap.DeviceSeq).HpkePublicKey, wrap.Wrap, wrap.ChainSeq),
			signature)
}

// saveAccountWrap stores one copy of the caller's account key. Never replaced,
// for the same reason as a workspace key's.
func saveAccountWrap(tx core.App, userID string, wrap sealedWrap, chain *util.SealedChain) error {
	if !checkWrapSignature(wrap, chain) {
		return refuse(http.StatusBadRequest, &util.Errors.SealedInvalid)
	}
	a := util.Fields.AccountKeyWrap
	e := util.Fields.AccountKeyEpoch
	epoch, _ := tx.FindFirstRecordByFilter(util.Coll.AccountKeyEpochs,
		e.User+" = {:u} && "+e.Epoch+" = {:e}", dbx.Params{"u": userID, "e": wrap.Epoch})
	if epoch == nil {
		return refuse(http.StatusBadRequest, &util.Errors.SealedInvalid)
	}
	existing, _ := tx.FindFirstRecordByFilter(util.Coll.AccountKeyWraps,
		a.User+" = {:u} && "+a.Epoch+" = {:e} && "+a.DeviceSeq+" = {:d}",
		dbx.Params{"u": userID, "e": wrap.Epoch, "d": wrap.DeviceSeq})
	if existing != nil {
		return refuse(http.StatusConflict, &util.Errors.SealedVersionConflict)
	}
	collection, err := tx.FindCollectionByNameOrId(util.Coll.AccountKeyWraps)
	if err != nil {
		return err
	}
	row := core.NewRecord(collection)
	row.Set(a.User, userID)
	row.Set(a.Epoch, wrap.Epoch)
	row.Set(a.DeviceSeq, wrap.DeviceSeq)
	row.Set(a.Wrap, wrap.Wrap)
	row.Set(a.SignerSeq, wrap.SignerSeq)
	row.Set(a.ChainSeq, wrap.ChainSeq)
	row.Set(a.Signature, wrap.Signature)
	return tx.Save(row)
}

// startAccountEpoch creates the caller's account key, or replaces it after one
// of their devices was removed. Like a workspace key: only a holder may replace
// it, the new key carries the old one, and every live device gets a copy.
func startAccountEpoch(app core.App, re *core.RequestEvent) error {
	var body struct {
		Epoch     int          `json:"epoch"`
		PriorWrap string       `json:"priorWrap"`
		Wraps     []sealedWrap `json:"wraps"`
	}
	if err := re.BindBody(&body); err != nil || body.Epoch < 1 ||
		len(body.Wraps) == 0 || len(body.Wraps) > maxSealedWraps || len(body.PriorWrap) > 256 {
		return appErrorResponse(re, http.StatusBadRequest, &util.Errors.SealedInvalid)
	}
	if body.PriorWrap != "" {
		if _, ok := decodeSealed(body.PriorWrap); !ok {
			return appErrorResponse(re, http.StatusBadRequest, &util.Errors.SealedInvalid)
		}
	}

	userID := re.Auth.Id
	scope := util.SealedAccountScope(userID)
	e := util.Fields.AccountKeyEpoch
	err := app.RunInTransaction(func(tx core.App) error {
		current := services.CurrentAccountEpoch(tx, userID)
		if current == nil {
			if body.Epoch != 1 || body.PriorWrap != "" {
				return refuse(http.StatusConflict, &util.Errors.SealedVersionConflict)
			}
		} else {
			if !services.HoldsAccountKey(tx, userID, current.GetInt(e.Epoch)) {
				return refuse(http.StatusForbidden, &util.Errors.SealedKeyMissing)
			}
			if body.Epoch != current.GetInt(e.Epoch)+1 {
				return refuse(http.StatusConflict, &util.Errors.SealedVersionConflict)
			}
			if body.PriorWrap == "" {
				return refuse(http.StatusBadRequest, &util.Errors.SealedInvalid)
			}
		}

		chain, err := loadSealedChain(tx, userID)
		if err != nil {
			return err
		}
		covered := map[int]bool{}
		for i := range body.Wraps {
			body.Wraps[i].Workspace = scope
			body.Wraps[i].Epoch = body.Epoch
			covered[body.Wraps[i].DeviceSeq] = true
		}
		for _, seq := range chain.Live() {
			if !covered[seq] {
				return refuse(http.StatusBadRequest, &util.Errors.SealedInvalid)
			}
		}

		collection, err := tx.FindCollectionByNameOrId(util.Coll.AccountKeyEpochs)
		if err != nil {
			return err
		}
		row := core.NewRecord(collection)
		row.Set(e.User, userID)
		row.Set(e.Epoch, body.Epoch)
		row.Set(e.PriorWrap, body.PriorWrap)
		if err := tx.Save(row); err != nil {
			return err
		}
		for _, wrap := range body.Wraps {
			if err := saveAccountWrap(tx, userID, wrap, chain); err != nil {
				return err
			}
		}
		return nil
	})
	if err != nil {
		return writeSealedResult(re, err)
	}

	services.RecordAudit(app, services.AuditEntry{
		Action:     util.AuditActionCreate,
		Collection: util.Coll.AccountKeyEpochs,
		RecordId:   userID,
		User:       userID,
		Ip:         re.Request.RemoteAddr,
		UserAgent:  re.Request.UserAgent(),
	})
	return re.JSON(http.StatusOK, map[string]any{"ok": true, "epoch": body.Epoch})
}

// saveSealedGrants stores keys a member hands to other members' devices. The
// granter must be able to bring people in, every recipient must be able to read
// the vault, and each copy must be signed by the granter's live device for a live
// device on the recipient's own list. Copies are never replaced. It returns whom
// it granted to.
func saveSealedGrants(tx core.App, granterID, workspace string, epoch int,
	grants []sealedGrant, granterChain *util.SealedChain) ([]string, error) {
	if len(grants) == 0 {
		return nil, nil
	}
	granter, member := util.WorkspaceMemberOf(tx, workspace, granterID)
	if !member {
		return nil, refuse(http.StatusForbidden, &util.Errors.NotWorkspaceMember)
	}
	if !services.MemberCanAdminister(granter) {
		return nil, refuse(http.StatusForbidden, &util.Errors.MissingPermission)
	}
	// An identity key still under the workspace key would open for whoever
	// receives it, and let them sign as its owner.
	i := util.Fields.Identity
	legacy, _ := tx.FindFirstRecordByFilter(util.Coll.Identities,
		i.Workspace+" = {:w} && "+i.SealedKey+" != '' && "+i.SealedKeyScope+" = ''",
		dbx.Params{"w": workspace})
	if legacy != nil {
		return nil, refuse(http.StatusConflict, &util.Errors.SealedIdentityKeysPending)
	}

	collection, err := tx.FindCollectionByNameOrId(util.Coll.WorkspaceKeyWraps)
	if err != nil {
		return nil, err
	}
	w := util.Fields.WorkspaceKeyWrap
	chains := map[string]*util.SealedChain{}
	granted := []string{}
	for _, g := range grants {
		if g.User == "" || g.User == granterID {
			return nil, refuse(http.StatusBadRequest, &util.Errors.SealedInvalid)
		}
		recipient, isMember := util.WorkspaceMemberOf(tx, workspace, g.User)
		if !isMember {
			return nil, refuse(http.StatusForbidden, &util.Errors.NotWorkspaceMember)
		}
		if !services.MemberCanReadRecords(recipient) {
			return nil, refuse(http.StatusForbidden, &util.Errors.MissingPermission)
		}
		chain := chains[g.User]
		if chain == nil {
			if chain, err = loadSealedChain(tx, g.User); err != nil {
				return nil, err
			}
			chains[g.User] = chain
		}
		signature, ok := decodeSealed(g.Signature)
		_, wrapOk := decodeSealed(g.Wrap)
		if !ok || !wrapOk || !chain.IsLive(g.DeviceSeq) || !granterChain.IsLive(g.SignerSeq) ||
			g.ChainSeq < 1 || g.ChainSeq > granterChain.HeadSeq() ||
			g.RecipientChainSeq < 1 || g.RecipientChainSeq > chain.HeadSeq() ||
			!util.VerifySealedSignature(granterChain.Entry(g.SignerSeq).SigningPublicKey,
				util.SealedGrantPayload(workspace, epoch, g.User, chain.Entry(g.DeviceSeq).HpkePublicKey,
					g.Wrap, granterID, g.ChainSeq, g.RecipientChainSeq),
				signature) {
			return nil, refuse(http.StatusBadRequest, &util.Errors.SealedInvalid)
		}
		existing, _ := tx.FindFirstRecordByFilter(util.Coll.WorkspaceKeyWraps,
			w.Workspace+" = {:w} && "+w.Epoch+" = {:e} && "+w.User+" = {:u} && "+w.DeviceSeq+" = {:d}",
			dbx.Params{"w": workspace, "e": epoch, "u": g.User, "d": g.DeviceSeq})
		if existing != nil {
			return nil, refuse(http.StatusConflict, &util.Errors.SealedVersionConflict)
		}
		row := core.NewRecord(collection)
		row.Set(w.Workspace, workspace)
		row.Set(w.Epoch, epoch)
		row.Set(w.User, g.User)
		row.Set(w.DeviceSeq, g.DeviceSeq)
		row.Set(w.Wrap, g.Wrap)
		row.Set(w.SignerSeq, g.SignerSeq)
		row.Set(w.ChainSeq, g.ChainSeq)
		row.Set(w.RecipientChainSeq, g.RecipientChainSeq)
		row.Set(w.Signature, g.Signature)
		row.Set(w.Granter, granterID)
		if err := tx.Save(row); err != nil {
			return nil, err
		}
		if !slices.Contains(granted, g.User) {
			granted = append(granted, g.User)
		}
	}
	return granted, nil
}

// grantSealedAccess hands the current workspace key to other members' devices.
// Only under a key nobody removed has: a due rotation comes first.
func grantSealedAccess(app core.App, re *core.RequestEvent) error {
	var body struct {
		Epoch  int           `json:"epoch"`
		Grants []sealedGrant `json:"grants"`
	}
	if err := re.BindBody(&body); err != nil || body.Epoch < 1 ||
		len(body.Grants) == 0 || len(body.Grants) > maxSealedWraps {
		return appErrorResponse(re, http.StatusBadRequest, &util.Errors.SealedInvalid)
	}
	workspace := re.Request.PathValue("id")
	userID := re.Auth.Id
	if _, member := util.WorkspaceMemberOf(app, workspace, userID); !member {
		return appErrorResponse(re, http.StatusNotFound, &util.Errors.WorkspaceNotFound)
	}

	var granted []string
	err := app.RunInTransaction(func(tx core.App) error {
		e := util.Fields.WorkspaceKeyEpoch
		current := services.CurrentKeyEpoch(tx, workspace)
		if current == nil || !services.HoldsWorkspaceKey(tx, workspace, userID, current.GetInt(e.Epoch)) {
			return refuse(http.StatusForbidden, &util.Errors.SealedKeyMissing)
		}
		if current.GetBool(e.RotationDue) || body.Epoch != current.GetInt(e.Epoch) {
			return refuse(http.StatusConflict, &util.Errors.SealedEpochStale)
		}
		chain, err := loadSealedChain(tx, userID)
		if err != nil {
			return err
		}
		granted, err = saveSealedGrants(tx, userID, workspace, body.Epoch, body.Grants, chain)
		return err
	})
	if err != nil {
		return writeSealedResult(re, err)
	}
	announceSealedGrants(app, re, workspace, granted, true)
	return re.JSON(http.StatusOK, map[string]any{"ok": true, "granted": granted})
}

// announceSealedGrants audits each grant and, with notify, tells its recipient,
// who should know whose word they now share a key on.
func announceSealedGrants(app core.App, re *core.RequestEvent, workspace string, granted []string, notify bool) {
	granter := re.Auth.GetString(util.Fields.User.Email)
	for _, recipient := range granted {
		services.RecordAudit(app, services.AuditEntry{
			Action:     util.AuditActionCreate,
			Collection: util.Coll.WorkspaceKeyWraps,
			RecordId:   recipient,
			Workspace:  workspace,
			User:       re.Auth.Id,
			Ip:         re.Request.RemoteAddr,
			UserAgent:  re.Request.UserAgent(),
		})
		if !notify {
			continue
		}
		services.EmitNotification(app, recipient, workspace, util.NotificationSealingAccessGranted,
			"You can read this workspace's encrypted records",
			granter+" gave your devices the key. Compare fingerprints with them under Settings → End-to-end encryption.",
			util.Coll.WorkspaceKeyWraps, workspace)
	}
}

// startSealedEpoch creates a workspace's first key, or replaces the current one.
//
// Only someone already holding the key may replace it. Otherwise any member could
// start an epoch only they hold, and everyone else's writes would then be refused
// as stale. Every one of the caller's live devices must receive it, recovery key
// included, or a bug here would quietly strand their recovery.
func startSealedEpoch(app core.App, re *core.RequestEvent) error {
	var body struct {
		Epoch     int           `json:"epoch"`
		PriorWrap string        `json:"priorWrap"`
		Wraps     []sealedWrap  `json:"wraps"`
		Grants    []sealedGrant `json:"grants"`
	}
	if err := re.BindBody(&body); err != nil || body.Epoch < 1 ||
		len(body.Wraps) == 0 || len(body.Wraps)+len(body.Grants) > maxSealedWraps {
		return appErrorResponse(re, http.StatusBadRequest, &util.Errors.SealedInvalid)
	}
	if _, ok := decodeSealed(body.PriorWrap); !ok {
		return appErrorResponse(re, http.StatusBadRequest, &util.Errors.SealedInvalid)
	}

	var granted []string
	workspace := re.Request.PathValue("id")
	userID := re.Auth.Id
	member, found := util.WorkspaceMemberOf(app, workspace, userID)
	if !found {
		return appErrorResponse(re, http.StatusNotFound, &util.Errors.WorkspaceNotFound)
	}

	e := util.Fields.WorkspaceKeyEpoch
	err := app.RunInTransaction(func(tx core.App) error {
		current := services.CurrentKeyEpoch(tx, workspace)
		if current == nil {
			permissions := member.GetStringSlice(util.Fields.WorkspaceMember.Permissions)
			if len(permissions) > 0 && !slices.Contains(permissions, util.ScopeRecordCreate) {
				return refuse(http.StatusForbidden, &util.Errors.MissingPermission)
			}
			if body.Epoch != 1 || body.PriorWrap != "" {
				return refuse(http.StatusConflict, &util.Errors.SealedVersionConflict)
			}
		} else {
			if !services.HoldsWorkspaceKey(tx, workspace, userID, current.GetInt(e.Epoch)) {
				return refuse(http.StatusForbidden, &util.Errors.SealedKeyMissing)
			}
			if body.Epoch != current.GetInt(e.Epoch)+1 {
				return refuse(http.StatusConflict, &util.Errors.SealedVersionConflict)
			}
			if body.PriorWrap == "" {
				return refuse(http.StatusBadRequest, &util.Errors.SealedInvalid)
			}
		}

		chain, err := loadSealedChain(tx, userID)
		if err != nil {
			return err
		}
		covered := map[int]bool{}
		for i := range body.Wraps {
			body.Wraps[i].Workspace = workspace
			body.Wraps[i].Epoch = body.Epoch
			covered[body.Wraps[i].DeviceSeq] = true
		}
		for _, seq := range chain.Live() {
			if !covered[seq] {
				return refuse(http.StatusBadRequest, &util.Errors.SealedInvalid)
			}
		}

		collection, err := tx.FindCollectionByNameOrId(util.Coll.WorkspaceKeyEpochs)
		if err != nil {
			return err
		}
		row := core.NewRecord(collection)
		row.Set(e.Workspace, workspace)
		row.Set(e.Epoch, body.Epoch)
		row.Set(e.PriorWrap, body.PriorWrap)
		row.Set(e.CreatedBy, userID)
		if err := tx.Save(row); err != nil {
			return err
		}
		if err := saveSealedWraps(tx, userID, body.Wraps, chain); err != nil {
			return err
		}
		// Other members' devices, each checked as in a grant. Anyone left out
		// goes back to waiting for access.
		granted, err = saveSealedGrants(tx, userID, workspace, body.Epoch, body.Grants, chain)
		return err
	})
	if err != nil {
		return writeSealedResult(re, err)
	}
	// A new key for people who already had the old one is no news to them.
	announceSealedGrants(app, re, workspace, granted, false)

	services.RecordAudit(app, services.AuditEntry{
		Action:     util.AuditActionCreate,
		Collection: util.Coll.WorkspaceKeyEpochs,
		RecordId:   workspace,
		Workspace:  workspace,
		User:       userID,
		Ip:         re.Request.RemoteAddr,
		UserAgent:  re.Request.UserAgent(),
	})
	return re.JSON(http.StatusOK, map[string]any{"ok": true, "epoch": body.Epoch})
}

// sealedBodyLimit lets an encrypted file through the sealed routes: the
// operator's file limit plus room for the blob's overhead and the rest of
// the form, or the size the app encrypts at most when there is no limit.
func sealedBodyLimit() int64 {
	const overhead = 1 << 20
	if max := util.FileLimitBytes(util.FileMaxSizeEnv); max >= 0 {
		return max + overhead
	}
	return 64<<20 + overhead
}

var errSealedBody = errors.New("not a sealed write")

// bindSealedBody reads a sealed write. JSON as before, or multipart for a
// file: the same JSON in `meta`, and the file in `blob`. An encrypted blob is
// stored under a fixed name, so nothing the client called it is kept; a plain
// file (`plain`, for Stop encrypting) keeps its name as any upload does.
func bindSealedBody(re *core.RequestEvent, dst any, plain bool) (*filesystem.File, error) {
	if !strings.HasPrefix(re.Request.Header.Get("Content-Type"), "multipart/form-data") {
		return nil, re.BindBody(dst)
	}
	if err := re.Request.ParseMultipartForm(32 << 20); err != nil {
		return nil, err
	}
	metas := re.Request.MultipartForm.Value["meta"]
	if len(metas) != 1 {
		return nil, errSealedBody
	}
	if err := json.Unmarshal([]byte(metas[0]), dst); err != nil {
		return nil, err
	}
	files, err := re.FindUploadedFiles("blob")
	if err != nil || len(files) != 1 {
		return nil, errSealedBody
	}
	blob := files[0]
	if !plain {
		suffix, err := util.GenerateToken(5)
		if err != nil {
			return nil, err
		}
		blob.OriginalName = util.SealedFileName
		blob.Name = "encrypted_" + suffix + ".bin"
	}
	return blob, nil
}

// sealedFileHash is what a device signs to stop encrypting a file, in place
// of the value it signs for anything else.
func sealedFileHash(file *filesystem.File) (string, error) {
	r, err := file.Reader.Open()
	if err != nil {
		return "", err
	}
	defer r.Close()
	h := sha256.New()
	if _, err := io.Copy(h, r); err != nil {
		return "", err
	}
	return "file:" + hex.EncodeToString(h.Sum(nil)), nil
}

// checkSealedWrite refuses a write under anything but the workspace's current
// key, and while a new one is due: that is what stops a value being written
// where a removed device or member can read it.
func checkSealedWrite(tx core.App, workspace, userID string, keyEpoch int) *sealedRefusal {
	e := util.Fields.WorkspaceKeyEpoch
	current := services.CurrentKeyEpoch(tx, workspace)
	if current == nil || !services.HoldsWorkspaceKey(tx, workspace, userID, current.GetInt(e.Epoch)) {
		return refuse(http.StatusForbidden, &util.Errors.SealedKeyMissing)
	}
	if current.GetBool(e.RotationDue) || keyEpoch != current.GetInt(e.Epoch) {
		return refuse(http.StatusConflict, &util.Errors.SealedEpochStale)
	}
	return nil
}

type sealedPayload struct {
	SealedValue string `json:"sealedValue"`
	KeyEpoch    int    `json:"keyEpoch"`
	KeyWrap     string `json:"keyWrap"`
}

func (p sealedPayload) valid() bool {
	_, valueOk := decodeSealed(p.SealedValue)
	_, wrapOk := decodeSealed(p.KeyWrap)
	return p.KeyEpoch >= 1 && p.SealedValue != "" && p.KeyWrap != "" && valueOk && wrapOk
}

// applySealed is the only code that puts a record into the sealed state.
func applySealed(rec *core.Record, p sealedPayload, version int) {
	f := util.Fields.Record
	rec.Set(f.Sealed, true)
	rec.Set(f.Value, "")
	rec.Set(f.SealedValue, p.SealedValue)
	rec.Set(f.SealedVersion, version)
	rec.Set(f.KeyEpoch, p.KeyEpoch)
	rec.Set(f.KeyWrap, p.KeyWrap)
}

// createSealedRecord takes the id from the client because the ciphertext is
// bound to it: the id has to exist before the value can be encrypted.
func createSealedRecord(app core.App, re *core.RequestEvent) error {
	var body struct {
		sealedPayload
		ID        string `json:"id"`
		Key       string `json:"key"`
		Label     string `json:"label"`
		Type      string `json:"type"`
		Format    string `json:"format"`
		Workspace string `json:"workspace"`
	}
	blob, err := bindSealedBody(re, &body, false)
	if err != nil || !body.valid() || !sealedRecordID.MatchString(body.ID) ||
		(body.Type == util.TypeFile) != (blob != nil) {
		return appErrorResponse(re, http.StatusBadRequest, &util.Errors.SealedInvalid)
	}

	spec, declared := util.AccessSpecFor(util.Coll.Records, util.ActionCreate)
	if !declared {
		return appErrorResponse(re, http.StatusForbidden, &util.Errors.NotAuthorized)
	}
	if errs := spec.Diagnose(app, util.AccessSubject{
		Auth:            re.Auth,
		RecordWorkspace: body.Workspace,
		RecordUser:      re.Auth.Id,
	}); len(errs) > 0 || body.Workspace == "" {
		return appErrorResponse(re, http.StatusForbidden, &util.Errors.NotAuthorized)
	}

	f := util.Fields.Record
	var saved *core.Record
	err = app.RunInTransaction(func(tx core.App) error {
		if refusal := checkSealedWrite(tx, body.Workspace, re.Auth.Id, body.KeyEpoch); refusal != nil {
			return refusal
		}
		collection, err := tx.FindCollectionByNameOrId(util.Coll.Records)
		if err != nil {
			return err
		}
		rec := core.NewRecord(collection)
		rec.Set("id", body.ID)
		rec.Set(f.Key, body.Key)
		rec.Set(f.Label, body.Label)
		rec.Set(f.Type, body.Type)
		rec.Set(f.Format, body.Format)
		rec.Set(f.User, re.Auth.Id)
		rec.Set(f.Workspace, body.Workspace)
		applySealed(rec, body.sealedPayload, 1)
		if blob != nil {
			rec.Set(f.File, blob)
		}
		if err := tx.Save(rec); err != nil {
			return err
		}
		saved = rec
		return nil
	})
	if err != nil {
		var refusal *sealedRefusal
		if errors.As(err, &refusal) {
			return writeSealedResult(re, err)
		}
		return re.BadRequestError("Failed to save.", err)
	}

	auditSealedRecord(app, re, util.AuditActionCreate, nil, saved)
	return re.JSON(http.StatusOK, saved)
}

// authorizeSealedUpdate applies the same declaration that guards a direct
// update. Refusals look like a missing record, as they do for other vault reads.
func authorizeSealedUpdate(app core.App, re *core.RequestEvent, rec *core.Record) bool {
	spec, declared := util.AccessSpecFor(util.Coll.Records, util.ActionUpdate)
	if !declared {
		return denyGate(re, http.StatusForbidden, &util.Errors.NotAuthorized)
	}
	errs := spec.Diagnose(app, util.AccessSubject{
		Auth:             re.Auth,
		RecordWorkspace:  rec.GetString(util.Fields.Record.Workspace),
		RecordUser:       rec.GetString(util.Fields.Record.User),
		RecordIsResponse: rec.GetString(util.Fields.Record.RequestedBy) != "",
		RecordEditors:    rec.GetStringSlice(util.Fields.Record.Editors),
	})
	if len(errs) > 0 {
		return denyGate(re, http.StatusNotFound, &util.Errors.RecordNotFound)
	}
	return true
}

// writeSealedRecord seals a plain record, or replaces a sealed one's value. The
// version only ever rises, across unsealing too, so a copy from before can't be
// passed off as current.
//
// The version is compared inside the transaction, and a write transaction holds
// the only write connection: of two devices saving at once, the second reads the
// first one's version and is refused rather than overwriting it unseen.
func writeSealedRecord(app core.App, re *core.RequestEvent) error {
	var body struct {
		sealedPayload
		ExpectedVersion int    `json:"expectedVersion"`
		DropLinks       bool   `json:"dropLinks"`
		CarryLinks      bool   `json:"carryLinks"`
		Key             string `json:"key"`
		Label           string `json:"label"`
		Type            string `json:"type"`
		Format          string `json:"format"`
		// LinkSeals renews, for the version this write makes, what each live
		// link carrying the record holds for it.
		LinkSeals []recordLinkSealInput `json:"linkSeals"`
	}
	blob, err := bindSealedBody(re, &body, false)
	if err != nil || !body.valid() || body.ExpectedVersion < 0 ||
		len(body.LinkSeals) > services.MaxLinkSealsPerRecord {
		return appErrorResponse(re, http.StatusBadRequest, &util.Errors.SealedInvalid)
	}

	id := re.Request.PathValue("id")
	first, err := app.FindRecordById(util.Coll.Records, id)
	if err != nil || first == nil {
		return appErrorResponse(re, http.StatusNotFound, &util.Errors.RecordNotFound)
	}
	if !authorizeSealedUpdate(app, re, first) {
		return nil
	}

	f := util.Fields.Record
	var saved *core.Record
	var before map[string]any
	var dropped []*core.Record
	err = app.RunInTransaction(func(tx core.App) error {
		rec, err := tx.FindRecordById(util.Coll.Records, id)
		if err != nil {
			return refuse(http.StatusNotFound, &util.Errors.RecordNotFound)
		}
		if rec.GetString(f.AliasOf) != "" {
			return refuse(http.StatusBadRequest, &util.Errors.SealedRecordUnsupported)
		}
		// A file keeps being a file, and nothing else gains one. Encrypting a
		// plain file replaces it: the plaintext must not stay behind the seal.
		isFile := rec.GetString(f.Type) == util.TypeFile
		if (blob != nil && !isFile) || (body.Type != "" && (body.Type == util.TypeFile) != isFile) ||
			(isFile && !services.IsSealed(rec) && blob == nil) {
			return refuse(http.StatusBadRequest, &util.Errors.SealedInvalid)
		}
		// The ciphertext is bound to the key the client saw. A rename racing this
		// write would otherwise leave a value nobody can open.
		if rec.GetInt(f.SealedVersion) != body.ExpectedVersion || rec.GetString(f.Key) != body.Key {
			return refuse(http.StatusConflict, &util.Errors.SealedVersionConflict)
		}
		if refusal := checkSealedWrite(tx, rec.GetString(f.Workspace), re.Auth.Id, body.KeyEpoch); refusal != nil {
			return refusal
		}
		if !services.IsSealed(rec) && !body.DropLinks && !body.CarryLinks {
			if links := services.LiveLinksReading(tx, id); links > 0 {
				refusal := refuse(http.StatusConflict, &util.Errors.SealedLinksAffected)
				refusal.extra = map[string]any{"links": links}
				return refusal
			}
		}
		before = rec.PublicExport()
		newlySealed := !services.IsSealed(rec)
		// While rec still reads as the version being replaced: its seals move
		// to the new one in this transaction, or the write does not happen.
		if refusal := renewLinkSeals(tx, rec, body.ExpectedVersion+1, body.LinkSeals); refusal != nil {
			return refusal
		}
		if newlySealed && body.CarryLinks {
			var failure *sealedRefusal
			dropped, failure = carryPlainRecord(tx, rec, re.Auth.Id, body.ExpectedVersion+1, body.LinkSeals, body.DropLinks)
			if failure != nil {
				return failure
			}
		} else if newlySealed {
			dropped = services.LinksReadingRecord(tx, rec.Id)
		}
		applySealed(rec, body.sealedPayload, body.ExpectedVersion+1)
		if blob != nil {
			rec.Set(f.File, blob)
		}
		// These travel inside the ciphertext too, which is what clients believe.
		// The copies here must land with it or the list shows yesterday's name.
		if body.Label != "" {
			rec.Set(f.Label, body.Label)
		}
		if body.Type != "" {
			rec.Set(f.Type, body.Type)
		}
		if body.Format != "" {
			rec.Set(f.Format, body.Format)
		}
		if err := tx.Save(rec); err != nil {
			return err
		}
		if newlySealed {
			if err := services.DetachSealedRecord(tx, id); err != nil {
				return err
			}
		}
		saved = rec
		return nil
	})
	if err != nil {
		var refusal *sealedRefusal
		if errors.As(err, &refusal) {
			return writeSealedResult(re, err)
		}
		return re.BadRequestError("Failed to save.", err)
	}

	for _, link := range dropped {
		owner := link.GetString(util.FieldUser)
		if owner == re.Auth.Id {
			continue
		}
		services.EmitNotification(app, owner, saved.GetString(f.Workspace), util.NotificationSealedLinkChanged,
			"An entry on this link was encrypted",
			"An entry was encrypted and is no longer shown on this link. It can be added again from a device that can read it.",
			util.Coll.Links, link.Id)
	}
	auditSealedRecord(app, re, util.AuditActionUpdate, before, saved)
	return re.JSON(http.StatusOK, saved)
}

// unsealRecord writes a value back in plaintext, at the owner's explicit
// request. Its version check stops a stale device undoing a newer value. It must
// be signed by a device on the list: a row saying someone holds the key proves
// nothing, and a stolen session could otherwise replace the ciphertext with
// whatever it likes.
func unsealRecord(app core.App, re *core.RequestEvent) error {
	var body struct {
		ExpectedVersion int    `json:"expectedVersion"`
		Value           string `json:"value"`
		DeviceSeq       int    `json:"deviceSeq"`
		Signature       string `json:"signature"`
		// For a file: the name it is stored under again.
		Filename string `json:"filename"`
	}
	// A file comes back as the plain file, and its device signs the file's
	// hash where it would sign a value.
	upload, err := bindSealedBody(re, &body, true)
	if err != nil || body.ExpectedVersion < 1 || len([]rune(body.Value)) > util.MaxRecordValueLength ||
		(upload == nil) == (body.Value == "") {
		return appErrorResponse(re, http.StatusBadRequest, &util.Errors.SealedInvalid)
	}
	signed := body.Value
	if upload != nil {
		if signed, err = sealedFileHash(upload); err != nil {
			return appErrorResponse(re, http.StatusBadRequest, &util.Errors.SealedInvalid)
		}
	}

	id := re.Request.PathValue("id")
	first, err := app.FindRecordById(util.Coll.Records, id)
	if err != nil || first == nil {
		return appErrorResponse(re, http.StatusNotFound, &util.Errors.RecordNotFound)
	}
	if !authorizeSealedUpdate(app, re, first) {
		return nil
	}

	f := util.Fields.Record
	var saved *core.Record
	var before map[string]any
	err = app.RunInTransaction(func(tx core.App) error {
		rec, err := tx.FindRecordById(util.Coll.Records, id)
		if err != nil {
			return refuse(http.StatusNotFound, &util.Errors.RecordNotFound)
		}
		if !services.IsSealed(rec) || rec.GetInt(f.SealedVersion) != body.ExpectedVersion {
			return refuse(http.StatusConflict, &util.Errors.SealedVersionConflict)
		}
		if (rec.GetString(f.Type) == util.TypeFile) != (upload != nil) {
			return refuse(http.StatusBadRequest, &util.Errors.SealedInvalid)
		}
		e := util.Fields.WorkspaceKeyEpoch
		current := services.CurrentKeyEpoch(tx, rec.GetString(f.Workspace))
		if current == nil || !services.HoldsWorkspaceKey(tx, rec.GetString(f.Workspace), re.Auth.Id, current.GetInt(e.Epoch)) {
			return refuse(http.StatusForbidden, &util.Errors.SealedKeyMissing)
		}
		chain, err := loadSealedChain(tx, re.Auth.Id)
		if err != nil {
			return err
		}
		signature, ok := decodeSealed(body.Signature)
		if !ok || !chain.IsLive(body.DeviceSeq) ||
			!util.VerifySealedSignature(chain.Entry(body.DeviceSeq).SigningPublicKey,
				util.SealedUnsealPayload(re.Auth.Id, id, body.ExpectedVersion, signed), signature) {
			return refuse(http.StatusForbidden, &util.Errors.SealedKeyMissing)
		}
		before = rec.PublicExport()
		rec.Set(f.Sealed, false)
		rec.Set(f.Value, body.Value)
		rec.Set(f.SealedValue, "")
		rec.Set(f.SealedVersion, body.ExpectedVersion+1)
		rec.Set(f.KeyEpoch, 0)
		rec.Set(f.KeyWrap, "")
		if upload != nil {
			rec.Set(f.File, upload)
			rec.Set(f.Filename, body.Filename)
		}
		if err := tx.Save(rec); err != nil {
			return err
		}
		// Its links serve the plain value from here on.
		if err := services.DeleteLinkSealsOfRecord(tx, id); err != nil {
			return err
		}
		saved = rec
		return nil
	})
	if err != nil {
		var refusal *sealedRefusal
		if errors.As(err, &refusal) {
			return writeSealedResult(re, err)
		}
		return re.BadRequestError("Failed to save.", err)
	}

	auditSealedRecord(app, re, util.AuditActionUpdate, before, saved)
	return re.JSON(http.StatusOK, saved)
}

// resetSealing is for someone who lost every device and their recovery key. It
// clears their device list and copies of keys, and deletes the encrypted records
// in any workspace where nobody else holds the key, since nobody can ever read
// them again. A dishonest server could do this without asking, so a device that
// knew the old list treats the new one as untrusted (E2EE.md §4.3).
func resetSealing(app core.App, re *core.RequestEvent) error {
	var body struct {
		Confirm string `json:"confirm"`
	}
	if err := re.BindBody(&body); err != nil || body.Confirm != sealedResetConfirmation {
		return appErrorResponse(re, http.StatusBadRequest, &util.Errors.SealedInvalid)
	}

	userID := re.Auth.Id
	w := util.Fields.WorkspaceKeyWrap
	d := util.Fields.DeviceKey
	e := util.Fields.WorkspaceKeyEpoch
	f := util.Fields.Record
	deleted := 0
	err := app.RunInTransaction(func(tx core.App) error {
		wraps, err := tx.FindRecordsByFilter(util.Coll.WorkspaceKeyWraps,
			w.User+" = {:u}", "", 0, 0, dbx.Params{"u": userID})
		if err != nil {
			return err
		}
		workspaces := map[string]bool{}
		for _, row := range wraps {
			workspaces[row.GetString(w.Workspace)] = true
			if err := tx.Delete(row); err != nil {
				return err
			}
		}
		devices, err := tx.FindRecordsByFilter(util.Coll.DeviceKeys,
			d.User+" = {:u}", "", 0, 0, dbx.Params{"u": userID})
		if err != nil {
			return err
		}
		for _, row := range devices {
			if err := tx.Delete(row); err != nil {
				return err
			}
		}
		if err := resetAccountKey(tx, userID); err != nil {
			return err
		}
		for workspace := range workspaces {
			others, _ := tx.FindFirstRecordByFilter(util.Coll.WorkspaceKeyWraps,
				w.Workspace+" = {:w}", dbx.Params{"w": workspace})
			if others != nil {
				// Their old devices still hold the key.
				if err := services.MarkKeyRotationDue(tx, workspace); err != nil {
					return err
				}
				continue
			}
			sealed, err := tx.FindRecordsByFilter(util.Coll.Records,
				f.Workspace+" = {:w} && "+f.Sealed+" = true", "", 0, 0, dbx.Params{"w": workspace})
			if err != nil {
				return err
			}
			for _, rec := range sealed {
				if err := tx.Delete(rec); err != nil {
					return err
				}
				deleted++
			}
			epochs, err := tx.FindRecordsByFilter(util.Coll.WorkspaceKeyEpochs,
				e.Workspace+" = {:w}", "", 0, 0, dbx.Params{"w": workspace})
			if err != nil {
				return err
			}
			for _, row := range epochs {
				if err := tx.Delete(row); err != nil {
					return err
				}
			}
		}
		return nil
	})
	if err != nil {
		return writeSealedResult(re, err)
	}

	services.RecordAudit(app, services.AuditEntry{
		Action:     util.AuditActionDelete,
		Collection: util.Coll.DeviceKeys,
		RecordId:   userID,
		User:       userID,
		Ip:         re.Request.RemoteAddr,
		UserAgent:  re.Request.UserAgent(),
	})
	services.NotifySealingReset(app, userID, re.Auth.GetString(util.Fields.User.ActiveWorkspace))
	return re.JSON(http.StatusOK, map[string]any{"ok": true, "deleted": deleted})
}

// resetAccountKey deletes a person's account key and the identity keys under it.
// Nobody can open them any more; a device still holding an identity's private
// key uploads it again under the new account key.
func resetAccountKey(tx core.App, userID string) error {
	for _, name := range []string{util.Coll.AccountKeyWraps, util.Coll.AccountKeyEpochs} {
		rows, err := tx.FindRecordsByFilter(name, "user = {:u}", "", 0, 0, dbx.Params{"u": userID})
		if err != nil {
			return err
		}
		for _, row := range rows {
			if err := tx.Delete(row); err != nil {
				return err
			}
		}
	}
	i := util.Fields.Identity
	identities, err := tx.FindRecordsByFilter(util.Coll.Identities,
		i.User+" = {:u} && "+i.SealedKey+" != ''", "", 0, 0, dbx.Params{"u": userID})
	if err != nil {
		return err
	}
	for _, row := range identities {
		row.Set(i.SealedKey, "")
		row.Set(i.SealedKeyEpoch, 0)
		row.Set(i.SealedKeyScope, "")
		if err := tx.Save(row); err != nil {
			return err
		}
	}
	return nil
}

// revokeOtherSessions ends every session this account has, and hands the caller a
// new one. A stolen device's session outlives its removal from the device list
// otherwise, and can go on reading plain records and deleting sealed ones.
func revokeOtherSessions(app core.App, re *core.RequestEvent) error {
	user, err := app.FindRecordById(util.Coll.Users, re.Auth.Id)
	if err != nil {
		return appErrorResponse(re, http.StatusNotFound, &util.Errors.UserNotFound)
	}
	user.RefreshTokenKey()
	if err := app.Save(user); err != nil {
		return re.InternalServerError("Failed to end sessions.", err)
	}
	token, err := user.NewAuthToken()
	if err != nil {
		return re.InternalServerError("Failed to start a new session.", err)
	}
	services.RecordAudit(app, services.AuditEntry{
		Action:     util.AuditActionUpdate,
		Collection: util.Coll.Users,
		RecordId:   user.Id,
		User:       user.Id,
		Ip:         re.Request.RemoteAddr,
		UserAgent:  re.Request.UserAgent(),
	})
	return re.JSON(http.StatusOK, map[string]any{"token": token})
}

// auditSealedRecord records a write these routes made with app.Save, which
// passes no request hook and so would otherwise leave no audit row.
func auditSealedRecord(app core.App, re *core.RequestEvent, action string, before map[string]any, rec *core.Record) {
	services.RecordAudit(app, services.AuditEntry{
		Action:     action,
		Collection: util.Coll.Records,
		RecordId:   rec.Id,
		Workspace:  rec.GetString(util.Fields.Record.Workspace),
		User:       re.Auth.Id,
		Ip:         re.Request.RemoteAddr,
		UserAgent:  re.Request.UserAgent(),
		OldData:    before,
		NewData:    rec.PublicExport(),
	})
}
