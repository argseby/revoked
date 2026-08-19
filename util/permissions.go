package util

import "slices"

// Permission is a grant as a person picks it, naming a product surface rather
// than a collection. Grants are expanded into Scopes when issued, so redefining
// a permission later never silently widens an existing grant.
type Permission struct {
	Key         string
	Label       string
	Description string
	// Destructive marks a permission that can escalate or lock others out.
	Destructive bool
	Scopes      []string
}

// Permission keys.
const (
	PermVaultRead        = "vault:read"
	PermVaultWrite       = "vault:write"
	PermResponsesRead    = "responses:read"
	PermResponsesManage  = "responses:manage"
	PermSharesRead       = "shares:read"
	PermSharesManage     = "shares:manage"
	PermRequestsRead     = "requests:read"
	PermRequestsManage   = "requests:manage"
	PermTemplatesRead    = "templates:read"
	PermTemplatesManage  = "templates:manage"
	PermIdentitiesRead   = "identities:read"
	PermIdentitiesManage = "identities:manage"
	PermMembersRead      = "members:read"
	PermMembersAdd       = "members:add"
	PermMembersRemove    = "members:remove"
	PermSettingsManage   = "settings:manage"
)

// Permissions is the catalogue offered when granting access, in display order.
var Permissions = []Permission{
	{
		Key: PermVaultRead, Label: "Read vault",
		Description: "View the entries and sections in this workspace's vault.",
		Scopes:      []string{ScopeRecordRead, ScopeSectionRead},
	},
	{
		Key: PermVaultWrite, Label: "Manage vault",
		Description: "Create, edit and delete vault entries and sections.",
		Scopes: []string{
			ScopeRecordCreate, ScopeRecordUpdate, ScopeRecordDelete,
			ScopeSectionCreate, ScopeSectionUpdate, ScopeSectionDelete,
		},
	},
	{
		Key: PermResponsesRead, Label: "Read collected data",
		Description: "View data other people submitted through requests.",
		Scopes:      []string{ScopeResponseRead},
	},
	{
		Key: PermResponsesManage, Label: "Manage collected data",
		Description: "Edit or delete data collected through requests.",
		Scopes:      []string{ScopeResponseUpdate, ScopeResponseDelete},
	},
	{
		Key: PermSharesRead, Label: "View shares",
		Description: "See the shares this workspace has issued.",
		Scopes:      []string{ScopeLinkRead},
	},
	{
		Key: PermSharesManage, Label: "Manage shares",
		Description: "Create shares, and pause, revoke or delete them.",
		Scopes:      []string{ScopeLinkCreate, ScopeLinkUpdate, ScopeLinkDelete},
	},
	{
		Key: PermRequestsRead, Label: "View requests",
		Description: "See the data requests this workspace has issued.",
		Scopes:      []string{ScopeRequestRead},
	},
	{
		Key: PermRequestsManage, Label: "Manage requests",
		Description: "Create data requests, and pause, revoke or delete them.",
		Scopes:      []string{ScopeRequestCreate, ScopeRequestUpdate, ScopeRequestDelete},
	},
	{
		Key: PermTemplatesRead, Label: "View templates",
		Description: "See the request templates in this workspace.",
		Scopes:      []string{ScopeTemplateRead},
	},
	{
		Key: PermTemplatesManage, Label: "Manage templates",
		Description: "Create, edit and delete request templates.",
		Scopes:      []string{ScopeTemplateCreate, ScopeTemplateUpdate, ScopeTemplateDelete},
	},
	{
		Key: PermIdentitiesRead, Label: "View identities",
		Description: "See the signing identities this workspace uses.",
		Scopes:      []string{ScopeIdentityRead},
	},
	{
		Key: PermIdentitiesManage, Label: "Manage identities",
		Description: "Create and remove signing identities. Identities are what recipients verify a share or request against.",
		Destructive: true,
		Scopes:      []string{ScopeIdentityCreate, ScopeIdentityUpdate, ScopeIdentityDelete},
	},
	{
		Key: PermMembersRead, Label: "View members",
		Description: "See who has access to this workspace.",
		Scopes:      []string{ScopeWorkspaceMembersRead},
	},
	{
		Key: PermMembersAdd, Label: "Invite members",
		Description: "Invite people into this workspace and choose what they may do. Anyone with this can extend access to others.",
		Destructive: true,
		Scopes:      []string{ScopeWorkspaceMembersCreate, ScopeWorkspaceMembersRead},
	},
	{
		Key: PermMembersRemove, Label: "Remove members",
		Description: "Change what members may do, and remove them from the workspace.",
		Destructive: true,
		Scopes:      []string{ScopeWorkspaceMembersUpdate, ScopeWorkspaceMembersDelete, ScopeWorkspaceMembersRead},
	},
	{
		Key: PermSettingsManage, Label: "Manage workspace",
		Description: "Rename the workspace, change its settings, and delete it.",
		Destructive: true,
		Scopes:      []string{ScopeWorkspacesUpdate, ScopeWorkspacesRead, ScopeWorkspacesDelete},
	},
}

// AdminPermissions are the grants that extend or revoke other people's access;
// a workspace must always retain a member holding both.
var AdminPermissions = []string{PermMembersAdd, PermMembersRemove}

// AllPermissionKeys lists every permission key in catalogue order.
func AllPermissionKeys() []string {
	keys := make([]string, 0, len(Permissions))
	for _, p := range Permissions {
		keys = append(keys, p.Key)
	}
	return keys
}

// PermissionByKey returns the catalogue entry for a permission key.
func PermissionByKey(key string) (Permission, bool) {
	for _, p := range Permissions {
		if p.Key == key {
			return p, true
		}
	}
	return Permission{}, false
}

// ExpandPermissions turns permission keys into the stored scope set; unknown
// keys are reported, not dropped, so a typo cannot quietly weaken a grant.
func ExpandPermissions(keys []string) (scopes []string, unknown []string) {
	seen := map[string]bool{}
	for _, key := range keys {
		perm, ok := PermissionByKey(key)
		if !ok {
			unknown = append(unknown, key)
			continue
		}
		for _, s := range perm.Scopes {
			if !seen[s] {
				seen[s] = true
				scopes = append(scopes, s)
			}
		}
	}
	slices.Sort(scopes)
	return scopes, unknown
}

// SurfacesFor reports which permissions a stored scope set satisfies: the
// inverse of [ExpandPermissions].
func SurfacesFor(scopes []string) []string {
	granted := []string{}
	for _, p := range Permissions {
		if len(p.Scopes) == 0 {
			continue
		}
		complete := true
		for _, s := range p.Scopes {
			if !slices.Contains(scopes, s) {
				complete = false
				break
			}
		}
		if complete {
			granted = append(granted, p.Key)
		}
	}
	return granted
}

// IsAdminScopeSet reports whether a scope set can extend or revoke other
// people's access to the workspace.
func IsAdminScopeSet(scopes []string) bool {
	for _, key := range AdminPermissions {
		perm, ok := PermissionByKey(key)
		if !ok {
			return false
		}
		for _, s := range perm.Scopes {
			if !slices.Contains(scopes, s) {
				return false
			}
		}
	}
	return true
}

// KnownScopes filters values down to real scopes, so callers may pass raw
// scopes instead of permission keys.
func KnownScopes(values []string) []string {
	out := []string{}
	for _, v := range values {
		if slices.Contains(AllScopes, v) {
			out = append(out, v)
		}
	}
	return out
}

// UnknownScopes returns the values that are neither a permission key nor a scope.
func UnknownScopes(values []string) []string {
	out := []string{}
	for _, v := range values {
		if _, isPerm := PermissionByKey(v); isPerm {
			continue
		}
		if slices.Contains(AllScopes, v) {
			continue
		}
		out = append(out, v)
	}
	return out
}

// MissingScopes returns the scopes in want that granter does not hold — a
// grant may never exceed the granter's own access.
func MissingScopes(granter, want []string) []string {
	missing := []string{}
	for _, s := range want {
		if !slices.Contains(granter, s) {
			missing = append(missing, s)
		}
	}
	return missing
}
