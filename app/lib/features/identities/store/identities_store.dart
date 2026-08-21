import 'package:mobx/mobx.dart';
import 'package:revoked_app/core/config/app_config.dart';
import 'package:revoked_app/core/models/identity.dart';
import 'package:revoked_app/core/network/api_client.dart';
import 'package:revoked_app/core/services/crypto_service.dart';

part 'identities_store.g.dart';

// ignore: library_private_types_in_public_api
class IdentitiesStore = _IdentitiesStore with _$IdentitiesStore;

abstract class _IdentitiesStore with Store {
  final ApiClient _api;
  final CryptoService _crypto;

  _IdentitiesStore(this._api, this._crypto);

  String get _basePath =>
      '/api/collections/${AppConfig.identitiesCollection}/records';

  final ObservableList<Identity> identities = ObservableList<Identity>();

  @observable
  bool isLoading = false;

  @observable
  String? errorMessage;

  @computed
  Identity? get primaryIdentity {
    for (final identity in identities) {
      if (identity.isPrimary) return identity;
    }
    return identities.isNotEmpty ? identities.first : null;
  }

  @action
  Future<void> loadIdentities() async {
    isLoading = true;
    errorMessage = null;
    try {
      final data = await _api.get(_basePath, queryParams: {'sort': '-created'});
      final items = (data['items'] as List<dynamic>?) ?? [];
      identities
        ..clear()
        ..addAll(
          items.map((e) => Identity.fromJson(e as Map<String, dynamic>)),
        );
    } catch (e) {
      errorMessage = e.toString();
    } finally {
      isLoading = false;
    }
  }

  /// Fetches an identity's public certificate + fingerprint from the dedicated
  /// route, which returns ONLY the public material — never the private key.
  Future<Map<String, dynamic>> getPublicCertificate(String identityId) async {
    final data = await _api.get('/api/certificate/$identityId');
    return data as Map<String, dynamic>;
  }

  /// Generates the keypair on the device and uploads only the public key; the
  /// private key goes into secure local storage once the server returns the
  /// new identity's id, and never leaves the device.
  @action
  Future<bool> createIdentity({
    required String name,
    bool isPrimary = false,
  }) async {
    isLoading = true;
    errorMessage = null;
    try {
      // The create rule requires `user = auth.id && workspace =
      // auth.activeWorkspace`, so both are hydrated from cached auth state.
      final user = _api.userData?['id'] as String?;
      final workspace = _api.userData?['activeWorkspace'] as String?;
      if (user == null ||
          user.isEmpty ||
          workspace == null ||
          workspace.isEmpty) {
        throw StateError(
          'Cannot create identity: missing authenticated user or active workspace.',
        );
      }

      final generated = _crypto.generateIdentity(commonName: name);
      final data = await _api.post(
        _basePath,
        body: {
          'name': name,
          'publicKey': generated.publicKeyPem,
          'user': user,
          'workspace': workspace,
        },
      );
      final identity = Identity.fromJson(data as Map<String, dynamic>);
      await _crypto.storePrivateKey(identity.id, generated.privateKeyPem);

      // copyWith preserves server-set fields (domainAtIssue, created, …)
      // that a hand-rebuilt Identity would silently drop.
      identities.insert(0, identity.copyWith(isPrimary: isPrimary));
      return true;
    } catch (e) {
      errorMessage = e.toString();
      return false;
    } finally {
      isLoading = false;
    }
  }

  /// Only the display name is editable; the certificate is fixed after
  /// creation because its fingerprint is what identifies the identity.
  @action
  Future<bool> updateIdentity(String id, {String? name}) async {
    isLoading = true;
    errorMessage = null;
    try {
      final Map<String, dynamic> body = {};
      if (name != null) body['name'] = name;
      final data = await _api.patch('$_basePath/$id', body: body);
      final updated = Identity.fromJson(data as Map<String, dynamic>);
      final idx = identities.indexWhere((i) => i.id == id);
      if (idx != -1) {
        identities[idx] = updated;
      }
      return true;
    } catch (e) {
      errorMessage = e.toString();
      return false;
    } finally {
      isLoading = false;
    }
  }

  /// Withdraws an identity without deleting it.
  ///
  /// The row has to survive, because the answer a verifier needs is about a
  /// fingerprint whose certificate is already out in the world — a deleted row
  /// could only answer with silence, which is indistinguishable from a server
  /// that never issued it. The private key goes, though: this is the action
  /// taken when it may have leaked, and keeping it would be the one mistake
  /// revoking is meant to undo.
  @action
  Future<bool> revokeIdentity(String id, {String reason = 'manual'}) async {
    isLoading = true;
    errorMessage = null;
    try {
      final data = await _api.patch(
        '$_basePath/$id',
        body: {'status': 'revoked', 'revokedReason': reason},
      );
      await _crypto.deletePrivateKey(id);
      final updated = Identity.fromJson(data as Map<String, dynamic>);
      final idx = identities.indexWhere((i) => i.id == id);
      if (idx != -1) identities[idx] = updated;
      return true;
    } catch (e) {
      errorMessage = e.toString();
      return false;
    } finally {
      isLoading = false;
    }
  }

  @action
  Future<void> deleteIdentity(String id) async {
    isLoading = true;
    errorMessage = null;
    try {
      await _api.delete('$_basePath/$id');
      await _crypto.deletePrivateKey(id);
      identities.removeWhere((i) => i.id == id);
    } catch (e) {
      errorMessage = e.toString();
    } finally {
      isLoading = false;
    }
  }

  @action
  Future<bool> setPrimary(String id) async {
    final previous = identities.toList();
    errorMessage = null;
    for (var i = 0; i < identities.length; i++) {
      // copyWith so domainAtIssue (and other server fields) survive the
      // primary flip — rebuilding by hand wiped them, breaking from_root.
      identities[i] = identities[i].copyWith(isPrimary: identities[i].id == id);
    }
    try {
      await _api.patch('$_basePath/$id', body: {'isPrimary': true});
      return true;
    } catch (e) {
      identities
        ..clear()
        ..addAll(previous);
      errorMessage = e.toString();
      return false;
    }
  }
}
