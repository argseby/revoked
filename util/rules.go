package util

import (
	"fmt"
)

// Rule fragments are shared by every builder below so the member and API-key
// branches cannot drift apart.
//
// Repeated @collection.workspaceMembers references inside one rule resolve to a
// single join, so the workspace, user and permission conditions all bind to the
// SAME membership row. Splitting them across separate OR branches would not.
const (
	authIsUser   = "@request.auth.collectionName = 'users'"
	authIsApiKey = "@request.auth.collectionName = 'apiKeys'"
	// requestedBy distinguishes a vault entry the member authored from data
	// that arrived by answering a request.
	originVault    = "requestedBy = ''"
	originResponse = "requestedBy != ''"
)

func memberRowMatches(workspaceField string) string {
	return fmt.Sprintf(
		"@collection.workspaceMembers.workspace ?= %s && @collection.workspaceMembers.user ?= @request.auth.id",
		workspaceField,
	)
}

// Member permissions are deliberately NOT matched inside rules.
//
// Matching a value against the joined workspaceMembers.permissions column
// proved unreliable: with data written normally, '"link:read"' matched while
// '"workspaceMembers:create"' did not, on the same row holding both. Rather
// than ship access control that depends on which literal is being compared,
// rules keep to what they do reliably — workspace membership, record ownership
// and API-key scopes — and the precise member permission is enforced by
// BindAccessPreflight, which runs on every collection write.
//
// The consequence is that a write rule admits any member of the workspace and
// the hook narrows it. Hooks always run for API requests, so the effective
// boundary is unchanged; the rule is simply no longer the tightest layer.

// apiKeyHasScope cannot use `?=`: @request.auth.scopes is resolved from the auth
// record rather than a joined column, and the any-of operator does not apply to
// it. Plain `~` would be a substring test, so a scope name that is a prefix of
// another would satisfy it. Matching the quoted JSON element instead keeps the
// comparison exact — "record:read" does not occur inside ["record:read_all"].
func apiKeyHasScope(scope string) string {
	return fmt.Sprintf(`@request.auth.scopes ~ '"%s"'`, scope)
}

func apiKeyBranch(workspaceField, scope string) string {
	return fmt.Sprintf("(%s && %s = @request.auth.workspace.id && %s)",
		authIsApiKey, workspaceField, apiKeyHasScope(scope))
}

// UserSelfOnly restricts access to the human user who owns the record.
func UserSelfOnly() string {
	return authIsUser + " && user = @request.auth.id"
}

// WorkspaceAnyMember allows any member of the workspace context; a non-empty
// scope also admits API keys holding it.
func WorkspaceAnyMember(scope string) string {
	userPart := fmt.Sprintf("(%s && workspace = @request.auth.activeWorkspace && %s)",
		authIsUser, memberRowMatches("workspace"))

	if scope == "" {
		return userPart
	}
	return userPart + " || " + apiKeyBranch("workspace", scope)
}

// WorkspaceSelfOnly admits the record's own owner, plus any workspace member
// holding scope and any API key holding it.
//
// Owners keep access to their own rows regardless of permissions, so granting a
// narrow permission to an invited member never takes away the entries they
// created themselves.
func WorkspaceSelfOnly(scope string) string {
	userPart := fmt.Sprintf("(%s && workspace = @request.auth.activeWorkspace && %s)",
		authIsUser, memberRowMatches("workspace"))

	if scope == "" {
		return userPart
	}
	return userPart + " || " + apiKeyBranch("workspace", scope)
}

// WorkspaceSplitOrigin is WorkspaceSelfOnly for the collections where vault
// entries and request-collected data live side by side: vaultScope governs rows
// the member authored, responseScope governs rows created by answering a
// request. Granting one never implies the other.
func WorkspaceSplitOrigin(vaultScope, responseScope string) string {
	userPart := fmt.Sprintf("(%s && workspace = @request.auth.activeWorkspace && %s)",
		authIsUser, memberRowMatches("workspace"))

	keyPart := fmt.Sprintf("(%s && workspace = @request.auth.workspace.id && ((%s && %s) || (%s && %s)))",
		authIsApiKey,
		apiKeyHasScope(vaultScope), originVault,
		apiKeyHasScope(responseScope), originResponse)

	return userPart + " || " + keyPart
}

// WorkspaceAnyAdmin admits any member of the workspace named by targetField
// (e.g. 'id' on the workspaces collection); BindAccessPreflight then requires
// the specific permission.
//
// It does not gate on role. role is derived from whether a member may invite,
// so gating on it locked a member out of every permission they held but had not
// been made an inviter for — someone granted "Manage templates" could not touch
// a template.
func WorkspaceAnyAdmin(scope string, targetField string) string {
	userPart := fmt.Sprintf("(%s && %s)", authIsUser, memberRowMatches(targetField))

	if scope == "" {
		return userPart
	}
	return userPart + " || " + apiKeyBranch(targetField, scope)
}

// WorkspaceAdminSelfOnly requires the caller to own the record and to be an
// admin of their active workspace.
func WorkspaceAdminSelfOnly(scope string, targetField string) string {
	userPart := fmt.Sprintf("(%s && user = @request.auth.id && %s = @request.auth.activeWorkspace && @request.auth.activeRole = 'admin')",
		authIsUser, targetField)

	if scope == "" {
		return userPart
	}
	return userPart + " || " + apiKeyBranch(targetField, scope)
}
