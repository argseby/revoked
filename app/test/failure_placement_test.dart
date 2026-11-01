import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/theme/app_theme.dart';
import 'package:revoked_app/core/widgets/app_alert.dart';
import 'package:revoked_app/core/widgets/app_load_error.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';

/// A failure has to appear where the reader is already looking — at the top of
/// the surface that failed. Both of these were centred in the viewport once,
/// which reads as a state of the whole app rather than of one list.
void main() {
  testWidgets('a toast lands in the top quarter of the screen', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(Brightness.light),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => AppToast.error(context, 'Could not load'),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    final screen = tester.getSize(find.byType(MaterialApp)).height;
    expect(
      tester.getCenter(find.text('Could not load')).dy,
      lessThan(screen / 4),
    );
  });

  testWidgets('a load failure sits at the top of the space it fills', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(Brightness.light),
        home: const Scaffold(
          body: AppLoadError(title: 'Failed to load', message: 'No route'),
        ),
      ),
    );

    final screen = tester.getSize(find.byType(MaterialApp)).height;
    expect(
      tester.getCenter(find.text('Failed to load')).dy,
      lessThan(screen / 4),
    );
  });

  testWidgets('a load failure keeps clear of the edges of a screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(Brightness.light),
        home: const Scaffold(
          body: AppLoadError(title: 'Failed to load', message: 'No route'),
        ),
      ),
    );

    final alert = tester.getRect(find.byType(AppAlert));
    expect(alert.left, AppSpacing.lg);
    expect(alert.right, 375 - AppSpacing.lg);
    expect(alert.top, AppSpacing.lg);
  });

  testWidgets('inside a scrolling page it leaves the page\'s edges alone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(Brightness.light),
        home: const Scaffold(
          body: SingleChildScrollView(
            child: AppLoadError(title: 'Failed to load', message: 'No route'),
          ),
        ),
      ),
    );

    final alert = tester.getRect(find.byType(AppAlert));
    expect(alert.left, 0);
    expect(alert.top, AppSpacing.lg);
  });
}
