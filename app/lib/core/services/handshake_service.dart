import 'package:revoked_app/core/network/api_client.dart';
import 'package:revoked_app/core/services/crypto_service.dart';

/// A server-issued challenge nonce together with the identity's signature
/// over it, ready to be replayed back to the server to prove key ownership.
class SignedChallenge {
  final String nonce;
  final String signature;

  /// Identifies the signer to the server. For authenticated flows this is
  /// the server-assigned identity id; for guest flows it is the ephemeral
  /// key's fingerprint.
  final String identityId;

  SignedChallenge({
    required this.nonce,
    required this.signature,
    required this.identityId,
  });
}

/// A service that performs the client side of the challenge/response
/// handshake used to authenticate access to a public link or request.
///
/// The flow is always: fetch a one-time `nonce` from the server for a given
/// [scope]/`slug`, sign that nonce with the identity's private key, and
/// return a [SignedChallenge] the caller posts back as proof of ownership.
class HandshakeService {
  static const String scopeRequest = 'request';
  static const String scopeLink = 'link';
  static const String scopeRequestGuest = 'request_guest';

  final ApiClient _apiClient;
  final CryptoService _cryptoService;

  HandshakeService(this._apiClient, this._cryptoService);

  /// Prepares a signed challenge for an authenticated identity.
  ///
  /// Signs the server's nonce with the private key held in secure storage
  /// for [identityId] (via [CryptoService.signMessage]). Use this when the
  /// caller owns a persisted identity.
  Future<SignedChallenge> prepare({
    required String scope,
    required String slug,
    required String identityId,
  }) async {
    final response = await _apiClient.get(
      '/api/challenges/$scope/$slug',
      queryParams: {'identityId': identityId},
    );

    final nonce = response['nonce'] as String;

    final signature = await _cryptoService.signMessage(
      identityId: identityId,
      message: nonce,
    );

    return SignedChallenge(
      nonce: nonce,
      signature: signature,
      identityId: identityId,
    );
  }

  /// Prepares a signed challenge for an ephemeral guest identity.
  ///
  /// Signs the nonce with the supplied [privateKeyPem] directly — the key
  /// is never persisted to secure storage — and identifies the signer by
  /// [fingerprint]. Use this for guests responding to a public request who
  /// minted a throwaway keypair on the spot.
  Future<SignedChallenge> prepareGuest({
    required String slug,
    required String publicKeyPem,
    required String privateKeyPem,
    required String fingerprint,
  }) async {
    final response = await _apiClient.get(
      '/api/challenges/$scopeRequestGuest/$slug',
      queryParams: {'guestFingerprint': fingerprint},
    );

    final nonce = response['nonce'] as String;

    final signature = _cryptoService.signWithPrivateKey(
      privateKeyPem: privateKeyPem,
      message: nonce,
    );

    return SignedChallenge(
      nonce: nonce,
      signature: signature,
      identityId: fingerprint,
    );
  }
}
