package tests

import (
	"net/http"
	"testing"

	"revoked/tests/testutils"
	"revoked/util"

	"github.com/gavv/httpexpect/v2"
	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase"
)

type sharedFixture struct {
	app           *pocketbase.PocketBase
	baseURL       string
	api           *testutils.PBClient
	owner, member contactParty
}

func newSharedFixture(t *testing.T) sharedFixture {
	t.Helper()
	f := newSealedFixture(t)
	member := addWorkspaceMember(t, f)
	return sharedFixture{f.app, f.baseURL, testutils.NewPBClient(t, f.baseURL), f.party, member}
}

// readOnly takes the member down to reading the vault.
func readOnly(t *testing.T, f sharedFixture) {
	t.Helper()
	m := util.Fields.WorkspaceMember
	row, err := f.app.FindFirstRecordByFilter(util.Coll.WorkspaceMembers,
		m.Workspace+" = {:w} && "+m.User+" = {:u}", dbx.Params{"w": f.owner.workspace, "u": f.member.id})
	if err != nil {
		t.Fatal(err)
	}
	scopes, _ := util.ExpandPermissions([]string{util.PermVaultRead})
	row.Set(m.Permissions, scopes)
	if err := f.app.Save(row); err != nil {
		t.Fatal(err)
	}
}

func (f sharedFixture) record(t *testing.T, token, user, key, value string, extra map[string]any) string {
	t.Helper()
	body := map[string]any{
		util.Fields.Record.Key: key, util.Fields.Record.Value: value, util.Fields.Record.Label: key,
		util.Fields.Record.Type: util.TypeText, util.Fields.Record.Format: util.FormatDefault,
		util.Fields.Record.User: user, util.Fields.Record.Workspace: f.owner.workspace,
	}
	for k, v := range extra {
		body[k] = v
	}
	return extractID(t, f.baseURL, util.Coll.Records, token, body)
}

func (f sharedFixture) section(t *testing.T, token, user, key string, shared bool, records ...string) string {
	t.Helper()
	return extractID(t, f.baseURL, util.Coll.Sections, token, map[string]any{
		util.Fields.Section.Key: key, util.Fields.Section.Name: key,
		util.Fields.Section.User: user, util.Fields.Section.Workspace: f.owner.workspace,
		util.Fields.Section.Records: records, util.Fields.Section.Shared: shared,
	})
}

func (f sharedFixture) shared(t *testing.T, token string) *httpexpect.Object {
	t.Helper()
	return testutils.NewExpect(t, f.baseURL).GET("/api/shared/vault").
		WithHeader("Authorization", token).Expect().Status(http.StatusOK).JSON().Object()
}

func TestSharedSections(t *testing.T) {
	t.Run("members read the records of a shared section, not of others", func(t *testing.T) {
		f := newSharedFixture(t)
		shown := f.record(t, f.owner.token, f.owner.id, "wifi", "hunter2", nil)
		private := f.record(t, f.owner.token, f.owner.id, "pin", "1234", nil)
		f.section(t, f.owner.token, f.owner.id, "office", true, shown)
		f.section(t, f.owner.token, f.owner.id, "mine", false, private)

		body := f.shared(t, f.member.token)
		sections := body.Value("sections").Array()
		sections.Length().IsEqual(1)
		sections.Value(0).Object().Value("ownerEmail").IsEqual(f.owner.email)
		records := body.Value("records").Array()
		records.Length().IsEqual(1)
		records.Value(0).Object().Value("id").IsEqual(shown)
		records.Value(0).Object().Value("value").IsEqual("hunter2")

		// The collection API stays self-only.
		f.api.Get(util.Coll.Records, shown, f.member.token).Expect().Status(http.StatusNotFound)
		// And the owner is not shown their own sections here.
		f.shared(t, f.owner.token).Value("sections").Array().Length().IsEqual(0)
	})

	t.Run("a member who may only read cannot change a shared record", func(t *testing.T) {
		f := newSharedFixture(t)
		readOnly(t, f)
		shown := f.record(t, f.owner.token, f.owner.id, "wifi", "hunter2", nil)
		f.section(t, f.owner.token, f.owner.id, "office", true, shown)
		f.api.Update(util.Coll.Records, shown, f.member.token, map[string]any{
			util.Fields.Record.Value: "changed",
		}).Expect().Status(http.StatusForbidden)
		f.api.Delete(util.Coll.Records, shown, f.member.token).Expect().Status(http.StatusForbidden)
		f.shared(t, f.member.token).Value("records").Array().Value(0).Object().
			Value("value").IsEqual("hunter2")
	})

	t.Run("unsharing hides it again", func(t *testing.T) {
		f := newSharedFixture(t)
		shown := f.record(t, f.owner.token, f.owner.id, "wifi", "hunter2", nil)
		section := f.section(t, f.owner.token, f.owner.id, "office", true, shown)
		f.api.Update(util.Coll.Sections, section, f.owner.token, map[string]any{
			util.Fields.Section.Shared: false,
		}).Expect().Status(http.StatusOK)
		f.shared(t, f.member.token).Value("records").Array().Length().IsEqual(0)
	})

	t.Run("a section cannot share someone else's record", func(t *testing.T) {
		f := newSharedFixture(t)
		// The member's own record, put into the member's shared section, is
		// fine; the owner's record named in it is not the member's to share.
		ownersRecord := f.record(t, f.owner.token, f.owner.id, "pin", "1234", nil)
		mine := f.record(t, f.member.token, f.member.id, "note", "hello", nil)
		f.section(t, f.member.token, f.member.id, "board", true, mine, ownersRecord)
		records := f.shared(t, f.owner.token).Value("records").Array()
		records.Length().IsEqual(1)
		records.Value(0).Object().Value("id").IsEqual(mine)
	})

	t.Run("no files and no aliases", func(t *testing.T) {
		f := newSharedFixture(t)
		parent := f.record(t, f.owner.token, f.owner.id, "pin", "1234", nil)
		alias := f.record(t, f.owner.token, f.owner.id, "pin_alias", "", map[string]any{
			util.Fields.Record.AliasOf: parent,
		})
		f.section(t, f.owner.token, f.owner.id, "office", true, alias)
		f.shared(t, f.member.token).Value("records").Array().Length().IsEqual(0)
	})

	t.Run("only for members who may read the vault", func(t *testing.T) {
		f := newSharedFixture(t)
		shown := f.record(t, f.owner.token, f.owner.id, "wifi", "hunter2", nil)
		f.section(t, f.owner.token, f.owner.id, "office", true, shown)
		outsider := newContactParty(t, f.baseURL)
		// An outsider's active workspace is their own; nothing of this one shows.
		f.shared(t, outsider.token).Value("records").Array().Length().IsEqual(0)
		testutils.NewExpect(t, f.baseURL).GET("/api/shared/vault").Expect().Status(http.StatusUnauthorized)
	})

	t.Run("only its owner can share a section", func(t *testing.T) {
		f := newSharedFixture(t)
		section := f.section(t, f.owner.token, f.owner.id, "office", false)
		// The member may manage the vault, so may change the section, but not
		// widen who reads it.
		f.api.Update(util.Coll.Sections, section, f.member.token, map[string]any{
			util.Fields.Section.Shared: true,
		}).Expect().Status(http.StatusForbidden).
			JSON().Object().Value("code").IsEqual(util.Errors.SectionShareByPersonOnly.ErrorCode)
		f.api.Update(util.Coll.Sections, section, f.owner.token, map[string]any{
			util.Fields.Section.Shared: true,
		}).Expect().Status(http.StatusOK)
		f.shared(t, f.member.token).Value("sections").Array().Length().IsEqual(1)
	})
}
