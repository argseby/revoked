import 'package:flutter/material.dart';

import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';

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

  /// A single badge, typically the status.
  final Widget? trailing;

  /// Opens the detail page. A row that opens something shows a chevron.
  final VoidCallback? onTap;

  const AppListRow({
    super.key,
    this.icon,
    this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
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
                if (hasSubtitle)
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

    if (onTap == null) return row;
    // Square on purpose: the row spans its card, whose rounded clip trims the
    // highlight on the first and last row.
    return InkWell(onTap: onTap, borderRadius: BorderRadius.zero, child: row);
  }
}
