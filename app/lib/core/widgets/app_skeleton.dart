import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:skeletonizer/skeletonizer.dart';

import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/motion.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/widgets/app_badge.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_detail.dart';
import 'package:revoked_app/core/widgets/app_filter_chips.dart';
import 'package:revoked_app/core/widgets/app_list_group.dart';
import 'package:revoked_app/core/widgets/app_list_page.dart';
import 'package:revoked_app/core/widgets/app_list_row.dart';

/// A page whose content is on its way: inert, and announced as loading. What
/// isn't known yet goes in an [AppBones]; the rest, such as a group's heading and
/// card, draws as itself.
class AppSkeleton extends StatelessWidget {
  final Widget child;

  const AppSkeleton({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading',
      container: true,
      child: ExcludeSemantics(child: IgnorePointer(child: child)),
    );
  }
}

/// Draws [child] as grey blocks. Built from the real widgets, so nothing jumps
/// when the content arrives. Still, not shimmering: [AppMotion] is the app's only
/// animation.
class AppBones extends StatelessWidget {
  final Widget child;

  const AppBones({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Skeletonizer(
      ignoreContainers: true,
      effect: SolidColorEffect(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: child,
    );
  }
}

/// One row of a skeleton. The words only give the blocks their widths.
class AppSkeletonRow {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? badge;

  const AppSkeletonRow(
    this.title,
    this.subtitle, {
    this.icon = AppIcons.fileText,
    this.badge,
  });
}

/// A list on its way, in the shape of the screen it stands in for: its filter
/// chips or its intro, its group heading, and rows like its own. Each screen
/// describes its own, so nothing moves when the real list replaces it.
class AppListSkeleton extends StatelessWidget {
  final List<String> filters;
  final String? intro;
  final String? group;
  final List<AppSkeletonRow> rows;

  /// Part of a page that scrolls and sets its own edges, like a settings
  /// section, rather than the whole of one.
  final bool embedded;

  const AppListSkeleton({
    super.key,
    this.filters = const [],
    this.intro,
    this.group,
    this.rows = _defaultRows,
    this.embedded = false,
  });

  static const _defaultRows = [
    AppSkeletonRow('Home address', 'A street and a town'),
    AppSkeletonRow('Bank details', 'An account in full'),
    AppSkeletonRow('Tax number', 'Eleven digits'),
    AppSkeletonRow('Passport', 'A document and its date'),
    AppSkeletonRow('Phone number', 'With the country code'),
  ];

  @override
  Widget build(BuildContext context) {
    final items = [
      for (final row in embedded ? rows.take(2) : rows)
        AppBones(
          child: AppListRow(
            icon: row.icon,
            title: row.title,
            subtitle: row.subtitle,
            trailing: row.badge == null ? null : AppBadge(label: row.badge!),
            onTap: () {},
          ),
        ),
    ];
    if (embedded) return AppSkeleton(child: AppListCard(children: items));
    return AppSkeleton(
      child: AppListPage(
        filters: filters.isEmpty
            ? null
            : AppBones(
                child: AppFilterChips<String>(
                  selected: filters.first,
                  onSelected: (_) {},
                  options: [
                    for (final label in filters)
                      AppFilterOption(value: label, label: label, count: 0),
                  ],
                ),
              ),
        groups: [
          if (intro != null) ...[
            AppBones(child: Text(intro!).muted.small),
            AppSpacing.gapMd,
          ],
          if (group != null)
            AppListGroup(
              title: group!,
              // Its count isn't known yet.
              trailing: const SizedBox.shrink(),
              children: items,
            )
          else
            AppListCard(children: items),
        ],
      ),
    );
  }
}

/// A group of facts on a detail page's skeleton.
class AppSkeletonGroup {
  final String title;
  final int rows;

  const AppSkeletonGroup(this.title, {this.rows = 1});
}

/// A detail page on its way, in the shape of the page it stands in for: built
/// on the real [AppDetailPage], so it splits into the same columns on a wide
/// window and stacks its buttons the same way on a phone.
class AppDetailSkeleton extends StatelessWidget {
  final List<String> badges;
  final String primary;
  final int icons;
  final List<AppSkeletonGroup> sections;
  final List<AppSkeletonGroup> aside;

  const AppDetailSkeleton({
    super.key,
    this.badges = const ['status'],
    this.primary = 'Open it',
    this.icons = 2,
    this.sections = const [AppSkeletonGroup('Contents', rows: 2)],
    this.aside = const [AppSkeletonGroup('Details', rows: 3)],
  });

  Widget _group(AppSkeletonGroup group) => AppListGroup(
    title: group.title,
    trailing: const SizedBox.shrink(),
    children: [
      for (var i = 0; i < group.rows; i++)
        const AppBones(
          child: AppDetailRow(
            icon: AppIcons.fileText,
            label: 'A fact',
            value: 'How it stands',
          ),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return AppSkeleton(
      child: AppDetailPage(
        header: AppBones(
          child: AppDetailHeader(
            badges: [for (final badge in badges) AppBadge(label: badge)],
            title: 'A name for this',
            subtitle: 'k7m2p9xq',
            primaryAction: AppButton(
              icon: AppIcons.fileText,
              label: primary,
              onTap: () {},
            ),
            secondaryActions: [
              for (var i = 0; i < icons; i++)
                AppButton(
                  icon: AppIcons.fileText,
                  tooltip: 'Action',
                  style: AppButtonStyle.accent,
                  onTap: () {},
                ),
            ],
          ),
        ),
        sections: [for (final group in sections) _group(group)],
        aside: [for (final group in aside) _group(group)],
      ),
    );
  }
}

/// A page that shows [skeleton] until its content has arrived, then fades over
/// to it. Rebuilds like an `Observer`, because both closures read stores.
class AppLoadFade extends StatelessWidget {
  final bool Function() loading;
  final Widget skeleton;
  final WidgetBuilder builder;

  const AppLoadFade({
    super.key,
    required this.loading,
    this.skeleton = const AppListSkeleton(),
    required this.builder,
  });

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (context) {
        final waiting = loading();
        return AnimatedSwitcher(
          duration: AppMotion.of(context),
          switchInCurve: AppMotion.curve,
          switchOutCurve: AppMotion.curve,
          layoutBuilder: (current, previous) =>
              Stack(fit: StackFit.expand, children: [...previous, ?current]),
          child: KeyedSubtree(
            key: ValueKey(waiting),
            child: waiting ? skeleton : builder(context),
          ),
        );
      },
    );
  }
}
