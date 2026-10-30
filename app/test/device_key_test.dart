import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:revoked_app/core/models/attestation_ask.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/theme/app_theme.dart';
import 'package:revoked_app/core/widgets/identity_picker.dart';

/// Signing in on a second device lists the account's identities, but their
/// keys stayed on the device that made them. The app has to say so before
/// anything tries to sign, and offer to make one here.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final created = <Map<String, dynamic>>[];

  Map<String, dynamic> identity(String id, String name) => {
    'id': id,
    'name': name,
    'certificate': '',
    'fingerprint': 'ab' * 32,
    'user': 'u',
    'workspace': 'w',
    'isPrimary': id == 'phone',
    'domainAtIssue': '',
    'status': 'active',
  };

  Future<http.Response> server(http.Request request) async {
    http.Response json(Object body) => http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json'},
    );
    if (request.url.path == '/api/collections/identities/records') {
      if (request.method == 'POST') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        created.add(body);
        return json(identity('here', body['name'] as String));
      }
      return json({
        'items': [identity('phone', 'Phone')],
      });
    }
    return json({'items': <Object>[]});
  }

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await Stores.init(httpClient: MockClient(server));
    await Stores.api.saveAuthState('session', {
      'id': 'u',
      'activeWorkspace': 'w',
    });
  });

  testWidgets('an identity whose key is elsewhere cannot be picked, and one '
      'can be made here', (tester) async {
    await Stores.identities.loadIdentities();
    expect(Stores.identities.keysElsewhere, isTrue);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(Brightness.light),
        home: Scaffold(
          body: SingleChildScrollView(
            child: IdentityPicker(selectedId: null, onChanged: (_) {}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No identity on this device yet'), findsOneWidget);
    expect(
      find.text('Key on another device - it can\'t sign here'),
      findsOneWidget,
    );

    await tester.tap(find.text('Create for this device'));
    await tester.pumpAndSettle();

    expect(created.single['name'], isNotEmpty);
    expect(created.single.containsKey('privateKey'), isFalse);
    expect(Stores.identities.hasLocalKey('here'), isTrue);
    expect(Stores.identities.keysElsewhere, isFalse);
    expect(find.text('No identity on this device yet'), findsNothing);
  });

  test('an ask fills in the Attest form without its values', () {
    Stores.attestations.resetDraft(
      ask: AttestationAsk(
        type: 'membership',
        claims: const ['member_since', 'board'],
        fingerprint: 'cd' * 32,
        name: 'Laptop',
      ),
    );
    final store = Stores.attestations;
    expect(store.typeController.text, 'membership');
    expect(store.subjectController.text, 'cd' * 32);
    expect(store.labelController.text, 'membership — Laptop');
    expect(
      [for (final c in store.draftClaims) c.trimmedName],
      ['member_since', 'board'],
    );
    expect(store.draftClaims.every((c) => c.value.text.isEmpty), isTrue);

    store.resetDraft();
    expect(store.draftAsk, isNull);
    expect(store.typeController.text, isEmpty);
  });
}
