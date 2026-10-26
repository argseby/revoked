import 'package:flutter/material.dart';

import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/widgets/app_focus_ring.dart';

/// One compact line in an [AppListGroup]: what the thing is, one sentence on
/// where it stands, and at most one badge.
///
///   [icon]  Title                               [badge]  ›
///           One plain line of status
///
/// Everything else a thing carries — slugs, flags, counts — belongs on its
/// detail page. A row that grows a second badge has started turning back into
/// the card it replaced.
class AppListRow extends StatelessWidget {
  final IconData? icon;

  /// Takes the icon's place — a selection checkbox while picking rows.
  final Widget? leading;

  final String title;

  /// One sentence the reader acts on: "Expires in 2 days", "3 new responses".
  final String? subtitle;

  /// Stands in for [subtitle] when the line is not plain text, such as a
  /// hidden value's redaction bar.
  final Widget? subtitleWidget;

  /// A single badge, typically the status.
  final Widget? trailing;

  /// The row whose page is open beside the list, in a split. Marked by a
  /// tint and an ink bar, and announced as selected.
  final bool selected;

  /// Opens the detail page. A row that opens something shows a chevron.
  final VoidCallback? onTap;

  const AppListRow({
    super.key,
    this.icon,
    this.leading,
    required this.title,
    this.subtitle,
    this.subtitleWidget,
    this.trailing,
    this.selected = false,
    this.onTap,
    this.showChevron = true,
  }) : assert(icon != null || leading != null, 'a row needs an icon');

  /// A row that toggles in place rather than opening a page drops the chevron.
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasSubtitle = subtitle != null && subtitle!.isNotEmpty;

    final row = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            height: 32,
            child:
                leading ??
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: AppRadius.allMd,
                  ),
                  child: Icon(icon, size: 18, color: scheme.onSurfaceVariant),
                ),
          ),
          AppSpacing.gapMd,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                AppText(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                if (subtitleWidget != null)
                  subtitleWidget!
                else if (hasSubtitle)
                  AppText(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ).small.muted,
              ],
            ),
          ),
          if (trailing != null) ...[AppSpacing.gapSm, trailing!],
          if (onTap != null && showChevron) ...[
            AppSpacing.gapXs,
            Icon(
              AppIcons.chevronRight,
              size: 18,
              color: scheme.onSurfaceVariant,
            ),
          ],
        ],
      ),
    );

    final marked = selected
        ? DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.secondaryContainer,
              border: Border(left: BorderSide(color: scheme.primary, width: 3)),
            ),
            child: row,
          )
        : row;
    if (onTap == null) return marked;
    // Square on purpose: the row spans its card, whose rounded clip trims the
    // highlight on the first and last row.
    return Semantics(
      selected: selected,
      child: AppFocusRing(
        borderRadius: BorderRadius.zero,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.zero,
          child: marked,
        ),
      ),
    );
  }
}
