import 'package:flutter/material.dart';

import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';

/// The start of a section: a heavy rule, a short label and, on the right, a
/// count or one action. The rule is what gives a long screen its structure,
/// like the lines of a ledger.
class LedgerHeader extends StatelessWidget {
  final String title;

  /// "3 records", "4 people". Plain text, beside the trailing action if both.
  final String? count;
  final Widget? trailing;

  const LedgerHeader(this.title, {super.key, this.count, this.trailing});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.xl, bottom: AppSpacing.sm),
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: scheme.onSurface, width: 2)),
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
