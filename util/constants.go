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

	SealedActionAdd    = "add"
	SealedActionRemove = "remove"
	SealedKindDevice   = "device"
	SealedKindRecovery = "recovery"
	SealedKindPasskey  = "passkey"

	// SealedKeyScopeAccount marks an identity's sealedKey as wrapped under its
	// owner's account key. Empty is the phase 1 form, under the workspace key.
	SealedKeyScopeAccount = "account"

	FormatHidden    = "hidden"
	FormatDefault   = "default"
	FormatMultiline = "multiline"

	// MaxTemplateDescriptionLength mirrors the templates.description column
	// limit set by migration 000052; keep the two in step.
	MaxTemplateDescriptionLength = 500

	StatusActive  = "active"
	StatusPaused  = "paused"
	StatusRevoked = "revoked"
	// StatusDisconnected ends a sign-in at a service; its row stays as history.
	StatusDisconnected = "disconnected"
	StatusExpired      = "expired"
	StatusCompleted    = "completed"
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
	NotificationSealingReset    = "sealing_reset"
	// A member handed this person the key to a workspace's encrypted records.
	NotificationSealingAccessGranted = "sealing_access_granted"
	NotificationReminder             = "reminder"
	// The attester hears that an offer was accepted and a credential issued.
	NotificationAttestationAccepted = "attestation_accepted"
	// Whoever asked to see an attestation hears that it was shown.
	NotificationAttestationChecked = "attestation_checked"
	// Someone with an account here handed this person a share, or asked them
	// for data.
	NotificationContactShare = "contact_share"
	NotificationContactAsk   = "contact_ask"
	// The sender hears that the email carrying their grant never arrived.
	NotificationEmailUndelivered = "email_undelivered"
	// A webhook endpoint was switched off after days of failed deliveries.
	NotificationWebhookDisabled = "webhook_disabled"

	// A check waits open until it is answered once, or its time runs out.
	CheckStatusOpen     = "open"
	CheckStatusAnswered = "answered"

	// A reminder fires at a point in time, or the first time the entry it
	// watches changes.
	ReminderKindDate   = "date"
	ReminderKindChange = "change"

	// What a contact's key material has been shown to be. Unverified is the
	// honest default: an address someone typed in proves nothing about who
	// reads it.
	ContactUnverified = "unverified"
	ContactVerified   = "verified"
	ContactRevoked    = "revoked"

	// What a bookmark points at. Empty reads as a share, so every bookmark
	// saved before a request could be handed over still resolves.
	BookmarkKindShare   = "share"
	BookmarkKindRequest = "request"

	// What an audit row says happened. The three CRUD verbs are what the
	// request hooks record. Handing a grant to a contact gets its own two,
	// because that row names the contact rather than the grant: the grant's
	// own creation is recorded separately, as any other create is.
	AuditActionCreate = "create"
	AuditActionUpdate = "update"
	AuditActionDelete = "delete"
	AuditActionSend   = "send"
	AuditActionAsk    = "ask"

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
	// DeliveryKindEmail mails a grant to a contact with no account here.
	DeliveryKindEmail = "email"

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
	NotificationSealingReset,
	NotificationSealingAccessGranted,
	NotificationReminder,
	NotificationAttestationAccepted,
	NotificationAttestationChecked,
	NotificationContactShare,
	NotificationContactAsk,
	NotificationEmailUndelivered,
	NotificationWebhookDisabled,
}

// BookmarkKinds lists what a bookmark may point at.
var BookmarkKinds = []string{BookmarkKindShare, BookmarkKindRequest}

// An attestation share is pending from its creation until the holder's
// presentation arrives, active while it can be opened, and revoked once the
// holder ends it. An expired one stays active: its date says so.
const (
	ShareLinkPending = "pending"
	ShareLinkActive  = "active"
	ShareLinkRevoked = "revoked"
)

// AttestationShareStatuses lists the valid attestation share statuses.
var AttestationShareStatuses = []string{ShareLinkPending, ShareLinkActive, ShareLinkRevoked}

// CheckStatuses lists the valid attestation check statuses.
var CheckStatuses = []string{CheckStatusOpen, CheckStatusAnswered}

// AttestationStatuses lists the valid attestation statuses. An attestation is
// offered until its subject accepts it, active once the credential was
// issued, and revoked from either state. Like an identity it never returns
// from revoked: the statement was published, and verifiers may have read it.
var AttestationStatuses = []string{StatusOffered, StatusActive, StatusRevoked}

// DeliveryKinds lists the valid grant delivery kinds.
var DeliveryKinds = []string{DeliveryKindPeer, DeliveryKindCallback, DeliveryKindEmail}

// GrantEventTypes lists the valid grant event types.
var GrantEventTypes = []string{GrantEventRevoked, GrantEventChanged, GrantEventExpired}

// ReminderKinds lists the valid reminder kinds.
var ReminderKinds = []string{ReminderKindDate, ReminderKindChange}

// ContactTrustStates lists the valid contact trust states.
var ContactTrustStates = []string{ContactUnverified, ContactVerified, ContactRevoked}

// Who sees an item inside its workspace, and who may change it
// (VISIBILITY.md). An empty audience kind reads as private.
const (
	AudiencePrivate   = "private"
	AudienceWorkspace = "workspace"
	AudienceGroups    = "groups"

	EditingOwner    = "owner"
	EditingAudience = "audience"
)
