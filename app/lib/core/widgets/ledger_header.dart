import 'package:flutter/material.dart';

import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';

/// The start of a section: a short label and, on the right, a count or one
/// action, set apart from the section above by space.
class LedgerHeader extends StatelessWidget {
  final String title;

  /// "3 records", "4 people". Plain text, beside the trailing action if both.
  final String? count;
  final Widget? trailing;

  const LedgerHeader(this.title, {super.key, this.count, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        top: AppSpacing.xxl,
        bottom: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: AppText(title).small.bold.muted,
            ),
          ),
          if (count != null) AppText(count!).small.muted,
          if (trailing != null) ...[AppSpacing.gapSm, trailing!],
        ],
      ),
    );
  }
}
