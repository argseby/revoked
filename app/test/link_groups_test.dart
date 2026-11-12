import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:revoked_app/core/models/link.dart';
import 'package:revoked_app/core/theme/app_theme.dart';
import 'package:revoked_app/core/widgets/app_list_group.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_list_row.dart';
import 'package:revoked_app/features/shares/view/link_groups.dart';

/// The Links list leads with what is about to stop working on its own and
/// folds away what already has, so a long list still says what needs doing.
void main() {
  final now = DateTime.utc(2026, 9, 30, 12);

  Link link({
    String status = 'active',
    String? expiresAt,
    int viewCount = 0,
    int maxViews = 0,
  }) => Link(
    id: 'id',
    slug: 'slug',
    label: 'Employer HR',
    sections: const [],
    records: const [],
    user: 'u',
    workspace: 'w',
    status: status,
    expiresAt: expiresAt,
    viewCount: viewCount,
    maxViews: maxViews,
  );

  group('linkGroup', () {
    test('sorts by status', () {
      expect(linkGroup(link(), now), LinkGroup.active);
      expect(linkGroup(link(status: 'paused'), now), LinkGroup.paused);
      expect(linkGroup(link(status: 'revoked'), now), LinkGroup.closed);
      expect(linkGroup(link(status: 'expired'), now), LinkGroup.closed);
    });

    test('a live link about to run out needs attention', () {
      final soon = link(expiresAt: '2026-10-02T12:00:00Z');
      expect(linkGroup(soon, now), LinkGroup.attention);
      expect(linkAttention(soon, now)!.reason, 'Expires in 2 days');
    });

    test('a paused link is never flagged, however close its date', () {
      final paused = link(status: 'paused', expiresAt: '2026-09-30T13:00:00Z');
      expect(linkAttention(paused, now), isNull);
    });
  });

  group('linkAttention', () {
    test('counts hours on the last day', () {
      final a = linkAttention(link(expiresAt: '2026-09-30T17:30:00Z'), now);
      expect(a!.reason, 'Expires in 5 hours');
      expect(a.short, 'Soon');
    });

    test('a date already past says so', () {
      final a = linkAttention(link(expiresAt: '2026-09-29T12:00:00Z'), now);
      expect(a!.reason, 'Past its expiry date');
    });

    test('a far-off date is fine', () {
      expect(
        linkAttention(link(expiresAt: '2026-12-01T00:00:00Z'), now),
        isNull,
      );
    });

    test('flags the last fifth of the views', () {
      expect(linkAttention(link(viewCount: 7, maxViews: 10), now), isNull);
      final a = linkAttention(link(viewCount: 8, maxViews: 10), now);
      expect(a!.reason, '8 of 10 views used');
      expect(a.short, '8/10');
    });

    test('flags the very last view even under a small cap', () {
      expect(linkAttention(link(viewCount: 1, maxViews: 3), now), isNull);
      expect(linkAttention(link(viewCount: 2, maxViews: 3), now), isNotNull);
      expect(
        linkAttention(link(viewCount: 3, maxViews: 3), now)!.reason,
        'All 3 views used',
      );
    });

    test('unlimited views are never flagged', () {
      expect(linkAttention(link(viewCount: 500), now), isNull);
    });
  });

  group('AppListGroup', () {
    Widget host(Widget child) => MaterialApp(
      theme: AppTheme.build(Brightness.light),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

    List<Widget> rows(int n) => [
      for (var i = 0; i < n; i++) AppListRow(icon: Icons.link, title: 'Row $i'),
    ];

    for (final width in [320.0, 1200.0]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('count stays beside its title at $width and $scale text', (
          tester,
        ) async {
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(
            host(
              MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: AppListGroup(title: 'Contacts', children: rows(3)),
              ),
            ),
          );
          final title = tester.getRect(find.text('Contacts'));
          final count = tester.getRect(find.text('3'));
          expect(count.left - title.right, 8);
          expect(count.center.dy, closeTo(title.center.dy, 1));
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets(
      'explicit count stays beside the title while action stays right',
      (tester) async {
        await tester.pumpWidget(
          host(
            AppListGroup(
              title: 'Saved',
              count: 37,
              trailing: AppButton(label: 'Change', onTap: () {}),
              children: rows(2),
            ),
          ),
        );
        final title = tester.getRect(find.text('Saved'));
        final count = tester.getRect(find.text('37'));
        final action = tester.getRect(find.byType(AppButton));
        expect(count.left - title.right, 8);
        expect(
          action.right,
          tester.view.physicalSize.width / tester.view.devicePixelRatio,
        );
        expect(count.right, lessThan(action.left));
        expect(find.text('2'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('a hidden header count stays hidden', (tester) async {
      await tester.pumpWidget(
        host(
          AppListGroup(
            title: 'Details',
            trailing: const SizedBox.shrink(),
            children: rows(2),
          ),
        ),
      );
      expect(find.text('2'), findsNothing);
    });

    testWidgets('badges can wrap without separating title and count', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        host(
          const AppListHeader(
            title: 'Contacts',
            count: 12,
            badge: Text('Shared with the workspace'),
          ),
        ),
      );
      expect(
        tester.getRect(find.text('12')).left -
            tester.getRect(find.text('Contacts')).right,
        8,
      );
      expect(
        tester.getRect(find.text('Shared with the workspace')).top,
        greaterThan(tester.getRect(find.text('Contacts')).bottom),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows a preview and reveals the rest', (tester) async {
      await tester.pumpWidget(
        host(AppListGroup(title: 'Active', previewCount: 2, children: rows(5))),
      );
      expect(find.text('Row 1'), findsOneWidget);
      expect(find.text('Row 2'), findsNothing);

      await tester.tap(find.text('3 more'));
      await tester.pump();
      expect(find.text('Row 4'), findsOneWidget);
      expect(find.text('Show less'), findsOneWidget);
    });

    testWidgets('a collapsed group shows only its count', (tester) async {
      await tester.pumpWidget(
        host(
          AppListGroup(
            title: 'Revoked or expired',
            collapsed: true,
            noun: 'links',
            children: rows(8),
          ),
        ),
      );
      expect(find.text('Row 0'), findsNothing);

      await tester.tap(find.text('Show 8 links'));
      await tester.pump();
      expect(find.text('Row 7'), findsOneWidget);
      await tester.tap(find.text('Hide 8 links'));
      await tester.pump();
      expect(find.text('Row 0'), findsNothing);
      expect(find.text('Show 8 links'), findsOneWidget);
      await tester.tap(find.text('Show 8 links'));
      await tester.pump();
      expect(find.text('Row 7'), findsOneWidget);
    });

    testWidgets('a collapsed group of one says it in the singular', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          AppListGroup(
            title: 'Closed',
            collapsed: true,
            noun: 'links',
            children: rows(1),
          ),
        ),
      );
      expect(find.text('Show 1 link'), findsOneWidget);
    });
  });
}
