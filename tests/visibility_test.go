package tests

import (
	"fmt"
	"math/rand"
	"net/http"
	"slices"
	"testing"

	"revoked/cmd/revoked/services"
	"revoked/tests/testutils"
	"revoked/util"

	"github.com/gavv/httpexpect/v2"
	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/core"
)

// Who sees and who edits sections and records inside a workspace
// (VISIBILITY.md, phase 1).

type visibilityFixture struct {
	sharedFixture
	readOnly, noVault, grouped, removed, outsider contactParty
	group                                         string
}

// newVisibilityFixture is a workspace with its owner and five other people:
//
//	member    vault read and write
//	readOnly  vault read
//	noVault   no vault permission
//	grouped   vault read and write, in the group "hr"
//	removed   was a member with vault read and write, then removed
//	outsider  never a member
func newVisibilityFixture(t *testing.T) visibilityFixture {
	t.Helper()
	sf := newSealedFixture(t)
	member := addWorkspaceMember(t, sf)
	f := visibilityFixture{sharedFixture: sharedFixture{sf.app, sf.baseURL, testutils.NewPBClient(t, sf.baseURL), sf.party, member}}
	f.readOnly = addWorkspaceMember(t, sf)
	f.setPermissions(t, f.readOnly.id, util.PermVaultRead)
	f.noVault = addWorkspaceMember(t, sf)
	f.setPermissions(t, f.noVault.id, util.PermSharesRead)
	f.grouped = addWorkspaceMember(t, sf)
	f.removed = addWorkspaceMember(t, sf)
	f.outsider = newContactParty(t, sf.baseURL)
	f.group = f.newGroup(t, "hr", f.grouped.id)
	return f
}

func (f visibilityFixture) membership(t *testing.T, user string) *core.Record {
	t.Helper()
	m := util.Fields.WorkspaceMember
	row, err := f.app.FindFirstRecordByFilter(util.Coll.WorkspaceMembers,
		m.Workspace+" = {:w} && "+m.User+" = {:u}", dbx.Params{"w": f.owner.workspace, "u": user})
	if err != nil {
		t.Fatal(err)
	}
	return row
}

func (f visibilityFixture) setPermissions(t *testing.T, user string, perms ...string) {
	t.Helper()
	row := f.membership(t, user)
	scopes, _ := util.ExpandPermissions(perms)
	row.Set(util.Fields.WorkspaceMember.Permissions, scopes)
	if err := f.app.Save(row); err != nil {
		t.Fatal(err)
	}
}

func (f visibilityFixture) removeMember(t *testing.T, user string) {
	t.Helper()
	if err := f.app.Delete(f.membership(t, user)); err != nil {
		t.Fatal(err)
	}
}

func (f visibilityFixture) newGroup(t *testing.T, key string, users ...string) string {
	t.Helper()
	coll, err := f.app.FindCollectionByNameOrId(util.Coll.Groups)
	if err != nil {
		t.Fatal(err)
	}
	g := core.NewRecord(coll)
	g.Set(util.Fields.Group.Workspace, f.owner.workspace)
	g.Set(util.Fields.Group.Key, key)
	g.Set(util.Fields.Group.Name, key)
	if err := f.app.Save(g); err != nil {
		t.Fatal(err)
	}
	for _, u := range users {
		f.addToGroup(t, g.Id, u)
	}
	return g.Id
}

func (f visibilityFixture) addToGroup(t *testing.T, group, user string) {
	t.Helper()
	coll, _ := f.app.FindCollectionByNameOrId(util.Coll.GroupMembers)
	gm := core.NewRecord(coll)
	gm.Set(util.Fields.GroupMember.Group, group)
	gm.Set(util.Fields.GroupMember.User, user)
	if err := f.app.Save(gm); err != nil {
		t.Fatal(err)
	}
}

// audienceSection creates a section of the owner's with an audience.
func (f visibilityFixture) audienceSection(t *testing.T, kind, editing string, groups []string, records ...string) string {
	t.Helper()
	s := util.Fields.Section
	return extractID(t, f.baseURL, util.Coll.Sections, f.owner.token, map[string]any{
		s.Key: "s" + randomSuffix(), s.Name: "section", s.User: f.owner.id, s.Workspace: f.owner.workspace,
		s.Records: records, s.AudienceKind: kind, s.Editing: editing, s.AudienceGroups: groups,
	})
}

func randomSuffix() string { return fmt.Sprintf("%d", rand.Int63()) }

// TestVisibilityMatrix runs every kind of member against every audience,
// for viewing and changing a section and the record in it.
func TestVisibilityMatrix(t *testing.T) {
	type expect struct{ seeSection, seeRecord, editSection, editRecord bool }
	type audience struct {
		name, kind, editing string
		group               bool
	}
	audiences := []audience{
		{"private", util.AudiencePrivate, util.EditingOwner, false},
		{"workspace, owner edits", util.AudienceWorkspace, util.EditingOwner, false},
		{"workspace, audience edits", util.AudienceWorkspace, util.EditingAudience, false},
		{"group, audience edits", util.AudienceGroups, util.EditingAudience, true},
	}
	// The expected answer per subject, per audience, in the order above.
	all := expect{true, true, true, true}
	none := expect{}
	seeOnly := expect{seeSection: true, seeRecord: true}
	table := map[string][]expect{
		"owner":    {all, all, all, all},
		"member":   {none, seeOnly, all, none},
		"readOnly": {none, seeOnly, seeOnly, none},
		"noVault":  {none, none, none, none},
		"grouped":  {none, seeOnly, all, all},
		"removed":  {none, none, none, none},
		"outsider": {none, none, none, none},
	}

	f := newVisibilityFixture(t)
	f.removeMember(t, f.removed.id)
	subjects := map[string]contactParty{
		"owner": f.owner, "member": f.member, "readOnly": f.readOnly, "noVault": f.noVault,
		"grouped": f.grouped, "removed": f.removed, "outsider": f.outsider,
	}
	for i, a := range audiences {
		for name, who := range subjects {
			want := table[name][i]
			t.Run(a.name+"/"+name, func(t *testing.T) {
				rec := f.record(t, f.owner.token, f.owner.id, "k"+randomSuffix(), "v", nil)
				var groups []string
				if a.group {
					groups = []string{f.group}
				}
				sec := f.audienceSection(t, a.kind, a.editing, groups, rec)
				api := f.api.T(t)
				status := func(ok bool) int {
					if ok {
						return http.StatusOK
					}
					return http.StatusNotFound
				}
				api.Get(util.Coll.Sections, sec, who.token).Expect().Status(status(want.seeSection))
				api.Get(util.Coll.Records, rec, who.token).Expect().Status(status(want.seeRecord))

				// A refusal is a 403 inside the workspace and a 404 outside
				// it; either way never a success.
				check := func(resp int, ok bool) {
					t.Helper()
					if ok && resp != http.StatusOK {
						t.Errorf("want 200, got %d", resp)
					}
					if !ok && resp == http.StatusOK {
						t.Errorf("want a refusal, got 200")
					}
				}
				check(api.Update(util.Coll.Sections, sec, who.token, map[string]any{
					util.Fields.Section.Name: "renamed",
				}).Expect().Raw().StatusCode, want.editSection)
				check(api.Update(util.Coll.Records, rec, who.token, map[string]any{
					util.Fields.Record.Value: "changed",
				}).Expect().Raw().StatusCode, want.editRecord)

				// The stored columns agree with the computed answer.
				for _, id := range []struct{ coll, id string }{{util.Coll.Sections, sec}, {util.Coll.Records, rec}} {
					row, _ := f.app.FindRecordById(id.coll, id.id)
					readers, editors := services.ExpectedAccess(f.app, row)
					if !slices.Equal(sortedCopy(row.GetStringSlice(util.Fields.Section.Readers)), readers) ||
						!slices.Equal(sortedCopy(row.GetStringSlice(util.Fields.Section.Editors)), editors) {
						t.Errorf("%s %s: stored access differs from the computed answer", id.coll, id.id)
					}
				}
			})
		}
	}
}

func sortedCopy(s []string) []string {
	out := slices.Clone(s)
	slices.Sort(out)
	return out
}

func TestVisibilityRules(t *testing.T) {
	t.Run("readers and editors are the server's", func(t *testing.T) {
		f := newVisibilityFixture(t)
		rec := f.record(t, f.owner.token, f.owner.id, "pin", "1234", nil)
		// Whatever the response, a value sent for them never takes effect.
		f.api.Update(util.Coll.Records, rec, f.owner.token, map[string]any{
			util.Fields.Record.Readers: []string{f.member.id},
			util.Fields.Record.Editors: []string{f.member.id},
		}).Expect()
		f.api.Get(util.Coll.Records, rec, f.member.token).Expect().Status(http.StatusNotFound)
		f.api.Update(util.Coll.Records, rec, f.member.token, map[string]any{util.Fields.Record.Value: "x"}).
			Expect().Status(http.StatusForbidden)
		row, _ := f.app.FindRecordById(util.Coll.Records, rec)
		if got := row.GetStringSlice(util.Fields.Record.Readers); !slices.Equal(got, []string{f.owner.id}) {
			t.Fatalf("readers = %v, want only the owner", got)
		}
	})

	t.Run("the older shared flag still sets the audience", func(t *testing.T) {
		f := newVisibilityFixture(t)
		sec := f.section(t, f.owner.token, f.owner.id, "office", true)
		row, _ := f.app.FindRecordById(util.Coll.Sections, sec)
		if a := services.SectionAudience(row); a.Kind != util.AudienceWorkspace || a.Editing != util.EditingAudience {
			t.Fatalf("shared=true gave %+v", a)
		}
		f.api.Update(util.Coll.Sections, sec, f.owner.token, map[string]any{util.Fields.Section.Shared: false}).
			Expect().Status(http.StatusOK)
		row, _ = f.app.FindRecordById(util.Coll.Sections, sec)
		if a := services.SectionAudience(row); a.Kind != util.AudiencePrivate || row.GetBool(util.Fields.Section.Shared) {
			t.Fatalf("shared=false gave %+v", a)
		}
	})

	t.Run("a groups audience needs a group of this workspace", func(t *testing.T) {
		f := newVisibilityFixture(t)
		s := util.Fields.Section
		f.api.Create(util.Coll.Sections, f.owner.token, map[string]any{
			s.Key: "g", s.Name: "g", s.Workspace: f.owner.workspace, s.AudienceKind: util.AudienceGroups,
		}).Expect().Status(http.StatusBadRequest)
		other := newVisibilityFixture(t)
		foreign := other.newGroup(t, "foreign")
		f.api.Create(util.Coll.Sections, f.owner.token, map[string]any{
			s.Key: "g2", s.Name: "g2", s.Workspace: f.owner.workspace, s.AudienceKind: util.AudienceGroups,
			s.AudienceGroups: []string{foreign},
		}).Expect().Status(http.StatusBadRequest)
	})

	t.Run("losing the vault permission hides the section again", func(t *testing.T) {
		f := newVisibilityFixture(t)
		rec := f.record(t, f.owner.token, f.owner.id, "wifi", "hunter2", nil)
		f.audienceSection(t, util.AudienceWorkspace, util.EditingAudience, nil, rec)
		f.api.Get(util.Coll.Records, rec, f.member.token).Expect().Status(http.StatusOK)
		f.setPermissions(t, f.member.id, util.PermSharesRead)
		f.api.Get(util.Coll.Records, rec, f.member.token).Expect().Status(http.StatusNotFound)
		f.setPermissions(t, f.member.id, util.PermVaultRead)
		f.api.Get(util.Coll.Records, rec, f.member.token).Expect().Status(http.StatusOK)
		f.api.Update(util.Coll.Records, rec, f.member.token, map[string]any{util.Fields.Record.Value: "x"}).
			Expect().Status(http.StatusForbidden)
	})

	t.Run("removal from the workspace or the group hides it", func(t *testing.T) {
		f := newVisibilityFixture(t)
		rec := f.record(t, f.owner.token, f.owner.id, "wifi", "hunter2", nil)
		f.audienceSection(t, util.AudienceGroups, util.EditingOwner, []string{f.group}, rec)
		f.api.Get(util.Coll.Records, rec, f.grouped.token).Expect().Status(http.StatusOK)
		f.api.Get(util.Coll.Records, rec, f.member.token).Expect().Status(http.StatusNotFound)

		f.addToGroup(t, f.group, f.member.id)
		f.api.Get(util.Coll.Records, rec, f.member.token).Expect().Status(http.StatusOK)
		gm, _ := f.app.FindFirstRecordByFilter(util.Coll.GroupMembers, "user = {:u}", dbx.Params{"u": f.member.id})
		if err := f.app.Delete(gm); err != nil {
			t.Fatal(err)
		}
		f.api.Get(util.Coll.Records, rec, f.member.token).Expect().Status(http.StatusNotFound)

		f.removeMember(t, f.grouped.id)
		f.api.Get(util.Coll.Records, rec, f.grouped.token).Expect().Status(http.StatusNotFound)
	})

	t.Run("deleting the group leaves the section with its owner", func(t *testing.T) {
		f := newVisibilityFixture(t)
		rec := f.record(t, f.owner.token, f.owner.id, "wifi", "hunter2", nil)
		f.audienceSection(t, util.AudienceGroups, util.EditingOwner, []string{f.group}, rec)
		g, _ := f.app.FindRecordById(util.Coll.Groups, f.group)
		if err := f.app.Delete(g); err != nil {
			t.Fatal(err)
		}
		f.api.Get(util.Coll.Records, rec, f.grouped.token).Expect().Status(http.StatusNotFound)
		f.api.Get(util.Coll.Records, rec, f.owner.token).Expect().Status(http.StatusOK)
	})

	t.Run("a record follows the sections holding it", func(t *testing.T) {
		f := newVisibilityFixture(t)
		rec := f.record(t, f.owner.token, f.owner.id, "wifi", "hunter2", nil)
		sec := f.audienceSection(t, util.AudienceWorkspace, util.EditingOwner, nil)
		f.api.Get(util.Coll.Records, rec, f.member.token).Expect().Status(http.StatusNotFound)
		f.api.Update(util.Coll.Sections, sec, f.owner.token, map[string]any{util.Fields.Section.Records: []string{rec}}).
			Expect().Status(http.StatusOK)
		f.api.Get(util.Coll.Records, rec, f.member.token).Expect().Status(http.StatusOK)
		f.api.Update(util.Coll.Sections, sec, f.owner.token, map[string]any{util.Fields.Section.Records: []string{}}).
			Expect().Status(http.StatusOK)
		f.api.Get(util.Coll.Records, rec, f.member.token).Expect().Status(http.StatusNotFound)

		f.api.Update(util.Coll.Sections, sec, f.owner.token, map[string]any{util.Fields.Section.Records: []string{rec}}).
			Expect().Status(http.StatusOK)
		f.api.Delete(util.Coll.Sections, sec, f.owner.token).Expect().Status(http.StatusNoContent)
		f.api.Get(util.Coll.Records, rec, f.member.token).Expect().Status(http.StatusNotFound)
	})

	t.Run("a section shares only its owner's records, no aliases", func(t *testing.T) {
		f := newVisibilityFixture(t)
		mine := f.record(t, f.member.token, f.member.id, "note", "hello", nil)
		parent := f.record(t, f.owner.token, f.owner.id, "pin", "1234", nil)
		alias := f.record(t, f.owner.token, f.owner.id, "pin_alias", "", map[string]any{util.Fields.Record.AliasOf: parent})
		f.audienceSection(t, util.AudienceWorkspace, util.EditingAudience, nil, mine, alias)
		f.api.Get(util.Coll.Records, mine, f.readOnly.token).Expect().Status(http.StatusNotFound)
		f.api.Get(util.Coll.Records, alias, f.readOnly.token).Expect().Status(http.StatusNotFound)
	})

	t.Run("a share holds only its creator's items", func(t *testing.T) {
		f := newVisibilityFixture(t)
		f.setPermissions(t, f.member.id, util.PermVaultRead, util.PermVaultWrite, util.PermSharesManage)
		rec := f.record(t, f.owner.token, f.owner.id, "wifi", "hunter2", nil)
		sec := f.audienceSection(t, util.AudienceWorkspace, util.EditingAudience, nil, rec)
		l := util.Fields.Link
		for _, body := range []map[string]any{
			{l.Label: "x", l.Workspace: f.owner.workspace, l.Records: []string{rec}},
			{l.Label: "y", l.Workspace: f.owner.workspace, l.Sections: []string{sec}},
		} {
			f.api.Create(util.Coll.Links, f.member.token, body).Expect().Status(http.StatusBadRequest)
		}
	})
}

func TestAccessRoute(t *testing.T) {
	f := newVisibilityFixture(t)
	f.removeMember(t, f.removed.id)
	rec := f.record(t, f.owner.token, f.owner.id, "wifi", "hunter2", nil)
	sec := f.audienceSection(t, util.AudienceWorkspace, util.EditingAudience, nil, rec)
	get := func(token, coll, id string, status int) {
		testutils.NewExpect(t, f.baseURL).GET("/api/access/"+coll+"/"+id).
			WithHeader("Authorization", token).Expect().Status(status)
	}

	body := testutils.NewExpect(t, f.baseURL).GET("/api/access/sections/"+sec).
		WithHeader("Authorization", f.owner.token).Expect().Status(http.StatusOK).JSON().Object()
	body.Value("audience").Object().Value("kind").IsEqual(util.AudienceWorkspace)
	body.Value("audience").Object().Value("editing").IsEqual(util.EditingAudience)
	body.Value("canChangeAudience").IsEqual(true)
	// owner, member and grouped read and edit; readOnly reads.
	body.Value("readers").Object().Value("count").IsEqual(4)
	body.Value("editors").Object().Value("count").IsEqual(3)
	body.Value("readers").Object().Value("members").Array().Length().IsEqual(4)

	member := testutils.NewExpect(t, f.baseURL).GET("/api/access/records/"+rec).
		WithHeader("Authorization", f.readOnly.token).Expect().Status(http.StatusOK).JSON().Object()
	member.Value("canEdit").IsEqual(false)
	member.Value("canChangeAudience").IsEqual(false)
	member.Value("audience").IsNull()
	member.Value("readers").Object().NotContainsKey("members")

	get(f.noVault.token, "sections", sec, http.StatusNotFound)
	get(f.outsider.token, "records", rec, http.StatusNotFound)
	get(f.owner.token, "links", sec, http.StatusNotFound)
	testutils.NewExpect(t, f.baseURL).GET("/api/access/sections/" + sec).Expect().Status(http.StatusUnauthorized)
}

func TestVisibilityReconcile(t *testing.T) {
	f := newVisibilityFixture(t)
	rec := f.record(t, f.owner.token, f.owner.id, "wifi", "hunter2", nil)
	f.audienceSection(t, util.AudienceWorkspace, util.EditingOwner, nil, rec)
	// Tamper with the stored answer behind the hooks' back.
	if _, err := f.app.DB().Update(util.Coll.Records, dbx.Params{
		util.Fields.Record.Readers: `["` + f.noVault.id + `"]`,
	}, dbx.HashExp{"id": rec}).Execute(); err != nil {
		t.Fatal(err)
	}
	f.api.Get(util.Coll.Records, rec, f.noVault.token).Expect().Status(http.StatusOK)
	_, repaired, err := services.ReconcileVisibility(f.app)
	if err != nil {
		t.Fatal(err)
	}
	if repaired < 1 {
		t.Fatalf("repaired %d rows, want at least 1", repaired)
	}
	f.api.Get(util.Coll.Records, rec, f.noVault.token).Expect().Status(http.StatusNotFound)
	f.api.Get(util.Coll.Records, rec, f.member.token).Expect().Status(http.StatusOK)
}

// TestVisibilityConsistency applies random changes to a workspace and checks
// after each one that every stored readers/editors column equals what
// services.Access computes.
func TestVisibilityConsistency(t *testing.T) {
	f := newVisibilityFixture(t)
	rng := rand.New(rand.NewSource(1))
	app := f.app
	people := []contactParty{f.owner, f.member, f.readOnly, f.noVault, f.grouped}
	perms := [][]string{{util.PermVaultRead}, {util.PermVaultRead, util.PermVaultWrite}, {util.PermSharesRead},
		{util.PermSharesManage, util.PermRequestsRead}, {util.PermRequestsManage, util.PermVaultRead},
		{util.PermTemplatesManage, util.PermContactsManage}, nil}
	groups := []string{f.group, f.newGroup(t, "techs", f.member.id)}

	sectionsColl, _ := app.FindCollectionByNameOrId(util.Coll.Sections)
	recordsColl, _ := app.FindCollectionByNameOrId(util.Coll.Records)
	var sections, records []*core.Record

	newRecord := func(owner contactParty) {
		r := core.NewRecord(recordsColl)
		rf := util.Fields.Record
		r.Set(rf.Key, "r"+randomSuffix())
		r.Set(rf.Label, "r")
		r.Set(rf.Value, "v")
		r.Set(rf.Type, util.TypeText)
		r.Set(rf.Format, util.FormatDefault)
		r.Set(rf.User, owner.id)
		r.Set(rf.Workspace, f.owner.workspace)
		if err := app.Save(r); err != nil {
			t.Fatal(err)
		}
		records = append(records, r)
	}
	newSection := func(owner contactParty) {
		s := core.NewRecord(sectionsColl)
		sf := util.Fields.Section
		s.Set(sf.Key, "s"+randomSuffix())
		s.Set(sf.Name, "s")
		s.Set(sf.User, owner.id)
		s.Set(sf.Workspace, f.owner.workspace)
		if err := app.Save(s); err != nil {
			t.Fatal(err)
		}
		sections = append(sections, s)
	}
	for _, p := range people {
		newRecord(p)
		newRecord(p)
		newSection(p)
	}
	// Shares and requests, one each per person, with their own audience.
	var owned []*core.Record
	identity := f.ownerIdentity(t)
	for _, p := range people {
		for _, coll := range []string{util.Coll.Links, util.Coll.Requests} {
			c, _ := app.FindCollectionByNameOrId(coll)
			row := core.NewRecord(c)
			row.Set("slug", "x"+randomSuffix()[:10])
			row.Set("label", "x")
			row.Set("status", util.StatusActive)
			row.Set("user", p.id)
			row.Set("workspace", f.owner.workspace)
			if coll == util.Coll.Requests {
				row.Set(util.Fields.Request.Identity, identity)
			}
			if err := app.Save(row); err != nil {
				t.Fatal(err)
			}
			owned = append(owned, row)
		}
		// A template and a contact each, as workspace data.
		tc, _ := app.FindCollectionByNameOrId(util.Coll.Templates)
		tpl := core.NewRecord(tc)
		tpl.Set(util.Fields.Template.Workspace, f.owner.workspace)
		tpl.Set(util.Fields.Template.Name, "t"+randomSuffix()[:10])
		tpl.Set(util.Fields.Template.Schema, map[string]any{"fields": []any{}})
		tpl.Set(util.Fields.Template.User, p.id)
		cc, _ := app.FindCollectionByNameOrId(util.Coll.Contacts)
		con := core.NewRecord(cc)
		con.Set(util.Fields.Contact.Workspace, f.owner.workspace)
		con.Set(util.Fields.Contact.Name, "c"+randomSuffix()[:10])
		con.Set(util.Fields.Contact.Email, "c"+randomSuffix()[:10]+"@example.com")
		con.Set(util.Fields.Contact.CreatedBy, p.id)
		for _, row := range []*core.Record{tpl, con} {
			if err := app.Save(row); err != nil {
				t.Fatal(err)
			}
			owned = append(owned, row)
		}
	}

	fresh := func(r *core.Record) *core.Record {
		got, err := app.FindRecordById(r.Collection().Name, r.Id)
		if err != nil {
			return nil
		}
		return got
	}
	verify := func(step int, what string) {
		t.Helper()
		for _, coll := range []string{util.Coll.Sections, util.Coll.Records, util.Coll.Links, util.Coll.Requests,
			util.Coll.Templates, util.Coll.Contacts} {
			rows, _ := app.FindAllRecords(coll, dbx.HashExp{util.FieldWorkspace: f.owner.workspace})
			for _, row := range rows {
				readers, editors := services.ExpectedAccess(app, row)
				if !slices.Equal(sortedCopy(row.GetStringSlice(util.Fields.Section.Readers)), readers) ||
					!slices.Equal(sortedCopy(row.GetStringSlice(util.Fields.Section.Editors)), editors) {
					t.Fatalf("step %d (%s): %s %s stored %v/%v, expected %v/%v", step, what, coll, row.Id,
						row.GetStringSlice(util.Fields.Section.Readers), row.GetStringSlice(util.Fields.Section.Editors),
						readers, editors)
				}
			}
		}
	}

	for step := 0; step < 200; step++ {
		var what string
		switch rng.Intn(9) {
		case 8:
			what = "share, request, template or contact audience"
			row := fresh(owned[rng.Intn(len(owned))])
			kinds := []string{util.AudiencePrivate, util.AudienceWorkspace, util.AudienceGroups}
			kind := kinds[rng.Intn(3)]
			row.Set(util.Fields.Section.AudienceKind, kind)
			if kind == util.AudienceGroups {
				row.Set(util.Fields.Section.AudienceGroups, []string{groups[rng.Intn(len(groups))]})
			}
			row.Set(util.Fields.Section.Editing, []string{util.EditingOwner, util.EditingAudience}[rng.Intn(2)])
			if err := app.Save(row); err != nil {
				t.Fatal(err)
			}
		case 0:
			what = "audience"
			s := fresh(sections[rng.Intn(len(sections))])
			if s == nil {
				continue
			}
			kinds := []string{util.AudiencePrivate, util.AudienceWorkspace, util.AudienceGroups}
			kind := kinds[rng.Intn(3)]
			s.Set(util.Fields.Section.AudienceKind, kind)
			if kind == util.AudienceGroups {
				s.Set(util.Fields.Section.AudienceGroups, []string{groups[rng.Intn(len(groups))]})
			}
			s.Set(util.Fields.Section.Editing, []string{util.EditingOwner, util.EditingAudience}[rng.Intn(2)])
			if err := app.Save(s); err != nil {
				t.Fatal(err)
			}
		case 1, 2:
			what = "section records"
			s := fresh(sections[rng.Intn(len(sections))])
			if s == nil {
				continue
			}
			var ids []string
			for _, r := range records {
				if rng.Intn(3) == 0 {
					ids = append(ids, r.Id)
				}
			}
			s.Set(util.Fields.Section.Records, ids)
			if err := app.Save(s); err != nil {
				t.Fatal(err)
			}
		case 3:
			what = "permissions"
			p := people[1+rng.Intn(len(people)-1)]
			f.setPermissions(t, p.id, perms[rng.Intn(len(perms))]...)
		case 4:
			what = "group membership"
			g := groups[rng.Intn(len(groups))]
			p := people[rng.Intn(len(people))]
			existing, err := app.FindFirstRecordByFilter(util.Coll.GroupMembers, "group = {:g} && user = {:u}",
				dbx.Params{"g": g, "u": p.id})
			if err == nil && existing != nil {
				if err := app.Delete(existing); err != nil {
					t.Fatal(err)
				}
			} else {
				f.addToGroup(t, g, p.id)
			}
		case 5:
			what = "new record"
			newRecord(people[rng.Intn(len(people))])
		case 6:
			what = "new or deleted section"
			if rng.Intn(2) == 0 {
				newSection(people[rng.Intn(len(people))])
			} else if s := fresh(sections[rng.Intn(len(sections))]); s != nil && len(sections) > 3 {
				if err := app.Delete(s); err != nil {
					t.Fatal(err)
				}
			}
		case 7:
			what = "record change"
			r := fresh(records[rng.Intn(len(records))])
			if r == nil {
				continue
			}
			r.Set(util.Fields.Record.Value, "v"+randomSuffix())
			if err := app.Save(r); err != nil {
				t.Fatal(err)
			}
		}
		verify(step, what)
	}

	// Finally, a removed member drops out of every row.
	f.removeMember(t, f.member.id)
	verify(-1, "member removed")
	_, repaired, err := services.ReconcileVisibility(app)
	if err != nil || repaired != 0 {
		t.Fatalf("reconcile after the run repaired %d rows (err %v); the hooks left something behind", repaired, err)
	}
}

// Phase 2: shares and requests carry an audience of their own, and a
// request's answers follow the request.

func (f visibilityFixture) share(t *testing.T, kind, editing string, groups []string) string {
	t.Helper()
	l := util.Fields.Link
	s := util.Fields.Section
	return extractID(t, f.baseURL, util.Coll.Links, f.owner.token, map[string]any{
		l.Slug: "l" + randomSuffix()[:8], l.Label: "share", l.Status: util.StatusActive,
		l.User: f.owner.id, l.Workspace: f.owner.workspace,
		s.AudienceKind: kind, s.Editing: editing, s.AudienceGroups: groups,
	})
}

// ownerIdentity is a signing identity of the owner's, which a request needs.
func (f visibilityFixture) ownerIdentity(t *testing.T) string {
	t.Helper()
	if id, ok := identities[f.owner.id]; ok {
		return id
	}
	id, _ := newIdentity(t, f.baseURL, f.owner.token, "Owner", f.owner.id, f.owner.workspace)
	identities[f.owner.id] = id
	return id
}

var identities = map[string]string{}

func (f visibilityFixture) dataRequest(t *testing.T, kind, editing string, groups []string) string {
	t.Helper()
	r := util.Fields.Request
	s := util.Fields.Section
	return extractID(t, f.baseURL, util.Coll.Requests, f.owner.token, map[string]any{
		r.Slug: "r" + randomSuffix()[:8], r.Label: "request", r.Status: util.StatusActive,
		r.User: f.owner.id, r.Workspace: f.owner.workspace, r.Identity: f.ownerIdentity(t),
		s.AudienceKind: kind, s.Editing: editing, s.AudienceGroups: groups,
	})
}

func TestShareAndRequestVisibility(t *testing.T) {
	f := newVisibilityFixture(t)
	f.removeMember(t, f.removed.id)
	// member: manages shares and requests and reads answers; readOnly: views
	// them; noVault: neither; grouped: manages them, in "hr".
	everything := []string{util.PermSharesManage, util.PermSharesRead, util.PermRequestsManage,
		util.PermRequestsRead, util.PermResponsesRead}
	f.setPermissions(t, f.member.id, everything...)
	f.setPermissions(t, f.grouped.id, everything...)
	f.setPermissions(t, f.readOnly.id, util.PermSharesRead, util.PermRequestsRead)
	f.setPermissions(t, f.noVault.id, util.PermVaultRead)

	type audience struct {
		name, kind, editing string
		group               bool
	}
	audiences := []audience{
		{"private", util.AudiencePrivate, util.EditingOwner, false},
		{"workspace, owner edits", util.AudienceWorkspace, util.EditingOwner, false},
		{"workspace, audience edits", util.AudienceWorkspace, util.EditingAudience, false},
		{"group, audience edits", util.AudienceGroups, util.EditingAudience, true},
	}
	type expect struct{ see, edit bool }
	all, none, see := expect{true, true}, expect{}, expect{see: true}
	table := map[string][]expect{
		"owner":    {all, all, all, all},
		"member":   {none, see, all, none},
		"readOnly": {none, see, see, none},
		"noVault":  {none, none, none, none},
		"grouped":  {none, see, all, all},
		"removed":  {none, none, none, none},
		"outsider": {none, none, none, none},
	}
	subjects := map[string]contactParty{
		"owner": f.owner, "member": f.member, "readOnly": f.readOnly, "noVault": f.noVault,
		"grouped": f.grouped, "removed": f.removed, "outsider": f.outsider,
	}
	for i, a := range audiences {
		var groups []string
		if a.group {
			groups = []string{f.group}
		}
		for name, who := range subjects {
			want := table[name][i]
			t.Run(a.name+"/"+name, func(t *testing.T) {
				api := f.api.T(t)
				items := map[string]string{
					util.Coll.Links:    f.share(t, a.kind, a.editing, groups),
					util.Coll.Requests: f.dataRequest(t, a.kind, a.editing, groups),
				}
				for coll, id := range items {
					status := http.StatusNotFound
					if want.see {
						status = http.StatusOK
					}
					api.Get(coll, id, who.token).Expect().Status(status)
					got := api.Update(coll, id, who.token, map[string]any{"label": "renamed"}).Expect().Raw().StatusCode
					if want.edit != (got == http.StatusOK) {
						t.Errorf("%s update: got %d, want edit=%v", coll, got, want.edit)
					}
				}
			})
		}
	}

	t.Run("only the owner changes the audience", func(t *testing.T) {
		api := f.api.T(t)
		for coll, id := range map[string]string{
			util.Coll.Links:    f.share(t, util.AudienceWorkspace, util.EditingAudience, nil),
			util.Coll.Requests: f.dataRequest(t, util.AudienceWorkspace, util.EditingAudience, nil),
		} {
			api.Update(coll, id, f.member.token, map[string]any{util.Fields.Section.AudienceKind: util.AudiencePrivate}).
				Expect().Status(http.StatusForbidden).JSON().Object().
				Value("code").IsEqual(util.Errors.AudienceByOwnerOnly.ErrorCode)
			api.Update(coll, id, f.owner.token, map[string]any{util.Fields.Section.AudienceKind: util.AudiencePrivate}).
				Expect().Status(http.StatusOK)
			api.Get(coll, id, f.member.token).Expect().Status(http.StatusNotFound)
		}
	})

	t.Run("the answers follow the request", func(t *testing.T) {
		req := f.dataRequest(t, util.AudienceWorkspace, util.EditingOwner, nil)
		answers := func(token string, status int) {
			t.Helper()
			testutils.NewExpect(t, f.baseURL).GET("/api/requests/"+req+"/links").
				WithHeader("Authorization", token).Expect().Status(status)
		}
		answers(f.owner.token, http.StatusOK)
		answers(f.member.token, http.StatusOK)
		answers(f.readOnly.token, http.StatusForbidden) // sees the request, may not read answers
		answers(f.noVault.token, http.StatusNotFound)
		answers(f.outsider.token, http.StatusNotFound)

		private := f.dataRequest(t, util.AudiencePrivate, util.EditingOwner, nil)
		testutils.NewExpect(t, f.baseURL).GET("/api/requests/"+private+"/links").
			WithHeader("Authorization", f.member.token).Expect().Status(http.StatusNotFound)
	})

	t.Run("the access route describes shares and requests", func(t *testing.T) {
		id := f.share(t, util.AudienceWorkspace, util.EditingAudience, nil)
		body := testutils.NewExpect(t, f.baseURL).GET("/api/access/links/"+id).
			WithHeader("Authorization", f.member.token).Expect().Status(http.StatusOK).JSON().Object()
		body.Value("audience").Object().Value("kind").IsEqual(util.AudienceWorkspace)
		body.Value("canEdit").IsEqual(true)
		body.Value("canChangeAudience").IsEqual(false)
	})
}

// Phase 3: templates, contacts and attestations were workspace data. They
// start visible to the workspace, and their owner can make them private.

func (f visibilityFixture) contact(t *testing.T, token string, extra map[string]any) string {
	t.Helper()
	body := map[string]any{
		util.Fields.Contact.Workspace: f.owner.workspace,
		util.Fields.Contact.Name:      "Ada " + randomSuffix()[:6],
		util.Fields.Contact.Email:     "ada" + randomSuffix()[:6] + "@example.com",
	}
	for k, v := range extra {
		body[k] = v
	}
	return extractID(t, f.baseURL, util.Coll.Contacts, token, body)
}

func (f visibilityFixture) template(t *testing.T, token string, extra map[string]any) string {
	t.Helper()
	body := map[string]any{
		util.Fields.Template.Workspace: f.owner.workspace,
		util.Fields.Template.Name:      "Onboarding " + randomSuffix()[:6],
		util.Fields.Template.Schema:    map[string]any{"fields": []any{}},
	}
	for k, v := range extra {
		body[k] = v
	}
	return extractID(t, f.baseURL, util.Coll.Templates, token, body)
}

func TestWorkspaceDataVisibility(t *testing.T) {
	f := newVisibilityFixture(t)
	manage := []string{util.PermContactsManage, util.PermContactsRead, util.PermTemplatesManage,
		util.PermTemplatesRead, util.PermAttestationsIssue, util.PermAttestationsRead}
	f.setPermissions(t, f.member.id, manage...)
	f.setPermissions(t, f.readOnly.id, util.PermContactsRead)
	s := util.Fields.Section

	t.Run("new ones are seen and edited by the workspace, as before", func(t *testing.T) {
		api := f.api.T(t)
		c := f.contact(t, f.owner.token, nil)
		tpl := f.template(t, f.owner.token, nil)
		for coll, id := range map[string]string{util.Coll.Contacts: c, util.Coll.Templates: tpl} {
			row, _ := f.app.FindRecordById(coll, id)
			if a := services.SectionAudience(row); a.Kind != util.AudienceWorkspace || a.Editing != util.EditingAudience {
				t.Fatalf("%s starts as %+v", coll, a)
			}
			// Read permissions were never needed to see these; still not.
			api.Get(coll, id, f.readOnly.token).Expect().Status(http.StatusOK)
			api.Get(coll, id, f.noVault.token).Expect().Status(http.StatusOK)
			api.Get(coll, id, f.outsider.token).Expect().Status(http.StatusNotFound)
		}
		api.Update(util.Coll.Contacts, c, f.member.token, map[string]any{util.Fields.Contact.Name: "Ada L."}).
			Expect().Status(http.StatusOK)
		api.Update(util.Coll.Contacts, c, f.readOnly.token, map[string]any{util.Fields.Contact.Name: "x"}).
			Expect().Status(http.StatusForbidden)
		row, _ := f.app.FindRecordById(util.Coll.Templates, tpl)
		if got := row.GetString(util.Fields.Template.User); got != f.owner.id {
			t.Fatalf("template owner = %q, want the creator", got)
		}
	})

	t.Run("a private contact is not there for colleagues, nor to send to", func(t *testing.T) {
		api := f.api.T(t)
		c := f.contact(t, f.owner.token, map[string]any{s.AudienceKind: util.AudiencePrivate})
		api.Get(util.Coll.Contacts, c, f.member.token).Expect().Status(http.StatusNotFound)
		grant(t, f.baseURL, "send", c, f.member.token, map[string]any{}).
			Expect().Status(http.StatusNotFound).JSON().Object().
			Value("code").IsEqual(util.Errors.ContactNotFound.ErrorCode)
		// The owner still reaches it: refused for sending nothing, not for
		// not finding it.
		grant(t, f.baseURL, "send", c, f.owner.token, map[string]any{}).
			Expect().Status(http.StatusBadRequest)
	})

	t.Run("the contact's creator owns it, not the account it points to", func(t *testing.T) {
		c := f.contact(t, f.member.token, nil)
		row, _ := f.app.FindRecordById(util.Coll.Contacts, c)
		if got := row.GetString(util.Fields.Contact.CreatedBy); got != f.member.id {
			t.Fatalf("createdBy = %q, want the member who added it", got)
		}
		f.api.Update(util.Coll.Contacts, c, f.member.token, map[string]any{s.AudienceKind: util.AudiencePrivate}).
			Expect().Status(http.StatusOK)
		f.api.Get(util.Coll.Contacts, c, f.owner.token).Expect().Status(http.StatusNotFound)
	})

	t.Run("only the owner changes who sees them", func(t *testing.T) {
		api := f.api.T(t)
		c := f.contact(t, f.owner.token, nil)
		api.Update(util.Coll.Contacts, c, f.member.token, map[string]any{s.AudienceKind: util.AudiencePrivate}).
			Expect().Status(http.StatusForbidden).JSON().Object().
			Value("code").IsEqual(util.Errors.AudienceByOwnerOnly.ErrorCode)
		tpl := f.template(t, f.owner.token, nil)
		api.Update(util.Coll.Templates, tpl, f.owner.token, map[string]any{s.AudienceKind: util.AudiencePrivate}).
			Expect().Status(http.StatusOK)
		api.Get(util.Coll.Templates, tpl, f.member.token).Expect().Status(http.StatusNotFound)
	})

	t.Run("an older template without an owner stays with the workspace", func(t *testing.T) {
		coll, _ := f.app.FindCollectionByNameOrId(util.Coll.Templates)
		row := core.NewRecord(coll)
		row.Set(util.Fields.Template.Workspace, f.owner.workspace)
		row.Set(util.Fields.Template.Name, "Legacy "+randomSuffix()[:6])
		row.Set(util.Fields.Template.Schema, map[string]any{"fields": []any{}})
		if err := f.app.Save(row); err != nil {
			t.Fatal(err)
		}
		api := f.api.T(t)
		api.Get(util.Coll.Templates, row.Id, f.noVault.token).Expect().Status(http.StatusOK)
		api.Update(util.Coll.Templates, row.Id, f.member.token, map[string]any{util.Fields.Template.Name: "Renamed " + randomSuffix()[:6]}).
			Expect().Status(http.StatusOK)
		// Nobody owns it, so nobody narrows it.
		for _, who := range []contactParty{f.owner, f.member} {
			api.Update(util.Coll.Templates, row.Id, who.token, map[string]any{s.AudienceKind: util.AudiencePrivate}).
				Expect().Status(http.StatusForbidden)
		}
	})

	t.Run("an attestation is changed with the permission, owned or not", func(t *testing.T) {
		t.Setenv(util.AllowAttestationsEnv, "true")
		a := util.Fields.Attestation
		api := f.api.T(t)
		// Issued directly: whether the operator allows issuing is not the
		// point here.
		coll, _ := f.app.FindCollectionByNameOrId(util.Coll.Attestations)
		row := core.NewRecord(coll)
		row.Set(a.User, f.member.id)
		row.Set(a.Workspace, f.owner.workspace)
		row.Set(a.Type, "membership")
		row.Set(a.Status, util.StatusActive)
		if err := f.app.Save(row); err != nil {
			t.Fatal(err)
		}
		id := row.Id
		api.Get(util.Coll.Attestations, id, f.owner.token).Expect().Status(http.StatusOK)
		// Reading attestations always took their permission; without it the
		// row is not listed among the readers, so it is not there.
		api.Get(util.Coll.Attestations, id, f.noVault.token).Expect().Status(http.StatusNotFound)

		// Its issuer loses the permission, and with it the right to revoke.
		f.setPermissions(t, f.member.id, util.PermContactsRead)
		api.Update(util.Coll.Attestations, id, f.member.token, map[string]any{a.Status: util.StatusRevoked}).
			Expect().Status(http.StatusForbidden)
		// The workspace's administrator holds it, owner or not.
		api.Update(util.Coll.Attestations, id, f.owner.token, map[string]any{a.Status: util.StatusRevoked}).
			Expect().Status(http.StatusOK)
		f.setPermissions(t, f.member.id, manage...)
	})
}

// Phase 4: keys, tools and webhooks follow the member they act for.

func TestCredentialsFollowTheirCreator(t *testing.T) {
	f := newVisibilityFixture(t)
	f.setPermissions(t, f.member.id, util.PermSharesManage, util.PermSharesRead, util.PermWebhooksManage,
		util.PermRequestsManage, util.PermRequestsRead, util.PermVaultRead, util.PermVaultWrite)
	s := util.Fields.Section
	memberShare := func(kind string) string {
		l := util.Fields.Link
		return extractID(t, f.baseURL, util.Coll.Links, f.member.token, map[string]any{
			l.Slug: "m" + randomSuffix()[:8], l.Label: "m", l.Status: util.StatusActive,
			l.User: f.member.id, l.Workspace: f.owner.workspace, s.AudienceKind: kind,
		})
	}
	private := memberShare(util.AudiencePrivate)
	open := memberShare(util.AudienceWorkspace)

	t.Run("an API key sees what its creator sees, not the workspace", func(t *testing.T) {
		api := f.api.T(t)
		key := api.Create(util.Coll.ApiKeys, f.owner.token, map[string]any{
			"label": "k-" + randomSuffix()[:6], "workspace": f.owner.workspace,
			"user": f.owner.id, "scopes": []string{util.PermSharesRead, util.PermSharesManage},
		}).Expect().Status(http.StatusOK).Header("X-Plain-Token").Raw()
		get := func(id string) int {
			return api.E.GET("/api/collections/"+util.Coll.Links+"/records/"+id).
				WithHeader("X-API-Key", key).Expect().Raw().StatusCode
		}
		if got := get(private); got != http.StatusNotFound {
			t.Errorf("a colleague's private share: %d, want 404", got)
		}
		if got := get(open); got != http.StatusOK {
			t.Errorf("a share open to the workspace: %d, want 200", got)
		}
		// Seeing is not editing: the share's editing stays with its owner.
		got := api.E.PATCH("/api/collections/"+util.Coll.Links+"/records/"+open).
			WithHeader("X-API-Key", key).WithJSON(map[string]any{"label": "x"}).Expect().Raw().StatusCode
		if got == http.StatusOK {
			t.Errorf("the key changed a share its creator may not change")
		}
	})

	t.Run("a webhook hears about what its creator sees", func(t *testing.T) {
		rcv := newWebhookReceiver(t)
		api := f.api.T(t)
		endpoint := api.E.POST("/api/webhooks/endpoints").WithHeader("Authorization", f.member.token).
			WithJSON(map[string]any{"url": rcv.srv.URL + "/hook", "events": []string{"record.created"}}).
			Expect().Status(http.StatusCreated).JSON().Object().Value("id").String().Raw()
		deliveries := func() int {
			rows, _ := f.app.FindRecordsByFilter(util.Coll.WebhookDeliveries, "endpoint = {:e}", "", 0, 0,
				dbx.Params{"e": endpoint})
			return len(rows)
		}
		// The owner's private record: the member's endpoint hears nothing.
		f.record(t, f.owner.token, f.owner.id, "secret"+randomSuffix()[:6], "x", nil)
		if n := deliveries(); n != 0 {
			t.Fatalf("a private record reached a colleague's webhook (%d deliveries)", n)
		}
		// The member's own record: heard.
		f.record(t, f.member.token, f.member.id, "own"+randomSuffix()[:6], "x", nil)
		if n := deliveries(); n != 1 {
			t.Fatalf("the creator's own record: %d deliveries, want 1", n)
		}
	})
}

// Phase 5: a workspace chooses who sees what its members create.

func TestWorkspaceDefaultAudience(t *testing.T) {
	f := newVisibilityFixture(t)
	f.setPermissions(t, f.member.id, util.PermSharesManage, util.PermSharesRead, util.PermContactsManage,
		util.PermContactsRead)
	s := util.Fields.Section
	setDefaults := func(defaults map[string]string) int {
		return f.api.Update(util.Coll.Workspaces, f.owner.workspace, f.owner.token, map[string]any{
			util.Fields.Workspace.DefaultAudience: defaults,
		}).Expect().Raw().StatusCode
	}

	t.Run("only known areas and audiences", func(t *testing.T) {
		if got := setDefaults(map[string]string{"links": "everyone"}); got != http.StatusBadRequest {
			t.Fatalf("an unknown audience: %d", got)
		}
		if got := setDefaults(map[string]string{"bookmarks": "workspace"}); got != http.StatusBadRequest {
			t.Fatalf("an area without an audience: %d", got)
		}
	})

	t.Run("new shares start with the workspace's default", func(t *testing.T) {
		if got := setDefaults(map[string]string{"links": "workspace", "contacts": "private"}); got != http.StatusOK {
			t.Fatalf("setting defaults: %d", got)
		}
		share := f.share(t, "", "", nil)
		row, _ := f.app.FindRecordById(util.Coll.Links, share)
		if a := services.SectionAudience(row); a.Kind != util.AudienceWorkspace {
			t.Fatalf("new share is %+v, want the workspace default", a)
		}
		c := f.contact(t, f.member.token, nil)
		f.api.Get(util.Coll.Contacts, c, f.owner.token).Expect().Status(http.StatusNotFound)
		// Naming an audience still wins.
		explicit := f.share(t, util.AudiencePrivate, util.EditingOwner, nil)
		row, _ = f.app.FindRecordById(util.Coll.Links, explicit)
		if a := services.SectionAudience(row); a.Kind != util.AudiencePrivate {
			t.Fatalf("an explicit audience was overridden: %+v", a)
		}
	})

	t.Run("what the server makes keeps the built-in default", func(t *testing.T) {
		if got := setDefaults(map[string]string{"links": "workspace", "sections": "workspace"}); got != http.StatusOK {
			t.Fatalf("setting defaults: %d", got)
		}
		coll, _ := f.app.FindCollectionByNameOrId(util.Coll.Links)
		row := core.NewRecord(coll)
		row.Set("slug", "srv"+randomSuffix()[:8])
		row.Set("label", "server-made")
		row.Set("status", util.StatusActive)
		row.Set("user", f.owner.id)
		row.Set("workspace", f.owner.workspace)
		if err := f.app.Save(row); err != nil {
			t.Fatal(err)
		}
		if a := services.SectionAudience(row); a.Kind != util.AudiencePrivate {
			t.Fatalf("a server-made share took the workspace default: %+v", a)
		}
	})
	_ = s
}

// Groups: managed by members who may invite, named by audiences.

func TestGroupsAPI(t *testing.T) {
	f := newVisibilityFixture(t)
	e := testutils.NewExpect(t, f.baseURL)
	call := func(method, path, token string, body any) *httpexpect.Response {
		req := e.Request(method, path).WithHeader("Authorization", token)
		if body != nil {
			req = req.WithJSON(body)
		}
		return req.Expect()
	}

	// The owner holds every permission; the member may not invite.
	call("POST", "/api/groups", f.member.token, map[string]any{"name": "Techs"}).
		Status(http.StatusForbidden)
	g := call("POST", "/api/groups", f.owner.token, map[string]any{"name": "Service Desk"}).
		Status(http.StatusCreated).JSON().Object()
	g.Value("key").IsEqual("service-desk")
	id := g.Value("id").String().Raw()
	call("POST", "/api/groups", f.owner.token, map[string]any{"name": "Service Desk"}).
		Status(http.StatusCreated).JSON().Object().Value("key").IsEqual("service-desk-2")
	call("POST", "/api/groups", f.owner.token, map[string]any{"name": "  "}).
		Status(http.StatusBadRequest)

	// Only members of the workspace join a group.
	call("PUT", "/api/groups/"+id+"/members/"+f.outsider.id, f.owner.token, nil).
		Status(http.StatusBadRequest)
	call("PUT", "/api/groups/"+id+"/members/"+f.member.id, f.owner.token, nil).
		Status(http.StatusOK).JSON().Object().Value("members").Array().Length().IsEqual(1)

	// Every member lists them.
	list := call("GET", "/api/groups", f.readOnly.token, nil).Status(http.StatusOK).JSON().Object()
	list.Value("canManage").IsEqual(false)
	list.Value("groups").Array().Length().Gt(1)
	call("GET", "/api/groups", f.outsider.token, nil).Status(http.StatusOK).JSON().Object().
		Value("groups").Array().Length().IsEqual(0)

	// A record in a section for the group reaches the member, and stops when
	// they leave the workspace.
	rec := f.record(t, f.owner.token, f.owner.id, "desk"+randomSuffix()[:6], "x", nil)
	f.audienceSection(t, util.AudienceGroups, util.EditingOwner, []string{id}, rec)
	f.api.Get(util.Coll.Records, rec, f.member.token).Expect().Status(http.StatusOK)
	f.api.Get(util.Coll.Records, rec, f.readOnly.token).Expect().Status(http.StatusNotFound)
	f.removeMember(t, f.member.id)
	rows, _ := f.app.FindAllRecords(util.Coll.GroupMembers, dbx.HashExp{util.Fields.GroupMember.Group: id})
	if len(rows) != 0 {
		t.Fatalf("leaving the workspace left %d group memberships behind", len(rows))
	}

	// Another workspace's group is not there.
	other := newVisibilityFixture(t)
	call("DELETE", "/api/groups/"+id, other.owner.token, nil).Status(http.StatusNotFound)
	call("PATCH", "/api/groups/"+id, f.owner.token, map[string]any{"name": "Desk"}).
		Status(http.StatusOK).JSON().Object().Value("name").IsEqual("Desk")
	call("DELETE", "/api/groups/"+id, f.owner.token, nil).Status(http.StatusNoContent)
}
