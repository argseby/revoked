package migrations

import (
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/migrations"
)

// API keys act as the member who made them (VISIBILITY.md, phase 4): on every
// collection with an audience, the key branch of a rule now also requires the
// key's creator among the row's readers (or editors, for a change). Before,
// a key holding a scope reached every member's rows of its workspace.
//
// 000095–000097 installed these rules with the key branch of their time;
// this reinstalls them, stating the specs here as applyFrozenRules asks. It
// also repairs what earlier builds of 000095–000097 left out (contacts'
// createdBy, hidden readers and editors), so a database that ran them
// arrives at the same schema as a fresh one.
func init() {
	type rules struct {
		read           string
		update, remove util.AccessSpec
	}
	by := util.Fields.Contact.CreatedBy
	frozen := map[string]rules{
		util.Coll.Records: {util.WorkspaceAudienceRead(util.ScopeRecordRead),
			util.AccessSpec{Kind: util.AccessWorkspaceAudience, Scope: util.ScopeRecordUpdate, ResponseScope: util.ScopeResponseUpdate},
			util.AccessSpec{Kind: util.AccessWorkspaceAudience, Scope: util.ScopeRecordDelete, ResponseScope: util.ScopeResponseDelete}},
		util.Coll.Sections: {util.WorkspaceAudienceRead(util.ScopeSectionRead),
			util.AccessSpec{Kind: util.AccessWorkspaceAudience, Scope: util.ScopeSectionUpdate, ResponseScope: util.ScopeResponseUpdate},
			util.AccessSpec{Kind: util.AccessWorkspaceAudience, Scope: util.ScopeSectionDelete, ResponseScope: util.ScopeResponseDelete}},
		util.Coll.Links: {util.WorkspaceAudienceRead(util.ScopeLinkRead),
			util.AccessSpec{Kind: util.AccessWorkspaceAudienceSelf, Scope: util.ScopeLinkUpdate},
			util.AccessSpec{Kind: util.AccessWorkspaceAudienceSelf, Scope: util.ScopeLinkDelete}},
		util.Coll.Requests: {util.WorkspaceAudienceRead(util.ScopeRequestRead),
			util.AccessSpec{Kind: util.AccessWorkspaceAudienceSelf, Scope: util.ScopeRequestUpdate},
			util.AccessSpec{Kind: util.AccessWorkspaceAudienceSelf, Scope: util.ScopeRequestDelete}},
		util.Coll.Templates: {util.WorkspaceAudienceRead(util.ScopeTemplateRead) + " || (@request.auth.id != '' && workspace = '')",
			util.AccessSpec{Kind: util.AccessWorkspaceAudienceSelf, Scope: util.ScopeTemplateUpdate},
			util.AccessSpec{Kind: util.AccessWorkspaceAudienceSelf, Scope: util.ScopeTemplateDelete}},
		util.Coll.Contacts: {util.WorkspaceAudienceReadBy(by, util.ScopeContactRead),
			util.AccessSpec{Kind: util.AccessWorkspaceAudienceSelf, Scope: util.ScopeContactUpdate, OwnerField: by},
			util.AccessSpec{Kind: util.AccessWorkspaceAudienceSelf, Scope: util.ScopeContactDelete, OwnerField: by}},
		util.Coll.Attestations: {util.WorkspaceAudienceRead(util.ScopeAttestationRead),
			util.AccessSpec{Kind: util.AccessWorkspaceAudienceAdmin, Scope: util.ScopeAttestationUpdate},
			util.AccessSpec{Kind: util.AccessWorkspaceAudienceAdmin, Scope: util.ScopeAttestationDelete}},
	}
	migrations.Register(func(app core.App) error {
		users, err := app.FindCollectionByNameOrId(util.Coll.Users)
		if err != nil {
			return err
		}
		for name, r := range frozen {
			c, err := app.FindCollectionByNameOrId(name)
			if err != nil {
				return err
			}
			// An earlier build of 000097 gave contacts their audience without
			// createdBy; a database that ran it lacks the column the contacts
			// rules name. Add it here, before the rules that need it.
			if name == util.Coll.Contacts && c.Fields.GetByName(by) == nil {
				c.Fields.Add(&core.RelationField{Name: by, CollectionId: users.Id, MaxSelect: 1})
			}
			// The same builds may have left readers and editors visible in
			// responses; they are the server's, and hidden.
			for _, f := range []string{util.Fields.Section.Readers, util.Fields.Section.Editors} {
				if field, ok := c.Fields.GetByName(f).(*core.RelationField); ok {
					field.Hidden = true
				}
			}
			applyAudienceRules(c, r.read, r.update, r.remove)
			if err := app.Save(c); err != nil {
				return err
			}
		}
		return nil
	}, func(app core.App) error {
		// The rules of 000095–000097 differ from these only in the key
		// branch, which a downgrade may leave as it is: it is narrower.
		return nil
	})
}
