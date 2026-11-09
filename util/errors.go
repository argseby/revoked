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
	ContactRouteMissing           AppError
	ContactBlockTargetMissing     AppError
	ContactNotFound               AppError
	ContactNothingToSend          AppError
	TemplateNotOwned              AppError
	IdentityRevoked               AppError
	IdentityFingerprintInvalid    AppError
	InviteInviterLostAccess       AppError
	SignupsDisabled               AppError
	InvalidScope                  AppError
	UnknownFeature                AppError
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
	ConnectionPaused              AppError
	ConnectionVaultNotAllowed     AppError
	ConnectionVaultPolled         AppError
	ConnectionVaultReconnect      AppError
	ConnectionNotPermitted        AppError
	ConnectionPolled              AppError
	ConnectionPermissionInvalid   AppError
	VaultNotAllowed               AppError
	VaultReadOnly                 AppError
	VaultSectionNotWritable       AppError
	VaultSectionInvalid           AppError
	VaultStorageExceeded          AppError
	VaultKeyTaken                 AppError
	LinkHandOverNotAllowed        AppError
	LinkConnectionForeign         AppError
	ConnectionForeign             AppError
	PasskeyOriginInvalid          AppError
	PasskeyRequestInvalid         AppError
	PasskeyEmailInvalid           AppError
	PasskeyEmailTaken             AppError
	PasskeyTicketInvalid          AppError
	PasskeyCeremonyInvalid        AppError
	PasskeyVerificationFailed     AppError
	PasskeyUnknown                AppError
	PasskeyGrantInvalid           AppError
	PasskeyLast                   AppError
	PasskeySignupOnly             AppError
	TwoFactorRequired             AppError
	TwoFactorChallengeInvalid     AppError
	TwoFactorCodeInvalid          AppError
	TwoFactorNotEnabled           AppError
	TwoFactorAlreadyEnabled       AppError
	TwoFactorNotPending           AppError
	TwoFactorEnforced             AppError
	TwoFactorSetupRequired        AppError
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
	OIDCNameInvalid               AppError
	OIDCNameTooLong               AppError
	OIDCSignInPaused              AppError
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
	CredentialNotFound            AppError
	ReissueCredentialInvalid      AppError
	ReissueCredentialExpired      AppError
	ReissueCredentialRevoked      AppError
	ReissueVoucherInvalid         AppError
	ReissueIdentityMismatch       AppError
	ReissueHolderRevoked          AppError
	ReissueHolderUnconfirmed      AppError
	PresentationInvalid           AppError
	AttestationCheckInvalid       AppError
	AttestationCheckNotFound      AppError
	AttestationCheckClosed        AppError
	AttestationShareInvalid       AppError
	AttestationShareNotFound      AppError
	AttestationShareClosed        AppError
	SealedFieldsRestricted        AppError
	SealedInvalid                 AppError
	SealedVersionConflict         AppError
	SealedEpochStale              AppError
	SealedKeyMissing              AppError
	SealedIdentityKeysPending     AppError
	SectionShareByPersonOnly      AppError
	AudienceByOwnerOnly           AppError
	AudienceInvalid               AppError
	DefaultAudienceInvalid        AppError
	GroupNotFound                 AppError
	GroupNameInvalid              AppError
	NotRecordEditor               AppError
	LinkContentNotOwned           AppError
	SealedRecordUnsupported       AppError
	SealedLinksAffected           AppError
	WebhookNotFound               AppError
	WebhookDeliveryNotFound       AppError
	WebhookUrlInvalid             AppError
	WebhookEventsInvalid          AppError
	WebhookLimitReached           AppError
	WebhookDisabled               AppError
}{
	DuplicateWorkspaceMember: AppError{
		ErrorCode: "duplicate_workspace_member",
		ErrorText: "This user is already a member of this workspace.",
	},
	WorkspaceMemberLimitReached: AppError{
		ErrorCode: "workspace_member_limit_reached",
		ErrorText: "This workspace has reached the maximum number of members.",
	},
	FailedToCreateWorkspaceMember: AppError{
		ErrorCode: "failed_to_create_workspace_member",
		ErrorText: "The user could not be added to the workspace.",
	},
	ValidationFieldRestricted: AppError{
		ErrorCode: "validation_insufficient_permissions",
		ErrorText: "Modifying this field is not permitted.",
	},
	ValidationFieldRequired: AppError{
		ErrorCode: "validation_required",
		ErrorText: "A required value is missing.",
	},
	NotAuthorized: AppError{
		ErrorCode: "not_authorized",
		ErrorText: "This request is not permitted.",
	},
	NotAuthenticated: AppError{
		ErrorCode: "not_authenticated",
		ErrorText: "Authentication is required.",
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
		ErrorText: "The maximum number of workspaces has been reached.",
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
		ErrorText: "The selected workspace does not match the active workspace.",
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
		ErrorText: "This link is paused and temporarily unavailable.",
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
		ErrorText: "The download token is invalid or expired. Reopening the link issues a new one.",
	},
	FileNotWatermarkable: AppError{
		ErrorCode: "file_not_watermarkable",
		ErrorText: "This share stamps its files. This file cannot be stamped and is not served.",
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
		ErrorText: "This request is paused and temporarily unavailable.",
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
		ErrorText: "The handshake could not be completed.",
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
		ErrorText: "The selected identity does not belong to this workspace.",
	},
	BookmarkGroupNotOwned: AppError{
		ErrorCode: "bookmark_group_not_owned",
		ErrorText: "A selected group does not belong to this account.",
	},
	ContactRouteMissing: AppError{
		ErrorCode: "contact_route_missing",
		ErrorText: "A contact requires an account, a server or an email address.",
	},
	ContactBlockTargetMissing: AppError{
		ErrorCode: "contact_block_target_missing",
		ErrorText: "A block requires an account, an email address or a domain.",
	},
	ContactNotFound: AppError{
		ErrorCode: "contact_not_found",
		ErrorText: "Contact not found.",
	},
	ContactNothingToSend: AppError{
		ErrorCode: "contact_nothing_to_send",
		ErrorText: "At least one entry must be selected.",
	},
	TemplateNotOwned: AppError{
		ErrorCode: "template_not_owned",
		ErrorText: "The selected template does not belong to this workspace.",
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
		ErrorText: "The creator of this invite can no longer invite members to this workspace.",
	},
	SignupsDisabled: AppError{
		ErrorCode: "signups_disabled",
		ErrorText: "This server does not accept new registrations.",
	},
	InvalidScope: AppError{
		ErrorCode: "invalid_scope",
		ErrorText: "One or more requested API key scopes are unknown.",
	},
	UnknownFeature: AppError{
		ErrorCode: "unknown_feature",
		ErrorText: "One or more requested features are unknown.",
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
		ErrorText: "This action requires a user session; API keys are not accepted.",
	},
	AccessDenied: AppError{
		ErrorCode: "access_denied",
		ErrorText: "This action is not permitted on this record.",
	},
	MissingActiveWorkspace: AppError{
		ErrorCode: "missing_active_workspace",
		ErrorText: "No active workspace is selected for this account.",
	},
	NotWorkspaceMember: AppError{
		ErrorCode: "not_workspace_member",
		ErrorText: "This account is not a member of this workspace.",
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
		ErrorText: "Workspace access does not include this action.",
	},
	PermissionEscalation: AppError{
		ErrorCode: "permission_escalation",
		ErrorText: "Access beyond the granter's own cannot be granted.",
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
		ErrorText: "This account already has access to this workspace.",
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
		ErrorText: "Too many attempts. Retry after a short delay.",
	},
	ApiKeyVaultScope: AppError{
		ErrorCode: "api_key_vault_scope",
		ErrorText: "API keys reach the vault only through assigned sections. At least one section is required.",
	},
	ConnectionClientInvalid: AppError{
		ErrorCode: "connection_client_invalid",
		ErrorText: "A tool must be identified by an https origin (or http on localhost).",
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
		ErrorText: "This connection has expired. The tool must be reconnected from the app.",
	},
	ConnectionNotConnected: AppError{
		ErrorCode: "connection_not_connected",
		ErrorText: "This tool has no active connection to reuse. Connections are made from the app.",
	},
	ConnectionRevokeNotAllowed: AppError{
		ErrorCode: "connection_revoke_not_allowed",
		ErrorText: "The owner has not allowed this tool to revoke links.",
	},
	ConnectionPaused: AppError{
		ErrorCode: "connection_paused",
		ErrorText: "This tool is paused by the owner and works again once reactivated.",
	},
	ConnectionVaultNotAllowed: AppError{
		ErrorCode: "connection_vault_not_allowed",
		ErrorText: "The owner has not allowed this tool to read the vault.",
	},
	ConnectionVaultPolled: AppError{
		ErrorCode: "connection_vault_polled",
		ErrorText: "Vault access requires the answer to be sent to the tool's own address. Tools that poll for it cannot read the vault.",
	},
	ConnectionVaultReconnect: AppError{
		ErrorCode: "connection_vault_reconnect",
		ErrorText: "Vault read access requires reconnecting from the tool.",
	},
	ConnectionNotPermitted: AppError{
		ErrorCode: "connection_not_permitted",
		ErrorText: "The owner has not allowed this tool to do that.",
	},
	ConnectionPolled: AppError{
		ErrorCode: "connection_polled",
		ErrorText: "This action requires the answer to be sent to the tool's own address. Tools that poll for it cannot perform it.",
	},
	ConnectionPermissionInvalid: AppError{
		ErrorCode: "connection_permission_invalid",
		ErrorText: "This permission cannot be granted to a connected tool.",
	},
	VaultNotAllowed: AppError{
		ErrorCode: "vault_not_allowed",
		ErrorText: "This key or tool was not given any part of the vault.",
	},
	VaultReadOnly: AppError{
		ErrorCode: "vault_read_only",
		ErrorText: "Only records written with this key or tool can be changed with it.",
	},
	VaultSectionNotWritable: AppError{
		ErrorCode: "vault_section_not_writable",
		ErrorText: "This key or tool cannot write to that section.",
	},
	VaultSectionInvalid: AppError{
		ErrorCode: "vault_section_invalid",
		ErrorText: "A selected section is not in this workspace.",
	},
	VaultStorageExceeded: AppError{
		ErrorCode: "vault_storage_exceeded",
		ErrorText: "This key or tool has reached its vault storage limit.",
	},
	VaultKeyTaken: AppError{
		ErrorCode: "vault_key_taken",
		ErrorText: "A record with this key already exists.",
	},
	LinkHandOverNotAllowed: AppError{
		ErrorCode: "link_hand_over_not_allowed",
		ErrorText: "The owner has not allowed this tool to receive links.",
	},
	LinkConnectionForeign: AppError{
		ErrorCode: "link_connection_foreign",
		ErrorText: "A link can only name a connection of the same account, and keeps the one it was created with.",
	},
	ConnectionForeign: AppError{
		ErrorCode: "connection_foreign",
		ErrorText: "Only a connected tool of the same account can be selected, and it cannot be changed later.",
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
		ErrorText: "The email address is invalid.",
	},
	PasskeyEmailTaken: AppError{
		ErrorCode: "passkey_email_taken",
		ErrorText: "An account with this email address already exists.",
	},
	PasskeyTicketInvalid: AppError{
		ErrorCode: "passkey_ticket_invalid",
		ErrorText: "This link is unknown, already used, or expired.",
	},
	PasskeyCeremonyInvalid: AppError{
		ErrorCode: "passkey_ceremony_invalid",
		ErrorText: "This attempt timed out or was already completed.",
	},
	PasskeyVerificationFailed: AppError{
		ErrorCode: "passkey_verification_failed",
		ErrorText: "The passkey could not be verified.",
	},
	PasskeyUnknown: AppError{
		ErrorCode: "passkey_unknown",
		ErrorText: "This passkey belongs to no account on this server. It may have been removed, or its account deleted.",
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
		ErrorText: "The only passkey on an account cannot be removed. Another passkey must be added first.",
	},
	TwoFactorRequired: AppError{
		ErrorCode: "two_factor_required",
		ErrorText: "This account asks for a code from its authenticator app before signing in.",
	},
	TwoFactorChallengeInvalid: AppError{
		ErrorCode: "two_factor_challenge_invalid",
		ErrorText: "This sign-in has expired or was already completed. Signing in starts again with the passkey.",
	},
	TwoFactorCodeInvalid: AppError{
		ErrorCode: "two_factor_code_invalid",
		ErrorText: "This code is not the one the authenticator app shows right now.",
	},
	TwoFactorNotEnabled: AppError{
		ErrorCode: "two_factor_not_enabled",
		ErrorText: "Two-factor authentication is not turned on for this account.",
	},
	TwoFactorAlreadyEnabled: AppError{
		ErrorCode: "two_factor_already_enabled",
		ErrorText: "Two-factor authentication is already turned on for this account.",
	},
	TwoFactorNotPending: AppError{
		ErrorCode: "two_factor_not_pending",
		ErrorText: "No authenticator app is being set up. Setting up starts again with a new secret.",
	},
	TwoFactorSetupRequired: AppError{
		ErrorCode: "two_factor_setup_required",
		ErrorText: "This server requires two-factor authentication. Set up an authenticator app first.",
	},
	TwoFactorEnforced: AppError{
		ErrorCode: "two_factor_enforced",
		ErrorText: "This server requires two-factor authentication, so it cannot be turned off.",
	},
	EmailVerificationOff: AppError{
		ErrorCode: "email_verification_off",
		ErrorText: "This server does not confirm email addresses. Accounts are created directly.",
	},
	EmailVerificationRequired: AppError{
		ErrorCode: "email_verification_required",
		ErrorText: "The email address must be confirmed with the code sent to it before the account is created.",
	},
	EmailCodeInvalid: AppError{
		ErrorCode: "email_code_invalid",
		ErrorText: "This code is wrong, expired, or was tried too often.",
	},
	EmailCodeTooSoon: AppError{
		ErrorCode: "email_code_too_soon",
		ErrorText: "A code was just sent to this address. Another can be requested after a minute.",
	},
	EmailSendFailed: AppError{
		ErrorCode: "email_send_failed",
		ErrorText: "The confirmation email could not be sent.",
	},
	ReminderRecordMissing: AppError{
		ErrorCode: "reminder_record_missing",
		ErrorText: "The reminder's entry does not exist or is not in an accessible workspace.",
	},
	ReminderWatchMissing: AppError{
		ErrorCode: "reminder_watch_missing",
		ErrorText: "The watched entry does not exist, or is not in the same workspace.",
	},
	ReminderDueRequired: AppError{
		ErrorCode: "reminder_due_required",
		ErrorText: "A reminder date is required.",
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
		ErrorText: "The other server could not be reached.",
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
		ErrorText: "The sending server's key could not be checked.",
	},
	OIDCRequestInvalid: AppError{
		ErrorCode: "oidc_request_invalid",
		ErrorText: "This sign-in has expired or was already used. It must be restarted from the service.",
	},
	OIDCLinkRecordInvalid: AppError{
		ErrorCode: "oidc_link_record_invalid",
		ErrorText: "A selected entry does not belong to this account.",
	},
	OIDCNameInvalid: AppError{
		ErrorCode: "oidc_name_invalid",
		ErrorText: "This name cannot be used. A name is a plain text entry of this account.",
	},
	OIDCNameTooLong: AppError{
		ErrorCode: "oidc_name_too_long",
		ErrorText: "This name is too long. A name can be at most 200 characters.",
	},
	OIDCSignInPaused: AppError{
		ErrorCode: "oidc_sign_in_paused",
		ErrorText: "This service is paused. Signing in requires reactivating it.",
	},
	AttestationsDisabled: AppError{
		ErrorCode: "attestations_disabled",
		ErrorText: "This server does not issue attestations. Issuing is enabled by its operator.",
	},
	AttestationTypeInvalid: AppError{
		ErrorCode: "attestation_type_invalid",
		ErrorText: "An attestation requires a type of up to 255 characters, without spaces.",
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
		ErrorText: "An offer names its identity by a fingerprint of 64 hexadecimal characters.",
	},
	AttestationImmutable: AppError{
		ErrorCode: "attestation_immutable",
		ErrorText: "An attestation's statement cannot be changed once issued. It can be revoked and reissued.",
	},
	AttestationExpiryInvalid: AppError{
		ErrorCode: "attestation_expiry_invalid",
		ErrorText: "The end date of an attestation or offer must be in the future.",
	},
	AttestationOfferNotFound: AppError{
		ErrorCode: "attestation_offer_not_found",
		ErrorText: "This offer does not exist.",
	},
	AttestationOfferExpired: AppError{
		ErrorCode: "attestation_offer_expired",
		ErrorText: "This offer has expired.",
	},
	AttestationOfferClaimed: AppError{
		ErrorCode: "attestation_offer_claimed",
		ErrorText: "This offer was already accepted. Offers can be accepted once.",
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
		ErrorText: "The credential could not be issued.",
	},
	CredentialInvalid: AppError{
		ErrorCode: "credential_invalid",
		ErrorText: "The credential the issuer returned did not verify, so it was not kept.",
	},
	CredentialNotFound: AppError{
		ErrorCode: "credential_not_found",
		ErrorText: "This credential does not exist.",
	},
	ReissueCredentialInvalid: AppError{
		ErrorCode: "reissue_credential_invalid",
		ErrorText: "This credential was not issued by this server, or cannot be read.",
	},
	ReissueCredentialExpired: AppError{
		ErrorCode: "reissue_credential_expired",
		ErrorText: "This credential has expired. An expired credential is not moved to a new identity.",
	},
	ReissueCredentialRevoked: AppError{
		ErrorCode: "reissue_credential_revoked",
		ErrorText: "This credential was revoked, or already moved to another identity.",
	},
	ReissueVoucherInvalid: AppError{
		ErrorCode: "reissue_voucher_invalid",
		ErrorText: "The key the credential is bound to did not vouch for the new identity.",
	},
	ReissueIdentityMismatch: AppError{
		ErrorCode: "reissue_identity_mismatch",
		ErrorText: "A credential moves only to another identity from the server that issued the current one.",
	},
	ReissueHolderRevoked: AppError{
		ErrorCode: "reissue_holder_revoked",
		ErrorText: "The identity this credential was issued to has been revoked. Its key no longer vouches for another.",
	},
	ReissueHolderUnconfirmed: AppError{
		ErrorCode: "reissue_holder_unconfirmed",
		ErrorText: "The server of the identity this credential was issued to could not confirm that it still stands.",
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
		ErrorText: "This check does not exist. The link may be incomplete.",
	},
	AttestationCheckClosed: AppError{
		ErrorCode: "attestation_check_closed",
		ErrorText: "This check was already answered or has expired.",
	},
	AttestationShareInvalid: AppError{
		ErrorCode: "attestation_share_invalid",
		ErrorText: "A share link names one of your attestations and how many days it stays open, from 1 to 90.",
	},
	AttestationShareNotFound: AppError{
		ErrorCode: "attestation_share_not_found",
		ErrorText: "This link does not exist. It may be incomplete.",
	},
	AttestationShareClosed: AppError{
		ErrorCode: "attestation_share_closed",
		ErrorText: "This link was ended by the person who shared it, or has expired.",
	},
	SealedFieldsRestricted: AppError{
		ErrorCode: "sealed_fields_restricted",
		ErrorText: "This entry is end-to-end encrypted. Changing it requires a newer app version.",
	},
	SealedInvalid: AppError{
		ErrorCode: "sealed_invalid",
		ErrorText: "This encrypted data is not in the expected form.",
	},
	SealedVersionConflict: AppError{
		ErrorCode: "sealed_version_conflict",
		ErrorText: "This was changed on another device first. Reload and retry.",
	},
	SealedEpochStale: AppError{
		ErrorCode: "sealed_epoch_stale",
		ErrorText: "This workspace's encryption key has changed. Reload and retry.",
	},
	SealedKeyMissing: AppError{
		ErrorCode: "sealed_key_missing",
		ErrorText: "The encryption key for this workspace is not available.",
	},
	SealedIdentityKeysPending: AppError{
		ErrorCode: "sealed_identity_keys_pending",
		ErrorText: "Some identity keys in this workspace are still under its encryption key. They move by themselves once their owners open the app.",
	},
	SectionShareByPersonOnly: AppError{
		ErrorCode: "section_share_by_person_only",
		ErrorText: "Only the section's owner can share it with members, from the app.",
	},
	AudienceByOwnerOnly: AppError{
		ErrorCode: "audience_by_owner_only",
		ErrorText: "Only the owner can change who sees this, from the app.",
	},
	AudienceInvalid: AppError{
		ErrorCode: "audience_invalid",
		ErrorText: "The audience must be private, workspace or groups of this workspace.",
	},
	DefaultAudienceInvalid: AppError{
		ErrorCode: "default_audience_invalid",
		ErrorText: "Defaults name sections, links, requests, templates, contacts or attestations, each private or workspace.",
	},
	GroupNotFound: AppError{
		ErrorCode: "group_not_found",
		ErrorText: "Group not found.",
	},
	GroupNameInvalid: AppError{
		ErrorCode: "group_name_invalid",
		ErrorText: "A group's name is 1 to 80 characters.",
	},
	NotRecordEditor: AppError{
		ErrorCode: "not_record_editor",
		ErrorText: "This item can be changed only by its owner and the members it is opened to for editing.",
	},
	LinkContentNotOwned: AppError{
		ErrorCode: "link_content_not_owned",
		ErrorText: "A share can hold only the creator's own records and sections.",
	},
	SealedRecordUnsupported: AppError{
		ErrorCode: "sealed_record_unsupported",
		ErrorText: "End-to-end encrypted entries are not supported here yet.",
	},
	SealedLinksAffected: AppError{
		ErrorCode: "sealed_links_affected",
		ErrorText: "This entry is shared by links, which would stop showing it once encrypted.",
	},
	WebhookNotFound: AppError{
		ErrorCode: "webhook_not_found",
		ErrorText: "Webhook not found.",
	},
	WebhookDeliveryNotFound: AppError{
		ErrorCode: "webhook_delivery_not_found",
		ErrorText: "Delivery not found.",
	},
	WebhookUrlInvalid: AppError{
		ErrorCode: "webhook_url_invalid",
		ErrorText: "A full http:// or https:// address reachable by this server is required.",
	},
	WebhookEventsInvalid: AppError{
		ErrorCode: "webhook_events_invalid",
		ErrorText: "At least one event from the event list is required.",
	},
	WebhookLimitReached: AppError{
		ErrorCode: "webhook_limit_reached",
		ErrorText: "This workspace has reached its webhook limit.",
	},
	WebhookDisabled: AppError{
		ErrorCode: "webhook_disabled",
		ErrorText: "This webhook is disabled.",
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
