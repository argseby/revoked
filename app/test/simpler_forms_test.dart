import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:revoked_app/core/models/record.dart' as models;
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/theme/app_theme.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/features/requests/view/request_create_sheet.dart';
import 'package:revoked_app/features/shares/view/share_create_sheet.dart';
import 'package:revoked_app/core/files/pending_upload.dart';
import 'package:revoked_app/features/vault/view/record_create_sheet.dart';
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
    expect(find.text('Defaults to record when empty.'), findsOneWidget);
  });

  void openRecord(BuildContext context) => openRecordCreateSheet(
    context: context,
    store: Stores.vault,
    authStore: Stores.auth,
  );

  testWidgets('leaving yes/no offers nothing back for an empty value', (
    tester,
  ) async {
    await open(tester, openRecord);
    await tester.tap(find.text('Yes or no'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Text'));
    await tester.pumpAndSettle();

    expect(Stores.vault.recordValue.text, isEmpty);
    expect(find.textContaining('Auto:'), findsNothing);
  });

  testWidgets('an attached file shows what it is and can be removed', (
    tester,
  ) async {
    await open(tester, openRecord);
    await tester.tap(find.text('File'));
    await tester.pumpAndSettle();
    expect(find.text('Choose a file'), findsOneWidget);

    Stores.vault.setPickedFile(
      PendingUpload(name: 'lease.pdf', size: 2048, open: () => Stream.empty()),
    );
    await tester.pumpAndSettle();
    expect(find.text('lease.pdf'), findsOneWidget);

    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(Stores.vault.pickedFile, isNull);
    expect(find.text('Choose a file'), findsOneWidget);
  });

  testWidgets('a link starts from what it shares and is named after it', (
    tester,
  ) async {
    await open(
      tester,
      (context) => openShareCreateSheet(context: context, records: ['r1']),
    );

    expect(find.text('What to share'), findsOneWidget);
    expect(find.text('Defaults to Company name.'), findsOneWidget);
    // A new link lapses by itself unless told otherwise.
    expect(find.text('Never'), findsNothing);
    expect(find.text('URL slug'), findsNothing);
    expect(button(tester, 'Create link').onTap, isNotNull);
  });

  testWidgets('a link sharing nothing cannot be created', (tester) async {
    await open(tester, (context) => openShareCreateSheet(context: context));

    expect(find.text('Select from the vault'), findsOneWidget);
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

    expect(find.text('No template selected'), findsOneWidget);
    expect(button(tester, 'Create request').onTap, isNull);
  });
}
