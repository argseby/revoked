package routes

import (
	"net/http"
	"net/url"
	"regexp"
	"slices"
	"strconv"
	"strings"

	"revoked/cmd/revoked/server"
	"revoked/cmd/revoked/services"
	"revoked/util"

	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/core"
)

// connectionGrant is what the owner decides for a tool, from the app. Left
// out, a connection keeps what it had.
//
// Permissions are catalogue keys (util.ConnectionPermissions); the vault keys
// among them set vaultAccess. AllowRevoke and AllowHandOver stand for the
// narrower "End what it proposed" and "Receive links" and edit the same scopes.
// Section gives the tool its own section, or takes its vault access away;
// Sections are those the owner adds, which the tool may read and not change.
type connectionGrant struct {
	Permissions    *[]string `json:"permissions"`
	AllowRevoke    *bool     `json:"allowRevoke"`
	AllowHandOver  *bool     `json:"allowHandOver"`
	AllowVaultRead *bool     `json:"allowVaultRead"`
	Section        *bool     `json:"section"`
	Sections       *[]string `json:"sections"`
}

// applyConnectionGrant sets a grant on the connection without saving it, or
// reports what it refused. Only what the granter holds can be given, as for a
// key: the narrow end and hand-over scopes excepted, which act only on what
// the tool itself proposed.
func applyConnectionGrant(app core.App, conn *core.Record, g connectionGrant, granter []string) *util.AppError {
	f := util.Fields.Connection
	scopes := conn.GetStringSlice(f.Scopes)
	access := conn.GetString(f.VaultAccess)

	if g.Permissions != nil {
		rest, vault := util.SplitVaultPermissions(*g.Permissions)
		for _, key := range rest {
			if !slices.Contains(util.ConnectionPermissions, key) {
				refused := util.Errors.ConnectionPermissionInvalid
				refused.ErrorText += " Refused: " + key + "."
				return &refused
			}
		}
		expanded, _ := util.ExpandPermissions(rest)
		if missing := util.MissingScopes(granter, expanded); len(missing) > 0 {
			return &util.Errors.PermissionEscalation
		}
		if vault != "" {
			want := []string{util.ScopeRecordRead}
			if vault == util.VaultAccessWrite {
				want = append(want, util.ScopeRecordCreate, util.ScopeRecordUpdate, util.ScopeRecordDelete)
			}
			if !util.HasAllScopes(granter, want) {
				return &util.Errors.PermissionEscalation
			}
		}
		next := expanded
		if util.HasAllScopes(scopes, util.ConnectionEndScopes) {
			next = appendMissing(next, util.ConnectionEndScopes...)
		}
		if slices.Contains(scopes, util.ConnectionHandOverScope) {
			next = appendMissing(next, util.ConnectionHandOverScope)
		}
		scopes, access = next, vault
	}
	if g.AllowRevoke != nil {
		scopes = setScopes(scopes, *g.AllowRevoke, util.ConnectionEndScopes...)
	}
	if g.AllowHandOver != nil {
		scopes = setScopes(scopes, *g.AllowHandOver, util.ConnectionHandOverScope)
	}
	if g.AllowVaultRead != nil {
		conn.Set(f.AllowVaultRead, *g.AllowVaultRead)
		if *g.AllowVaultRead && access == "" {
			access = util.VaultAccessRead
		}
	}
	// Its own section is somewhere to keep things: asking for it asks to
	// read and write there, unless the owner said read only. Taking it away
	// switches the section off and keeps it, so giving it back brings the
	// same section, with what is in it, and the sections the owner added
	// stay readable meanwhile.
	if g.Section != nil {
		conn.Set(f.SectionOff, !*g.Section)
		if *g.Section && access == "" {
			access = util.VaultAccessWrite
		}
	}
	if g.Sections != nil {
		ids := []string{}
		for _, id := range *g.Sections {
			s, err := app.FindRecordById(util.Coll.Sections, id)
			if err != nil || s == nil ||
				s.GetString(util.Fields.Section.Workspace) != conn.GetString(f.Workspace) ||
				s.GetString(util.Fields.Section.User) != conn.GetString(f.User) ||
				s.GetString(util.Fields.Section.RequestedBy) != "" {
				return &util.Errors.VaultSectionInvalid
			}
			if !slices.Contains(ids, id) {
				ids = append(ids, id)
			}
		}
		conn.Set(f.Sections, ids)
		// Adding a section is letting the tool read it.
		if len(ids) > 0 && access == "" {
			access = util.VaultAccessRead
		}
	}
	conn.Set(f.Scopes, scopes)
	conn.Set(f.VaultAccess, access)
	return nil
}

func appendMissing(scopes []string, add ...string) []string {
	for _, s := range add {
		if !slices.Contains(scopes, s) {
			scopes = append(scopes, s)
		}
	}
	return scopes
}

func setScopes(scopes []string, on bool, which ...string) []string {
	if on {
		return appendMissing(scopes, which...)
	}
	return slices.DeleteFunc(slices.Clone(scopes), func(s string) bool { return slices.Contains(which, s) })
}

var sectionKeyUnsafe = regexp.MustCompile(`[^a-z0-9_]+`)

// ensureOwnSection gives a connection that asked for one its own section,
// named after the tool. A section the owner deleted is replaced; one the
// connection already has is kept, with what is in it.
func ensureOwnSection(app core.App, conn *core.Record, g connectionGrant) error {
	f := util.Fields.Connection
	if g.Section == nil || !*g.Section {
		return nil
	}
	if id := conn.GetString(f.Section); id != "" {
		if s, err := app.FindRecordById(util.Coll.Sections, id); err == nil && s != nil {
			return nil
		}
	}
	name := conn.GetString(f.ClientName)
	if name == "" {
		name = strings.TrimPrefix(strings.TrimPrefix(conn.GetString(f.ClientId), "https://"), "http://")
	}
	base := strings.Trim(sectionKeyUnsafe.ReplaceAllString(strings.ToLower(name), "_"), "_")
	if base == "" {
		base = "tool"
	}
	if len(base) > 60 {
		base = base[:60]
	}
	key := base
	for n := 2; ; n++ {
		taken, _ := app.FindFirstRecordByFilter(util.Coll.Sections,
			"workspace = {:ws} && user = {:user} && key = {:key}",
			dbx.Params{"ws": conn.GetString(f.Workspace), "user": conn.GetString(f.User), "key": key})
		if taken == nil {
			break
		}
		key = base + "_" + strconv.Itoa(n)
	}
	coll, err := app.FindCollectionByNameOrId(util.Coll.Sections)
	if err != nil {
		return err
	}
	section := core.NewRecord(coll)
	// A tool's own section is its owner's alone until they widen it, whatever
	// the workspace's default (VISIBILITY.md).
	section.Set(util.Fields.Section.AudienceKind, util.AudiencePrivate)
	section.Set(util.Fields.Section.Editing, util.EditingOwner)
	section.Set(util.Fields.Section.Key, key)
	section.Set(util.Fields.Section.Name, name)
	section.Set(util.Fields.Section.User, conn.GetString(f.User))
	section.Set(util.Fields.Section.Workspace, conn.GetString(f.Workspace))
	if err := app.Save(section); err != nil {
		return err
	}
	conn.Set(f.Section, section.Id)
	return app.Save(conn)
}

func connectionHas(conn *core.Record, scope string) bool {
	return slices.Contains(conn.GetStringSlice(util.Fields.Connection.Scopes), scope)
}

// connectionGrantView is what a tool and its owner see of what it may do.
// With a token, it also says whether that token reaches the whole vault.
func connectionGrantView(conn, token *core.Record) map[string]any {
	f := util.Fields.Connection
	scopes := conn.GetStringSlice(f.Scopes)
	view := map[string]any{
		"permissions":    util.HeldPermissions(scopes, conn.GetString(f.VaultAccess)),
		"vaultAccess":    conn.GetString(f.VaultAccess),
		"section":        conn.GetString(f.Section),
		"sectionOff":     conn.GetBool(f.SectionOff),
		"sections":       conn.GetStringSlice(f.Sections),
		"allowRevoke":    util.HasAllScopes(scopes, util.ConnectionEndScopes),
		"allowHandOver":  slices.Contains(scopes, util.ConnectionHandOverScope),
		"allowVaultRead": conn.GetBool(f.AllowVaultRead),
	}
	if token != nil {
		view["vaultReadable"] = vaultReadable(conn, token)
	}
	return view
}

// ConnectionCreateRoute lets a tool create shares and requests itself, where
// the owner gave it the permission:
//
//	POST /api/connection/links      a share of records and sections within its reach
//	POST /api/connection/requests   a request in the owner's workspace
//
// Both belong to the owner and join the connection, exactly as a proposal the
// owner saved does; the owner can pause, change or revoke them in the app.
func ConnectionCreateRoute(app core.App, root *server.RootKey) {
	app.OnServe().BindFunc(func(e *core.ServeEvent) error {
		e.Router.POST("/api/connection/links", func(re *core.RequestEvent) error {
			token, conn, _, ok := connectionTokenFromRequest(app, re)
			if !ok {
				return nil
			}
			c := services.ConnectionCredential(conn, token)
			if !c.Has(util.ScopeLinkCreate) {
				return appErrorResponse(re, http.StatusForbidden, &util.Errors.ConnectionNotPermitted)
			}
			var body struct {
				Label     string   `json:"label"`
				Records   []string `json:"records"`
				Sections  []string `json:"sections"`
				ExpiresAt string   `json:"expiresAt"`
				MaxViews  int      `json:"maxViews"`
				Ref       string   `json:"ref"`
			}
			if err := re.BindBody(&body); err != nil {
				return appErrorResponse(re, http.StatusBadRequest, &util.Errors.InvalidRequestBody)
			}
			label := strings.TrimSpace(body.Label)
			if label == "" {
				return appErrorResponse(re, http.StatusBadRequest, &util.Errors.ValidationFieldRequired)
			}
			if len(body.Records) == 0 && len(body.Sections) == 0 {
				return appErrorResponse(re, http.StatusBadRequest, &util.Errors.ContactNothingToSend)
			}
			// A share hands out values, so it may hold only what the tool
			// could read itself.
			for _, id := range body.Records {
				rec, err := app.FindRecordById(util.Coll.Records, id)
				if err != nil || !c.RecordInReach(app, rec) {
					return appErrorResponse(re, http.StatusNotFound, &util.Errors.RecordNotFound)
				}
			}
			for _, id := range body.Sections {
				if !c.SectionInReach(app, id) {
					return appErrorResponse(re, http.StatusNotFound, &util.Errors.RecordNotFound)
				}
			}
			expires, ok := parseGrantExpiry(re, body.ExpiresAt)
			if !ok {
				return nil
			}
			slug, err := services.MintUniqueSlug(app, util.Coll.Links, "")
			if err != nil {
				return re.InternalServerError("Failed to create the share", err)
			}
			coll, err := app.FindCollectionByNameOrId(util.Coll.Links)
			if err != nil {
				return re.InternalServerError("Link collection missing", err)
			}
			lf := util.Fields.Link
			link := core.NewRecord(coll)
			// What a tool creates is its owner's alone until they widen it
			// in the app, whatever the workspace's default (VISIBILITY.md).
			link.Set(util.Fields.Section.AudienceKind, util.AudiencePrivate)
			link.Set(util.Fields.Section.Editing, util.EditingOwner)
			link.Set(lf.Slug, slug)
			link.Set(lf.Label, label)
			link.Set(lf.User, c.User)
			link.Set(lf.Workspace, c.Workspace)
			link.Set(lf.Records, body.Records)
			link.Set(lf.Sections, body.Sections)
			link.Set(lf.Status, util.StatusActive)
			link.Set(lf.ExpiresAt, expires)
			link.Set(lf.Connection, conn.Id)
			link.Set(lf.Ref, strings.TrimSpace(body.Ref))
			link.Set(lf.HandedOver, c.Has(util.ConnectionHandOverScope))
			if body.MaxViews > 0 {
				link.Set(lf.MaxViews, body.MaxViews)
			}
			if err := app.Save(link); err != nil {
				return re.BadRequestError("The share could not be saved.", err)
			}
			auditConnection(app, re, conn, auditToolCreatedLink, map[string]any{"link": link.Id})
			view := connectionLinkView(conn, link, root.Domain())
			// The tool made it to hand out, and could read all of it anyway.
			view["url"] = publicLinkURL(root.Domain(), slug)
			return re.JSON(http.StatusCreated, view)
		})

		e.Router.POST("/api/connection/requests", func(re *core.RequestEvent) error {
			token, conn, _, ok := connectionTokenFromRequest(app, re)
			if !ok {
				return nil
			}
			if !connectionHas(conn, util.ScopeRequestCreate) {
				return appErrorResponse(re, http.StatusForbidden, &util.Errors.ConnectionNotPermitted)
			}
			// A request asks strangers for data in the owner's name. Whoever
			// sent the owner a connect link can read them its check code, so a
			// polled answer never carries that.
			if token.GetBool(util.Fields.ConnectionToken.Poll) {
				return appErrorResponse(re, http.StatusForbidden, &util.Errors.ConnectionPolled)
			}
			var body struct {
				Label        string `json:"label"`
				Template     string `json:"template"`
				Identity     string `json:"identity"`
				ExpiresAt    string `json:"expiresAt"`
				MaxResponses int    `json:"maxResponses"`
				Ref          string `json:"ref"`
			}
			if err := re.BindBody(&body); err != nil {
				return appErrorResponse(re, http.StatusBadRequest, &util.Errors.InvalidRequestBody)
			}
			label := strings.TrimSpace(body.Label)
			if label == "" {
				return appErrorResponse(re, http.StatusBadRequest, &util.Errors.ValidationFieldRequired)
			}
			workspace := conn.GetString(util.Fields.Connection.Workspace)
			template := ""
			if body.Template != "" {
				t, err := app.FindRecordById(util.Coll.Templates, body.Template)
				if err != nil || t == nil {
					t, err = app.FindFirstRecordByFilter(util.Coll.Templates,
						"workspace = {:ws} && name = {:name}", dbx.Params{"ws": workspace, "name": body.Template})
				}
				// The tool acts for its owner, so it may use what they see.
				if err != nil || t == nil || t.GetString(util.Fields.Template.Workspace) != workspace ||
					!services.CanSee(app, conn.GetString(util.Fields.Connection.User), t) {
					return appErrorResponse(re, http.StatusForbidden, &util.Errors.TemplateNotOwned)
				}
				template = t.Id
			}
			// A request asks in the name of an identity. Left out, it is the
			// workspace's primary one, as the app offers first.
			if body.Identity == "" {
				primary, _ := app.FindFirstRecordByFilter(util.Coll.Identities,
					"workspace = {:ws} && isPrimary = true && (status = '' || status = 'active')",
					dbx.Params{"ws": workspace})
				if primary != nil {
					body.Identity = primary.Id
				}
			}
			if appErr := authorizeAskIdentity(app, workspace, body.Identity); appErr != nil {
				return appErrorResponse(re, http.StatusForbidden, appErr)
			}
			expires, ok := parseGrantExpiry(re, body.ExpiresAt)
			if !ok {
				return nil
			}
			slug, err := services.MintUniqueSlug(app, util.Coll.Requests, "")
			if err != nil {
				return re.InternalServerError("Failed to create the request", err)
			}
			coll, err := app.FindCollectionByNameOrId(util.Coll.Requests)
			if err != nil {
				return re.InternalServerError("Request collection missing", err)
			}
			rf := util.Fields.Request
			req := core.NewRecord(coll)
			// Private, as everything a tool creates (VISIBILITY.md).
			req.Set(util.Fields.Section.AudienceKind, util.AudiencePrivate)
			req.Set(util.Fields.Section.Editing, util.EditingOwner)
			req.Set(rf.Slug, slug)
			req.Set(rf.Label, label)
			req.Set(rf.Status, util.StatusActive)
			req.Set(rf.Identity, body.Identity)
			req.Set(rf.Template, template)
			req.Set(rf.User, conn.GetString(util.Fields.Connection.User))
			req.Set(rf.Workspace, workspace)
			req.Set(rf.Connection, conn.Id)
			req.Set(rf.Ref, strings.TrimSpace(body.Ref))
			if body.MaxResponses > 0 {
				req.Set(rf.MaxResponses, body.MaxResponses)
			}
			req.Set(rf.AllowExtraFields, template == "")
			req.Set(rf.ExpiresAt, expires)
			if err := app.Save(req); err != nil {
				return re.BadRequestError("The request could not be saved.", err)
			}
			auditConnection(app, re, conn, auditToolCreatedRequest, map[string]any{"request": req.Id})
			view := connectionRequestView(req)
			// Its own request, to pass on to whoever should answer it. Answering
			// takes an account, so the link opens the app.
			origin := strings.TrimSuffix(publicLinkURL(root.Domain(), ""), "/s/")
			view["url"] = "revoked://r/" + url.QueryEscape(origin) + "/" + url.QueryEscape(slug)
			return re.JSON(http.StatusCreated, view)
		})
		return e.Next()
	})
}
