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

  static const handshakeRequired = 'handshake_required';
  static const handshakeInvalid = 'handshake_invalid';
  static const identityNotFound = 'identity_not_found';
  static const identityRequired = 'identity_required';
  static const invalidCertificate = 'invalid_certificate';
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
              'This invite key is not valid. Check that it was copied in full.',
          code: e.code,
          isTerminal: true,
        );
      case AppErrorCode.inviteExpired:
        return AppErrorMessage(
          title: 'Invite expired',
          description: 'This invite is no longer valid. Ask for a new one.',
          code: e.code,
          isTerminal: true,
        );
      case AppErrorCode.inviteRevoked:
        return AppErrorMessage(
          title: 'Invite withdrawn',
          description:
              'This invite was withdrawn by the workspace. Ask for a new one.',
          code: e.code,
          isTerminal: true,
        );
      case AppErrorCode.inviteExhausted:
        return AppErrorMessage(
          title: 'Invite already used',
          description: 'This invite has already been used. Ask for a new one.',
          code: e.code,
          isTerminal: true,
        );
      case AppErrorCode.inviteWrongAccount:
        return AppErrorMessage(
          title: 'Wrong account',
          description:
              'This invite was issued for a different email address. Sign in with that account to accept it.',
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
              'A personal workspace holds one person. Create an organisation workspace to work with others.',
          code: e.code,
        );

      case AppErrorCode.signupsDisabled:
        return AppErrorMessage(
          title: 'This server is invite-only',
          description: 'Account creations are disabled by the operator. ',
          code: e.code,
          isTerminal: true,
        );

      case AppErrorCode.invalidActiveWorkspace:
        return AppErrorMessage(
          title: 'No active workspace',
          description:
              'Pick a workspace before doing this. Settings lists the ones '
              'you belong to.',
          code: e.code,
        );
      case AppErrorCode.activeWorkspaceMismatch:
      case AppErrorCode.forbiddenWorkspaceAccess:
        return AppErrorMessage(
          title: 'Wrong workspace',
          description:
              'This belongs to a different workspace than the one you have '
              'active. Switch to it and try again.',
          code: e.code,
        );
      case AppErrorCode.workspaceNotFound:
        return AppErrorMessage(
          title: 'Workspace not found',
          description:
              'It may have been deleted, or you no longer belong to '
              'it.',
          code: e.code,
          isTerminal: true,
        );
      case AppErrorCode.personalWorkspaceLimitReached:
      case AppErrorCode.businessWorkspaceLimitReached:
        return AppErrorMessage(
          title: 'Workspace limit reached',
          description:
              'This account already has as many workspaces as it may create.',
          code: e.code,
        );
      case AppErrorCode.failedToCreateWorkspaceMember:
        return AppErrorMessage(
          title: 'Could not add the member',
          description:
              'The workspace membership could not be created. Try '
              'again.',
          code: e.code,
        );
      case AppErrorCode.failedToCreateRecord:
        return AppErrorMessage(
          title: 'Could not save',
          description:
              'The server refused to store this. Check the fields '
              'and try again.',
          code: e.code,
        );
      case AppErrorCode.userNotFound:
        return AppErrorMessage(
          title: 'Account not found',
          description: 'No account exists for that address.',
          code: e.code,
          isTerminal: true,
        );
      case AppErrorCode.validationInsufficientPermissions:
        return AppErrorMessage(
          title: 'Not enough permission',
          description:
              'You cannot grant access you do not hold yourself. Ask an '
              'administrator.',
          code: e.code,
        );
      case AppErrorCode.requestTimeout:
        return AppErrorMessage(
          title: 'The server did not respond',
          description:
              'It may be unreachable or overloaded. Check the server address '
              'in settings, then try again.',
          code: e.code,
        );

      case AppErrorCode.missingPermission:
      case AppErrorCode.accessDenied:
        return AppErrorMessage(
          title: 'Not permitted',
          description:
              'Your access to this workspace does not cover this action. An administrator can grant it.',
          code: e.code,
        );
      case AppErrorCode.permissionEscalation:
        return AppErrorMessage(
          title: 'Cannot grant that',
          description:
              'You can only pass on access you hold yourself. Remove the permissions you do not have.',
          code: e.code,
        );
      case AppErrorCode.lastAdminProtected:
        return AppErrorMessage(
          title: 'Last administrator',
          description:
              'Someone must be able to manage members, or nobody could restore access. Give another member that permission first.',
          code: e.code,
        );
      case AppErrorCode.invalidScope:
        return AppErrorMessage(
          title: 'Unknown permission',
          description: 'One of the requested permissions is not recognised.',
          code: e.code,
        );
      case AppErrorCode.invalidApiKey:
        return AppErrorMessage(
          title: 'Invalid API key',
          description: 'The supplied API key is not valid.',
          code: e.code,
          isAuthError: true,
        );

      case AppErrorCode.linkNotFound:
        return AppErrorMessage(
          title: 'Link not found',
          description:
              'The link you are trying to open does not exist or has been removed.',
          code: e.code,
          isTerminal: true,
        );
      case AppErrorCode.linkRevoked:
        return AppErrorMessage(
          title: 'Link revoked',
          description:
              'This link has been revoked by its owner and can no longer be used.',
          code: e.code,
          isTerminal: true,
        );
      case AppErrorCode.linkExpired:
        return AppErrorMessage(
          title: 'Link expired',
          description:
              'This link is past its expiry date and no longer grants access.',
          code: e.code,
          isTerminal: true,
        );
      case AppErrorCode.linkPaused:
        return AppErrorMessage(
          title: 'Link paused',
          description:
              'This link is paused by its owner. It is temporarily unavailable and may come back.',
          code: e.code,
        );
      case AppErrorCode.linkMaxViewsReached:
        return AppErrorMessage(
          title: 'View limit reached',
          description:
              'This link reached its maximum number of views and was automatically revoked.',
          code: e.code,
          isTerminal: true,
        );
      case AppErrorCode.linkPasswordRequired:
        return AppErrorMessage(
          title: 'Password required',
          description:
              'Enter the password the sender provided to view this link.',
          code: e.code,
        );
      case AppErrorCode.linkPasswordInvalid:
        return AppErrorMessage(
          title: 'Wrong password',
          description:
              'The password you entered does not match. Please try again.',
          code: e.code,
        );

      case AppErrorCode.requestNotFound:
        return AppErrorMessage(
          title: 'Request not found',
          description:
              'The request you are trying to respond to does not exist.',
          code: e.code,
          isTerminal: true,
        );
      case AppErrorCode.requestRevoked:
        return AppErrorMessage(
          title: 'Request revoked',
          description: 'This request has been revoked by its owner.',
          code: e.code,
          isTerminal: true,
        );
      case AppErrorCode.requestExpired:
        return AppErrorMessage(
          title: 'Request expired',
          description:
              'This request is past its expiry date and no longer accepts submissions.',
          code: e.code,
          isTerminal: true,
        );
      case AppErrorCode.requestPaused:
        return AppErrorMessage(
          title: 'Request paused',
          description:
              'This request is paused by its owner. It is temporarily unavailable and may come back.',
          code: e.code,
        );
      case AppErrorCode.requestCompleted:
        return AppErrorMessage(
          title: 'Request completed',
          description:
              'This request reached its maximum response count and is now closed.',
          code: e.code,
          isTerminal: true,
        );
      case AppErrorCode.requestPasswordRequired:
        return AppErrorMessage(
          title: 'Password required',
          description: 'A password is required to submit data to this request.',
          code: e.code,
        );
      case AppErrorCode.requestPasswordInvalid:
        return AppErrorMessage(
          title: 'Wrong password',
          description: 'The password you entered is incorrect.',
          code: e.code,
        );
      case AppErrorCode.requestIdentifierMissing:
        return AppErrorMessage(
          title: 'Identifier required',
          description:
              'You need to provide the identifier the sender gave you.',
          code: e.code,
        );

      case AppErrorCode.handshakeRequired:
        return AppErrorMessage(
          title: 'Handshake required',
          description:
              'A handshake token from your first visit is required to continue.',
          code: e.code,
        );
      case AppErrorCode.handshakeInvalid:
        return AppErrorMessage(
          title: 'Handshake mismatch',
          description:
              'Your stored handshake does not match the one on file. Try with a different identity.',
          code: e.code,
        );
      case AppErrorCode.identityRequired:
        return AppErrorMessage(
          title: 'Identity required',
          description:
              'You need to select a cryptographic identity to continue.',
          code: e.code,
        );
      case AppErrorCode.identityNotFound:
        return AppErrorMessage(
          title: 'Identity not found',
          description: 'The identity you selected no longer exists.',
          code: e.code,
        );
      case AppErrorCode.invalidCertificate:
        return AppErrorMessage(
          title: 'Invalid certificate',
          description: 'The certificate could not be validated.',
          code: e.code,
        );

      case AppErrorCode.notAuthenticated:
        return AppErrorMessage(
          title: 'Please sign in',
          description: 'You need to be signed in to perform this action.',
          code: e.code,
          isAuthError: true,
        );
      case AppErrorCode.notAuthorized:
        return AppErrorMessage(
          title: 'Not allowed',
          description: 'You do not have permission to perform this action.',
          code: e.code,
        );
      case AppErrorCode.duplicateValues:
        return AppErrorMessage(
          title: 'Already exists',
          description: 'A record with these values already exists.',
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
          description: 'This user is already a member of this workspace.',
          code: e.code,
        );
      case AppErrorCode.workspaceMemberLimitReached:
        return AppErrorMessage(
          title: 'Member limit reached',
          description:
              'This workspace has reached its maximum number of members.',
          code: e.code,
        );
    }

    // Fallback for un-coded errors. Use HTTP status to give *some* hint.
    switch (e.statusCode) {
      case 401:
        return AppErrorMessage(
          title: 'Please sign in',
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
          title: 'Request failed',
          description: e.message,
          code: e.code,
        );
    }
  }
}
