package migrations

import (
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/migrations"
)

// Re-applies the collection rules after member permissions moved out of them.
//
// Matching a value against the joined workspaceMembers.permissions column did
// not evaluate reliably, so a write rule now admits any member of the workspace
// and BindAccessPreflight enforces the specific permission. The rules also gate
// administration on the role denormalization, which the workspaceMembers hooks
// keep in step with the permission set.
func init() {
	migrations.Register(func(app core.App) error {
		return applyFrozenRules(app, frozenRules042)
	}, func(app core.App) error {
		return applyFrozenRules(app, frozenRules040)
	})
}

var frozenRules042 = map[string]map[string]string{
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
		"create": "(@request.auth.collectionName = 'users' && @collection.workspaceMembers.workspace ?= workspace && @collection.workspaceMembers.user ?= @request.auth.id && @collection.workspaceMembers.role ?= 'admin') || (@request.auth.collectionName = 'apiKeys' && workspace = @request.auth.workspace.id && @request.auth.scopes ~ '\"workspaceMembers:create\"')",
		"delete": "(@request.auth.collectionName = 'users' && @collection.workspaceMembers.workspace ?= workspace && @collection.workspaceMembers.user ?= @request.auth.id && @collection.workspaceMembers.role ?= 'admin') || (@request.auth.collectionName = 'apiKeys' && workspace = @request.auth.workspace.id && @request.auth.scopes ~ '\"workspaceMembers:create\"')",
		"update": "(@request.auth.collectionName = 'users' && @collection.workspaceMembers.workspace ?= workspace && @collection.workspaceMembers.user ?= @request.auth.id && @collection.workspaceMembers.role ?= 'admin') || (@request.auth.collectionName = 'apiKeys' && workspace = @request.auth.workspace.id && @request.auth.scopes ~ '\"workspaceMembers:create\"')",
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
		"create": "(@request.auth.collectionName = 'users' && @collection.workspaceMembers.workspace ?= workspace && @collection.workspaceMembers.user ?= @request.auth.id && @collection.workspaceMembers.role ?= 'admin') || (@request.auth.collectionName = 'apiKeys' && workspace = @request.auth.workspace.id && @request.auth.scopes ~ '\"template:create\"')",
		"delete": "(@request.auth.collectionName = 'users' && @collection.workspaceMembers.workspace ?= workspace && @collection.workspaceMembers.user ?= @request.auth.id && @collection.workspaceMembers.role ?= 'admin') || (@request.auth.collectionName = 'apiKeys' && workspace = @request.auth.workspace.id && @request.auth.scopes ~ '\"template:delete\"')",
		"update": "(@request.auth.collectionName = 'users' && @collection.workspaceMembers.workspace ?= workspace && @collection.workspaceMembers.user ?= @request.auth.id && @collection.workspaceMembers.role ?= 'admin') || (@request.auth.collectionName = 'apiKeys' && workspace = @request.auth.workspace.id && @request.auth.scopes ~ '\"template:update\"')",
	},
	"workspaceMembers": {
		"create": "(@request.auth.collectionName = 'users' && @collection.workspaceMembers.workspace ?= @request.body.workspace && @collection.workspaceMembers.user ?= @request.auth.id && @collection.workspaceMembers.role ?= 'admin') || (@request.auth.collectionName = 'apiKeys' && @request.body.workspace = @request.auth.workspace.id && @request.auth.scopes ~ '\"workspaceMembers:create\"')",
		"delete": "(@request.auth.collectionName = 'users' && @collection.workspaceMembers.workspace ?= workspace && @collection.workspaceMembers.user ?= @request.auth.id && @collection.workspaceMembers.role ?= 'admin') || (@request.auth.collectionName = 'apiKeys' && workspace = @request.auth.workspace.id && @request.auth.scopes ~ '\"workspaceMembers:delete\"')",
		"update": "(@request.auth.collectionName = 'users' && @collection.workspaceMembers.workspace ?= workspace && @collection.workspaceMembers.user ?= @request.auth.id && @collection.workspaceMembers.role ?= 'admin') || (@request.auth.collectionName = 'apiKeys' && workspace = @request.auth.workspace.id && @request.auth.scopes ~ '\"workspaceMembers:update\"')",
	},
	"workspaces": {
		"delete": "(@request.auth.collectionName = 'users' && @collection.workspaceMembers.workspace ?= id && @collection.workspaceMembers.user ?= @request.auth.id && @collection.workspaceMembers.role ?= 'admin') || (@request.auth.collectionName = 'apiKeys' && id = @request.auth.workspace.id && @request.auth.scopes ~ '\"workspaces:delete\"')",
		"update": "((@request.auth.collectionName = 'users' && @collection.workspaceMembers.workspace ?= id && @collection.workspaceMembers.user ?= @request.auth.id && @collection.workspaceMembers.role ?= 'admin') || (@request.auth.collectionName = 'apiKeys' && id = @request.auth.workspace.id && @request.auth.scopes ~ '\"workspaces:update\"')) && @request.body.type:isset = false",
	},
}
