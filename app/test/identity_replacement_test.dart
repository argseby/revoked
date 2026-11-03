import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:revoked_app/core/services/crypto_service.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/features/identities/store/identity_replacement_store.dart';

/// Replacing an identity moves its attestations one by one, each vouched for
/// by the old key on this device; an issuer that cannot be reached leaves its
/// attestation behind and the old identity standing until the person decides.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final oldFingerprint = 'a' * 64;
  final newFingerprint = 'b' * 64;
  late GeneratedIdentity oldKeys;

  // What the server was asked, by path.
  final reissues = <String, Map<String, dynamic>>{};
  final patches = <String, List<Map<String, dynamic>>>{};
  final created = <Map<String, dynamic>>[];
  var unreachable = <String>{};
  var revoked = false;
  // Whether the person already has a second identity, i9.
  var second = false;

  Map<String, dynamic> identity(
    String id,
    String fingerprint, {
    bool primary = false,
  }) => {
    'id': id,
    'name': id == 'i1' ? 'Laptop' : 'Phone',
    'certificate': 'cert-$id',
    'fingerprint': fingerprint,
    'user': 'u1',
    'workspace': 'w1',
    'isPrimary': primary,
    'domainAtIssue': 'home.example',
    'status': id == 'i1' && revoked ? 'revoked' : 'active',
  };

  Map<String, dynamic> credential(String id, String issuer, String bound) => {
    'id': id,
    'issuer': issuer,
    'type': 'membership',
    'identity': bound,
    'workspace': 'w1',
    'credential': 'jwt-$id~',
    'claims': <String, dynamic>{},
  };

  final held = <String, Map<String, dynamic>>{};

  Future<http.Response> server(http.Request request) async {
    final path = request.url.path;
    http.Response json(Object body, [int status = 200]) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

    if (path == '/api/collections/identities/records') {
      if (request.method == 'POST') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        created.add(body);
        return json({...identity('i2', newFingerprint), 'name': body['name']});
      }
      return json({
        'items': [
          identity('i1', oldFingerprint, primary: true),
          if (second) identity('i9', 'c' * 64),
        ],
      });
    }
    if (path.startsWith('/api/collections/identities/records/') &&
        request.method == 'PATCH') {
      final id = path.split('/').last;
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      patches.putIfAbsent(id, () => []).add(body);
      if (body['status'] == 'revoked') revoked = true;
      return json(
        identity(id, id == 'i1' ? oldFingerprint : newFingerprint)
          ..addAll(body),
      );
    }
    if (path == '/api/collections/credentials/records') {
      return json({'items': held.values.toList()});
    }
    final reissue = RegExp(
      r'^/api/credentials/([^/]+)/reissue$',
    ).firstMatch(path);
    if (reissue != null) {
      final id = reissue.group(1)!;
      if (request.method == 'GET') {
        return json({'nonce': 'nonce-for-$id-0123456789'});
      }
      if (unreachable.contains(id)) {
        return json({
          'code': 'remote_unreachable',
          'message': 'The issuer could not be reached.',
        }, 502);
      }
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      reissues[id] = body;
      held[id] = {...held[id]!, 'identity': body['identityId']};
      return json(held[id]!);
    }
    if (path.endsWith('/status')) {
      return json({'state': 'verified', 'reason': '', 'status': 'valid'});
    }
    return json({'items': <Object>[]});
  }

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await Stores.init(httpClient: MockClient(server));
    await Stores.api.saveAuthState('session-token', {
      'id': 'u1',
      'activeWorkspace': 'w1',
    });
  });

  setUp(() async {
    reissues.clear();
    patches.clear();
    created.clear();
    unreachable = {};
    revoked = false;
    second = false;
    held
      ..clear()
      ..addAll({
        'c1': credential('c1', 'club.example', 'i1'),
        'c2': credential('c2', 'verify.example', 'i1'),
        'c3': credential('c3', 'club.example', 'i9'),
      });
    oldKeys = Stores.crypto.generateIdentity(commonName: 'Laptop');
    await Stores.crypto.storePrivateKey('i1', oldKeys.privateKeyPem);
    await Stores.identities.loadIdentities();
    await Stores.credentials.load();
  });

  IdentityReplacementStore store() => Stores.identityReplacement;

  bool verifies(String keyPem, String message, String signature) =>
      Stores.crypto.verifySignature(
        publicKeyPem: keyPem,
        message: message,
        signatureBytes: Uint8List.fromList(base64Decode(signature)),
      );

  test('the old key vouches, the new key answers, and the old identity '
      'stands until every attestation moved', () async {
    unreachable = {'c2'};
    store().begin(Stores.identities.byId('i1')!);
    expect(store().bound.map((c) => c.id), ['c1', 'c2']);
    store().nameController.text = 'Phone';
    expect(store().problem, isNull);

    await store().start();

    expect(created.single['name'], 'Phone');
    expect(store().to?.id, 'i2');
    expect(store().moved.map((c) => c.id), ['c1']);
    expect(store().failed.single.credential.id, 'c2');
    expect(store().failed.single.reason, 'The issuer could not be reached.');
    expect(store().stage, ReplacementStage.review);
    expect(
      patches['i1'],
      isNull,
      reason: 'revoking the old identity would end its key\'s say',
    );
    expect(reissues.keys, isNot(contains('c3')));
    expect(
      patches['i2'],
      contains(containsPair('isPrimary', true)),
      reason: 'the primary\'s successor becomes the primary',
    );

    final sent = reissues['c1']!;
    final nonce = sent['challengeNonce'] as String;
    expect(nonce, 'nonce-for-c1-0123456789');
    final voucher = sent['voucher'] as Map<String, dynamic>;
    final payload = utf8.decode(
      base64Url.decode(base64Url.normalize(voucher['payload'] as String)),
    );
    expect(payload, startsWith('{"type":"credential-reissue-v1"'));
    expect(jsonDecode(payload), {
      'type': 'credential-reissue-v1',
      'issuer': 'club.example',
      'oldFingerprint': oldFingerprint,
      'newFingerprint': newFingerprint,
      'nonce': nonce,
    });
    expect(
      verifies(oldKeys.publicKeyPem, payload, voucher['signature'] as String),
      isTrue,
      reason: 'the voucher is signed with the old identity\'s key',
    );
    expect(
      verifies(
        created.single['publicKey'] as String,
        nonce,
        sent['challengeSignature'] as String,
      ),
      isTrue,
      reason: 'the challenge is answered with the new identity\'s key',
    );
    expect(Stores.credentials.boundTo('i2').map((c) => c.id), ['c1']);

    unreachable = {};
    await store().retry();

    expect(store().failed, isEmpty);
    expect(store().moved.map((c) => c.id), ['c1', 'c2']);
    expect(patches['i1'], contains(containsPair('status', 'revoked')));
    expect(store().stage, ReplacementStage.done);
    expect(await Stores.crypto.loadPrivateKey('i1'), isNull);
  });

  test(
    'the old identity can be revoked with attestations left on it',
    () async {
      unreachable = {'c2'};
      store().begin(Stores.identities.byId('i1')!);
      await store().start();
      expect(store().stage, ReplacementStage.review);

      await store().revokeAnyway();

      expect(patches['i1'], contains(containsPair('status', 'revoked')));
      expect(store().stage, ReplacementStage.done);
      expect(Stores.credentials.boundTo('i1').map((c) => c.id), ['c2']);
    },
  );

  test(
    'an identity the person already has can take the old one\'s place',
    () async {
      second = true;
      await Stores.crypto.storePrivateKey(
        'i9',
        Stores.crypto.generateIdentity(commonName: 'Phone').privateKeyPem,
      );
      await Stores.identities.loadIdentities();
      store().begin(Stores.identities.byId('i1')!);
      expect(store().targets.map((i) => i.id), ['i9']);
      store().chooseTarget('i9');
      store().nameController.clear();
      expect(store().problem, isNull, reason: 'no name is needed for it');

      await store().start();

      expect(created, isEmpty);
      expect(reissues.keys, ['c1', 'c2']);
      expect(reissues.values.map((r) => r['identityId']).toSet(), {'i9'});
      expect(patches['i9'], contains(containsPair('isPrimary', true)));
      expect(patches['i1'], contains(containsPair('status', 'revoked')));
      expect(store().stage, ReplacementStage.done);
      await Stores.crypto.deletePrivateKey('i9');
    },
  );

  test('an identity whose key is elsewhere cannot vouch from here', () async {
    await Stores.crypto.deletePrivateKey('i1');
    await Stores.identities.loadIdentities();
    store().begin(Stores.identities.byId('i1')!);
    expect(store().problem, contains('not on this device'));

    await store().start();

    expect(created, isEmpty);
    expect(reissues, isEmpty);
    expect(store().stage, ReplacementStage.choosing);
  });
}
