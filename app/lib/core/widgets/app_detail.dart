import 'package:flutter/material.dart';

import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/widgets/app_list_group.dart';
import 'package:revoked_app/core/widgets/app_list_page.dart';

/// The top of every detail page: where it stands, what it is called, and the
/// one thing you most likely came to do.
///
///   [Active]
///   Employer HR
///   k7m2p9xq
///   ( Share link                    ) [✎] [⧉]
///
/// The page below it is built from `AppListGroup`s — what it contains, who
/// can reach it, its history — and ends with the actions that are hard to
/// undo, so every entity's page reads the same.
class AppDetailHeader extends StatelessWidget {
  /// Status badges, above the title.
  final List<Widget> badges;
  final String title;
  final String? subtitle;

  /// [subtitle] is a slug or key and reads as one.
  final bool subtitleMono;

  /// The page's main action, stretched to fill the row.
  final Widget? primaryAction;

  /// Icon buttons after the main action.
  final List<Widget> secondaryActions;

  const AppDetailHeader({
    super.key,
    required this.title,
    this.badges = const [],
    this.subtitle,
    this.subtitleMono = false,
    this.primaryAction,
    this.secondaryActions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final hasSubtitle = subtitle != null && subtitle!.isNotEmpty;
    final hasActions = primaryAction != null || secondaryActions.isNotEmpty;

    var sub = AppText(subtitle ?? '').small.muted.selectable;
    if (subtitleMono) sub = sub.mono;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xxs,
        0,
        AppSpacing.xxs,
        AppSpacing.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (badges.isNotEmpty) ...[
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: badges,
            ),
            AppSpacing.gapSm,
          ],
          AppText(title).header,
          if (hasSubtitle) ...[const SizedBox(height: AppSpacing.xxs), sub],
          if (hasActions) ...[
            AppSpacing.gapLg,
            Row(
              children: [
                if (primaryAction != null) Expanded(child: primaryAction!),
                for (final a in secondaryActions) ...[AppSpacing.gapSm, a],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// One fact on a detail page: an icon, what it is, and its value.
///
///   [🔒] Password                                        On
class AppDetailRow extends StatelessWidget {
  final IconData? icon;
  final String label;
  final String value;

  /// [value] is a slug or key and reads as one.
  final bool valueMono;

  final VoidCallback? onTap;

  const AppDetailRow({
    super.key,
    this.icon,
    required this.label,
    this.value = '',
    this.valueMono = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // The value gets the larger share and wraps, so an address or a stamp
    // is read in full rather than cut off; the label keeps to its words.
    var valueText = AppText(
      value,
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.end,
    ).muted;
    if (valueMono) valueText = valueText.mono;

    final labelText = AppText(
      label,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );

    final row = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: scheme.onSurfaceVariant),
            AppSpacing.gapMd,
          ],
          if (value.isEmpty)
            Expanded(child: labelText)
          else
            // The label keeps to its words within two fifths; whatever it
            // leaves unused goes between it and the value, so the value always
            // ends flush with the row's right edge.
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(flex: 2, child: labelText),
                  AppSpacing.gapLg,
                  Expanded(
                    flex: 3,
                    child: Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: valueText,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );

    if (onTap == null) return row;
    // Square like every row in a card; the card's clip rounds the ends.
    return InkWell(onTap: onTap, borderRadius: BorderRadius.zero, child: row);
  }
}

/// The whole of a detail page: its header, its `AppListGroup`s, and the
/// [AppDetailManage] block last — in the same column as the list it was opened
/// from, so the edges do not jump.
class AppDetailPage extends StatelessWidget {
  final AppDetailHeader header;
  final List<Widget> sections;

  const AppDetailPage({
    super.key,
    required this.header,
    required this.sections,
  });

  @override
  Widget build(BuildContext context) {
    return AppPageBody(children: [header, ...sections]);
  }
}

/// The actions that end or remove the thing, at the foot of its detail page
/// and apart from the everyday ones in the header.
class AppDetailManage extends StatelessWidget {
  final List<Widget> actions;

  const AppDetailManage({super.key, required this.actions});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AppListHeader(title: 'Manage'),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: actions,
        ),
      ],
    );
  }
}
