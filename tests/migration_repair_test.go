package tests

import (
	"testing"

	"revoked/tests/testutils"
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tools/types"
)

// A database that ran an earlier build of 000097 has contacts with an
// audience but no createdBy, and readers/editors that are not hidden.
// 000098 must bring it to the same schema as a fresh one instead of failing
// on rules that name the missing column.
func TestMigration098RepairsAnEarlier097(t *testing.T) {
	_, app := testutils.SetupTestApp(t)

	contacts, err := app.FindCollectionByNameOrId(util.Coll.Contacts)
	if err != nil {
		t.Fatal(err)
	}
	// The earlier build: rules owned by user, no createdBy, lists visible.
	old := util.WorkspaceAudienceRead(util.ScopeContactRead)
	contacts.ListRule = types.Pointer(old)
	contacts.ViewRule = types.Pointer(old)
	contacts.UpdateRule = types.Pointer(util.WorkspaceAudienceWrite(util.ScopeContactUpdate))
	contacts.DeleteRule = types.Pointer(util.WorkspaceAudienceWrite(util.ScopeContactDelete))
	contacts.Fields.RemoveByName(util.Fields.Contact.CreatedBy)
	if f, ok := contacts.Fields.GetByName(util.Fields.Section.Readers).(*core.RelationField); ok {
		f.Hidden = false
	}
	if err := app.Save(contacts); err != nil {
		t.Fatalf("simulating the earlier build: %v", err)
	}

	var up func(core.App) error
	for _, m := range core.AppMigrations.Items() {
		if m.File == "000098_bind_keys_to_their_creator.go" {
			up = m.Up
		}
	}
	if up == nil {
		t.Fatal("000098 is not registered")
	}
	if err := up(app); err != nil {
		t.Fatalf("000098 on an earlier 000097: %v", err)
	}

	contacts, _ = app.FindCollectionByNameOrId(util.Coll.Contacts)
	if contacts.Fields.GetByName(util.Fields.Contact.CreatedBy) == nil {
		t.Fatal("createdBy was not added")
	}
	if f, ok := contacts.Fields.GetByName(util.Fields.Section.Readers).(*core.RelationField); !ok || !f.Hidden {
		t.Fatal("readers is not hidden again")
	}
	want := util.AudienceReadRules[util.Coll.Contacts]
	if contacts.ListRule == nil || *contacts.ListRule != want {
		t.Fatalf("contacts read rule not the current one: %v", contacts.ListRule)
	}
}
