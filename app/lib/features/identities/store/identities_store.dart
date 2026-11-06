import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:mobx/mobx.dart';
import 'package:revoked_app/core/config/app_config.dart';
import 'package:revoked_app/core/models/identity.dart';
import 'package:revoked_app/core/network/api_client.dart';
import 'package:revoked_app/core/network/app_errors.dart';
import 'package:revoked_app/core/services/crypto_service.dart';
import 'package:revoked_app/core/state/load_state.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/features/sealing/store/keys_store.dart'
    show identityKeyScopeAccount;

part 'identities_store.g.dart';

/// A name for an identity made on this device, so the list tells apart the
/// phone's from the laptop's.
String get thisDeviceName {
  if (kIsWeb) return 'This browser';
  if (Platform.isAndroid) return 'Android phone';
  if (Platform.isIOS) return 'iPhone';
  if (Platform.isMacOS) return 'Mac';
  if (Platform.isWindows) return 'Windows computer';
  return 'Linux computer';
}

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

  /// The identities whose private key is on this device. With end-to-end
  /// encryption on, keys travel to every trusted device through the device
  /// list ([syncSealedKeys]); without it, each key stays on the device that
  /// made it, and the account's other identities are listed but cannot sign
  /// here.
  final ObservableSet<String> localKeyIds = ObservableSet<String>();

  /// Whether this device's key check has run since the identities loaded.
  @observable
  bool keysChecked = false;

  bool hasLocalKey(String id) => localKeyIds.contains(id);

  /// Whether any identity that still stands can sign on this device.
  @computed
  bool get canSignHere =>
      identities.any((i) => !i.isRevoked && localKeyIds.contains(i.id));

  /// The account has identities, but none of them can sign here.
  @computed
  bool get keysElsewhere =>
      keysChecked && identities.any((i) => !i.isRevoked) && !canSignHere;

  @computed
  Identity? get primaryIdentity {
    for (final identity in identities) {
      if (identity.isPrimary) return identity;
    }
    return identities.isNotEmpty ? identities.first : null;
  }

  /// The identity with [id], when it is among this person's: for a view that
  /// names the identity something is bound to.
  Identity? byId(String id) {
    for (final identity in identities) {
      if (identity.id == id) return identity;
    }
    return null;
  }

  /// Tracks this list for the cache and the first-load skeleton.
  final LoadState loadState = LoadState();

  /// [loadIdentities], unless what's here is still fresh.
  Future<void> loadIfDue() async {
    if (loadState.isDue) await loadIdentities();
  }

  @action
  Future<void> loadIdentities() async {
    isLoading = true;
    errorMessage = null;
    final ticket = loadState.begin();
    try {
      final data = await _api.get(_basePath, queryParams: {'sort': '-created'});
      final items = (data['items'] as List<dynamic>?) ?? [];
      if (!loadState.isCurrent(ticket)) return;
      identities
        ..clear()
        ..addAll(
          items.map((e) => Identity.fromJson(e as Map<String, dynamic>)),
        );
      await _checkLocalKeys();
      loadState.succeed(ticket);
    } catch (e) {
      if (!loadState.isCurrent(ticket)) return;
      errorMessage = describeError(e);
      loadState.fail(ticket, errorMessage!);
    } finally {
      isLoading = false;
    }
  }

  Future<void> _checkLocalKeys() async {
    final present = <String>{};
    for (final identity in identities) {
      final key = await _crypto.loadPrivateKey(identity.id);
      if (key != null && key.isNotEmpty) present.add(identity.id);
    }
    runInAction(() {
      localKeyIds
        ..clear()
        ..addAll(present);
      keysChecked = true;
    });
    await syncSealedKeys();
  }

  /// Whether a sync pass is running, so two loads don't race one another.
  bool _syncing = false;

  /// Brings this device in line with the account's device list: opens keys
  /// wrapped on another device, and wraps a key that exists only here — an
  /// identity from before syncing, or one made while encryption was off.
  /// Quietly does nothing on an account without end-to-end encryption, or
  /// while this device is not trusted yet.
  Future<void> syncSealedKeys() async {
    if (_syncing) return;
    _syncing = true;
    try {
      await Stores.keys.ensureLoaded();
      for (final identity in identities.toList()) {
        if (identity.isRevoked) continue;
        final here = localKeyIds.contains(identity.id);
        // Under the workspace key, every member that key is one day handed
        // to could open it: moved to the account key wherever this device
        // holds the private key.
        final onAccountKey = identity.sealedKeyScope == identityKeyScopeAccount;
        if (!here && identity.sealedKey.isNotEmpty) {
          final pem = Stores.keys.openIdentityKey(
            workspace: identity.workspace,
            identity: identity.id,
            epoch: identity.sealedKeyEpoch,
            wrap: identity.sealedKey,
            scope: identity.sealedKeyScope,
          );
          if (pem == null || pem.isEmpty) continue;
          await _crypto.storePrivateKey(identity.id, pem);
          runInAction(() => localKeyIds.add(identity.id));
          if (!onAccountKey) {
            await _uploadSealedKey(identity.id, identity.workspace, pem);
          }
        } else if (here && (identity.sealedKey.isEmpty || !onAccountKey)) {
          final pem = await _crypto.loadPrivateKey(identity.id);
          if (pem == null || pem.isEmpty) continue;
          await _uploadSealedKey(identity.id, identity.workspace, pem);
        }
      }
    } catch (_) {
      // Never the identities list's problem: whatever failed here, every key
      // already on this device keeps working, and the next load tries again.
    } finally {
      _syncing = false;
    }
  }

  /// Wraps the private key under the owner's account key and stores it on
  /// the identity, where their other devices find it. Does nothing when this
  /// device holds no account key and can't make one, and keeps the key local
  /// when the server refuses (an older server, or a member without the
  /// identities permission).
  Future<void> _uploadSealedKey(String id, String workspace, String pem) async {
    if (!await Stores.keys.ensureAccountKey()) return;
    final sealed = Stores.keys.sealIdentityKey(
      workspace: workspace,
      identity: id,
      privateKeyPem: pem,
    );
    if (sealed == null) return;
    try {
      final data = await _api.patch(
        '$_basePath/$id',
        body: {
          'sealedKey': sealed.wrap,
          'sealedKeyEpoch': sealed.epoch,
          'sealedKeyScope': identityKeyScopeAccount,
        },
      );
      final updated = Identity.fromJson(data as Map<String, dynamic>);
      final idx = identities.indexWhere((i) => i.id == id);
      if (idx != -1) runInAction(() => identities[idx] = updated);
    } catch (_) {
      // Left local; the next load tries again.
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
        throw UserFacingException(
          'A signed-in account and an open workspace are required.',
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
      localKeyIds.add(identity.id);

      // copyWith preserves server-set fields (domainAtIssue, created, …)
      // that a hand-rebuilt Identity would silently drop.
      identities.insert(0, identity.copyWith(isPrimary: isPrimary));
      // So the person's other devices can sign with it too. Best effort: on
      // an account without encryption the key simply stays here.
      await _uploadSealedKey(identity.id, workspace, generated.privateKeyPem);
      return true;
    } catch (e) {
      errorMessage = describeError(e);
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
      errorMessage = describeError(e);
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
      localKeyIds.remove(id);
      final updated = Identity.fromJson(data as Map<String, dynamic>);
      final idx = identities.indexWhere((i) => i.id == id);
      if (idx != -1) identities[idx] = updated;
      return true;
    } catch (e) {
      errorMessage = describeError(e);
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
      localKeyIds.remove(id);
      identities.removeWhere((i) => i.id == id);
    } catch (e) {
      errorMessage = describeError(e);
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
      errorMessage = describeError(e);
      return false;
    }
  }
}
