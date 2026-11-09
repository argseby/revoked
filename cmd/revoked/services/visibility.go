package services

import (
	"encoding/json"
	"slices"

	"revoked/util"

	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/core"
)

// Who sees and who edits an item inside its workspace (VISIBILITY.md).
//
// This file is the single answer. The collection rules match the readers and
// editors columns, which hold what Expected* below computes; every hook that
// can change the answer recomputes them, and ReconcileVisibility checks and
// repairs them at startup. Routes that load rows outside the rules ask
// CanSee / CanEdit directly.
//
// Sections, shares (links) and requests carry an audience of their own;
// records follow the sections holding them (phase 1), and the answers to a
// request follow the request (phase 2, through the routes that read them):
//
//   - A section is seen by its owner and by its audience (every member, or
//     the members of the listed groups) holding the section-read permission.
//     With editing "audience", those of them holding section-update edit it.
//   - A record is seen by its owner and by everyone who sees a section of the
//     same owner holding it, with record-read; edited likewise with
//     record-update where the section's editing is "audience". Answers to
//     requests, files and aliases stay with their owner for now.
//   - A share or a request is seen by its owner and its audience holding the
//     area's read permission (link:read, request:read), and edited by those
//     of them holding its update permission where editing is "audience".

// audienceArea names the permissions an item with an audience is read and
// edited with, and how a new one starts.
type audienceArea struct {
	// read is the permission the audience needs to see the item; empty means
	// none, as for templates and contacts, which every member read before
	// audiences existed (VISIBILITY.md, phase 3). Attestations always needed
	// attestations:read, checked by their own hook as well.
	read string
	// edit is the permission the audience, or the owner where owning is not
	// enough, needs to change it.
	edit string
	// publish is a further permission the audience needs to change an item
	// that is visible beyond its owner: the shared vault is locked to those
	// who may publish to it (record:publish).
	publish string
	// ownerNeedsPermission marks an area where owning the row is not enough
	// to change it: an attestation speaks for the domain, so whoever issued
	// it still needs the permission to revoke it.
	ownerNeedsPermission bool
	// defaultAudience is the audience of a new item that names none:
	// private for vault, shares and requests, the workspace for what was
	// workspace data before.
	defaultAudience Audience
}

var (
	privateByDefault   = Audience{Kind: util.AudiencePrivate, Editing: util.EditingOwner}
	workspaceByDefault = Audience{Kind: util.AudienceWorkspace, Editing: util.EditingAudience}
)

// audienceAreas are the collections whose rows carry an audience of their
// own, and the permissions that go with them.
var audienceAreas = map[string]audienceArea{
	util.Coll.Sections:     {read: util.ScopeSectionRead, edit: util.ScopeSectionUpdate, publish: util.ScopeRecordPublish, defaultAudience: privateByDefault},
	util.Coll.Records:      {read: util.ScopeRecordRead, edit: util.ScopeRecordUpdate, publish: util.ScopeRecordPublish, defaultAudience: privateByDefault},
	util.Coll.Links:        {read: util.ScopeLinkRead, edit: util.ScopeLinkUpdate, defaultAudience: privateByDefault},
	util.Coll.Requests:     {read: util.ScopeRequestRead, edit: util.ScopeRequestUpdate, defaultAudience: privateByDefault},
	util.Coll.Templates:    {edit: util.ScopeTemplateUpdate, defaultAudience: workspaceByDefault},
	util.Coll.Contacts:     {edit: util.ScopeContactUpdate, defaultAudience: workspaceByDefault},
	util.Coll.Attestations: {read: util.ScopeAttestationRead, edit: util.ScopeAttestationUpdate, ownerNeedsPermission: true, defaultAudience: workspaceByDefault},
}

// OwnerOf is the member who owns an item, whose own it always is. Contacts
// keep theirs in createdBy: their user is the account they point to.
func OwnerOf(item *core.Record) string {
	if item.Collection().Name == util.Coll.Contacts {
		return item.GetString(util.Fields.Contact.CreatedBy)
	}
	return item.GetString(util.FieldUser)
}

// DefaultAudience is the built-in audience a new item of a collection starts
// with, before any workspace setting.
func DefaultAudience(collection string) Audience {
	if area, ok := audienceAreas[collection]; ok {
		return area.defaultAudience
	}
	return privateByDefault
}

// DefaultAudienceIn is the audience a new item of a collection starts with in
// a workspace: the workspace's own default for the area (VISIBILITY.md §4.4),
// or the built-in one.
func DefaultAudienceIn(app core.App, workspace, collection string) Audience {
	if workspace != "" {
		if ws, err := app.FindRecordById(util.Coll.Workspaces, workspace); err == nil && ws != nil {
			defaults := map[string]string{}
			_ = ws.UnmarshalJSONField(util.Fields.Workspace.DefaultAudience, &defaults)
			switch defaults[collection] {
			case util.AudiencePrivate:
				return privateByDefault
			case util.AudienceWorkspace:
				return workspaceByDefault
			}
		}
	}
	return DefaultAudience(collection)
}

// ValidDefaultAudience checks a workspace's defaults: areas with an audience,
// each private or workspace.
func ValidDefaultAudience(defaults map[string]string) bool {
	for coll, kind := range defaults {
		if !HasAudience(coll) || (kind != util.AudiencePrivate && kind != util.AudienceWorkspace) {
			return false
		}
	}
	return true
}

// HasAudience reports whether a collection's rows carry an audience.
func HasAudience(collection string) bool {
	_, ok := audienceAreas[collection]
	return ok
}

// Audience is a section's audience, normalized: an empty kind reads as
// private, "groups" with no group reads as private, and an empty editing
// setting reads as owner.
type Audience struct {
	Kind    string
	Groups  []string
	Editing string
}

// SectionAudience reads the audience of a section, share or request (the
// fields have the same names in each).
func SectionAudience(sec *core.Record) Audience {
	s := util.Fields.Section
	a := Audience{
		Kind:    sec.GetString(s.AudienceKind),
		Groups:  sec.GetStringSlice(s.AudienceGroups),
		Editing: sec.GetString(s.Editing),
	}
	if a.Kind != util.AudienceWorkspace && a.Kind != util.AudienceGroups {
		a.Kind = util.AudiencePrivate
	}
	if a.Kind == util.AudienceGroups && len(a.Groups) == 0 {
		a.Kind = util.AudiencePrivate
	}
	if a.Kind != util.AudienceGroups {
		a.Groups = nil
	}
	if a.Editing != util.EditingAudience {
		a.Editing = util.EditingOwner
	}
	return a
}

// workspaceView is what the answer depends on for one workspace: each
// member's permissions (nil for a legacy row, which holds all of them) and
// the members of each group named so far.
type workspaceView struct {
	app       core.App
	workspace string
	members   map[string][]string
	groups    map[string]map[string]bool
}

func loadWorkspaceView(app core.App, workspace string) *workspaceView {
	v := &workspaceView{app: app, workspace: workspace, members: map[string][]string{}, groups: map[string]map[string]bool{}}
	rows, err := app.FindAllRecords(util.Coll.WorkspaceMembers,
		dbx.HashExp{util.Fields.WorkspaceMember.Workspace: workspace})
	if err != nil {
		return v
	}
	for _, m := range rows {
		perms := m.GetStringSlice(util.Fields.WorkspaceMember.Permissions)
		if len(perms) == 0 {
			perms = nil
		}
		v.members[m.GetString(util.Fields.WorkspaceMember.User)] = perms
	}
	return v
}

func (v *workspaceView) isMember(user string) bool {
	_, ok := v.members[user]
	return ok
}

func (v *workspaceView) holds(user, scope string) bool {
	perms, ok := v.members[user]
	if !ok {
		return false
	}
	return scope == "" || perms == nil || slices.Contains(perms, scope)
}

// groupUsers lists the members of a group, only when the group belongs to
// this workspace.
func (v *workspaceView) groupUsers(group string) map[string]bool {
	if users, ok := v.groups[group]; ok {
		return users
	}
	users := map[string]bool{}
	v.groups[group] = users
	g, err := v.app.FindRecordById(util.Coll.Groups, group)
	if err != nil || g == nil || g.GetString(util.Fields.Group.Workspace) != v.workspace {
		return users
	}
	rows, err := v.app.FindAllRecords(util.Coll.GroupMembers, dbx.HashExp{util.Fields.GroupMember.Group: group})
	if err != nil {
		return users
	}
	for _, r := range rows {
		users[r.GetString(util.Fields.GroupMember.User)] = true
	}
	return users
}

// inAudience reports whether a member belongs to an audience (owner aside).
func (v *workspaceView) inAudience(user string, a Audience) bool {
	if !v.isMember(user) {
		return false
	}
	switch a.Kind {
	case util.AudienceWorkspace:
		return true
	case util.AudienceGroups:
		for _, g := range a.Groups {
			if v.groupUsers(g)[user] {
				return true
			}
		}
	}
	return false
}

// audienceAccess lists who reads and who edits under one audience, beside
// the owner, with the given read and edit permissions.
func (v *workspaceView) audienceAccess(a Audience, readScope, editScope, publishScope string, readers, editors map[string]bool) {
	if a.Kind == util.AudiencePrivate {
		return
	}
	for user := range v.members {
		if !v.inAudience(user, a) || !v.holds(user, readScope) {
			continue
		}
		readers[user] = true
		if a.Editing == util.EditingAudience && v.holds(user, editScope) && v.holds(user, publishScope) {
			editors[user] = true
		}
	}
}

// ownAccess is the answer for a row with an audience of its own. A section
// holding answers to a request keeps none: it follows its request.
func (v *workspaceView) ownAccess(item *core.Record, area audienceArea) (readers, editors []string) {
	r, e := map[string]bool{}, map[string]bool{}
	if owner := OwnerOf(item); owner != "" {
		r[owner] = true
		if !area.ownerNeedsPermission || v.holds(owner, area.edit) {
			e[owner] = true
		}
	}
	answers := item.Collection().Name == util.Coll.Sections &&
		item.GetString(util.Fields.Section.RequestedBy) != ""
	if !answers {
		v.audienceAccess(SectionAudience(item), area.read, area.edit, area.publish, r, e)
	}
	return sortedKeys(r), sortedKeys(e)
}

func (v *workspaceView) sectionAccess(sec *core.Record) (readers, editors []string) {
	return v.ownAccess(sec, audienceAreas[util.Coll.Sections])
}

// recordSharesThroughSections reports whether a record can be seen through
// the sections holding it at all. Answers stay with the request (phase 2);
// files have no member download path yet, and an alias would show a record
// its owner never put in the section.
func recordSharesThroughSections(rec *core.Record) bool {
	r := util.Fields.Record
	return rec.GetString(r.RequestedBy) == "" &&
		rec.GetString(r.Type) != util.TypeFile &&
		rec.GetString(r.AliasOf) == ""
}

// sectionsHolding lists the sections of the record's own owner, in its
// workspace, that hold it. Only those count: a section naming someone else's
// record shares nothing of theirs.
func sectionsHolding(app core.App, rec *core.Record) []*core.Record {
	s := util.Fields.Section
	rows, err := app.FindRecordsByFilter(util.Coll.Sections,
		s.Workspace+" = {:w} && "+s.User+" = {:u} && "+s.Records+" ~ {:id}", "", 0, 0,
		dbx.Params{"w": rec.GetString(util.FieldWorkspace), "u": rec.GetString(util.FieldUser), "id": rec.Id})
	if err != nil {
		return nil
	}
	out := rows[:0]
	for _, sec := range rows {
		if slices.Contains(sec.GetStringSlice(s.Records), rec.Id) {
			out = append(out, sec)
		}
	}
	return out
}

func (v *workspaceView) recordAccess(rec *core.Record) (readers, editors []string) {
	r, e := map[string]bool{}, map[string]bool{}
	if owner := rec.GetString(util.FieldUser); owner != "" {
		r[owner], e[owner] = true, true
	}
	if recordSharesThroughSections(rec) {
		// Its own visibility, set when it was made or since (an entry of the
		// company's root vault, say), and that of every section holding it.
		v.audienceAccess(SectionAudience(rec), util.ScopeRecordRead, util.ScopeRecordUpdate, util.ScopeRecordPublish, r, e)
		for _, sec := range sectionsHolding(v.app, rec) {
			if sec.GetString(util.Fields.Section.RequestedBy) != "" {
				continue
			}
			v.audienceAccess(SectionAudience(sec), util.ScopeRecordRead, util.ScopeRecordUpdate, util.ScopeRecordPublish, r, e)
		}
	}
	return sortedKeys(r), sortedKeys(e)
}

// ExpectedAccess computes who reads and who edits a section or record.
func ExpectedAccess(app core.App, item *core.Record) (readers, editors []string) {
	v := loadWorkspaceView(app, item.GetString(util.FieldWorkspace))
	return v.access(item)
}

func (v *workspaceView) access(item *core.Record) (readers, editors []string) {
	name := item.Collection().Name
	if name == util.Coll.Records {
		return v.recordAccess(item)
	}
	if area, ok := audienceAreas[name]; ok {
		return v.ownAccess(item, area)
	}
	return nil, nil
}

// CanSee reports whether a member sees a section, record, share or request. The owner always
// does while still a member of the item's workspace.
func CanSee(app core.App, user string, item *core.Record) bool {
	v := loadWorkspaceView(app, item.GetString(util.FieldWorkspace))
	if !v.isMember(user) {
		return false
	}
	readers, _ := v.access(item)
	return slices.Contains(readers, user)
}

// CanEdit reports whether a member may change a section, record, share or
// request.
func CanEdit(app core.App, user string, item *core.Record) bool {
	v := loadWorkspaceView(app, item.GetString(util.FieldWorkspace))
	if !v.isMember(user) {
		return false
	}
	_, editors := v.access(item)
	return slices.Contains(editors, user)
}

// storedAccess reads the readers and editors columns as they are.
func storedAccess(item *core.Record) (readers, editors []string) {
	readers = slices.Clone(item.GetStringSlice(util.Fields.Section.Readers))
	editors = slices.Clone(item.GetStringSlice(util.Fields.Section.Editors))
	slices.Sort(readers)
	slices.Sort(editors)
	return readers, editors
}

// writeAccess stores readers and editors straight into the row, without the
// record hooks (which would recompute again) and without touching updated.
// app is the caller's, so inside a transaction it writes inside it.
func writeAccess(app core.App, item *core.Record, readers, editors []string) error {
	r, _ := json.Marshal(nonNil(readers))
	e, _ := json.Marshal(nonNil(editors))
	_, err := app.DB().Update(item.Collection().Name, dbx.Params{
		util.Fields.Section.Readers: string(r),
		util.Fields.Section.Editors: string(e),
	}, dbx.HashExp{"id": item.Id}).Execute()
	if err == nil {
		item.Set(util.Fields.Section.Readers, readers)
		item.Set(util.Fields.Section.Editors, editors)
	}
	return err
}

func (v *workspaceView) recompute(item *core.Record) error {
	readers, editors := v.access(item)
	sr, se := storedAccess(item)
	if slices.Equal(readers, sr) && slices.Equal(editors, se) {
		return nil
	}
	return writeAccess(v.app, item, readers, editors)
}

// visibilityCollections are every collection with readers and editors.
var visibilityCollections = []string{
	util.Coll.Sections, util.Coll.Records, util.Coll.Links, util.Coll.Requests,
	util.Coll.Templates, util.Coll.Contacts, util.Coll.Attestations,
}

// RecomputeItem refreshes one row's readers and editors: a share or a
// request, or a record.
func RecomputeItem(app core.App, item *core.Record) error {
	return loadWorkspaceView(app, item.GetString(util.FieldWorkspace)).recompute(item)
}

// RecomputeRecord refreshes one record's readers and editors.
func RecomputeRecord(app core.App, rec *core.Record) error {
	return loadWorkspaceView(app, rec.GetString(util.FieldWorkspace)).recompute(rec)
}

// RecomputeSection refreshes a section, and every record it holds now or held
// before (extra), since a record's audience follows its sections.
func RecomputeSection(app core.App, sec *core.Record, extra ...string) error {
	v := loadWorkspaceView(app, sec.GetString(util.FieldWorkspace))
	if err := v.recompute(sec); err != nil {
		return err
	}
	return v.recomputeRecords(append(sec.GetStringSlice(util.Fields.Section.Records), extra...))
}

// RecomputeRecordsById refreshes the named records, for a section that is
// gone.
func RecomputeRecordsById(app core.App, workspace string, ids []string) error {
	return loadWorkspaceView(app, workspace).recomputeRecords(ids)
}

func (v *workspaceView) recomputeRecords(ids []string) error {
	ids = uniqueIds(ids)
	if len(ids) == 0 {
		return nil
	}
	recs, err := v.app.FindRecordsByIds(util.Coll.Records, ids)
	if err != nil {
		return err
	}
	for _, rec := range recs {
		if rec.GetString(util.FieldWorkspace) != v.workspace {
			continue
		}
		if err := v.recompute(rec); err != nil {
			return err
		}
	}
	return nil
}

// RecomputeWorkspace refreshes every section and record of a workspace whose
// answer can depend on membership, permissions or groups: sections with an
// audience, the records they hold, and every row that still lists someone
// beside its owner.
func RecomputeWorkspace(app core.App, workspace string) error {
	v := loadWorkspaceView(app, workspace)
	for _, coll := range visibilityCollections {
		rows, err := app.FindAllRecords(coll, dbx.HashExp{util.FieldWorkspace: workspace})
		if err != nil {
			return err
		}
		for _, row := range rows {
			if err := v.recompute(row); err != nil {
				return err
			}
		}
	}
	return nil
}

// RecomputeGroup refreshes the rows naming a group: sections with their
// records, shares and requests.
func RecomputeGroup(app core.App, group string) error {
	filter := util.Fields.Section.AudienceGroups + " ~ {:g}"
	for _, coll := range visibilityCollections {
		if !HasAudience(coll) {
			continue
		}
		rows, err := app.FindRecordsByFilter(coll, filter, "", 0, 0, dbx.Params{"g": group})
		if err != nil {
			return err
		}
		for _, row := range rows {
			var err error
			if coll == util.Coll.Sections {
				err = RecomputeSection(app, row)
			} else {
				err = RecomputeItem(app, row)
			}
			if err != nil {
				return err
			}
		}
	}
	return nil
}

// ReconcileVisibility compares every section's and record's readers and
// editors with what they should be and repairs any difference. A row whose
// columns were never filled (both empty, as after the migration) is filled
// quietly; any other difference is a bug in the recompute hooks and is
// counted and logged.
func ReconcileVisibility(app core.App) (filled, repaired int, err error) {
	workspaces, err := app.FindAllRecords(util.Coll.Workspaces)
	if err != nil {
		return 0, 0, err
	}
	for _, ws := range workspaces {
		v := loadWorkspaceView(app, ws.Id)
		for _, coll := range visibilityCollections {
			rows, err := app.FindAllRecords(coll, dbx.HashExp{util.FieldWorkspace: ws.Id})
			if err != nil {
				return filled, repaired, err
			}
			for _, row := range rows {
				readers, editors := v.access(row)
				sr, se := storedAccess(row)
				if slices.Equal(readers, sr) && slices.Equal(editors, se) {
					continue
				}
				if len(sr) == 0 && len(se) == 0 {
					filled++
				} else {
					repaired++
					app.Logger().Error("Visibility out of step, repaired",
						"collection", coll, "id", row.Id, "workspace", ws.Id,
						"stored_readers", len(sr), "expected_readers", len(readers),
						"stored_editors", len(se), "expected_editors", len(editors))
				}
				if err := writeAccess(app, row, readers, editors); err != nil {
					return filled, repaired, err
				}
			}
		}
	}
	return filled, repaired, nil
}

func sortedKeys(m map[string]bool) []string {
	out := make([]string, 0, len(m))
	for k := range m {
		out = append(out, k)
	}
	slices.Sort(out)
	return out
}

func nonNil(s []string) []string {
	if s == nil {
		return []string{}
	}
	return s
}

// SharedWithMember lists the sections of other members that a member sees in
// a workspace, sorted by name, and for each the records of it the member
// sees, in the section's order.
func SharedWithMember(app core.App, workspace, user string) ([]*core.Record, map[string][]*core.Record, error) {
	v := loadWorkspaceView(app, workspace)
	if !v.isMember(user) {
		return nil, nil, nil
	}
	s := util.Fields.Section
	rows, err := app.FindRecordsByFilter(util.Coll.Sections,
		s.Workspace+" = {:w} && "+s.User+" != {:me} && "+s.AudienceKind+" != {:private} && "+s.RequestedBy+" = ''",
		s.Name, 0, 0,
		dbx.Params{"w": workspace, "me": user, "private": util.AudiencePrivate})
	if err != nil {
		return nil, nil, err
	}
	sections := []*core.Record{}
	records := map[string][]*core.Record{}
	for _, sec := range rows {
		if readers, _ := v.sectionAccess(sec); !slices.Contains(readers, user) {
			continue
		}
		sections = append(sections, sec)
		ids := uniqueIds(sec.GetStringSlice(s.Records))
		found := recordsByIds(app, ids)
		for _, rec := range found {
			// Only the section owner's records are shared through it.
			if rec.GetString(util.FieldWorkspace) != workspace ||
				rec.GetString(util.FieldUser) != sec.GetString(s.User) {
				continue
			}
			if readers, _ := v.recordAccess(rec); slices.Contains(readers, user) {
				records[sec.Id] = append(records[sec.Id], rec)
			}
		}
	}
	return sections, records, nil
}

// AccessSummary describes who sees and edits an item, for the app's access
// view: the audience (sections only), and the readers and editors beside the
// owner.
type AccessSummary struct {
	Audience *Audience
	Owner    string
	Readers  []string
	Editors  []string
}

// SummarizeAccess computes an item's access summary.
func SummarizeAccess(app core.App, item *core.Record) AccessSummary {
	readers, editors := ExpectedAccess(app, item)
	sum := AccessSummary{Owner: OwnerOf(item), Readers: readers, Editors: editors}
	if HasAudience(item.Collection().Name) {
		a := SectionAudience(item)
		sum.Audience = &a
	}
	return sum
}

// HoldsPermission reports whether a member of a workspace holds a scope. A
// legacy membership row with no permissions holds all of them.
func HoldsPermission(app core.App, workspace, user, scope string) bool {
	return loadWorkspaceView(app, workspace).holds(user, scope)
}

// LeaveWorkspaceGroups takes a member out of every group of a workspace they
// left. Each removal recomputes who sees what through the group hooks.
func LeaveWorkspaceGroups(app core.App, workspace, user string) error {
	groups, err := app.FindAllRecords(util.Coll.Groups, dbx.HashExp{util.Fields.Group.Workspace: workspace})
	if err != nil {
		return err
	}
	for _, g := range groups {
		rows, err := app.FindAllRecords(util.Coll.GroupMembers,
			dbx.HashExp{util.Fields.GroupMember.Group: g.Id, util.Fields.GroupMember.User: user})
		if err != nil {
			return err
		}
		for _, row := range rows {
			if err := app.Delete(row); err != nil {
				return err
			}
		}
	}
	return nil
}

// DirectlySharedRecords lists other members' vault entries a member sees
// through the entry's own visibility (the company's root vault, say), as
// opposed to through a section holding it. Sorted by label.
func DirectlySharedRecords(app core.App, workspace, user string) ([]*core.Record, error) {
	v := loadWorkspaceView(app, workspace)
	if !v.isMember(user) {
		return nil, nil
	}
	r := util.Fields.Record
	rows, err := app.FindRecordsByFilter(util.Coll.Records,
		r.Workspace+" = {:w} && "+r.User+" != {:me} && "+util.Fields.Section.AudienceKind+" != {:private}",
		r.Label, 0, 0,
		dbx.Params{"w": workspace, "me": user, "private": util.AudiencePrivate})
	if err != nil {
		return nil, err
	}
	out := []*core.Record{}
	for _, rec := range rows {
		if !recordSharesThroughSections(rec) {
			continue
		}
		if readers, _ := v.recordAccess(rec); slices.Contains(readers, user) {
			out = append(out, rec)
		}
	}
	return out, nil
}
