package util

// Granular permissions an API key may be granted, in "resource:action" form.
const (
	// record:* covers vault entries the member authored. Data that arrived by
	// answering a request is governed by response:* instead, so "browse the
	// vault" and "read what people submitted to me" can be granted separately.
	// The two are told apart by requestedBy being set.
	// ScopeRecordPublish makes vault entries and sections visible beyond
	// their owner (the workspace, its groups), and changes those that are
	// (VISIBILITY.md). Without it a member's vault stays their own.
	ScopeRecordPublish = "record:publish"
	ScopeRecordRead    = "record:read"
	ScopeRecordCreate  = "record:create"
	ScopeRecordUpdate  = "record:update"
	ScopeRecordDelete  = "record:delete"

	ScopeResponseRead   = "response:read"
	ScopeResponseUpdate = "response:update"
	ScopeResponseDelete = "response:delete"

	ScopeSectionRead   = "section:read"
	ScopeSectionCreate = "section:create"
	ScopeSectionUpdate = "section:update"
	ScopeSectionDelete = "section:delete"

	ScopeWorkspacesRead   = "workspaces:read"
	ScopeWorkspacesCreate = "workspaces:create"
	ScopeWorkspacesUpdate = "workspaces:update"
	ScopeWorkspacesDelete = "workspaces:delete"

	ScopeWorkspaceMembersRead   = "workspaceMembers:read"
	ScopeWorkspaceMembersCreate = "workspaceMembers:create"
	ScopeWorkspaceMembersUpdate = "workspaceMembers:update"
	ScopeWorkspaceMembersDelete = "workspaceMembers:delete"

	ScopeTemplateRead   = "template:read"
	ScopeTemplateCreate = "template:create"
	ScopeTemplateUpdate = "template:update"
	ScopeTemplateDelete = "template:delete"

	ScopeLinkRead   = "link:read"
	ScopeLinkCreate = "link:create"
	ScopeLinkUpdate = "link:update"
	ScopeLinkDelete = "link:delete"

	ScopeIdentityRead   = "identity:read"
	ScopeIdentityCreate = "identity:create"
	ScopeIdentityUpdate = "identity:update"
	ScopeIdentityDelete = "identity:delete"

	ScopeRequestRead   = "request:read"
	ScopeRequestCreate = "request:create"
	ScopeRequestUpdate = "request:update"
	ScopeRequestDelete = "request:delete"

	ScopeNotificationRead   = "notification:read"
	ScopeNotificationUpdate = "notification:update"
	ScopeNotificationDelete = "notification:delete"

	// attestation:* covers statements this workspace signs about other
	// people's identities, in the name of the server's domain.
	ScopeAttestationRead   = "attestation:read"
	ScopeAttestationCreate = "attestation:create"
	ScopeAttestationUpdate = "attestation:update"
	ScopeAttestationDelete = "attestation:delete"

	// contact:* covers the workspace's address book: who it sends to and asks
	// from. Reading one yields an address and, for a peer, its fingerprint.
	ScopeContactRead   = "contact:read"
	ScopeContactCreate = "contact:create"
	ScopeContactUpdate = "contact:update"
	ScopeContactDelete = "contact:delete"

	// webhook:manage covers the workspace's webhook endpoints and their
	// delivery log. An endpoint hears about activity across the workspace, so
	// it is one scope: reading the log is as revealing as subscribing.
	ScopeWebhookManage = "webhook:manage"
)

// AllScopes lists every defined API key scope.
var AllScopes = []string{
	ScopeRecordRead,
	ScopeRecordCreate,
	ScopeRecordUpdate,
	ScopeRecordDelete,
	ScopeResponseRead,
	ScopeResponseUpdate,
	ScopeResponseDelete,
	ScopeSectionRead,
	ScopeSectionCreate,
	ScopeSectionUpdate,
	ScopeSectionDelete,
	ScopeWorkspacesRead,
	ScopeWorkspacesCreate,
	ScopeWorkspacesUpdate,
	ScopeWorkspacesDelete,
	ScopeWorkspaceMembersRead,
	ScopeWorkspaceMembersCreate,
	ScopeWorkspaceMembersUpdate,
	ScopeWorkspaceMembersDelete,
	ScopeTemplateRead,
	ScopeTemplateCreate,
	ScopeTemplateUpdate,
	ScopeTemplateDelete,
	ScopeLinkRead,
	ScopeLinkCreate,
	ScopeLinkUpdate,
	ScopeLinkDelete,
	ScopeIdentityRead,
	ScopeIdentityCreate,
	ScopeIdentityUpdate,
	ScopeIdentityDelete,
	ScopeRequestRead,
	ScopeRequestCreate,
	ScopeRequestUpdate,
	ScopeRequestDelete,
	ScopeNotificationRead,
	ScopeNotificationUpdate,
	ScopeNotificationDelete,
	ScopeAttestationRead,
	ScopeAttestationCreate,
	ScopeAttestationUpdate,
	ScopeAttestationDelete,
	ScopeContactRead,
	ScopeContactCreate,
	ScopeContactUpdate,
	ScopeContactDelete,
	ScopeWebhookManage,
	ScopeRecordPublish,
}

// AttestationScopes are the scopes added with attestations, for the migration
// that hands them to the members who already administer a workspace.
var AttestationScopes = []string{
	ScopeAttestationRead,
	ScopeAttestationCreate,
	ScopeAttestationUpdate,
	ScopeAttestationDelete,
}
