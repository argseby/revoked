import 'package:flutter/material.dart';

import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/widgets/app_badge.dart';
import 'package:revoked_app/core/widgets/app_button.dart';

/// A screen's name and count, rendered in the shell's top bar rather than in
/// the screen's body — a list spends its vertical space on content. Screens
/// register one through `ShellSlots.title`; nothing else draws a title up
/// there, so every screen reads the same.
class AppBarTitle extends StatelessWidget {
  final String title;

  /// The count beside the name — "12 links", "3 records".
  final String? badgeLabel;

  /// Set by a sub-screen: the back arrow it is left by, ahead of the title —
  /// the single, consistent way out, in the same place on every screen.
  final VoidCallback? onBack;

  const AppBarTitle({
    super.key,
    required this.title,
    this.badgeLabel,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (onBack != null) ...[
          AppButton(
            icon: AppIcons.arrowLeft,
            style: AppButtonStyle.accent,
            tooltip: 'Back',
            onTap: onBack,
          ),
          AppSpacing.gapXs,
        ],
        Flexible(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ).header,
        ),
        if (badgeLabel != null) ...[
          AppSpacing.gapSm,
          AppBadge(label: badgeLabel!),
        ],
      ],
    );
  }
}
