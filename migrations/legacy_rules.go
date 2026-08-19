package migrations

import "fmt"

// Frozen copies of the util rule builders as they were before member
// permissions existed.
//
// A migration must produce the same SQL forever. Historical migrations used to
// call the live builders in util/rules.go, so editing a builder silently
// rewrote what every past migration emitted — and a from-scratch `migrate up`
// broke the moment a builder referenced a column that later migrations create.
// Migrations at and after 000040 use util.AccessSpec; everything before this
// point uses these frozen forms and must never be changed.
func legacyUserSelfOnly() string {
	return "@request.auth.collectionName = 'users' && user = @request.auth.id"
}

func legacyApiKeyPart(workspaceField, scope string) string {
	return fmt.Sprintf("(@request.auth.collectionName = 'apiKeys' && %s = @request.auth.workspace.id && @request.auth.scopes ~ '%s')", workspaceField, scope)
}

func legacyWorkspaceAnyMember(scope string) string {
	userPart := "(@request.auth.collectionName = 'users' && workspace = @request.auth.activeWorkspace && @collection.workspaceMembers.workspace ?= workspace && @collection.workspaceMembers.user ?= @request.auth.id)"
	if scope == "" {
		return userPart
	}
	return userPart + " || " + legacyApiKeyPart("workspace", scope)
}

func legacyWorkspaceSelfOnly(scope string) string {
	userPart := "(@request.auth.collectionName = 'users' && workspace = @request.auth.activeWorkspace && @collection.workspaceMembers.workspace ?= workspace && @collection.workspaceMembers.user ?= @request.auth.id && user = @request.auth.id)"
	if scope == "" {
		return userPart
	}
	return userPart + " || " + legacyApiKeyPart("workspace", scope)
}

func legacyWorkspaceAnyAdmin(scope string, targetField string) string {
	userPart := fmt.Sprintf("(@request.auth.collectionName = 'users' && @collection.workspaceMembers.workspace ?= %s && @collection.workspaceMembers.user ?= @request.auth.id && @collection.workspaceMembers.role ?= 'admin')", targetField)
	if scope == "" {
		return userPart
	}
	return userPart + " || " + legacyApiKeyPart(targetField, scope)
}

func legacyWorkspaceAdminSelfOnly(scope string, targetField string) string {
	userPart := fmt.Sprintf("(@request.auth.collectionName = 'users' && user = @request.auth.id && %s = @request.auth.activeWorkspace && @request.auth.activeRole = 'admin')", targetField)
	if scope == "" {
		return userPart
	}
	return userPart + " || " + legacyApiKeyPart(targetField, scope)
}
