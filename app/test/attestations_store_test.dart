import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/features/attestations/store/attestations_store.dart';

/// Issuing writes what a credential will state, so the draft is held to the
/// same shape the server enforces — and a refusal from the server, which
/// decides who may issue at all, is shown as it is.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final created = <Map<String, dynamic>>[];
  final patched = <String, Map<String, dynamic>>{};
  var refuse = false;

  Future<http.Response> server(http.Request request) async {
    final path = request.url.path;
    http.Response json(Object body, [int status = 200]) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

    if (path == '/api/collections/attestations/records' &&
        request.method == 'POST') {
      if (refuse) {
        return json({
          'message': 'This server does not issue attestations.',
          'data': {
            'attestations': {
              'code': 'attestations_disabled',
              'message': 'This server does not issue attestations.',
            },
          },
        }, 403);
      }
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      created.add(body);
      return http.Response(
        jsonEncode({...body, 'id': 'a1', 'status': 'offered'}),
        200,
        headers: {
          'content-type': 'application/json',
          'x-attestation-token': 'one-time-token',
        },
      );
    }
    if (path == '/api/collections/attestations/records/a1' &&
        request.method == 'PATCH') {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      patched['a1'] = body;
      return json({'id': 'a1', 'type': 'membership', 'status': 'revoked'});
    }
    if (path == '/api/server') {
      return json({
        'attestations': {'issuing': true},
      });
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

  setUp(() {
    created.clear();
    patched.clear();
    refuse = false;
    Stores.attestations.attestations.clear();
    Stores.attestations.resetDraft();
  });

  AttestationsStore store() => Stores.attestations;

  test('a draft needs a type, and claims the server would accept', () {
    expect(store().draftProblem, contains('what kind'));

    store().typeController.text = 'two words';
    expect(store().draftProblem, contains('one word'));

    store().typeController.text = 'membership';
    expect(
      store().draftProblem,
      isNull,
      reason: 'a blank claim row is skipped',
    );

    final claim = store().draftClaims.single;
    claim.name.text = 'has space';
    claim.value.text = 'x';
    expect(store().draftProblem, contains('Name each detail'));

    claim.name.text = 'member_no';
    claim.kind = ClaimKind.number;
    claim.value.text = 'forty-two';
    expect(store().draftProblem, contains('isn’t a number'));
    claim.value.text = '42';
    expect(store().draftProblem, isNull);

    store().addClaim();
    store().draftClaims.last
      ..name.text = 'member_no'
      ..value.text = 'again';
    expect(store().draftProblem, contains('twice'));
    store().removeClaim(store().draftClaims.last);

    store().subjectController.text = 'abc';
    expect(store().draftProblem, contains('fingerprint'));
    store().subjectController.text = 'AB' * 32;
    expect(store().draftProblem, isNull);

    store().validDaysController.text = '0';
    expect(store().draftProblem, contains('days'));
  });

  test(
    'an offer is created with typed claims and its link shown once',
    () async {
      store().typeController.text = 'membership';
      store().labelController.text = 'Membership 2027';
      store().draftClaims.single
        ..name.text = 'name'
        ..value.text = ' Ada Lovelace ';
      store().addClaim();
      store().draftClaims.last
        ..name.text = 'age_over_18'
        ..kind = ClaimKind.yesNo;
      store().addClaim();
      store().draftClaims.last
        ..name.text = 'member_no'
        ..kind = ClaimKind.number
        ..value.text = '42';
      // A row left blank states nothing.
      store().addClaim();
      store().subjectController.text = 'AB' * 32;
      store().validDaysController.text = '365';

      expect(await store().create(), isTrue);

      final body = created.single;
      expect(body['user'], 'u1');
      expect(body['workspace'], 'w1');
      expect(body['type'], 'membership');
      expect(body['claims'], {
        'name': 'Ada Lovelace',
        'age_over_18': true,
        'member_no': 42,
      });
      expect(body['subjectFingerprint'], 'ab' * 32);
      final expires = DateTime.parse(body['expiresAt'] as String);
      expect(
        expires.difference(DateTime.now()).inDays,
        inInclusiveRange(364, 365),
      );

      expect(store().lastCreatedToken, 'one-time-token');
      expect(store().attestations.single.id, 'a1');
    },
  );

  test('a draft with a problem is not sent', () async {
    store().typeController.text = 'two words';
    expect(await store().create(), isFalse);
    expect(created, isEmpty);
  });

  test('the operator\'s refusal is shown as what it is', () async {
    refuse = true;
    store().typeController.text = 'membership';
    expect(await store().create(), isFalse);
    expect(store().createError?.code, 'attestations_disabled');
    expect(
      store().createError?.title,
      'This server doesn\'t issue attestations',
    );
    expect(store().lastCreatedToken, isNull);
  });

  test('revoking sends the one transition there is', () async {
    store().typeController.text = 'membership';
    await store().create();
    expect(await store().revoke('a1'), isTrue);
    expect(patched['a1'], {'status': 'revoked'});
    expect(store().attestations.single.isRevoked, isTrue);
  });

  test('the server says whether it issues at all', () async {
    await store().loadPolicy();
    expect(store().issuingAllowed, isTrue);
  });
}
