import 'package:flutter/material.dart';
import 'package:revoked_app/core/design/app_colors.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/utils/form_factor.dart';

/// Where someone is on the way from the app to the browser and back:
/// [at] 0 is about to leave, 1 is in the browser, 2 is back.
///
/// Drawn the same before, during and after, so the browser opening is the
/// step the picture promised rather than a surprise.
class RoundTrip extends StatelessWidget {
  final int at;

  const RoundTrip({super.key, required this.at});

  static const _dot = 44.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final stops = [
      (isMobileDevice ? AppIcons.phone : AppIcons.computer, 'Here'),
      (AppIcons.globe, 'Browser'),
      (AppIcons.boxArrowInRight, 'Back here'),
    ];

    Widget stop(int i) {
      final done = i < at;
      final current = i == at;
      final (icon, label) = stops[i];
      return SizedBox(
        width: _dot * 2,
        child: Column(
          children: [
            Container(
              width: _dot,
              height: _dot,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done
                    ? scheme.successContainer
                    : current
                    ? scheme.primary
                    : null,
                border: done || current
                    ? null
                    : Border.all(color: scheme.outline),
              ),
              child: Icon(
                done ? AppIcons.check : icon,
                size: AppSpacing.xl,
                color: done
                    ? scheme.success
                    : current
                    ? scheme.onPrimary
                    : scheme.onSurfaceVariant,
              ),
            ),
            AppSpacing.gapXs,
            AppText(label).small.muted,
          ],
        ),
      );
    }

    Widget line(int i) => Expanded(
      child: Padding(
        padding: const EdgeInsets.only(top: _dot / 2),
        child: Container(
          height: 2,
          color: i < at ? scheme.success : scheme.outlineVariant,
        ),
      ),
    );

    return Semantics(
      label: 'Step ${at + 1} of 3: ${stops[at].$2}',
      child: ExcludeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [stop(0), line(0), stop(1), line(1), stop(2)],
        ),
      ),
    );
  }
}
