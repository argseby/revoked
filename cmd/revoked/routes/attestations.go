package routes

import (
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"

	"revoked/cmd/revoked/server"
	"revoked/cmd/revoked/services"
	"revoked/util"

	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tools/types"
)

// challengeScopeAttestation is the challenge scope an offer is accepted under.
const challengeScopeAttestation = "attestation"

// maxOfferTokenLength bounds what is looked up as an offer token.
const maxOfferTokenLength = 128

// AttestationsRoute exposes what attestations need beyond the collection API:
//
//	GET  /.well-known/jwt-vc-issuer             the credential key, certified by the root key
//	GET  /api/attestations/status               the status list of every credential issued here
//	GET  /api/attestations/offers/{token}       what an offer states, before it is accepted
//	POST /api/attestations/offers/{token}/claim accept it with a proven identity -> the credential
//	POST /api/attestations/verify               a presentation -> a verdict
//	POST /api/credentials/claim                 holder's app -> holder's server -> the issuer
//	GET  /api/credentials/{id}/status           the holder's view of a credential they keep
//
// An attestation is created through the collection API as an offer. Accepting
// it is what issues the credential: the subject proves possession of an
// identity key, this server checks that identity with the server that issued
// it, and signs a credential bound to that key. The credential is handed over
// once and not kept here.
func AttestationsRoute(app core.App, root *server.RootKey) {
	app.OnServe().BindFunc(func(e *core.ServeEvent) error {
		e.Router.GET("/.well-known/jwt-vc-issuer", func(re *core.RequestEvent) error {
			keys, err := root.Credentials()
			if err != nil {
				return re.InternalServerError("Credential key unavailable", err)
			}
			re.Response.Header().Set("Cache-Control", "public, max-age=3600")
			return re.JSON(http.StatusOK, map[string]any{
				"issuer": services.CredentialIssuer(root.Domain()),
				"jwks":   map[string]any{"keys": []server.PublicJWK{keys.JWK()}},
			})
		})

		e.Router.GET("/api/attestations/status", func(re *core.RequestEvent) error {
			return serveStatusList(app, root, re)
		})

		e.Router.GET("/api/attestations/offers/{token}", func(re *core.RequestEvent) error {
			if !allowRequest(re, probeLimiter, "") {
				return rateLimitedResponse(re)
			}
			offer, appErr, status := findAttestationOffer(app, re.Request.PathValue("token"))
			if appErr != nil {
				return appErrorResponse(re, status, appErr)
			}
			re.Response.Header().Set("Cache-Control", "no-store")
			return re.JSON(http.StatusOK, attestationOfferProbe(app, root, offer))
		})

		e.Router.POST("/api/attestations/offers/{token}/claim", func(re *core.RequestEvent) error {
			if !allowRequest(re, grantPeerLimiter, "") {
				return rateLimitedResponse(re)
			}
			var body attestationClaim
			_ = re.BindBody(&body)
			credential, appErr, status := claimAttestationOffer(app, root, re.Request.PathValue("token"), body)
			if appErr != nil {
				return appErrorResponse(re, status, appErr)
			}
			re.Response.Header().Set("Cache-Control", "no-store")
			return re.JSON(http.StatusOK, map[string]any{
				"credential": credential,
				"issuer":     root.Domain(),
			})
		})

		e.Router.POST("/api/attestations/verify", func(re *core.RequestEvent) error {
			// Unauthenticated, and each call can make this server look up DNS
			// and fetch from a domain the caller named: budgeted like the
			// peer verification it resembles.
			if !allowRequest(re, probeLimiter, "verify-attestation") {
				return rateLimitedResponse(re)
			}
			var body struct {
				Presentation string `json:"presentation"`
				Audience     string `json:"audience"`
				Nonce        string `json:"nonce"`
			}
			if err := re.BindBody(&body); err != nil || strings.TrimSpace(body.Presentation) == "" {
				return appErrorResponse(re, http.StatusBadRequest, &util.Errors.PresentationInvalid)
			}
			verdict := services.VerifyPresentation(app, root, body.Presentation,
				services.VerifyOptions{Audience: body.Audience, Nonce: body.Nonce}, time.Now())
			re.Response.Header().Set("Cache-Control", "no-store")
			return re.JSON(http.StatusOK, verdict)
		})

		e.Router.POST("/api/credentials/claim", func(re *core.RequestEvent) error {
			return relayAttestationClaim(app, root, re)
		})

		e.Router.GET("/api/credentials/{id}/status", func(re *core.RequestEvent) error {
			if re.Auth == nil || re.Auth.Collection().Name != util.Coll.Users {
				return appErrorResponse(re, http.StatusUnauthorized, &util.Errors.NotAuthenticated)
			}
			// Each read can reach out to the issuer's server on the caller's
			// behalf, so it is budgeted per account.
			if !allowRequest(re, grantPeerLimiter, "credential|"+re.Auth.Id) {
				return rateLimitedResponse(re)
			}
			rec, err := app.FindRecordById(util.Coll.Credentials, re.Request.PathValue("id"))
			if err != nil || rec == nil || rec.GetString(util.Fields.Credential.User) != re.Auth.Id {
				return re.NotFoundError("Credential not found", nil)
			}
			verdict := services.VerifyPresentation(app, root, rec.GetString(util.Fields.Credential.Credential),
				services.VerifyOptions{SkipKeyBinding: true}, time.Now())
			re.Response.Header().Set("Cache-Control", "no-store")
			return re.JSON(http.StatusOK, verdict)
		})

		return e.Next()
	})
}

// serveStatusList publishes the revocation state of every credential this
// server issued, as one signed list. A verifier reads the whole list and
// looks its credential up in it, so this server never learns which
// credential was checked, or by whom.
func serveStatusList(app core.App, root *server.RootKey, re *core.RequestEvent) error {
	if !allowRequest(re, probeLimiter, "status-list") {
		return rateLimitedResponse(re)
	}
	keys, err := root.Credentials()
	if err != nil {
		return re.InternalServerError("Credential key unavailable", err)
	}
	list, err := services.AttestationStatusList(app)
	if err != nil {
		return re.InternalServerError("Failed to build the status list", nil)
	}
	token, err := keys.SignStatusList(services.CredentialStatusURI(root.Domain()), list, time.Now())
	if err != nil {
		return re.InternalServerError("Failed to sign the status list", nil)
	}
	// Cacheable for as long as the list itself says it may be kept.
	re.Response.Header().Set("Cache-Control", "public, max-age="+strconv.Itoa(int(server.StatusListTTL.Seconds())))
	re.Response.Header().Set("Content-Type", "application/statuslist+jwt")
	re.Response.WriteHeader(http.StatusOK)
	_, err = re.Response.Write([]byte(token))
	return err
}

// findAttestationOffer resolves a plaintext token to an offer that can still
// be looked at: not withdrawn, and not past its date. Only the hash is stored.
//
// An accepted offer is still returned. The identity that accepted it may ask
// for the credential again until the offer's date, so an answer lost on the
// way, or a credential its holder removed, can be had again. Each time takes
// a fresh proof of the identity's key.
func findAttestationOffer(app core.App, token string) (*core.Record, *util.AppError, int) {
	f := util.Fields.Attestation
	if token == "" || len(token) > maxOfferTokenLength {
		return nil, &util.Errors.AttestationOfferNotFound, http.StatusNotFound
	}
	offer, err := app.FindFirstRecordByFilter(util.Coll.Attestations,
		f.OfferTokenHash+" = {:h}", dbx.Params{"h": util.HashToken(token)})
	if err != nil || offer == nil {
		return nil, &util.Errors.AttestationOfferNotFound, http.StatusNotFound
	}
	if offer.GetString(f.Status) == util.StatusRevoked {
		return nil, &util.Errors.AttestationOfferRevoked, http.StatusGone
	}
	now := time.Now()
	if until := offer.GetDateTime(f.OfferExpiresAt); !until.IsZero() && !until.Time().After(now) {
		return nil, &util.Errors.AttestationOfferExpired, http.StatusGone
	}
	if until := offer.GetDateTime(f.ExpiresAt); !until.IsZero() && !until.Time().After(now) {
		return nil, &util.Errors.AttestationOfferExpired, http.StatusGone
	}
	return offer, nil, http.StatusOK
}

// attestationOfferProbe is what an offer shows before it is accepted: who
// attests, what, and for whom. The values are shown only while the offer is
// open — the subject should see what would be stated about them — and are
// left out once it was accepted.
func attestationOfferProbe(app core.App, root *server.RootKey, offer *core.Record) map[string]any {
	f := util.Fields.Attestation
	out := map[string]any{
		"type":           offer.GetString(f.Type),
		"label":          offer.GetString(f.Label),
		"status":         offer.GetString(f.Status),
		"expiresAt":      offer.GetString(f.ExpiresAt),
		"offerExpiresAt": offer.GetString(f.OfferExpiresAt),
		// Set when the offer was made for one identity, or accepted by one.
		"subjectFingerprint": offer.GetString(f.SubjectFingerprint),
		// Without this the subject has nothing to walk the DNS chain
		// against, and an offer from a spoofed server looks like any other.
		"server": map[string]any{
			"domain":          root.Domain(),
			"rootFingerprint": root.Fingerprint(),
		},
	}
	if offer.GetString(f.Status) == util.StatusOffered {
		claims := map[string]any{}
		_ = offer.UnmarshalJSONField(f.Claims, &claims)
		out["claims"] = claims
	}
	if ws, err := app.FindRecordById(util.Coll.Workspaces, offer.GetString(f.Workspace)); err == nil && ws != nil {
		out["workspace"] = map[string]any{"name": ws.GetString(util.Fields.Workspace.Name)}
	}
	return out
}

// attestationClaim is what accepts an offer: the public half of the subject's
// identity, and its signature over this server's challenge.
type attestationClaim struct {
	Identity           *remoteIdentity `json:"identity"`
	ChallengeNonce     string          `json:"challengeNonce"`
	ChallengeSignature string          `json:"challengeSignature"`
}

var (
	errOfferClaimed  = errors.New("offer claimed by another identity")
	errOfferRevoked  = errors.New("offer revoked")
	errOfferMismatch = errors.New("offer made for another identity")
)

// claimAttestationOffer accepts an offer and issues the credential.
//
// The order is the order of cost: the offer and the identity's shape are
// checked first, then the one-time challenge is spent, and only an identity
// that proved its key has its issuing server asked about it.
func claimAttestationOffer(app core.App, root *server.RootKey, token string, body attestationClaim) (string, *util.AppError, int) {
	f := util.Fields.Attestation
	offer, appErr, status := findAttestationOffer(app, token)
	if appErr != nil {
		return "", appErr, status
	}
	id := body.Identity
	if id == nil {
		return "", &util.Errors.IdentityRequired, http.StatusBadRequest
	}
	id.Fingerprint = strings.ToLower(strings.TrimSpace(id.Fingerprint))
	domain, ok := util.NormalizePeerDomain(id.DomainAtIssue)
	if !ok || !server.ValidIdentityFingerprint(id.Fingerprint) {
		return "", &util.Errors.RemoteIdentityInvalid, http.StatusForbidden
	}
	id.DomainAtIssue = domain
	sum := sha256.Sum256([]byte(id.Certificate))
	if hex.EncodeToString(sum[:]) != id.Fingerprint {
		return "", &util.Errors.RemoteIdentityInvalid, http.StatusForbidden
	}
	if bound := offer.GetString(f.SubjectFingerprint); bound != "" && bound != id.Fingerprint {
		if offer.GetString(f.Status) == util.StatusActive {
			return "", &util.Errors.AttestationOfferClaimed, http.StatusGone
		}
		return "", &util.Errors.AttestationIdentityMismatch, http.StatusForbidden
	}

	holderPub, err := util.PublicKeyFromPEM(id.Certificate)
	if err != nil {
		return "", &util.Errors.RemoteIdentityInvalid, http.StatusForbidden
	}
	holderKey, err := server.JWKFromPublicKey(holderPub)
	if err != nil {
		return "", &util.Errors.AttestationKeyUnsupported, http.StatusBadRequest
	}

	if body.ChallengeNonce == "" || body.ChallengeSignature == "" {
		return "", &util.Errors.ChallengeRequired, http.StatusUnauthorized
	}
	if !ConsumeChallenge(body.ChallengeNonce, challengeScopeAttestation, token, id.ID) {
		return "", &util.Errors.ChallengeInvalid, http.StatusUnauthorized
	}
	if err := util.VerifySignature(id.Certificate, body.ChallengeNonce, body.ChallengeSignature); err != nil {
		return "", &util.Errors.SignatureInvalid, http.StatusUnauthorized
	}
	if appErr, status := verifyIdentityChain(app, root, id); appErr != nil {
		return "", appErr, status
	}

	keys, err := root.Credentials()
	if err != nil {
		app.Logger().Error("Credential key unavailable", "error", err)
		return "", &util.Errors.AttestationIssueFailed, http.StatusInternalServerError
	}

	credential := ""
	first := false
	err = app.RunInTransaction(func(tx core.App) error {
		// Read again inside the transaction: two identities may race for an
		// offer that was open when each of them looked.
		fresh, err := tx.FindRecordById(util.Coll.Attestations, offer.Id)
		if err != nil {
			return err
		}
		switch fresh.GetString(f.Status) {
		case util.StatusRevoked:
			return errOfferRevoked
		case util.StatusActive:
			if fresh.GetString(f.SubjectFingerprint) != id.Fingerprint {
				return errOfferClaimed
			}
		default:
			if bound := fresh.GetString(f.SubjectFingerprint); bound != "" && bound != id.Fingerprint {
				return errOfferMismatch
			}
			first = true
			fresh.Set(f.Status, util.StatusActive)
			fresh.Set(f.SubjectFingerprint, id.Fingerprint)
			fresh.Set(f.SubjectDomain, id.DomainAtIssue)
			fresh.Set(f.SubjectName, truncateRunes(id.Name, 255))
			fresh.Set(f.IssuedAt, types.NowDateTime())
			if err := tx.Save(fresh); err != nil {
				return err
			}
		}

		idx, err := services.AllocateAttestationStatus(tx, fresh.Id)
		if err != nil {
			return err
		}
		claims := map[string]any{}
		if err := fresh.UnmarshalJSONField(f.Claims, &claims); err != nil {
			return err
		}
		// The same attestation states the same thing every time it is handed
		// out: its first issue date, and its one position in the status list.
		spec := server.CredentialSpec{
			Issuer:    services.CredentialIssuer(root.Domain()),
			Type:      fresh.GetString(f.Type),
			Holder:    server.HolderRef{Fingerprint: id.Fingerprint, Domain: id.DomainAtIssue},
			HolderKey: holderKey,
			Claims:    claims,
			IssuedAt:  fresh.GetDateTime(f.IssuedAt).Time(),
			Status:    &server.StatusRef{Idx: idx, URI: services.CredentialStatusURI(root.Domain())},
		}
		if until := fresh.GetDateTime(f.ExpiresAt); !until.IsZero() {
			spec.ExpiresAt = until.Time()
		}
		credential, err = keys.IssueCredential(spec)
		offer = fresh
		return err
	})
	switch {
	case errors.Is(err, errOfferRevoked):
		return "", &util.Errors.AttestationOfferRevoked, http.StatusGone
	case errors.Is(err, errOfferClaimed):
		return "", &util.Errors.AttestationOfferClaimed, http.StatusGone
	case errors.Is(err, errOfferMismatch):
		return "", &util.Errors.AttestationIdentityMismatch, http.StatusForbidden
	case err != nil:
		app.Logger().Error("Failed to issue a credential", "error", err, "attestation", offer.Id)
		return "", &util.Errors.AttestationIssueFailed, http.StatusInternalServerError
	}

	if first {
		what := offer.GetString(f.Label)
		if what == "" {
			what = offer.GetString(f.Type)
		}
		services.EmitNotification(app, offer.GetString(f.User), offer.GetString(f.Workspace),
			util.NotificationAttestationAccepted,
			"Attestation accepted",
			"\""+what+"\" was accepted by "+offer.GetString(f.SubjectName)+" ("+id.DomainAtIssue+").",
			util.Coll.Attestations, offer.Id)
		app.Logger().Info("Credential issued", "attestation", offer.Id, "holder", id.DomainAtIssue)
	}
	return credential, nil, http.StatusOK
}

// verifyIdentityChain checks that an identity which just proved its key still
// stands: with this server's own records when it issued the identity, and
// with the issuing server — DNS pin, root key, parent signature, current
// status — when another did.
func verifyIdentityChain(app core.App, root *server.RootKey, id *remoteIdentity) (*util.AppError, int) {
	if strings.EqualFold(id.DomainAtIssue, root.Domain()) {
		rec, err := app.FindFirstRecordByFilter(util.Coll.Identities,
			util.Fields.Identity.Fingerprint+" = {:f}", dbx.Params{"f": id.Fingerprint})
		if err != nil || rec == nil || rec.GetString(util.Fields.Identity.Certificate) != id.Certificate {
			return &util.Errors.RemoteIdentityInvalid, http.StatusForbidden
		}
		if !services.IdentityIsActive(rec) {
			return &util.Errors.IdentityRevoked, http.StatusForbidden
		}
		return nil, http.StatusOK
	}

	rootPub, err := services.PeerRootKey(id.DomainAtIssue)
	if err != nil {
		return &util.Errors.RemoteIdentityInvalid, http.StatusForbidden
	}
	if err := server.VerifyParentSignature(rootPub, id.Fingerprint, id.ParentSignature); err != nil {
		return &util.Errors.RemoteIdentityInvalid, http.StatusForbidden
	}
	assertion, err := services.FetchPeerIdentityStatus(id.DomainAtIssue, id.Fingerprint)
	if err != nil {
		return &util.Errors.RemoteIdentityInvalid, http.StatusForbidden
	}
	status, err := server.VerifyIdentityStatus(assertion, rootPub, id.DomainAtIssue, id.Fingerprint, time.Now())
	if err != nil {
		return &util.Errors.RemoteIdentityInvalid, http.StatusForbidden
	}
	if status.Status != server.IdentityStatusActive {
		return &util.Errors.IdentityRevoked, http.StatusForbidden
	}
	return nil, http.StatusOK
}

// relayAttestationClaim accepts an offer for a person signed in here, and
// keeps the credential for them.
//
// The app signs the issuer's challenge on the device, where the identity key
// is; this server adds the identity's public half, asks the issuer — itself,
// when the offer is its own — and checks what comes back before keeping it:
// the issuer that was asked signed it, and it is bound to the identity that
// asked. The credential is stored once per attestation: accepting again
// replaces the copy.
func relayAttestationClaim(app core.App, root *server.RootKey, re *core.RequestEvent) error {
	if re.Auth == nil || re.Auth.Collection().Name != util.Coll.Users {
		return appErrorResponse(re, http.StatusUnauthorized, &util.Errors.NotAuthenticated)
	}
	if !allowRequest(re, grantPeerLimiter, "claim|"+re.Auth.Id) {
		return rateLimitedResponse(re)
	}
	var body struct {
		Origin             string `json:"origin"`
		Token              string `json:"token"`
		IdentityId         string `json:"identityId"`
		ChallengeNonce     string `json:"challengeNonce"`
		ChallengeSignature string `json:"challengeSignature"`
	}
	_ = re.BindBody(&body)
	if body.Token == "" || len(body.Token) > maxOfferTokenLength {
		return appErrorResponse(re, http.StatusNotFound, &util.Errors.AttestationOfferNotFound)
	}

	idRec, err := app.FindRecordById(util.Coll.Identities, body.IdentityId)
	if err != nil || idRec == nil || idRec.GetString(util.Fields.Identity.User) != re.Auth.Id {
		return appErrorResponse(re, http.StatusForbidden, &util.Errors.IdentityNotOwned)
	}
	if !services.IdentityIsActive(idRec) {
		return appErrorResponse(re, http.StatusForbidden, &util.Errors.IdentityRevoked)
	}
	identity := &remoteIdentity{
		ID:              idRec.Id,
		Name:            idRec.GetString(util.Fields.Identity.Name),
		Fingerprint:     idRec.GetString(util.Fields.Identity.Fingerprint),
		Certificate:     idRec.GetString(util.Fields.Identity.Certificate),
		ParentSignature: idRec.GetString(util.Fields.Identity.ParentSignature),
		DomainAtIssue:   idRec.GetString(util.Fields.Identity.DomainAtIssue),
	}
	holderPub, err := util.PublicKeyFromPEM(identity.Certificate)
	if err != nil {
		return appErrorResponse(re, http.StatusBadRequest, &util.Errors.AttestationKeyUnsupported)
	}
	holderKey, err := server.JWKFromPublicKey(holderPub)
	if err != nil {
		return appErrorResponse(re, http.StatusBadRequest, &util.Errors.AttestationKeyUnsupported)
	}
	claim := attestationClaim{
		Identity:           identity,
		ChallengeNonce:     body.ChallengeNonce,
		ChallengeSignature: body.ChallengeSignature,
	}

	// No origin means the offer is this server's own.
	issuer, credential := root.Domain(), ""
	base := ""
	if strings.TrimSpace(body.Origin) != "" {
		domain, peerBase, ok := util.PeerDomainForOrigin(body.Origin)
		if !ok {
			return appErrorResponse(re, http.StatusBadRequest, &util.Errors.RemoteOriginInvalid)
		}
		if !strings.EqualFold(domain, root.Domain()) {
			issuer, base = domain, peerBase
		}
	}
	if base == "" {
		issued, appErr, status := claimAttestationOffer(app, root, body.Token, claim)
		if appErr != nil {
			return appErrorResponse(re, status, appErr)
		}
		credential = issued
	} else {
		var out struct {
			Credential string `json:"credential"`
		}
		target := base + "/api/attestations/offers/" + url.PathEscape(body.Token) + "/claim"
		if perr, err := peerJSON(http.MethodPost, target, claim, &out); err != nil {
			return appErrorResponse(re, http.StatusBadGateway, &util.Errors.RemoteUnreachable)
		} else if perr != nil {
			return peerErrorResponse(re, perr)
		}
		credential = out.Credential
	}

	stated, err := services.CheckIssuedCredential(root, credential, issuer, holderKey,
		server.HolderRef{Fingerprint: identity.Fingerprint, Domain: identity.DomainAtIssue}, time.Now())
	if err != nil {
		app.Logger().Warn("An issued credential did not verify", "issuer", issuer, "error", err)
		return appErrorResponse(re, http.StatusBadGateway, &util.Errors.CredentialInvalid)
	}

	rec, err := saveCredential(app, re.Auth, idRec, issuer, credential, stated)
	if err != nil {
		app.Logger().Error("Failed to keep a credential", "error", err)
		return re.InternalServerError("Failed to keep the credential", nil)
	}
	re.Response.Header().Set("Cache-Control", "no-store")
	return re.JSON(http.StatusOK, rec.PublicExport())
}

// saveCredential keeps a credential for its holder: one row per attestation,
// recognised by its place in the issuer's status list, so accepting an offer
// again replaces the copy instead of adding a second.
func saveCredential(app core.App, auth, identity *core.Record, issuer, credential string, stated server.CredentialVerification) (*core.Record, error) {
	f := util.Fields.Credential
	var rec *core.Record
	if stated.Status != nil {
		existing, _ := app.FindAllRecords(util.Coll.Credentials, dbx.HashExp{
			f.User: auth.Id, f.Identity: identity.Id, f.Issuer: issuer,
		})
		for _, row := range existing {
			p, err := server.ParseCredential(row.GetString(f.Credential))
			if err != nil {
				continue
			}
			if sameStatusRef(p.Payload["status"], stated.Status) {
				rec = row
				break
			}
		}
	}
	if rec == nil {
		col, err := app.FindCollectionByNameOrId(util.Coll.Credentials)
		if err != nil {
			return nil, err
		}
		rec = core.NewRecord(col)
		rec.Set(f.User, auth.Id)
		rec.Set(f.Workspace, identity.GetString(util.Fields.Identity.Workspace))
		rec.Set(f.Identity, identity.Id)
		rec.Set(f.Issuer, issuer)
	}
	rec.Set(f.Type, stated.Type)
	rec.Set(f.Credential, credential)
	rec.Set(f.Claims, stated.Claims)
	rec.Set(f.IssuedAt, nil)
	rec.Set(f.ExpiresAt, nil)
	if !stated.IssuedAt.IsZero() {
		at, _ := types.ParseDateTime(stated.IssuedAt)
		rec.Set(f.IssuedAt, at)
	}
	if !stated.ExpiresAt.IsZero() {
		at, _ := types.ParseDateTime(stated.ExpiresAt)
		rec.Set(f.ExpiresAt, at)
	}
	if err := app.Save(rec); err != nil {
		return nil, err
	}
	return rec, nil
}

// sameStatusRef reports whether a credential's status claim points at ref.
func sameStatusRef(raw any, ref *server.StatusRef) bool {
	status, ok := raw.(map[string]any)
	if !ok {
		return false
	}
	list, ok := status["status_list"].(map[string]any)
	if !ok {
		return false
	}
	idx, _ := list["idx"].(float64)
	uri, _ := list["uri"].(string)
	return uri == ref.URI && int(idx) == ref.Idx
}
