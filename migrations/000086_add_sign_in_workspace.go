package migrations

import (
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/migrations"
	"github.com/pocketbase/pocketbase/tools/types"
)

// Gives signIns a workspace: each workspace is its own account at a service,
// with its own subject, name and shared entries. One row per person, workspace
// and service; the app lists the active workspace's.
//
// Older rows move to the workspace their link lives in, otherwise to the
// person's active one.
func init() {
	migrations.Register(func(app core.App) error {
		signIns, err := app.FindCollectionByNameOrId(util.Coll.SignIns)
		if err != nil {
			return err
		}
		s := util.Fields.SignIn
		if signIns.Fields.GetByName(s.Workspace) != nil {
			return nil
		}
		workspaces, err := app.FindCollectionByNameOrId(util.Coll.Workspaces)
		if err != nil {
			return err
		}
		signIns.Fields.Add(&core.RelationField{
			Name: s.Workspace, CollectionId: workspaces.Id, MaxSelect: 1, CascadeDelete: true,
		})
		signIns.RemoveIndex("idxSignInsClient")
		signIns.AddIndex("idxSignInsClient", true, s.User+", "+s.Workspace+", "+s.ClientId, "")
		owner := util.AccessSpec{
			Kind:  util.AccessUserSelf,
			Extra: s.Workspace + " = @request.auth." + util.Fields.User.ActiveWorkspace,
		}
		signIns.ListRule = types.Pointer(owner.Rule())
		signIns.ViewRule = types.Pointer(owner.Rule())
		if err := app.Save(signIns); err != nil {
			return err
		}

		rows, err := app.FindAllRecords(util.Coll.SignIns)
		if err != nil {
			return err
		}
		for _, row := range rows {
			workspace := ""
			if link, err := app.FindRecordById(util.Coll.Links, row.GetString(s.Link)); err == nil && link != nil {
				workspace = link.GetString(util.Fields.Link.Workspace)
			}
			if workspace == "" {
				if user, err := app.FindRecordById(util.Coll.Users, row.GetString(s.User)); err == nil && user != nil {
					workspace = user.GetString(util.Fields.User.ActiveWorkspace)
				}
			}
			row.Set(s.Workspace, workspace)
			if err := app.Save(row); err != nil {
				return err
			}
		}
		return nil
	}, func(app core.App) error {
		return nil
	})
}
