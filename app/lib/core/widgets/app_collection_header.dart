import 'package:material_ui/material_ui.dart';

import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/widgets/app_button.dart';

/// Collection pages name themselves in the content, above their local tools.
class AppCollectionHeader extends StatelessWidget {
  final String title;
  final String? description;
  final Widget? action;

  /// A sub-page's way back, beside its title instead of in the top bar.
  final VoidCallback? onBack;

  const AppCollectionHeader({
    super.key,
    required this.title,
    this.description,
    this.action,
    this.onBack,
  });

  Widget _title() {
    final text = AppText(title).header;
    if (onBack == null) return text;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppButton(
          icon: AppIcons.arrowLeft,
          tooltip: 'Back',
          style: AppButtonStyle.ghost,
          onTap: onBack,
        ),
        AppSpacing.gapXs,
        Flexible(child: text),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.md),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (action == null)
          _title()
        else
          OverflowBar(
            alignment: MainAxisAlignment.spaceBetween,
            spacing: AppSpacing.md,
            overflowSpacing: AppSpacing.sm,
            overflowAlignment: OverflowBarAlignment.start,
            children: [_title(), action!],
          ),
        if (description != null) ...[
          AppSpacing.gapXxs,
          AppText(description!).small.muted,
        ],
      ],
    ),
  );
}

/// A few meaningful destinations above a collection, wrapping on small screens.
class AppCollectionGrid extends StatelessWidget {
  final List<Widget> children;
  const AppCollectionGrid({super.key, required this.children});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
      final columns = (box.maxWidth / (220 * scale)).floor().clamp(1, 3);
      final width = (box.maxWidth - AppSpacing.md * (columns - 1)) / columns;
      return Wrap(
        spacing: AppSpacing.md,
        runSpacing: AppSpacing.md,
        children: [
          for (final child in children) SizedBox(width: width, child: child),
        ],
      );
    },
  );
}

class AppCollectionTile extends StatelessWidget {
  final String title;
  final String value;
  final String description;
  final IconData icon;
  final VoidCallback onTap;
  final bool selected;
  final Color? accent;

  const AppCollectionTile({
    super.key,
    required this.title,
    required this.value,
    required this.description,
    required this.icon,
    required this.onTap,
    this.selected = false,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected
            ? scheme.secondaryContainer
            : scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.allMd,
          side: BorderSide(
            color: selected ? scheme.primary : scheme.outlineVariant,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.allMd,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: LayoutBuilder(
              builder: (context, box) {
                final compact =
                    box.maxWidth >= 240 ||
                    MediaQuery.textScalerOf(context).scale(16) > 24;
                final copy = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppText(title).bold,
                    AppSpacing.gapXxs,
                    AppText(description).small.muted,
                  ],
                );
                if (compact) {
                  return Row(
                    children: [
                      Icon(
                        icon,
                        size: 22,
                        color: accent ?? scheme.onSurfaceVariant,
                      ),
                      AppSpacing.gapMd,
                      Expanded(child: copy),
                      AppSpacing.gapMd,
                      AppText(value).header,
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          icon,
                          size: 22,
                          color: accent ?? scheme.onSurfaceVariant,
                        ),
                        const Spacer(),
                        AppText(value).header,
                      ],
                    ),
                    AppSpacing.gapLg,
                    copy,
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
