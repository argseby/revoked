package routes

import (
	"errors"
	"net/http"
	"strings"

	"revoked/cmd/revoked/server"
	"revoked/cmd/revoked/services"
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tools/types"
)

// ContactGrantsRoute lets a workspace hand a grant to one of its contacts.
//
//	POST /api/contacts/{id}/send   share named vault entries with them
//	POST /api/contacts/{id}/ask    ask them for data
//
// Both mint the grant in the caller's own workspace, so the caller keeps the
// side they can pause and revoke, and both answer with the slug. Where the
// contact's address belongs to an account on this server the grant is also put
// in that person's tray; where it does not, the slug comes back for the caller
// to pass on themselves. Nothing is pushed to another server: a push would
// have to accept deliveries from anywhere, with nobody's consent in it.
func ContactGrantsRoute(app core.App, root *server.RootKey) {
	app.OnServe().BindFunc(func(e *core.ServeEvent) error {
		e.Router.POST("/api/contacts/{id}/send", func(re *core.RequestEvent) error {
			return sendToContact(app, re, root)
		})
		e.Router.POST("/api/contacts/{id}/ask", func(re *core.RequestEvent) error {
			return askContact(app, re, root)
		})
		return e.Next()
	})
}

func sendToContact(app core.App, re *core.RequestEvent, root *server.RootKey) error {
	contact, allowed := authorizeContactGrant(app, re, util.Coll.Links)
	if !allowed {
		return nil
	}

	var body struct {
		Records   []string `json:"records"`
		Sections  []string `json:"sections"`
		Label     string   `json:"label"`
		ExpiresAt string   `json:"expiresAt"`
		MaxViews  int      `json:"maxViews"`
		Locale    string   `json:"locale"`
	}
	_ = re.BindBody(&body)

	label := strings.TrimSpace(body.Label)
	if label == "" {
		return appErrorResponse(re, http.StatusBadRequest, &util.Errors.ValidationFieldRequired)
	}
	if len(body.Records) == 0 && len(body.Sections) == 0 {
		return appErrorResponse(re, http.StatusBadRequest, &util.Errors.ContactNothingToSend)
	}
	expires, ok := parseGrantExpiry(re, body.ExpiresAt)
	if !ok {
		return nil
	}
	workspace := contact.GetString(util.Fields.Contact.Workspace)
	if !authorizeVaultReads(app, re, workspace, util.Coll.Records, body.Records) ||
		!authorizeVaultReads(app, re, workspace, util.Coll.Sections, body.Sections) {
		return nil
	}

	col, err := app.FindCollectionByNameOrId(util.Coll.Links)
	if err != nil {
		return re.InternalServerError("Link collection missing", nil)
	}
	slug, err := mintUniqueSlug(app, util.Coll.Links, "")
	if err != nil {
		app.Logger().Error("Failed to mint contact share slug", "error", err)
		return re.InternalServerError("Failed to create the share", nil)
	}

	link := core.NewRecord(col)
	link.Set(util.Fields.Link.Slug, slug)
	link.Set(util.Fields.Link.Label, label)
	link.Set(util.Fields.Link.User, re.Auth.Id)
	link.Set(util.Fields.Link.Workspace, workspace)
	link.Set(util.Fields.Link.Records, body.Records)
	link.Set(util.Fields.Link.Sections, body.Sections)
	link.Set(util.Fields.Link.Status, util.StatusActive)
	link.Set(util.Fields.Link.ExpiresAt, expires)
	if body.MaxViews > 0 {
		link.Set(util.Fields.Link.MaxViews, body.MaxViews)
	}
	if err := app.Save(link); err != nil {
		app.Logger().Error("Failed to create contact share", "error", err)
		return re.InternalServerError("Failed to create the share", nil)
	}

	auditGrantCreated(app, re, util.Coll.Links, link)
	return answerContactGrant(app, re, contactHandOver{
		contact:    contact,
		grant:      link,
		collection: util.Coll.Links,
		kind:       util.BookmarkKindShare,
		action:     util.AuditActionSend,
		slug:       slug,
		label:      label,
		locale:     body.Locale,
		root:       root,
	})
}

func askContact(app core.App, re *core.RequestEvent, root *server.RootKey) error {
	contact, allowed := authorizeContactGrant(app, re, util.Coll.Requests)
	if !allowed {
		return nil
	}

	var body struct {
		Label        string `json:"label"`
		Identity     string `json:"identity"`
		Template     string `json:"template"`
		ExpiresAt    string `json:"expiresAt"`
		MaxResponses int    `json:"maxResponses"`
		Locale       string `json:"locale"`
	}
	_ = re.BindBody(&body)

	label := strings.TrimSpace(body.Label)
	if label == "" {
		return appErrorResponse(re, http.StatusBadRequest, &util.Errors.ValidationFieldRequired)
	}
	expires, ok := parseGrantExpiry(re, body.ExpiresAt)
	if !ok {
		return nil
	}
	workspace := contact.GetString(util.Fields.Contact.Workspace)
	if appErr := authorizeAskIdentity(app, workspace, body.Identity); appErr != nil {
		return appErrorResponse(re, http.StatusForbidden, appErr)
	}
	if body.Template != "" {
		template, err := app.FindRecordById(util.Coll.Templates, body.Template)
		if err != nil || template == nil ||
			template.GetString(util.Fields.Template.Workspace) != workspace ||
			!services.CanSee(app, re.Auth.Id, template) {
			return appErrorResponse(re, http.StatusForbidden, &util.Errors.TemplateNotOwned)
		}
	}

	col, err := app.FindCollectionByNameOrId(util.Coll.Requests)
	if err != nil {
		return re.InternalServerError("Request collection missing", nil)
	}
	slug, err := mintUniqueSlug(app, util.Coll.Requests, "")
	if err != nil {
		app.Logger().Error("Failed to mint contact request slug", "error", err)
		return re.InternalServerError("Failed to create the request", nil)
	}

	req := core.NewRecord(col)
	req.Set(util.Fields.Request.Slug, slug)
	req.Set(util.Fields.Request.Label, label)
	req.Set(util.Fields.Request.Status, util.StatusActive)
	req.Set(util.Fields.Request.Identity, body.Identity)
	req.Set(util.Fields.Request.Template, body.Template)
	req.Set(util.Fields.Request.User, re.Auth.Id)
	req.Set(util.Fields.Request.Workspace, workspace)
	// An ask is addressed to one person, so one answer closes it unless the
	// caller says otherwise. A request left uncapped is a form anyone holding
	// the slug can keep filling in.
	responses := body.MaxResponses
	if responses <= 0 {
		responses = 1
	}
	req.Set(util.Fields.Request.MaxResponses, responses)
	// Without a form there is nothing to list as asked-for, so whatever the
	// responder chooses to send has to be allowed through.
	req.Set(util.Fields.Request.AllowExtraFields, body.Template == "")
	req.Set(util.Fields.Request.ExpiresAt, expires)
	if err := app.Save(req); err != nil {
		app.Logger().Error("Failed to create contact request", "error", err)
		return re.InternalServerError("Failed to create the request", nil)
	}

	auditGrantCreated(app, re, util.Coll.Requests, req)
	return answerContactGrant(app, re, contactHandOver{
		contact:    contact,
		grant:      req,
		collection: util.Coll.Requests,
		kind:       util.BookmarkKindRequest,
		action:     util.AuditActionAsk,
		slug:       slug,
		label:      label,
		identityId: body.Identity,
		locale:     body.Locale,
		root:       root,
	})
}

// authorizeContactGrant resolves the contact in the path and settles whether
// this caller may mint the grant named by coll in its workspace.
//
// It returns a bool rather than an error because every refusal here is written
// to the response already: a helper that returned the written refusal would
// report it to its caller as a nil error, and the handler would carry on and
// mint the grant anyway.
func authorizeContactGrant(app core.App, re *core.RequestEvent, coll string) (*core.Record, bool) {
	if re.Auth == nil {
		return nil, denyGate(re, http.StatusUnauthorized, &util.Errors.NotAuthenticated)
	}
	// Handing something to a person is a decision a person makes: an API key
	// authenticates as a program and this is the one path that writes into
	// somebody else's account.
	if re.Auth.Collection().Name != util.Coll.Users {
		return nil, denyGate(re, http.StatusForbidden, &util.Errors.ApiKeyNotPermitted)
	}
	if !allowRequest(re, contactGrantLimiter, re.Auth.Id) {
		_ = rateLimitedResponse(re)
		return nil, false
	}

	contact, err := app.FindRecordById(util.Coll.Contacts, re.Request.PathValue("id"))
	// A colleague's private contact is not there for this member
	// (VISIBILITY.md).
	if err != nil || contact == nil || !services.CanSee(app, re.Auth.Id, contact) {
		return nil, denyGate(re, http.StatusNotFound, &util.Errors.ContactNotFound)
	}

	spec, declared := util.AccessSpecFor(coll, util.ActionCreate)
	if !declared {
		return nil, denyGate(re, http.StatusForbidden, &util.Errors.NotAuthorized)
	}
	// The grant is minted in the contact's workspace and owned by the caller,
	// so the same declaration that guards a direct create guards this one.
	errs := spec.Diagnose(app, util.AccessSubject{
		Auth:            re.Auth,
		RecordWorkspace: contact.GetString(util.Fields.Contact.Workspace),
		RecordUser:      re.Auth.Id,
	})
	if len(errs) > 0 {
		// A contact nobody may reach must look no different from one that is
		// not there, or the 403 enumerates other workspaces' contacts.
		return nil, denyGate(re, http.StatusNotFound, &util.Errors.ContactNotFound)
	}
	return contact, true
}

// authorizeVaultReads refuses a send naming an entry or section outside the
// contact's workspace, or one a member without read access cannot see.
//
// Relation validation only proves the ids exist, and these ids travel in API
// responses, so without this a member could name a co-member's entries — or
// another tenant's — and have the server resolve them for a stranger.
func authorizeVaultReads(app core.App, re *core.RequestEvent, workspace, collection string, ids []string) bool {
	scope := util.ScopeRecordRead
	if collection == util.Coll.Sections {
		scope = util.ScopeSectionRead
	}
	read := util.AccessSpec{Kind: util.AccessWorkspaceSelf, Scope: scope}
	for _, id := range ids {
		rec, err := app.FindRecordById(collection, id)
		// Only the sender's own items: a colleague's record seen through a
		// shared section is not theirs to send (VISIBILITY.md).
		if err != nil || rec == nil ||
			rec.GetString(util.FieldWorkspace) != workspace ||
			rec.GetString(util.FieldUser) != re.Auth.Id {
			return denyGate(re, http.StatusNotFound, &util.Errors.RecordNotFound)
		}
		if collection == util.Coll.Records && services.IsSealedThroughAlias(app, rec) {
			return denyGate(re, http.StatusBadRequest, &util.Errors.SealedRecordUnsupported)
		}
		errs := read.Diagnose(app, util.AccessSubject{
			Auth:            re.Auth,
			RecordWorkspace: workspace,
			RecordUser:      rec.GetString(util.FieldUser),
		})
		if len(errs) > 0 {
			return denyGate(re, http.StatusNotFound, &util.Errors.RecordNotFound)
		}
	}
	return true
}

// authorizeAskIdentity rejects a request signed with an identity the
// workspace does not hold, which would let anyone put a verified name they do
// not own on an ask — the phishing primitive the trust chain exists to stop.
func authorizeAskIdentity(app core.App, workspace, identityId string) *util.AppError {
	if identityId == "" {
		return &util.Errors.IdentityRequired
	}
	identity, err := app.FindRecordById(util.Coll.Identities, identityId)
	if err != nil || identity == nil {
		return &util.Errors.IdentityNotFound
	}
	if identity.GetString(util.FieldWorkspace) != workspace {
		return &util.Errors.IdentityNotOwned
	}
	if !services.IdentityIsActive(identity) {
		return &util.Errors.IdentityRevoked
	}
	return nil
}

// parseGrantExpiry reads an optional RFC3339 expiry, writing the refusal and
// reporting false when it is unreadable. A zero value means no expiry.
func parseGrantExpiry(re *core.RequestEvent, raw string) (types.DateTime, bool) {
	if strings.TrimSpace(raw) == "" {
		return types.DateTime{}, true
	}
	parsed, err := types.ParseDateTime(raw)
	if err != nil {
		return types.DateTime{}, denyGate(re, http.StatusBadRequest, &util.Errors.ValidationFieldRequired)
	}
	return parsed, true
}

// contactHandOver is one minted grant on its way to a contact.
type contactHandOver struct {
	contact    *core.Record
	grant      *core.Record
	collection string
	kind       string
	action     string
	slug       string
	label      string
	identityId string

	// locale is the sender's, which is the best guess available for an email:
	// the recipient's is unknown.
	locale string

	root *server.RootKey
}

// answerContactGrant delivers the minted grant where the contact names someone
// here, and reports the slug either way.
//
// Delivery failing does not fail the call: the grant exists and its slug is in
// the answer, so the caller can still pass it on by hand.
func answerContactGrant(app core.App, re *core.RequestEvent, h contactHandOver) error {
	workspace := h.contact.GetString(util.Fields.Contact.Workspace)
	recipient := services.ContactAccountHere(app, h.contact)
	standing := services.ContactStanding(app, h.contact, re.Auth.Id, recipient)
	services.MarkContactUsed(app, h.contact, recipient, standing)

	delivered, refused := false, ""
	recipientId := ""
	if recipient != nil {
		recipientId = recipient.Id
		refused = services.ContactDeliveryRefusal(app, re.Auth, recipient, standing)
		if refused == "" {
			from := services.ContactSenderName(app, workspace, h.identityId)
			if err := services.DeliverToContact(app, re.Auth, recipient, h.kind, h.slug, h.label, from); err != nil {
				app.Logger().Error("Failed to deliver grant to contact", "error", err, "contact", h.contact.Id)
			} else {
				delivered = true
				services.RecordContactDelivery(app, re.Auth, recipient, workspace, h.kind)
			}
		}
	}

	// Mail only where there is no account to deliver to. Someone with an
	// account here already has the better channel, and mailing them as well
	// would double the outbound volume for nothing — and would turn a refused
	// delivery into the same message in their inbox, which is the flood this
	// guards against taking the other door.
	emailed, emailReason := false, ""
	if recipient == nil {
		emailed, emailReason = emailContactGrant(app, h, workspace)
	}

	// The audit row keeps the whole truth, including the refusal: the operator
	// is the one reader who must be able to see a sender working through
	// addresses.
	auditHandOver(app, re, h, recipientId, delivered, emailed, emailReason, refused)

	// A refused delivery is told as little as a stranger's: a sender who
	// learns they were blocked opens another account, and the person who
	// blocked them is the one with something to lose.
	return re.JSON(http.StatusOK, contactGrantAnswer(h, standing && refused == "", delivered, emailed))
}

// contactGrantAnswer is what the sender is told. Where something already
// connects the two it is the precise outcome; otherwise it says only that the
// grant exists and hands over the slug.
//
// Without that reserve the answer resolves an address for anyone who types
// one: "delivered" means the address has an account on this server, and
// "emailed" — only ever attempted where it has none — means it does not. Sixty
// addresses an hour, per account, with nothing to show for it on the other
// side. The slug is in every answer, so the sender always has a way to pass
// the grant on by hand; what they lose is the confirmation, until the
// recipient is somebody they are actually in touch with.
func contactGrantAnswer(h contactHandOver, precise, delivered, emailed bool) map[string]any {
	answer := map[string]any{
		"ok":   true,
		"id":   h.grant.Id,
		"slug": h.slug,
		"kind": h.kind,
	}
	if !precise {
		answer["delivered"] = false
		answer["emailed"] = false
		answer["channel"] = util.ContactChannelHandedOver
		return answer
	}
	answer["delivered"] = delivered
	answer["emailed"] = emailed
	switch {
	case delivered:
		answer["channel"] = util.ContactChannelAccount
	case emailed:
		answer["channel"] = util.ContactChannelEmail
	default:
		answer["channel"] = util.ContactChannelManual
	}
	return answer
}

// emailContactGrant queues the grant for email where the operator's policy
// allows it. It never fails the call: the grant exists and its slug is in the
// answer, so the sender can always pass it on by hand.
//
// `emailed` means queued, not accepted by a relay.
func emailContactGrant(app core.App, h contactHandOver, workspace string) (bool, string) {
	address := h.contact.GetString(util.Fields.Contact.Email)
	if strings.TrimSpace(address) == "" {
		return false, ""
	}
	// An ask is answered with an account, so without open signups the mail
	// would lead somewhere the recipient cannot finish.
	if h.kind == util.BookmarkKindRequest && !util.SignupsAllowed() {
		return false, "signups-closed"
	}
	ok, reason := services.MayEmailGrant(app, h.root.Domain(), address)
	if !ok {
		return false, reason
	}
	// The per-account cap already covers one person; this covers a workspace
	// that multiplies it by inviting members.
	if !workspaceMailLimiter.Allow(workspace) {
		return false, "rate"
	}
	err := services.EnqueueGrantEmail(app, address, services.GrantEmailPayload{
		Grant:      h.grant.Id,
		Collection: h.collection,
		Workspace:  workspace,
		Locale:     h.locale,
	})
	if err != nil {
		app.Logger().Error("Failed to queue a grant email", "error", err, "contact", h.contact.Id)
		return false, "queue"
	}
	return true, ""
}

// auditGrantCreated records a server-minted grant the way the request hooks
// record a direct one. Those hooks do not see this path, so without it an
// audit log filtered to links or requests is missing exactly the grants a
// member handed to somebody.
func auditGrantCreated(app core.App, re *core.RequestEvent, collection string, grant *core.Record) {
	services.RecordAudit(app, services.AuditEntry{
		Action:     util.AuditActionCreate,
		Collection: collection,
		RecordId:   grant.Id,
		Workspace:  grant.GetString(util.FieldWorkspace),
		User:       re.Auth.Id,
		Ip:         re.Request.RemoteAddr,
		UserAgent:  re.Request.UserAgent(),
		NewData:    grant.PublicExport(),
	})
}

// auditHandOver records who was given the grant, which is the question the
// grant's own create row cannot answer: a link carries no contact.
//
// The slug is deliberately absent. This row is about a capability now in
// somebody else's hands, and the audit log redacts a bookmark's slug for that
// same reason; the grant id is what leads back to the rest.
func auditHandOver(app core.App, re *core.RequestEvent, h contactHandOver,
	recipientId string, delivered, emailed bool, emailReason, refused string) {
	services.RecordAudit(app, services.AuditEntry{
		Action:     h.action,
		Collection: util.Coll.Contacts,
		RecordId:   h.contact.Id,
		Workspace:  h.contact.GetString(util.Fields.Contact.Workspace),
		User:       re.Auth.Id,
		Ip:         re.Request.RemoteAddr,
		UserAgent:  re.Request.UserAgent(),
		NewData: map[string]any{
			"grantCollection": h.collection,
			"grant":           h.grant.Id,
			"label":           h.label,
			"delivered":       delivered,
			"recipient":       recipientId,
			"emailed":         emailed,
			// Why not, as a short stable token. Never the address: an audit
			// row is read by people who hold no key, and the contact id in
			// recordId already leads to it.
			"emailReason": emailReason,
			// Why the recipient's tray was left alone — a block of theirs, or
			// the per-pair cap. Empty when nothing stood in the way.
			"refused": refused,
		},
	})
}

// mintUniqueSlug returns an unused capability slug for a collection. It fails
// rather than falling back to anything derivable: the slug is the only thing
// guarding what it names.
func mintUniqueSlug(app core.App, collection, prefix string) (string, error) {
	var lastErr error
	for attempt := 0; attempt < 5; attempt++ {
		token, err := util.GenerateToken(grantSlugBytes)
		if err != nil {
			lastErr = err
			continue
		}
		slug := prefix + token
		existing, _ := app.FindFirstRecordByFilter(collection, "slug = {:s}", map[string]any{"s": slug})
		if existing == nil {
			return slug, nil
		}
	}
	if lastErr == nil {
		lastErr = errors.New("exhausted slug attempts")
	}
	return "", lastErr
}
