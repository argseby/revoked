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

/// Sending and asking are the two things a contact is for, so these drive
/// them through the screen: pick a contact, fill the form, and check both
/// outcomes — it reached their app, or here is the link to pass on.
/// The first field of the open sheet — not the list's search above the
/// contacts.
Finder _sheetField() => find
    .descendant(of: find.byType(BottomSheet), matching: find.byType(TextField))
    .first;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final handed = <Map<String, dynamic>>[];
  var contacts = <Map<String, dynamic>>[];
  var delivers = true;
  // Set where the server answers an unconfirmed contact: the grant exists
  // and it says no more than that.
  var reserved = false;

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
        'delivered': !reserved && delivers,
        // The channel the server sends where it is willing to name one; a
        // contact nobody has confirmed gets 'handed_over' instead.
        'channel': reserved
            ? 'handed_over'
            : delivers
            ? 'account'
            : 'manual',
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
    // The identity's key is on this device, so asking can be signed here.
    await Stores.crypto.storePrivateKey('i1', 'test-private-key');
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
    expect(find.text('Add contact'), findsOneWidget);
  });

  testWidgets('a contact with an account here reads as reachable', (
    tester,
  ) async {
    await open(tester);

    expect(find.text('Ada Lovelace'), findsOneWidget);
    expect(find.text('In the app · ada@example.com'), findsOneWidget);
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
    await tester.enterText(_sheetField(), 'My bank details');
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
    await tester.enterText(_sheetField(), 'My number');
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
    expect(
      find.textContaining('has no account here. The link is delivered'),
      findsOneWidget,
    );
  });

  // The reserve the server keeps for an unconfirmed contact has to read as
  // what to do next, not as a claim about the address: "no account here"
  // would be a guess, and the grant may well be in their app already.
  testWidgets('an unconfirmed contact is told the link is theirs to pass on', (
    tester,
  ) async {
    reserved = true;
    addTearDown(() => reserved = false);
    await open(tester);

    await tester.tap(find.text('Ada Lovelace'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send records'));
    await tester.pumpAndSettle();
    await tester.enterText(_sheetField(), 'My number');
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
    expect(
      find.textContaining('already has this if they hold an account here'),
      findsOneWidget,
    );
    expect(find.textContaining('has no account here'), findsNothing);
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
    await tester.enterText(_sheetField(), 'Your new address');
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
