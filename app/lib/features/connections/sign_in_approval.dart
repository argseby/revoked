import 'package:revoked_app/core/models/identity.dart';
import 'package:revoked_app/core/models/sign_in_consent.dart';
import 'package:revoked_app/core/models/sign_in_request.dart';
import 'package:revoked_app/core/network/api_client.dart';
import 'package:revoked_app/core/services/crypto_service.dart';
import 'package:revoked_app/core/services/device_unlock.dart';
import 'package:revoked_app/features/identities/store/identities_store.dart';

/// Why a sign-in could not be approved, in words for the person.
class SignInApprovalException implements Exception {
  final String message;
  const SignInApprovalException(this.message);

  @override
  String toString() => message;
}

/// A request the app opened: the consent to show, or — when the server
/// refused the request but could name the service — the address that tells
/// the service so.
typedef SignInOpened = ({SignInConsent? consent, String? refusal});

/// The app's side of "Sign in with Revoked". A sign-in is approved here and
/// nowhere else: the request is opened on the server the app is signed into,
/// the person decides on the consent screen, and an approval is signed with
/// an identity key that never leaves this device, after the person unlocked
/// it. The server then answers with the address that takes the browser back
/// to the service.
class SignInApproval {
  /// The message an approval is signed over is this, then the ticket. A
  /// challenge nonce never contains a colon, so neither signature can stand
  /// in for the other.
  static const consentPrefix = 'revoked-oidc-consent:';

  final ApiClient _api;
  final CryptoService _crypto;
  final IdentitiesStore _identities;
  final DeviceUnlock _unlock;

  SignInApproval(this._api, this._crypto, this._identities, this._unlock);

  /// Opens [request] on the signed-in server.
  Future<SignInOpened> open(SignInRequest request) async {
    final data = await _api.post(
      '/oidc/authorize/app',
      body: {'params': request.toQuery()},
    );
    final json = data as Map<String, dynamic>;
    if (json['ticket'] == null) {
      return (consent: null, refusal: json['redirect'] as String?);
    }
    return (consent: SignInConsent.fromJson(json), refusal: null);
  }

  /// Records the person's decision and returns where to send the browser.
  ///
  /// An approval asks the person to unlock the device first, then signs the
  /// ticket with an identity whose key this device holds. [links] maps each
  /// key asked for to the chosen entry id; an empty id shares nothing.
  Future<String> decide(
    SignInConsent consent, {
    required bool approve,
    Set<String> scopes = const {},
    Map<String, String> links = const {},
  }) async {
    final body = <String, dynamic>{
      'ticket': consent.ticket,
      'approve': approve,
    };
    if (approve) {
      final identity = await _signingIdentity();
      final bool confirmed;
      try {
        confirmed = await _unlock.confirm('Sign in to ${consent.clientHost}');
      } on DeviceUnlockException catch (e) {
        throw SignInApprovalException(e.message);
      }
      if (!confirmed) {
        throw const SignInApprovalException(
          'Signing in needs your confirmation on this device.',
        );
      }
      body['scopes'] = scopes.toList();
      body['links'] = {
        for (final e in links.entries)
          if (e.value.isNotEmpty) e.key: e.value,
      };
      body['identityId'] = identity.id;
      body['signature'] = await _crypto.signMessage(
        identityId: identity.id,
        message: '$consentPrefix${consent.ticket}',
      );
    }
    final data = await _api.post('/oidc/authorize/consent', body: body);
    return (data as Map<String, dynamic>)['redirect'] as String;
  }

  /// Hands [redirect] — the answer — to a service that waits for it, without
  /// a browser. False when the service could not be reached.
  Future<bool> deliver(String redirect) async {
    final uri = Uri.tryParse(redirect);
    if (uri == null) return false;
    try {
      return await _api.getFromService(uri);
    } catch (_) {
      return false;
    }
  }

  /// The identity the approval is signed with: the primary one if its key is
  /// on this device, otherwise any active one whose key is.
  Future<Identity> _signingIdentity() async {
    if (_identities.identities.isEmpty) await _identities.loadIdentities();
    final active = _identities.identities.where((i) => !i.isRevoked).toList()
      ..sort((a, b) => (b.isPrimary ? 1 : 0) - (a.isPrimary ? 1 : 0));
    for (final identity in active) {
      final key = await _crypto.loadPrivateKey(identity.id);
      if (key != null && key.isNotEmpty) return identity;
    }
    throw const SignInApprovalException(
      'This device holds no identity key, so it cannot confirm a sign-in. '
      'Approve it on the device you set up Revoked on, or create an identity '
      'here first.',
    );
  }
}
