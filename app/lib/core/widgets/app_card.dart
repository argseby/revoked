import 'package:flutter/material.dart';

import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/design/spacing.dart';

/// Flat, bordered Material 3 card. Replaces shadcn's `Card`/`SurfaceCard`,
/// which came with built-in padding and a border. Uses [Card.outlined] for
/// the clean, shadowless M3 look and applies default content padding so call
/// sites read the same as before.
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final VoidCallback? onTap;
  final Clip clipBehavior;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.margin = EdgeInsets.zero,
    this.onTap,
    this.clipBehavior = Clip.antiAlias,
  });

  @override
  Widget build(BuildContext context) {
    final content = Padding(padding: padding, child: child);
    return Card.outlined(
      margin: margin,
      clipBehavior: clipBehavior,
      child: onTap == null
          ? content
          : InkWell(
              onTap: onTap,
              borderRadius: AppRadius.allLg,
              child: content,
            ),
    );
  }
}
