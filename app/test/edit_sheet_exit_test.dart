import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/theme/app_theme.dart';
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
      // Further down the sheet, below who sees the new entry.
      await tester.scrollUntilVisible(
        find.text('Advanced'),
        200,
        scrollable: find
            .ancestor(
              of: find.text('Visible to'),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Advanced'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Key'));
      await tester.pumpAndSettle();
    }

    testWidgets('is typed where it stands, with no sheet to get out of', (
      tester,
    ) async {
      await openKey(tester);
      expect(find.text('Done'), findsNothing);

      await tester.enterText(
        find.widgetWithText(TextField, 'record'),
        'typed_key',
      );
      await tester.pumpAndSettle();
      expect(Stores.vault.recordKey.text, 'typed_key');
      expect(find.text('Create record'), findsOneWidget);
    });
  });
}
