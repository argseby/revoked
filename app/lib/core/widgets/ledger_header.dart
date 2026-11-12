import 'package:material_ui/material_ui.dart';

import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';

/// The start of a section: a short label with its count beside it and one
/// action on the right, set apart from the section above by space.
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
          Flexible(
            child: Semantics(
              header: true,
              child: AppText(title).small.bold.muted,
            ),
          ),
          if (count != null) ...[AppSpacing.gapSm, AppText(count!).small.muted],
          if (trailing != null) const Spacer(),
          if (trailing != null) ...[AppSpacing.gapSm, trailing!],
        ],
      ),
    );
  }
}
