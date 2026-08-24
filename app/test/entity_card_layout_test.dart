import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/theme/app_theme.dart';
import 'package:revoked_app/core/widgets/app_badge.dart';
import 'package:revoked_app/core/widgets/app_entity_card.dart';

/// On a phone the one-line header ran out of room: the title ellipsized to a
/// few characters and the tags wrapped over several runs. Below the breakpoint
/// the tags get a line of their own, and the title keeps the first one.
void main() {
  Widget card() => MaterialApp(
    theme: AppTheme.build(Brightness.light),
    home: const Scaffold(
      body: AppEntityCard(
        title: 'A record with a long enough label to crowd the line',
        subtitle: 'billing/stripe-secret',
        subtitleMono: true,
        date: '2026-08-24',
        tags: [
          AppBadge(label: 'Active'),
          AppBadge(label: '3/10'),
          AppBadge(label: 'Password'),
        ],
      ),
    ),
  );

  Future<void> pumpAt(WidgetTester tester, double width) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(card());
  }

  testWidgets('a phone-width card puts the tags under the title', (
    tester,
  ) async {
    await pumpAt(tester, AppSpacing.narrowWidth - 1);

    expect(
      tester.getCenter(find.text('Active')).dy,
      greaterThan(tester.getCenter(find.text('2026-08-24')).dy),
    );
    expect(
      tester.getCenter(find.text('Active')).dx,
      lessThan(tester.getCenter(find.text('2026-08-24')).dx),
    );
  });

  testWidgets('a wide card keeps the whole header on one line', (tester) async {
    await pumpAt(tester, 1200);

    expect(
      tester.getCenter(find.text('Active')).dy,
      tester.getCenter(find.text('2026-08-24')).dy,
    );
  });
}
