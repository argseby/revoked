import 'package:flutter/material.dart';
import 'package:revoked_app/core/design/app_colors.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/widgets/app_divider.dart';

/// Whether the reader can satisfy one requirement right now.
enum RequirementStatus {
  /// Met — nothing more to do for this one.
  ready,

  /// Not met yet, but within reach (a field still to fill).
  pending,

  /// Cannot be met as things stand — the reason names whose problem it is.
  blocked,
}

/// One gate between the reader and submitting.
class RequirementItem {
  final IconData icon;
  final String title;
  final String description;
  final RequirementStatus status;

  const RequirementItem({
    required this.icon,
    required this.title,
    required this.description,
    required this.status,
  });
}

/// The "required to submit" group: every gate in one card, each row stating
/// what it is, what it means, and — at a glance, right-aligned — whether the
/// reader already satisfies it. Green rows need nothing; a red row tells the
/// reader whether the blocker is theirs to fix or the sender's.
class RequirementList extends StatelessWidget {
  final List<RequirementItem> items;

  const RequirementList({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: AppRadius.allMd,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final item in items) ...[
            if (item != items.first) const AppDivider(),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(item.icon, size: 16, color: scheme.onSurfaceVariant),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.title).small,
                        const SizedBox(height: AppSpacing.xxs),
                        Text(item.description).muted.small,
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  _StatusIcon(status: item.status),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusIcon extends StatelessWidget {
  final RequirementStatus status;

  const _StatusIcon({required this.status});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, color) = switch (status) {
      RequirementStatus.ready => (AppIcons.checkCircle, scheme.primary),
      RequirementStatus.pending => (AppIcons.circle, scheme.onSurfaceVariant),
      RequirementStatus.blocked => (AppIcons.xCircle, scheme.danger),
    };
    return Icon(icon, size: 16, color: color);
  }
}
