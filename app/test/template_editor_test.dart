import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/theme/app_theme.dart';
import 'package:revoked_app/features/templates/view/templates_screen.dart';

/// A template can be created before anything is known about it: no name and
/// no fields still saves one, and the toast says it was created.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('an empty template is created and confirmed', (tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Map<String, dynamic>? sent;
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await Stores.init(
      httpClient: MockClient((request) async {
        if (request.method == 'POST' &&
            request.url.path.contains('/templates/records')) {
          sent = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({'id': 't1', ...sent!}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('{}', 404);
      }),
    );
    Stores.templates.templates.clear();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(Brightness.light),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => openTemplateEditorSheet(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('No fields.'), findsOneWidget);

    await tester.tap(find.text('Create template'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(sent?['name'], 'Untitled template');
    expect(sent?['schema'], {'records': <dynamic>[], 'sections': <dynamic>[]});
    expect(find.text('Template created'), findsOneWidget);
    expect(Stores.templates.templates.single.name, 'Untitled template');

    // Let the toast time out so no timer outlives the test.
    await tester.pumpAndSettle(const Duration(seconds: 10));
  });
}
