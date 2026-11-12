import 'package:material_ui/material_ui.dart';
import 'package:revoked_app/core/design/app_colors.dart';
import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/design/spacing.dart';

/// How an [AppAlert] reads. Colour is never the only signal: a toned alert
/// carries its own icon and words.
enum AppAlertTone { neutral, success, warning, danger }

/// Inline alert banner. Replaces shadcn's `Alert` (Material has no inline
/// alert widget). Renders an optional leading icon, a title and content using
/// M3 container color roles. `destructive: true` is [AppAlertTone.danger].
class AppAlert extends StatelessWidget {
  final Widget? leading;
  final Widget? title;
  final Widget? content;
  final bool destructive;
  final AppAlertTone tone;

  const AppAlert({
    super.key,
    this.leading,
    this.title,
    this.content,
    this.destructive = false,
    this.tone = AppAlertTone.neutral,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final effective = destructive ? AppAlertTone.danger : tone;
    final (bg, fg, border) = switch (effective) {
      AppAlertTone.neutral => (
        scheme.surfaceContainerHighest,
        scheme.onSurface,
        scheme.outlineVariant,
      ),
      AppAlertTone.danger => (
        scheme.errorContainer.withValues(alpha: 0.75),
        scheme.onErrorContainer.withValues(alpha: 0.8),
        scheme.error.withValues(alpha: 0.4),
      ),
      AppAlertTone.success => (
        scheme.successContainer,
        scheme.success,
        scheme.success.withValues(alpha: 0.4),
      ),
      AppAlertTone.warning => (
        scheme.warningContainer,
        scheme.warning,
        scheme.warning.withValues(alpha: 0.4),
      ),
    };

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
