import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/theme/app_theme.dart';
import 'package:revoked_app/features/contacts/view/contacts_screen.dart';

/// Sending and asking are the two things a contact is for, so these drive
/// them through the screen: pick a contact, fill the form, and check both
/// outcomes — it reached their app, or here is the link to pass on.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final handed = <Map<String, dynamic>>[];
  var contacts = <Map<String, dynamic>>[];
  var delivers = true;

  Future<http.Response> server(http.Request request) async {
    final path = request.url.path;
    http.Response json(Object body, [int status = 200]) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

    if (path.startsWith('/api/contacts/')) {
      final parts = path.split('/');
      final action = parts.last;
      handed.add({
        'action': action,
        ...jsonDecode(request.body) as Map<String, dynamic>,
      });
      return json({
        'ok': true,
        'id': 'g1',
        'slug': 'abc123',
        'kind': action == 'ask' ? 'request' : 'share',
        'delivered': delivers,
      });
    }
    if (path == '/api/collections/contacts/records') {
      return json({'items': contacts});
    }
    if (path.startsWith('/api/collections/contacts/records/')) {
      return json(contacts.first);
    }
    if (path == '/api/collections/records/records') {
      return json({
        'items': [
          {
            'id': 'r1',
            'key': 'iban',
            'label': 'IBAN',
            'type': 'text',
            'format': 'default',
            'value': 'DE89',
            'user': 'u1',
            'workspace': 'w1',
          },
        ],
      });
    }
    if (path == '/api/collections/identities/records') {
      return json({
        'items': [
          {
            'id': 'i1',
            'name': 'Landlord',
            'certificate': '',
            'fingerprint': 'ab' * 32,
            'user': 'u1',
            'workspace': 'w1',
            'status': 'active',
            'isPrimary': true,
          },
        ],
      });
    }
    return json({'items': <Object>[]});
  }

  // Built per case; a store outliving the zone it was first used in runs every
  // later async action in a dead one.
  setUp(() async {
    handed.clear();
    delivers = true;
    contacts = [
      {
        'id': 'c1',
        'workspace': 'w1',
        'name': 'Ada Lovelace',
        'email': 'ada@example.com',
        'user': 'u2',
        'trustState': 'unverified',
      },
    ];
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await Stores.init(httpClient: MockClient(server));
    await Stores.api.saveAuthState('session-token', {
      'id': 'u1',
      'activeWorkspace': 'w1',
    });
  });

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(Brightness.light),
        home: const Scaffold(body: ContactsScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('with nobody saved, it says what a contact is for', (
    tester,
  ) async {
    contacts = [];
    await open(tester);

    expect(find.text('No contacts'), findsOneWidget);
    expect(find.text('Add a contact'), findsOneWidget);
  });

  testWidgets('a contact with an account here reads as reachable', (
    tester,
  ) async {
    await open(tester);

    expect(find.text('Ada Lovelace'), findsOneWidget);
    expect(find.textContaining('In the app'), findsOneWidget);
  });

  testWidgets('sending picks vault entries and reports it arrived', (
    tester,
  ) async {
    await open(tester);

    await tester.tap(find.text('Ada Lovelace'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send records'));
    await tester.pumpAndSettle();

    expect(find.text('Send to Ada Lovelace'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'My bank details');
    await tester.pumpAndSettle();

    // Nothing picked yet, so the button is still refusing.
    expect(Stores.contacts.canSend, isFalse);

    await tester.tap(find.text('Select from the vault'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('IBAN'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Share 1 item'));
    await tester.pumpAndSettle();

    expect(Stores.contacts.canSend, isTrue);
    await tester.tap(find.widgetWithText(FilledButton, 'Send'));
    await tester.pumpAndSettle();

    expect(handed.single, {
      'action': 'send',
      'records': ['r1'],
      'sections': <String>[],
      'label': 'My bank details',
    });
    // It reached their app, so there is no link to pass on.
    expect(find.textContaining('Link for'), findsNothing);
  });

  testWidgets('a contact with no account here gets the link to pass on', (
    tester,
  ) async {
    delivers = false;
    await open(tester);

    await tester.tap(find.text('Ada Lovelace'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send records'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'My number');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select from the vault'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('IBAN'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Share 1 item'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Send'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Link for Ada Lovelace'), findsOneWidget);
    expect(find.textContaining('has no account here. The link is delivered'), findsOneWidget);
  });

  testWidgets('asking is signed with an identity of this workspace', (
    tester,
  ) async {
    await open(tester);

    await tester.tap(find.text('Ada Lovelace'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Request data'));
    await tester.pumpAndSettle();

    expect(find.text('Request from Ada Lovelace'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'Your new address');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Ask'));
    await tester.pumpAndSettle();

    expect(handed.single, {
      'action': 'ask',
      'label': 'Your new address',
      'identity': 'i1',
    });
  });
}
