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

// OwnerImmutable forbids handing a row to another user on update: the rule
// checks the stored owner, not the one the body asks for.
const OwnerImmutable = "@request.body.user:isset = false"

// CollectionAccess declares the authorization requirement for every write
// action the API exposes, keyed by collection and action.
//
// Entries must stay in step with the rules the migrations installed —
// TestAccessRegistryMatchesRules asserts each entry's Rule() is byte-identical
// to the deployed rule, so drift fails the build. Superuser-only collections are
// deliberately absent: PocketBase rejects those before anything here is read.
var CollectionAccess = map[string]map[string]AccessSpec{
	// Create always writes a vault entry: request-collected rows are minted
	// server-side, never through the collection API. Update and delete admit
	// the owner and the members listed in editors (VISIBILITY.md).
	Coll.Records: {
		ActionCreate: {Kind: AccessWorkspaceSelf, Scope: ScopeRecordCreate},
		ActionUpdate: {Kind: AccessWorkspaceAudience, Scope: ScopeRecordUpdate, ResponseScope: ScopeResponseUpdate},
		ActionDelete: {Kind: AccessWorkspaceAudience, Scope: ScopeRecordDelete, ResponseScope: ScopeResponseDelete},
	},
	Coll.Sections: {
		ActionCreate: {Kind: AccessWorkspaceSelf, Scope: ScopeSectionCreate},
		ActionUpdate: {Kind: AccessWorkspaceAudience, Scope: ScopeSectionUpdate, ResponseScope: ScopeResponseUpdate},
		ActionDelete: {Kind: AccessWorkspaceAudience, Scope: ScopeSectionDelete, ResponseScope: ScopeResponseDelete},
	},
	// Shares and requests carry an audience (VISIBILITY.md, phase 2): update
	// and delete admit the owner and the members listed in editors.
	Coll.Links: {
		ActionCreate: {Kind: AccessWorkspaceSelf, Scope: ScopeLinkCreate},
		ActionUpdate: {Kind: AccessWorkspaceAudienceSelf, Scope: ScopeLinkUpdate},
		ActionDelete: {Kind: AccessWorkspaceAudienceSelf, Scope: ScopeLinkDelete},
	},
	Coll.Requests: {
		ActionCreate: {Kind: AccessWorkspaceSelf, Scope: ScopeRequestCreate},
		ActionUpdate: {Kind: AccessWorkspaceAudienceSelf, Scope: ScopeRequestUpdate},
		ActionDelete: {Kind: AccessWorkspaceAudienceSelf, Scope: ScopeRequestDelete},
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
		ActionUpdate: {Kind: AccessWorkspaceAudienceSelf, Scope: ScopeTemplateUpdate},
		ActionDelete: {Kind: AccessWorkspaceAudienceSelf, Scope: ScopeTemplateDelete},
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
	// Personal, not workspace data: a bookmark holds a capability someone
	// handed to this person, and a co-member or an API key reading it would
	// widen that grant past whoever it was given to.
	Coll.Bookmarks: {
		ActionCreate: {Kind: AccessUserSelf},
		ActionUpdate: {Kind: AccessUserSelf, Extra: OwnerImmutable},
		ActionDelete: {Kind: AccessUserSelf},
	},
	Coll.BookmarkGroups: {
		ActionCreate: {Kind: AccessUserSelf},
		ActionUpdate: {Kind: AccessUserSelf, Extra: OwnerImmutable},
		ActionDelete: {Kind: AccessUserSelf},
	},
	// Personal: a reminder is one person's note to self about an entry, and
	// its notification goes to them alone. The hooks bind it to the entry's
	// workspace and require membership there.
	Coll.Reminders: {
		ActionCreate: {Kind: AccessUserSelf},
		ActionUpdate: {Kind: AccessUserSelf, Extra: OwnerImmutable},
		ActionDelete: {Kind: AccessUserSelf},
	},
	// Governed by the permission alone, like templates: owning the row is not
	// enough, because an attestation speaks for the domain and a member whose
	// permission was withdrawn must not keep issuing through rows they made.
	Coll.Attestations: {
		ActionCreate: {Kind: AccessWorkspaceAdmin, Scope: ScopeAttestationCreate},
		ActionUpdate: {Kind: AccessWorkspaceAudienceAdmin, Scope: ScopeAttestationUpdate},
		ActionDelete: {Kind: AccessWorkspaceAudienceAdmin, Scope: ScopeAttestationDelete},
	},
	// Personal, like the vault: a credential carries everything it states
	// about its holder. It is written by the claim route alone; its owner may
	// read and remove it, and no API key reaches it.
	Coll.Credentials: {
		ActionDelete: {Kind: AccessUserSelf},
	},
	// Personal: what someone chose to show the asker. Written by the check
	// routes alone; its owner may read and remove it.
	Coll.AttestationChecks: {
		ActionDelete: {Kind: AccessUserSelf},
	},
	// Workspace data, like shares: a contact is what the workspace sends to,
	// so it follows the workspace rather than whoever typed it in. Whether a
	// contact is proven is not the client's to say — the hooks hold
	// trustState, verifiedAt and peerFingerprint, so a member cannot dress an
	// address up as a verified peer for a co-member to send the vault to.
	Coll.Contacts: {
		ActionCreate: {Kind: AccessWorkspaceSelf, Scope: ScopeContactCreate},
		ActionUpdate: {Kind: AccessWorkspaceAudienceSelf, Scope: ScopeContactUpdate, OwnerField: Fields.Contact.CreatedBy},
		ActionDelete: {Kind: AccessWorkspaceAudienceSelf, Scope: ScopeContactDelete, OwnerField: Fields.Contact.CreatedBy},
	},
	// Personal, like bookmarks: who a person refuses deliveries from is
	// theirs, not their workspace's, and no API key speaks for it. A block is
	// added or removed and never edited, so no update is declared.
	Coll.ContactBlocks: {
		ActionCreate: {Kind: AccessUserSelf},
		ActionDelete: {Kind: AccessUserSelf},
	},
}

// AudienceReadRules are the list/view rules of the collections with an
// audience. They are not part of the write registry above; the registry test
// checks them against the deployed rules all the same.
var AudienceReadRules = map[string]string{
	Coll.Records:  WorkspaceAudienceRead(ScopeRecordRead),
	Coll.Sections: WorkspaceAudienceRead(ScopeSectionRead),
	Coll.Links:    WorkspaceAudienceRead(ScopeLinkRead),
	Coll.Requests: WorkspaceAudienceRead(ScopeRequestRead),
	// Built-in templates (no workspace) stay readable by anyone signed in.
	Coll.Templates:    WorkspaceAudienceRead(ScopeTemplateRead) + " || (@request.auth.id != '' && workspace = '')",
	Coll.Contacts:     WorkspaceAudienceReadBy(Fields.Contact.CreatedBy, ScopeContactRead),
	Coll.Attestations: WorkspaceAudienceRead(ScopeAttestationRead),
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
