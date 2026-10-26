import 'package:flutter/material.dart';

/// The app's only animation: 200 ms ease-out. Every fade, size change or
/// slide uses exactly this; navigation does not animate at all.
abstract final class AppMotion {
  static const duration = Duration(milliseconds: 200);
  static const curve = Curves.easeOut;

  /// [duration], or none at all when the system asks for reduced motion.
  /// Views animate with this rather than [duration], so the setting reaches
  /// every fade and slide.
  static Duration of(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false
      ? Duration.zero
      : duration;
}
