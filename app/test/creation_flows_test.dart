import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:revoked_app/core/models/record.dart' as models;
import 'package:revoked_app/core/models/section.dart';
import 'package:revoked_app/core/models/template.dart';
import 'package:revoked_app/core/widgets/app_composer.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/theme/app_theme.dart';
import 'package:revoked_app/core/widgets/app_checkbox.dart';
import 'package:revoked_app/core/widgets/app_text_field.dart';
import 'package:revoked_app/features/shares/view/share_contents_picker.dart';
import 'package:revoked_app/features/shares/view/share_create_sheet.dart';
import 'package:revoked_app/features/requests/view/request_create_sheet.dart';
import 'package:revoked_app/features/vault/view/vault_create_sheet.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await Stores.init(
      httpClient: MockClient(
        (request) async => http.Response(
          jsonEncode({'items': []}),
          200,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );
    Stores.vault.records.addAll([
      models.Record(
        id: 'alpha',
        key: 'alpha',
        label: 'Alpha',
        value: 'value',
        type: 'text',
        format: 'default',
        user: 'u',
        workspace: 'w',
      ),
      models.Record(
        id: 'zulu',
        key: 'zulu',
        label: 'Zulu',
        value: '',
        type: 'file',
        format: 'default',
        user: 'u',
        workspace: 'w',
      ),
    ]);
    Stores.vault.sections.add(
      Section(
        id: 'work',
        key: 'work',
        name: 'Work',
        records: ['alpha'],
        user: 'u',
        workspace: 'w',
      ),
    );
  });

  Future<void> open(
    WidgetTester tester,
    void Function(BuildContext) show, {
    Size size = const Size(1100, 1000),
    double scale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(Brightness.light),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => show(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'share picker groups records and preserves selection through search and filters',
    (tester) async {
      await open(tester, (context) {
        openShareContentsPicker(context);
      });
      expect(find.text('Work'), findsOneWidget);
      expect(find.text('Without a section'), findsOneWidget);
      await tester.tap(find.text('Entire section'));
      await tester.pumpAndSettle();
      final alpha = tester.widget<AppCheckRow>(
        find.widgetWithText(AppCheckRow, 'Alpha'),
      );
      expect(alpha.value, isTrue);
      expect(alpha.onChanged, isNull);
      expect(Stores.shares.draftSections, contains('work'));

      await tester.enterText(find.byType(AppTextField), 'Zulu');
      await tester.pumpAndSettle();
      expect(find.text('Work'), findsNothing);
      expect(find.widgetWithText(AppCheckRow, 'Zulu'), findsOneWidget);
      expect(Stores.shares.draftSections, contains('work'));
      await tester.tap(find.widgetWithText(AppCheckRow, 'Zulu'));
      await tester.pumpAndSettle();
      expect(Stores.shares.draftRecords, contains('zulu'));
      await tester.enterText(find.byType(AppTextField), '');
      await tester.tap(find.text('All records'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Files').last);
      await tester.pumpAndSettle();
      expect(find.text('Alpha'), findsNothing);
      expect(find.widgetWithText(AppCheckRow, 'Zulu'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'request access controls immediately update the adjacent summary',
    (tester) async {
      await open(
        tester,
        (context) => openRequestCreateSheet(
          context: context,
          store: Stores.requests,
          authStore: Stores.auth,
        ),
      );
      expect(find.text('Anyone signed in'), findsOneWidget);
      await tester.ensureVisible(find.text('Require a verified identity'));
      await tester.tap(find.text('Require a verified identity'));
      await tester.pumpAndSettle();
      expect(find.text('Anyone signed in'), findsNothing);
      expect(find.text('Verified identities'), findsOneWidget);
      expect(find.text('Accepted identities'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('desktop template rail opens the selected checklist', (
    tester,
  ) async {
    await open(
      tester,
      (context) =>
          openVaultCreateSheet(context, initialTab: VaultCreateTab.template),
    );
    Stores.templates.templates.add(
      Template(
        id: 'checklist',
        name: 'Work checklist',
        description: '',
        workspace: 'w',
        schema: const {
          'records': [
            {'key': 'company', 'label': 'Company', 'type': 'text'},
          ],
        },
        created: DateTime(2026),
        updated: DateTime(2026),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(AppComposerChoice, 'Work checklist'));
    await tester.pumpAndSettle();
    expect(find.text('Company'), findsOneWidget);
    expect(find.text('0 of 1 filled'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  final flows = <String, void Function(BuildContext)>{
    'share': (context) => openShareCreateSheet(context: context),
    'request': (context) => openRequestCreateSheet(
      context: context,
      store: Stores.requests,
      authStore: Stores.auth,
    ),
    'section': (context) =>
        openVaultCreateSheet(context, initialTab: VaultCreateTab.section),
    'template': (context) =>
        openVaultCreateSheet(context, initialTab: VaultCreateTab.template),
    'picker': (context) {
      openShareContentsPicker(context);
    },
  };
  for (final flow in flows.entries) {
    for (final (size, scale) in [
      (const Size(320, 900), 1.0),
      (const Size(375, 1000), 1.8),
      (const Size(1100, 1000), 1.0),
    ]) {
      testWidgets('${flow.key} fits $size at $scale text scale', (
        tester,
      ) async {
        await open(tester, flow.value, size: size, scale: scale);
        // Let the test framework report layout exceptions.
      });
    }
  }
}
