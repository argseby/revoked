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

	// OfficialDomain is the server the project itself runs.
	OfficialDomain = "api.revoked.link"

	// BlockedDomainsFileEnv names a file of domains this server's users are
	// warned off, in the format of blocked-domains.txt.
	BlockedDomainsFileEnv = "BLOCKED_DOMAINS_FILE"

	// MaxBlockedDomainsBytes bounds that file.
	MaxBlockedDomainsBytes = 1 << 20

	// MaxRecordValueLength mirrors the records.value column limit set by
	// migration 000019; keep the two in step.
	MaxRecordValueLength = 1000

	TypeText     = "text"
	TypeNumber   = "number"
	TypeUrl      = "url"
	TypeBoolean  = "boolean"
	TypeDatetime = "datetime"
	TypeFile     = "file"

	FormatHidden    = "hidden"
	FormatDefault   = "default"
	FormatMultiline = "multiline"

	// MaxTemplateDescriptionLength mirrors the templates.description column
	// limit set by migration 000052; keep the two in step.
	MaxTemplateDescriptionLength = 500

	StatusActive    = "active"
	StatusPaused    = "paused"
	StatusRevoked   = "revoked"
	StatusExpired   = "expired"
	StatusCompleted = "completed"
	// StatusOffered is an attestation that waits to be accepted: nothing has
	// been signed yet, and nobody holds a credential for it.
	StatusOffered = "offered"

	NotificationRequestResponse = "request_response"
	NotificationLinkExpired     = "link_expired"
	NotificationLinkRevoked     = "link_revoked"
	NotificationLinkMaxViews    = "link_max_views"
	NotificationRequestExpired  = "request_expired"
	NotificationRequestComplete = "request_complete"
	NotificationCallbackFailed  = "callback_failed"
	NotificationInviteAccepted  = "invite_accepted"
	NotificationLinkOpened      = "link_opened"
	NotificationReminder        = "reminder"
	// The attester hears that an offer was accepted and a credential issued.
	NotificationAttestationAccepted = "attestation_accepted"

	// A reminder fires at a point in time, or the first time the entry it
	// watches changes.
	ReminderKindDate   = "date"
	ReminderKindChange = "change"

	PurposeApplication = "application"

	// Grant events: what a requester learns when a grant it holds changes.
	// An event names the grant and its new status, never a value; the
	// receiver reads the value again if it needs it.
	GrantEventRevoked = "grant.revoked"
	GrantEventChanged = "grant.changed"
	GrantEventExpired = "grant.expired"

	// A grant delivery goes to another server's event endpoint, or to the
	// callback URL of one of this server's own requests.
	DeliveryKindPeer     = "peer"
	DeliveryKindCallback = "callback"

	// Revocation reasons recorded on an identity. They are advisory — a verifier
	// treats every non-active status the same — but they are what tells an
	// operator reading an audit trail why a credential stopped being honoured.
	RevocationManual          = "manual"
	RevocationMembershipEnded = "membership_ended"
	RevocationKeyCompromise   = "key_compromise"
	RevocationDeleted         = "deleted"
)

// WorkspaceRoles lists the valid workspace member roles.
var WorkspaceRoles = []string{RoleAdmin, RoleMember}

// RecordTypes lists the valid record value types. Everything but a file is
// stored as text and read back as text; the type says how the client should
// render and validate it, which is why widening this list needs no other
// change here.
var RecordTypes = []string{
	TypeText,
	TypeNumber,
	TypeUrl,
	TypeBoolean,
	TypeDatetime,
	TypeFile,
}

// RecordFormats lists the valid record display formats.
var RecordFormats = []string{FormatHidden, FormatDefault}

// LinkPurposes lists the valid link purposes; an empty purpose is a plain share.
var LinkPurposes = []string{PurposeApplication}

// LinkStatuses lists the valid link statuses.
var LinkStatuses = []string{StatusActive, StatusPaused, StatusRevoked, StatusExpired}

// InviteStatuses lists the valid invite statuses. An invite is spent when it
// reaches maxUses, and revoked when an admin withdraws it.
var InviteStatuses = []string{StatusActive, StatusRevoked, StatusExpired, StatusCompleted}

// IdentityStatuses lists the valid identity statuses. An identity is never
// deleted in the normal course of things — it is revoked, so that a verifier
// holding a copy of its public material gets a definitive answer instead of
// the silence a missing row would produce.
var IdentityStatuses = []string{StatusActive, StatusRevoked}

// RevocationReasons lists the valid identity revocation reasons.
var RevocationReasons = []string{
	RevocationManual,
	RevocationMembershipEnded,
	RevocationKeyCompromise,
	RevocationDeleted,
}

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
	NotificationLinkOpened,
	NotificationReminder,
	NotificationAttestationAccepted,
}

// AttestationStatuses lists the valid attestation statuses. An attestation is
// offered until its subject accepts it, active once the credential was
// issued, and revoked from either state. Like an identity it never returns
// from revoked: the statement was published, and verifiers may have read it.
var AttestationStatuses = []string{StatusOffered, StatusActive, StatusRevoked}

// DeliveryKinds lists the valid grant delivery kinds.
var DeliveryKinds = []string{DeliveryKindPeer, DeliveryKindCallback}

// GrantEventTypes lists the valid grant event types.
var GrantEventTypes = []string{GrantEventRevoked, GrantEventChanged, GrantEventExpired}

// ReminderKinds lists the valid reminder kinds.
var ReminderKinds = []string{ReminderKindDate, ReminderKindChange}
