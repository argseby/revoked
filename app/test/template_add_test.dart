import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:revoked_app/core/models/template.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/theme/app_theme.dart';
import 'package:revoked_app/features/vault/view/vault_create_sheet.dart';

/// A template is added to the vault before any of it is answered: its
/// section is made empty, and a toast says so.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a template with no answers is added as an empty section', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Map<String, dynamic>? sent;
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await Stores.init(
      httpClient: MockClient((request) async {
        if (request.method == 'POST' && request.url.path.contains('section')) {
          sent = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({'id': 's1', 'user': '', 'workspace': '', ...sent!}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('{}', 404);
      }),
    );
    Stores.vault.sections.clear();
    Stores.vault.records.clear();
    Stores.templates.templates
      ..clear()
      ..add(
        Template(
          id: 't1',
          name: 'Supplier onboarding',
          description: '',
          workspace: 'w',
          schema: const {
            'records': [
              {'key': 'company_name', 'label': 'Company name', 'type': 'text'},
            ],
          },
          created: DateTime(2026),
          updated: DateTime(2026),
        ),
      );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(Brightness.light),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => openVaultCreateSheet(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Template'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Supplier onboarding').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Create section'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(sent?['name'], 'Supplier onboarding');
    expect(sent?['records'], isEmpty);
    expect(find.text('Section created'), findsOneWidget);
    expect(Stores.vault.sections.single.name, 'Supplier onboarding');

    await tester.pumpAndSettle(const Duration(seconds: 10));
  });
}
