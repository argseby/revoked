package routes

import (
	"net/http"
	"revoked/cmd/revoked/server"
	"revoked/cmd/revoked/services"
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
)

// root is threaded in so the probe can publish this server's domain claim and
// root fingerprint — without them a viewer has nothing to walk the DNS chain
// against, and a signed share is indistinguishable from an unsigned one.
//
// PublicLinksRoute exposes the per-slug endpoint for a link's data. All gating
// (status, expiry, max views, password, handshake) is enforced here, never by client
// code, and there is deliberately no list/scan endpoint — the slug is the only way in.
func PublicLinksRoute(app core.App, root *server.RootKey) {
	app.OnServe().BindFunc(func(e *core.ServeEvent) error {

		// Probe: existence and gates only, never data.
		e.Router.GET("/api/public/links/{slug}", func(re *core.RequestEvent) error {
			if !allowRequest(re, probeLimiter, "") {
				return rateLimitedResponse(re)
			}
			slug := re.Request.PathValue("slug")
			link, err := app.FindFirstRecordByFilter(util.Coll.Links, "slug = {:slug}", map[string]any{"slug": slug})
			if err != nil || link == nil {
				return re.NotFoundError(util.Errors.LinkNotFound.ErrorText, nil)
			}

			if errResp := services.RefreshLinkStatus(app, link); errResp != nil {
				return resourceErrorResponse(re, errResp)
			}

			sharer := map[string]any{}
			if idRec, idErr := app.FindRecordById(util.Coll.Identities, link.GetString(util.Fields.Link.Identity)); idErr == nil && idRec != nil {
				sharer["identityId"] = idRec.Id
				sharer["name"] = idRec.GetString(util.Fields.Identity.Name)
				sharer["fingerprint"] = idRec.GetString(util.Fields.Identity.Fingerprint)
				sharer["parentSignature"] = idRec.GetString(util.Fields.Identity.ParentSignature)
				sharer["domainAtIssue"] = idRec.GetString(util.Fields.Identity.DomainAtIssue)
				sharer["status"] = services.IdentityStatusOf(idRec)
				stapleIdentityStatus(app, root, sharer, idRec.GetString(util.Fields.Identity.Fingerprint))
			}

			return re.JSON(http.StatusOK, map[string]any{
				"slug":             link.GetString(util.Fields.Link.Slug),
				"label":            link.GetString(util.Fields.Link.Label),
				"status":           link.GetString(util.Fields.Link.Status),
				"requiresPassword": link.GetString(util.Fields.Link.Password) != "",
				"requireHandshake": link.GetBool(util.Fields.Link.RequireHandshake),
				"identity":         link.GetString(util.Fields.Link.Identity),
				"sharer":           sharer,
				"server": map[string]any{
					"domain":          root.Domain(),
					"rootFingerprint": root.Fingerprint(),
				},
			})
		})

		// POST so the password and handshake token travel in the body, not the URL.
		e.Router.POST("/api/public/links/{slug}", func(re *core.RequestEvent) error {
			slug := re.Request.PathValue("slug")

			var body struct {
				Password           string `json:"password"`
				HandshakeToken     string `json:"handshakeToken"`
				IdentityId         string `json:"identityId"`
				ChallengeNonce     string `json:"challengeNonce"`
				ChallengeSignature string `json:"challengeSignature"`
			}
			_ = re.BindBody(&body)

			link, err := app.FindFirstRecordByFilter(util.Coll.Links, "slug = {:slug}", map[string]any{"slug": slug})
			if err != nil || link == nil {
				return re.NotFoundError(util.Errors.LinkNotFound.ErrorText, nil)
			}

			if appErr := services.RefreshLinkStatus(app, link); appErr != nil {
				return resourceErrorResponse(re, appErr)
			}

			// Password gate — enforced here, not just advertised by the probe.
			if hash := link.GetString(util.Fields.Link.Password); hash != "" {
				if !allowRequest(re, gatePasswordLimiter, slug) {
					return rateLimitedResponse(re)
				}
				if body.Password == "" {
					return appErrorResponse(re, http.StatusUnauthorized, &util.Errors.LinkPasswordRequired)
				}
				if !util.VerifyPassword(hash, body.Password) {
					return appErrorResponse(re, http.StatusUnauthorized, &util.Errors.LinkPasswordInvalid)
				}
				// Clear the budget so a viewer who mistyped is not throttled after
				// unlocking.
				gatePasswordLimiter.Reset(rateLimitKey(re, slug))
			}

			if link.GetBool(util.Fields.Link.RequireHandshake) {
				if body.IdentityId == "" {
					return appErrorResponse(re, http.StatusBadRequest, &util.Errors.IdentityRequired)
				}
				if !enforceLinkHandshake(app, link, body.IdentityId, body.HandshakeToken, body.ChallengeNonce, body.ChallengeSignature, re) {
					return nil
				}
			}

			// The view claim is atomic: losing it means a concurrent reader took
			// the last view, so this request must not be served the data.
			currentViews, revokedByLimit, err := services.ClaimLinkView(app, link)
			if err != nil {
				return resourceErrorResponse(re, &util.Errors.LinkMaxViewsReached)
			}

			sectionIds := link.GetStringSlice(util.Fields.Link.Sections)
			recordIds := link.GetStringSlice(util.Fields.Link.Records)

			sections := []map[string]any{}
			records := []map[string]any{}

			for _, id := range sectionIds {
				if rec, err := app.FindRecordById(util.Coll.Sections, id); err == nil {
					sections = append(sections, sanitizeRecord(rec))
				}
			}
			for _, id := range recordIds {
				if rec, err := app.FindRecordById(util.Coll.Records, id); err == nil {
					entry := sanitizeRecord(rec)
					// The resolve above claimed the view; the token carries that
					// claim to the byte endpoint, so a download is never a
					// second claim and never claim-free.
					if rec.GetString(util.Fields.Record.Type) == util.TypeFile {
						if token, tokenErr := issueDownloadToken(slug, rec.Id); tokenErr == nil {
							entry["downloadToken"] = token
						}
					}
					records = append(records, entry)
				}
			}

			if revokedByLimit {
				services.EmitNotification(app, link.GetString(util.Fields.Link.User),
					link.GetString(util.Fields.Link.Workspace),
					util.NotificationLinkMaxViews,
					"Link reached max views",
					"Link "+link.GetString(util.Fields.Link.Slug)+" was auto-revoked after reaching its max views.",
					util.Coll.Links, link.Id)
			}

			return re.JSON(http.StatusOK, map[string]any{
				"slug":      link.GetString(util.Fields.Link.Slug),
				"label":     link.GetString(util.Fields.Link.Label),
				"identity":  link.GetString(util.Fields.Link.Identity),
				"sections":  sections,
				"records":   records,
				"viewCount": currentViews,
			})
		})

		return e.Next()
	})
}

// sanitizeRecord returns only public-safe fields from a section/record entity.
func sanitizeRecord(rec *core.Record) map[string]any {
	out := map[string]any{
		"id": rec.Id,
	}
	// Never include workspace or user IDs in public output. The hash salt stays
	// private too — hash alone proves currency, hash plus salt is a guessing
	// oracle for recognizable content.
	// `file` stays out: the storage name is an implementation detail, and the
	// bytes are only ever reachable through the claimed download endpoint.
	for _, name := range []string{"key", "value", "label", "name", "type", "format", "records", "requestedBy", "filename", "mime", "size", "contentHash", "updated"} {
		if v := rec.Get(name); v != nil && v != "" {
			out[name] = v
		}
	}
	return out
}

// enforceLinkHandshake verifies a stored handshake token, or on first contact
// requires a signed challenge nonce proving possession of the identity's private
// key before issuing one.
// Reports whether the caller may proceed, having already written the refusal
// when it may not. See [denyGate] for why this is a bool and not an error.
func enforceLinkHandshake(app core.App, link *core.Record, identityId, token, challengeNonce, challengeSignature string, re *core.RequestEvent) bool {
	identity, err := app.FindRecordById(util.Coll.Identities, identityId)
	if err != nil || identity == nil {
		return denyGate(re, http.StatusBadRequest, &util.Errors.IdentityNotFound)
	}

	// Checked before the stored-token fast path, so revoking an identity ends the
	// sessions it already opened instead of only blocking new ones.
	if !services.IdentityIsActive(identity) {
		return denyGate(re, http.StatusForbidden, &util.Errors.IdentityRevoked)
	}

	existing, err := app.FindFirstRecordByFilter(util.Coll.Handshakes,
		"link = {:link} && identity = {:identity}",
		map[string]any{"link": link.Id, "identity": identityId})

	if err == nil && existing != nil {
		if token == "" {
			return denyGate(re, http.StatusUnauthorized, &util.Errors.HandshakeRequired)
		}
		if existing.GetString(util.Fields.Handshake.TokenHash) != util.HashToken(token) {
			return denyGate(re, http.StatusUnauthorized, &util.Errors.HandshakeInvalid)
		}
		return true
	}

	if challengeNonce == "" || challengeSignature == "" {
		return denyGate(re, http.StatusUnauthorized, &util.Errors.ChallengeRequired)
	}
	slug := link.GetString(util.Fields.Link.Slug)
	if !ConsumeChallenge(challengeNonce, "link", slug, identityId) {
		return denyGate(re, http.StatusUnauthorized, &util.Errors.ChallengeInvalid)
	}
	cert := identity.GetString(util.Fields.Identity.Certificate)
	if err := util.VerifySignature(cert, challengeNonce, challengeSignature); err != nil {
		return denyGate(re, http.StatusUnauthorized, &util.Errors.SignatureInvalid)
	}

	newToken, err := util.GenerateToken(24)
	if err != nil {
		return denyGate(re, http.StatusInternalServerError, &util.Errors.HandshakeFailed)
	}
	col, err := app.FindCollectionByNameOrId(util.Coll.Handshakes)
	if err != nil {
		return denyGate(re, http.StatusInternalServerError, &util.Errors.HandshakeFailed)
	}
	hs := core.NewRecord(col)
	hs.Set(util.Fields.Handshake.Link, link.Id)
	hs.Set(util.Fields.Handshake.Identity, identityId)
	hs.Set(util.Fields.Handshake.TokenHash, util.HashToken(newToken))
	hs.Set(util.Fields.Handshake.Workspace, link.GetString(util.Fields.Link.Workspace))
	if err := app.Save(hs); err != nil {
		app.Logger().Error("Failed to save handshake", "error", err)
		return denyGate(re, http.StatusInternalServerError, &util.Errors.HandshakeFailed)
	}
	re.Response.Header().Set("X-Handshake-Token", newToken)
	re.Response.Header().Set("Access-Control-Expose-Headers", "X-Handshake-Token")
	return true
}

// denyGate writes the stable error envelope and reports that the gate refused,
// so a caller reads as `if !enforceX(...) { return nil }`.
//
// A gate must never hand back what appErrorResponse returned: re.JSON reports
// success as a nil error, so a gate returning it tells its caller the check
// PASSED. That is the same trap the rate limiters are shaped around
// (invariant #7), and it is why these helpers return bool rather than error.
func denyGate(re *core.RequestEvent, status int, e *util.AppError) bool {
	_ = appErrorResponse(re, status, e)
	return false
}

// resourceErrorResponse renders a lifecycle error with the right status: paused is
// temporary (403) so consumers don't treat it as permanently gone, while
// revoked/expired/completed are terminal (410).
func resourceErrorResponse(re *core.RequestEvent, e *util.AppError) error {
	status := http.StatusGone
	if e.ErrorCode == util.Errors.LinkPaused.ErrorCode ||
		e.ErrorCode == util.Errors.RequestPaused.ErrorCode {
		status = http.StatusForbidden
	}
	return appErrorResponse(re, status, e)
}

// appErrorResponse serializes the error envelope itself: PocketBase's Error helpers
// run errData through a validation pipeline that strips custom error codes.
func appErrorResponse(re *core.RequestEvent, status int, e *util.AppError) error {
	return re.JSON(status, map[string]any{
		"code":    e.ErrorCode,
		"message": e.ErrorText,
		"status":  status,
	})
}
