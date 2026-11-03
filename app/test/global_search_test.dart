import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mobx/mobx.dart';

import 'package:revoked_app/core/models/user.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/theme/app_theme.dart';
import 'package:revoked_app/features/shell/view/link_search_sheet.dart';

/// The shell's panel is the only search in the app, so it has to reach every
/// kind — and say so when it has only seen one page of a list.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  var records = <Map<String, dynamic>>[];

  Future<http.Response> server(http.Request request) async {
    final path = request.url.path;
    http.Response json(Object body, [int status = 200]) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

    switch (path) {
      case '/api/collections/records/records':
        return json({'items': records});
      case '/api/collections/links/records':
        return json({
          'items': [
            {
              'id': 'l1',
              'label': 'Move-in pack',
              'slug': 'aaa111',
              'status': 'active',
            },
          ],
        });
      case '/api/collections/contacts/records':
        return json({
          'items': [
            {
              'id': 'c1',
              'workspace': 'w1',
              'name': 'Movers Ltd',
              'email': 'hi@movers.test',
              'trustState': 'unverified',
            },
          ],
        });
      default:
        return json({'items': <Object>[]});
    }
  }

  models(String id, String key) => {
    'id': id,
    'key': key,
    'value': 'DE89370400440532013000',
    'label': '',
    'type': 'text',
    'format': 'hidden',
    'user': 'u1',
    'workspace': 'w1',
  };

  // Built per case; a store outliving the zone it was first used in runs every
  // later async action in a dead one.
  setUp(() async {
    records = [models('r1', 'move_date')];
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    // The panel reads the clipboard as it opens; unmocked, that never
    // answers and the panel never appears.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.getData') return {'text': ''};
          return null;
        });
    await Stores.init(httpClient: MockClient(server));
    await Stores.api.saveAuthState('session-token', {
      'id': 'u1',
      'activeWorkspace': 'w1',
    });
    // The panel only searches for someone signed in, and that is the auth
    // store's own user rather than the stored token.
    runInAction(
      () => Stores.auth.currentUser = User.fromJson({
        'id': 'u1',
        'email': 'ada@example.com',
        'activeWorkspace': 'w1',
      }),
    );
  });

  Future<void> openPanel(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(Brightness.light),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => openLinkSearchSheet(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('one query reaches records, links and contacts at once', (
    tester,
  ) async {
    await openPanel(tester);
    await tester.enterText(find.byType(TextField).first, 'move');
    await tester.pumpAndSettle();

    // Each kind heads its own group, so the reader can tell them apart.
    expect(find.text('Record'), findsOneWidget);
    expect(find.text('Link'), findsOneWidget);
    expect(find.text('Contact'), findsOneWidget);

    expect(find.text('move_date'), findsOneWidget);
    expect(find.text('Move-in pack'), findsOneWidget);
    expect(find.text('Movers Ltd'), findsOneWidget);
  });

  testWidgets('a value is never matched, however much of it you type', (
    tester,
  ) async {
    await openPanel(tester);
    await tester.enterText(find.byType(TextField).first, 'DE8937');
    await tester.pumpAndSettle();

    expect(find.textContaining('No matches for'), findsOneWidget);
    expect(find.text('move_date'), findsNothing);
  });

  testWidgets('a list seen only one page deep says so', (tester) async {
    records = [for (var i = 0; i < 500; i++) models('r$i', 'move_$i')];
    await openPanel(tester);
    await tester.enterText(find.byType(TextField).first, 'move');
    await tester.pumpAndSettle();

    expect(find.textContaining('most recent 500'), findsOneWidget);
    expect(find.textContaining('Older entries may exist'), findsOneWidget);
  });
}
