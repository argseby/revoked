import 'package:flutter/material.dart';
import 'package:revoked_app/core/design/motion.dart';

/// The app's size change, at [AppMotion].
///
/// With reduced motion the duration is zero, and an [AnimatedSize] that
/// finishes the instant it starts re-dirties its own layout and throws, so
/// the child is then laid out at its new size directly.
class AppAnimatedSize extends StatelessWidget {
  final Widget child;

  const AppAnimatedSize({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final duration = AppMotion.of(context);
    if (duration == Duration.zero) return child;
    return AnimatedSize(
      duration: duration,
      curve: AppMotion.curve,
      alignment: Alignment.topCenter,
      child: child,
    );
  }
}
