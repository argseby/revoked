import 'package:flutter/widgets.dart';

/// Corner-radius scale, the [AppSpacing] counterpart for rounding.
///
/// Four steps and a pill. Views never call `BorderRadius.circular(n)` with a
/// bare number; the whole point is that a card, an alert and a dialog cannot
/// quietly disagree about how round they are. The steps are square, like the
/// website; only avatars, dots and progress tracks stay round.
abstract final class AppRadius {
  /// Tight rounding for chips and inline labels that sit inside text.
  static const double xs = 0;

  /// Inputs, small controls, table cells.
  static const double sm = 0;

  /// The default: cards, alerts, dialogs, menus, toasts, buttons and tags.
  static const double md = 0;

  /// Large surfaces — sheets, hero containers.
  static const double lg = 0;

  /// Fully rounded ends. Avatars, progress tracks, round affordances.
  static const double pill = 999;

  static const BorderRadius allXs = BorderRadius.all(Radius.circular(xs));
  static const BorderRadius allSm = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius allMd = BorderRadius.all(Radius.circular(md));
  static const BorderRadius allLg = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius allPill = BorderRadius.all(Radius.circular(pill));
}
