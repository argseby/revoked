import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:revoked_app/core/models/record.dart' as models;
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/theme/app_theme.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/features/requests/view/request_create_sheet.dart';
import 'package:revoked_app/features/shares/view/share_create_sheet.dart';
import 'package:revoked_app/features/vault/view/vault_create_sheet.dart';

/// The create forms open with only what most people fill in: developer
/// fields wait under Advanced, a link is created with what it shares, and a
/// request cannot be created asking for nothing.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Stores.init();
  });

  setUp(() {
    Stores.vault.records
      ..clear()
      ..add(
        models.Record(
          id: 'r1',
          key: 'company_name',
          value: 'Acme',
          label: 'Company name',
          type: 'text',
          format: 'default',
          user: 'u',
          workspace: 'w',
        ),
      );
    Stores.vault.sections.clear();
  });

  Future<void> open(
    WidgetTester tester,
    void Function(BuildContext) show,
  ) async {
    tester.view.physicalSize = const Size(780, 1800);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(Brightness.light),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => show(context),
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

  AppButton button(WidgetTester tester, String label) => tester.widget(
    find.ancestor(of: find.text(label), matching: find.byType(AppButton)),
  );

  testWidgets('a record needs no key; it waits under Advanced', (tester) async {
    await open(tester, openVaultCreateSheet);

    expect(find.text('Key'), findsNothing);
    await tester.tap(find.text('Advanced'));
    await tester.pumpAndSettle();
    expect(find.text('Key'), findsOneWidget);
    expect(find.text('From the label: record'), findsOneWidget);
  });

  testWidgets('a link starts from what it shares and is named after it', (
    tester,
  ) async {
    await open(
      tester,
      (context) => openShareCreateSheet(context: context, records: ['r1']),
    );

    expect(find.text('What to share'), findsOneWidget);
    expect(find.text('Company name'), findsOneWidget);
    expect(find.text('From the selection: Company name'), findsOneWidget);
    // A new link lapses by itself unless told otherwise.
    expect(find.text('Never'), findsNothing);
    expect(find.text('URL slug'), findsNothing);
    expect(button(tester, 'Create link').onTap, isNotNull);
  });

  testWidgets('a link sharing nothing cannot be created', (tester) async {
    await open(tester, (context) => openShareCreateSheet(context: context));

    expect(find.text('Required — pick from your vault'), findsOneWidget);
    expect(button(tester, 'Create link').onTap, isNull);
  });

  testWidgets('a request asking for nothing cannot be created', (tester) async {
    await open(
      tester,
      (context) => openRequestCreateSheet(
        context: context,
        store: Stores.requests,
        authStore: Stores.auth,
      ),
    );

    expect(find.text('Required — pick the fields to ask for'), findsOneWidget);
    expect(button(tester, 'Create request').onTap, isNull);
  });
}
