import 'package:flutter/material.dart';

import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/design/spacing.dart';

/// Flexible leading/title/subtitle/trailing row. Replaces shadcn's `Basic`
/// layout widget. Unlike Material's [ListTile] it imposes no fixed height or
/// padding, so it drops into cards and toasts the same way `Basic` did.
class AppTile extends StatelessWidget {
  final Widget? leading;
  final Widget? title;
  final Widget? subtitle;
  final Widget? trailing;
  final Widget? content;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final CrossAxisAlignment crossAxisAlignment;

  const AppTile({
    super.key,
    this.leading,
    this.title,
    this.subtitle,
    this.trailing,
    this.content,
    this.onTap,
    this.padding = EdgeInsets.zero,
    this.crossAxisAlignment = CrossAxisAlignment.center,
  });

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: crossAxisAlignment,
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: AppSpacing.md),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (title != null)
                  DefaultTextStyle.merge(
                    style: const TextStyle(fontWeight: FontWeight.w500),
                    child: title!,
                  ),
                if (subtitle != null) ...[
                  if (title != null) const SizedBox(height: AppSpacing.xxs),
                  subtitle!,
                ],
                if (content != null) ...[
                  if (title != null || subtitle != null)
                    const SizedBox(height: AppSpacing.xs),
                  content!,
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: AppSpacing.md),
            trailing!,
          ],
        ],
      ),
    );

    if (onTap == null) return row;
    return InkWell(onTap: onTap, borderRadius: AppRadius.allMd, child: row);
  }
}
