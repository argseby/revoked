import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:revoked_app/core/models/request.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/features/data/view/data_screen.dart';

/// The per-request list shows every response the sheet shows. It is built
/// from answered fields, so a response with none — sent on a form that asked
/// for nothing, or withdrawn by its responder — used to vanish from the list
/// while the sheet still had a row for it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Stores.init();
  });

  Future<void> show(
    WidgetTester tester, {
    required DataRequest request,
    required List<Map<String, dynamic>> responses,
  }) async {
    Stores.requests.requests
      ..clear()
      ..add(request);
    Stores.requests.responsesByRequest
      ..clear()
      ..[request.id] = responses;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: DataScreen(requestId: request.id)),
      ),
    );
    // The screen refreshes from the server on open; in tests every call fails
    // fast and leaves the data above in place.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();
  }

  DataRequest request({String templateId = ''}) => DataRequest(
    id: 'r1',
    slug: 'w3bi7j',
    label: 'Please give me all your data!',
    status: 'active',
    identity: 'i1',
    templateId: templateId,
    user: 'u',
    workspace: 'w',
  );

  Map<String, dynamic> response({
    String status = 'active',
    Map<String, dynamic> data = const {},
  }) => {
    'slug': 'g_1',
    'status': status,
    'data': data,
    'senderName': '',
    'identity': '',
    'created': '2026-10-11T23:58:04Z',
  };

  testWidgets('a response to a form without fields is listed and explained', (
    tester,
  ) async {
    await show(tester, request: request(), responses: [response()]);

    expect(find.text('Responses are listed here'), findsNothing);
    expect(find.text('Anonymous'), findsOneWidget);
    expect(find.text('0 fields'), findsOneWidget);
    expect(find.textContaining('This request asks for none'), findsOneWidget);
  });

  testWidgets('a withdrawn response stays listed as withdrawn', (tester) async {
    await show(
      tester,
      request: request(templateId: 't1'),
      responses: [response(status: 'revoked')],
    );

    expect(find.text('Anonymous'), findsOneWidget);
    expect(find.textContaining('answers were withdrawn'), findsOneWidget);
  });

  testWidgets('answered fields are listed as before', (tester) async {
    await show(
      tester,
      request: request(templateId: 't1'),
      responses: [
        response(data: {'iban': 'DE89 3704 0044 0532 0130 00'}),
      ],
    );

    expect(find.text('1 field'), findsOneWidget);
    expect(find.text('iban'), findsOneWidget);
    expect(find.textContaining('without any fields'), findsNothing);
  });
}
