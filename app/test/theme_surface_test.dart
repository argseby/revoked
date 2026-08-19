import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:revoked_app/core/theme/app_theme.dart';
import 'package:revoked_app/core/widgets/app_dialog.dart';
import 'package:revoked_app/core/widgets/app_sheet.dart';

/// One background everywhere: a sheet or dialog that paints a different shade
/// than the page behind it is the patchwork this theme exists to prevent.
void main() {
  for (final brightness in Brightness.values) {
    final theme = AppTheme.build(brightness);
    final page = theme.scaffoldBackgroundColor;

    testWidgets('a sheet matches the page in ${brightness.name}', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showAppSheet(
                  context: context,
                  builder: (_) => const Text('sheet'),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final material = tester.widget<Material>(
        find
            .ancestor(of: find.text('sheet'), matching: find.byType(Material))
            .first,
      );
      expect(material.color, page);
    });

    testWidgets('a dialog matches the page in ${brightness.name}', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () =>
                    showAppDialog(context: context, title: 'Sure?'),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final dialog = tester.widget<AlertDialog>(find.byType(AlertDialog));
      final resolved =
          dialog.backgroundColor ??
          Theme.of(
            tester.element(find.byType(AlertDialog)),
          ).dialogTheme.backgroundColor;
      expect(resolved, page);
    });
  }
}
