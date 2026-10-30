import 'dart:async';

import 'package:mobx/mobx.dart';

import 'package:revoked_app/core/config/app_config.dart';
import 'package:revoked_app/core/models/attestation.dart';
import 'package:revoked_app/core/models/attestation_ask.dart';
import 'package:revoked_app/core/models/credential.dart';
import 'package:revoked_app/core/models/identity.dart';
import 'package:revoked_app/core/models/presentation_request.dart';
import 'package:revoked_app/core/models/tool_client.dart';
import 'package:revoked_app/core/models/trust_verdict.dart';
import 'package:revoked_app/core/network/api_client.dart';
import 'package:revoked_app/core/network/app_errors.dart';
import 'package:revoked_app/core/services/crypto_service.dart';
import 'package:revoked_app/core/services/domain_verification_service.dart';
import 'package:revoked_app/core/services/handshake_service.dart';
import 'package:revoked_app/core/state/observable_text_controller.dart';

part 'credentials_store.g.dart';

/// The attestations a person holds: accepting an offer, keeping the
/// credential, and presenting it.
///
/// A credential lives on the person's own server, which checks it before
/// keeping it. Two things happen on the device and nowhere else, because the
/// identity key is here: signing the issuer's challenge when an offer is
/// accepted, and signing the key binding when a credential is presented.
// ignore: library_private_types_in_public_api
class CredentialsStore = _CredentialsStore with _$CredentialsStore;

abstract class _CredentialsStore with Store {
  final ApiClient _api;
  final CryptoService _crypto;
  final HandshakeService _handshake;
  final DomainVerificationService _domainVerification;

  _CredentialsStore(
    this._api,
    this._crypto,
    this._handshake,
    this._domainVerification,
  );

  String get _basePath =>
      '/api/collections/${AppConfig.credentialsCollection}/records';

  final ObservableList<Credential> credentials = ObservableList<Credential>();

  /// What the server found for a credential when it was last asked, by id.
  /// Absent while the answer is on its way, or when it could not be had.
  final ObservableMap<String, CredentialVerdict> verdicts =
      ObservableMap<String, CredentialVerdict>();

  @observable
  bool isLoading = false;

  @observable
  String? errorMessage;

  @action
  Future<void> load() async {
    isLoading = true;
    errorMessage = null;
    try {
      // Like the identities they are bound to, credentials are listed for
      // the workspace that is active.
      final workspace = _api.userData?['activeWorkspace'] as String? ?? '';
      final data = await _api.get(
        _basePath,
        queryParams: {
          'sort': '-created',
          if (workspace.isNotEmpty) 'filter': 'workspace = "$workspace"',
        },
      );
      final items = (data['items'] as List<dynamic>?) ?? [];
      credentials
        ..clear()
        ..addAll(
          items.map((e) => Credential.fromJson(e as Map<String, dynamic>)),
        );
      // Each answer can involve the issuer's server, so they are asked for
      // side by side and land one by one.
      for (final c in credentials) {
        unawaited(loadVerdict(c.id));
      }
    } catch (e) {
      errorMessage = AppErrorMessage.fromException(e).description;
    } finally {
      isLoading = false;
    }
  }

  /// Asks the server whether a credential still stands: the issuer's key,
  /// its status list, and the identity the credential is bound to.
  @action
  Future<void> loadVerdict(String id) async {
    try {
      final data = await _api.get('/api/credentials/$id/status');
      final verdict = CredentialVerdict.fromJson(data as Map<String, dynamic>);
      runInAction(() => verdicts[id] = verdict);
    } catch (_) {
      // No answer is not a verdict; the row shows none.
    }
  }

  @action
  Future<bool> remove(String id) async {
    errorMessage = null;
    try {
      await _api.delete('$_basePath/$id');
      credentials.removeWhere((c) => c.id == id);
      verdicts.remove(id);
      return true;
    } catch (e) {
      errorMessage = AppErrorMessage.fromException(e).description;
      return false;
    }
  }

  // An offer being looked at.

  @observable
  AttestationOffer? offer;

  @observable
  AppErrorMessage? offerError;

  @observable
  bool isProbing = false;

  @observable
  bool isAccepting = false;

  /// Whether the offer's server is the domain it says it is.
  @observable
  TrustVerdict? offerTrust;

  @observable
  bool isVerifyingOffer = false;

  /// Reads what an offer states from the server it lives on, and checks that
  /// server's domain. Nothing is accepted by looking.
  @action
  Future<void> probeOffer(String token, String? origin) async {
    isProbing = true;
    offer = null;
    offerError = null;
    offerTrust = null;
    try {
      final data = await _api.getFromOrigin(
        origin,
        '/api/attestations/offers/${Uri.encodeComponent(token)}',
      );
      final probed = AttestationOffer.fromJson(data as Map<String, dynamic>);
      runInAction(() => offer = probed);
      unawaited(_verifyOfferServer(probed.serverDomain));
    } catch (e) {
      offerError = AppErrorMessage.fromException(e);
    } finally {
      isProbing = false;
    }
  }

  @action
  Future<void> _verifyOfferServer(String domain) async {
    if (domain.isEmpty) return;
    isVerifyingOffer = true;
    TrustVerdict verdict;
    try {
      verdict = await _domainVerification.verify(
        claimedDomain: domain,
        identityFingerprint: '',
        parentSignatureHex: '',
      );
    } catch (e) {
      // A failed check is an unverified server, not the absence of an opinion.
      verdict = TrustVerdict.unverified(
        domain: domain,
        reason: 'We couldn’t check this domain: $e',
      );
    }
    runInAction(() {
      offerTrust = verdict;
      isVerifyingOffer = false;
    });
  }

  /// Accepts an offer with one of the person's identities.
  ///
  /// The issuer's challenge is signed here, with the identity key. The rest
  /// goes through the person's own server, which adds the identity's public
  /// half, asks the issuer, checks the credential that comes back and keeps
  /// it. Returns the credential, or null with [offerError] set.
  @action
  Future<Credential?> acceptOffer({
    required String token,
    required String? origin,
    required String identityId,
  }) async {
    isAccepting = true;
    offerError = null;
    try {
      final foreign = !_api.isOwnOrigin(origin);
      final base = foreign ? ApiClient.publicBaseFor(origin!) : null;
      if (foreign && base == null) {
        throw ApiException(
          0,
          'This link points to an invalid server. Ask for a new one.',
          code: 'invalid_origin',
        );
      }
      final challenge = await _handshake.prepare(
        scope: HandshakeService.scopeAttestation,
        slug: token,
        identityId: identityId,
        origin: origin,
      );
      final data = await _api.post(
        '/api/credentials/claim',
        body: {
          'origin': ?base,
          'token': token,
          'identityId': identityId,
          'challengeNonce': challenge.nonce,
          'challengeSignature': challenge.signature,
        },
      );
      final kept = Credential.fromJson(data as Map<String, dynamic>);
      runInAction(() {
        credentials
          ..removeWhere((c) => c.id == kept.id)
          ..insert(0, kept);
      });
      unawaited(loadVerdict(kept.id));
      return kept;
    } on StateError catch (e) {
      // The identity's key is not on this device.
      offerError = AppErrorMessage(
        title: 'This identity lives on another device',
        description: e.message,
        code: '',
      );
      return null;
    } catch (e) {
      offerError = AppErrorMessage.fromException(e);
      return null;
    } finally {
      isAccepting = false;
    }
  }

  @action
  void clearOffer() {
    offer = null;
    offerError = null;
    offerTrust = null;
    isProbing = false;
    isAccepting = false;
    isVerifyingOffer = false;
  }

  // Presenting.

  @observable
  bool isPresenting = false;

  @observable
  String? presentError;

  /// The held credentials a request asks for: the right kind, from an
  /// attester the service accepts, and not past their date.
  List<Credential> matching(PresentationRequest request) => [
    for (final c in credentials)
      if (!c.isExpired &&
          request.accepts(issuer: c.issuer, credentialType: c.type))
        c,
  ];

  /// Presents [credential] to the service that asked: only the claims in
  /// [disclose] travel, bound to the service and to its nonce with the
  /// identity key. The service's answer may name an address on its own
  /// origin to continue at; that address is returned, or null.
  ///
  /// Throws nothing: a failure is reported through [presentError] and a
  /// false [PresentationOutcome.delivered].
  @action
  Future<PresentationOutcome> present({
    required PresentationRequest request,
    required Credential credential,
    required Iterable<String> disclose,
  }) async {
    isPresenting = true;
    presentError = null;
    try {
      final presentation = await _crypto.presentCredential(
        identityId: credential.identity,
        credential: credential.credential,
        disclose: disclose,
        audience: request.clientId,
        nonce: request.nonce,
      );
      final answer = await _api.postToService(Uri.parse(request.responseUri), {
        'presentation': presentation,
        if (request.state.isNotEmpty) 'state': request.state,
      });
      Uri? next;
      if (answer is Map<String, dynamic> && answer['redirect_uri'] is String) {
        final redirect = answer['redirect_uri'] as String;
        // Only an address on the service's own origin is followed.
        if (ToolClient.redirectWithin(redirect, request.clientId)) {
          next = Uri.parse(redirect);
        }
      }
      return PresentationOutcome(delivered: true, next: next);
    } on StateError catch (e) {
      presentError = e.message;
      return const PresentationOutcome(delivered: false);
    } on FormatException catch (e) {
      presentError = 'This attestation can’t be shown: ${e.message}.';
      return const PresentationOutcome(delivered: false);
    } catch (e) {
      presentError = AppErrorMessage.fromException(e).description;
      return const PresentationOutcome(delivered: false);
    } finally {
      isPresenting = false;
    }
  }

  // Who asks, when the request is a person's check rather than a service's.

  /// The asker's identity name, once their server named it.
  @observable
  String? askerName;

  /// Whether the asker's identity was issued by the domain they ask from.
  @observable
  TrustVerdict? askerTrust;

  /// Why the asker's server could not say who asks, such as a check that
  /// was already answered.
  @observable
  AppErrorMessage? askerError;

  static const _checkAnswerPath = '/api/public/attestation-checks/answer';

  /// Reads who asks when [request] is someone's check: its answer goes to a
  /// Revoked server, which names the asker's identity the way a request
  /// names its requester, and that identity is checked along the same chain.
  /// A service's request names nobody beyond its address, and is left alone.
  @action
  Future<void> probeAsker(PresentationRequest request) async {
    askerName = null;
    askerTrust = null;
    askerError = null;
    if (request.state.isEmpty ||
        request.responseUri != '${request.clientId}$_checkAnswerPath') {
      return;
    }
    final origin = Uri.parse(request.clientId).authority;
    try {
      final data = await _api.getFromOrigin(
        origin,
        '/api/public/attestation-checks/${Uri.encodeComponent(request.state)}',
      );
      final probe = data as Map<String, dynamic>;
      final asker = probe['asker'];
      final server = probe['server'];
      String field(Object? block, String key) =>
          block is Map ? block[key] as String? ?? '' : '';
      final name = field(asker, 'name');
      runInAction(() => askerName = name.isEmpty ? 'Someone' : name);
      final verdict = await _domainVerification.verify(
        claimedDomain: field(server, 'domain'),
        identityFingerprint: field(asker, 'fingerprint'),
        parentSignatureHex: field(asker, 'parentSignature'),
      );
      runInAction(() => askerTrust = verdict);
    } catch (e) {
      runInAction(() => askerError = AppErrorMessage.fromException(e));
    }
  }

  // Asking someone for an attestation about one of this person's
  // identities.

  final ObservableTextController askTypeController = ObservableTextController();
  final ObservableTextController askClaimsController =
      ObservableTextController();

  /// Which identity the attestation should be bound to.
  @observable
  String? askIdentityId;

  @action
  void resetAsk({String? identityId}) {
    askTypeController.clear();
    askClaimsController.clear();
    askIdentityId = identityId;
  }

  @action
  void setAskIdentity(String? id) => askIdentityId = id;

  static final _askType = RegExp(r'^[\x21-\x7e]{1,255}$');
  static final _askClaim = RegExp(r'^[A-Za-z][A-Za-z0-9_]{0,63}$');

  /// What stops the ask from being made, or null when nothing does.
  @computed
  String? get askProblem {
    final type = askTypeController.text.trim();
    if (type.isEmpty) {
      return 'Say what kind, for example membership.';
    }
    if (!_askType.hasMatch(type)) {
      return 'Use one word for the kind, for example membership.';
    }
    for (final claim in AttestationAsk.splitClaims(askClaimsController.text)) {
      if (!_askClaim.hasMatch(claim)) {
        return '“$claim” won’t work as a name. Use letters, digits and '
            'underscores, and start with a letter.';
      }
    }
    if (askIdentityId == null) return 'Choose which identity it’s for.';
    return null;
  }

  /// The ask as a link, for the identity chosen; null while [askProblem]
  /// names something.
  AttestationAsk? ask(Identity identity) {
    if (askProblem != null) return null;
    return AttestationAsk(
      type: askTypeController.text.trim(),
      claims: AttestationAsk.splitClaims(askClaimsController.text),
      fingerprint: identity.fingerprint.toLowerCase(),
      name: identity.name,
    );
  }
}

/// What became of a presentation.
class PresentationOutcome {
  /// Whether the service received it.
  final bool delivered;

  /// Where the service asks to continue, on its own origin.
  final Uri? next;

  const PresentationOutcome({required this.delivered, this.next});
}
