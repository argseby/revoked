import 'package:flutter/material.dart';

import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';

/// A keyboard key drawn as a key cap, beside the control it triggers. Left
/// out on phones and tablets, where a keyboard is the exception, and hidden
/// from screen readers, which announce the control itself.
class AppKeyHint extends StatelessWidget {
  final String label;

  const AppKeyHint(this.label, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (theme.platform == TargetPlatform.android ||
        theme.platform == TargetPlatform.iOS) {
      return const SizedBox.shrink();
    }
    return ExcludeSemantics(
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: 1,
        ),
        decoration: BoxDecoration(
          borderRadius: AppRadius.allXs,
          border: Border.all(color: theme.colorScheme.outline),
        ),
        child: AppText(label).small.muted.mono,
      ),
    );
  }
}
