package routes

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"regexp"
	"revoked/cmd/revoked/server"
	"revoked/cmd/revoked/services"
	"revoked/util"
	"strings"
	"time"

	"github.com/pocketbase/pocketbase/core"
)

// recordKeyPattern mirrors util.SlugPattern, so a submitted key can never be one the
// vault would reject later.
var recordKeyPattern = regexp.MustCompile(util.SlugPattern)

const (
	// grantSlugPrefix marks a link as request-born; it encodes nothing about the
	// request that minted it.
	grantSlugPrefix = "g_"
	// grantSlugBytes gives every request-born slug 128 bits of entropy.
	grantSlugBytes = 16
	// maxKeySuffixProbes bounds the key_1, key_2 … search in uniqueRecordKey.
	maxKeySuffixProbes = 50
)

// PublicRequestsRoute exposes the public probe and submission endpoints for a request.
// Same rules as links: slug-only access, no scanning, and password / expiry /
// max-responses / handshake / template validation all enforced server-side.
//
// root is threaded in so the probe can publish this server's domain claim and root
// fingerprint; without them a receiver cannot tell a real identity from a spoof.
func PublicRequestsRoute(app core.App, root *server.RootKey) {
	app.OnServe().BindFunc(func(e *core.ServeEvent) error {

		e.Router.GET("/api/public/requests/{slug}", func(re *core.RequestEvent) error {
			if !allowRequest(re, probeLimiter, "") {
				return rateLimitedResponse(re)
			}
			slug := re.Request.PathValue("slug")
			req, err := app.FindFirstRecordByFilter(util.Coll.Requests, "slug = {:slug}", map[string]any{"slug": slug})
			if err != nil || req == nil {
				return re.NotFoundError(util.Errors.RequestNotFound.ErrorText, nil)
			}
			if appErr := services.RefreshRequestStatus(app, req); appErr != nil {
				return resourceErrorResponse(re, appErr)
			}

			// The identity is included even when parentSignature is empty, so the
			// client can render it as "unverified" rather than silently hide it.
			requester := map[string]any{}
			if idRec, idErr := app.FindRecordById(util.Coll.Identities, req.GetString(util.Fields.Request.Identity)); idErr == nil && idRec != nil {
				requester["identityId"] = idRec.Id
				requester["name"] = idRec.GetString(util.Fields.Identity.Name)
				requester["fingerprint"] = idRec.GetString(util.Fields.Identity.Fingerprint)
				requester["parentSignature"] = idRec.GetString(util.Fields.Identity.ParentSignature)
				requester["domainAtIssue"] = idRec.GetString(util.Fields.Identity.DomainAtIssue)
			}

			records, sections := loadRequestTemplate(app, req)

			return re.JSON(http.StatusOK, map[string]any{
				"requestId":          req.Id,
				"slug":               req.GetString(util.Fields.Request.Slug),
				"label":              req.GetString(util.Fields.Request.Label),
				"status":             req.GetString(util.Fields.Request.Status),
				"identity":           req.GetString(util.Fields.Request.Identity),
				"requester":          requester,
				"requiresIdentifier": req.GetString(util.Fields.Request.Identifier) != "",
				"requiresPassword":   req.GetString(util.Fields.Request.Password) != "",
				"requireHandshake":   req.GetBool(util.Fields.Request.RequireHandshake),
				"identityScope":      req.GetString(util.Fields.Request.IdentityScope),
				"allowExtraFields":   req.GetBool(util.Fields.Request.AllowExtraFields),
				"template": map[string]any{
					"records":  records,
					"sections": sections,
				},
				"server": map[string]any{
					"domain":          root.Domain(),
					"rootFingerprint": root.Fingerprint(),
				},
			})
		})

		e.Router.POST("/api/public/requests/{slug}", func(re *core.RequestEvent) error {
			slug := re.Request.PathValue("slug")

			var body struct {
				Password           string            `json:"password"`
				Identifier         string            `json:"identifier"`
				HandshakeToken     string            `json:"handshakeToken"`
				IdentityId         string            `json:"identityId"`
				ChallengeNonce     string            `json:"challengeNonce"`
				ChallengeSignature string            `json:"challengeSignature"`
				GuestCertificate   string            `json:"guestCertificate"`
				SenderName         string            `json:"senderName"`
				Data               map[string]any    `json:"data"`
				Mappings           map[string]string `json:"mappings"`
			}
			_ = re.BindBody(&body)

			req, err := app.FindFirstRecordByFilter(util.Coll.Requests, "slug = {:slug}", map[string]any{"slug": slug})
			if err != nil || req == nil {
				return re.NotFoundError(util.Errors.RequestNotFound.ErrorText, nil)
			}

			if appErr := services.RefreshRequestStatus(app, req); appErr != nil {
				return resourceErrorResponse(re, appErr)
			}

			if hash := req.GetString(util.Fields.Request.Password); hash != "" {
				if !allowRequest(re, gatePasswordLimiter, slug) {
					return rateLimitedResponse(re)
				}
				if body.Password == "" {
					return appErrorResponse(re, http.StatusUnauthorized, &util.Errors.RequestPasswordRequired)
				}
				if !util.VerifyPassword(hash, body.Password) {
					return appErrorResponse(re, http.StatusUnauthorized, &util.Errors.RequestPasswordInvalid)
				}
				gatePasswordLimiter.Reset(rateLimitKey(re, slug))
			}

			// A defined identifier must be echoed back, which blocks spray-and-pray
			// submissions against guessed slugs.
			identifierEnforced := false
			if expected := req.GetString(util.Fields.Request.Identifier); expected != "" {
				// A shared secret like the password, so it shares that budget.
				if !allowRequest(re, gatePasswordLimiter, slug) {
					return rateLimitedResponse(re)
				}
				if body.Identifier == "" || body.Identifier != expected {
					return appErrorResponse(re, http.StatusBadRequest, &util.Errors.RequestIdentifierMissing)
				}
				identifierEnforced = true
				gatePasswordLimiter.Reset(rateLimitKey(re, slug))
			}

			// Gating: requireHandshake demands a workspace-known identity with a
			// signed challenge; an identifier alone still demands proof of *some*
			// keypair via an ephemeral guest cert; neither leaves submission open.
			//
			// identityProven gates attribution. Identity ids are public (the probe
			// returns one), so only a verified signature may record one on the link.
			identityProven := false
			if req.GetBool(util.Fields.Request.RequireHandshake) {
				if body.IdentityId == "" {
					return appErrorResponse(re, http.StatusBadRequest, &util.Errors.IdentityRequired)
				}
				if err := enforceRequestHandshake(app, root, req, body.IdentityId, body.HandshakeToken, body.ChallengeNonce, body.ChallengeSignature, re); err != nil {
					return err
				}
				identityProven = true
			} else if identifierEnforced {
				if err := enforceRequestGuestIdentity(app, req, body.GuestCertificate, body.ChallengeNonce, body.ChallengeSignature, re); err != nil {
					return err
				}
			}

			// Mappings are honored only for a signed-in responder: an anonymous
			// caller must not create aliases in someone else's vault.
			mappedGrants := map[string]string{}
			var mappedAliasIds []string
			if len(body.Mappings) > 0 && re.Auth != nil && re.Auth.Collection().Name == util.Coll.Users {
				if body.Data == nil {
					body.Data = map[string]any{}
				}
				resolved, aliasIds, err := resolveResponseMappings(app, re.Auth, body.Mappings, body.Data, requesterDisplayName(app, req))
				if err != nil {
					return err
				}
				mappedGrants = resolved
				mappedAliasIds = aliasIds
			}

			// Template validation runs after gating, so bad-data 400s cannot be used
			// to probe the template without first passing the password/identifier gates.
			tplRecords, tplSections := loadRequestTemplate(app, req)
			templateKeys := map[string]templateEntry{}
			for _, item := range tplRecords {
				templateKeys[item.Key] = templateEntry{required: item.Required}
			}
			// Section children are answerable too, so their required flags must count.
			for _, sec := range tplSections {
				for _, child := range sec.Records {
					templateKeys[child.Key] = templateEntry{required: child.Required}
				}
			}
			if appErr := validateSubmissionData(body.Data, templateKeys, req.GetBool(util.Fields.Request.AllowExtraFields)); appErr != nil {
				return appErrorResponse(re, http.StatusBadRequest, appErr)
			}

			// A signed-in responder's answers become records in their own vault —
			// a living, revocable grant rather than a frozen copy. Guests keep
			// only the snapshot.
			grantMap := map[string]string{}
			if re.Auth != nil && re.Auth.Collection().Name == util.Coll.Users {
				grantMap = createGrantRecords(app, re.Auth, req, body.Data, mappedGrants, mappedAliasIds)
			}

			senderName := body.SenderName
			if senderName == "" && body.GuestCertificate != "" {
				senderName = "guest:" + fingerprintForCert(body.GuestCertificate)[:16]
			}

			// The answer is minted as a `links` row: its `request` backref lets the
			// requester aggregate every answer, and `user` stays empty for guests.
			linkCol, err := app.FindCollectionByNameOrId(util.Coll.Links)
			if err != nil {
				return re.InternalServerError("Link collection missing", nil)
			}
			// The link lives in the responder's workspace so they can revoke it;
			// guests fall back to the request's only to satisfy the required field.
			linkWorkspace := req.GetString(util.Fields.Request.Workspace)
			if re.Auth != nil && re.Auth.Collection().Name == util.Coll.Users {
				if aw := re.Auth.GetString(util.Fields.User.ActiveWorkspace); aw != "" {
					linkWorkspace = aw
				}
			}
			// One living grant per (request, responder): re-answering updates the
			// existing link rather than minting a duplicate. Guests always get a
			// fresh one.
			var resp *core.Record
			isUpdate := false
			if re.Auth != nil && re.Auth.Collection().Name == util.Coll.Users {
				if existing, _ := app.FindFirstRecordByFilter(util.Coll.Links,
					"request = {:r} && user = {:u}",
					map[string]any{"r": req.Id, "u": re.Auth.Id}); existing != nil {
					resp = existing
					isUpdate = true
				}
			}
			if resp == nil {
				linkSlug, slugErr := mintLinkSlug(app, req)
				if slugErr != nil {
					app.Logger().Error("Failed to mint response link slug", "error", slugErr)
					return re.InternalServerError("Failed to record response", nil)
				}
				resp = core.NewRecord(linkCol)
				resp.Set(util.Fields.Link.Slug, linkSlug)
			}
			resp.Set(util.Fields.Link.Label, requestLinkLabel(req))
			resp.Set(util.Fields.Link.Workspace, linkWorkspace)
			resp.Set(util.Fields.Link.Request, req.Id)
			resp.Set(util.Fields.Link.Status, util.StatusActive)
			resp.Set(util.Fields.Link.SenderName, senderName)
			resp.Set(util.Fields.Link.Identifier, body.Identifier)
			// `identity` on a link always means cryptographically proven.
			if body.IdentityId != "" && identityProven {
				resp.Set(util.Fields.Link.Identity, body.IdentityId)
			}
			if re.Auth != nil && re.Auth.Collection().Name == util.Coll.Users {
				resp.Set(util.Fields.Link.User, re.Auth.Id)
			}
			// Overwritten on update so a re-answer never keeps fields the responder
			// has since dropped.
			resp.Set(util.Fields.Link.Data, body.Data)
			resp.Set(util.Fields.Link.Records, grantRecordIdsFrom(grantMap))
			resp.Set(util.Fields.Link.Grants, grantMap)
			if err := app.Save(resp); err != nil {
				app.Logger().Error("Failed to record response", "error", err)
				return re.InternalServerError("Failed to record response", nil)
			}

			// Only a genuinely new response counts; an update must not inflate it.
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
				go deliverCallback(app, req, resp, cb, senderName)
			}

			respTitle := "Request received a new response"
			respBody := "Request " + req.GetString(util.Fields.Request.Slug) +
				" received a new submission."
			if isUpdate {
				respTitle = "A response was updated"
				respBody = "A responder updated their submission to request " +
					req.GetString(util.Fields.Request.Slug) + "."
			}
			services.EmitNotification(app, req.GetString(util.Fields.Request.User),
				req.GetString(util.Fields.Request.Workspace),
				util.NotificationRequestResponse,
				respTitle, respBody,
				util.Coll.Requests, req.Id)
			if completed {
				services.EmitNotification(app, req.GetString(util.Fields.Request.User),
					req.GetString(util.Fields.Request.Workspace),
					util.NotificationRequestComplete,
					"Request completed",
					"Request "+req.GetString(util.Fields.Request.Slug)+" reached its max response limit.",
					util.Coll.Requests, req.Id)
			}

			return re.JSON(http.StatusOK, map[string]any{
				"ok":         true,
				"linkId":     resp.Id,
				"responseId": resp.Id,
				"completed":  completed,
				"updated":    isUpdate,
			})
		})

		return e.Next()
	})
}

type templateEntry struct {
	required bool
}

// publicTemplateItem is one record or section of a template's schema, as exposed to
// the public probe.
type publicTemplateItem struct {
	Key      string               `json:"key"`
	Label    string               `json:"label"`
	Type     string               `json:"type,omitempty"`
	Format   string               `json:"format,omitempty"`
	Required bool                 `json:"required"`
	Reason   string               `json:"reason,omitempty"`
	Records  []publicTemplateItem `json:"records,omitempty"`
}

// loadRequestTemplate projects the request's template into (records, sections) for
// the public probe, returning empty slices when there is no usable template.
func loadRequestTemplate(app core.App, req *core.Record) ([]publicTemplateItem, []publicTemplateItem) {
	records := []publicTemplateItem{}
	sections := []publicTemplateItem{}

	templateId := req.GetString(util.Fields.Request.Template)
	if templateId == "" {
		return records, sections
	}
	tpl, err := app.FindRecordById(util.Coll.Templates, templateId)
	if err != nil || tpl == nil {
		return records, sections
	}

	var schema struct {
		Records  []map[string]any `json:"records"`
		Sections []map[string]any `json:"sections"`
	}
	rawSchema := tpl.GetString(util.Fields.Template.Schema)
	if rawSchema == "" {
		return records, sections
	}
	if err := json.Unmarshal([]byte(rawSchema), &schema); err != nil {
		return records, sections
	}

	for _, r := range schema.Records {
		records = append(records, templateItemFromRaw(r))
	}
	for _, s := range schema.Sections {
		item := templateItemFromRaw(s)
		if rawRecs, ok := s["records"].([]any); ok {
			for _, child := range rawRecs {
				if m, ok := child.(map[string]any); ok {
					item.Records = append(item.Records, templateItemFromRaw(m))
				}
			}
		}
		sections = append(sections, item)
	}
	return records, sections
}

// templateItemFromRaw projects a raw schema map onto a publicTemplateItem, reading
// every field defensively.
func templateItemFromRaw(raw map[string]any) publicTemplateItem {
	getStr := func(k string) string {
		if v, ok := raw[k].(string); ok {
			return v
		}
		return ""
	}
	getBool := func(k string) bool {
		if v, ok := raw[k].(bool); ok {
			return v
		}
		return false
	}
	return publicTemplateItem{
		Key:      getStr("key"),
		Label:    getStr("label"),
		Type:     getStr("type"),
		Format:   getStr("format"),
		Required: getBool("required"),
		Reason:   getStr("reason"),
	}
}

// validateSubmissionData enforces the template, extras and key-pattern rules,
// returning nil when the data is acceptable.
func validateSubmissionData(data map[string]any, template map[string]templateEntry, allowExtras bool) *util.AppError {
	for k := range data {
		if !recordKeyPattern.MatchString(k) {
			return &util.Errors.RequestKeyInvalid
		}
	}
	if !allowExtras && len(template) > 0 {
		for k := range data {
			if _, ok := template[k]; !ok {
				return &util.Errors.RequestExtraFieldsForbidden
			}
		}
	}
	for k, entry := range template {
		if !entry.required {
			continue
		}
		v, ok := data[k]
		if !ok {
			return &util.Errors.RequestRequiredMissing
		}
		if s, isString := v.(string); isString && s == "" {
			return &util.Errors.RequestRequiredMissing
		}
	}
	return nil
}

// enforceRequestHandshake mirrors [enforceLinkHandshake] for requests: a fresh
// signed challenge proves possession of the identity's private key before the
// persistent X-Handshake-Token is issued.
func enforceRequestHandshake(app core.App, root *server.RootKey, req *core.Record, identityId, token, challengeNonce, challengeSignature string, re *core.RequestEvent) error {
	identity, err := app.FindRecordById(util.Coll.Identities, identityId)
	if err != nil || identity == nil {
		return re.BadRequestError(util.Errors.IdentityNotFound.ErrorText, nil)
	}

	// from_root scope accepts only identities this server issued. Checked before the
	// token short-circuit so it always applies.
	if req.GetString(util.Fields.Request.IdentityScope) == "from_root" &&
		identity.GetString(util.Fields.Identity.DomainAtIssue) != root.Domain() {
		return appErrorResponse(re, http.StatusForbidden, &util.Errors.IdentityWrongRoot)
	}

	existing, _ := app.FindFirstRecordByFilter(util.Coll.Handshakes,
		"request = {:request} && identity = {:identity}",
		map[string]any{"request": req.Id, "identity": identityId})

	// Fast path: a matching stored token lets a return visit skip re-signing.
	if existing != nil && token != "" &&
		existing.GetString(util.Fields.Handshake.TokenHash) == util.HashToken(token) {
		return nil
	}

	// Otherwise a fresh signature is required. This also covers a client that lost
	// its token (reinstall, cleared storage, server reset): a valid signer is never
	// rejected merely for a missing token, which would lock them out for good.
	if challengeNonce == "" || challengeSignature == "" {
		return appErrorResponse(re, http.StatusUnauthorized, &util.Errors.ChallengeRequired)
	}
	slug := req.GetString(util.Fields.Request.Slug)
	if !ConsumeChallenge(challengeNonce, "request", slug, identityId) {
		return appErrorResponse(re, http.StatusUnauthorized, &util.Errors.ChallengeInvalid)
	}
	cert := identity.GetString(util.Fields.Identity.Certificate)
	if err := util.VerifySignature(cert, challengeNonce, challengeSignature); err != nil {
		return appErrorResponse(re, http.StatusUnauthorized, &util.Errors.SignatureInvalid)
	}

	newToken, err := util.GenerateToken(24)
	if err != nil {
		return re.InternalServerError("Failed to generate handshake token", nil)
	}
	hs := existing
	if hs == nil {
		col, err := app.FindCollectionByNameOrId(util.Coll.Handshakes)
		if err != nil {
			return re.InternalServerError("Handshake collection missing", nil)
		}
		hs = core.NewRecord(col)
		hs.Set(util.Fields.Handshake.Request, req.Id)
		hs.Set(util.Fields.Handshake.Identity, identityId)
		hs.Set(util.Fields.Handshake.Workspace, req.GetString(util.Fields.Request.Workspace))
	}
	hs.Set(util.Fields.Handshake.TokenHash, util.HashToken(newToken))
	if err := app.Save(hs); err != nil {
		app.Logger().Error("Failed to save handshake", "error", err)
		return re.InternalServerError("Failed to save handshake", nil)
	}
	re.Response.Header().Set("X-Handshake-Token", newToken)
	re.Response.Header().Set("Access-Control-Expose-Headers", "X-Handshake-Token")
	return nil
}

// enforceRequestGuestIdentity covers identifier-only requests, where no known
// identity exists: the responder proves possession of a one-shot keypair by signing
// a challenge. The certificate is verified but not persisted — only a short
// fingerprint survives, as `senderName`.
func enforceRequestGuestIdentity(app core.App, req *core.Record, guestCert, nonce, signature string, re *core.RequestEvent) error {
	if guestCert == "" || nonce == "" || signature == "" {
		return appErrorResponse(re, http.StatusUnauthorized, &util.Errors.ChallengeRequired)
	}
	fp := fingerprintForCert(guestCert)
	slug := req.GetString(util.Fields.Request.Slug)
	if !ConsumeChallenge(nonce, "request_guest", slug, fp) {
		return appErrorResponse(re, http.StatusUnauthorized, &util.Errors.ChallengeInvalid)
	}
	if err := util.VerifySignature(guestCert, nonce, signature); err != nil {
		return appErrorResponse(re, http.StatusUnauthorized, &util.Errors.SignatureInvalid)
	}
	_ = app // reserved for audit logging
	return nil
}

// fingerprintForCert is the hex SHA-256 of a certificate PEM, used as a stable guest
// identifier.
func fingerprintForCert(pem string) string {
	sum := sha256.Sum256([]byte(pem))
	return hex.EncodeToString(sum[:])
}

// resolveResponseMappings turns caller-supplied (key → recordId) pairs into a
// (requestedKey → value-carrier recordId) grant map, minting an alias in the
// responder's vault when the chosen record's own key differs. Grants point at the
// value carrier, so editing the record updates everywhere it has been shared.
func resolveResponseMappings(app core.App, auth *core.Record, mappings map[string]string, data map[string]any, requestedBy string) (map[string]string, []string, error) {
	grants := map[string]string{}
	aliasIds := []string{}
	authUserId := auth.Id
	authWorkspace := auth.GetString(util.Fields.User.ActiveWorkspace)

	for requestedKey, recordId := range mappings {
		if !recordKeyPattern.MatchString(requestedKey) {
			continue
		}
		rec, err := app.FindRecordById(util.Coll.Records, recordId)
		if err != nil || rec == nil {
			continue
		}
		if rec.GetString(util.Fields.Record.User) != authUserId {
			continue
		}

		// Dereference aliases to find the value carrier.
		parent := rec
		if parentId := rec.GetString(util.Fields.Record.AliasOf); parentId != "" {
			if p, err := app.FindRecordById(util.Coll.Records, parentId); err == nil && p != nil {
				parent = p
			}
		}

		if parent.GetString(util.Fields.Record.Key) != requestedKey {
			existing, _ := app.FindFirstRecordByFilter(util.Coll.Records,
				"key = {:key} && user = {:user} && workspace = {:workspace}",
				map[string]any{
					"key":       requestedKey,
					"user":      authUserId,
					"workspace": authWorkspace,
				})
			if existing != nil {
				// The key is taken: it cannot be aliased onto (the
				// (workspace,key,user) index is unique), and forwarding a different
				// record under it would silently shadow the responder's real field.
				// Forward the existing one instead.
				carrier := existing
				if pid := existing.GetString(util.Fields.Record.AliasOf); pid != "" {
					if p, err := app.FindRecordById(util.Coll.Records, pid); err == nil && p != nil {
						carrier = p
					}
				}
				grants[requestedKey] = carrier.Id
				data[requestedKey] = carrier.GetString(util.Fields.Record.Value)
				continue
			}

			col, err := app.FindCollectionByNameOrId(util.Coll.Records)
			if err == nil {
				alias := core.NewRecord(col)
				alias.Set(util.Fields.Record.Key, requestedKey)
				alias.Set(util.Fields.Record.Label, parent.GetString(util.Fields.Record.Label))
				alias.Set(util.Fields.Record.Type, parent.GetString(util.Fields.Record.Type))
				alias.Set(util.Fields.Record.Format, parent.GetString(util.Fields.Record.Format))
				alias.Set(util.Fields.Record.User, authUserId)
				alias.Set(util.Fields.Record.Workspace, authWorkspace)
				alias.Set(util.Fields.Record.AliasOf, parent.Id)
				alias.Set(util.Fields.Record.RequestedBy, requestedBy)
				if err := app.Save(alias); err == nil {
					aliasIds = append(aliasIds, alias.Id)
				}
			}
		}

		grants[requestedKey] = parent.Id
		data[requestedKey] = parent.GetString(util.Fields.Record.Value)
	}
	return grants, aliasIds, nil
}

// createGrantRecords turns a signed-in responder's free-typed answers into living
// grants, reusing a vault record that already holds the same value under the same key
// so re-answering does not spawn field_1 / field_2 duplicates. Best-effort: a failure
// only yields fewer references, and the response still saves its data snapshot.
func createGrantRecords(app core.App, auth *core.Record, req *core.Record, data map[string]any, mapped map[string]string, aliasIds []string) map[string]string {
	grants := map[string]string{}
	for k, id := range mapped {
		grants[k] = id
	}

	workspace := auth.GetString(util.Fields.User.ActiveWorkspace)
	if workspace == "" {
		return grants
	}
	userId := auth.Id
	requestedBy := requesterDisplayName(app, req)

	secCol, err := app.FindCollectionByNameOrId(util.Coll.Sections)
	if err != nil {
		return grants
	}

	// Created lazily, so a submission that only reuses existing records leaves no
	// empty section behind.
	var section *core.Record
	ensureSection := func() *core.Record {
		if section != nil {
			return section
		}
		secKey := sanitizeKey("req_" + req.GetString(util.Fields.Request.Slug))
		s, _ := app.FindFirstRecordByFilter(util.Coll.Sections,
			"key = {:k} && user = {:u} && workspace = {:w}",
			map[string]any{"k": secKey, "u": userId, "w": workspace})
		if s == nil {
			s = core.NewRecord(secCol)
			s.Set(util.Fields.Section.Key, secKey)
			name := req.GetString(util.Fields.Request.Label)
			if name == "" {
				name = req.GetString(util.Fields.Request.Slug)
			}
			s.Set(util.Fields.Section.Name, name)
			s.Set(util.Fields.Section.RequestedBy, requestedBy)
			s.Set(util.Fields.Section.User, userId)
			s.Set(util.Fields.Section.Workspace, workspace)
			if err := app.Save(s); err != nil {
				return nil
			}
		}
		section = s
		return s
	}

	newIds := []string{}
	if len(data) > 0 {
		if recCol, err := app.FindCollectionByNameOrId(util.Coll.Records); err == nil {
			for key, raw := range data {
				if _, ok := grants[key]; ok {
					continue // already satisfied by an explicit mapping
				}
				value, ok := raw.(string)
				if !ok || len(value) < 1 || len(value) > util.MaxRecordValueLength {
					continue
				}
				sanitized := sanitizeKey(key)

				if existing, _ := app.FindFirstRecordByFilter(util.Coll.Records,
					"key = {:k} && value = {:v} && user = {:u} && workspace = {:w}",
					map[string]any{"k": sanitized, "v": value, "u": userId, "w": workspace}); existing != nil {
					grants[key] = existing.Id
					continue
				}

				if ensureSection() == nil {
					continue
				}
				recordKey := uniqueRecordKey(app, sanitized, userId, workspace)
				rec := core.NewRecord(recCol)
				rec.Set(util.Fields.Record.Key, recordKey)
				rec.Set(util.Fields.Record.Value, value)
				rec.Set(util.Fields.Record.Label, key)
				rec.Set(util.Fields.Record.Type, util.TypeText)
				rec.Set(util.Fields.Record.Format, util.FormatDefault)
				rec.Set(util.Fields.Record.User, userId)
				rec.Set(util.Fields.Record.Workspace, workspace)
				rec.Set(util.Fields.Record.RequestedBy, requestedBy)
				if err := app.Save(rec); err != nil {
					continue
				}
				grants[key] = rec.Id
				newIds = append(newIds, rec.Id)
			}
		}
	}

	// Group every request-specific record under the per-request section.
	sectionIds := append(append([]string{}, aliasIds...), newIds...)
	if len(sectionIds) > 0 {
		if sec := ensureSection(); sec != nil {
			existing := sec.GetStringSlice(util.Fields.Section.Records)
			seen := map[string]bool{}
			for _, id := range existing {
				seen[id] = true
			}
			changed := false
			for _, id := range sectionIds {
				if id == "" || seen[id] {
					continue
				}
				existing = append(existing, id)
				seen[id] = true
				changed = true
			}
			if changed {
				sec.Set(util.Fields.Section.Records, existing)
				_ = app.Save(sec)
			}
		}
	}
	return grants
}

// grantRecordIdsFrom returns the unique record ids referenced by a grant map.
func grantRecordIdsFrom(grants map[string]string) []string {
	seen := map[string]bool{}
	ids := []string{}
	for _, id := range grants {
		if id == "" || seen[id] {
			continue
		}
		seen[id] = true
		ids = append(ids, id)
	}
	return ids
}

// sanitizeKey coerces an arbitrary string into a vault-safe key ([a-z0-9_]);
// empty input becomes "field".
func sanitizeKey(s string) string {
	var b strings.Builder
	for _, r := range strings.ToLower(s) {
		switch {
		case r >= 'a' && r <= 'z', r >= '0' && r <= '9', r == '_':
			b.WriteRune(r)
		default:
			b.WriteRune('_')
		}
	}
	out := b.String()
	if out == "" {
		return "field"
	}
	return out
}

// uniqueRecordKey returns base, or base_N for the smallest free N (records have a
// unique key index per user+workspace). The search is bounded because each probe is a
// query: an unbounded scan would let one submission become an arbitrarily long chain
// of them.
func uniqueRecordKey(app core.App, base, userId, workspace string) string {
	taken := func(key string) bool {
		existing, _ := app.FindFirstRecordByFilter(util.Coll.Records,
			"key = {:k} && user = {:u} && workspace = {:w}",
			map[string]any{"k": key, "u": userId, "w": workspace})
		return existing != nil
	}

	if !taken(base) {
		return base
	}
	for n := 1; n <= maxKeySuffixProbes; n++ {
		key := fmt.Sprintf("%s_%d", base, n)
		if !taken(key) {
			return key
		}
	}
	// A collision on the random suffix is harmless: the save fails the unique index
	// and the grant degrades to the snapshot.
	suffix, err := util.GenerateToken(4)
	if err != nil {
		suffix = fmt.Sprintf("%d", time.Now().UnixNano())
	}
	return fmt.Sprintf("%s_%s", base, suffix)
}

// mintLinkSlug returns a unique, unguessable slug for a request-born link.
//
// The slug is the capability: it must carry its own entropy and reveal nothing about
// the request, or any invited responder could enumerate the others' answers. It
// returns an error rather than degrading to a derivable slug.
func mintLinkSlug(app core.App, req *core.Record) (string, error) {
	_ = req // the slug deliberately encodes nothing about the request
	var lastErr error
	for attempt := 0; attempt < 5; attempt++ {
		token, err := util.GenerateToken(grantSlugBytes)
		if err != nil {
			lastErr = err
			continue
		}
		slug := grantSlugPrefix + token
		existing, _ := app.FindFirstRecordByFilter(util.Coll.Links, "slug = {:s}", map[string]any{"s": slug})
		if existing == nil {
			return slug, nil
		}
	}
	if lastErr == nil {
		lastErr = errors.New("exhausted slug attempts")
	}
	return "", lastErr
}

// requesterDisplayName names who issued a request, for the `requestedBy` stamp that
// tells a responder why an entry exists. Falls back identity name → label → slug.
func requesterDisplayName(app core.App, req *core.Record) string {
	name := ""
	domain := ""
	if idID := req.GetString(util.Fields.Request.Identity); idID != "" {
		if idRec, err := app.FindRecordById(util.Coll.Identities, idID); err == nil && idRec != nil {
			name = idRec.GetString(util.Fields.Identity.Name)
			domain = idRec.GetString(util.Fields.Identity.DomainAtIssue)
		}
	}
	if name == "" {
		name = req.GetString(util.Fields.Request.Label)
	}
	if name == "" {
		name = req.GetString(util.Fields.Request.Slug)
	}
	if domain != "" {
		return name + " (" + domain + ")"
	}
	return name
}

// requestLinkLabel is the owner-facing label shown for a request-born link.
func requestLinkLabel(req *core.Record) string {
	if l := req.GetString(util.Fields.Request.Label); l != "" {
		return l
	}
	if s := req.GetString(util.Fields.Request.Slug); s != "" {
		return s
	}
	return "Shared via request"
}

// deliverCallback POSTs the response payload to the configured callback URL,
// notifying on failure. Runs in its own goroutine and never blocks the submitter.
func deliverCallback(app core.App, req *core.Record, resp *core.Record, url, senderName string) {
	payload := map[string]any{
		"requestId":  req.Id,
		"slug":       req.GetString(util.Fields.Request.Slug),
		"responseId": resp.Id,
		"linkId":     resp.Id,
		"identity":   resp.GetString(util.Fields.Link.Identity),
		"identifier": resp.GetString(util.Fields.Link.Identifier),
		"senderName": senderName,
		"data":       resp.Get(util.Fields.Link.Data),
	}
	// The callback target is attacker-influenced input this server fetches itself:
	// validate up front and deliver through a client that refuses redirects and
	// re-checks the resolved IP at connect time.
	if err := util.ValidateCallbackURL(url); err != nil {
		notifyCallbackFailed(app, req, err.Error())
		return
	}

	b, _ := json.Marshal(payload)
	client := util.NewSafeCallbackClient(10 * time.Second)
	httpReq, err := http.NewRequest("POST", url, bytes.NewReader(b))
	if err != nil {
		notifyCallbackFailed(app, req, err.Error())
		return
	}
	httpReq.Header.Set("Content-Type", "application/json")
	httpReq.Header.Set("X-Revoked-Request", req.Id)
	httpResp, err := client.Do(httpReq)
	if err != nil {
		notifyCallbackFailed(app, req, err.Error())
		return
	}
	defer httpResp.Body.Close()
	if httpResp.StatusCode >= 400 {
		notifyCallbackFailed(app, req, "callback returned status "+httpResp.Status)
	}
}

// notifyCallbackFailed emits a callback-failure notification to the request owner.
func notifyCallbackFailed(app core.App, req *core.Record, msg string) {
	services.EmitNotification(app, req.GetString(util.Fields.Request.User),
		req.GetString(util.Fields.Request.Workspace),
		util.NotificationCallbackFailed,
		"Callback delivery failed",
		"Callback URL for request "+req.GetString(util.Fields.Request.Slug)+" failed: "+msg,
		util.Coll.Requests, req.Id)
}
