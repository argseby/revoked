import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/theme/app_theme.dart';
import 'package:revoked_app/core/widgets/app_qr_code.dart';
import 'package:revoked_app/features/attestations/view/attestation_check_sheet.dart';

/// Asking someone to show an attestation: the asker's server makes the link,
/// the sheet shows it and waits, and the verdict appears in the same sheet
/// once the other person answered.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final created = <Map<String, dynamic>>[];
  var answered = false;

  Map<String, dynamic> record() => {
    'id': 'chk1',
    'type': 'membership',
    'issuers': ['club.test'],
    'claims': ['member_since'],
    'status': answered ? 'answered' : 'open',
    'expiresAt': DateTime.now()
        .toUtc()
        .add(const Duration(minutes: 10))
        .toIso8601String(),
    'answeredAt': answered ? DateTime.now().toUtc().toIso8601String() : '',
    if (answered)
      'result': {
        'state': 'verified',
        'reason': 'club.test attests this.',
        'issuer': 'club.test',
        'type': 'membership',
        'claims': {'member_since': 2021},
        'withheld': 2,
        'holder': {'fingerprint': 'ab' * 32, 'domain': 'home.test'},
      },
  };

  Future<http.Response> server(http.Request request) async {
    http.Response json(Object body) => http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json'},
    );
    final path = request.url.path;
    if (path == '/api/attestation-checks' && request.method == 'POST') {
      created.add(jsonDecode(request.body) as Map<String, dynamic>);
      return json({
        'id': 'chk1',
        'expiresAt': record()['expiresAt'],
        'present': {
          'client_id': 'https://home.test',
          'response_uri':
              'https://home.test/api/public/attestation-checks/answer',
          'nonce': 'n' * 64,
          'state': 'chk1',
          'type': 'membership',
        },
      });
    }
    if (path == '/api/collections/attestationChecks/records/chk1') {
      return json(record());
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

  testWidgets('the check is shown as a code, and the answer appears in place', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(Brightness.light),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => openAttestationCheckSheet(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), 'membership');
    await tester.enterText(find.byType(TextField).at(1), 'Club.test');
    await tester.enterText(find.byType(TextField).at(2), 'member_since');
    await tester.tap(find.text('Create check'));
    await tester.pump();
    await tester.pump();

    expect(created.single['type'], 'membership');
    expect(created.single['issuers'], ['club.test']);
    expect(created.single['claims'], ['member_since']);
    expect(find.text('Show this to them'), findsOneWidget);
    expect(find.byType(AppQrCode), findsOneWidget);
    expect(
      Stores.attestationChecks.pendingLink,
      startsWith('revoked://present?'),
    );

    answered = true;
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();

    expect(find.text('What they showed'), findsWidgets);
    expect(find.text('Verified'), findsOneWidget);
    expect(find.text('2021'), findsOneWidget);
    expect(find.text('2 details'), findsOneWidget);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(Stores.attestationChecks.pending, isNull);
  });
}
