import 'package:flutter/material.dart';

import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/widgets/app_sheet.dart';

/// One action in an [showAppOptionsSheet] options drawer.
class AppSheetAction {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;
  final bool enabled;

  /// Marks the most important action so surfaces that render these as buttons
  /// (e.g. the expandable entity card) can give it a highlighted treatment.
  final bool primary;

  const AppSheetAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
    this.enabled = true,
    this.primary = false,
  });
}

/// The single per-item options drawer used by My Data, Share and Request.
/// Replaces the assorted popup menus / dialogs so every "⋮" opens the same
/// bottom sheet: a title + key, then a stack of icon-and-label actions.
///
/// Each action closes the sheet before running, so callers don't have to pop.
Future<void> showAppOptionsSheet({
  required BuildContext context,
  required String title,
  String? subtitle,
  required List<AppSheetAction> actions,
}) {
  return showAppSheet(
    context: context,
    builder: (sheetCtx) {
      final scheme = Theme.of(sheetCtx).colorScheme;
      return Container(
        constraints: const BoxConstraints(maxWidth: 460),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.xxs,
          AppSpacing.xl,
          AppSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis).header,
            if (subtitle != null && subtitle.isNotEmpty) ...[
              AppSpacing.gapXxs,
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ).mono.muted.small,
            ],
            AppSpacing.gapLg,
            for (final a in actions)
              _OptionRow(
                action: a,
                color: a.destructive ? scheme.error : scheme.onSurface,
                onSelected: () {
                  Navigator.of(sheetCtx).pop();
                  a.onTap();
                },
              ),
          ],
        ),
      );
    },
  );
}

class _OptionRow extends StatelessWidget {
  final AppSheetAction action;
  final Color color;
  final VoidCallback onSelected;

  const _OptionRow({
    required this.action,
    required this.color,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final fg = action.enabled
        ? color
        : Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5);
    return InkWell(
      borderRadius: AppRadius.allMd,
      onTap: action.enabled ? onSelected : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            Icon(action.icon, size: 20, color: fg),
            AppSpacing.gapLg,
            Expanded(
              child: DefaultTextStyle.merge(
                style: TextStyle(color: fg),
                child: Text(action.label),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
