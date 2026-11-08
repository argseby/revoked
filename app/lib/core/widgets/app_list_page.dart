import 'package:flutter/material.dart';

import 'package:revoked_app/core/state/shell_slots.dart';
import 'package:revoked_app/core/widgets/app_filter_menu.dart';

import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';

/// The body of every list tab — Vault, Links, Requests — laid out the same:
///
///   top bar:  Shares     [🔍 Search links …… ⚟ Filter and sort] [+ New]
///   [header]                       a pane's name, if any
///   (Active ×) (Oldest first ×)    what narrows the list, if anything
///   (All 14) (Active 6) (Closed 8)
///   [banner]                       a mode the screen is held in, if any
///   Group ─────────────────────
///   Group ─────────────────────
///
/// The [toolbar]'s search pill goes up into the shell's top bar, beside New,
/// on every screen and width; on a phone behind a search icon there. It is
/// handed up only while this list is the one in view — not from a tab that
/// is not selected. Outside the shell (a sheet, a test) the pill stays above
/// the list. The [header] and the chips of what is active stay pinned above
/// the list; the [filters] scroll away with it, so a phone spends its height
/// on rows.
class AppListPage extends StatelessWidget {
  /// The list's search, Filter and sort.
  final AppListToolbar? toolbar;

  /// Pinned above the list, over the chips — a pane's name.
  final Widget? header;

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
    this.toolbar,
    this.header,
    this.filters,
    this.banners = const [],
    required this.groups,
    this.emptyMessage,
  });

  @override
  Widget build(BuildContext context) {
    final body = AppPageBody(
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
    final toolbar = this.toolbar;
    final inShell = toolbar != null && ShellSearchHost.contains(context);
    final pinned = <Widget>[
      ?header,
      if (toolbar != null && !inShell) toolbar.pill(),
      ?toolbar?.chips(context),
    ];
    Widget page = pinned.isEmpty
        ? body
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppPageInset(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (i, w) in pinned.indexed) ...[
                      if (i > 0) AppSpacing.gapSm,
                      w,
                    ],
                  ],
                ),
              ),
              Expanded(child: body),
            ],
          );
    if (inShell) page = _SearchClaim(toolbar: toolbar, child: page);
    return page;
  }
}

/// Keeps [toolbar] in [ShellSlots.search] while its list is the one in view,
/// and takes it out when the list goes or its tab is switched away. Claims
/// land after the frame: the shell rebuilds from them, and changing what it
/// observes in the middle of a build is not allowed.
class _SearchClaim extends StatefulWidget {
  final AppListToolbar toolbar;
  final Widget child;

  const _SearchClaim({required this.toolbar, required this.child});

  @override
  State<_SearchClaim> createState() => _SearchClaimState();
}

class _SearchClaimState extends State<_SearchClaim> {
  /// The screen this list belongs to, taken when it first appears and kept:
  /// a claim names it, so the bar never shows one screen's search on
  /// another.
  late final String _root = ShellSearchHost.maybeOf(context)?.root ?? '';

  @override
  Widget build(BuildContext context) {
    // A tab that is not selected is still built; it must not claim. Nor may
    // a page on its way out: switching screens keeps the old page mounted
    // for a moment, and a rebuild there would take the bar back from the
    // new screen, then empty it when the old page goes.
    final visible =
        Visibility.of(context) && (ModalRoute.of(context)?.isCurrent ?? true);
    final root = _root;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (visible) {
        ShellSlots.search.claim(this, root, widget.toolbar);
      } else {
        ShellSlots.search.release(this);
      }
    });
    return widget.child;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => ShellSlots.search.release(this),
    );
    super.dispose();
  }
}

/// A row outside the scrolling body that lines up with it: the same side
/// inset and the same maximum width as [AppPageBody]'s column.
class AppPageInset extends StatelessWidget {
  final Widget child;

  const AppPageInset({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.screenH(context),
        AppSpacing.sm,
        AppSpacing.screenH(context),
        0,
      ),
      child: Align(
        alignment: AlignmentDirectional.topStart,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AppSpacing.contentMaxWidth,
          ),
          child: child,
        ),
      ),
    );
  }
}

/// The scrolling column every page sits in: the same side inset and the same
/// width — the window's, up to [AppSpacing.contentMaxWidth] — so moving from
/// a list into a detail page keeps the edges still.
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
        child: Align(
          alignment: AlignmentDirectional.topStart,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppSpacing.contentMaxWidth,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
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
