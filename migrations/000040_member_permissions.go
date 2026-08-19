package migrations

import (
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/migrations"
	"github.com/pocketbase/pocketbase/tools/types"
)

// Gives workspace members the same permission vocabulary API keys already use,
// so access is declared once and enforced identically for both.
//
// Order matters: the field is created and backfilled BEFORE the rules start
// consulting it, otherwise every existing member loses access between the two
// statements.
//
// The backfill preserves current behaviour rather than reinterpreting it.
// Members previously reached only their own rows, and the new rules keep that
// (a row's owner always passes), so an existing member granted nothing is
// exactly as capable as before; admins receive the full set because they are
// the ones who could already administer the workspace.
func init() {
	migrations.Register(func(app core.App) error {
		members, err := app.FindCollectionByNameOrId(util.Coll.WorkspaceMembers)
		if err != nil {
			return err
		}

		if members.Fields.GetByName(util.Fields.WorkspaceMember.Permissions) == nil {
			members.Fields.Add(&core.SelectField{
				Name:      util.Fields.WorkspaceMember.Permissions,
				Values:    util.AllScopes,
				MaxSelect: len(util.AllScopes),
			})
			if err := app.Save(members); err != nil {
				return err
			}
		}

		adminScopes, _ := util.ExpandPermissions(allPermissionKeys())
		rows, err := app.FindAllRecords(util.Coll.WorkspaceMembers)
		if err != nil {
			return err
		}
		for _, row := range rows {
			if len(row.GetStringSlice(util.Fields.WorkspaceMember.Permissions)) > 0 {
				continue
			}
			if row.GetString(util.Fields.WorkspaceMember.Role) != util.RoleAdmin {
				continue
			}
			row.Set(util.Fields.WorkspaceMember.Permissions, adminScopes)
			if err := app.Save(row); err != nil {
				return err
			}
		}

		return applyFrozenRules(app, frozenRules040)
	}, func(app core.App) error {
		members, err := app.FindCollectionByNameOrId(util.Coll.WorkspaceMembers)
		if err == nil {
			members.Fields.RemoveByName(util.Fields.WorkspaceMember.Permissions)
			_ = app.Save(members)
		}
		return nil
	})
}

func allPermissionKeys() []string {
	keys := make([]string, 0, len(util.Permissions))
	for _, p := range util.Permissions {
		keys = append(keys, p.Key)
	}
	return keys
}

// applyFrozenRules writes a snapshot of rules onto their collections.
//
// The strings are frozen rather than rendered from util.CollectionAccess at run
// time. A migration must produce the same SQL forever, and a live builder that
// later references a column created by a newer migration would break a
// from-scratch replay at exactly this point. Changing a builder therefore means
// writing a NEW reconcile migration; TestAccessRegistryMatchesRules fails until
// one exists.
func applyFrozenRules(app core.App, rules map[string]map[string]string) error {
	for collName, actions := range rules {
		coll, err := app.FindCollectionByNameOrId(collName)
		if err != nil {
			return err
		}
		for action, rule := range actions {
			ptr := types.Pointer(rule)
			switch action {
			case util.ActionCreate:
				coll.CreateRule = ptr
			case util.ActionUpdate:
				coll.UpdateRule = ptr
			case util.ActionDelete:
				coll.DeleteRule = ptr
			}
		}
		if err := app.Save(coll); err != nil {
			return err
		}
	}
	return nil
}

var frozenRules040 = map[string]map[string]string{
	"apiKeys": {
		"create": "(@request.auth.collectionName = 'users' && user = @request.auth.id && workspace = @request.auth.activeWorkspace && @request.auth.activeRole = 'admin')",
		"delete": "@request.auth.collectionName = 'users' && user = @request.auth.id",
	},
	"identities": {
		"create": "(@request.auth.collectionName = 'users' && workspace = @request.auth.activeWorkspace && @collection.workspaceMembers.workspace ?= workspace && @collection.workspaceMembers.user ?= @request.auth.id && (user = @request.auth.id || @collection.workspaceMembers.permissions ~ '\"identity:create\"')) || (@request.auth.collectionName = 'apiKeys' && workspace = @request.auth.workspace.id && @request.auth.scopes ~ '\"identity:create\"')",
		"delete": "(@request.auth.collectionName = 'users' && workspace = @request.auth.activeWorkspace && @collection.workspaceMembers.workspace ?= workspace && @collection.workspaceMembers.user ?= @request.auth.id && (user = @request.auth.id || @collection.workspaceMembers.permissions ~ '\"identity:delete\"')) || (@request.auth.collectionName = 'apiKeys' && workspace = @request.auth.workspace.id && @request.auth.scopes ~ '\"identity:delete\"')",
		"update": "(@request.auth.collectionName = 'users' && workspace = @request.auth.activeWorkspace && @collection.workspaceMembers.workspace ?= workspace && @collection.workspaceMembers.user ?= @request.auth.id && (user = @request.auth.id || @collection.workspaceMembers.permissions ~ '\"identity:update\"')) || (@request.auth.collectionName = 'apiKeys' && workspace = @request.auth.workspace.id && @request.auth.scopes ~ '\"identity:update\"')",
	},
	"links": {
		"create": "(@request.auth.collectionName = 'users' && workspace = @request.auth.activeWorkspace && @collection.workspaceMembers.workspace ?= workspace && @collection.workspaceMembers.user ?= @request.auth.id && (user = @request.auth.id || @collection.workspaceMembers.permissions ~ '\"link:create\"')) || (@request.auth.collectionName = 'apiKeys' && workspace = @request.auth.workspace.id && @request.auth.scopes ~ '\"link:create\"')",
		"delete": "(@request.auth.collectionName = 'users' && workspace = @request.auth.activeWorkspace && @collection.workspaceMembers.workspace ?= workspace && @collection.workspaceMembers.user ?= @request.auth.id && (user = @request.auth.id || @collection.workspaceMembers.permissions ~ '\"link:delete\"')) || (@request.auth.collectionName = 'apiKeys' && workspace = @request.auth.workspace.id && @request.auth.scopes ~ '\"link:delete\"')",
		"update": "(@request.auth.collectionName = 'users' && workspace = @request.auth.activeWorkspace && @collection.workspaceMembers.workspace ?= workspace && @collection.workspaceMembers.user ?= @request.auth.id && (user = @request.auth.id || @collection.workspaceMembers.permissions ~ '\"link:update\"')) || (@request.auth.collectionName = 'apiKeys' && workspace = @request.auth.workspace.id && @request.auth.scopes ~ '\"link:update\"')",
	},
	"notifications": {
		"delete": "(@request.auth.collectionName = 'users' && workspace = @request.auth.activeWorkspace && @collection.workspaceMembers.workspace ?= workspace && @collection.workspaceMembers.user ?= @request.auth.id && (user = @request.auth.id || @collection.workspaceMembers.permissions ~ '\"notification:delete\"')) || (@request.auth.collectionName = 'apiKeys' && workspace = @request.auth.workspace.id && @request.auth.scopes ~ '\"notification:delete\"')",
		"update": "(@request.auth.collectionName = 'users' && workspace = @request.auth.activeWorkspace && @collection.workspaceMembers.workspace ?= workspace && @collection.workspaceMembers.user ?= @request.auth.id && (user = @request.auth.id || @collection.workspaceMembers.permissions ~ '\"notification:update\"')) || (@request.auth.collectionName = 'apiKeys' && workspace = @request.auth.workspace.id && @request.auth.scopes ~ '\"notification:update\"')",
	},
	"records": {
		"create": "(@request.auth.collectionName = 'users' && workspace = @request.auth.activeWorkspace && @collection.workspaceMembers.workspace ?= workspace && @collection.workspaceMembers.user ?= @request.auth.id && (user = @request.auth.id || @collection.workspaceMembers.permissions ~ '\"record:create\"')) || (@request.auth.collectionName = 'apiKeys' && workspace = @request.auth.workspace.id && @request.auth.scopes ~ '\"record:create\"')",
		"delete": "(@request.auth.collectionName = 'users' && workspace = @request.auth.activeWorkspace && @collection.workspaceMembers.workspace ?= workspace && @collection.workspaceMembers.user ?= @request.auth.id && (user = @request.auth.id || ((@collection.workspaceMembers.permissions ~ '\"record:delete\"' && requestedBy = '') || (@collection.workspaceMembers.permissions ~ '\"response:delete\"' && requestedBy != '')))) || (@request.auth.collectionName = 'apiKeys' && workspace = @request.auth.workspace.id && ((@request.auth.scopes ~ '\"record:delete\"' && requestedBy = '') || (@request.auth.scopes ~ '\"response:delete\"' && requestedBy != '')))",
		"update": "(@request.auth.collectionName = 'users' && workspace = @request.auth.activeWorkspace && @collection.workspaceMembers.workspace ?= workspace && @collection.workspaceMembers.user ?= @request.auth.id && (user = @request.auth.id || ((@collection.workspaceMembers.permissions ~ '\"record:update\"' && requestedBy = '') || (@collection.workspaceMembers.permissions ~ '\"response:update\"' && requestedBy != '')))) || (@request.auth.collectionName = 'apiKeys' && workspace = @request.auth.workspace.id && ((@request.auth.scopes ~ '\"record:update\"' && requestedBy = '') || (@request.auth.scopes ~ '\"response:update\"' && requestedBy != '')))",
	},
	"requests": {
		"create": "(@request.auth.collectionName = 'users' && workspace = @request.auth.activeWorkspace && @collection.workspaceMembers.workspace ?= workspace && @collection.workspaceMembers.user ?= @request.auth.id && (user = @request.auth.id || @collection.workspaceMembers.permissions ~ '\"request:create\"')) || (@request.auth.collectionName = 'apiKeys' && workspace = @request.auth.workspace.id && @request.auth.scopes ~ '\"request:create\"')",
		"delete": "(@request.auth.collectionName = 'users' && workspace = @request.auth.activeWorkspace && @collection.workspaceMembers.workspace ?= workspace && @collection.workspaceMembers.user ?= @request.auth.id && (user = @request.auth.id || @collection.workspaceMembers.permissions ~ '\"request:delete\"')) || (@request.auth.collectionName = 'apiKeys' && workspace = @request.auth.workspace.id && @request.auth.scopes ~ '\"request:delete\"')",
		"update": "(@request.auth.collectionName = 'users' && workspace = @request.auth.activeWorkspace && @collection.workspaceMembers.workspace ?= workspace && @collection.workspaceMembers.user ?= @request.auth.id && (user = @request.auth.id || @collection.workspaceMembers.permissions ~ '\"request:update\"')) || (@request.auth.collectionName = 'apiKeys' && workspace = @request.auth.workspace.id && @request.auth.scopes ~ '\"request:update\"')",
	},
	"sections": {
		"create": "(@request.auth.collectionName = 'users' && workspace = @request.auth.activeWorkspace && @collection.workspaceMembers.workspace ?= workspace && @collection.workspaceMembers.user ?= @request.auth.id && (user = @request.auth.id || @collection.workspaceMembers.permissions ~ '\"section:create\"')) || (@request.auth.collectionName = 'apiKeys' && workspace = @request.auth.workspace.id && @request.auth.scopes ~ '\"section:create\"')",
		"delete": "(@request.auth.collectionName = 'users' && workspace = @request.auth.activeWorkspace && @collection.workspaceMembers.workspace ?= workspace && @collection.workspaceMembers.user ?= @request.auth.id && (user = @request.auth.id || ((@collection.workspaceMembers.permissions ~ '\"section:delete\"' && requestedBy = '') || (@collection.workspaceMembers.permissions ~ '\"response:delete\"' && requestedBy != '')))) || (@request.auth.collectionName = 'apiKeys' && workspace = @request.auth.workspace.id && ((@request.auth.scopes ~ '\"section:delete\"' && requestedBy = '') || (@request.auth.scopes ~ '\"response:delete\"' && requestedBy != '')))",
		"update": "(@request.auth.collectionName = 'users' && workspace = @request.auth.activeWorkspace && @collection.workspaceMembers.workspace ?= workspace && @collection.workspaceMembers.user ?= @request.auth.id && (user = @request.auth.id || ((@collection.workspaceMembers.permissions ~ '\"section:update\"' && requestedBy = '') || (@collection.workspaceMembers.permissions ~ '\"response:update\"' && requestedBy != '')))) || (@request.auth.collectionName = 'apiKeys' && workspace = @request.auth.workspace.id && ((@request.auth.scopes ~ '\"section:update\"' && requestedBy = '') || (@request.auth.scopes ~ '\"response:update\"' && requestedBy != '')))",
	},
	"templates": {
		"create": "(@request.auth.collectionName = 'users' && @collection.workspaceMembers.workspace ?= workspace && @collection.workspaceMembers.user ?= @request.auth.id && (@collection.workspaceMembers.role ?= 'admin' || @collection.workspaceMembers.permissions ~ '\"template:create\"')) || (@request.auth.collectionName = 'apiKeys' && workspace = @request.auth.workspace.id && @request.auth.scopes ~ '\"template:create\"')",
		"delete": "(@request.auth.collectionName = 'users' && @collection.workspaceMembers.workspace ?= workspace && @collection.workspaceMembers.user ?= @request.auth.id && (@collection.workspaceMembers.role ?= 'admin' || @collection.workspaceMembers.permissions ~ '\"template:delete\"')) || (@request.auth.collectionName = 'apiKeys' && workspace = @request.auth.workspace.id && @request.auth.scopes ~ '\"template:delete\"')",
		"update": "(@request.auth.collectionName = 'users' && @collection.workspaceMembers.workspace ?= workspace && @collection.workspaceMembers.user ?= @request.auth.id && (@collection.workspaceMembers.role ?= 'admin' || @collection.workspaceMembers.permissions ~ '\"template:update\"')) || (@request.auth.collectionName = 'apiKeys' && workspace = @request.auth.workspace.id && @request.auth.scopes ~ '\"template:update\"')",
	},
	"workspaceMembers": {
		"create": "(@request.auth.collectionName = 'users' && @collection.workspaceMembers.workspace ?= @request.body.workspace && @collection.workspaceMembers.user ?= @request.auth.id && (@collection.workspaceMembers.role ?= 'admin' || @collection.workspaceMembers.permissions ~ '\"workspaceMembers:create\"')) || (@request.auth.collectionName = 'apiKeys' && @request.body.workspace = @request.auth.workspace.id && @request.auth.scopes ~ '\"workspaceMembers:create\"')",
		"delete": "(@request.auth.collectionName = 'users' && @collection.workspaceMembers.workspace ?= workspace && @collection.workspaceMembers.user ?= @request.auth.id && (@collection.workspaceMembers.role ?= 'admin' || @collection.workspaceMembers.permissions ~ '\"workspaceMembers:delete\"')) || (@request.auth.collectionName = 'apiKeys' && workspace = @request.auth.workspace.id && @request.auth.scopes ~ '\"workspaceMembers:delete\"')",
		"update": "(@request.auth.collectionName = 'users' && @collection.workspaceMembers.workspace ?= workspace && @collection.workspaceMembers.user ?= @request.auth.id && (@collection.workspaceMembers.role ?= 'admin' || @collection.workspaceMembers.permissions ~ '\"workspaceMembers:update\"')) || (@request.auth.collectionName = 'apiKeys' && workspace = @request.auth.workspace.id && @request.auth.scopes ~ '\"workspaceMembers:update\"')",
	},
	"workspaces": {
		"delete": "(@request.auth.collectionName = 'users' && @collection.workspaceMembers.workspace ?= id && @collection.workspaceMembers.user ?= @request.auth.id && (@collection.workspaceMembers.role ?= 'admin' || @collection.workspaceMembers.permissions ~ '\"workspaces:delete\"')) || (@request.auth.collectionName = 'apiKeys' && id = @request.auth.workspace.id && @request.auth.scopes ~ '\"workspaces:delete\"')",
		"update": "((@request.auth.collectionName = 'users' && @collection.workspaceMembers.workspace ?= id && @collection.workspaceMembers.user ?= @request.auth.id && (@collection.workspaceMembers.role ?= 'admin' || @collection.workspaceMembers.permissions ~ '\"workspaces:update\"')) || (@request.auth.collectionName = 'apiKeys' && id = @request.auth.workspace.id && @request.auth.scopes ~ '\"workspaces:update\"')) && @request.body.type:isset = false",
	},
}
