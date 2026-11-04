package routes

import (
	"bytes"
	"encoding/json"
	"html/template"
	"net/http"
	"revoked/cmd/revoked/server"
	"revoked/cmd/revoked/services"
	"revoked/util"
	"sort"
	"strings"
	"time"

	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tools/types"
)

// AttestationSharesRoute lets a holder make a link that shows one of their
// attestations to whoever opens it:
//
//	POST /api/attestation-shares                    the holder starts a link
//	POST /api/attestation-shares/{id}/activate      the holder signs it
//	POST /api/attestation-shares/{id}/revoke        the holder ends it
//	GET  /api/public/attestation-shares/{token}     anyone with the link reads it
//	GET  /p/{token}                                 the same, as a page
//
// Starting a link gives the app a nonce and an audience; the app makes a
// presentation of the details the holder picked, bound to both, and the
// server keeps it once it verifies. Whoever opens the link sees what the
// issuer attests and whether it still stands, checked again on every view.
//
// What the link proves is that the holder showed this. It does not prove that
// whoever sends the link on is the holder: anyone who has it can pass it on.
// Proving that takes a check, which is answered live.
func AttestationSharesRoute(app core.App, root *server.RootKey) {
	app.OnServe().BindFunc(func(e *core.ServeEvent) error {
		e.Router.POST("/api/attestation-shares", func(re *core.RequestEvent) error {
			return createAttestationShare(app, root, re)
		})
		e.Router.POST("/api/attestation-shares/{id}/activate", func(re *core.RequestEvent) error {
			return activateAttestationShare(app, root, re)
		})
		e.Router.POST("/api/attestation-shares/{id}/revoke", func(re *core.RequestEvent) error {
			return revokeAttestationShare(app, re)
		})
		e.Router.GET("/api/public/attestation-shares/{token}", func(re *core.RequestEvent) error {
			return viewAttestationShare(app, root, re, false)
		})
		e.Router.GET("/p/{token}", func(re *core.RequestEvent) error {
			return viewAttestationShare(app, root, re, wantsHTML(re.Request.Header.Get("Accept")))
		})
		return e.Next()
	})
}

// The holder's own share, or why not. Someone else's reads as missing.
func ownedShare(app core.App, re *core.RequestEvent) (*core.Record, *util.AppError, int) {
	if re.Auth == nil || re.Auth.Collection().Name != util.Coll.Users {
		return nil, &util.Errors.NotAuthenticated, http.StatusUnauthorized
	}
	share, err := app.FindRecordById(util.Coll.AttestationShares, re.Request.PathValue("id"))
	if err != nil || share.GetString(util.Fields.AttestationShare.User) != re.Auth.Id {
		return nil, &util.Errors.AttestationShareNotFound, http.StatusNotFound
	}
	return share, nil, 0
}

func createAttestationShare(app core.App, root *server.RootKey, re *core.RequestEvent) error {
	// An API key has no attestation of its own to show.
	if re.Auth == nil || re.Auth.Collection().Name != util.Coll.Users {
		return appErrorResponse(re, http.StatusUnauthorized, &util.Errors.NotAuthenticated)
	}
	if !allowRequest(re, grantPeerLimiter, "share|"+re.Auth.Id) {
		return rateLimitedResponse(re)
	}
	var body struct {
		Credential string `json:"credential"`
		Days       int    `json:"days"`
	}
	if err := re.BindBody(&body); err != nil {
		return appErrorResponse(re, http.StatusBadRequest, &util.Errors.AttestationShareInvalid)
	}
	ttl := time.Duration(body.Days) * 24 * time.Hour
	if body.Days < 1 || ttl > util.AttestationShareMaxTTL {
		return appErrorResponse(re, http.StatusBadRequest, &util.Errors.AttestationShareInvalid)
	}
	credential, err := app.FindRecordById(util.Coll.Credentials, strings.TrimSpace(body.Credential))
	if err != nil || credential.GetString(util.Fields.Credential.User) != re.Auth.Id {
		return appErrorResponse(re, http.StatusBadRequest, &util.Errors.AttestationShareInvalid)
	}

	nonce, err := util.GenerateToken(32)
	if err != nil {
		return re.InternalServerError("Failed to create the link", err)
	}
	collection, err := app.FindCollectionByNameOrId(util.Coll.AttestationShares)
	if err != nil {
		return re.InternalServerError("Failed to create the link", err)
	}
	f := util.Fields.AttestationShare
	audience := checkOrigin(re, root)
	expires := time.Now().UTC().Add(ttl)
	share := core.NewRecord(collection)
	share.Set(f.User, re.Auth.Id)
	share.Set(f.Credential, credential.Id)
	share.Set(f.Status, util.ShareLinkPending)
	share.Set(f.Nonce, nonce)
	share.Set(f.Audience, audience)
	share.Set(f.ExpiresAt, expires)
	if err := app.Save(share); err != nil {
		return re.InternalServerError("Failed to create the link", err)
	}

	re.Response.Header().Set("Cache-Control", "no-store")
	return re.JSON(http.StatusOK, map[string]any{
		"id":        share.Id,
		"audience":  audience,
		"nonce":     nonce,
		"expiresAt": expires.Format(time.RFC3339),
	})
}

// activateAttestationShare takes the holder's presentation for a pending
// link, verifies it against the link's own audience and nonce, and opens the
// link. Only the identity the attestation was issued to can make one that
// verifies, so a copy of someone else's credential is refused here.
func activateAttestationShare(app core.App, root *server.RootKey, re *core.RequestEvent) error {
	share, appErr, status := ownedShare(app, re)
	if appErr != nil {
		return appErrorResponse(re, status, appErr)
	}
	f := util.Fields.AttestationShare
	now := time.Now().UTC()
	if share.GetString(f.Status) != util.ShareLinkPending ||
		now.Sub(share.GetDateTime(f.Created).Time()) > util.AttestationSharePendingTTL {
		return appErrorResponse(re, http.StatusGone, &util.Errors.AttestationShareClosed)
	}
	var body struct {
		Presentation string `json:"presentation"`
	}
	if err := re.BindBody(&body); err != nil || strings.TrimSpace(body.Presentation) == "" {
		return appErrorResponse(re, http.StatusBadRequest, &util.Errors.PresentationInvalid)
	}

	verdict := services.VerifyPresentation(app, root, body.Presentation, services.VerifyOptions{
		Audience: share.GetString(f.Audience),
		Nonce:    share.GetString(f.Nonce),
	}, now)
	if !shareableVerdict(verdict) || !heldBy(app, share, verdict) {
		return appErrorResponse(re, http.StatusBadRequest, &util.Errors.PresentationInvalid)
	}

	token, err := util.GenerateToken(32)
	if err != nil {
		return re.InternalServerError("Failed to open the link", err)
	}
	disclosed := make([]string, 0, len(verdict.Claims))
	for name := range verdict.Claims {
		disclosed = append(disclosed, name)
	}
	sort.Strings(disclosed)
	share.Set(f.Presentation, strings.TrimSpace(body.Presentation))
	share.Set(f.Disclosed, disclosed)
	share.Set(f.TokenHash, util.HashToken(token))
	share.Set(f.Status, util.ShareLinkActive)
	if err := app.Save(share); err != nil {
		return re.InternalServerError("Failed to open the link", err)
	}

	re.Response.Header().Set("Cache-Control", "no-store")
	return re.JSON(http.StatusOK, map[string]any{
		"id":        share.Id,
		"token":     token,
		"url":       share.GetString(f.Audience) + "/p/" + token,
		"expiresAt": share.GetDateTime(f.ExpiresAt).Time().UTC().Format(time.RFC3339),
		"disclosed": disclosed,
	})
}

// shareableVerdict holds back what no link should show: something that does
// not verify as the holder's, or an attestation that no longer stands.
func shareableVerdict(v services.AttestationVerdict) bool {
	if !v.KeyBound {
		return false
	}
	switch v.State {
	case services.AttestationInvalid, services.AttestationSpoofed,
		services.AttestationRevoked, services.AttestationExpired:
		return false
	}
	return true
}

// heldBy says whether the presentation was made by the identity the shared
// credential belongs to: the holder named in it is that identity.
func heldBy(app core.App, share *core.Record, v services.AttestationVerdict) bool {
	if v.Holder == nil || v.Holder.Fingerprint == "" {
		return false
	}
	credential, err := app.FindRecordById(util.Coll.Credentials, share.GetString(util.Fields.AttestationShare.Credential))
	if err != nil {
		return false
	}
	identity, err := app.FindRecordById(util.Coll.Identities, credential.GetString(util.Fields.Credential.Identity))
	if err != nil {
		return false
	}
	return strings.EqualFold(identity.GetString(util.Fields.Identity.Fingerprint), v.Holder.Fingerprint)
}

func revokeAttestationShare(app core.App, re *core.RequestEvent) error {
	share, appErr, status := ownedShare(app, re)
	if appErr != nil {
		return appErrorResponse(re, status, appErr)
	}
	f := util.Fields.AttestationShare
	if share.GetString(f.Status) != util.ShareLinkRevoked {
		share.Set(f.Status, util.ShareLinkRevoked)
		if err := app.Save(share); err != nil {
			return re.InternalServerError("Failed to end the link", err)
		}
	}
	re.Response.Header().Set("Cache-Control", "no-store")
	return re.JSON(http.StatusOK, map[string]any{"id": share.Id, "status": util.ShareLinkRevoked})
}

// openShare finds an active, unexpired link by its token.
func openShare(app core.App, token string) (*core.Record, *util.AppError, int) {
	token = strings.TrimSpace(token)
	if token == "" {
		return nil, &util.Errors.AttestationShareNotFound, http.StatusNotFound
	}
	f := util.Fields.AttestationShare
	share, err := app.FindFirstRecordByData(util.Coll.AttestationShares, f.TokenHash, util.HashToken(token))
	if err != nil || share == nil {
		return nil, &util.Errors.AttestationShareNotFound, http.StatusNotFound
	}
	if share.GetString(f.Status) != util.ShareLinkActive ||
		!share.GetDateTime(f.ExpiresAt).Time().After(time.Now()) {
		return nil, &util.Errors.AttestationShareClosed, http.StatusGone
	}
	return share, nil, 0
}

// sharedAttestation is what a link shows.
type sharedAttestation struct {
	services.AttestationVerdict
	HolderName    string `json:"holderName,omitempty"`
	SharedAt      string `json:"sharedAt"`
	LinkExpiresAt string `json:"linkExpiresAt"`
}

// viewAttestationShare shows what the link holds. The presentation's key
// binding was checked when the holder made the link and is not checked again:
// it would be too old by now. Everything that can change — whether the issuer
// still stands behind it, whether it expired, whether the holder's identity
// was revoked — is checked on every view.
func viewAttestationShare(app core.App, root *server.RootKey, re *core.RequestEvent, html bool) error {
	if !allowRequest(re, probeLimiter, "") {
		return rateLimitedResponse(re)
	}
	share, appErr, status := openShare(app, re.Request.PathValue("token"))
	if appErr != nil {
		if html {
			return linkStatusPage(re, "This link is not available", appErr.ErrorText, status)
		}
		return appErrorResponse(re, status, appErr)
	}
	f := util.Fields.AttestationShare
	now := time.Now().UTC()
	verdict := services.VerifyPresentation(app, root, share.GetString(f.Presentation), services.VerifyOptions{
		SkipKeyBinding: true,
	}, now)
	verdict.KeyBound = true
	if verdict.State == services.AttestationVerified {
		verdict.Reason = verdict.Issuer + " attests this, its key is tied to the domain through DNS, " +
			"the attestation still stands, and its holder signed this link."
	}
	shown := sharedAttestation{
		AttestationVerdict: verdict,
		SharedAt:           share.GetDateTime(f.Created).Time().UTC().Format(time.RFC3339),
		LinkExpiresAt:      share.GetDateTime(f.ExpiresAt).Time().UTC().Format(time.RFC3339),
	}
	if credential, err := app.FindRecordById(util.Coll.Credentials, share.GetString(f.Credential)); err == nil {
		if identity, err := app.FindRecordById(util.Coll.Identities, credential.GetString(util.Fields.Credential.Identity)); err == nil {
			shown.HolderName = identity.GetString(util.Fields.Identity.Name)
		}
	}

	// Counted for the holder, who sees how often the link was opened. A lost
	// update under a burst of views is acceptable; a failed one is not fatal.
	_, _ = app.DB().NewQuery(`
		UPDATE {{attestationShares}}
		SET viewCount = viewCount + 1, lastViewedAt = {:now}
		WHERE id = {:id}
	`).Bind(dbx.Params{"now": types.NowDateTime().String(), "id": share.Id}).Execute()

	re.Response.Header().Set("Cache-Control", "no-store")
	re.Response.Header().Set("Referrer-Policy", "no-referrer")
	if html {
		return renderSharedAttestation(re, root, shown)
	}
	return re.JSON(http.StatusOK, shown)
}

type sharedClaim struct{ Name, Value string }

func renderSharedAttestation(re *core.RequestEvent, root *server.RootKey, s sharedAttestation) error {
	claims := make([]sharedClaim, 0, len(s.Claims))
	for name, value := range s.Claims {
		claims = append(claims, sharedClaim{Name: name, Value: claimDisplay(value)})
	}
	sort.Slice(claims, func(i, j int) bool { return claims[i].Name < claims[j].Name })
	holder := ""
	if s.Holder != nil {
		holder = s.Holder.Fingerprint
	}
	data := map[string]any{
		"Type":        s.Type,
		"Issuer":      s.Issuer,
		"State":       s.State,
		"Verified":    s.State == services.AttestationVerified,
		"Reason":      s.Reason,
		"Claims":      claims,
		"Withheld":    s.Withheld,
		"HolderName":  s.HolderName,
		"HolderPrint": holder,
		"SharedAt":    shortDay(s.SharedAt),
		"LinkExpires": shortDay(s.LinkExpiresAt),
		"Domain":      root.Domain(),
	}
	var buf bytes.Buffer
	if err := sharedAttestationTemplate.Execute(&buf, data); err != nil {
		return re.InternalServerError("Failed to render the page.", err)
	}
	h := re.Response.Header()
	h.Set("Content-Security-Policy", pageCSP)
	h.Set("X-Content-Type-Options", "nosniff")
	return writeText(re, "text/html", buf.String())
}

func claimDisplay(v any) string {
	switch x := v.(type) {
	case bool:
		if x {
			return "Yes"
		}
		return "No"
	case string:
		return x
	case nil:
		return "—"
	default:
		b, err := json.Marshal(x)
		if err != nil {
			return "—"
		}
		return string(b)
	}
}

func shortDay(rfc string) string {
	t, err := time.Parse(time.RFC3339, rfc)
	if err != nil {
		return rfc
	}
	return t.Format("2 Jan 2006")
}

var sharedAttestationTemplate = template.Must(template.New("shared").Funcs(brandFuncs).Parse(`<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex, nofollow">
<link rel="icon" type="image/svg+xml" href="{{logoLight}}" media="(prefers-color-scheme: light)">
<link rel="icon" type="image/svg+xml" href="{{logoDark}}" media="(prefers-color-scheme: dark)">
<title>{{if .Type}}{{.Type}}{{else}}Attestation{{end}} · Revoked</title>
<style>` + pageTokens + `
* { box-sizing: border-box; margin: 0; padding: 0; }
body { margin: 0; background: var(--bg); color: var(--fg); font-family: var(--font-sans); font-size: 16px; line-height: 1.45; }
header { border-bottom: 1px solid var(--border); background: var(--surface); padding: 12px 20px; }
.nav { max-width: 600px; margin: 0 auto; display: flex; align-items: center; gap: 8px; font-weight: 700; font-size: 15px; }
.logo { width: 24px; height: 24px; }
.logo-dark { display: none; }
html[data-theme="dark"] .logo-light { display: none; }
html[data-theme="dark"] .logo-dark { display: block; }
@media (prefers-color-scheme: dark) {
html:not([data-theme="light"]) .logo-light { display: none; }
html:not([data-theme="light"]) .logo-dark { display: block; }
}
main { max-width: 600px; margin: 32px auto; padding: 0 16px; }
h1 { font-size: 22px; font-weight: 650; letter-spacing: -0.02em; margin-bottom: 4px; }
.muted { color: var(--fg-muted); font-size: 14px; }
.card { background: var(--surface); border: 1px solid var(--border); margin-top: 16px; }
.row { display: flex; justify-content: space-between; gap: 16px; padding: 12px 16px; border-top: 1px solid var(--border); }
.row:first-child { border-top: 0; }
.row .k { color: var(--fg-muted); }
.row .v { text-align: right; overflow-wrap: anywhere; }
.mono { font-family: var(--font-mono, ui-monospace, monospace); font-size: 13px; }
.state { display: inline-block; padding: 2px 8px; font-size: 13px; font-weight: 600; border: 1px solid currentColor; }
.ok { color: var(--success, #16a34a); }
.warn { color: var(--warning, #d97706); }
h2 { font-size: 15px; font-weight: 600; margin-top: 24px; }
p.note { margin-top: 16px; color: var(--fg-muted); font-size: 14px; }
</style>
</head>
<body>
<header><div class="nav">
<img class="logo logo-light" src="{{logoLight}}" alt="">
<img class="logo logo-dark" src="{{logoDark}}" alt="">
<span>Revoked</span>
</div></header>
<main>
<h1>{{if .Type}}{{.Type}}{{else}}Attestation{{end}}</h1>
<p class="muted">Attested by {{.Issuer}}{{if .HolderName}}, shown by {{.HolderName}}{{end}}</p>
<div class="card">
<div class="row"><span class="k">Status</span><span class="v"><span class="state {{if .Verified}}ok{{else}}warn{{end}}">{{if .Verified}}Verified{{else}}{{.State}}{{end}}</span></span></div>
<div class="row"><span class="k">Attested by</span><span class="v">{{.Issuer}}</span></div>
{{if .HolderPrint}}<div class="row"><span class="k">Holder identity</span><span class="v mono">{{.HolderPrint}}</span></div>{{end}}
<div class="row"><span class="k">Shared</span><span class="v">{{.SharedAt}}</span></div>
<div class="row"><span class="k">Link open until</span><span class="v">{{.LinkExpires}}</span></div>
</div>
<p class="note">{{.Reason}}</p>
<h2>Details</h2>
<div class="card">
{{range .Claims}}<div class="row"><span class="k mono">{{.Name}}</span><span class="v">{{.Value}}</span></div>
{{else}}<div class="row"><span class="k">No details beyond the kind.</span></div>
{{end}}{{if .Withheld}}<div class="row"><span class="k">Withheld by the holder</span><span class="v">{{.Withheld}}</span></div>{{end}}
</div>
<p class="note">The holder signed this link with the key of the identity the attestation was issued to. Its status is checked each time the page is opened. The link shows what the holder chose to share; it does not prove that whoever sent it is the holder.</p>
</main>
</body>
</html>`))
