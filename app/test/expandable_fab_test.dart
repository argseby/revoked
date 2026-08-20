import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/widgets/app_expandable_fab.dart';

/// The vault FAB fans out in place instead of opening a chooser sheet. The
/// contract: collapsed options are neither visible nor tappable, expanding
/// makes them both, and choosing one collapses the fan and runs the action.
void main() {
  Widget host() => MaterialApp(
    home: Scaffold(
      floatingActionButton: AppExpandableFab(
        tooltip: 'Create',
        actions: [
          AppFabAction(
            icon: AppIcons.folderPlus,
            label: 'New Section',
            onTap: () {},
          ),
          AppFabAction(
            icon: AppIcons.filePlus,
            label: 'New Record',
            onTap: () {},
          ),
        ],
      ),
    ),
  );

  testWidgets('collapsed options are invisible and untappable', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          floatingActionButton: AppExpandableFab(
            tooltip: 'Create',
            actions: [
              AppFabAction(
                icon: AppIcons.filePlus,
                label: 'New Record',
                onTap: () => tapped = true,
              ),
            ],
          ),
        ),
      ),
    );

    final opacity = tester.widget<AnimatedOpacity>(
      find.byType(AnimatedOpacity).first,
    );
    expect(opacity.opacity, 0);

    await tester.tap(find.text('New Record'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(tapped, isFalse, reason: 'a hidden option must not be tappable');
  });

  testWidgets('expanding reveals the options, choosing one collapses', (
    tester,
  ) async {
    await tester.pumpWidget(host());

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<AnimatedOpacity>(find.byType(AnimatedOpacity).first)
          .opacity,
      1,
    );
    expect(
      find.byIcon(AppIcons.x),
      findsOneWidget,
      reason: 'the main button reads as "close" while open',
    );

    await tester.tap(find.text('New Section'));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<AnimatedOpacity>(find.byType(AnimatedOpacity).first)
          .opacity,
      0,
      reason: 'choosing an action must collapse the fan',
    );
    expect(find.byIcon(AppIcons.plus), findsOneWidget);
  });
}
