import 'package:flutter/material.dart';

import 'package:revoked_app/core/design/app_colors.dart';
import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/widgets/app_focus_ring.dart';

/// How urgent an [AttentionCard] is. Each has its own colour, and always its
/// own icon and word, so colour is never the only signal.
enum AttentionTone { info, success, warning, danger }

/// One thing that needs the person, on the Overview: a status word, a count
/// ("2 requests") and one line of detail. Tapping it opens the list it counts.
class AttentionCard extends StatelessWidget {
  final AttentionTone tone;
  final IconData icon;

  /// The status word — "To answer", "Ends soon", "Check sender".
  final String label;

  /// The count, said in full — "2 requests".
  final String value;
  final String detail;
  final VoidCallback? onTap;

  const AttentionCard({
    super.key,
    required this.tone,
    required this.icon,
    required this.label,
    required this.value,
    required this.detail,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (tone) {
      AttentionTone.info => scheme.accent,
      AttentionTone.success => scheme.success,
      AttentionTone.warning => scheme.warning,
      AttentionTone.danger => scheme.danger,
    };
    final edge = tone == AttentionTone.danger ? scheme.danger : scheme.outline;
    final body = Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        borderRadius: AppRadius.allMd,
        border: Border.all(color: edge),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              AppSpacing.gapXs,
              Flexible(
                child: DefaultTextStyle.merge(
                  style: TextStyle(color: color),
                  child: AppText(label).small.bold,
                ),
              ),
            ],
          ),
          AppSpacing.gapXs,
          AppText(value).header,
          AppText(detail).small.muted,
        ],
      ),
    );
    return Semantics(
      button: onTap != null,
      label: '$label: $value. $detail',
      excludeSemantics: true,
      child: onTap == null
          ? body
          : AppFocusRing(
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  onTap: onTap,
                  borderRadius: AppRadius.allMd,
                  child: body,
                ),
              ),
            ),
    );
  }
}
