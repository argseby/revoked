import 'package:flutter/material.dart';

import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';

/// The app's only rule line. A bare [AppDivider] is a hairline that takes no
/// vertical space of its own — separators between rows must not add rhythm the
/// spacing scale didn't ask for.
class AppDivider extends StatelessWidget {
  /// Insets both ends so the line starts where the content does, for rules
  /// drawn between rows inside a card.
  final bool inset;

  /// Adds breathing room around the line, for rules that separate sections
  /// rather than rows.
  final bool spaced;

  /// Renders centred text in a gap in the line ("or").
  final String? label;

  const AppDivider({
    super.key,
    this.inset = false,
    this.spaced = false,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    if (label != null) {
      return Row(
        children: [
          const Expanded(child: Divider()),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Text(label!).muted.small,
          ),
          const Expanded(child: Divider()),
        ],
      );
    }
    return Divider(
      height: spaced ? AppSpacing.lg : 1,
      indent: inset ? AppSpacing.lg : 0,
      endIndent: inset ? AppSpacing.lg : 0,
    );
  }
}
