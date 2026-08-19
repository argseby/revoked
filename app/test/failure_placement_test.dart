import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:revoked_app/core/theme/app_theme.dart';
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
}
