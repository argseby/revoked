package util

import (
	"errors"

	validation "github.com/go-ozzo/ozzo-validation/v4"
)

// ErrInviteAlreadySpent is returned when a concurrent redemption took the last
// use of an invite.
var ErrInviteAlreadySpent = errors.New("invite already spent")

// AppError pairs a stable machine-readable error code with a human-readable message.
type AppError struct {
	ErrorCode string
	ErrorText string
}

// Errors holds the typed application errors returned across the backend.
var Errors = struct {
	DuplicateWorkspaceMember      AppError
	FailedToCreateWorkspaceMember AppError
	WorkspaceMemberLimitReached   AppError
	WorkspaceLimitReached         AppError
	WorkspaceNotFound             AppError
	UserNotFound                  AppError
	ValidationFieldRequired       AppError
	ValidationFieldRestricted     AppError
	NotAuthorized                 AppError
	NotAuthenticated              AppError
	FailedToCreateRecord          AppError
	ForbiddenWorkspaceAccess      AppError
	DuplicateValues               AppError
	InvalidActiveWorkspace        AppError
	ActiveWorkspaceMismatch       AppError
	LinkNotFound                  AppError
	LinkRevoked                   AppError
	LinkExpired                   AppError
	LinkPaused                    AppError
	LinkMaxViewsReached           AppError
	LinkPasswordRequired          AppError
	LinkPasswordInvalid           AppError
	RequestNotFound               AppError
	RequestRevoked                AppError
	RequestExpired                AppError
	RequestPaused                 AppError
	RequestCompleted              AppError
	RequestPasswordRequired       AppError
	RequestPasswordInvalid        AppError
	RequestIdentifierMissing      AppError
	RequestAccountRequired        AppError
	HandshakeRequired             AppError
	HandshakeInvalid              AppError
	HandshakeFailed               AppError
	IdentityNotFound              AppError
	IdentityRequired              AppError
	IdentityWrongRoot             AppError
	IdentityNotOwned              AppError
	BookmarkGroupNotOwned         AppError
	IdentityRevoked               AppError
	IdentityFingerprintInvalid    AppError
	InviteInviterLostAccess       AppError
	SignupsDisabled               AppError
	InvalidScope                  AppError
	InvalidApiKey                 AppError
	ApiKeyExpired                 AppError
	ApiKeyNotPermitted            AppError
	AccessDenied                  AppError
	MissingActiveWorkspace        AppError
	NotWorkspaceMember            AppError
	NotWorkspaceAdmin             AppError
	NotRecordOwner                AppError
	MissingPermission             AppError
	PermissionEscalation          AppError
	LastAdminProtected            AppError
	InviteNotFound                AppError
	InviteExpired                 AppError
	FileRequired                  AppError
	FileNotAllowed                AppError
	FileTooLarge                  AppError
	FileStorageExceeded           AppError
	FileAliasUnsupported          AppError
	FileDownloadInvalid           AppError
	FileNotWatermarkable          AppError
	ApplicationNeedsWatermark     AppError
	FileNameInvalid               AppError
	RecordNotFound                AppError
	WatermarkTextInvalid          AppError
	ArchiveEmpty                  AppError
	InviteRevoked                 AppError
	InviteExhausted               AppError
	InviteWrongAccount            AppError
	AlreadyWorkspaceMember        AppError
	InvalidCertificate            AppError
	ChallengeRequired             AppError
	ChallengeInvalid              AppError
	SignatureInvalid              AppError
	RequestRequiredMissing        AppError
	RequestExtraFieldsForbidden   AppError
	RequestKeyInvalid             AppError
	AliasCycle                    AppError
	AliasParentMissing            AppError
	RateLimited                   AppError
	ApiKeyVaultScope              AppError
	ConnectionClientInvalid       AppError
	ConnectionRedirectInvalid     AppError
	ConnectionChallengeInvalid    AppError
	ConnectionGrantInvalid        AppError
	ConnectionUnauthorized        AppError
	ConnectionExpired             AppError
	ConnectionNotConnected        AppError
	ConnectionRevokeNotAllowed    AppError
	LinkHandOverNotAllowed        AppError
	LinkConnectionForeign         AppError
	PasskeyOriginInvalid          AppError
	PasskeyRequestInvalid         AppError
	PasskeyEmailInvalid           AppError
	PasskeyEmailTaken             AppError
	PasskeyTicketInvalid          AppError
	PasskeyCeremonyInvalid        AppError
	PasskeyVerificationFailed     AppError
	PasskeyGrantInvalid           AppError
	PasskeyLast                   AppError
	PasskeySignupOnly             AppError
	EmailVerificationOff          AppError
	EmailVerificationRequired     AppError
	EmailCodeInvalid              AppError
	EmailCodeTooSoon              AppError
	EmailSendFailed               AppError
	ReminderRecordMissing         AppError
	ReminderWatchMissing          AppError
	ReminderDueRequired           AppError
	ReminderKindInvalid           AppError
	RemoteOriginInvalid           AppError
	RemoteServerMismatch          AppError
	RemoteUnreachable             AppError
	RemoteGrantUnresolvable       AppError
	RemoteIdentityInvalid         AppError
	GrantEventsUnverified         AppError
	PeerKeyUnavailable            AppError
	OIDCRequestInvalid            AppError
	OIDCLinkRecordInvalid         AppError
	AttestationsDisabled          AppError
	AttestationTypeInvalid        AppError
	AttestationClaimsInvalid      AppError
	AttestationClaimReserved      AppError
	AttestationSubjectInvalid     AppError
	AttestationImmutable          AppError
	AttestationExpiryInvalid      AppError
	AttestationOfferNotFound      AppError
	AttestationOfferExpired       AppError
	AttestationOfferClaimed       AppError
	AttestationOfferRevoked       AppError
	AttestationIdentityMismatch   AppError
	AttestationKeyUnsupported     AppError
	AttestationIssueFailed        AppError
	CredentialInvalid             AppError
	PresentationInvalid           AppError
	AttestationCheckInvalid       AppError
	AttestationCheckNotFound      AppError
	AttestationCheckClosed        AppError
}{
	DuplicateWorkspaceMember: AppError{
		ErrorCode: "duplicate_workspace_member",
		ErrorText: "This user is already a member of this workspace.",
	},
	WorkspaceMemberLimitReached: AppError{
		ErrorCode: "workspace_member_limit_reached",
		ErrorText: "This workspace reached the maximum number of members.",
	},
	FailedToCreateWorkspaceMember: AppError{
		ErrorCode: "failed_to_create_workspace_member",
		ErrorText: "Failed to add user to workspace.",
	},
	ValidationFieldRestricted: AppError{
		ErrorCode: "validation_insufficient_permissions",
		ErrorText: "You do not have permission to modify this field.",
	},
	ValidationFieldRequired: AppError{
		ErrorCode: "validation_required",
		ErrorText: "Missing required value.",
	},
	NotAuthorized: AppError{
		ErrorCode: "not_authorized",
		ErrorText: "You do not have the permission for this request.",
	},
	NotAuthenticated: AppError{
		ErrorCode: "not_authenticated",
		ErrorText: "You are not authenticated.",
	},
	FailedToCreateRecord: AppError{
		ErrorCode: "failed_to_create_record",
		ErrorText: "Failed to create record.",
	},
	DuplicateValues: AppError{
		ErrorCode: "duplicate_values",
		ErrorText: "Duplicate values are not allowed.",
	},
	WorkspaceLimitReached: AppError{
		ErrorCode: "workspace_limit_reached",
		ErrorText: "You have reached the maximum number of workspaces.",
	},
	WorkspaceNotFound: AppError{
		ErrorCode: "workspace_not_found",
		ErrorText: "Workspace not found.",
	},
	UserNotFound: AppError{
		ErrorCode: "user_not_found",
		ErrorText: "User not found.",
	},
	ForbiddenWorkspaceAccess: AppError{
		ErrorCode: "forbidden_workspace_access",
		ErrorText: "This user does not have access to this workspace.",
	},
	InvalidActiveWorkspace: AppError{
		ErrorCode: "invalid_active_workspace",
		ErrorText: "The selected active workspace is invalid.",
	},
	ActiveWorkspaceMismatch: AppError{
		ErrorCode: "active_workspace_mismatch",
		ErrorText: "The selected workspace does not match your active workspace.",
	},
	LinkNotFound: AppError{
		ErrorCode: "link_not_found",
		ErrorText: "Link not found.",
	},
	LinkRevoked: AppError{
		ErrorCode: "link_revoked",
		ErrorText: "This link has been revoked.",
	},
	LinkExpired: AppError{
		ErrorCode: "link_expired",
		ErrorText: "This link has expired.",
	},
	LinkPaused: AppError{
		ErrorCode: "link_paused",
		ErrorText: "This link is paused by its owner and is temporarily unavailable.",
	},
	LinkMaxViewsReached: AppError{
		ErrorCode: "link_max_views_reached",
		ErrorText: "This link has reached its maximum number of views.",
	},
	LinkPasswordRequired: AppError{
		ErrorCode: "link_password_required",
		ErrorText: "A password is required to access this link.",
	},
	LinkPasswordInvalid: AppError{
		ErrorCode: "link_password_invalid",
		ErrorText: "The supplied password is invalid.",
	},
	RequestNotFound: AppError{
		ErrorCode: "request_not_found",
		ErrorText: "Request not found.",
	},
	FileRequired: AppError{
		ErrorCode: "file_required",
		ErrorText: "A file record requires an uploaded file.",
	},
	FileNotAllowed: AppError{
		ErrorCode: "file_not_allowed",
		ErrorText: "Only file records may carry an uploaded file.",
	},
	FileTooLarge: AppError{
		ErrorCode: "file_too_large",
		ErrorText: "The file exceeds this server's maximum file size.",
	},
	FileStorageExceeded: AppError{
		ErrorCode: "file_storage_exceeded",
		ErrorText: "This workspace has reached its file storage limit.",
	},
	FileAliasUnsupported: AppError{
		ErrorCode: "file_alias_unsupported",
		ErrorText: "A reference record cannot be a file.",
	},
	FileDownloadInvalid: AppError{
		ErrorCode: "file_download_invalid",
		ErrorText: "The download token is invalid or expired. Reopen the link to request a new one.",
	},
	FileNotWatermarkable: AppError{
		ErrorCode: "file_not_watermarkable",
		ErrorText: "This share stamps its files, and this file cannot be stamped, so it is not served.",
	},
	ApplicationNeedsWatermark: AppError{
		ErrorCode: "application_needs_watermark",
		ErrorText: "An application link must stamp its files.",
	},
	FileNameInvalid: AppError{
		ErrorCode: "file_name_invalid",
		ErrorText: "A file name cannot be empty or contain path separators.",
	},
	RecordNotFound: AppError{
		ErrorCode: "record_not_found",
		ErrorText: "Record not found.",
	},
	WatermarkTextInvalid: AppError{
		ErrorCode: "watermark_text_invalid",
		ErrorText: "A stamp text must be a single line of 1 to 120 characters.",
	},
	ArchiveEmpty: AppError{
		ErrorCode: "archive_empty",
		ErrorText: "This share has no files that can be downloaded together.",
	},
	RequestRevoked: AppError{
		ErrorCode: "request_revoked",
		ErrorText: "This request has been revoked.",
	},
	RequestExpired: AppError{
		ErrorCode: "request_expired",
		ErrorText: "This request has expired.",
	},
	RequestPaused: AppError{
		ErrorCode: "request_paused",
		ErrorText: "This request is paused by its owner and is temporarily unavailable.",
	},
	RequestCompleted: AppError{
		ErrorCode: "request_completed",
		ErrorText: "This request has already been completed.",
	},
	RequestPasswordRequired: AppError{
		ErrorCode: "request_password_required",
		ErrorText: "A password is required to access this request.",
	},
	RequestPasswordInvalid: AppError{
		ErrorCode: "request_password_invalid",
		ErrorText: "The supplied password is invalid.",
	},
	RequestIdentifierMissing: AppError{
		ErrorCode: "request_identifier_missing",
		ErrorText: "The identifier is missing or does not match.",
	},
	RequestAccountRequired: AppError{
		ErrorCode: "request_account_required",
		ErrorText: "An account on this server is required to respond to a request.",
	},
	HandshakeRequired: AppError{
		ErrorCode: "handshake_required",
		ErrorText: "A handshake token is required for subsequent communications.",
	},
	HandshakeInvalid: AppError{
		ErrorCode: "handshake_invalid",
		ErrorText: "The provided handshake token is invalid.",
	},
	HandshakeFailed: AppError{
		ErrorCode: "handshake_failed",
		ErrorText: "The handshake could not be completed. Please try again.",
	},
	IdentityNotFound: AppError{
		ErrorCode: "identity_not_found",
		ErrorText: "Identity not found.",
	},
	IdentityRequired: AppError{
		ErrorCode: "identity_required",
		ErrorText: "An identity is required for this action.",
	},
	IdentityWrongRoot: AppError{
		ErrorCode: "identity_wrong_root",
		ErrorText: "This request only accepts identities issued by this server.",
	},
	IdentityNotOwned: AppError{
		ErrorCode: "identity_not_owned",
		ErrorText: "The selected identity does not belong to your workspace.",
	},
	BookmarkGroupNotOwned: AppError{
		ErrorCode: "bookmark_group_not_owned",
		ErrorText: "A selected group is not one of yours.",
	},
	IdentityRevoked: AppError{
		ErrorCode: "identity_revoked",
		ErrorText: "This identity has been revoked by the server that issued it.",
	},
	IdentityFingerprintInvalid: AppError{
		ErrorCode: "identity_fingerprint_invalid",
		ErrorText: "An identity fingerprint must be 64 lowercase hexadecimal characters.",
	},
	InviteInviterLostAccess: AppError{
		ErrorCode: "invite_inviter_lost_access",
		ErrorText: "Whoever created this invite can no longer invite people to this workspace.",
	},
	SignupsDisabled: AppError{
		ErrorCode: "signups_disabled",
		ErrorText: "This server does not accept new registrations.",
	},
	InvalidScope: AppError{
		ErrorCode: "invalid_scope",
		ErrorText: "One or more requested API key scopes are unknown.",
	},
	ApiKeyExpired: AppError{
		ErrorCode: "api_key_expired",
		ErrorText: "This API key has expired.",
	},
	InvalidApiKey: AppError{
		ErrorCode: "invalid_api_key",
		ErrorText: "The supplied X-API-Key is not valid.",
	},
	ApiKeyNotPermitted: AppError{
		ErrorCode: "api_key_not_permitted",
		ErrorText: "API keys cannot perform this action; use a user session.",
	},
	AccessDenied: AppError{
		ErrorCode: "access_denied",
		ErrorText: "You are not allowed to perform this action on this record.",
	},
	MissingActiveWorkspace: AppError{
		ErrorCode: "missing_active_workspace",
		ErrorText: "No active workspace is selected for this account.",
	},
	NotWorkspaceMember: AppError{
		ErrorCode: "not_workspace_member",
		ErrorText: "You are not a member of this workspace.",
	},
	NotWorkspaceAdmin: AppError{
		ErrorCode: "not_workspace_admin",
		ErrorText: "This action requires the admin role in this workspace.",
	},
	NotRecordOwner: AppError{
		ErrorCode: "not_record_owner",
		ErrorText: "This record belongs to another user.",
	},
	MissingPermission: AppError{
		ErrorCode: "missing_permission",
		ErrorText: "Your access to this workspace does not include this action.",
	},
	PermissionEscalation: AppError{
		ErrorCode: "permission_escalation",
		ErrorText: "You cannot grant access you do not hold yourself.",
	},
	LastAdminProtected: AppError{
		ErrorCode: "last_admin_protected",
		ErrorText: "This workspace would be left with nobody who can manage members.",
	},
	InviteNotFound: AppError{
		ErrorCode: "invite_not_found",
		ErrorText: "This invite does not exist.",
	},
	InviteExpired: AppError{
		ErrorCode: "invite_expired",
		ErrorText: "This invite has expired.",
	},
	InviteRevoked: AppError{
		ErrorCode: "invite_revoked",
		ErrorText: "This invite has been revoked.",
	},
	InviteExhausted: AppError{
		ErrorCode: "invite_exhausted",
		ErrorText: "This invite has already been used.",
	},
	InviteWrongAccount: AppError{
		ErrorCode: "invite_wrong_account",
		ErrorText: "This invite was issued for a different email address.",
	},
	AlreadyWorkspaceMember: AppError{
		ErrorCode: "already_workspace_member",
		ErrorText: "You already have access to this workspace.",
	},
	InvalidCertificate: AppError{
		ErrorCode: "invalid_certificate",
		ErrorText: "The supplied certificate is invalid.",
	},
	ChallengeRequired: AppError{
		ErrorCode: "challenge_required",
		ErrorText: "A signed handshake challenge is required.",
	},
	ChallengeInvalid: AppError{
		ErrorCode: "challenge_invalid",
		ErrorText: "The handshake challenge is unknown, expired, or already used.",
	},
	SignatureInvalid: AppError{
		ErrorCode: "signature_invalid",
		ErrorText: "The supplied challenge signature is invalid.",
	},
	RequestRequiredMissing: AppError{
		ErrorCode: "request_required_missing",
		ErrorText: "Required template fields are missing from the submission.",
	},
	RequestExtraFieldsForbidden: AppError{
		ErrorCode: "request_extra_fields_forbidden",
		ErrorText: "Additional fields beyond the template are not allowed for this request.",
	},
	RequestKeyInvalid: AppError{
		ErrorCode: "request_key_invalid",
		ErrorText: "One or more submitted keys do not match the required pattern.",
	},
	AliasCycle: AppError{
		ErrorCode: "alias_cycle",
		ErrorText: "An alias cannot point at another alias.",
	},
	AliasParentMissing: AppError{
		ErrorCode: "alias_parent_missing",
		ErrorText: "The alias parent record does not exist in this workspace.",
	},
	RateLimited: AppError{
		ErrorCode: "rate_limited",
		ErrorText: "Too many attempts. Please wait a moment and try again.",
	},
	ApiKeyVaultScope: AppError{
		ErrorCode: "api_key_vault_scope",
		ErrorText: "An API key cannot read or write the vault.",
	},
	ConnectionClientInvalid: AppError{
		ErrorCode: "connection_client_invalid",
		ErrorText: "A tool is identified by an https origin (or http on localhost), and nothing else.",
	},
	ConnectionRedirectInvalid: AppError{
		ErrorCode: "connection_redirect_invalid",
		ErrorText: "The return address must be on the tool's own origin.",
	},
	ConnectionChallengeInvalid: AppError{
		ErrorCode: "connection_challenge_invalid",
		ErrorText: "The PKCE challenge is missing or malformed.",
	},
	ConnectionGrantInvalid: AppError{
		ErrorCode: "connection_grant_invalid",
		ErrorText: "This code is unknown, expired, already used, or does not match its verifier.",
	},
	ConnectionUnauthorized: AppError{
		ErrorCode: "connection_unauthorized",
		ErrorText: "This connection token is unknown or was disconnected.",
	},
	ConnectionExpired: AppError{
		ErrorCode: "connection_expired",
		ErrorText: "This connection has expired. Connect the tool again from the app.",
	},
	ConnectionNotConnected: AppError{
		ErrorCode: "connection_not_connected",
		ErrorText: "This tool has no live connection to reuse. Connect it from the app.",
	},
	ConnectionRevokeNotAllowed: AppError{
		ErrorCode: "connection_revoke_not_allowed",
		ErrorText: "The owner has not allowed this tool to revoke links.",
	},
	LinkHandOverNotAllowed: AppError{
		ErrorCode: "link_hand_over_not_allowed",
		ErrorText: "The owner has not allowed this tool to receive links.",
	},
	LinkConnectionForeign: AppError{
		ErrorCode: "link_connection_foreign",
		ErrorText: "A link can only name one of your own connections, and keeps the one it was created with.",
	},
	PasskeyOriginInvalid: AppError{
		ErrorCode: "passkey_origin_invalid",
		ErrorText: "Passkeys only work at this server's own address. On a development machine that is localhost, not 127.0.0.1.",
	},
	PasskeyRequestInvalid: AppError{
		ErrorCode: "passkey_request_invalid",
		ErrorText: "The sign-in request is malformed.",
	},
	PasskeyEmailInvalid: AppError{
		ErrorCode: "passkey_email_invalid",
		ErrorText: "Enter a valid email address.",
	},
	PasskeyEmailTaken: AppError{
		ErrorCode: "passkey_email_taken",
		ErrorText: "An account with this email address already exists. Sign in instead.",
	},
	PasskeyTicketInvalid: AppError{
		ErrorCode: "passkey_ticket_invalid",
		ErrorText: "This link is unknown, already used, or has expired. Ask for a new one.",
	},
	PasskeyCeremonyInvalid: AppError{
		ErrorCode: "passkey_ceremony_invalid",
		ErrorText: "This attempt took too long or was already finished. Start again.",
	},
	PasskeyVerificationFailed: AppError{
		ErrorCode: "passkey_verification_failed",
		ErrorText: "The passkey could not be verified.",
	},
	PasskeyGrantInvalid: AppError{
		ErrorCode: "passkey_grant_invalid",
		ErrorText: "This code is unknown, expired, already used, or does not match its verifier.",
	},
	PasskeySignupOnly: AppError{
		ErrorCode: "passkey_signup_only",
		ErrorText: "Accounts are created with a passkey, on this server's sign-in page.",
	},
	PasskeyLast: AppError{
		ErrorCode: "passkey_last",
		ErrorText: "This is your only passkey. Add another before removing it, or you could not sign in again.",
	},
	EmailVerificationOff: AppError{
		ErrorCode: "email_verification_off",
		ErrorText: "This server does not confirm email addresses. Create the account directly.",
	},
	EmailVerificationRequired: AppError{
		ErrorCode: "email_verification_required",
		ErrorText: "Confirm your email address with the code we sent before creating the account.",
	},
	EmailCodeInvalid: AppError{
		ErrorCode: "email_code_invalid",
		ErrorText: "This code is wrong, expired, or was tried too often. Request a new one.",
	},
	EmailCodeTooSoon: AppError{
		ErrorCode: "email_code_too_soon",
		ErrorText: "A code was just sent to this address. Wait a minute before asking for another.",
	},
	EmailSendFailed: AppError{
		ErrorCode: "email_send_failed",
		ErrorText: "The confirmation email could not be sent. Try again later.",
	},
	ReminderRecordMissing: AppError{
		ErrorCode: "reminder_record_missing",
		ErrorText: "The entry this reminder is for does not exist, or is not in a workspace you belong to.",
	},
	ReminderWatchMissing: AppError{
		ErrorCode: "reminder_watch_missing",
		ErrorText: "The watched entry does not exist, or is not in the same workspace.",
	},
	ReminderDueRequired: AppError{
		ErrorCode: "reminder_due_required",
		ErrorText: "Pick when to be reminded.",
	},
	ReminderKindInvalid: AppError{
		ErrorCode: "reminder_kind_invalid",
		ErrorText: "A reminder is either for a date or for a change.",
	},
	RemoteOriginInvalid: AppError{
		ErrorCode: "remote_origin_invalid",
		ErrorText: "The request names a server address that cannot be used.",
	},
	RemoteServerMismatch: AppError{
		ErrorCode: "remote_server_mismatch",
		ErrorText: "The server at this address claims to be a different domain.",
	},
	RemoteUnreachable: AppError{
		ErrorCode: "remote_unreachable",
		ErrorText: "The other server could not be reached. Try again later.",
	},
	RemoteGrantUnresolvable: AppError{
		ErrorCode: "remote_grant_unresolvable",
		ErrorText: "The answer could not be read from the server it lives on.",
	},
	RemoteIdentityInvalid: AppError{
		ErrorCode: "remote_identity_invalid",
		ErrorText: "The identity could not be verified with the server that issued it.",
	},
	GrantEventsUnverified: AppError{
		ErrorCode: "grant_events_unverified",
		ErrorText: "The events are not signed by the server they claim to come from.",
	},
	PeerKeyUnavailable: AppError{
		ErrorCode: "peer_key_unavailable",
		ErrorText: "The sending server's key could not be checked. Try again later.",
	},
	OIDCRequestInvalid: AppError{
		ErrorCode: "oidc_request_invalid",
		ErrorText: "This sign-in has expired or was already used. Start it again from the service.",
	},
	OIDCLinkRecordInvalid: AppError{
		ErrorCode: "oidc_link_record_invalid",
		ErrorText: "An entry chosen to share is not one of yours.",
	},
	AttestationsDisabled: AppError{
		ErrorCode: "attestations_disabled",
		ErrorText: "This server does not issue attestations. Its operator decides whether it speaks for its domain.",
	},
	AttestationTypeInvalid: AppError{
		ErrorCode: "attestation_type_invalid",
		ErrorText: "An attestation needs a type: up to 255 characters, without spaces.",
	},
	AttestationClaimsInvalid: AppError{
		ErrorCode: "attestation_claims_invalid",
		ErrorText: "Claims are a flat set of named values: names of letters, digits and underscores, values of text, numbers or true/false.",
	},
	AttestationClaimReserved: AppError{
		ErrorCode: "attestation_claim_reserved",
		ErrorText: "A claim uses a name the credential format sets itself.",
	},
	AttestationSubjectInvalid: AppError{
		ErrorCode: "attestation_subject_invalid",
		ErrorText: "The identity an offer is made for is named by its fingerprint: 64 hexadecimal characters.",
	},
	AttestationImmutable: AppError{
		ErrorCode: "attestation_immutable",
		ErrorText: "What an attestation states cannot be changed once it exists. Revoke it and issue a new one.",
	},
	AttestationExpiryInvalid: AppError{
		ErrorCode: "attestation_expiry_invalid",
		ErrorText: "A date an attestation or its offer ends on lies in the future.",
	},
	AttestationOfferNotFound: AppError{
		ErrorCode: "attestation_offer_not_found",
		ErrorText: "This offer does not exist.",
	},
	AttestationOfferExpired: AppError{
		ErrorCode: "attestation_offer_expired",
		ErrorText: "This offer has expired. Ask its issuer for a new one.",
	},
	AttestationOfferClaimed: AppError{
		ErrorCode: "attestation_offer_claimed",
		ErrorText: "This offer was already accepted. An offer works once.",
	},
	AttestationOfferRevoked: AppError{
		ErrorCode: "attestation_offer_revoked",
		ErrorText: "This offer was withdrawn by its issuer.",
	},
	AttestationIdentityMismatch: AppError{
		ErrorCode: "attestation_identity_mismatch",
		ErrorText: "This offer was made for a different identity.",
	},
	AttestationKeyUnsupported: AppError{
		ErrorCode: "attestation_key_unsupported",
		ErrorText: "The identity's key is of a kind a credential cannot be bound to.",
	},
	AttestationIssueFailed: AppError{
		ErrorCode: "attestation_issue_failed",
		ErrorText: "The credential could not be issued. Try again later.",
	},
	CredentialInvalid: AppError{
		ErrorCode: "credential_invalid",
		ErrorText: "The credential the issuer returned did not verify, so it was not kept.",
	},
	PresentationInvalid: AppError{
		ErrorCode: "presentation_invalid",
		ErrorText: "This is not a credential presentation that can be read.",
	},
	AttestationCheckInvalid: AppError{
		ErrorCode: "attestation_check_invalid",
		ErrorText: "A check names a type without spaces, attesters as domains, and claims as names of letters, digits and underscores.",
	},
	AttestationCheckNotFound: AppError{
		ErrorCode: "attestation_check_not_found",
		ErrorText: "This check does not exist. Check that the link was copied in full.",
	},
	AttestationCheckClosed: AppError{
		ErrorCode: "attestation_check_closed",
		ErrorText: "This check was already answered or has run out. Ask for a new one.",
	},
}

// AsValidationError converts an AppError into an ozzo-validation error carrying its code and text.
func AsValidationError(appErr AppError) error {
	return validation.NewError(appErr.ErrorCode, appErr.ErrorText)
}

// AsFieldValidationError binds a typed error to the field that caused it, so
// PocketBase carries it into the response's data map. A bare validation error
// surfaces as a dataless 400, which the preflight's normalizeGenericFailure
// rewrites into a generic 403 — hiding the actual code from the caller.
func AsFieldValidationError(field string, appErr AppError) error {
	return validation.Errors{field: validation.NewError(appErr.ErrorCode, appErr.ErrorText)}
}
