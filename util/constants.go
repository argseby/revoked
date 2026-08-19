// Package util provides the shared schema names, access rules, typed API errors,
// and crypto helpers used across the revoked backend.
package util

// Domain constants shared across the backend.
const (
	SlugPattern              = "^[a-z0-9_-]+$"
	MaximumWorkspacesPerUser = 10
	MaximumWorkspaceMembers  = 50
	RoleAdmin                = "admin"
	RoleMember               = "member"

	// MaxRecordValueLength mirrors the records.value column limit set by
	// migration 000019; keep the two in step.
	MaxRecordValueLength = 1000

	TypeText   = "text"
	TypeNumber = "number"

	FormatHidden  = "hidden"
	FormatDefault = "default"

	StatusActive    = "active"
	StatusPaused    = "paused"
	StatusRevoked   = "revoked"
	StatusExpired   = "expired"
	StatusCompleted = "completed"

	NotificationRequestResponse = "request_response"
	NotificationLinkExpired     = "link_expired"
	NotificationLinkRevoked     = "link_revoked"
	NotificationLinkMaxViews    = "link_max_views"
	NotificationRequestExpired  = "request_expired"
	NotificationRequestComplete = "request_complete"
	NotificationCallbackFailed  = "callback_failed"
	NotificationInviteAccepted  = "invite_accepted"
)

// WorkspaceRoles lists the valid workspace member roles.
var WorkspaceRoles = []string{RoleAdmin, RoleMember}

// RecordTypes lists the valid record value types.
var RecordTypes = []string{TypeText, TypeNumber}

// RecordFormats lists the valid record display formats.
var RecordFormats = []string{FormatHidden, FormatDefault}

// LinkStatuses lists the valid link statuses.
var LinkStatuses = []string{StatusActive, StatusPaused, StatusRevoked, StatusExpired}

// InviteStatuses lists the valid invite statuses. An invite is spent when it
// reaches maxUses, and revoked when an admin withdraws it.
var InviteStatuses = []string{StatusActive, StatusRevoked, StatusExpired, StatusCompleted}

// RequestStatuses lists the valid request statuses.
var RequestStatuses = []string{StatusActive, StatusPaused, StatusRevoked, StatusExpired, StatusCompleted}

// NotificationTypes lists the valid notification types.
var NotificationTypes = []string{
	NotificationRequestResponse,
	NotificationLinkExpired,
	NotificationLinkRevoked,
	NotificationLinkMaxViews,
	NotificationRequestExpired,
	NotificationRequestComplete,
	NotificationCallbackFailed,
	NotificationInviteAccepted,
}
