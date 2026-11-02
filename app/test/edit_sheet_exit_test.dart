import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:revoked_app/core/state/observable_text_controller.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/theme/app_theme.dart';
import 'package:revoked_app/core/widgets/app_edit_sheet.dart';
import 'package:revoked_app/features/vault/view/record_create_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A sheet that edits one value closes only through its own buttons, and Done
/// is off while the value is invalid. With Done as its only button, an empty
/// key left the person with no way out at all.
void main() {
  test('no sheet offers a Done that can be off without a Cancel beside it', () {
    final hits = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (RegExp(
        r"label:\s*'Done',\s*onTap:\s*done\b",
      ).hasMatch(entity.readAsStringSync())) {
        hits.add(entity.path);
      }
    }
    expect(hits, isEmpty, reason: 'use AppEditSheetActions');
  });

  group('the key of a new record', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      await Stores.init(
        httpClient: MockClient(
          (_) async => http.Response(
            '{"items":[]}',
            200,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );
    });

    Future<void> openKey(WidgetTester tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      late BuildContext page;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(Brightness.light),
          home: Builder(
            builder: (context) {
              page = context;
              return const Scaffold();
            },
          ),
        ),
      );
      openRecordCreateSheet(
        context: page,
        store: Stores.vault,
        authStore: Stores.auth,
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Advanced'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Advanced'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Key'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Key'));
      await tester.pumpAndSettle();
    }

    testWidgets('left empty, Done closes it, as its text promises', (
      tester,
    ) async {
      await openKey(tester);
      expect(find.text('prod_api_key'), findsOneWidget);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.text('prod_api_key'), findsNothing);
    });

    testWidgets('Cancel gets out of it and drops what was typed', (
      tester,
    ) async {
      await openKey(tester);
      await tester.enterText(find.byType(TextField).last, 'typed_key');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();
      expect(find.text('prod_api_key'), findsNothing);
      expect(Stores.vault.recordKey.text, isEmpty);
    });
  });

  testWidgets('Cancel closes the sheet and puts the text back', (tester) async {
    final controller = ObservableTextController()..text = 'before';
    late BuildContext page;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(Brightness.light),
        home: Builder(
          builder: (context) {
            page = context;
            return const Scaffold();
          },
        ),
      ),
    );
    final result = showAppEditSheet(
      context: page,
      title: 'Label',
      controller: controller,
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'typed');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(await result, isFalse);
    expect(controller.text, 'before');
    expect(find.text('Cancel'), findsNothing);
  });
}
