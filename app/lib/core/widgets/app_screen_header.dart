import 'package:flutter/material.dart';

import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/widgets/app_badge.dart';
import 'package:revoked_app/core/widgets/app_button.dart';

/// Compact screen header: an optional back arrow, then `title · count` on the
/// left and any actions on the right. No divider; an optional [subtitle]
/// renders as one tight muted line below. Kept deliberately short so list
/// screens spend their vertical space on content, not chrome.
class AppScreenHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? badgeLabel;
  final List<Widget>? actions;

  /// When set, a top-left back arrow is shown — the single, consistent way to
  /// leave any sub-screen.
  final VoidCallback? onBack;

  const AppScreenHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.badgeLabel,
    this.actions,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        top: AppSpacing.xxs,
        bottom: AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
              Expanded(
                child: Row(
                  children: [
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
                ),
              ),
              for (final action in actions ?? const <Widget>[]) ...[
                AppSpacing.gapXs,
                action,
              ],
            ],
          ),
          if (subtitle != null) ...[
            AppSpacing.gapXxs,
            Text(
              subtitle!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ).muted.small,
          ],
        ],
      ),
    );
  }
}
