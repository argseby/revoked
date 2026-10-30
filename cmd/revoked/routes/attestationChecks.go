package routes

import (
	"encoding/json"
	"net/http"
	"revoked/cmd/revoked/server"
	"revoked/cmd/revoked/services"
	"revoked/util"
	"strings"
	"time"

	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tools/types"
)

// AttestationChecksRoute lets one person ask another to show an attestation,
// with this server standing in for the service that would otherwise ask:
//
//	POST /api/attestation-checks                     the asker makes a check
//	GET  /api/public/attestation-checks/{id}         the other app reads who asks
//	POST /api/public/attestation-checks/answer       the other app answers
//
// The check is answered through the ordinary present link: its audience is
// this server's origin, its nonce is the check's own, and its state is the
// check's id. The answer is verified on arrival and only the verdict is kept.
func AttestationChecksRoute(app core.App, root *server.RootKey) {
	app.OnServe().BindFunc(func(e *core.ServeEvent) error {
		e.Router.POST("/api/attestation-checks", func(re *core.RequestEvent) error {
			return createAttestationCheck(app, root, re)
		})
		e.Router.GET("/api/public/attestation-checks/{id}", func(re *core.RequestEvent) error {
			return probeAttestationCheck(app, root, re)
		})
		e.Router.POST("/api/public/attestation-checks/answer", func(re *core.RequestEvent) error {
			return answerAttestationCheck(app, root, re)
		})
		return e.Next()
	})
}

const (
	maxCheckIssuers = 20
	maxCheckClaims  = 50
)

// checkOrigin is the address this server answers at, as the asker's link
// names it. The other app posts its answer there and binds the presentation
// to it, so it must be the origin the asker's app reached.
func checkOrigin(re *core.RequestEvent, root *server.RootKey) string {
	host := pageOrigin(re, root)
	name := strings.Split(host, ":")[0]
	if isLoopbackName(name) {
		return "http://" + host
	}
	return "https://" + host
}

func createAttestationCheck(app core.App, root *server.RootKey, re *core.RequestEvent) error {
	// An API key has no person behind it to show the result to.
	if re.Auth == nil || re.Auth.Collection().Name != util.Coll.Users {
		return appErrorResponse(re, http.StatusUnauthorized, &util.Errors.NotAuthenticated)
	}
	if !allowRequest(re, grantPeerLimiter, "check|"+re.Auth.Id) {
		return rateLimitedResponse(re)
	}
	var body struct {
		Type       string   `json:"type"`
		Issuers    []string `json:"issuers"`
		Claims     []string `json:"claims"`
		IdentityID string   `json:"identityId"`
	}
	if err := re.BindBody(&body); err != nil {
		return appErrorResponse(re, http.StatusBadRequest, &util.Errors.AttestationCheckInvalid)
	}

	kind := strings.TrimSpace(body.Type)
	if kind != "" && !util.ValidAttestationType(kind) {
		return appErrorResponse(re, http.StatusBadRequest, &util.Errors.AttestationCheckInvalid)
	}
	issuers := []string{}
	for _, raw := range body.Issuers {
		domain, ok := util.NormalizePeerDomain(raw)
		if !ok || len(issuers) == maxCheckIssuers {
			return appErrorResponse(re, http.StatusBadRequest, &util.Errors.AttestationCheckInvalid)
		}
		issuers = append(issuers, domain)
	}
	claims := []string{}
	for _, name := range body.Claims {
		name = strings.TrimSpace(name)
		if ok, _ := util.ValidAttestationClaimName(name); !ok || len(claims) == maxCheckClaims {
			return appErrorResponse(re, http.StatusBadRequest, &util.Errors.AttestationCheckInvalid)
		}
		claims = append(claims, name)
	}

	// Identity ids are public, so a foreign one would let the asker appear to
	// the other person as someone else.
	identityID := strings.TrimSpace(body.IdentityID)
	if identityID != "" {
		identity, err := app.FindRecordById(util.Coll.Identities, identityID)
		if err != nil || identity.GetString(util.Fields.Identity.User) != re.Auth.Id ||
			!services.IdentityIsActive(identity) {
			return appErrorResponse(re, http.StatusForbidden, &util.Errors.IdentityNotOwned)
		}
	}

	nonce, err := util.GenerateToken(32)
	if err != nil {
		return re.InternalServerError("Failed to create the check", err)
	}
	collection, err := app.FindCollectionByNameOrId(util.Coll.AttestationChecks)
	if err != nil {
		return re.InternalServerError("Failed to create the check", err)
	}
	f := util.Fields.AttestationCheck
	audience := checkOrigin(re, root)
	expires := time.Now().UTC().Add(util.AttestationCheckTTL)
	check := core.NewRecord(collection)
	check.Set(f.User, re.Auth.Id)
	check.Set(f.Identity, identityID)
	check.Set(f.Type, kind)
	check.Set(f.Issuers, issuers)
	check.Set(f.Claims, claims)
	check.Set(f.Nonce, nonce)
	check.Set(f.Audience, audience)
	check.Set(f.Status, util.CheckStatusOpen)
	check.Set(f.ExpiresAt, expires)
	if err := app.Save(check); err != nil {
		return re.InternalServerError("Failed to create the check", err)
	}

	present := map[string]string{
		"client_id":    audience,
		"response_uri": audience + "/api/public/attestation-checks/answer",
		"nonce":        nonce,
		"state":        check.Id,
	}
	if kind != "" {
		present["type"] = kind
	}
	if len(issuers) > 0 {
		present["issuers"] = strings.Join(issuers, ",")
	}
	if len(claims) > 0 {
		present["claims"] = strings.Join(claims, ",")
	}
	re.Response.Header().Set("Cache-Control", "no-store")
	return re.JSON(http.StatusOK, map[string]any{
		"id":        check.Id,
		"expiresAt": expires.Format(time.RFC3339),
		"present":   present,
	})
}

// openCheck finds a check that can still be answered.
func openCheck(app core.App, id string) (*core.Record, *util.AppError, int) {
	check, err := app.FindRecordById(util.Coll.AttestationChecks, id)
	if err != nil || check == nil {
		return nil, &util.Errors.AttestationCheckNotFound, http.StatusNotFound
	}
	f := util.Fields.AttestationCheck
	if check.GetString(f.Status) != util.CheckStatusOpen ||
		!check.GetDateTime(f.ExpiresAt).Time().After(time.Now()) {
		return nil, &util.Errors.AttestationCheckClosed, http.StatusGone
	}
	return check, nil, 0
}

// probeAttestationCheck tells the other app who asks and what for, before
// anything is shown: the asker's identity as a request probe states its
// requester, so the app checks it along the same chain.
func probeAttestationCheck(app core.App, root *server.RootKey, re *core.RequestEvent) error {
	if !allowRequest(re, probeLimiter, "") {
		return rateLimitedResponse(re)
	}
	check, appErr, status := openCheck(app, re.Request.PathValue("id"))
	if appErr != nil {
		return appErrorResponse(re, status, appErr)
	}
	f := util.Fields.AttestationCheck
	asker := map[string]any{}
	if identity, err := app.FindRecordById(util.Coll.Identities, check.GetString(f.Identity)); err == nil {
		asker["name"] = identity.GetString(util.Fields.Identity.Name)
		asker["fingerprint"] = identity.GetString(util.Fields.Identity.Fingerprint)
		asker["parentSignature"] = identity.GetString(util.Fields.Identity.ParentSignature)
		asker["domainAtIssue"] = identity.GetString(util.Fields.Identity.DomainAtIssue)
		asker["status"] = services.IdentityStatusOf(identity)
		stapleIdentityStatus(app, root, asker, identity.GetString(util.Fields.Identity.Fingerprint))
	}
	re.Response.Header().Set("Cache-Control", "no-store")
	return re.JSON(http.StatusOK, map[string]any{
		"asker":     asker,
		"expiresAt": check.GetDateTime(f.ExpiresAt).Time().UTC().Format(time.RFC3339),
		"server": map[string]any{
			"domain":          root.Domain(),
			"rootFingerprint": root.Fingerprint(),
		},
	})
}

// answerAttestationCheck takes the other person's presentation, verifies it
// against the check's own audience and nonce, and keeps the verdict. A check
// is answered once: the verdict is written by a single guarded UPDATE, so two
// answers racing each other cannot both land.
func answerAttestationCheck(app core.App, root *server.RootKey, re *core.RequestEvent) error {
	if !allowRequest(re, grantPeerLimiter, "check-answer") {
		return rateLimitedResponse(re)
	}
	var body struct {
		Presentation string `json:"presentation"`
		State        string `json:"state"`
	}
	if err := re.BindBody(&body); err != nil || strings.TrimSpace(body.Presentation) == "" {
		return appErrorResponse(re, http.StatusBadRequest, &util.Errors.PresentationInvalid)
	}
	check, appErr, status := openCheck(app, body.State)
	if appErr != nil {
		return appErrorResponse(re, status, appErr)
	}

	f := util.Fields.AttestationCheck
	verdict := services.VerifyPresentation(app, root, body.Presentation, services.VerifyOptions{
		Audience: check.GetString(f.Audience),
		Nonce:    check.GetString(f.Nonce),
	}, time.Now())
	// Something that is not a presentation at all does not use up the check:
	// whoever saw the code could otherwise spend it with garbage.
	if verdict.State == services.AttestationInvalid {
		return appErrorResponse(re, http.StatusBadRequest, &util.Errors.PresentationInvalid)
	}

	result, err := json.Marshal(verdict)
	if err != nil {
		return re.InternalServerError("Failed to keep the answer", err)
	}
	now := types.NowDateTime()
	res, err := app.DB().NewQuery(`
		UPDATE {{attestationChecks}}
		SET status = {:answered}, result = {:result}, answeredAt = {:now}, updated = {:now}
		WHERE id = {:id} AND status = {:open} AND expiresAt > {:now}
	`).Bind(dbx.Params{
		"answered": util.CheckStatusAnswered,
		"open":     util.CheckStatusOpen,
		"result":   string(result),
		"now":      now.String(),
		"id":       check.Id,
	}).Execute()
	if err != nil {
		return re.InternalServerError("Failed to keep the answer", err)
	}
	if affected, err := res.RowsAffected(); err != nil || affected == 0 {
		return appErrorResponse(re, http.StatusGone, &util.Errors.AttestationCheckClosed)
	}

	title := "An attestation was shown to you"
	if verdict.State != services.AttestationVerified {
		title = "An attestation was shown to you, and did not verify"
	}
	what := verdict.Type
	if what == "" {
		what = "An attestation"
	}
	if verdict.Issuer != "" {
		what += " from " + verdict.Issuer
	}
	// A check belongs to a person, not a workspace; the notice goes where
	// they are working now.
	if asker, err := app.FindRecordById(util.Coll.Users, check.GetString(f.User)); err == nil {
		services.EmitNotification(app, asker.Id,
			asker.GetString(util.Fields.User.ActiveWorkspace),
			util.NotificationAttestationChecked, title, what+".",
			util.Coll.AttestationChecks, check.Id)
	}

	re.Response.Header().Set("Cache-Control", "no-store")
	return re.JSON(http.StatusOK, map[string]any{"state": verdict.State})
}
