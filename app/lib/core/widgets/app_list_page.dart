import 'package:flutter/material.dart';

import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';

/// The body of every list tab — Vault, Links, Requests — laid out the same:
///
///   (All 14) (Active 6) (Closed 8)
///   [banner]                      a mode the screen is held in, if any
///   Group ─────────────────────
///   Group ─────────────────────
///
/// The search lives in the top bar (an `AppSearchField` in the title slot),
/// so the chips are the first thing on the page. They scroll away with the
/// list, so a phone spends its height on rows.
class AppListPage extends StatelessWidget {
  /// The filter chips, first on the page.
  final Widget? filters;

  /// Banners under the chips — "Editing section: Personal".
  final List<Widget> banners;

  /// The `AppListGroup`s, in order.
  final List<Widget> groups;

  /// Shown instead of the groups when the search and filters leave nothing.
  final String? emptyMessage;

  const AppListPage({
    super.key,
    this.filters,
    this.banners = const [],
    required this.groups,
    this.emptyMessage,
  });

  @override
  Widget build(BuildContext context) {
    return AppPageBody(
      children: [
        if (filters != null) ...[filters!, AppSpacing.gapLg],
        for (final b in banners) ...[b, AppSpacing.gapLg],
        if (emptyMessage != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xxl),
            child: Center(child: AppText(emptyMessage!).muted),
          )
        else
          ...groups,
      ],
    );
  }
}

/// The scrolling column every page sits in: the same side inset and the full
/// width of the window, so moving from a list into a detail page keeps the
/// edges still.
class AppPageBody extends StatelessWidget {
  final List<Widget> children;

  /// Room below the last child. The default clears the shell's stacked
  /// floating buttons; a page with its own bottom bar needs less.
  final double bottomPadding;

  const AppPageBody({
    super.key,
    required this.children,
    this.bottomPadding = AppSpacing.gigantic * 3,
  });

  @override
  Widget build(BuildContext context) {
    final scrollbar = AppSpacing.scrollbarMargin(context);
    final inner = AppSpacing.screenH(context) - scrollbar;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: scrollbar),
      // Built in full rather than lazily: a page is a handful of groups, and
      // everything on it can be found without scrolling it into view first.
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          inner,
          AppSpacing.md,
          inner,
          bottomPadding,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}

/// A mode the list is held in, with its way out — "Editing section: Personal.
/// Tick the records it holds."
class AppListBanner extends StatelessWidget {
  final IconData icon;
  final String message;
  final Widget? action;

  const AppListBanner({
    super.key,
    required this.icon,
    required this.message,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.1),
        borderRadius: AppRadius.allMd,
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Icon(icon, size: 16, color: scheme.primary),
            AppSpacing.gapSm,
            Expanded(child: AppText(message).small),
            if (action != null) ...[AppSpacing.gapSm, action!],
          ],
        ),
      ),
    );
  }
}
