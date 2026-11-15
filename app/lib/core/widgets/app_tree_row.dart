import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_list_row.dart';
import 'package:revoked_app/core/widgets/app_options_sheet.dart';

/// A row in a tree of what belongs to what: an [AppListRow] indented by
/// [depth]. A row with children has [expanded] set. One that opens a page
/// keeps [onTap] and folds through a button of its own; one that only holds
/// children folds when tapped.
class AppTreeRow extends StatelessWidget {
  final int depth;
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? subtitleWidget;
  final Widget? trailing;
  final Widget? audience;
  final Color? accent;
  final bool selected;

  /// Null for a row without children.
  final bool? expanded;
  final VoidCallback? onToggle;

  /// Opens the row's page or selects it.
  final VoidCallback? onTap;

  /// Off for a row that selects in place rather than opening a page.
  final bool showChevron;

  final FutureOr<List<AppSheetAction>> Function()? contextActions;

  const AppTreeRow({
    super.key,
    this.depth = 0,
    required this.icon,
    required this.title,
    this.subtitle,
    this.subtitleWidget,
    this.trailing,
    this.audience,
    this.accent,
    this.selected = false,
    this.expanded,
    this.onToggle,
    this.onTap,
    this.showChevron = true,
    this.contextActions,
  });

  @override
  Widget build(BuildContext context) {
    final open = expanded;
    final chevron = open == true ? AppIcons.chevronDown : AppIcons.chevronRight;
    final fold = open == null
        ? null
        : onTap == null
        ? Icon(
            chevron,
            size: 18,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          )
        : AppButton(
            icon: chevron,
            tooltip: open ? 'Collapse' : 'Expand',
            style: AppButtonStyle.accent,
            size: AppButtonSize.small,
            onTap: onToggle,
          );
    Widget row(Widget? end) => AppListRow(
      icon: icon,
      title: title,
      subtitle: subtitle,
      subtitleWidget: subtitleWidget,
      trailing: end,
      audience: audience,
      accent: accent,
      selected: selected,
      showChevron: showChevron && open == null,
      onTap: onTap ?? onToggle,
      contextActions: contextActions,
    );
    final t = trailing;
    return Padding(
      padding: EdgeInsets.only(left: AppSpacing.xl * depth),
      child: t == null || fold == null
          ? row(t ?? fold)
          // Beside the fold button a badge gives way on a row too narrow
          // for both, as on a small phone with enlarged text.
          : LayoutBuilder(
              builder: (context, box) {
                final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
                if (box.maxWidth / scale < 240) return row(fold);
                return row(
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [t, AppSpacing.gapXs, fold],
                  ),
                );
              },
            ),
    );
  }
}
