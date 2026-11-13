package hooks

import (
	"encoding/json"
	"net/http"
	"slices"

	"revoked/cmd/revoked/services"
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tools/hook"
	"github.com/pocketbase/pocketbase/tools/types"
)

// BindVisibilityHooks keeps who sees and who edits sections, records, shares
// and requests
// (VISIBILITY.md) in step with everything it depends on, and keeps changing
// a section's audience the owner's own act.
//
//   - readers and editors are the server's: no client writes them.
//   - audienceKind, audienceGroups, editing (and a section's older shared
//     flag) change only by the item's owner, signed in as a person. An API key or a
//     connected tool may hold the section-update scope and must not use it to
//     widen who reads the vault. Each change is audited.
//   - Every save that can change the answer recomputes it inside the same
//     transaction: a section's own save, a record's, a section's deletion, a
//     membership or its permissions, a group's members.
//   - At startup, before requests are served, every row is checked and
//     repaired (services.ReconcileVisibility).
func BindVisibilityHooks(app core.App) {
	s := util.Fields.Section
	withAccessLists := []string{
		util.Coll.Sections, util.Coll.Records, util.Coll.Links, util.Coll.Requests,
		util.Coll.Templates, util.Coll.Contacts, util.Coll.Attestations,
	}

	for _, h := range []*hook.TaggedHook[*core.RecordRequestEvent]{
		app.OnRecordCreateRequest(withAccessLists...),
		app.OnRecordUpdateRequest(withAccessLists...),
	} {
		h.BindFunc(func(e *core.RecordRequestEvent) error {
			if err := util.RestrictFields(e, s.Readers, s.Editors); err != nil {
				return err
			}
			return e.Next()
		})
	}

	guard := func(e *core.RecordRequestEvent, isCreate bool) error {
		if e.RequestEvent.HasSuperuserAuth() {
			return e.Next()
		}
		translateLegacyShared(e)
		// Asking for a groups audience without a group is a mistake to report;
		// a group deleted later leaves the section with its owner instead.
		if e.Record.GetString(s.AudienceKind) == util.AudienceGroups &&
			len(e.Record.GetStringSlice(s.AudienceGroups)) == 0 {
			return util.AsFieldValidationError(s.AudienceKind, util.Errors.AudienceInvalid)
		}
		// A new item that names no audience gets its area's default in its
		// workspace, which is no change of audience: an API key may create
		// one.
		var before services.Audience
		named := e.Record.GetString(s.AudienceKind) != ""
		workspace := e.Record.GetString(s.Workspace)
		if isCreate {
			if workspace == "" && e.Auth != nil {
				switch e.Auth.Collection().Name {
				case util.Coll.Users:
					workspace = e.Auth.GetString(util.Fields.User.ActiveWorkspace)
				case util.Coll.ApiKeys:
					workspace = e.Auth.GetString(util.Fields.ApiKey.Workspace)
				}
			}
			before = services.DefaultAudienceIn(e.App, workspace, e.Record.Collection().Name)
			applyDefaultAudience(e.App, e.Record, workspace)
		} else {
			before = services.SectionAudience(e.Record.Original())
		}
		normalizeAudienceFields(e.Record)
		after := services.SectionAudience(e.Record)

		// The shared vault is locked: putting a vault entry or section before
		// anyone beside its owner takes the permission to publish
		// (VISIBILITY.md). A default that would publish quietly gives way to
		// private for a member without it; asking for it outright is refused.
		coll := e.Record.Collection().Name
		if (coll == util.Coll.Sections || coll == util.Coll.Records) && after.Kind != util.AudiencePrivate &&
			(isCreate || !sameAudience(before, after)) {
			mayPublish := e.Auth != nil && e.Auth.Collection().Name == util.Coll.Users &&
				services.HoldsPermission(e.App, workspace, e.Auth.Id, util.ScopeRecordPublish)
			if !mayPublish {
				if isCreate && !named {
					e.Record.Set(s.AudienceKind, util.AudiencePrivate)
					e.Record.Set(s.Editing, util.EditingOwner)
					normalizeAudienceFields(e.Record)
					return e.Next()
				}
				appErr := util.Errors.MissingPermission
				return e.RequestEvent.JSON(http.StatusForbidden, map[string]any{
					"code": appErr.ErrorCode, "message": "Publishing to the workspace vault takes its permission.",
					"status": http.StatusForbidden,
				})
			}
		}
		if sameAudience(before, after) {
			return e.Next()
		}
		if e.Auth == nil || e.Auth.Collection().Name != util.Coll.Users ||
			(!isCreate && e.Auth.Id != services.OwnerOf(e.Record.Original())) {
			appErr := util.Errors.AudienceByOwnerOnly
			return e.RequestEvent.JSON(http.StatusForbidden, map[string]any{
				"code": appErr.ErrorCode, "message": appErr.ErrorText, "status": http.StatusForbidden,
			})
		}
		if err := e.Next(); err != nil {
			return err
		}
		services.RecordAudit(app, services.AuditEntry{
			Action:     util.AuditActionUpdate,
			Collection: e.Record.Collection().Name,
			RecordId:   e.Record.Id,
			Workspace:  e.Record.GetString(s.Workspace),
			User:       e.Auth.Id,
			Ip:         e.RequestEvent.Request.RemoteAddr,
			UserAgent:  e.RequestEvent.Request.UserAgent(),
		})
		return nil
	}
	audienced := []string{
		util.Coll.Sections, util.Coll.Records, util.Coll.Links, util.Coll.Requests,
		util.Coll.Templates, util.Coll.Contacts, util.Coll.Attestations,
	}
	app.OnRecordCreateRequest(audienced...).BindFunc(func(e *core.RecordRequestEvent) error {
		return guard(e, true)
	})
	app.OnRecordUpdateRequest(audienced...).BindFunc(func(e *core.RecordRequestEvent) error {
		return guard(e, false)
	})

	// Shares, requests and workspace data: their own audience, nothing that
	// follows them.
	recomputeOwn := func(e *core.RecordEvent) error {
		// Server-made items (a sign-in's share, a responder's answer link, a
		// send to a contact) keep the built-in default; the workspace's
		// default is for what people create (the request guard above).
		if e.Record.IsNew() {
			applyDefaultAudience(nil, e.Record, "")
		}
		normalizeAudienceFields(e.Record)
		if err := validateAudience(e.App, e.Record); err != nil {
			return err
		}
		if err := e.Next(); err != nil {
			return err
		}
		return services.RecomputeItem(e.App, e.Record)
	}
	ownAudience := []string{
		util.Coll.Links, util.Coll.Requests,
		util.Coll.Templates, util.Coll.Contacts, util.Coll.Attestations,
	}
	app.OnRecordCreate(ownAudience...).BindFunc(recomputeOwn)
	app.OnRecordUpdate(ownAudience...).BindFunc(recomputeOwn)

	// Model level: every save, from the API or the server itself.
	app.OnRecordCreate(util.Coll.Sections).BindFunc(func(e *core.RecordEvent) error {
		normalizeAudienceFields(e.Record)
		if err := validateAudience(e.App, e.Record); err != nil {
			return err
		}
		if err := validateSectionView(e.Record); err != nil {
			return err
		}
		if err := e.Next(); err != nil {
			return err
		}
		return services.RecomputeSection(e.App, e.Record)
	})
	app.OnRecordUpdate(util.Coll.Sections).BindFunc(func(e *core.RecordEvent) error {
		normalizeAudienceFields(e.Record)
		if err := validateAudience(e.App, e.Record); err != nil {
			return err
		}
		if err := validateSectionView(e.Record); err != nil {
			return err
		}
		held := e.Record.Original().GetStringSlice(s.Records)
		if err := e.Next(); err != nil {
			return err
		}
		return services.RecomputeSection(e.App, e.Record, held...)
	})
	app.OnRecordDelete(util.Coll.Sections).BindFunc(func(e *core.RecordEvent) error {
		held := e.Record.GetStringSlice(s.Records)
		workspace := e.Record.GetString(s.Workspace)
		if err := e.Next(); err != nil {
			return err
		}
		return services.RecomputeRecordsById(e.App, workspace, held)
	})

	recomputeRecord := func(e *core.RecordEvent) error {
		if e.Record.IsNew() {
			applyDefaultAudience(nil, e.Record, "")
		}
		normalizeAudienceFields(e.Record)
		if err := validateAudience(e.App, e.Record); err != nil {
			return err
		}
		if err := e.Next(); err != nil {
			return err
		}
		return services.RecomputeRecord(e.App, e.Record)
	}
	app.OnRecordCreate(util.Coll.Records).BindFunc(recomputeRecord)
	app.OnRecordUpdate(util.Coll.Records).BindFunc(recomputeRecord)

	recomputeWorkspace := func(e *core.RecordEvent) error {
		workspace := e.Record.GetString(util.Fields.WorkspaceMember.Workspace)
		if err := e.Next(); err != nil {
			return err
		}
		return services.RecomputeWorkspace(e.App, workspace)
	}
	// Leaving a workspace leaves its groups too, inside the same transaction.
	app.OnRecordDelete(util.Coll.WorkspaceMembers).BindFunc(func(e *core.RecordEvent) error {
		if err := e.Next(); err != nil {
			return err
		}
		return services.LeaveWorkspaceGroups(e.App,
			e.Record.GetString(util.Fields.WorkspaceMember.Workspace),
			e.Record.GetString(util.Fields.WorkspaceMember.User))
	})
	app.OnRecordCreate(util.Coll.WorkspaceMembers).BindFunc(recomputeWorkspace)
	app.OnRecordUpdate(util.Coll.WorkspaceMembers).BindFunc(recomputeWorkspace)
	app.OnRecordDelete(util.Coll.WorkspaceMembers).BindFunc(recomputeWorkspace)

	recomputeGroup := func(group func(*core.Record) string) func(e *core.RecordEvent) error {
		return func(e *core.RecordEvent) error {
			id := group(e.Record)
			if err := e.Next(); err != nil {
				return err
			}
			return services.RecomputeGroup(e.App, id)
		}
	}
	memberGroup := func(r *core.Record) string { return r.GetString(util.Fields.GroupMember.Group) }
	app.OnRecordCreate(util.Coll.GroupMembers).BindFunc(recomputeGroup(memberGroup))
	app.OnRecordUpdate(util.Coll.GroupMembers).BindFunc(recomputeGroup(memberGroup))
	app.OnRecordDelete(util.Coll.GroupMembers).BindFunc(recomputeGroup(memberGroup))
	app.OnRecordDelete(util.Coll.Groups).BindFunc(recomputeGroup(func(r *core.Record) string { return r.Id }))

	// A workspace's defaults name areas and audiences the server knows.
	checkDefaults := func(e *core.RecordEvent) error {
		defaults := map[string]string{}
		raw := e.Record.GetString(util.Fields.Workspace.DefaultAudience)
		if raw != "" && raw != "null" {
			if err := e.Record.UnmarshalJSONField(util.Fields.Workspace.DefaultAudience, &defaults); err != nil ||
				!services.ValidDefaultAudience(defaults) {
				return util.AsFieldValidationError(util.Fields.Workspace.DefaultAudience, util.Errors.DefaultAudienceInvalid)
			}
		}
		return e.Next()
	}
	app.OnRecordCreate(util.Coll.Workspaces).BindFunc(checkDefaults)
	app.OnRecordUpdate(util.Coll.Workspaces).BindFunc(checkDefaults)

	app.OnServe().BindFunc(func(e *core.ServeEvent) error {
		filled, repaired, err := services.ReconcileVisibility(e.App)
		if err != nil {
			return err
		}
		if filled > 0 || repaired > 0 {
			e.App.Logger().Info("Visibility reconciled", "filled", filled, "repaired", repaired)
		}
		return e.Next()
	})
}

// translateLegacyShared lets an older app keep using the shared flag: setting
// it without an audience sets the audience it stood for.
func translateLegacyShared(e *core.RecordRequestEvent) {
	if e.Record.Collection().Name != util.Coll.Sections {
		return
	}
	info, err := e.RequestInfo()
	if err != nil {
		return
	}
	s := util.Fields.Section
	if _, ok := info.Body[s.Shared]; !ok {
		return
	}
	if _, ok := info.Body[s.AudienceKind]; ok {
		return
	}
	if e.Record.GetBool(s.Shared) {
		e.Record.Set(s.AudienceKind, util.AudienceWorkspace)
		if _, ok := info.Body[s.Editing]; !ok {
			e.Record.Set(s.Editing, util.EditingAudience)
		}
	} else {
		e.Record.Set(s.AudienceKind, util.AudiencePrivate)
	}
}

// applyDefaultAudience gives a new item that names no audience its area's
// default in its workspace (services.DefaultAudienceIn), or the built-in
// default when app is nil.
func applyDefaultAudience(app core.App, rec *core.Record, workspace string) {
	s := util.Fields.Section
	if rec.GetString(s.AudienceKind) != "" {
		return
	}
	// A section holding answers (or a sign-in's) follows its request, and
	// stays with its owner whatever the workspace prefers.
	if rec.Collection().Name == util.Coll.Sections && rec.GetString(s.RequestedBy) != "" {
		rec.Set(s.AudienceKind, util.AudiencePrivate)
		rec.Set(s.Editing, util.EditingOwner)
		return
	}
	d := services.DefaultAudience(rec.Collection().Name)
	if app != nil {
		d = services.DefaultAudienceIn(app, workspace, rec.Collection().Name)
	}
	rec.Set(s.AudienceKind, d.Kind)
	if rec.GetString(s.Editing) == "" {
		rec.Set(s.Editing, d.Editing)
	}
}

// normalizeAudienceFields stores the normalized audience, and keeps the older
// shared flag in step with it.
func normalizeAudienceFields(rec *core.Record) {
	s := util.Fields.Section
	a := services.SectionAudience(rec)
	rec.Set(s.AudienceKind, a.Kind)
	if a.Kind != util.AudienceGroups {
		rec.Set(s.AudienceGroups, []string{})
	}
	rec.Set(s.Editing, a.Editing)
	if rec.Collection().Name == util.Coll.Sections {
		rec.Set(s.Shared, a.Kind == util.AudienceWorkspace)
	}
}

// validateAudience refuses groups of another workspace, and any audience on a section that holds answers to a request
// (those follow their request, VISIBILITY.md §4.2).
// validateSectionView refuses a section view that is not a layout the app
// can read. An empty view is allowed: it shows the plain list.
func validateSectionView(rec *core.Record) error {
	field := util.Fields.Section.View
	raw := rec.Get(field)
	if raw == nil {
		return nil
	}
	var view any
	switch v := raw.(type) {
	case types.JSONRaw:
		if len(v) == 0 || string(v) == "null" {
			return nil
		}
		if err := json.Unmarshal(v, &view); err != nil {
			return util.AsFieldValidationError(field, util.Errors.SectionViewInvalid)
		}
	default:
		view = v
	}
	if view == nil {
		return nil
	}
	if err := services.ValidateSectionView(view); err != nil {
		return util.AsFieldValidationError(field, util.Errors.SectionViewInvalid)
	}
	return nil
}

func validateAudience(app core.App, rec *core.Record) error {
	s := util.Fields.Section
	kind := rec.GetString(s.AudienceKind)
	groups := rec.GetStringSlice(s.AudienceGroups)
	coll := rec.Collection().Name
	if (coll == util.Coll.Sections || coll == util.Coll.Records) && rec.GetString(s.RequestedBy) != "" &&
		kind != util.AudiencePrivate {
		return util.AsFieldValidationError(s.AudienceKind, util.Errors.AudienceInvalid)
	}
	// An alias would show a record its owner never published, and a file has
	// no member download path yet: both stay with their owner.
	if coll == util.Coll.Records && kind != util.AudiencePrivate &&
		(rec.GetString(util.Fields.Record.AliasOf) != "" || rec.GetString(util.Fields.Record.Type) == util.TypeFile) {
		return util.AsFieldValidationError(s.AudienceKind, util.Errors.AudienceInvalid)
	}
	workspace := rec.GetString(s.Workspace)
	for _, id := range groups {
		g, err := app.FindRecordById(util.Coll.Groups, id)
		if err != nil || g == nil || g.GetString(util.Fields.Group.Workspace) != workspace {
			return util.AsFieldValidationError(s.AudienceGroups, util.Errors.AudienceInvalid)
		}
	}
	return nil
}

func sameAudience(a, b services.Audience) bool {
	ga, gb := slices.Clone(a.Groups), slices.Clone(b.Groups)
	slices.Sort(ga)
	slices.Sort(gb)
	return a.Kind == b.Kind && a.Editing == b.Editing && slices.Equal(ga, gb)
}
