package util

// Write actions a collection rule can govern.
const (
	ActionCreate = "create"
	ActionUpdate = "update"
	ActionDelete = "delete"
)

// WorkspaceTypeImmutable forbids changing workspaces.type after creation; the
// workspace and member caps it drives are only checked on create.
const WorkspaceTypeImmutable = "@request.body.type:isset = false"

// CollectionAccess declares the authorization requirement for every write
// action the API exposes, keyed by collection and action.
//
// Entries must stay in step with the rules the migrations installed —
// TestAccessRegistryMatchesRules asserts each entry's Rule() is byte-identical
// to the deployed rule, so drift fails the build. Superuser-only collections are
// deliberately absent: PocketBase rejects those before anything here is read.
var CollectionAccess = map[string]map[string]AccessSpec{
	// Create always writes a vault entry: request-collected rows are minted
	// server-side, never through the collection API.
	Coll.Records: {
		ActionCreate: {Kind: AccessWorkspaceSelf, Scope: ScopeRecordCreate},
		ActionUpdate: {Kind: AccessWorkspaceSplitOrigin, Scope: ScopeRecordUpdate, ResponseScope: ScopeResponseUpdate},
		ActionDelete: {Kind: AccessWorkspaceSplitOrigin, Scope: ScopeRecordDelete, ResponseScope: ScopeResponseDelete},
	},
	Coll.Sections: {
		ActionCreate: {Kind: AccessWorkspaceSelf, Scope: ScopeSectionCreate},
		ActionUpdate: {Kind: AccessWorkspaceSplitOrigin, Scope: ScopeSectionUpdate, ResponseScope: ScopeResponseUpdate},
		ActionDelete: {Kind: AccessWorkspaceSplitOrigin, Scope: ScopeSectionDelete, ResponseScope: ScopeResponseDelete},
	},
	Coll.Links: {
		ActionCreate: {Kind: AccessWorkspaceSelf, Scope: ScopeLinkCreate},
		ActionUpdate: {Kind: AccessWorkspaceSelf, Scope: ScopeLinkUpdate},
		ActionDelete: {Kind: AccessWorkspaceSelf, Scope: ScopeLinkDelete},
	},
	Coll.Requests: {
		ActionCreate: {Kind: AccessWorkspaceSelf, Scope: ScopeRequestCreate},
		ActionUpdate: {Kind: AccessWorkspaceSelf, Scope: ScopeRequestUpdate},
		ActionDelete: {Kind: AccessWorkspaceSelf, Scope: ScopeRequestDelete},
	},
	Coll.Identities: {
		ActionCreate: {Kind: AccessWorkspaceSelf, Scope: ScopeIdentityCreate},
		ActionUpdate: {Kind: AccessWorkspaceSelf, Scope: ScopeIdentityUpdate},
		ActionDelete: {Kind: AccessWorkspaceSelf, Scope: ScopeIdentityDelete},
	},
	Coll.Notifications: {
		ActionUpdate: {Kind: AccessWorkspaceSelf, Scope: ScopeNotificationUpdate},
		ActionDelete: {Kind: AccessWorkspaceSelf, Scope: ScopeNotificationDelete},
	},
	Coll.Templates: {
		ActionCreate: {Kind: AccessWorkspaceAdmin, Scope: ScopeTemplateCreate},
		ActionUpdate: {Kind: AccessWorkspaceAdmin, Scope: ScopeTemplateUpdate},
		ActionDelete: {Kind: AccessWorkspaceAdmin, Scope: ScopeTemplateDelete},
	},
	Coll.Workspaces: {
		ActionUpdate: {Kind: AccessWorkspaceAdmin, Scope: ScopeWorkspacesUpdate, WorkspaceField: "id"},
		ActionDelete: {Kind: AccessWorkspaceAdmin, Scope: ScopeWorkspacesDelete, WorkspaceField: "id"},
	},
	Coll.WorkspaceMembers: {
		ActionCreate: {Kind: AccessWorkspaceAdmin, Scope: ScopeWorkspaceMembersCreate, WorkspaceField: "@request.body.workspace"},
		ActionUpdate: {Kind: AccessWorkspaceAdmin, Scope: ScopeWorkspaceMembersUpdate},
		ActionDelete: {Kind: AccessWorkspaceAdmin, Scope: ScopeWorkspaceMembersDelete},
	},
	Coll.Invites: {
		ActionCreate: {Kind: AccessWorkspaceAdmin, Scope: ScopeWorkspaceMembersCreate},
		ActionUpdate: {Kind: AccessWorkspaceAdmin, Scope: ScopeWorkspaceMembersCreate},
		ActionDelete: {Kind: AccessWorkspaceAdmin, Scope: ScopeWorkspaceMembersCreate},
	},
	Coll.ApiKeys: {
		ActionCreate: {Kind: AccessWorkspaceAdminSelf},
		ActionDelete: {Kind: AccessUserSelf},
	},
}

// AccessSpecFor returns the requirement for a collection action, if declared.
func AccessSpecFor(collection, action string) (AccessSpec, bool) {
	actions, ok := CollectionAccess[collection]
	if !ok {
		return AccessSpec{}, false
	}
	spec, ok := actions[action]
	return spec, ok
}
