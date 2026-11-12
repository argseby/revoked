import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/theme/app_theme.dart';
import 'package:revoked_app/features/contacts/view/contacts_screen.dart';

/// Before anyone taps Send, the sheet says where the grant will actually go.
/// The button is never disabled — the grant is minted either way and the slug
/// comes back — so the expectation is set in words instead.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final handed = <Map<String, dynamic>>[];
  var contacts = <Map<String, dynamic>>[];
  var delivers = true;
  String? mailPolicy;
  var signupsOpen = true;

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
        // The channel the server sends where it is willing to name one; a
        // contact nobody has confirmed gets 'handed_over' instead.
        'channel': delivers ? 'account' : 'manual',
      });
    }
    if (path == '/api/server') {
      return json({
        'domain': 'test.invalid',
        'signups': {'open': signupsOpen},
        if (mailPolicy != null) 'mail': {'recipients': mailPolicy},
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
    mailPolicy = null;
    signupsOpen = true;
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

  /// Ada, but with no account on this server — the case email exists for.
  Map<String, dynamic> emailOnly() => {
    'id': 'c1',
    'workspace': 'w1',
    'name': 'Ada Lovelace',
    'email': 'ada@elsewhere.example',
    'trustState': 'unverified',
  };

  Future<void> openSend(WidgetTester tester) async {
    await open(tester);
    await tester.tap(find.text('Ada Lovelace'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send records'));
    await tester.pumpAndSettle();
  }

  testWidgets('with no mail policy, the sender is told to pass the link on', (
    tester,
  ) async {
    contacts = [emailOnly()];
    await openSend(tester);

    expect(
      find.textContaining('The link is returned for manual delivery'),
      findsOneWidget,
    );
  });

  testWidgets('where the policy reaches them, it says an email goes out', (
    tester,
  ) async {
    mailPolicy = 'all';
    contacts = [emailOnly()];
    await openSend(tester);

    expect(find.textContaining('receives the link by email'), findsOneWidget);
  });

  testWidgets('an address outside the policy is told so before the tap', (
    tester,
  ) async {
    mailPolicy = 'same-domain';
    contacts = [emailOnly()];
    await openSend(tester);

    expect(
      find.textContaining('The link is returned for manual delivery'),
      findsOneWidget,
    );
    // The button still works: the grant is minted and the slug comes back.
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Send'))
          .onPressed,
      isNull,
      reason:
          'nothing is picked yet, so Send waits on the form, not the policy',
    );
  });

  testWidgets('someone with an account here is reached in the app', (
    tester,
  ) async {
    mailPolicy = 'all';
    await openSend(tester);

    expect(
      find.textContaining('Delivered to Ada Lovelace\u2019s app'),
      findsOneWidget,
    );
  });

  testWidgets('an ask explains the account it needs when signups are shut', (
    tester,
  ) async {
    mailPolicy = 'all';
    signupsOpen = false;
    contacts = [emailOnly()];
    await open(tester);
    await tester.tap(find.text('Ada Lovelace'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Request data'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('needs an account here to respond'),
      findsOneWidget,
    );
  });
}
