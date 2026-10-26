import 'package:flutter/material.dart';

import 'package:revoked_app/core/design/status_colors.dart';
import 'package:revoked_app/core/widgets/app_badge.dart';
import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';

/// A link's or request's status as a badge — "Active" green, "Paused" amber,
/// "Revoked" red — the same everywhere a status is shown.
class AppStatusBadge extends StatelessWidget {
  final String status;

  const AppStatusBadge(this.status, {super.key});

  @override
  Widget build(BuildContext context) {
    return AppBadge(
      label: StatusColors.displayLabel(status),
      accent: StatusColors.foreground(Theme.of(context), status),
    );
  }
}

/// A status said three ways at once: icon, word and colour on its own tint.
/// Never colour alone, so it reads the same to someone who cannot tell green
/// from red, and to a screen reader ("Status: Paused").
class StatusLabel extends StatelessWidget {
  final String status;

  const StatusLabel(this.status, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = StatusColors.foreground(theme, status);
    final label = StatusColors.displayLabel(status);
    return Semantics(
      label: 'Status: $label',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xxs,
        ),
        decoration: BoxDecoration(
          color: StatusColors.background(theme, status),
          borderRadius: AppRadius.allMd,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(StatusColors.icon(status), size: 16, color: fg),
            AppSpacing.gapXs,
            DefaultTextStyle.merge(
              style: TextStyle(color: fg),
              child: AppText(label).small.bold,
            ),
          ],
        ),
      ),
    );
  }
}
