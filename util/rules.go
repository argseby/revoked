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

// apiKeyAudienceBranch admits an API key holding scope only to rows whose
// readers (or editors) list the member who made the key: a key acts as its
// creator, narrowed by its scopes, and never sees more than they do
// (VISIBILITY.md, phase 4). It loses that access with them.
func apiKeyAudienceBranch(scope, column string) string {
	return fmt.Sprintf("(%s && workspace = @request.auth.workspace.id && %s && %s.id ?= @request.auth.user)",
		authIsApiKey, apiKeyHasScope(scope), column)
}

// audienceUserPart admits a member of the active workspace who owns the row or
// is listed in its server-maintained audience column (readers or editors).
//
// The column holds the outcome of services.Access, permissions included, so
// the rule never has to evaluate a permission itself (see above). It is
// matched through the relation (`readers.id ?=`): the bare `readers ?=` form
// compares against the stored JSON text and never matches.
func audienceUserPart(column string) string {
	return audienceUserPartBy("user", column)
}

// audienceUserPartBy is audienceUserPart for a collection whose owner is held
// in ownerField rather than user (contacts: createdBy).
func audienceUserPartBy(ownerField, column string) string {
	return fmt.Sprintf("(%s && workspace = @request.auth.activeWorkspace && %s && (%s = @request.auth.id || %s.id ?= @request.auth.id))",
		authIsUser, memberRowMatches("workspace"), ownerField, column)
}

// WorkspaceAudienceRead is the list/view rule for collections with an
// audience: the owner, or a member listed in readers. A non-empty scope also
// admits API keys holding it, as before audiences existed.
func WorkspaceAudienceRead(scope string) string {
	return WorkspaceAudienceReadBy("user", scope)
}

// WorkspaceAudienceReadBy is WorkspaceAudienceRead for a collection whose
// owner is held in ownerField.
func WorkspaceAudienceReadBy(ownerField, scope string) string {
	userPart := audienceUserPartBy(ownerField, "readers")
	if scope == "" {
		return userPart
	}
	return userPart + " || " + apiKeyAudienceBranch(scope, "readers")
}

// WorkspaceAudienceSplit is WorkspaceSplitOrigin narrowed to the owner and the
// members listed in editors, so a member can never change a row they can't
// see. The API-key branch is unchanged.
func WorkspaceAudienceSplit(vaultScope, responseScope string) string {
	keyPart := fmt.Sprintf("(%s && workspace = @request.auth.workspace.id && ((%s && %s) || (%s && %s)) && editors.id ?= @request.auth.user)",
		authIsApiKey,
		apiKeyHasScope(vaultScope), originVault,
		apiKeyHasScope(responseScope), originResponse)

	return audienceUserPart("editors") + " || " + keyPart
}

// WorkspaceAudienceWrite is WorkspaceSelfOnly narrowed to the owner and the
// members listed in editors, for collections with an audience and no
// request-collected rows (shares, requests). The API-key branch is unchanged.
func WorkspaceAudienceWrite(scope string) string {
	return WorkspaceAudienceWriteBy("user", scope)
}

// WorkspaceAudienceWriteBy is WorkspaceAudienceWrite for a collection whose
// owner is held in ownerField.
func WorkspaceAudienceWriteBy(ownerField, scope string) string {
	userPart := audienceUserPartBy(ownerField, "editors")
	if scope == "" {
		return userPart
	}
	return userPart + " || " + apiKeyAudienceBranch(scope, "editors")
}

// WorkspaceAudienceEditorsOnly admits only the members listed in editors, and
// API keys holding the scope: for areas where owning a row is not enough to
// change it (attestations), the owner is listed only while they hold the
// permission.
func WorkspaceAudienceEditorsOnly(scope string) string {
	userPart := fmt.Sprintf("(%s && workspace = @request.auth.activeWorkspace && %s && editors.id ?= @request.auth.id)",
		authIsUser, memberRowMatches("workspace"))
	if scope == "" {
		return userPart
	}
	return userPart + " || " + apiKeyAudienceBranch(scope, "editors")
}
