import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:revoked_app/core/models/section.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/theme/app_theme.dart';
import 'package:revoked_app/features/vault/view/vault_create_sheet.dart';

/// A new section and a duplicate are made in one form, the Section tab of
/// the vault's create drawer, whichever button opened it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Stores.init();
  });

  final payroll = Section(
    id: 's1',
    key: 'payroll',
    name: 'Payroll',
    records: const ['r1', 'r2'],
    user: 'u',
    workspace: 'w',
  );

  setUp(() {
    Stores.vault.records.clear();
    Stores.vault.sections
      ..clear()
      ..add(payroll);
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

  testWidgets('+ Section opens the vault drawer on an empty section form', (
    tester,
  ) async {
    await open(
      tester,
      (c) => openVaultCreateSheet(c, initialTab: VaultCreateTab.section),
    );
    expect(find.text('Add to vault'), findsOneWidget);
    expect(find.text('Create section'), findsOneWidget);
    expect(Stores.vault.sectionKey.text, isEmpty);
  });

  testWidgets('Duplicate opens the same form, filled with a copy', (
    tester,
  ) async {
    await open(
      tester,
      (c) => openVaultCreateSheet(c, duplicateSection: payroll),
    );
    expect(find.text('Duplicate section'), findsWidgets);
    expect(find.textContaining('A copy of "Payroll"'), findsOneWidget);
    expect(Stores.vault.sectionKey.text, 'payroll_1');
    expect(Stores.vault.sectionName.text, 'Payroll');
  });
}
