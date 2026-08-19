// Package migrations contains the PocketBase database migrations that define the revoked schema.
package migrations

import (
	"revoked/util"
	"strings"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/migrations"
)

func init() {
	migrations.Register(func(app core.App) error {
		workspace := core.NewBaseCollection(util.Coll.Workspaces)
		workspace.Fields.Add(
			&core.TextField{Name: util.Fields.Workspace.Name, Required: true, Min: 1, Max: 100},
			&core.TextField{Name: util.Fields.Workspace.Slug, Required: true, Min: 1, Max: 50, Pattern: util.SlugPattern},
			&core.SelectField{Name: util.Fields.Workspace.Type, Values: []string{"personal", "business"}, Required: true, MaxSelect: 1},
			&core.AutodateField{Name: util.Fields.Workspace.Created, OnCreate: true},
			&core.AutodateField{Name: util.Fields.Workspace.Updated, OnCreate: true, OnUpdate: true},
		)
		workspace.AddIndex("idxWorkspaceSlug", true, util.Fields.Workspace.Slug, "")
		if err := app.Save(workspace); err != nil {
			return err
		}

		users, err := app.FindCollectionByNameOrId(util.Coll.Users)
		if err != nil {
			return err
		}
		users.Fields.Add(
			// Optional by design: a freshly created user belongs to no workspace yet.
			&core.RelationField{
				Name:          util.Fields.User.ActiveWorkspace,
				CollectionId:  workspace.Id,
				MaxSelect:     1,
				CascadeDelete: false,
			},
			&core.SelectField{
				Name:      util.Fields.User.ActiveRole,
				Values:    util.WorkspaceRoles,
				MaxSelect: 1,
			},
		)
		if err := app.Save(users); err != nil {
			return err
		}
		workspaceMember := core.NewBaseCollection(util.Coll.WorkspaceMembers)
		workspaceMember.Fields.Add(
			&core.RelationField{
				Name:          util.Fields.WorkspaceMember.User,
				CollectionId:  users.Id,
				Required:      true,
				MaxSelect:     1,
				CascadeDelete: true,
			},
			&core.RelationField{
				Name:          util.Fields.WorkspaceMember.Workspace,
				CollectionId:  workspace.Id,
				Required:      true,
				MaxSelect:     1,
				CascadeDelete: true,
			},
			&core.SelectField{
				Name:      util.Fields.WorkspaceMember.Role,
				Values:    util.WorkspaceRoles,
				MaxSelect: 1,
				Required:  true,
			},
			&core.AutodateField{Name: util.Fields.WorkspaceMember.Created, OnCreate: true},
			&core.AutodateField{Name: util.Fields.WorkspaceMember.Updated, OnCreate: true, OnUpdate: true},
		)
		workspaceMember.AddIndex(
			"idxWorkspaceMemberUserWorkspace",
			true,
			strings.Join([]string{
				util.Fields.WorkspaceMember.Workspace,
				util.Fields.WorkspaceMember.User,
			}, ","),
			"",
		)

		if err := app.Save(workspaceMember); err != nil {
			return err
		}

		return nil

	}, func(app core.App) error {
		collections := []string{util.Coll.WorkspaceMembers, util.Coll.Workspaces}
		for _, name := range collections {
			col, err := app.FindCollectionByNameOrId(name)
			if err != nil {
				continue
			}
			if err := app.Delete(col); err != nil {
				return err
			}
		}
		users, err := app.FindCollectionByNameOrId(util.Coll.Users)
		if err == nil {
			users.Fields.RemoveByName(util.Fields.User.ActiveWorkspace)
			users.Fields.RemoveByName(util.Fields.User.ActiveRole)
			err := app.Save(users)
			if err != nil {
				return err
			}
		}

		return nil
	})
}
