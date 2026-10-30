import 'package:revoked_app/core/network/api_client.dart';

/// Stable error codes emitted by the backend (`util/errors.go`).
abstract class AppErrorCode {
  static const notAuthorized = 'not_authorized';
  static const notAuthenticated = 'not_authenticated';
  static const duplicateWorkspaceMember = 'duplicate_workspace_member';
  static const workspaceMemberLimitReached = 'workspace_member_limit_reached';
  static const personalWorkspaceLimitReached =
      'personal_workspace_limit_reached';
  static const businessWorkspaceLimitReached =
      'business_workspace_limit_reached';
  static const failedToCreateWorkspaceMember =
      'failed_to_create_workspace_member';
  static const failedToCreateRecord = 'failed_to_create_record';
  static const forbiddenWorkspaceAccess = 'forbidden_workspace_access';
  static const invalidActiveWorkspace = 'invalid_active_workspace';
  static const activeWorkspaceMismatch = 'active_workspace_mismatch';
  static const workspaceNotFound = 'workspace_not_found';

  static const missingPermission = 'missing_permission';
  static const permissionEscalation = 'permission_escalation';
  static const lastAdminProtected = 'last_admin_protected';
  static const accessDenied = 'access_denied';
  static const invalidScope = 'invalid_scope';
  static const invalidApiKey = 'invalid_api_key';
  static const inviteNotFound = 'invite_not_found';
  static const inviteExpired = 'invite_expired';
  static const inviteRevoked = 'invite_revoked';
  static const inviteExhausted = 'invite_exhausted';
  static const inviteWrongAccount = 'invite_wrong_account';
  static const alreadyWorkspaceMember = 'already_workspace_member';
  static const invitesNotForPersonal = 'invites_not_for_personal';
  static const userNotFound = 'user_not_found';
  static const signupsDisabled = 'signups_disabled';

  /// Raised by the client itself when a request exceeds [ApiClient.timeout].
  static const requestTimeout = 'request_timeout';
  static const duplicateValues = 'duplicate_values';
  static const validationRequired = 'validation_required';
  static const validationInsufficientPermissions =
      'validation_insufficient_permissions';

  static const linkNotFound = 'link_not_found';
  static const linkRevoked = 'link_revoked';
  static const linkExpired = 'link_expired';
  static const linkPaused = 'link_paused';
  static const linkMaxViewsReached = 'link_max_views_reached';
  static const linkPasswordRequired = 'link_password_required';
  static const linkPasswordInvalid = 'link_password_invalid';

  static const requestNotFound = 'request_not_found';
  static const requestRevoked = 'request_revoked';
  static const requestExpired = 'request_expired';
  static const requestPaused = 'request_paused';
  static const requestCompleted = 'request_completed';
  static const requestPasswordRequired = 'request_password_required';
  static const requestPasswordInvalid = 'request_password_invalid';
  static const requestIdentifierMissing = 'request_identifier_missing';
  static const requestAccountRequired = 'request_account_required';

  static const handshakeRequired = 'handshake_required';
  static const handshakeInvalid = 'handshake_invalid';
  static const handshakeFailed = 'handshake_failed';
  static const identityNotFound = 'identity_not_found';
  static const identityRequired = 'identity_required';
  static const identityRevoked = 'identity_revoked';
  static const identityFingerprintInvalid = 'identity_fingerprint_invalid';
  static const invalidCertificate = 'invalid_certificate';

  static const bookmarkGroupNotOwned = 'bookmark_group_not_owned';
  static const fileNotWatermarkable = 'file_not_watermarkable';
  static const applicationNeedsWatermark = 'application_needs_watermark';
  static const recordNotFound = 'record_not_found';
  static const watermarkTextInvalid = 'watermark_text_invalid';
  static const archiveEmpty = 'archive_empty';

  static const attestationsDisabled = 'attestations_disabled';
  static const attestationOfferNotFound = 'attestation_offer_not_found';
  static const attestationOfferExpired = 'attestation_offer_expired';
  static const attestationOfferClaimed = 'attestation_offer_claimed';
  static const attestationOfferRevoked = 'attestation_offer_revoked';
  static const attestationIdentityMismatch = 'attestation_identity_mismatch';
  static const attestationKeyUnsupported = 'attestation_key_unsupported';
  static const credentialInvalid = 'credential_invalid';
  static const attestationCheckInvalid = 'attestation_check_invalid';
  static const attestationCheckNotFound = 'attestation_check_not_found';
  static const attestationCheckClosed = 'attestation_check_closed';
  static const remoteIdentityInvalid = 'remote_identity_invalid';
}

/// Translates an [ApiException] into a short, user-friendly message and a
/// flag indicating whether the issue is terminal (i.e. retrying without
/// user input cannot recover).
class AppErrorMessage {
  /// Short, user-friendly title.
  final String title;

  /// Longer description shown as toast subtitle.
  final String description;

  /// Whether this error is "soft" — i.e. the user can correct it (wrong
  /// password, missing identifier) — vs. terminal (revoked, expired).
  final bool isTerminal;

  /// Whether the user should re-authenticate.
  final bool isAuthError;

  /// The original error code, if any.
  final String code;

  const AppErrorMessage({
    required this.title,
    required this.description,
    required this.code,
    this.isTerminal = false,
    this.isAuthError = false,
  });

  /// Build a user-friendly message from an arbitrary exception.
  factory AppErrorMessage.fromException(Object error) {
    if (error is ApiException) {
      return _mapApiException(error);
    }
    return AppErrorMessage(
      title: 'Something went wrong',
      description: error.toString(),
      code: '',
    );
  }

  static AppErrorMessage _mapApiException(ApiException e) {
    switch (e.code) {
      case AppErrorCode.inviteNotFound:
        return AppErrorMessage(
          title: 'Invite not found',
          description:
              'This invite key isn\'t valid. Check that you copied all of it.',
          code: e.code,
          isTerminal: true,
        );
      case AppErrorCode.inviteExpired:
        return AppErrorMessage(
          title: 'Invite expired',
          description: 'This invite has run out. Ask for a new one.',
          code: e.code,
          isTerminal: true,
        );
      case AppErrorCode.inviteRevoked:
        return AppErrorMessage(
          title: 'Invite withdrawn',
          description: 'The workspace withdrew this invite. Ask for a new one.',
          code: e.code,
          isTerminal: true,
        );
      case AppErrorCode.inviteExhausted:
        return AppErrorMessage(
          title: 'Invite already used',
          description: 'Someone already used this invite. Ask for a new one.',
          code: e.code,
          isTerminal: true,
        );
      case AppErrorCode.inviteWrongAccount:
        return AppErrorMessage(
          title: 'Wrong account',
          description:
              'This invite is for a different email address. Sign in with that account to accept it.',
          code: e.code,
          isTerminal: true,
        );
      case AppErrorCode.alreadyWorkspaceMember:
        return AppErrorMessage(
          title: 'Already a member',
          description: 'You already have access to this workspace.',
          code: e.code,
          isTerminal: true,
        );
      case AppErrorCode.invitesNotForPersonal:
        return AppErrorMessage(
          title: 'Personal workspaces are private',
          description:
              'A personal workspace is just for you. Create a shared workspace to work with others.',
          code: e.code,
        );

      case AppErrorCode.signupsDisabled:
        return AppErrorMessage(
          title: 'Signups are closed',
          description:
              'This server isn\'t taking new accounts. Ask the person who runs it for an invite.',
          code: e.code,
          isTerminal: true,
        );

      case AppErrorCode.invalidActiveWorkspace:
        return AppErrorMessage(
          title: 'No active workspace',
          description: 'Pick a workspace first. You find yours in Settings.',
          code: e.code,
        );
      case AppErrorCode.activeWorkspaceMismatch:
      case AppErrorCode.forbiddenWorkspaceAccess:
        return AppErrorMessage(
          title: 'Wrong workspace',
          description:
              'This belongs to another workspace. Switch to it and try '
              'again.',
          code: e.code,
        );
      case AppErrorCode.workspaceNotFound:
        return AppErrorMessage(
          title: 'Workspace not found',
          description: 'It may have been deleted, or you\'re no longer in it.',
          code: e.code,
          isTerminal: true,
        );
      case AppErrorCode.personalWorkspaceLimitReached:
      case AppErrorCode.businessWorkspaceLimitReached:
        return AppErrorMessage(
          title: 'Workspace limit reached',
          description: 'You\'ve created as many workspaces as you can.',
          code: e.code,
        );
      case AppErrorCode.failedToCreateWorkspaceMember:
        return AppErrorMessage(
          title: 'Couldn\'t add the member',
          description: 'Something went wrong. Try again.',
          code: e.code,
        );
      case AppErrorCode.failedToCreateRecord:
        return AppErrorMessage(
          title: 'Couldn\'t save',
          description: 'Check what you entered and try again.',
          code: e.code,
        );
      case AppErrorCode.userNotFound:
        return AppErrorMessage(
          title: 'Account not found',
          description: 'There\'s no account with that address.',
          code: e.code,
          isTerminal: true,
        );
      case AppErrorCode.validationInsufficientPermissions:
        return AppErrorMessage(
          title: 'Not enough permission',
          description:
              'You can only give access you have yourself. Ask an '
              'admin.',
          code: e.code,
        );
      case AppErrorCode.requestTimeout:
        return AppErrorMessage(
          title: 'The server didn\'t answer',
          description:
              'It may be down or busy. Check the server address in settings, '
              'then try again.',
          code: e.code,
        );

      case AppErrorCode.missingPermission:
      case AppErrorCode.accessDenied:
        return AppErrorMessage(
          title: 'Not permitted',
          description:
              'You don\'t have access to do this in this workspace. Ask an admin.',
          code: e.code,
        );
      case AppErrorCode.permissionEscalation:
        return AppErrorMessage(
          title: 'Can\'t give that access',
          description:
              'You can only give access you have yourself. Remove the ones you don\'t have.',
          code: e.code,
        );
      case AppErrorCode.lastAdminProtected:
        return AppErrorMessage(
          title: 'Last admin',
          description:
              'Someone has to be able to manage members. Give another member that permission first.',
          code: e.code,
        );
      case AppErrorCode.invalidScope:
        return AppErrorMessage(
          title: 'Unknown permission',
          description: 'One of these permissions doesn\'t exist.',
          code: e.code,
        );
      case AppErrorCode.invalidApiKey:
        return AppErrorMessage(
          title: 'Invalid API key',
          description: 'This API key isn\'t valid.',
          code: e.code,
          isAuthError: true,
        );

      case AppErrorCode.linkNotFound:
        return AppErrorMessage(
          title: 'Link not found',
          description: 'This link doesn\'t exist or was removed.',
          code: e.code,
          isTerminal: true,
        );
      case AppErrorCode.linkRevoked:
        return AppErrorMessage(
          title: 'Link revoked',
          description: 'Its owner revoked this link. It no longer works.',
          code: e.code,
          isTerminal: true,
        );
      case AppErrorCode.linkExpired:
        return AppErrorMessage(
          title: 'Link expired',
          description: 'This link has expired.',
          code: e.code,
          isTerminal: true,
        );
      case AppErrorCode.linkPaused:
        return AppErrorMessage(
          title: 'Link paused',
          description: 'Its owner paused this link. It may work again later.',
          code: e.code,
        );
      case AppErrorCode.linkMaxViewsReached:
        return AppErrorMessage(
          title: 'View limit reached',
          description:
              'This link was opened as often as allowed, so it stopped working.',
          code: e.code,
          isTerminal: true,
        );
      case AppErrorCode.linkPasswordRequired:
        return AppErrorMessage(
          title: 'Password required',
          description: 'Enter the password you got from the sender.',
          code: e.code,
        );
      case AppErrorCode.linkPasswordInvalid:
        return AppErrorMessage(
          title: 'Wrong password',
          description: 'That password is wrong. Try again.',
          code: e.code,
        );

      case AppErrorCode.requestNotFound:
        return AppErrorMessage(
          title: 'Request not found',
          description: 'This request doesn\'t exist.',
          code: e.code,
          isTerminal: true,
        );
      case AppErrorCode.requestRevoked:
        return AppErrorMessage(
          title: 'Request revoked',
          description: 'Its owner revoked this request.',
          code: e.code,
          isTerminal: true,
        );
      case AppErrorCode.requestExpired:
        return AppErrorMessage(
          title: 'Request expired',
          description:
              'This request has expired. You can\'t answer it anymore.',
          code: e.code,
          isTerminal: true,
        );
      case AppErrorCode.requestPaused:
        return AppErrorMessage(
          title: 'Request paused',
          description:
              'Its owner paused this request. It may open again later.',
          code: e.code,
        );
      case AppErrorCode.requestCompleted:
        return AppErrorMessage(
          title: 'Request completed',
          description:
              'This request has all the answers it needs, so it\'s closed.',
          code: e.code,
          isTerminal: true,
        );
      case AppErrorCode.requestPasswordRequired:
        return AppErrorMessage(
          title: 'Password required',
          description: 'Enter the password you got from the sender to answer.',
          code: e.code,
        );
      case AppErrorCode.requestPasswordInvalid:
        return AppErrorMessage(
          title: 'Wrong password',
          description: 'That password is wrong. Try again.',
          code: e.code,
        );
      case AppErrorCode.requestIdentifierMissing:
        return AppErrorMessage(
          title: 'Identifier required',
          description: 'Enter the identifier the sender gave you.',
          code: e.code,
        );
      case AppErrorCode.requestAccountRequired:
        return AppErrorMessage(
          title: 'Account required',
          description:
              'Sign in or create an account on this server to answer. That '
              'way your answer stays under your control.',
          code: e.code,
        );

      case AppErrorCode.handshakeRequired:
        return AppErrorMessage(
          title: 'Start again from the link',
          description: 'Open the link again to continue.',
          code: e.code,
        );
      case AppErrorCode.handshakeInvalid:
        return AppErrorMessage(
          title: 'Identity doesn\'t match',
          description:
              'This doesn\'t match the identity you used before. Try a different one.',
          code: e.code,
        );
      case AppErrorCode.identityRequired:
        return AppErrorMessage(
          title: 'Identity required',
          description: 'Pick an identity to continue.',
          code: e.code,
        );
      case AppErrorCode.identityNotFound:
        return AppErrorMessage(
          title: 'Identity not found',
          description: 'The identity you picked no longer exists.',
          code: e.code,
        );
      case AppErrorCode.fileNotWatermarkable:
        return AppErrorMessage(
          title: 'File not available',
          description:
              'This share adds a watermark to its files, and this file type '
              'can\'t take one, so it isn\'t shared.',
          code: e.code,
          isTerminal: true,
        );
      case AppErrorCode.applicationNeedsWatermark:
        return AppErrorMessage(
          title: 'Watermark required',
          description:
              'Application links always watermark their files. Turn the '
              'watermark on to save.',
          code: e.code,
          isTerminal: true,
        );
      case AppErrorCode.recordNotFound:
        return AppErrorMessage(
          title: 'Record not found',
          description: 'This record doesn\'t exist, or it isn\'t yours.',
          code: e.code,
          isTerminal: true,
        );
      case AppErrorCode.watermarkTextInvalid:
        return AppErrorMessage(
          title: 'Watermark text too long',
          description: 'Use one line of 1 to 120 characters.',
          code: e.code,
        );
      case AppErrorCode.archiveEmpty:
        return AppErrorMessage(
          title: 'Nothing to download',
          description: 'None of the files in this share can go in a download.',
          code: e.code,
          isTerminal: true,
        );
      case AppErrorCode.bookmarkGroupNotOwned:
        return AppErrorMessage(
          title: 'Group not found',
          description:
              'That group isn\'t in your bookmarks anymore. Reload and pick '
              'again.',
          code: e.code,
        );
      case AppErrorCode.identityRevoked:
        return AppErrorMessage(
          title: 'Identity revoked',
          description:
              'The server that issued this identity withdrew it. It can no '
              'longer sign for that domain. Create a new one.',
          code: e.code,
          isTerminal: true,
        );
      case AppErrorCode.attestationsDisabled:
        return AppErrorMessage(
          title: 'This server doesn\'t issue attestations',
          description:
              'An attestation speaks for the server\'s domain, so the '
              'person who runs it decides.',
          code: e.code,
          isTerminal: true,
        );
      case AppErrorCode.attestationOfferNotFound:
        return AppErrorMessage(
          title: 'Offer not found',
          description:
              'This link doesn\'t lead to an attestation. Check that you '
              'copied all of it.',
          code: e.code,
          isTerminal: true,
        );
      case AppErrorCode.attestationOfferExpired:
        return AppErrorMessage(
          title: 'Offer expired',
          description: 'This offer has expired. Ask its issuer for a new one.',
          code: e.code,
          isTerminal: true,
        );
      case AppErrorCode.attestationOfferClaimed:
        return AppErrorMessage(
          title: 'Already accepted',
          description:
              'Someone accepted this offer with another identity. An offer '
              'works for one identity only.',
          code: e.code,
          isTerminal: true,
        );
      case AppErrorCode.attestationOfferRevoked:
        return AppErrorMessage(
          title: 'Offer withdrawn',
          description: 'The issuer withdrew this offer.',
          code: e.code,
          isTerminal: true,
        );
      case AppErrorCode.attestationIdentityMismatch:
        return AppErrorMessage(
          title: 'Made for another identity',
          description:
              'This offer is for a different identity than the one you '
              'picked.',
          code: e.code,
        );
      case AppErrorCode.attestationKeyUnsupported:
        return AppErrorMessage(
          title: 'This identity can\'t hold it',
          description:
              'This identity\'s key can\'t hold an attestation. A new '
              'identity can.',
          code: e.code,
        );
      case AppErrorCode.credentialInvalid:
        return AppErrorMessage(
          title: 'Attestation not saved',
          description:
              'What the issuer sent back didn\'t check out, so it wasn\'t '
              'saved. Try again once the issuer\'s domain is verified.',
          code: e.code,
        );
      case AppErrorCode.attestationCheckInvalid:
        return AppErrorMessage(
          title: 'You can\'t ask for that',
          description:
              'Use one word for the kind, like membership, a website like '
              'club.example for who confirms it, and only letters, digits '
              'and underscores for each detail.',
          code: e.code,
        );
      case AppErrorCode.attestationCheckNotFound:
        return AppErrorMessage(
          title: 'Check not found',
          description:
              'This link doesn\'t lead to a request to see an attestation. '
              'Check that you copied all of it.',
          code: e.code,
          isTerminal: true,
        );
      case AppErrorCode.attestationCheckClosed:
        return AppErrorMessage(
          title: 'No longer open',
          description:
              'Someone already answered it, or its ten minutes ran out. Ask '
              'whoever showed it to you for a new one.',
          code: e.code,
          isTerminal: true,
        );
      case AppErrorCode.remoteIdentityInvalid:
        return AppErrorMessage(
          title: 'Identity not confirmed',
          description:
              'The other server couldn\'t check this identity with the '
              'server that issued it. That server\'s domain must be '
              'verified and online.',
          code: e.code,
        );
      case AppErrorCode.identityFingerprintInvalid:
        return AppErrorMessage(
          title: 'Invalid fingerprint',
          description: 'That doesn\'t look like an identity fingerprint.',
          code: e.code,
        );
      case AppErrorCode.handshakeFailed:
        return AppErrorMessage(
          title: 'Couldn\'t connect safely',
          description: 'Something went wrong while checking. Try again.',
          code: e.code,
        );
      case AppErrorCode.invalidCertificate:
        return AppErrorMessage(
          title: 'Certificate not valid',
          description: 'This certificate didn\'t check out.',
          code: e.code,
        );

      case AppErrorCode.notAuthenticated:
        return AppErrorMessage(
          title: 'Sign in',
          description: 'Sign in to do this.',
          code: e.code,
          isAuthError: true,
        );
      case AppErrorCode.notAuthorized:
        return AppErrorMessage(
          title: 'Not allowed',
          description: 'You don\'t have access to do this.',
          code: e.code,
        );
      case AppErrorCode.duplicateValues:
        return AppErrorMessage(
          title: 'Already exists',
          description: 'Something with these values already exists.',
          code: e.code,
        );
      case AppErrorCode.validationRequired:
        return AppErrorMessage(
          title: 'Missing required value',
          description: e.message,
          code: e.code,
        );
      case AppErrorCode.duplicateWorkspaceMember:
        return AppErrorMessage(
          title: 'Already a member',
          description: 'This person is already in this workspace.',
          code: e.code,
        );
      case AppErrorCode.workspaceMemberLimitReached:
        return AppErrorMessage(
          title: 'Member limit reached',
          description:
              'This workspace is full. Remove a member to add someone new.',
          code: e.code,
        );
    }

    // Fallback for un-coded errors. Use HTTP status to give *some* hint.
    switch (e.statusCode) {
      case 401:
        return AppErrorMessage(
          title: 'Sign in',
          description: e.message,
          code: e.code,
          isAuthError: true,
        );
      case 403:
        return AppErrorMessage(
          title: 'Not allowed',
          description: e.message,
          code: e.code,
        );
      case 404:
        return AppErrorMessage(
          title: 'Not found',
          description: e.message,
          code: e.code,
        );
      case 410:
        return AppErrorMessage(
          title: 'No longer available',
          description: e.message,
          code: e.code,
          isTerminal: true,
        );
      default:
        return AppErrorMessage(
          title: 'Something went wrong',
          description: e.message,
          code: e.code,
        );
    }
  }
}
