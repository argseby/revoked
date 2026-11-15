import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobx/mobx.dart';
import 'package:revoked_app/core/models/connection.dart';
import 'package:revoked_app/core/models/request.dart';
import 'package:revoked_app/core/models/template.dart';
import 'package:revoked_app/core/models/user.dart';
import 'package:revoked_app/core/state/tree_folds_store.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/theme/app_theme.dart';
import 'package:revoked_app/features/requests/view/inbox_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _show(WidgetTester tester, {double width = 1400}) async {
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({});
  await Stores.init(
    httpClient: MockClient((request) async {
      if (request.url.path == '/api/requests/flat3b/links') {
        return http.Response(
          jsonEncode({
            'items': [
              {
                'id': 'answer1',
                'senderName': 'Mara',
                'status': 'active',
                'data': {'payslip': 'x', 'schufa': 'y'},
              },
            ],
          }),
          200,
        );
      }
      return http.Response('{"items":[]}', 200);
    }),
  );
  DataRequest request(
    String id,
    String label, {
    String template = '',
    String connection = '',
  }) => DataRequest(
    id: id,
    slug: id,
    label: label,
    status: 'active',
    identity: 'i',
    templateId: template,
    connection: connection,
    responseCount: 1,
    user: 'u',
    workspace: 'w',
  );
  runInAction(() {
    Stores.auth.currentUser = User.fromJson({
      'id': 'u',
      'email': 'jamie@example.com',
      'activeWorkspace': 'w',
    });
    Stores.templates.templates.add(
      Template(
        id: 'tenant',
        name: 'Tenant check',
        description: '',
        workspace: 'w',
        schema: const {},
        created: DateTime(2026),
        updated: DateTime(2026),
      ),
    );
    Stores.connections.connections = ObservableList.of([
      const Connection(
        id: 'conn00000packet',
        clientId: 'https://packet.example',
        clientName: 'Packet',
      ),
    ]);
    Stores.requests.requests.addAll([
      request('flat3b', 'Flat 3B applicants', template: 'tenant'),
      request('contact', 'Emergency contact'),
      request('order', 'Order 2041', connection: 'conn00000packet'),
    ]);
    Stores.requests.loadState.succeed(Stores.requests.loadState.begin());
  });
  tester.view.physicalSize = Size(width, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.build(Brightness.light),
      home: const Scaffold(body: InboxScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final width in [320.0, 1400.0]) {
    testWidgets('requests group by creator and template at $width', (
      tester,
    ) async {
      await _show(tester, width: width);
      double top(String key) => tester.getRect(find.byKey(ValueKey(key))).top;
      expect(find.text('Own requests'), findsOneWidget);
      expect(find.text('Packet'), findsOneWidget);
      expect(
        top('requests-by-own'),
        lessThan(top('requests-by-tool:conn00000packet')),
      );
      // A template first, requests without one after it.
      expect(
        top('request-template-own/tenant'),
        lessThan(top('request-template-own/')),
      );
      expect(
        top('request-template-own/tenant'),
        lessThan(top('request-flat3b')),
      );
      expect(find.text('Tenant check'), findsOneWidget);
      expect(find.text('No template'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('request-template-own/tenant')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('request-flat3b')), findsNothing);
      await tester.tap(
        find.byKey(const ValueKey('request-template-own/tenant')),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('request-flat3b')),
          matching: find.byTooltip('Expand'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Mara'), findsOneWidget);
      expect(find.text('2 fields · payslip, schufa'), findsOneWidget);
      expect(find.textContaining('x'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('folds and opened requests stay when the list is opened again', (
    tester,
  ) async {
    await _show(tester);
    await tester.tap(find.byKey(const ValueKey('request-template-own/')));
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('request-flat3b')),
        matching: find.byTooltip('Expand'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('request-contact')), findsNothing);
    expect(find.text('Mara'), findsOneWidget);

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    runInAction(Stores.requests.responsesByRequest.clear);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(Brightness.light),
        home: const Scaffold(body: InboxScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('request-contact')), findsNothing);
    expect(find.text('Mara'), findsOneWidget);
  });

  test('a new store reads the folds saved on the device', () async {
    SharedPreferences.setMockInitialValues({});
    final first = TreeFoldsStore();
    first.toggle(TreeFold.vaultSources, 'own');
    first.toggle(TreeFold.links, 'lease');
    await pumpEventQueue();

    final second = TreeFoldsStore();
    await second.load();
    expect(second.isOpen(TreeFold.vaultSources, 'own'), isFalse);
    expect(second.isOpen(TreeFold.links, 'lease'), isTrue);
    expect(second.isOpen(TreeFold.links, 'other'), isFalse);
    expect(second.isOpen(TreeFold.requestTemplates, 'any'), isTrue);

    second.forget();
    expect(second.isOpen(TreeFold.vaultSources, 'own'), isTrue);
  });
}
