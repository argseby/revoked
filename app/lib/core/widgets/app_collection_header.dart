import 'package:material_ui/material_ui.dart';

import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';

/// Collection pages name themselves in the content, above their local tools.
class AppCollectionHeader extends StatelessWidget {
  final String title;
  final String description;
  final Widget? action;

  const AppCollectionHeader({
    super.key,
    required this.title,
    required this.description,
    this.action,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: AppSpacing.lg, bottom: AppSpacing.xxl),
    child: LayoutBuilder(
      builder: (context, box) {
        final heading = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppText(title).title,
            AppSpacing.gapSm,
            AppText(description).small.muted,
          ],
        );
        if (action == null) return heading;
        if (box.maxWidth < 600 ||
            MediaQuery.textScalerOf(context).scale(16) > 24) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [heading, AppSpacing.gapLg, action!],
          );
        }
        return Row(
          children: [
            Expanded(child: heading),
            AppSpacing.gapLg,
            action!,
          ],
        );
      },
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
