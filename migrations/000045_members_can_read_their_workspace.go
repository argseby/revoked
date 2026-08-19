package migrations

import (
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/migrations"
	"github.com/pocketbase/pocketbase/tools/types"
)

// Lets a member read the workspace they belong to.
//
// The list/view rule required role = 'admin', so a member who joined by invite
// got a 404 fetching their own workspace and the join looked like it had
// failed. The write rules dropped the same gate: role is derived from whether a
// member may invite, so gating on it also locked members out of every
// permission they held without being an inviter — someone granted "Manage
// templates" could not touch a template. BindAccessPreflight already enforces
// the specific permission on every write.
func init() {
	migrations.Register(func(app core.App) error {
		if err := applyFrozenRules(app, frozenRules045); err != nil {
			return err
		}
		for collName, rule := range frozenReadRules045 {
			coll, err := app.FindCollectionByNameOrId(collName)
			if err != nil {
				return err
			}
			coll.ListRule = types.Pointer(rule)
			coll.ViewRule = types.Pointer(rule)
			if err := app.Save(coll); err != nil {
				return err
			}
		}
		return nil
	}, func(app core.App) error {
		return applyFrozenRules(app, frozenRules042)
	})
}

var frozenRules045 = map[string]map[string]string{
	"apiKeys": {
		"create": "(@request.auth.collectionName = 'users' && user = @request.auth.id && workspace = @request.auth.activeWorkspace && @request.auth.activeRole = 'admin')",
		"delete": "@request.auth.collectionName = 'users' && user = @request.auth.id",
	},
	"identities": {
		"create": "(@request.auth.collectionName = 'users' && workspace = @request.auth.activeWorkspace && @collection.workspaceMembers.workspace ?= workspace && @collection.workspaceMembers.user ?= @request.auth.id) || (@request.auth.collectionName = 'apiKeys' && workspace = @request.auth.workspace.id && @request.auth.scopes ~ '\"identity:create\"')",
		"delete": "(@request.auth.collectionName = 'users' && workspace = @request.auth.activeWorkspace && @collection.workspaceMembers.workspace ?= workspace && @collection.workspaceMembers.user ?= @request.auth.id) || (@request.auth.collectionName = 'apiKeys' && workspace = @request.auth.workspace.id && @request.auth.scopes ~ '\"identity:delete\"')",
		"update": "(@request.auth.collectionName = 'users' && workspace = @request.auth.activeWorkspace && @collection.workspaceMembers.workspace ?= workspace && @collection.workspaceMembers.user ?= @request.auth.id) || (@request.auth.collectionName = 'apiKeys' && workspace = @request.auth.workspace.id && @request.auth.scopes ~ '\"identity:update\"')",
	},
	"invites": {
		"create": "(@request.auth.collectionName = 'users' && @collection.workspaceMembers.workspace ?= workspace && @collection.workspaceMembers.user ?= @request.auth.id) || (@request.auth.collectionName = 'apiKeys' && workspace = @request.auth.workspace.id && @request.auth.scopes ~ '\"workspaceMembers:create\"')",
		"delete": "(@request.auth.collectionName = 'users' && @collection.workspaceMembers.workspace ?= workspace && @collection.workspaceMembers.user ?= @request.auth.id) || (@request.auth.collectionName = 'apiKeys' && workspace = @request.auth.workspace.id && @request.auth.scopes ~ '\"workspaceMembers:create\"')",
		"update": "(@request.auth.collectionName = 'users' && @collection.workspaceMembers.workspace ?= workspace && @collection.workspaceMembers.user ?= @request.auth.id) || (@request.auth.collectionName = 'apiKeys' && workspace = @request.auth.workspace.id && @request.auth.scopes ~ '\"workspaceMembers:create\"')",
	},
	"links": {
		"create": "(@request.auth.collectionName = 'users' && workspace = @request.auth.activeWorkspace && @collection.workspaceMembers.workspace ?= workspace && @collection.workspaceMembers.user ?= @request.auth.id) || (@request.auth.collectionName = 'apiKeys' && workspace = @request.auth.workspace.id && @request.auth.scopes ~ '\"link:create\"')",
		"delete": "(@request.auth.collectionName = 'users' && workspace = @request.auth.activeWorkspace && @collection.workspaceMembers.workspace ?= workspace && @collection.workspaceMembers.user ?= @request.auth.id) || (@request.auth.collectionName = 'apiKeys' && workspace = @request.auth.workspace.id && @request.auth.scopes ~ '\"link:delete\"')",
		"update": "(@request.auth.collectionName = 'users' && workspace = @request.auth.activeWorkspace && @collection.workspaceMembers.workspace ?= workspace && @collection.workspaceMembers.user ?= @request.auth.id) || (@request.auth.collectionName = 'apiKeys' && workspace = @request.auth.workspace.id && @request.auth.scopes ~ '\"link:update\"')",
	},
	"notifications": {
		"delete": "(@request.auth.collectionName = 'users' && workspace = @request.auth.activeWorkspace && @collection.workspaceMembers.workspace ?= workspace && @collection.workspaceMembers.user ?= @request.auth.id) || (@request.auth.collectionName = 'apiKeys' && workspace = @request.auth.workspace.id && @request.auth.scopes ~ '\"notification:delete\"')",
		"update": "(@request.auth.collectionName = 'users' && workspace = @request.auth.activeWorkspace && @collection.workspaceMembers.workspace ?= workspace && @collection.workspaceMembers.user ?= @request.auth.id) || (@request.auth.collectionName = 'apiKeys' && workspace = @request.auth.workspace.id && @request.auth.scopes ~ '\"notification:update\"')",
	},
	"records": {
		"create": "(@request.auth.collectionName = 'users' && workspace = @request.auth.activeWorkspace && @collection.workspaceMembers.workspace ?= workspace && @collection.workspaceMembers.user ?= @request.auth.id) || (@request.auth.collectionName = 'apiKeys' && workspace = @request.auth.workspace.id && @request.auth.scopes ~ '\"record:create\"')",
		"delete": "(@request.auth.collectionName = 'users' && workspace = @request.auth.activeWorkspace && @collection.workspaceMembers.workspace ?= workspace && @collection.workspaceMembers.user ?= @request.auth.id) || (@request.auth.collectionName = 'apiKeys' && workspace = @request.auth.workspace.id && ((@request.auth.scopes ~ '\"record:delete\"' && requestedBy = '') || (@request.auth.scopes ~ '\"response:delete\"' && requestedBy != '')))",
		"update": "(@request.auth.collectionName = 'users' && workspace = @request.auth.activeWorkspace && @collection.workspaceMembers.workspace ?= workspace && @collection.workspaceMembers.user ?= @request.auth.id) || (@request.auth.collectionName = 'apiKeys' && workspace = @request.auth.workspace.id && ((@request.auth.scopes ~ '\"record:update\"' && requestedBy = '') || (@request.auth.scopes ~ '\"response:update\"' && requestedBy != '')))",
	},
	"requests": {
		"create": "(@request.auth.collectionName = 'users' && workspace = @request.auth.activeWorkspace && @collection.workspaceMembers.workspace ?= workspace && @collection.workspaceMembers.user ?= @request.auth.id) || (@request.auth.collectionName = 'apiKeys' && workspace = @request.auth.workspace.id && @request.auth.scopes ~ '\"request:create\"')",
		"delete": "(@request.auth.collectionName = 'users' && workspace = @request.auth.activeWorkspace && @collection.workspaceMembers.workspace ?= workspace && @collection.workspaceMembers.user ?= @request.auth.id) || (@request.auth.collectionName = 'apiKeys' && workspace = @request.auth.workspace.id && @request.auth.scopes ~ '\"request:delete\"')",
		"update": "(@request.auth.collectionName = 'users' && workspace = @request.auth.activeWorkspace && @collection.workspaceMembers.workspace ?= workspace && @collection.workspaceMembers.user ?= @request.auth.id) || (@request.auth.collectionName = 'apiKeys' && workspace = @request.auth.workspace.id && @request.auth.scopes ~ '\"request:update\"')",
	},
	"sections": {
		"create": "(@request.auth.collectionName = 'users' && workspace = @request.auth.activeWorkspace && @collection.workspaceMembers.workspace ?= workspace && @collection.workspaceMembers.user ?= @request.auth.id) || (@request.auth.collectionName = 'apiKeys' && workspace = @request.auth.workspace.id && @request.auth.scopes ~ '\"section:create\"')",
		"delete": "(@request.auth.collectionName = 'users' && workspace = @request.auth.activeWorkspace && @collection.workspaceMembers.workspace ?= workspace && @collection.workspaceMembers.user ?= @request.auth.id) || (@request.auth.collectionName = 'apiKeys' && workspace = @request.auth.workspace.id && ((@request.auth.scopes ~ '\"section:delete\"' && requestedBy = '') || (@request.auth.scopes ~ '\"response:delete\"' && requestedBy != '')))",
		"update": "(@request.auth.collectionName = 'users' && workspace = @request.auth.activeWorkspace && @collection.workspaceMembers.workspace ?= workspace && @collection.workspaceMembers.user ?= @request.auth.id) || (@request.auth.collectionName = 'apiKeys' && workspace = @request.auth.workspace.id && ((@request.auth.scopes ~ '\"section:update\"' && requestedBy = '') || (@request.auth.scopes ~ '\"response:update\"' && requestedBy != '')))",
	},
	"templates": {
		"create": "(@request.auth.collectionName = 'users' && @collection.workspaceMembers.workspace ?= workspace && @collection.workspaceMembers.user ?= @request.auth.id) || (@request.auth.collectionName = 'apiKeys' && workspace = @request.auth.workspace.id && @request.auth.scopes ~ '\"template:create\"')",
		"delete": "(@request.auth.collectionName = 'users' && @collection.workspaceMembers.workspace ?= workspace && @collection.workspaceMembers.user ?= @request.auth.id) || (@request.auth.collectionName = 'apiKeys' && workspace = @request.auth.workspace.id && @request.auth.scopes ~ '\"template:delete\"')",
		"update": "(@request.auth.collectionName = 'users' && @collection.workspaceMembers.workspace ?= workspace && @collection.workspaceMembers.user ?= @request.auth.id) || (@request.auth.collectionName = 'apiKeys' && workspace = @request.auth.workspace.id && @request.auth.scopes ~ '\"template:update\"')",
	},
	"workspaceMembers": {
		"create": "(@request.auth.collectionName = 'users' && @collection.workspaceMembers.workspace ?= @request.body.workspace && @collection.workspaceMembers.user ?= @request.auth.id) || (@request.auth.collectionName = 'apiKeys' && @request.body.workspace = @request.auth.workspace.id && @request.auth.scopes ~ '\"workspaceMembers:create\"')",
		"delete": "(@request.auth.collectionName = 'users' && @collection.workspaceMembers.workspace ?= workspace && @collection.workspaceMembers.user ?= @request.auth.id) || (@request.auth.collectionName = 'apiKeys' && workspace = @request.auth.workspace.id && @request.auth.scopes ~ '\"workspaceMembers:delete\"')",
		"update": "(@request.auth.collectionName = 'users' && @collection.workspaceMembers.workspace ?= workspace && @collection.workspaceMembers.user ?= @request.auth.id) || (@request.auth.collectionName = 'apiKeys' && workspace = @request.auth.workspace.id && @request.auth.scopes ~ '\"workspaceMembers:update\"')",
	},
	"workspaces": {
		"delete": "(@request.auth.collectionName = 'users' && @collection.workspaceMembers.workspace ?= id && @collection.workspaceMembers.user ?= @request.auth.id) || (@request.auth.collectionName = 'apiKeys' && id = @request.auth.workspace.id && @request.auth.scopes ~ '\"workspaces:delete\"')",
		"update": "(@request.auth.collectionName = 'users' && @collection.workspaceMembers.workspace ?= id && @collection.workspaceMembers.user ?= @request.auth.id) || (@request.auth.collectionName = 'apiKeys' && id = @request.auth.workspace.id && @request.auth.scopes ~ '\"workspaces:update\"')",
	},
}

// List/view rules are not in the access registry, so they are frozen here too.
var frozenReadRules045 = map[string]string{
	"workspaces":       "(@request.auth.collectionName = 'users' && @collection.workspaceMembers.workspace ?= id && @collection.workspaceMembers.user ?= @request.auth.id) || (@request.auth.collectionName = 'apiKeys' && id = @request.auth.workspace.id && @request.auth.scopes ~ '\"workspaces:read\"')",
	"workspaceMembers": "user = @request.auth.id || (@request.auth.collectionName = 'users' && @collection.workspaceMembers.workspace ?= workspace && @collection.workspaceMembers.user ?= @request.auth.id) || (@request.auth.collectionName = 'apiKeys' && workspace = @request.auth.workspace.id && @request.auth.scopes ~ '\"workspaceMembers:read\"')",
	"invites":          "(@request.auth.collectionName = 'users' && @collection.workspaceMembers.workspace ?= workspace && @collection.workspaceMembers.user ?= @request.auth.id) || (@request.auth.collectionName = 'apiKeys' && workspace = @request.auth.workspace.id && @request.auth.scopes ~ '\"workspaceMembers:read\"')",
}
