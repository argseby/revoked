import 'package:flutter/material.dart';

import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_focus_ring.dart';
import 'package:revoked_app/core/design/text_styles.dart';

/// The height of the bar's other controls, so search and New line up.
const double _searchHeight = AppButton.smallExtent;

/// The app's one search control: a pill that opens the shell's search and
/// link panel rather than filtering anything in place. Lists do not carry
/// their own search, so this is the only place a query is typed.
class AppSearchTrigger extends StatelessWidget {
  final String hint;
  final VoidCallback onTap;
  final Widget? trailing;

  const AppSearchTrigger({
    super.key,
    required this.hint,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: hint,
      excludeSemantics: true,
      child: AppFocusRing(
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            borderRadius: AppRadius.allMd,
            child: Ink(
              height: _searchHeight,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: AppRadius.allMd,
              ),
              child: Row(
                children: [
                  // The width of a field's prefix icon, so the hint starts
                  // where [AppSearchField]'s does.
                  SizedBox(width: 12),

                  Expanded(
                    child: AppText(
                      hint,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ).muted,
                  ),
                  if (trailing != null) ...[
                    trailing!,
                    AppSpacing.gapSm,
                  ] else
                    AppSpacing.gapMd,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
