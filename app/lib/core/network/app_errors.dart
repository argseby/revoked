import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:revoked_app/core/crypto/sealing.dart';
import 'package:revoked_app/core/network/api_client.dart';
import 'package:revoked_app/core/services/device_unlock.dart';
import 'package:revoked_app/features/connections/sign_in_approval.dart';

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

  static const twoFactorRequired = 'two_factor_required';
  static const twoFactorChallengeInvalid = 'two_factor_challenge_invalid';
  static const twoFactorCodeInvalid = 'two_factor_code_invalid';
  static const twoFactorEnforced = 'two_factor_enforced';
  static const twoFactorSetupRequired = 'two_factor_setup_required';

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

  static const connectionPaused = 'connection_paused';
  static const oidcSignInPaused = 'oidc_sign_in_paused';

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
  static const contactRouteMissing = 'contact_route_missing';
  static const contactNotFound = 'contact_not_found';
  static const contactNothingToSend = 'contact_nothing_to_send';
  static const templateNotOwned = 'template_not_owned';
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
  static const sealedFieldsRestricted = 'sealed_fields_restricted';
  static const sealedInvalid = 'sealed_invalid';
  static const sealedVersionConflict = 'sealed_version_conflict';
  static const sealedEpochStale = 'sealed_epoch_stale';
  static const sealedKeyMissing = 'sealed_key_missing';

  static const webhookNotFound = 'webhook_not_found';
  static const webhookDeliveryNotFound = 'webhook_delivery_not_found';
  static const webhookUrlInvalid = 'webhook_url_invalid';
  static const webhookEventsInvalid = 'webhook_events_invalid';
  static const webhookLimitReached = 'webhook_limit_reached';
  static const webhookDisabled = 'webhook_disabled';
  static const sealedRecordUnsupported = 'sealed_record_unsupported';
  static const sealedLinksAffected = 'sealed_links_affected';
  static const sealedLinkSealsMissing = 'sealed_link_seals_missing';
  static const sealedLinkContent = 'sealed_link_content';
}

/// A failure whose message was written for the reader, so it can be shown as is.
/// Anything else is described by [AppErrorMessage], never by its `toString()`.
class UserFacingException implements Exception {
  final String message;

  const UserFacingException(this.message);

  @override
  String toString() => message;
}

/// What to tell the reader about any failure: the one way to turn a caught
/// error into text.
String describeError(Object error) =>
    AppErrorMessage.fromException(error).description;

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
    switch (error) {
      case ApiException():
        return _mapApiException(error);
      case UserFacingException(:final message) ||
          SealingException(:final message) ||
          DeviceUnlockException(:final message) ||
          SignInApprovalException(:final message):
        return AppErrorMessage(
          title: 'Something went wrong',
          description: message,
          code: '',
        );
      case SocketException() ||
          TlsException() ||
          http.ClientException() ||
          TimeoutException():
        return const AppErrorMessage(
          title: 'Server unreachable',
          description: 'Check the network connection and try again.',
          code: '',
        );
      default:
        // The text a reader never sees is still what a developer needs. Debug
        // only: an error can carry what the request held.
        if (kDebugMode) debugPrint('Unexpected error: $error');
        return const AppErrorMessage(
          title: 'Something went wrong',
          description:
              'An unexpected error occurred. If it persists, restart the app.',
          code: '',
        );
    }
  }

  /// An error without one of our codes: PocketBase's own envelope or a proxy in
  /// front of the server. Its text was not written for the reader, so the
  /// status decides what to say.
  static AppErrorMessage _fromStatus(ApiException e) {
    final status = e.statusCode;
    return switch (status) {
      0 => const AppErrorMessage(
        title: 'Server unreachable',
        description: 'Check the network connection and try again.',
        code: '',
      ),
      400 || 422 => const AppErrorMessage(
        title: 'Request rejected',
        description: 'Check the entered values and try again.',
        code: '',
      ),
      401 => const AppErrorMessage(
        title: 'Session ended',
        description: 'The session has ended. Sign in again to continue.',
        code: '',
        isAuthError: true,
      ),
      403 => const AppErrorMessage(
        title: 'Not permitted',
        description:
            'This action is not permitted in this workspace. Permissions are granted by an admin.',
        code: '',
      ),
      404 => const AppErrorMessage(
        title: 'Not found',
        description:
            'The item may have been removed, or the server does not support this yet.',
        code: '',
      ),
      410 => const AppErrorMessage(
        title: 'No longer available',
        description: 'The item was removed or has ended.',
        code: '',
        isTerminal: true,
      ),
      413 => const AppErrorMessage(
        title: 'Too large',
        description: 'The server does not accept data of this size.',
        code: '',
      ),
      429 => const AppErrorMessage(
        title: 'Too many requests',
        description: 'Wait a moment before retrying.',
        code: '',
      ),
      >= 500 => const AppErrorMessage(
        title: 'Server error',
        description:
            'The server could not complete the request. If it persists, contact the server operator.',
        code: '',
      ),
      _ => const AppErrorMessage(
        title: 'Something went wrong',
        description:
            'An unexpected error occurred. If it persists, restart the app.',
        code: '',
      ),
    };
  }

  static AppErrorMessage _mapApiException(ApiException e) {
    switch (e.code) {
      case AppErrorCode.inviteNotFound:
        return AppErrorMessage(
          title: 'Invite not found',
          description: 'The invite key is not valid. It may be incomplete.',
          code: e.code,
          isTerminal: true,
        );
      case AppErrorCode.inviteExpired:
        return AppErrorMessage(
          title: 'Invite expired',
          description: 'This invite has expired. A new invite is required.',
          code: e.code,
          isTerminal: true,
        );
      case AppErrorCode.inviteRevoked:
        return AppErrorMessage(
          title: 'Invite withdrawn',
          description:
              'This invite was withdrawn by the workspace. A new invite is required.',
          code: e.code,
          isTerminal: true,
        );
      case AppErrorCode.inviteExhausted:
        return AppErrorMessage(
          title: 'Invite already used',
          description:
              'This invite has already been used. A new invite is required.',
          code: e.code,
          isTerminal: true,
        );
      case AppErrorCode.inviteWrongAccount:
        return AppErrorMessage(
          title: 'Wrong account',
          description:
              'This invite was issued to a different email address. It can only be accepted from that account.',
          code: e.code,
          isTerminal: true,
        );
      case AppErrorCode.alreadyWorkspaceMember:
        return AppErrorMessage(
          title: 'Already a member',
          description: 'This account is already a member of this workspace.',
          code: e.code,
          isTerminal: true,
        );
      case AppErrorCode.invitesNotForPersonal:
        return AppErrorMessage(
          title: 'Personal workspaces are private',
          description:
              'Personal workspaces have no other members. Collaboration requires a shared workspace.',
          code: e.code,
        );

      case AppErrorCode.signupsDisabled:
        return AppErrorMessage(
          title: 'Signups are closed',
          description:
              'This server does not accept new accounts. Access requires an invite from its operator.',
          code: e.code,
          isTerminal: true,
        );

      case AppErrorCode.invalidActiveWorkspace:
        return AppErrorMessage(
          title: 'No active workspace',
          description:
              'A workspace must be selected first. Workspaces are listed in Settings.',
          code: e.code,
        );
      case AppErrorCode.activeWorkspaceMismatch:
      case AppErrorCode.forbiddenWorkspaceAccess:
        return AppErrorMessage(
          title: 'Wrong workspace',
          description:
              'This item belongs to another workspace. Switch to that workspace to continue.',
          code: e.code,
        );
      case AppErrorCode.workspaceNotFound:
        return AppErrorMessage(
          title: 'Workspace not found',
          description:
              'The workspace may have been deleted, or this account is no longer a member.',
          code: e.code,
          isTerminal: true,
        );
      case AppErrorCode.personalWorkspaceLimitReached:
      case AppErrorCode.businessWorkspaceLimitReached:
        return AppErrorMessage(
          title: 'Workspace limit reached',
          description:
              'The maximum number of workspaces for this account has been reached.',
          code: e.code,
        );
      case AppErrorCode.failedToCreateWorkspaceMember:
        return AppErrorMessage(
          title: 'Member not added',
          description: 'An unexpected error occurred.',
          code: e.code,
        );
      case AppErrorCode.failedToCreateRecord:
        return AppErrorMessage(
          title: 'Not saved',
          description: 'Check the entered values and try again.',
          code: e.code,
        );
      case AppErrorCode.userNotFound:
        return AppErrorMessage(
          title: 'Account not found',
          description: 'No account exists with this address.',
          code: e.code,
          isTerminal: true,
        );
      case AppErrorCode.validationInsufficientPermissions:
        return AppErrorMessage(
          title: 'Insufficient permissions',
          description:
              'Only permissions already held can be granted. An admin can grant the rest.',
          code: e.code,
        );
      case AppErrorCode.requestTimeout:
        return AppErrorMessage(
          title: 'Server not responding',
          description:
              'The server may be down or busy. Check the server address in Settings.',
          code: e.code,
        );

      case AppErrorCode.missingPermission:
      case AppErrorCode.accessDenied:
        return AppErrorMessage(
          title: 'Not permitted',
          description:
              'This action is not permitted in this workspace. Permissions are granted by an admin.',
          code: e.code,
        );
      case AppErrorCode.permissionEscalation:
        return AppErrorMessage(
          title: 'Permissions not grantable',
          description:
              'Only permissions already held can be granted. Remove the others.',
          code: e.code,
        );
      case AppErrorCode.lastAdminProtected:
        return AppErrorMessage(
          title: 'Last admin',
          description:
              'At least one member must be able to manage members. Grant this permission to another member first.',
          code: e.code,
        );
      case AppErrorCode.invalidScope:
        return AppErrorMessage(
          title: 'Unknown permission',
          description: 'One or more permissions do not exist.',
          code: e.code,
        );
      case AppErrorCode.invalidApiKey:
        return AppErrorMessage(
          title: 'Invalid API key',
          description: 'This API key is not valid.',
          code: e.code,
          isAuthError: true,
        );

      case AppErrorCode.linkNotFound:
        return AppErrorMessage(
          title: 'Link not found',
          description: 'This link does not exist or was removed.',
          code: e.code,
          isTerminal: true,
        );
      case AppErrorCode.linkRevoked:
        return AppErrorMessage(
          title: 'Link revoked',
          description: 'This link was revoked by its owner.',
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
          description:
              'This link was paused by its owner. It may be resumed later.',
          code: e.code,
        );
      case AppErrorCode.linkMaxViewsReached:
        return AppErrorMessage(
          title: 'View limit reached',
          description: 'This link has reached its view limit.',
          code: e.code,
          isTerminal: true,
        );
      case AppErrorCode.linkPasswordRequired:
        return AppErrorMessage(
          title: 'Password required',
          description: 'This link is protected by a password from its sender.',
          code: e.code,
        );
      case AppErrorCode.linkPasswordInvalid:
        return AppErrorMessage(
          title: 'Incorrect password',
          description: 'The password is incorrect.',
          code: e.code,
        );

      case AppErrorCode.requestNotFound:
        return AppErrorMessage(
          title: 'Request not found',
          description: 'This request does not exist.',
          code: e.code,
          isTerminal: true,
        );
      case AppErrorCode.requestRevoked:
        return AppErrorMessage(
          title: 'Request revoked',
          description: 'This request was revoked by its owner.',
          code: e.code,
          isTerminal: true,
        );
      case AppErrorCode.requestExpired:
        return AppErrorMessage(
          title: 'Request expired',
          description:
              'This request has expired and no longer accepts responses.',
          code: e.code,
          isTerminal: true,
        );
      case AppErrorCode.requestPaused:
        return AppErrorMessage(
          title: 'Request paused',
          description:
              'This request was paused by its owner. It may be resumed later.',
          code: e.code,
        );
      case AppErrorCode.requestCompleted:
        return AppErrorMessage(
          title: 'Request completed',
          description: 'This request has received all responses and is closed.',
          code: e.code,
          isTerminal: true,
        );
      case AppErrorCode.requestPasswordRequired:
        return AppErrorMessage(
          title: 'Password required',
          description:
              'Responding requires the password provided by the sender.',
          code: e.code,
        );
      case AppErrorCode.requestPasswordInvalid:
        return AppErrorMessage(
          title: 'Incorrect password',
          description: 'The password is incorrect.',
          code: e.code,
        );
      case AppErrorCode.requestIdentifierMissing:
        return AppErrorMessage(
          title: 'Identifier required',
          description:
              'Responding requires the identifier provided by the sender.',
          code: e.code,
        );
      case AppErrorCode.requestAccountRequired:
        return AppErrorMessage(
          title: 'Account required',
          description:
              'Responding requires an account on this server, so the response can be updated or revoked later.',
          code: e.code,
        );

      case AppErrorCode.handshakeRequired:
        return AppErrorMessage(
          title: 'Verification required',
          description: 'The link must be opened again to continue.',
          code: e.code,
        );
      case AppErrorCode.handshakeInvalid:
        return AppErrorMessage(
          title: 'Identity mismatch',
          description: 'This identity differs from the one used before.',
          code: e.code,
        );
      case AppErrorCode.identityRequired:
        return AppErrorMessage(
          title: 'Identity required',
          description: 'An identity must be selected to continue.',
          code: e.code,
        );
      case AppErrorCode.identityNotFound:
        return AppErrorMessage(
          title: 'Identity not found',
          description: 'The selected identity no longer exists.',
          code: e.code,
        );
      case AppErrorCode.fileNotWatermarkable:
        return AppErrorMessage(
          title: 'File not available',
          description:
              'This share watermarks its files. This file type cannot be watermarked and is not shared.',
          code: e.code,
          isTerminal: true,
        );
      case AppErrorCode.applicationNeedsWatermark:
        return AppErrorMessage(
          title: 'Watermark required',
          description:
              'Application links always watermark their files. The watermark must be enabled to save.',
          code: e.code,
          isTerminal: true,
        );
      case AppErrorCode.recordNotFound:
        return AppErrorMessage(
          title: 'Record not found',
          description:
              'This record does not exist or belongs to another account.',
          code: e.code,
          isTerminal: true,
        );
      case AppErrorCode.watermarkTextInvalid:
        return AppErrorMessage(
          title: 'Watermark text too long',
          description:
              'Watermark text is limited to one line of 1 to 120 characters.',
          code: e.code,
        );
      case AppErrorCode.archiveEmpty:
        return AppErrorMessage(
          title: 'Nothing to download',
          description:
              'None of the files in this share can be included in a download.',
          code: e.code,
          isTerminal: true,
        );
      case AppErrorCode.bookmarkGroupNotOwned:
        return AppErrorMessage(
          title: 'Group not found',
          description:
              'This group is no longer in the bookmarks. Reload to see the current list.',
          code: e.code,
        );
      case AppErrorCode.contactRouteMissing:
        return AppErrorMessage(
          title: 'No contact route',
          description:
              'Sending to this contact requires an email address or a server.',
          code: e.code,
        );
      case AppErrorCode.contactNotFound:
        return AppErrorMessage(
          title: 'Contact not found',
          description:
              'This contact is no longer in this workspace. Reload to see the current list.',
          code: e.code,
        );
      case AppErrorCode.contactNothingToSend:
        return AppErrorMessage(
          title: 'Nothing selected',
          description: 'At least one entry must be selected.',
          code: e.code,
        );
      case AppErrorCode.templateNotOwned:
        return AppErrorMessage(
          title: 'Template not found',
          description:
              'This template is not in this workspace. Select a workspace template or continue without one.',
          code: e.code,
        );
      case AppErrorCode.identityRevoked:
        return AppErrorMessage(
          title: 'Identity revoked',
          description:
              'This identity was revoked by its issuing server and can no longer sign for that domain. A new identity is required.',
          code: e.code,
          isTerminal: true,
        );
      case AppErrorCode.attestationsDisabled:
        return AppErrorMessage(
          title: 'Attestations not available',
          description:
              'Attestations speak for the server\'s domain and are enabled by its operator.',
          code: e.code,
          isTerminal: true,
        );
      case AppErrorCode.attestationOfferNotFound:
        return AppErrorMessage(
          title: 'Offer not found',
          description:
              'This link does not lead to an attestation. It may be incomplete.',
          code: e.code,
          isTerminal: true,
        );
      case AppErrorCode.attestationOfferExpired:
        return AppErrorMessage(
          title: 'Offer expired',
          description:
              'This offer has expired. A new one can be requested from its issuer.',
          code: e.code,
          isTerminal: true,
        );
      case AppErrorCode.attestationOfferClaimed:
        return AppErrorMessage(
          title: 'Already accepted',
          description:
              'This offer was accepted with another identity. Each offer is valid for one identity only.',
          code: e.code,
          isTerminal: true,
        );
      case AppErrorCode.attestationOfferRevoked:
        return AppErrorMessage(
          title: 'Offer withdrawn',
          description: 'This offer was withdrawn by its issuer.',
          code: e.code,
          isTerminal: true,
        );
      case AppErrorCode.attestationIdentityMismatch:
        return AppErrorMessage(
          title: 'Issued to another identity',
          description:
              'This offer was issued to a different identity than the one selected.',
          code: e.code,
        );
      case AppErrorCode.attestationKeyUnsupported:
        return AppErrorMessage(
          title: 'Unsupported identity',
          description:
              'This identity\'s key cannot hold an attestation. A newly created identity can.',
          code: e.code,
        );
      case AppErrorCode.credentialInvalid:
        return AppErrorMessage(
          title: 'Attestation not saved',
          description:
              'The issuer\'s response could not be verified and was not saved. Retry once the issuer\'s domain is verified.',
          code: e.code,
        );
      case AppErrorCode.attestationCheckInvalid:
        return AppErrorMessage(
          title: 'Invalid check',
          description:
              'The kind must be one word, such as membership. The confirming party must be a domain, such as club.example. Details may contain only letters, digits and underscores.',
          code: e.code,
        );
      case AppErrorCode.attestationCheckNotFound:
        return AppErrorMessage(
          title: 'Check not found',
          description:
              'This link does not lead to an attestation check. It may be incomplete.',
          code: e.code,
          isTerminal: true,
        );
      case AppErrorCode.attestationCheckClosed:
        return AppErrorMessage(
          title: 'No longer open',
          description:
              'This check was already answered or its ten-minute window has passed. A new check is required.',
          code: e.code,
          isTerminal: true,
        );
      case AppErrorCode.sealedFieldsRestricted:
        return AppErrorMessage(
          title: 'This record is encrypted',
          description: 'Changing it requires a newer version of the app.',
          code: e.code,
          isTerminal: true,
        );
      case AppErrorCode.sealedInvalid:
        return AppErrorMessage(
          title: 'Not saved',
          description:
              'The server rejected the encrypted data sent by the app.',
          code: e.code,
        );
      case AppErrorCode.sealedVersionConflict:
        return AppErrorMessage(
          title: 'Changed on another device',
          description: 'Reload to get the latest version before retrying.',
          code: e.code,
        );
      case AppErrorCode.sealedEpochStale:
        return AppErrorMessage(
          title: 'Encryption key changed',
          description: 'Reload before retrying.',
          code: e.code,
        );
      case AppErrorCode.sealedKeyMissing:
        return AppErrorMessage(
          title: 'Key not available',
          description:
              'Only the member who enabled encryption in this workspace can use it.',
          code: e.code,
          isTerminal: true,
        );
      case AppErrorCode.sealedRecordUnsupported:
        return AppErrorMessage(
          title: 'Not supported for encrypted records',
          description: 'Encrypted records cannot be used here yet.',
          code: e.code,
          isTerminal: true,
        );
      case AppErrorCode.sealedLinksAffected:
        return AppErrorMessage(
          title: 'Links share this record',
          description: 'Links stop showing this record once it is encrypted.',
          code: e.code,
        );
      case AppErrorCode.sealedLinkSealsMissing:
        return AppErrorMessage(
          title: 'A link was added in between',
          description:
              'A link started carrying this record while it was being saved. Saving again includes it.',
          code: e.code,
        );
      case AppErrorCode.sealedLinkContent:
        return AppErrorMessage(
          title: 'Not added to the link',
          description:
              'An encrypted record goes onto a link only from a device that can open it, and the first one only from the link\'s owner.',
          code: e.code,
        );
      case AppErrorCode.remoteIdentityInvalid:
        return AppErrorMessage(
          title: 'Identity not confirmed',
          description:
              'The receiving server could not verify this identity with its issuing server. The issuing domain must be verified and reachable.',
          code: e.code,
        );
      case AppErrorCode.identityFingerprintInvalid:
        return AppErrorMessage(
          title: 'Invalid fingerprint',
          description: 'This is not a valid identity fingerprint.',
          code: e.code,
        );
      case AppErrorCode.handshakeFailed:
        return AppErrorMessage(
          title: 'Secure connection failed',
          description: 'Verification failed unexpectedly.',
          code: e.code,
        );
      case AppErrorCode.invalidCertificate:
        return AppErrorMessage(
          title: 'Certificate not valid',
          description: 'This certificate could not be verified.',
          code: e.code,
        );

      case AppErrorCode.notAuthenticated:
        return AppErrorMessage(
          title: 'Sign-in required',
          description: 'This action requires signing in.',
          code: e.code,
          isAuthError: true,
        );
      case AppErrorCode.notAuthorized:
        return AppErrorMessage(
          title: 'Not allowed',
          description: 'This action is not permitted.',
          code: e.code,
        );
      case AppErrorCode.duplicateValues:
        return AppErrorMessage(
          title: 'Already exists',
          description: 'An item with these values already exists.',
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
          description: 'This person is already a member of this workspace.',
          code: e.code,
        );
      case AppErrorCode.workspaceMemberLimitReached:
        return AppErrorMessage(
          title: 'Member limit reached',
          description:
              'This workspace has reached its member limit. A member must be removed first.',
          code: e.code,
        );
    }

    if (e.code.isEmpty) return _fromStatus(e);
    // A code this build doesn't know yet: the server wrote its text for people.
    return AppErrorMessage(
      title: switch (e.statusCode) {
        401 => 'Sign-in required',
        403 => 'Not allowed',
        404 => 'Not found',
        410 => 'No longer available',
        _ => 'Something went wrong',
      },
      description: e.message,
      code: e.code,
      isAuthError: e.statusCode == 401,
      isTerminal: e.statusCode == 410,
    );
  }
}
