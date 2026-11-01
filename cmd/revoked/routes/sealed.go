package routes

import (
	"errors"
	"net/http"
	"regexp"
	"slices"

	"revoked/cmd/revoked/services"
	"revoked/util"

	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/core"
)

const (
	maxSealedEntries = 8
	maxSealedWraps   = 500
	// sealedResetConfirmation must be sent to start over: it destroys data
	// nobody can recover, so a stray or replayed call must not be enough.
	sealedResetConfirmation = "delete my encrypted records"
)

var (
	sealedEncoded  = regexp.MustCompile(`^[A-Za-z0-9_-]+={0,2}$`)
	sealedRecordID = regexp.MustCompile(`^[a-z0-9]{15}$`)
)

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

// SealedRoute serves end-to-end encrypted records. The server never decrypts or
// verifies anything here: it stores opaque bytes, and each client checks the
// device list and wraps for itself (E2EE.md §4). What it does enforce is the
// honest-server behaviour a client cannot do alone: versions move one at a
// time, a record and its key land together, and nothing is written under a
// key someone was removed from.
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
		e.Router.POST("/api/sealed/records", func(re *core.RequestEvent) error {
			if !authorizeSealed(re) {
				return nil
			}
			return createSealedRecord(app, re)
		})
		e.Router.PUT("/api/sealed/records/{id}", func(re *core.RequestEvent) error {
			if !authorizeSealed(re) {
				return nil
			}
			return writeSealedRecord(app, re)
		})
		e.Router.POST("/api/sealed/records/{id}/unseal", func(re *core.RequestEvent) error {
			if !authorizeSealed(re) {
				return nil
			}
			return unsealRecord(app, re)
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
	HpkePublicKey    string `json:"hpkePublicKey"`
	SigningPublicKey string `json:"signingPublicKey"`
	TargetSeq        int    `json:"targetSeq"`
	PreviousHash     string `json:"previousHash"`
	SignerSeq        int    `json:"signerSeq"`
	AnchorSignature  string `json:"anchorSignature"`
	Signature        string `json:"signature"`
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

func sealedState(app core.App, re *core.RequestEvent) error {
	d := util.Fields.DeviceKey
	rows, err := app.FindRecordsByFilter(util.Coll.DeviceKeys,
		d.User+" = {:u}", d.Seq, 0, 0, dbx.Params{"u": re.Auth.Id})
	if err != nil {
		return re.InternalServerError("Failed to read devices.", err)
	}
	devices := make([]map[string]any, 0, len(rows))
	for _, row := range rows {
		devices = append(devices, map[string]any{
			"user":             row.GetString(d.User),
			"seq":              row.GetInt(d.Seq),
			"action":           row.GetString(d.Action),
			"kind":             row.GetString(d.Kind),
			"label":            row.GetString(d.Label),
			"hpkePublicKey":    row.GetString(d.HpkePublicKey),
			"signingPublicKey": row.GetString(d.SigningPublicKey),
			"targetSeq":        row.GetInt(d.TargetSeq),
			"previousHash":     row.GetString(d.PreviousHash),
			"signerSeq":        row.GetInt(d.SignerSeq),
			"anchorSignature":  row.GetString(d.AnchorSignature),
			"signature":        row.GetString(d.Signature),
		})
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
				"epoch":     row.GetInt(w.Epoch),
				"deviceSeq": row.GetInt(w.DeviceSeq),
				"wrap":      row.GetString(w.Wrap),
				"signerSeq": row.GetInt(w.SignerSeq),
				"chainSeq":  row.GetInt(w.ChainSeq),
				"signature": row.GetString(w.Signature),
			})
		}
		workspaces = append(workspaces, map[string]any{
			"workspace": workspace,
			"epochs":    epochs,
			"wraps":     wraps,
		})
	}

	return re.JSON(http.StatusOK, map[string]any{
		"devices":    devices,
		"workspaces": workspaces,
	})
}

func validSealedEntry(entry sealedEntry) bool {
	if entry.Seq < 1 || entry.SignerSeq < 1 || !sealedEncoded.MatchString(entry.Signature) ||
		len(entry.Label) > 255 {
		return false
	}
	if entry.PreviousHash != "" && !sealedEncoded.MatchString(entry.PreviousHash) {
		return false
	}
	switch entry.Action {
	case util.SealedActionAdd:
		return (entry.Kind == util.SealedKindDevice || entry.Kind == util.SealedKindRecovery) &&
			entry.TargetSeq == 0 &&
			sealedEncoded.MatchString(entry.HpkePublicKey) &&
			sealedEncoded.MatchString(entry.SigningPublicKey)
	case util.SealedActionRemove:
		return entry.TargetSeq >= 1
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
		existing, err := tx.FindRecordsByFilter(util.Coll.DeviceKeys,
			d.User+" = {:u}", d.Seq, 0, 0, dbx.Params{"u": userID})
		if err != nil {
			return err
		}
		live := map[int]bool{}
		next := 1
		for _, row := range existing {
			seq := row.GetInt(d.Seq)
			if row.GetString(d.Action) == util.SealedActionAdd {
				live[seq] = true
			} else {
				delete(live, row.GetInt(d.TargetSeq))
			}
			next = seq + 1
		}

		for _, entry := range body.Entries {
			if entry.Seq != next {
				return refuse(http.StatusConflict, &util.Errors.SealedVersionConflict)
			}
			next++
			row := core.NewRecord(collection)
			row.Set(d.User, userID)
			row.Set(d.Seq, entry.Seq)
			row.Set(d.Action, entry.Action)
			row.Set(d.Kind, entry.Kind)
			row.Set(d.Label, entry.Label)
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
			if entry.Action == util.SealedActionAdd {
				live[entry.Seq] = true
				continue
			}
			if !live[entry.TargetSeq] {
				return refuse(http.StatusBadRequest, &util.Errors.SealedInvalid)
			}
			delete(live, entry.TargetSeq)
			if err := withdrawDeviceWraps(tx, userID, entry.TargetSeq); err != nil {
				return err
			}
		}

		return saveSealedWraps(tx, userID, body.Wraps, live)
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
	return nil
}

// saveSealedWraps stores keys handed to the caller's own live devices. Phase 1
// has no way to hand a key to another person, so naming anyone else's device
// is not a path that exists.
func saveSealedWraps(tx core.App, userID string, wraps []sealedWrap, live map[int]bool) error {
	if len(wraps) == 0 {
		return nil
	}
	collection, err := tx.FindCollectionByNameOrId(util.Coll.WorkspaceKeyWraps)
	if err != nil {
		return err
	}
	w := util.Fields.WorkspaceKeyWrap
	e := util.Fields.WorkspaceKeyEpoch
	for _, wrap := range wraps {
		if !live[wrap.DeviceSeq] || wrap.ChainSeq < 1 ||
			!sealedEncoded.MatchString(wrap.Wrap) ||
			!sealedEncoded.MatchString(wrap.Signature) {
			return refuse(http.StatusBadRequest, &util.Errors.SealedInvalid)
		}
		if _, member := util.WorkspaceMemberOf(tx, wrap.Workspace, userID); !member {
			return refuse(http.StatusForbidden, &util.Errors.NotWorkspaceMember)
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

func liveDeviceSeqs(tx core.App, userID string) (map[int]bool, error) {
	d := util.Fields.DeviceKey
	rows, err := tx.FindRecordsByFilter(util.Coll.DeviceKeys,
		d.User+" = {:u}", d.Seq, 0, 0, dbx.Params{"u": userID})
	if err != nil {
		return nil, err
	}
	live := map[int]bool{}
	for _, row := range rows {
		if row.GetString(d.Action) == util.SealedActionAdd {
			live[row.GetInt(d.Seq)] = true
		} else {
			delete(live, row.GetInt(d.TargetSeq))
		}
	}
	return live, nil
}

// startSealedEpoch creates a workspace's first key, or replaces the current one.
//
// Only someone already holding the key may replace it. Otherwise any member could
// start an epoch only they hold, and everyone else's writes would then be refused
// as stale. Every one of the caller's live devices must receive it, recovery key
// included, or a bug here would quietly strand their recovery.
func startSealedEpoch(app core.App, re *core.RequestEvent) error {
	var body struct {
		Epoch     int          `json:"epoch"`
		PriorWrap string       `json:"priorWrap"`
		Wraps     []sealedWrap `json:"wraps"`
	}
	if err := re.BindBody(&body); err != nil || body.Epoch < 1 ||
		len(body.Wraps) == 0 || len(body.Wraps) > maxSealedWraps {
		return appErrorResponse(re, http.StatusBadRequest, &util.Errors.SealedInvalid)
	}
	if body.PriorWrap != "" && !sealedEncoded.MatchString(body.PriorWrap) {
		return appErrorResponse(re, http.StatusBadRequest, &util.Errors.SealedInvalid)
	}

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

		live, err := liveDeviceSeqs(tx, userID)
		if err != nil {
			return err
		}
		covered := map[int]bool{}
		for i := range body.Wraps {
			body.Wraps[i].Workspace = workspace
			body.Wraps[i].Epoch = body.Epoch
			covered[body.Wraps[i].DeviceSeq] = true
		}
		for seq := range live {
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
		return saveSealedWraps(tx, userID, body.Wraps, live)
	})
	if err != nil {
		return writeSealedResult(re, err)
	}

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
	return p.KeyEpoch >= 1 && sealedEncoded.MatchString(p.SealedValue) && sealedEncoded.MatchString(p.KeyWrap)
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
	if err := re.BindBody(&body); err != nil || !body.valid() || !sealedRecordID.MatchString(body.ID) {
		return appErrorResponse(re, http.StatusBadRequest, &util.Errors.SealedInvalid)
	}
	if body.Type == util.TypeFile {
		return appErrorResponse(re, http.StatusBadRequest, &util.Errors.SealedRecordUnsupported)
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
	err := app.RunInTransaction(func(tx core.App) error {
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
		ExpectedVersion int  `json:"expectedVersion"`
		DropLinks       bool `json:"dropLinks"`
	}
	if err := re.BindBody(&body); err != nil || !body.valid() || body.ExpectedVersion < 0 {
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
	err = app.RunInTransaction(func(tx core.App) error {
		rec, err := tx.FindRecordById(util.Coll.Records, id)
		if err != nil {
			return refuse(http.StatusNotFound, &util.Errors.RecordNotFound)
		}
		if rec.GetString(f.Type) == util.TypeFile || rec.GetString(f.AliasOf) != "" {
			return refuse(http.StatusBadRequest, &util.Errors.SealedRecordUnsupported)
		}
		if rec.GetInt(f.SealedVersion) != body.ExpectedVersion {
			return refuse(http.StatusConflict, &util.Errors.SealedVersionConflict)
		}
		if refusal := checkSealedWrite(tx, rec.GetString(f.Workspace), re.Auth.Id, body.KeyEpoch); refusal != nil {
			return refusal
		}
		if !services.IsSealed(rec) && !body.DropLinks {
			if links := services.LiveLinksReading(tx, id); links > 0 {
				refusal := refuse(http.StatusConflict, &util.Errors.SealedLinksAffected)
				refusal.extra = map[string]any{"links": links}
				return refusal
			}
		}
		before = rec.PublicExport()
		newlySealed := !services.IsSealed(rec)
		applySealed(rec, body.sealedPayload, body.ExpectedVersion+1)
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

	auditSealedRecord(app, re, util.AuditActionUpdate, before, saved)
	return re.JSON(http.StatusOK, saved)
}

// unsealRecord writes a value back in plaintext, at the owner's explicit
// request. Its version check stops a stale device undoing a newer value, and
// holding the key is required so that anyone else with update access, or a stolen
// session, can't replace the ciphertext with whatever they like.
func unsealRecord(app core.App, re *core.RequestEvent) error {
	var body struct {
		ExpectedVersion int    `json:"expectedVersion"`
		Value           string `json:"value"`
	}
	if err := re.BindBody(&body); err != nil || body.ExpectedVersion < 1 ||
		body.Value == "" || len([]rune(body.Value)) > util.MaxRecordValueLength {
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
	err = app.RunInTransaction(func(tx core.App) error {
		rec, err := tx.FindRecordById(util.Coll.Records, id)
		if err != nil {
			return refuse(http.StatusNotFound, &util.Errors.RecordNotFound)
		}
		if !services.IsSealed(rec) || rec.GetInt(f.SealedVersion) != body.ExpectedVersion {
			return refuse(http.StatusConflict, &util.Errors.SealedVersionConflict)
		}
		e := util.Fields.WorkspaceKeyEpoch
		current := services.CurrentKeyEpoch(tx, rec.GetString(f.Workspace))
		if current == nil || !services.HoldsWorkspaceKey(tx, rec.GetString(f.Workspace), re.Auth.Id, current.GetInt(e.Epoch)) {
			return refuse(http.StatusForbidden, &util.Errors.SealedKeyMissing)
		}
		before = rec.PublicExport()
		rec.Set(f.Sealed, false)
		rec.Set(f.Value, body.Value)
		rec.Set(f.SealedValue, "")
		rec.Set(f.SealedVersion, body.ExpectedVersion+1)
		rec.Set(f.KeyEpoch, 0)
		rec.Set(f.KeyWrap, "")
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
