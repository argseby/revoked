package routes

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/url"
	"regexp"
	"strconv"
	"strings"
	"time"

	"revoked/cmd/revoked/server"
	"revoked/cmd/revoked/services"
	"revoked/util"

	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/core"
)

// maxGrantEventsPerBatch bounds one inbound event batch.
const maxGrantEventsPerBatch = 1000

var requestSlugPattern = regexp.MustCompile(util.SlugPattern)

// RemoteGrantsRoute exposes the four endpoints that let an answer live on the
// responder's server while the requester's server reads it:
//
//	POST /api/requests/remote               responder's app → responder's server
//	POST /api/public/requests/{slug}/remote responder's server → requester's server
//	POST /api/grants/resolve                requester's server → responder's server
//	POST /api/grants/events                 responder's server → requester's server
//
// The answer's values never leave the responder's server except as the answer
// to a read made with the grant's token, and every outbound call goes through
// the SSRF-safe client: each target is named by someone else.
func RemoteGrantsRoute(app core.App, root *server.RootKey) {
	app.OnServe().BindFunc(func(e *core.ServeEvent) error {
		e.Router.POST("/api/requests/remote", func(re *core.RequestEvent) error {
			return relayRemoteAnswer(app, root, re)
		})
		e.Router.POST("/api/public/requests/{slug}/remote", func(re *core.RequestEvent) error {
			return acceptRemoteAnswer(app, root, re)
		})
		e.Router.POST("/api/grants/resolve", func(re *core.RequestEvent) error {
			return resolveGrantBatch(app, re)
		})
		e.Router.POST("/api/grants/events", func(re *core.RequestEvent) error {
			return receiveGrantEvents(app, root, re)
		})
		return e.Next()
	})
}

// remoteIdentity is the public half of a responder's identity, relayed by the
// server that issued it so the requester's server can walk its chain.
type remoteIdentity struct {
	ID              string `json:"id"`
	Name            string `json:"name"`
	Fingerprint     string `json:"fingerprint"`
	Certificate     string `json:"certificate"`
	ParentSignature string `json:"parentSignature"`
	DomainAtIssue   string `json:"domainAtIssue"`
}

// remoteAnswer is what the responder's server sends the requester's server.
type remoteAnswer struct {
	Server             string          `json:"server"`
	Grant              remoteGrantRef  `json:"grant"`
	Password           string          `json:"password,omitempty"`
	Identifier         string          `json:"identifier,omitempty"`
	SenderName         string          `json:"senderName,omitempty"`
	Identity           *remoteIdentity `json:"identity,omitempty"`
	ChallengeNonce     string          `json:"challengeNonce,omitempty"`
	ChallengeSignature string          `json:"challengeSignature,omitempty"`
}

type remoteGrantRef struct {
	ID    string `json:"id"`
	Token string `json:"token"`
}

// remoteProbe is the part of another server's request probe the relay uses.
type remoteProbe struct {
	Label            string `json:"label"`
	RequireHandshake bool   `json:"requireHandshake"`
	AllowExtraFields bool   `json:"allowExtraFields"`
	Requester        struct {
		Name string `json:"name"`
	} `json:"requester"`
	Template struct {
		Records  []publicTemplateItem `json:"records"`
		Sections []publicTemplateItem `json:"sections"`
	} `json:"template"`
	Server struct {
		Domain string `json:"domain"`
	} `json:"server"`
}

// peerError is another server's refusal, passed on with its own code.
type peerError struct {
	status  int
	code    string
	message string
}

// relayRemoteAnswer answers a request on another server for a person signed
// in here. The answer becomes entries in their own vault and a link they own,
// exactly as for a request on this server; the other server receives the
// link's id and a token to read it with, and nothing else.
//
// The other server is asked twice: first for its probe, so the answer can be
// checked against the template before anything is written, and then with the
// grant. If it refuses the grant, everything written for it is taken back.
func relayRemoteAnswer(app core.App, root *server.RootKey, re *core.RequestEvent) error {
	if re.Auth == nil || re.Auth.Collection().Name != util.Coll.Users {
		return appErrorResponse(re, http.StatusUnauthorized, &util.Errors.NotAuthenticated)
	}
	// Each answer makes this server call one the caller named, so it is
	// budgeted per account like any other outbound call on someone's behalf.
	if !allowRequest(re, grantPeerLimiter, "relay|"+re.Auth.Id) {
		return rateLimitedResponse(re)
	}
	var body struct {
		Origin             string            `json:"origin"`
		Slug               string            `json:"slug"`
		Password           string            `json:"password"`
		Identifier         string            `json:"identifier"`
		IdentityId         string            `json:"identityId"`
		ChallengeNonce     string            `json:"challengeNonce"`
		ChallengeSignature string            `json:"challengeSignature"`
		SenderName         string            `json:"senderName"`
		Data               map[string]any    `json:"data"`
		Mappings           map[string]string `json:"mappings"`
	}
	_ = re.BindBody(&body)
	if body.Data == nil {
		body.Data = map[string]any{}
	}

	domain, base, ok := util.PeerDomainForOrigin(body.Origin)
	if !ok {
		return appErrorResponse(re, http.StatusBadRequest, &util.Errors.RemoteOriginInvalid)
	}
	if !requestSlugPattern.MatchString(body.Slug) {
		return appErrorResponse(re, http.StatusNotFound, &util.Errors.RequestNotFound)
	}
	slugPath := "/api/public/requests/" + url.PathEscape(body.Slug)

	var probe remoteProbe
	if perr, err := peerJSON(http.MethodGet, base+slugPath, nil, &probe); err != nil {
		return appErrorResponse(re, http.StatusBadGateway, &util.Errors.RemoteUnreachable)
	} else if perr != nil {
		return peerErrorResponse(re, perr)
	}
	if !strings.EqualFold(probe.Server.Domain, domain) {
		return appErrorResponse(re, http.StatusBadGateway, &util.Errors.RemoteServerMismatch)
	}

	var identity *remoteIdentity
	if body.IdentityId != "" {
		idRec, err := app.FindRecordById(util.Coll.Identities, body.IdentityId)
		if err != nil || idRec == nil || idRec.GetString(util.Fields.Identity.User) != re.Auth.Id {
			return appErrorResponse(re, http.StatusForbidden, &util.Errors.IdentityNotOwned)
		}
		if !services.IdentityIsActive(idRec) {
			return appErrorResponse(re, http.StatusForbidden, &util.Errors.IdentityRevoked)
		}
		identity = &remoteIdentity{
			ID:              idRec.Id,
			Name:            idRec.GetString(util.Fields.Identity.Name),
			Fingerprint:     idRec.GetString(util.Fields.Identity.Fingerprint),
			Certificate:     idRec.GetString(util.Fields.Identity.Certificate),
			ParentSignature: idRec.GetString(util.Fields.Identity.ParentSignature),
			DomainAtIssue:   idRec.GetString(util.Fields.Identity.DomainAtIssue),
		}
	}

	requesterName := probe.Requester.Name
	if requesterName == "" {
		requesterName = probe.Label
	}
	if requesterName == "" {
		requesterName = body.Slug
	}
	requestedBy := requesterName + " (" + domain + ")"
	label := probe.Label
	if label == "" {
		label = body.Slug
	}

	mappedGrants := map[string]string{}
	var aliasIds []string
	if len(body.Mappings) > 0 {
		resolved, ids, err := resolveResponseMappings(app, re.Auth, body.Mappings, body.Data, requestedBy)
		if err != nil {
			return err
		}
		mappedGrants, aliasIds = resolved, ids
	}

	// Checked here against the other server's published template, so a plain
	// mistake costs nothing; the other server checks again, on the values it
	// reads, and its word is final.
	templateKeys := templateKeysFrom(probe.Template.Records, probe.Template.Sections)
	if appErr := validateSubmissionData(body.Data, templateKeys, probe.AllowExtraFields); appErr != nil {
		deleteRecords(app, aliasIds)
		return appErrorResponse(re, http.StatusBadRequest, appErr)
	}

	grantMap, created := createGrantRecords(app, re.Auth, grantTarget{
		sectionKey:  sanitizeKey("req_" + domain + "_" + body.Slug),
		sectionName: label,
		requestedBy: requestedBy,
	}, body.Data, mappedGrants, aliasIds)

	undoVault := func() {
		deleteRecords(app, created.records)
		deleteRecords(app, aliasIds)
		if created.section != "" {
			if sec, err := app.FindRecordById(util.Coll.Sections, created.section); err == nil {
				_ = app.Delete(sec)
			}
		}
	}

	token, err := util.GenerateToken(32)
	if err != nil {
		undoVault()
		return re.InternalServerError("Failed to record response", nil)
	}

	link, before, err := saveRemoteLink(app, re.Auth, domain, body.Slug, label, body.SenderName,
		body.Identifier, identity != nil && probe.RequireHandshake, body.IdentityId, body.Data, grantMap, token)
	if err != nil {
		app.Logger().Error("Failed to record remote response", "error", err)
		undoVault()
		return re.InternalServerError("Failed to record response", nil)
	}
	undo := func() {
		undoRemoteLink(app, link, before)
		undoVault()
	}

	answer := remoteAnswer{
		Server:             root.Domain(),
		Grant:              remoteGrantRef{ID: link.Id, Token: token},
		Password:           body.Password,
		Identifier:         body.Identifier,
		SenderName:         body.SenderName,
		Identity:           identity,
		ChallengeNonce:     body.ChallengeNonce,
		ChallengeSignature: body.ChallengeSignature,
	}
	var accepted struct {
		ResponseID string `json:"responseId"`
		Completed  bool   `json:"completed"`
		Updated    bool   `json:"updated"`
	}
	perr, err := peerJSON(http.MethodPost, base+slugPath+"/remote", answer, &accepted)
	if err != nil {
		undo()
		return appErrorResponse(re, http.StatusBadGateway, &util.Errors.RemoteUnreachable)
	}
	if perr != nil {
		undo()
		return peerErrorResponse(re, perr)
	}

	return re.JSON(http.StatusOK, map[string]any{
		"ok":         true,
		"linkId":     link.Id,
		"responseId": accepted.ResponseID,
		"server":     domain,
		"completed":  accepted.Completed,
		"updated":    before != nil || accepted.Updated,
	})
}

// remoteLinkState is what a re-answer overwrites, kept to restore it if the
// other server refuses the new answer.
type remoteLinkState struct {
	label, senderName, identifier, identity, tokenHash string
	data, grants                                       any
	records                                            []string
}

// saveRemoteLink writes the responder's link for a request on another server:
// one per (server, request, responder), so answering again updates it. The
// token is rotated on every answer; the other server receives the new one
// with the answer. before is nil when the link is new.
func saveRemoteLink(app core.App, auth *core.Record, domain, slug, label, senderName, identifier string,
	withIdentity bool, identityID string, data map[string]any, grants map[string]string, token string,
) (*core.Record, *remoteLinkState, error) {
	f := util.Fields.Link
	link, _ := app.FindFirstRecordByFilter(util.Coll.Links,
		f.RemoteDomain+" = {:d} && "+f.RemoteRequest+" = {:s} && "+f.User+" = {:u}",
		dbx.Params{"d": domain, "s": slug, "u": auth.Id})

	var before *remoteLinkState
	if link != nil {
		before = &remoteLinkState{
			label:      link.GetString(f.Label),
			senderName: link.GetString(f.SenderName),
			identifier: link.GetString(f.Identifier),
			identity:   link.GetString(f.Identity),
			tokenHash:  link.GetString(f.GrantTokenHash),
			data:       link.Get(f.Data),
			grants:     link.Get(f.Grants),
			records:    link.GetStringSlice(f.Records),
		}
	} else {
		col, err := app.FindCollectionByNameOrId(util.Coll.Links)
		if err != nil {
			return nil, nil, err
		}
		linkSlug, err := mintLinkSlug(app, nil)
		if err != nil {
			return nil, nil, err
		}
		link = core.NewRecord(col)
		link.Set(f.Slug, linkSlug)
		link.Set(f.RemoteDomain, domain)
		link.Set(f.RemoteRequest, slug)
		link.Set(f.User, auth.Id)
		link.Set(f.Workspace, auth.GetString(util.Fields.User.ActiveWorkspace))
	}

	link.Set(f.Label, label)
	link.Set(f.Status, util.StatusActive)
	link.Set(f.SenderName, senderName)
	link.Set(f.Identifier, identifier)
	if withIdentity {
		link.Set(f.Identity, identityID)
	} else {
		link.Set(f.Identity, "")
	}
	link.Set(f.Data, data)
	link.Set(f.Records, grantRecordIdsFrom(grants))
	link.Set(f.Grants, grants)
	link.Set(f.GrantTokenHash, util.HashToken(token))
	if err := app.Save(link); err != nil {
		return nil, nil, err
	}
	return link, before, nil
}

// undoRemoteLink takes back a link whose answer the other server refused: a
// new one is deleted, an updated one gets its previous answer back.
func undoRemoteLink(app core.App, link *core.Record, before *remoteLinkState) {
	f := util.Fields.Link
	if before == nil {
		// Never held by anyone, so its deletion is nothing to announce.
		link.Set(f.Status, util.StatusRevoked)
		if err := app.Delete(link); err != nil {
			app.Logger().Error("Failed to remove refused remote link", "error", err, "link", link.Id)
		}
		return
	}
	link.Set(f.Label, before.label)
	link.Set(f.SenderName, before.senderName)
	link.Set(f.Identifier, before.identifier)
	link.Set(f.Identity, before.identity)
	link.Set(f.GrantTokenHash, before.tokenHash)
	link.Set(f.Data, before.data)
	link.Set(f.Grants, before.grants)
	link.Set(f.Records, before.records)
	if err := app.Save(link); err != nil {
		app.Logger().Error("Failed to restore remote link", "error", err, "link", link.Id)
	}
}

func deleteRecords(app core.App, ids []string) {
	for _, id := range ids {
		if rec, err := app.FindRecordById(util.Coll.Records, id); err == nil && rec != nil {
			_ = app.Delete(rec)
		}
	}
}

// peerJSON makes one JSON call to another server through the SSRF-safe
// client. A transport failure is err; a refusal in the error envelope is a
// *peerError; anything else 2xx is decoded into out.
func peerJSON(method, target string, in any, out any) (*peerError, error) {
	var reader io.Reader
	if in != nil {
		b, err := json.Marshal(in)
		if err != nil {
			return nil, err
		}
		reader = bytes.NewReader(b)
	}
	req, err := http.NewRequest(method, target, reader)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Accept", "application/json")
	if in != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	resp, err := util.NewSafeCallbackClient(services.PeerFetchTimeout).Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	raw, err := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if err != nil {
		return nil, err
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		var env struct {
			Code    string `json:"code"`
			Message string `json:"message"`
		}
		_ = json.Unmarshal(raw, &env)
		if env.Code == "" {
			return nil, errors.New("HTTP " + strconv.Itoa(resp.StatusCode))
		}
		return &peerError{status: resp.StatusCode, code: env.Code, message: env.Message}, nil
	}
	if out != nil {
		if err := json.Unmarshal(raw, out); err != nil {
			return nil, err
		}
	}
	return nil, nil
}

// peerErrorResponse passes another server's refusal on with its code, so the
// app reacts to a wrong password there as it would to one here. A 5xx from
// the other server is reported as a bad gateway rather than as this server's
// own failure.
func peerErrorResponse(re *core.RequestEvent, p *peerError) error {
	status := p.status
	if status >= 500 {
		status = http.StatusBadGateway
	}
	return appErrorResponse(re, status, &util.AppError{ErrorCode: p.code, ErrorText: p.message})
}

// acceptRemoteAnswer takes an answer that lives on the responder's server.
//
// Every gate a local answer passes applies here too. The responder's account
// is on their own server, so instead of a session this server receives the
// grant itself and reads it once before accepting: that proves the server is
// reachable at the domain it claims, that it recognises the token, and gives
// the values the template is checked against. The values are not kept.
func acceptRemoteAnswer(app core.App, root *server.RootKey, re *core.RequestEvent) error {
	if !allowRequest(re, grantPeerLimiter, "") {
		return rateLimitedResponse(re)
	}
	slug := re.Request.PathValue("slug")
	var body remoteAnswer
	_ = re.BindBody(&body)

	req, err := app.FindFirstRecordByFilter(util.Coll.Requests, "slug = {:slug}", dbx.Params{"slug": slug})
	if err != nil || req == nil {
		return re.NotFoundError(util.Errors.RequestNotFound.ErrorText, nil)
	}
	if appErr := services.RefreshRequestStatus(app, req); appErr != nil {
		return resourceErrorResponse(re, appErr)
	}
	if !enforceRequestSecrets(re, req, slug, body.Password, body.Identifier) {
		return nil
	}

	peer, ok := util.NormalizePeerDomain(body.Server)
	if !ok {
		return appErrorResponse(re, http.StatusBadRequest, &util.Errors.RemoteOriginInvalid)
	}
	if body.Grant.ID == "" || body.Grant.Token == "" {
		return appErrorResponse(re, http.StatusBadRequest, &util.Errors.RemoteGrantUnresolvable)
	}

	var proven *remoteIdentity
	if req.GetBool(util.Fields.Request.RequireHandshake) {
		if body.Identity == nil || body.Identity.ID == "" {
			return appErrorResponse(re, http.StatusBadRequest, &util.Errors.IdentityRequired)
		}
		if !verifyRemoteIdentity(root, re, req, slug, peer, body.Identity, body.ChallengeNonce, body.ChallengeSignature) {
			return nil
		}
		proven = body.Identity
	}

	results, err := services.FetchRemoteGrants(peer, []services.GrantReadItem{{ID: body.Grant.ID, Token: body.Grant.Token}})
	if err != nil {
		return appErrorResponse(re, http.StatusBadGateway, &util.Errors.RemoteUnreachable)
	}
	if len(results) != 1 || results[0].ID != body.Grant.ID || results[0].Status != util.StatusActive {
		return appErrorResponse(re, http.StatusBadRequest, &util.Errors.RemoteGrantUnresolvable)
	}
	read := results[0]

	values := make(map[string]any, len(read.Values))
	keys := make([]string, 0, len(read.Values))
	for k, v := range read.Values {
		values[k] = v
		keys = append(keys, k)
	}
	templateKeys := templateKeysFrom(loadRequestTemplate(app, req))
	if appErr := validateSubmissionData(values, templateKeys, req.GetBool(util.Fields.Request.AllowExtraFields)); appErr != nil {
		return appErrorResponse(re, http.StatusBadRequest, appErr)
	}

	f := util.Fields.RemoteGrant
	rg, _ := app.FindFirstRecordByFilter(util.Coll.RemoteGrants,
		f.Domain+" = {:d} && "+f.Grant+" = {:g}", dbx.Params{"d": peer, "g": body.Grant.ID})
	isUpdate := rg != nil
	if isUpdate && rg.GetString(f.Request) != req.Id {
		// A grant answers one request; the same grant offered to another is
		// not the answer it claims to be.
		return appErrorResponse(re, http.StatusBadRequest, &util.Errors.RemoteGrantUnresolvable)
	}
	if rg == nil {
		col, err := app.FindCollectionByNameOrId(util.Coll.RemoteGrants)
		if err != nil {
			return re.InternalServerError("Failed to record response", nil)
		}
		rg = core.NewRecord(col)
		rg.Set(f.Request, req.Id)
		rg.Set(f.Domain, peer)
		rg.Set(f.Grant, body.Grant.ID)
	}
	rg.Set(f.Token, body.Grant.Token)
	rg.Set(f.Status, util.StatusActive)
	// Event times are the responder's server's clock, not this one's, so an
	// answer starts with none: any event that follows it may apply.
	rg.Set(f.StatusAt, 0)
	rg.Set(f.Keys, keys)
	rg.Set(f.SenderName, body.SenderName)
	rg.Set(f.Identifier, body.Identifier)
	rg.Set(f.IdentityName, "")
	rg.Set(f.IdentityFingerprint, "")
	rg.Set(f.IdentityDomain, "")
	if proven != nil {
		rg.Set(f.IdentityName, proven.Name)
		rg.Set(f.IdentityFingerprint, proven.Fingerprint)
		rg.Set(f.IdentityDomain, proven.DomainAtIssue)
	}
	if err := app.Save(rg); err != nil {
		app.Logger().Error("Failed to record remote response", "error", err)
		return re.InternalServerError("Failed to record response", nil)
	}
	services.RememberRemoteGrant(peer, body.Grant.ID, read, time.Now())

	completed := false
	if !isUpdate {
		count := req.GetInt(util.Fields.Request.ResponseCount) + 1
		req.Set(util.Fields.Request.ResponseCount, count)
		if max := req.GetInt(util.Fields.Request.MaxResponses); max > 0 && count >= max {
			req.Set(util.Fields.Request.Status, util.StatusCompleted)
			completed = true
		}
		if err := app.Save(req); err != nil {
			app.Logger().Error("Failed to update request response count", "error", err)
		}
	}

	if cb := req.GetString(util.Fields.Request.CallbackUrl); cb != "" {
		go deliverRemoteCallback(app, req, rg, values, cb)
	}
	notifyRequestAnswered(app, req, isUpdate, completed)

	return re.JSON(http.StatusOK, map[string]any{
		"ok":         true,
		"responseId": rg.Id,
		"completed":  completed,
		"updated":    isUpdate,
	})
}

// verifyRemoteIdentity walks a relayed identity's chain: the certificate is
// the one fingerprinted, the issuing server's root key — tied to its domain by
// the DNS pin — signed that fingerprint, the issuer still vouches for it, and
// the responder's device signed this request's challenge with its key.
//
// Reports whether the caller may proceed, having written the refusal if not.
func verifyRemoteIdentity(root *server.RootKey, re *core.RequestEvent, req *core.Record, slug, peer string, id *remoteIdentity, nonce, signature string) bool {
	if !strings.EqualFold(id.DomainAtIssue, peer) || !server.ValidIdentityFingerprint(id.Fingerprint) {
		return denyGate(re, http.StatusForbidden, &util.Errors.RemoteIdentityInvalid)
	}
	sum := sha256.Sum256([]byte(id.Certificate))
	if hex.EncodeToString(sum[:]) != id.Fingerprint {
		return denyGate(re, http.StatusForbidden, &util.Errors.RemoteIdentityInvalid)
	}
	if req.GetString(util.Fields.Request.IdentityScope) == "from_root" &&
		!strings.EqualFold(id.DomainAtIssue, root.Domain()) {
		return denyGate(re, http.StatusForbidden, &util.Errors.IdentityWrongRoot)
	}

	if nonce == "" || signature == "" {
		return denyGate(re, http.StatusUnauthorized, &util.Errors.ChallengeRequired)
	}
	if !ConsumeChallenge(nonce, "request", slug, id.ID) {
		return denyGate(re, http.StatusUnauthorized, &util.Errors.ChallengeInvalid)
	}
	if err := util.VerifySignature(id.Certificate, nonce, signature); err != nil {
		return denyGate(re, http.StatusUnauthorized, &util.Errors.SignatureInvalid)
	}

	rootPub, err := services.PeerRootKey(peer)
	if err != nil {
		return denyGate(re, http.StatusForbidden, &util.Errors.RemoteIdentityInvalid)
	}
	if err := server.VerifyParentSignature(rootPub, id.Fingerprint, id.ParentSignature); err != nil {
		return denyGate(re, http.StatusForbidden, &util.Errors.RemoteIdentityInvalid)
	}
	assertion, err := services.FetchPeerIdentityStatus(peer, id.Fingerprint)
	if err != nil {
		return denyGate(re, http.StatusForbidden, &util.Errors.RemoteIdentityInvalid)
	}
	status, err := server.VerifyIdentityStatus(assertion, rootPub, peer, id.Fingerprint, time.Now())
	if err != nil {
		return denyGate(re, http.StatusForbidden, &util.Errors.RemoteIdentityInvalid)
	}
	if status.Status != server.IdentityStatusActive {
		return denyGate(re, http.StatusForbidden, &util.Errors.IdentityRevoked)
	}
	return true
}

// deliverRemoteCallback is deliverCallback for an answer that lives on the
// responder's server: the values are the ones just read, and `server` names
// where the answer lives.
func deliverRemoteCallback(app core.App, req, rg *core.Record, values map[string]any, url string) {
	f := util.Fields.RemoteGrant
	payload := map[string]any{
		"requestId":  req.Id,
		"slug":       req.GetString(util.Fields.Request.Slug),
		"responseId": rg.Id,
		"linkId":     rg.Id,
		"server":     rg.GetString(f.Domain),
		"identity":   rg.GetString(f.IdentityFingerprint),
		"identifier": rg.GetString(f.Identifier),
		"senderName": rg.GetString(f.SenderName),
		"data":       values,
	}
	status, err := services.PostCallback(url, req.Id, payload)
	if err != nil {
		notifyCallbackFailed(app, req, err.Error())
		return
	}
	if status >= 400 {
		notifyCallbackFailed(app, req, "callback returned status "+strconv.Itoa(status))
	}
}

// resolveGrantBatch answers another server's bulk read of grants it holds.
func resolveGrantBatch(app core.App, re *core.RequestEvent) error {
	if !allowRequest(re, grantPeerLimiter, "") {
		return rateLimitedResponse(re)
	}
	var body struct {
		Grants []services.GrantReadItem `json:"grants"`
	}
	if err := re.BindBody(&body); err != nil || len(body.Grants) == 0 {
		return re.BadRequestError("grants is required", nil)
	}
	if len(body.Grants) > services.MaxGrantReadBatch {
		return re.BadRequestError("at most "+strconv.Itoa(services.MaxGrantReadBatch)+" grants per request", nil)
	}
	re.Response.Header().Set("Cache-Control", "no-store")
	return re.JSON(http.StatusOK, map[string]any{"items": services.ReadGrants(app, body.Grants)})
}

// receiveGrantEvents takes a signed batch of events from a responder's server.
//
// The claimed sender is read from the unverified payload only to know whose
// key to fetch; nothing is acted on until the signature verifies under that
// key. A key that cannot be fetched answers 503, so the sender retries; one
// that does not verify answers 401, which it does not.
func receiveGrantEvents(app core.App, root *server.RootKey, re *core.RequestEvent) error {
	if !allowRequest(re, grantPeerLimiter, "") {
		return rateLimitedResponse(re)
	}
	var signed server.SignedGrantEvents
	if err := re.BindBody(&signed); err != nil {
		return re.BadRequestError("invalid body", nil)
	}
	claimed, err := signed.Body()
	if err != nil {
		return appErrorResponse(re, http.StatusUnauthorized, &util.Errors.GrantEventsUnverified)
	}
	sender, ok := util.NormalizePeerDomain(claimed.Domain)
	if !ok {
		return appErrorResponse(re, http.StatusUnauthorized, &util.Errors.GrantEventsUnverified)
	}

	verified, err := verifyFromPeer(signed, sender, root.Domain())
	if err != nil {
		if errors.Is(err, errPeerKeyUnavailable) {
			re.Response.Header().Set("Retry-After", "60")
			return appErrorResponse(re, http.StatusServiceUnavailable, &util.Errors.PeerKeyUnavailable)
		}
		return appErrorResponse(re, http.StatusUnauthorized, &util.Errors.GrantEventsUnverified)
	}
	if len(verified.Events) > maxGrantEventsPerBatch {
		return re.BadRequestError("too many events in one batch", nil)
	}
	applied := services.ApplyGrantEvents(app, sender, verified.Events)
	return re.JSON(http.StatusOK, map[string]any{"applied": applied})
}

var errPeerKeyUnavailable = errors.New("peer key unavailable")

// verifyFromPeer checks a batch against the sender's root key. A batch that
// fails under a cached key is checked once more under a freshly fetched one,
// so a peer that rotated its key is not refused for an hour.
func verifyFromPeer(signed server.SignedGrantEvents, sender, audience string) (server.GrantEventsBody, error) {
	for attempt := 0; attempt < 2; attempt++ {
		pub, err := services.PeerRootKey(sender)
		if err != nil {
			if errors.Is(err, services.ErrPeerNotPinned) || errors.Is(err, services.ErrPeerKeySpoofed) {
				return server.GrantEventsBody{}, err
			}
			return server.GrantEventsBody{}, errPeerKeyUnavailable
		}
		body, err := server.VerifyGrantEvents(signed, pub, sender, audience, time.Now())
		if err == nil {
			return body, nil
		}
		if attempt == 0 && services.ForgetPeerRootKey(sender) {
			continue
		}
		return server.GrantEventsBody{}, err
	}
	return server.GrantEventsBody{}, errors.New("unreachable")
}
