import 'package:flutter/widgets.dart';

/// Spacing scale used throughout the app.
///
/// Pick values from this scale rather than free-typing pixel values; keeps
/// rhythm and density consistent across screens. The scale follows a
/// roughly 4-pixel grid (4 → 8 → 12 → 16 → 20 → 24 → 32 → 40).
abstract class AppSpacing {
  static const double xxs = 4;
  static const double xs = 6;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double huge = 32;
  static const double gigantic = 40;

  /// SizedBox helpers so call sites stay terse.
  static const SizedBox gapXxs = SizedBox(height: xxs, width: xxs);
  static const SizedBox gapXs = SizedBox(height: xs, width: xs);
  static const SizedBox gapSm = SizedBox(height: sm, width: sm);
  static const SizedBox gapMd = SizedBox(height: md, width: md);
  static const SizedBox gapLg = SizedBox(height: lg, width: lg);
  static const SizedBox gapXl = SizedBox(height: xl, width: xl);
  static const SizedBox gapXxl = SizedBox(height: xxl, width: xxl);

  /// Inset a scrolling list keeps for its scrollbar, so the bar never sits on
  /// the content's edge. Paired with [screenH]: the list pads by this and the
  /// screen by the remainder, which is why both must come from one place.
  static double scrollbarMargin(BuildContext context) =>
      MediaQuery.sizeOf(context).width < 600 ? xxs : xs;

  /// Standard horizontal padding for a screen's content. Use this for every
  /// screen's header AND its scrollable content so they all line up to the
  /// same left/right edge: 16 on narrow (mobile) layouts, 24 on wider ones.
  static double screenH(BuildContext context) =>
      MediaQuery.sizeOf(context).width < 600 ? 16 : 24;
}
