package routes

import (
	"errors"
	"net/http"
	"net/url"
	"strings"
	"time"

	"revoked/cmd/revoked/server"
	"revoked/cmd/revoked/services"
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
)

// challengeScopeReissue is the challenge scope a credential is moved under.
// Its slug is the fingerprint of the identity the credential is bound to, and
// its identity the one it moves to.
const challengeScopeReissue = "reissue"

// credentialReissue is what moves a credential to another identity: the
// credential as issued, the public half of the identity it moves to, that
// identity's signature over the issuer's challenge, and the voucher the key
// the credential is bound to signed for it.
type credentialReissue struct {
	Credential         string                 `json:"credential"`
	Identity           *remoteIdentity        `json:"identity"`
	ChallengeNonce     string                 `json:"challengeNonce"`
	ChallengeSignature string                 `json:"challengeSignature"`
	Voucher            *server.ReissueVoucher `json:"voucher"`
}

// errReissueStale: between the first look and the transaction, the
// credential stopped standing — revoked, or moved by another request.
var errReissueStale = errors.New("credential no longer stands")

// reissueCredential is the issuer's side of replacing an identity: a
// credential issued here, bound to the identity being replaced, is issued
// again for its replacement, and the old one is revoked.
//
// Nobody at the issuer is asked. The authority is the key the credential is
// bound to, which could present the credential anyway; with the voucher it
// hands that over to one other identity, once. Three things keep the hand-over
// from outliving its purpose. The old identity must still stand, so revoking
// it ends the old key's say. The new identity must come from the server that
// issued the old one, so a copy of the key cannot carry the credential off to
// a domain of the copier's choosing. And the old credential is revoked as the
// new one is issued, so it is handed over once and the first hand-over is
// visible to the holder as a refusal of the second.
//
// The order is the order of cost, as for a claim: what can be checked here,
// then the one-time challenge, then the identities' servers.
func reissueCredential(app core.App, root *server.RootKey, body credentialReissue) (string, *util.AppError, int) {
	f := util.Fields.Attestation
	now := time.Now()
	invalid := func() (string, *util.AppError, int) {
		return "", &util.Errors.ReissueCredentialInvalid, http.StatusBadRequest
	}

	raw := strings.TrimSpace(body.Credential)
	if raw == "" || len(raw) > util.MaxCredentialLength {
		return invalid()
	}
	p, err := server.ParseCredential(raw)
	if err != nil || p.KeyBinding != "" {
		return invalid()
	}
	keys, err := root.Credentials()
	if err != nil {
		app.Logger().Error("Credential key unavailable", "error", err)
		return "", &util.Errors.AttestationIssueFailed, http.StatusInternalServerError
	}
	iss, _ := p.Payload["iss"].(string)
	if domain, ok := services.CredentialIssuerDomain(iss); !ok || !strings.EqualFold(domain, root.Domain()) || p.Header.Kid != keys.Kid() {
		return invalid()
	}
	stated, err := server.VerifyCredential(p, keys.PublicKey(), now)
	switch {
	case errors.Is(err, server.ErrCredentialExpired):
		return "", &util.Errors.ReissueCredentialExpired, http.StatusGone
	case err != nil:
		return invalid()
	}
	old := stated.Holder
	old.Fingerprint = strings.ToLower(old.Fingerprint)
	if stated.HolderKey == nil || stated.Status == nil ||
		stated.Status.URI != services.CredentialStatusURI(root.Domain()) ||
		!server.ValidIdentityFingerprint(old.Fingerprint) {
		return invalid()
	}

	id := body.Identity
	newKey, appErr, status := checkPresentedIdentity(id)
	if appErr != nil {
		return "", appErr, status
	}
	oldDomain, ok := util.NormalizePeerDomain(old.Domain)
	if !ok || !strings.EqualFold(oldDomain, id.DomainAtIssue) || id.Fingerprint == old.Fingerprint {
		return "", &util.Errors.ReissueIdentityMismatch, http.StatusForbidden
	}

	attestation, again, appErr, status := standingAttestation(app, stated.Status.Idx, old.Fingerprint, id.Fingerprint)
	if appErr != nil {
		return "", appErr, status
	}
	if body.ChallengeNonce == "" || body.ChallengeSignature == "" {
		return "", &util.Errors.ChallengeRequired, http.StatusUnauthorized
	}
	if body.Voucher == nil {
		return "", &util.Errors.ReissueVoucherInvalid, http.StatusUnauthorized
	}
	if err := server.VerifyReissueVoucher(*body.Voucher, *stated.HolderKey, server.ReissueVoucherBody{
		Issuer:         root.Domain(),
		OldFingerprint: old.Fingerprint,
		NewFingerprint: id.Fingerprint,
		Nonce:          body.ChallengeNonce,
	}); err != nil {
		return "", &util.Errors.ReissueVoucherInvalid, http.StatusUnauthorized
	}

	if !ConsumeChallenge(body.ChallengeNonce, challengeScopeReissue, old.Fingerprint, id.ID) {
		return "", &util.Errors.ChallengeInvalid, http.StatusUnauthorized
	}
	if err := util.VerifySignature(id.Certificate, body.ChallengeNonce, body.ChallengeSignature); err != nil {
		return "", &util.Errors.SignatureInvalid, http.StatusUnauthorized
	}

	if appErr, status := verifyIdentityChain(app, root, id); appErr != nil {
		return "", appErr, status
	}
	switch services.HolderIdentityStatus(app, root, old, now).State {
	case services.AttestationVerified:
	case services.AttestationRevoked:
		return "", &util.Errors.ReissueHolderRevoked, http.StatusForbidden
	default:
		return "", &util.Errors.ReissueHolderUnconfirmed, http.StatusForbidden
	}

	credential := ""
	err = app.RunInTransaction(func(tx core.App) error {
		// Read again inside the transaction: the issuer may have revoked it,
		// or a second request moved it, since the first look.
		fresh, err := tx.FindRecordById(util.Coll.Attestations, attestation.Id)
		if err != nil {
			return err
		}
		if fresh.GetString(f.Status) != util.StatusActive {
			return errReissueStale
		}

		var idx int
		if again {
			// Moved here before: the credential at its current position,
			// once more, and nothing else changes.
			if fresh.GetString(f.SubjectFingerprint) != id.Fingerprint {
				return errReissueStale
			}
			if idx, err = services.AllocateAttestationStatus(tx, fresh.Id); err != nil {
				return err
			}
		} else {
			if fresh.GetString(f.SubjectFingerprint) != old.Fingerprint {
				return errReissueStale
			}
			position, err := services.AttestationStatusAt(tx, stated.Status.Idx)
			if err != nil {
				return err
			}
			if position == nil || position.GetBool(util.Fields.AttestationStatus.Revoked) ||
				position.GetString(util.Fields.AttestationStatus.Attestation) != fresh.Id {
				return errReissueStale
			}
			if idx, err = services.RenewAttestationStatus(tx, fresh.Id); err != nil {
				return err
			}
			fresh.Set(f.SubjectFingerprint, id.Fingerprint)
			fresh.Set(f.SubjectDomain, id.DomainAtIssue)
			fresh.Set(f.SubjectName, truncateRunes(id.Name, 255))
			if err := tx.Save(fresh); err != nil {
				return err
			}
		}

		claims := map[string]any{}
		if err := fresh.UnmarshalJSONField(f.Claims, &claims); err != nil {
			return err
		}
		issuedAt := fresh.GetDateTime(f.IssuedAt).Time()
		if issuedAt.IsZero() {
			issuedAt = stated.IssuedAt
		}
		// The same statement, from the same day, until the same day: only the
		// identity it is about and its place in the status list are new.
		spec := server.CredentialSpec{
			Issuer:    services.CredentialIssuer(root.Domain()),
			Type:      fresh.GetString(f.Type),
			Holder:    server.HolderRef{Fingerprint: id.Fingerprint, Domain: id.DomainAtIssue},
			HolderKey: newKey,
			Claims:    claims,
			IssuedAt:  issuedAt,
			Status:    &server.StatusRef{Idx: idx, URI: services.CredentialStatusURI(root.Domain())},
		}
		if until := fresh.GetDateTime(f.ExpiresAt); !until.IsZero() {
			spec.ExpiresAt = until.Time()
		}
		credential, err = keys.IssueCredential(spec)
		return err
	})
	switch {
	case errors.Is(err, errReissueStale):
		return "", &util.Errors.ReissueCredentialRevoked, http.StatusGone
	case err != nil:
		app.Logger().Error("Failed to reissue a credential", "error", err, "attestation", attestation.Id)
		return "", &util.Errors.AttestationIssueFailed, http.StatusInternalServerError
	}
	app.Logger().Info("Credential reissued", "attestation", attestation.Id, "holder", id.DomainAtIssue, "again", again)
	return credential, nil, http.StatusOK
}

// standingAttestation finds the attestation a credential issued here stands
// for, by the credential's position in the status list, and refuses one that
// no longer stands for holder: its position revoked, the attestation revoked
// or deleted, or the attestation moved on to someone else.
//
// One case is let through: the credential was already moved to next. Its
// position is revoked and the attestation names next, and again reports it.
// Asking again then hands out the current credential once more, so an answer
// lost on its way to the holder costs nothing — the same identity, with the
// same proofs, receiving what it already holds.
func standingAttestation(app core.App, idx int, holder, next string) (rec *core.Record, again bool, appErr *util.AppError, status int) {
	f := util.Fields.Attestation
	position, err := services.AttestationStatusAt(app, idx)
	if err != nil {
		app.Logger().Error("Failed to read the status list", "error", err)
		return nil, false, &util.Errors.AttestationIssueFailed, http.StatusInternalServerError
	}
	if position == nil {
		return nil, false, &util.Errors.ReissueCredentialRevoked, http.StatusGone
	}
	rec, err = app.FindRecordById(util.Coll.Attestations, position.GetString(util.Fields.AttestationStatus.Attestation))
	if err != nil || rec == nil || rec.GetString(f.Status) != util.StatusActive {
		return nil, false, &util.Errors.ReissueCredentialRevoked, http.StatusGone
	}
	revoked, subject := position.GetBool(util.Fields.AttestationStatus.Revoked), rec.GetString(f.SubjectFingerprint)
	switch {
	case !revoked && subject == holder:
		return rec, false, nil, http.StatusOK
	case revoked && subject == next:
		return rec, true, nil, http.StatusOK
	}
	return nil, false, &util.Errors.ReissueCredentialRevoked, http.StatusGone
}

// reissueTarget is what the holder's server moves when one of its people
// replaces an identity: the credential row, the identity it is bound to, the
// identity it moves to, and where its issuer is.
type reissueTarget struct {
	row      *core.Record
	from, to *core.Record
	issuer   string
	// base is the issuer's address; empty when the issuer is this server.
	base string
}

// loadReissueTarget resolves a credential of auth's and an identity of
// theirs to move it to. Both must be theirs; the identity it moves to must
// stand, and be another one.
func loadReissueTarget(app core.App, root *server.RootKey, auth *core.Record, credentialID, identityID string) (*reissueTarget, *util.AppError, int) {
	row, err := app.FindRecordById(util.Coll.Credentials, credentialID)
	if err != nil || row == nil || row.GetString(util.Fields.Credential.User) != auth.Id {
		return nil, &util.Errors.CredentialNotFound, http.StatusNotFound
	}
	from, err := app.FindRecordById(util.Coll.Identities, row.GetString(util.Fields.Credential.Identity))
	if err != nil || from == nil || from.GetString(util.Fields.Identity.User) != auth.Id {
		return nil, &util.Errors.CredentialNotFound, http.StatusNotFound
	}
	to, err := app.FindRecordById(util.Coll.Identities, identityID)
	if identityID == "" || err != nil || to == nil || to.GetString(util.Fields.Identity.User) != auth.Id {
		return nil, &util.Errors.IdentityNotOwned, http.StatusForbidden
	}
	if !services.IdentityIsActive(to) {
		return nil, &util.Errors.IdentityRevoked, http.StatusForbidden
	}
	if to.Id == from.Id {
		return nil, &util.Errors.ReissueIdentityMismatch, http.StatusForbidden
	}
	target := &reissueTarget{row: row, from: from, to: to, issuer: row.GetString(util.Fields.Credential.Issuer)}
	if !strings.EqualFold(target.issuer, root.Domain()) {
		target.base, _ = util.PeerBaseURL(target.issuer)
	}
	return target, nil, http.StatusOK
}

// relayReissueChallenge fetches the issuer's challenge for moving a
// credential, for the app to sign. The app knows its issuer only by domain,
// which this server can reach and the app, in a development setup, may not;
// what the app signs it builds itself, from what it already knows.
func relayReissueChallenge(app core.App, root *server.RootKey, re *core.RequestEvent) error {
	if re.Auth == nil || re.Auth.Collection().Name != util.Coll.Users {
		return appErrorResponse(re, http.StatusUnauthorized, &util.Errors.NotAuthenticated)
	}
	if !allowRequest(re, grantPeerLimiter, "reissue|"+re.Auth.Id) {
		return rateLimitedResponse(re)
	}
	target, appErr, status := loadReissueTarget(app, root, re.Auth,
		re.Request.PathValue("id"), re.Request.URL.Query().Get("identityId"))
	if appErr != nil {
		return appErrorResponse(re, status, appErr)
	}
	slug := target.from.GetString(util.Fields.Identity.Fingerprint)

	var out struct {
		Nonce     string `json:"nonce"`
		ExpiresAt string `json:"expiresAt"`
	}
	if target.base == "" {
		nonce, exp, err := IssueChallenge(challengeScopeReissue, slug, target.to.Id)
		if err != nil {
			return re.InternalServerError("Failed to issue challenge", nil)
		}
		out.Nonce, out.ExpiresAt = nonce, exp.UTC().Format(time.RFC3339)
	} else {
		query := url.Values{"identityId": {target.to.Id}}
		address := target.base + "/api/challenges/" + challengeScopeReissue + "/" + url.PathEscape(slug) + "?" + query.Encode()
		if perr, err := peerJSON(http.MethodGet, address, nil, &out); err != nil {
			return appErrorResponse(re, http.StatusBadGateway, &util.Errors.RemoteUnreachable)
		} else if perr != nil {
			return peerErrorResponse(re, perr)
		}
		if out.Nonce == "" {
			return appErrorResponse(re, http.StatusBadGateway, &util.Errors.RemoteUnreachable)
		}
	}
	re.Response.Header().Set("Cache-Control", "no-store")
	return re.JSON(http.StatusOK, out)
}

// relayCredentialReissue moves a credential of a person signed in here to
// another of their identities, and keeps the replacement in place of the old
// copy.
//
// The app signs on the device, where both keys are: the voucher with the key
// the credential is bound to, the issuer's challenge with the new one. This
// server adds the credential and the new identity's public half, asks the
// issuer — itself, when the credential is its own — and checks what comes
// back as it checks an accepted offer: the issuer signed it, and it is bound
// to the identity it moves to.
func relayCredentialReissue(app core.App, root *server.RootKey, re *core.RequestEvent) error {
	if re.Auth == nil || re.Auth.Collection().Name != util.Coll.Users {
		return appErrorResponse(re, http.StatusUnauthorized, &util.Errors.NotAuthenticated)
	}
	if !allowRequest(re, grantPeerLimiter, "reissue|"+re.Auth.Id) {
		return rateLimitedResponse(re)
	}
	var body struct {
		IdentityId         string                 `json:"identityId"`
		ChallengeNonce     string                 `json:"challengeNonce"`
		ChallengeSignature string                 `json:"challengeSignature"`
		Voucher            *server.ReissueVoucher `json:"voucher"`
	}
	_ = re.BindBody(&body)
	target, appErr, status := loadReissueTarget(app, root, re.Auth, re.Request.PathValue("id"), body.IdentityId)
	if appErr != nil {
		return appErrorResponse(re, status, appErr)
	}

	identity := identityFromRecord(target.to)
	holderPub, err := util.PublicKeyFromPEM(identity.Certificate)
	if err != nil {
		return appErrorResponse(re, http.StatusBadRequest, &util.Errors.AttestationKeyUnsupported)
	}
	holderKey, err := server.JWKFromPublicKey(holderPub)
	if err != nil {
		return appErrorResponse(re, http.StatusBadRequest, &util.Errors.AttestationKeyUnsupported)
	}
	request := credentialReissue{
		Credential:         target.row.GetString(util.Fields.Credential.Credential),
		Identity:           identity,
		ChallengeNonce:     body.ChallengeNonce,
		ChallengeSignature: body.ChallengeSignature,
		Voucher:            body.Voucher,
	}

	credential := ""
	if target.base == "" {
		issued, appErr, status := reissueCredential(app, root, request)
		if appErr != nil {
			return appErrorResponse(re, status, appErr)
		}
		credential = issued
	} else {
		var out struct {
			Credential string `json:"credential"`
		}
		if perr, err := peerJSON(http.MethodPost, target.base+"/api/attestations/reissue", request, &out); err != nil {
			return appErrorResponse(re, http.StatusBadGateway, &util.Errors.RemoteUnreachable)
		} else if perr != nil {
			return peerErrorResponse(re, perr)
		}
		credential = out.Credential
	}

	stated, err := services.CheckIssuedCredential(root, credential, target.issuer, holderKey,
		server.HolderRef{Fingerprint: identity.Fingerprint, Domain: identity.DomainAtIssue}, time.Now())
	if err != nil {
		app.Logger().Warn("A reissued credential did not verify", "issuer", target.issuer, "error", err)
		return appErrorResponse(re, http.StatusBadGateway, &util.Errors.CredentialInvalid)
	}

	row := target.row
	row.Set(util.Fields.Credential.Identity, target.to.Id)
	row.Set(util.Fields.Credential.Workspace, target.to.GetString(util.Fields.Identity.Workspace))
	if err := writeCredential(app, row, credential, stated); err != nil {
		app.Logger().Error("Failed to keep a reissued credential", "error", err)
		return re.InternalServerError("Failed to keep the credential", nil)
	}
	re.Response.Header().Set("Cache-Control", "no-store")
	return re.JSON(http.StatusOK, row.PublicExport())
}
