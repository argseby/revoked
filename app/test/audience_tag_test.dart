import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:revoked_app/core/models/group.dart';
import 'package:revoked_app/core/models/invite.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/theme/app_theme.dart';
import 'package:revoked_app/core/widgets/app_filter_menu.dart';
import 'package:revoked_app/core/widgets/app_list_row.dart';
import 'package:revoked_app/core/widgets/audience_tag.dart';

/// Who sees an item is said on its row in every list, in the same place,
/// and the lists filter by it. In a workspace of one there is nobody else to
/// see anything, so neither the tag nor the filter shows.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Stores.init();
  });

  WorkspaceMemberDetail member(String id) => WorkspaceMemberDetail(
    id: 'm$id',
    userId: id,
    email: '$id@example.com',
    role: 'member',
    permissions: const [],
  );

  void workspaceOf(int members) => Stores.invites.members
    ..clear()
    ..addAll([for (var i = 0; i < members; i++) member('u$i')]);

  setUp(() {
    workspaceOf(3);
    Stores.settings.groups
      ..clear()
      ..addAll([
        const WorkspaceGroup(
          id: 'hr',
          key: 'hr',
          name: 'HR',
          members: [(id: 'u0', email: ''), (id: 'u1', email: '')],
        ),
        const WorkspaceGroup(
          id: 'svc',
          key: 'svc',
          name: 'Service',
          members: [(id: 'u1', email: ''), (id: 'u2', email: '')],
        ),
      ]);
  });

  group('Audience', () {
    test('groups without a group read as private', () {
      expect(const Audience('groups').effectiveKind, 'private');
      expect(const Audience('groups').filterIds, {'private'});
      expect(const Audience('nonsense').isPrivate, isTrue);
    });

    test('filter ids name the kind or each group', () {
      expect(const Audience('workspace').filterIds, {'workspace'});
      expect(const Audience('groups', ['hr', 'svc']).filterIds, {
        'group:hr',
        'group:svc',
      });
    });

    test('a record reaches its own audience and its sections\' together', () {
      expect(Audience.combined([Audience.private]).effectiveKind, 'private');
      expect(
        Audience.combined([
          Audience.private,
          const Audience('groups', ['hr']),
          const Audience('groups', ['svc', 'hr']),
        ]).filterIds,
        {'group:hr', 'group:svc'},
      );
      expect(
        Audience.combined([
          const Audience('groups', ['hr']),
          const Audience('workspace'),
        ]).effectiveKind,
        'workspace',
      );
    });

    test('an item matches when any of its audiences is ticked', () {
      const record = Audience.private;
      const section = Audience('groups', ['hr']);
      expect(audienceMatches(const {}, [record]), isTrue);
      expect(audienceMatches(const {'group:hr'}, [record]), isFalse);
      expect(audienceMatches(const {'group:hr'}, [record, section]), isTrue);
      expect(audienceMatches(const {'workspace'}, [record, section]), isFalse);
    });
  });

  group('audienceFilterSection', () {
    test('counts each item once per audience it reaches', () {
      final section = audienceFilterSection(
        items: [
          [Audience.private],
          [const Audience('workspace')],
          [
            const Audience('groups', ['hr', 'svc']),
          ],
          [
            Audience.private,
            const Audience('groups', ['hr']),
          ],
        ],
        selected: const {},
        onToggle: (_, _) {},
      )!;
      expect(section.title, 'Visible to');
      final counts = {for (final i in section.items) i.label: i.count};
      expect(counts, {'Private': 2, 'Workspace': 1, 'HR': 2, 'Service': 1});
    });

    test('is left out in a workspace of one with only private items', () {
      workspaceOf(1);
      AppChecklistSection? section(List<Audience> items) =>
          audienceFilterSection(
            items: [
              for (final a in items) [a],
            ],
            selected: const {},
            onToggle: (_, _) {},
          );
      expect(section([Audience.private]), isNull);
      expect(section([const Audience('workspace')]), isNotNull);
    });
  });

  group('AudienceTag', () {
    Future<void> pumpRow(
      WidgetTester tester,
      Audience audience, {
      double width = 900,
    }) async {
      tester.view.physicalSize = Size(width, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(Brightness.light),
          home: Scaffold(
            body: AppListRow(
              icon: Icons.link,
              title: 'Insurance proof',
              audience: AudienceTag(audience),
              onTap: () {},
            ),
          ),
        ),
      );
    }

    testWidgets('names private, workspace and groups on the row', (
      tester,
    ) async {
      await pumpRow(tester, Audience.private);
      expect(find.text('Private'), findsOneWidget);
      expect(
        find.byTooltip('Private · visible to the owner only'),
        findsOneWidget,
      );

      await pumpRow(tester, const Audience('workspace'));
      expect(find.text('Workspace'), findsOneWidget);
      expect(
        find.byTooltip('Visible to the workspace · 3 people'),
        findsOneWidget,
      );

      await pumpRow(tester, const Audience('groups', ['hr', 'svc']));
      expect(find.text('HR'), findsOneWidget);
      expect(find.text('Service'), findsOneWidget);
      expect(
        find.byTooltip('Visible to HR and Service · 3 people'),
        findsOneWidget,
      );
    });

    testWidgets('more than two groups end in a count', (tester) async {
      Stores.settings.groups.add(
        const WorkspaceGroup(id: 'tech', key: 'tech', name: 'Techs'),
      );
      await pumpRow(tester, const Audience('groups', ['hr', 'svc', 'tech']));
      expect(find.text('+1'), findsOneWidget);
      expect(find.text('Techs'), findsNothing);
    });

    testWidgets('a phone shows only the icon, still announced in full', (
      tester,
    ) async {
      await pumpRow(tester, const Audience('workspace'), width: 390);
      expect(find.text('Workspace'), findsNothing);
      expect(
        find.byTooltip('Visible to the workspace · 3 people'),
        findsOneWidget,
      );
    });

    testWidgets('a narrow list on a wide window shows only the icon', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(Brightness.light),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 328,
                child: AppListRow(
                  icon: Icons.link,
                  title: 'A rather long link label for a narrow pane',
                  audience: const AudienceTag(
                    Audience('groups', ['hr', 'svc']),
                  ),
                  trailing: const Text('Active'),
                  onTap: () {},
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('HR'), findsNothing);
      expect(
        find.byTooltip('Visible to HR and Service · 3 people'),
        findsOneWidget,
      );
    });

    testWidgets('a workspace of one shows no Private tag', (tester) async {
      workspaceOf(1);
      await pumpRow(tester, Audience.private);
      expect(find.text('Private'), findsNothing);
      expect(find.text('Insurance proof'), findsOneWidget);
    });

    testWidgets('an item open to others says so even before members load', (
      tester,
    ) async {
      workspaceOf(0);
      await pumpRow(tester, const Audience('workspace'));
      expect(find.text('Workspace'), findsOneWidget);
    });
  });
}
