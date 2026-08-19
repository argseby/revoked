import 'package:flutter/material.dart';

/// The app's only progress indicator. Two sizes: inline (inside a button or a
/// row of text) and [large] for a whole page or panel that has nothing else to
/// show yet. Anything in between is a screen inventing its own scale.
class AppSpinner extends StatelessWidget {
  final bool large;

  /// Set when the spinner sits on a filled surface and must match its
  /// foreground; otherwise it takes the theme's.
  final Color? color;

  const AppSpinner({super.key, this.large = false, this.color});

  @override
  Widget build(BuildContext context) {
    final extent = large ? 24.0 : 16.0;
    return SizedBox(
      width: extent,
      height: extent,
      child: CircularProgressIndicator(strokeWidth: 2, color: color),
    );
  }
}
