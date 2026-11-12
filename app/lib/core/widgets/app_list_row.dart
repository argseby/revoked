import 'dart:async';
import 'package:flutter/material.dart';

import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/widgets/app_focus_ring.dart';
import 'package:revoked_app/core/widgets/app_context_menu.dart';
import 'package:revoked_app/core/widgets/app_options_sheet.dart';
import 'package:revoked_app/core/widgets/audience_tag.dart';

/// One compact line in an [AppListGroup]: what the thing is, one sentence on
/// where it stands, who sees it, and at most one badge.
///
///   [icon]  Title                      [audience]  [badge]  ›
///           One plain line of status
///
/// Everything else a thing carries — slugs, flags, counts — belongs on its
/// detail page. A row that grows a second badge has started turning back into
/// the card it replaced. The audience is not one: who sees an item is the
/// one fact every list in a workspace answers, in the same place.
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

  /// Who sees the item, an `AudienceTag`, just before [trailing].
  final Widget? audience;

  /// Tints the icon for a row that needs a look, a link about to expire or
  /// a request with unread answers, so it is found from the left edge too
  /// and not only by its badge.
  final Color? accent;

  /// The row whose page is open beside the list, in a split. Marked by a
  /// tint and an ink bar, and announced as selected.
  final bool selected;

  /// Opens the detail page. A row that opens something shows a chevron.
  final VoidCallback? onTap;

  /// Built at invocation so permissions and item state are current.
  final FutureOr<List<AppSheetAction>> Function()? contextActions;

  const AppListRow({
    super.key,
    this.icon,
    this.leading,
    required this.title,
    this.subtitle,
    this.subtitleWidget,
    this.trailing,
    this.audience,
    this.accent,
    this.selected = false,
    this.onTap,
    this.contextActions,
    this.showChevron = true,
  }) : assert(icon != null || leading != null, 'a row needs an icon');

  /// A row that toggles in place rather than opening a page drops the chevron.
  final bool showChevron;

  /// Below this the row shows the audience as its icon only.
  static const double _fullAudienceWidth = 480;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasSubtitle = subtitle != null && subtitle!.isNotEmpty;

    final padded = Padding(
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
                    color:
                        accent?.withValues(alpha: 0.12) ??
                        scheme.surfaceContainerHighest,
                    borderRadius: AppRadius.allMd,
                  ),
                  child: Icon(
                    icon,
                    size: 18,
                    color: accent ?? scheme.onSurfaceVariant,
                  ),
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
          if (audience != null) ...[
            AppSpacing.gapSm,
            // Room for two group names; the tag says the rest in its tooltip.
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 180),
              child: audience!,
            ),
          ],
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

    // A list beside an open page is narrow on a wide window; there the
    // audience gives its words up to the title, as on a phone.
    final row = audience == null
        ? padded
        : LayoutBuilder(
            builder: (context, box) => AudienceCompact(
              compact: box.maxWidth < _fullAudienceWidth,
              child: padded,
            ),
          );

    final marked = selected
        ? Ink(
            decoration: BoxDecoration(
              color: scheme.secondaryContainer,
              border: Border(left: BorderSide(color: scheme.primary, width: 3)),
            ),
            child: row,
          )
        : row;
    // Rectangular row feedback fills the list; an enclosing card clips
    // its outer corners. The same shape applies when rows sit on the page.
    final surface = Material(
      color: Colors.transparent,
      borderRadius: AppRadius.row,
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? marked
          : InkWell(onTap: onTap, borderRadius: AppRadius.row, child: marked),
    );
    final content = onTap == null
        ? surface
        : Semantics(
            selected: selected,
            child: AppFocusRing(borderRadius: AppRadius.row, child: surface),
          );
    final actions = contextActions;
    return actions == null
        ? content
        : AppContextMenu(title: title, actions: actions, child: content);
  }
}
