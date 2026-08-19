import 'package:flutter/material.dart';

import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/design/spacing.dart';

/// Inline alert banner. Replaces shadcn's `Alert` (Material has no inline
/// alert widget). Renders an optional leading icon, a title and content using
/// M3 container color roles. `destructive: true` switches to the error palette.
class AppAlert extends StatelessWidget {
  final Widget? leading;
  final Widget? title;
  final Widget? content;
  final bool destructive;

  const AppAlert({
    super.key,
    this.leading,
    this.title,
    this.content,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = destructive
        ? scheme.errorContainer
        : scheme.surfaceContainerHighest;
    final fg = destructive ? scheme.onErrorContainer : scheme.onSurface;
    final border = destructive
        ? scheme.error.withValues(alpha: 0.4)
        : scheme.outlineVariant;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: AppRadius.allMd,
        border: Border.all(color: border),
      ),
      child: DefaultTextStyle.merge(
        style: TextStyle(color: fg),
        child: IconTheme.merge(
          data: IconThemeData(color: fg, size: 18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ?leading,
              if (leading != null) AppSpacing.gapMd,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (title != null)
                      DefaultTextStyle.merge(
                        style: const TextStyle(fontWeight: FontWeight.w600),
                        child: title!,
                      ),
                    if (title != null && content != null) AppSpacing.gapXxs,
                    ?content,
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
