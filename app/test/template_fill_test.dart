import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:revoked_app/core/models/record.dart' as models;
import 'package:revoked_app/core/models/template.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/theme/app_theme.dart';
import 'package:revoked_app/features/vault/view/vault_create_sheet.dart';
import 'package:revoked_app/features/vault/views/builtin_views.dart';

/// A template is a checklist of what to store, so a field has to be
/// answerable on its own — and the drawer has to say how much of the list is
/// already in the vault, counting by key rather than by anything the template
/// itself remembers. Typing is only one way to answer: a file opens the
/// picker, and a date opens the calendar — the stored value has to parse as
/// ISO 8601, which is not what anyone types by hand.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Stores.init();
  });

  setUp(() {
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
              {
                'key': 'vat_id',
                'label': 'VAT id',
                'type': 'text',
                'reason': 'Needed for invoicing.',
              },
            ],
            'sections': [
              {
                'key': 'documents',
                'name': 'Documents',
                'records': [
                  {
                    'key': 'passport_scan',
                    'label': 'Passport scan',
                    'type': 'file',
                  },
                  {
                    'key': 'signed_on',
                    'label': 'Signed on',
                    'type': 'datetime',
                    'value': '2026-03-14',
                  },
                ],
              },
              {
                'key': 'contact',
                'name': 'Contact',
                'records': [
                  {'key': 'contact_email', 'label': 'Email', 'type': 'text'},
                  {'key': 'contact_phone', 'label': 'Phone', 'type': 'number'},
                ],
              },
            ],
          },
          created: DateTime(2026),
          updated: DateTime(2026),
        ),
      );
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
  });

  testWidgets('a template lists its fields and counts the filled ones', (
    tester,
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
    expect(find.text('1 of 6 filled'), findsOneWidget);

    await tester.tap(find.text('Supplier onboarding'));
    await tester.pumpAndSettle();
    expect(find.text('Contact'), findsOneWidget);

    // The filled field is done; an unanswered one opens the input drawer,
    // carrying the template's own reason for asking.
    expect(find.text('Company name'), findsOneWidget);
    await tester.ensureVisible(find.text('VAT id'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('VAT id'));
    await tester.pumpAndSettle();
    expect(find.text('Needed for invoicing.'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    // An answered field reopens on what is stored, not on a blank box.
    await tester.ensureVisible(find.text('Company name'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Company name'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      'Acme',
    );

    // Cancel rather than save: the save is a write, and this test has no
    // server behind it.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    // A date is picked, not typed: the picker opens on the template's value.
    await tester.ensureVisible(find.text('Signed on'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Signed on'));
    await tester.pumpAndSettle();
    expect(find.text('Signed on'), findsWidgets);
    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();

    // A file field answers with the picker, not the keyboard.
    await tester.ensureVisible(find.text('Passport scan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Passport scan'));
    await tester.pumpAndSettle();
    expect(find.text('File'), findsOneWidget);
    expect(find.text('Cancel'), findsWidgets);
  });

  testWidgets('a template with a view switches between it and the values', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(780, 1800);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    Stores.templates.templates
      ..clear()
      ..add(
        Template(
          id: 't2',
          name: 'Home Wi-Fi',
          description: '',
          workspace: 'w',
          schema: {
            'records': const [
              {
                'key': 'network_name',
                'label': 'SSID of the router',
                'type': 'text',
              },
              {'key': 'wifi_password', 'label': 'Password', 'type': 'text'},
            ],
            'view': builtinViewJson.firstWhere((v) => v['id'] == 'wifi'),
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
    await tester.tap(find.text('Home Wi-Fi'));
    await tester.pumpAndSettle();

    // The values come first; the view waits behind the switch.
    final viewSwitch = find.byKey(const ValueKey('template-fill-view-switch'));
    expect(viewSwitch, findsOneWidget);
    expect(find.text('wifi_password'), findsOneWidget);
    expect(find.text('Shows as · sample values'), findsNothing);

    await tester.tap(
      find.descendant(of: viewSwitch, matching: find.text('Wi-Fi network')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Shows as · sample values'), findsOneWidget);
    expect(find.text('wifi_password'), findsNothing);

    await tester.tap(
      find.descendant(of: viewSwitch, matching: find.text('Values')),
    );
    await tester.pumpAndSettle();
    expect(find.text('wifi_password'), findsOneWidget);
  });
}
