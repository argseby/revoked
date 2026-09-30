import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/state/local.dart';
import 'package:revoked_app/core/widgets/app_card.dart';
import 'package:revoked_app/core/widgets/app_divider.dart';

/// A named block of rows — the one shape every list and every detail page is
/// built from:
///
///   Needs attention                                   2
///   ┌──────────────────────────────────────────────────┐
///   │ row                                              │
///   │ row                                              │
///   │ ⌄ 3 more                                         │
///   └──────────────────────────────────────────────────┘
///
/// A long group shows its first [previewCount] rows and a "3 more" row that
/// reveals the rest, so no single group can push the next one off the screen.
/// A [collapsed] group shows only a "Show 8 links" row — for things the
/// reader rarely needs, like revoked links.
class AppListGroup extends StatefulWidget {
  final String title;
  final List<Widget> children;

  /// Shown on the right of the header; defaults to how many rows the group
  /// holds. A detail section passes an action ("Change") instead.
  final Widget? trailing;

  /// Rows shown before the "N more" toggle; 0 shows them all.
  final int previewCount;

  /// Starts folded down to a single "Show N [noun]" row.
  final bool collapsed;

  /// What the rows are, for the folded row: "links", "requests".
  final String noun;

  /// A note under the card — what the rows mean, or what happens next.
  final Widget? footer;

  const AppListGroup({
    super.key,
    required this.title,
    required this.children,
    this.trailing,
    this.previewCount = 0,
    this.collapsed = false,
    this.noun = 'items',
    this.footer,
  });

  @override
  State<AppListGroup> createState() => _AppListGroupState();
}

class _AppListGroupState extends State<AppListGroup> {
  late final Local<bool> _open = Local(!widget.collapsed);
  final Local<bool> _showAll = Local(false);

  @override
  Widget build(BuildContext context) {
    return Observer(builder: (_) => _build(context));
  }

  Widget _build(BuildContext context) {
    final w = widget;
    final total = w.children.length;
    final open = _open.value;
    final showAll = _showAll.value;
    final limited = w.previewCount > 0 && total > w.previewCount;

    final List<Widget> rows;
    if (!open) {
      rows = [
        _ToggleRow(
          icon: AppIcons.chevronRight,
          label: 'Show $total ${w.noun}',
          onTap: () => _open.value = true,
        ),
      ];
    } else if (limited && !showAll) {
      rows = [
        ...w.children.take(w.previewCount),
        _ToggleRow(
          icon: AppIcons.chevronDown,
          label: '${total - w.previewCount} more',
          onTap: () => _showAll.value = true,
        ),
      ];
    } else {
      rows = [
        ...w.children,
        if (limited)
          _ToggleRow(
            icon: AppIcons.chevronUp,
            label: 'Show less',
            onTap: () => _showAll.value = false,
          ),
      ];
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppListHeader(
            title: w.title,
            trailing: w.trailing ?? AppText('$total').small.muted,
          ),
          AppListCard(children: rows),
          if (w.footer != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xxs,
                AppSpacing.sm,
                AppSpacing.xxs,
                0,
              ),
              child: DefaultTextStyle.merge(
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                child: w.footer!,
              ),
            ),
        ],
      ),
    );
  }
}

/// The label above a group of rows, with an optional count or action on the
/// right.
class AppListHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;

  const AppListHeader({super.key, required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xxs,
        0,
        AppSpacing.xxs,
        AppSpacing.xs,
      ),
      child: ConstrainedBox(
        // Room for a small button, so a header with an action lines up with
        // one without.
        constraints: const BoxConstraints(minHeight: 32),
        child: Row(
          children: [
            Expanded(child: AppText(title).small.muted),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

/// Rows in one bordered card, separated by hairlines.
class AppListCard extends StatelessWidget {
  final List<Widget> children;

  const AppListCard({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const AppDivider(),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ToggleRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 32,
              child: Icon(icon, size: 18, color: scheme.onSurfaceVariant),
            ),
            AppSpacing.gapMd,
            Expanded(child: AppText(label).small.muted),
          ],
        ),
      ),
    );
  }
}
