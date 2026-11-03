import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:revoked_app/core/models/record.dart' as models;
import 'package:revoked_app/core/models/section.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/features/vault/tool_reach_confirm.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Putting a record into a section a connected tool reads hands it to the
/// tool, so the owner is asked first, with the tool named. A record a tool
/// wrote says so.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<Map<String, dynamic>> tools;
  late List<String> filters;
  late bool failing;

  Future<http.Response> server(http.Request request) async {
    if (failing) return http.Response('{}', 500);
    if (request.url.path == '/api/collections/connections/records') {
      filters.add(request.url.queryParameters['filter'] ?? '');
      return http.Response(
        jsonEncode({'items': tools}),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    return http.Response('{}', 404);
  }

  final section = Section(
    id: 's1',
    key: 'documents',
    name: 'Documents',
    records: const [],
    user: 'u1',
    workspace: 'w1',
  );
  final record = models.Record.fromJson({
    'id': 'r1',
    'key': 'iban',
    'label': 'IBAN',
    'type': 'text',
    'format': 'default',
    'user': 'u1',
    'workspace': 'w1',
  });

  Future<bool?> ask(WidgetTester tester, {String? answer}) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await Stores.init(httpClient: MockClient(server));
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async =>
                result = await confirmToolsReach(context, section, record),
            child: const Text('add'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('add'));
    await tester.pumpAndSettle();
    if (answer != null) {
      await tester.tap(find.widgetWithText(FilledButton, answer));
      await tester.pumpAndSettle();
    }
    return result;
  }

  setUp(() {
    failing = false;
    filters = [];
    tools = [
      {
        'id': 'c1',
        'clientId': 'https://tool.example',
        'clientName': 'Flat tool',
        'expiresAt': '2099-01-01 00:00:00.000Z',
        'vaultAccess': 'write',
        'section': 's1',
      },
    ];
  });

  testWidgets('a section a tool reads asks first, naming the tool', (
    tester,
  ) async {
    final result = await ask(tester);
    expect(filters.single, 'section = "s1" || sections ~ "s1"');
    expect(find.text('Let Flat tool read IBAN?'), findsOneWidget);
    expect(find.textContaining('Flat tool (tool.example)'), findsOneWidget);
    expect(result, isNull);

    await tester.tap(find.widgetWithText(FilledButton, 'Add to section'));
    await tester.pumpAndSettle();
  });

  testWidgets('agreeing adds it', (tester) async {
    expect(await ask(tester, answer: 'Add to section'), isTrue);
  });

  testWidgets('a tool that may not read the vault is not asked about', (
    tester,
  ) async {
    tools.single['vaultAccess'] = '';
    expect(await ask(tester), isTrue);
    expect(find.text('Let Flat tool read IBAN?'), findsNothing);
  });

  testWidgets('when the tools can\'t be checked, it still asks', (
    tester,
  ) async {
    failing = true;
    final result = await ask(tester);
    expect(find.text('Add IBAN to Documents?'), findsOneWidget);
    expect(result, isNull);

    await tester.tap(find.widgetWithText(FilledButton, 'Add to section'));
    await tester.pumpAndSettle();
  });

  test('a record a tool wrote carries its name', () {
    final written = models.Record.fromJson({
      'id': 'r2',
      'key': 'save',
      'label': 'Save game',
      'type': 'text',
      'format': 'default',
      'user': 'u1',
      'workspace': 'w1',
      'writtenBy': 'c1',
      'writtenByName': 'Flat tool',
    });
    expect(written.isWrittenByTool, isTrue);
    expect(written.writerName, 'Flat tool');
    expect(record.isWrittenByTool, isFalse);
  });
}
