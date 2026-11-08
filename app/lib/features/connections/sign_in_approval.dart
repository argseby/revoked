import 'package:flutter/widgets.dart';
import 'package:revoked_app/core/models/sign_in_consent.dart';
import 'package:revoked_app/core/models/sign_in_request.dart';
import 'package:revoked_app/core/config/app_config.dart';
import 'package:revoked_app/core/network/api_client.dart';
import 'package:revoked_app/core/services/crypto_service.dart';
import 'package:revoked_app/core/services/device_unlock.dart';
import 'package:revoked_app/core/state/observable_text_controller.dart';
import 'package:revoked_app/core/stores.dart';
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
/// the service so. [paused] is the person's row for a service they paused,
/// which is why it was refused.
typedef SignInOpened = ({
  SignInConsent? consent,
  String? refusal,
  String? paused,
});

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

  /// The longest name the server gives a service, in characters. Checked
  /// before the name is saved, so a refusal leaves no stray entry behind.
  static const maxNameLength = 200;

  final ApiClient _api;
  final CryptoService _crypto;
  final IdentitiesStore _identities;
  final DeviceUnlock _unlock;

  /// A new name being typed for this service.
  final ObservableTextController nameDraft = ObservableTextController();

  /// What's being searched for in the vault browser.
  final ObservableTextController browseQuery = ObservableTextController();

  final Map<String, ObservableTextController> _valueDrafts = {};

  /// A new value being typed for the vault key [key].
  ObservableTextController valueDraft(String key) =>
      _valueDrafts.putIfAbsent(key, ObservableTextController.new);

  SignInApproval(this._api, this._crypto, this._identities, this._unlock);

  /// Opens [request] on the signed-in server.
  Future<SignInOpened> open(SignInRequest request) async {
    nameDraft.clear();
    for (final draft in _valueDrafts.values) {
      draft.clear();
    }
    final data = await _api.post(
      '/oidc/authorize/app',
      body: {'params': request.toQuery()},
    );
    final json = data as Map<String, dynamic>;
    if (json['ticket'] == null) {
      return (
        consent: null,
        refusal: json['redirect'] as String?,
        paused: json['paused'] as String?,
      );
    }
    return (consent: SignInConsent.fromJson(json), refusal: null, paused: null);
  }

  /// Records the person's decision and returns where to send the browser.
  ///
  /// An approval asks the person to unlock the device first, then signs the
  /// ticket with an identity whose key this device holds. [links] maps each
  /// key asked for to the chosen entry id; an empty id shares nothing. [name]
  /// is the name picked for this service; [newName] is one to save first, as
  /// a vault entry of its own, once the person has confirmed. [newValues] maps
  /// a key asked for to a value to save the same way and share under that key.
  Future<String> decide(
    SignInConsent consent, {
    required bool approve,
    Set<String> scopes = const {},
    Map<String, String> links = const {},
    SignInNameOption? name,
    String newName = '',
    Map<String, String> newValues = const {},
  }) async {
    final body = <String, dynamic>{
      'ticket': consent.ticket,
      'approve': approve,
    };
    if (approve) {
      final identityId = await _signingIdentity(consent);
      final bool confirmed;
      try {
        confirmed = await _unlock.confirm('Sign in to ${consent.clientHost}');
      } on DeviceUnlockException catch (e) {
        throw SignInApprovalException(e.message);
      }
      if (!confirmed) {
        throw const SignInApprovalException(
          'Sign-in requires confirmation on this device.',
        );
      }
      if (newName.characters.length > maxNameLength) {
        throw const SignInApprovalException(
          'This name is too long. A name can be at most $maxNameLength '
          'characters.',
        );
      }
      final saved = newName.isEmpty ? null : await _saveName(consent, newName);
      final savedValues = {
        for (final e in newValues.entries)
          e.key: (await _saveValue(e.key, e.value)).id,
      };
      final given = saved ?? name;
      if (given != null) {
        body['name'] = {'kind': given.kind, 'id': given.id};
      }
      body['scopes'] = scopes.toList();
      body['links'] = {
        for (final e in links.entries)
          if (e.value.isNotEmpty) e.key: e.value,
        ...savedValues,
      };
      body['created'] = [?saved?.id, ...savedValues.values];
      body['identityId'] = identityId;
      body['signature'] = await _crypto.signMessage(
        identityId: identityId,
        message: '$consentPrefix${consent.ticket}',
      );
    }
    final data = await _api.post('/oidc/authorize/consent', body: body);
    return (data as Map<String, dynamic>)['redirect'] as String;
  }

  /// Saves [value] as a vault entry for this service, under a key of its own.
  Future<SignInNameOption> _saveName(SignInConsent c, String value) {
    final host = c.clientHost.toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9]'),
      '_',
    );
    return _saveEntry(
      base: 'name_${host.length > 80 ? host.substring(0, 80) : host}',
      value: value,
      label: 'Name on ${c.clientHost}',
      failure: 'The name could not be saved.',
    );
  }

  /// Saves [value] under the key a service asked for. A key the person already
  /// uses keeps its value, because other links may read it: the new entry takes
  /// the next free key, and is shared under the one asked for.
  Future<SignInNameOption> _saveValue(String key, String value) => _saveEntry(
    base: key,
    value: value,
    label: key,
    failure: 'The new value could not be saved.',
  );

  Future<SignInNameOption> _saveEntry({
    required String base,
    required String value,
    required String label,
    required String failure,
  }) async {
    final records = '/api/collections/${AppConfig.recordsCollection}/records';
    try {
      // The base holds only characters a key allows, so it can't break out of
      // the filter.
      final data = await _api.get(
        records,
        queryParams: {'filter': 'key ~ "$base"', 'perPage': '200'},
      );
      final taken = {
        for (final e in (data['items'] as List<dynamic>?) ?? [])
          (e as Map<String, dynamic>)['key'] as String?,
      };
      var key = base;
      for (var n = 2; taken.contains(key); n++) {
        key = '${base}_$n';
      }
      final created = await _api.post(
        records,
        body: {
          'key': key,
          'value': value,
          'label': label,
          'type': 'text',
          'format': 'default',
          'user': Stores.auth.currentUser?.id,
          'workspace': Stores.auth.activeWorkspace,
        },
      );
      return SignInNameOption(
        kind: SignInNameOption.fromRecord,
        id: (created as Map<String, dynamic>)['id'] as String,
        value: value,
        key: key,
      );
    } on ApiException catch (e) {
      // Not left as an ApiException: the ticket is still good, so the person
      // can try again from here. The server's reason goes with it — "could
      // not be saved" alone leaves nothing to change.
      final reason = _fieldMessage(e) ?? e.message;
      throw SignInApprovalException(
        reason.isEmpty ? failure : '$failure $reason',
      );
    }
  }

  /// The first per-field message of a validation refusal, such as the value
  /// field's length limit.
  static String? _fieldMessage(ApiException e) {
    for (final field in (e.data ?? const {}).values) {
      if (field is Map && field['message'] is String) {
        return field['message'] as String;
      }
    }
    return null;
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

  /// The identity the approval is signed with: the first of the person's, in
  /// any workspace, whose key is on this device.
  Future<String> _signingIdentity(SignInConsent consent) async {
    if (_identities.identities.isEmpty) await _identities.loadIdentities();
    final active = _identities.identities.where((i) => !i.isRevoked).toList()
      ..sort((a, b) => (b.isPrimary ? 1 : 0) - (a.isPrimary ? 1 : 0));
    for (final id in {...active.map((i) => i.id), ...consent.signers}) {
      final key = await _crypto.loadPrivateKey(id);
      if (key != null && key.isNotEmpty) return id;
    }
    throw const SignInApprovalException(
      'This device has no identity. The sign-in can be approved on the '
      'device where Revoked was set up, or after creating an identity here.',
    );
  }
}
