import 'package:flutter/widgets.dart';

/// Corner-radius scale, the [AppSpacing] counterpart for rounding.
///
/// Four steps and a pill. Views never call `BorderRadius.circular(n)` with a
/// bare number; the whole point is that a card, an alert and a dialog cannot
/// quietly disagree about how round they are. Controls use a restrained
/// 8 px radius; larger surfaces use the sidebar panel’s 14 px radius.
abstract final class AppRadius {
  /// Tight rounding for chips and inline labels that sit inside text.
  static const double xs = 4;

  /// Inputs, small controls, table cells.
  static const double sm = 6;

  /// The default: cards, alerts, dialogs, menus, toasts, buttons and tags.
  static const double md = 8;

  /// Large surfaces — sheets, hero containers.
  static const double lg = 14;

  /// Fully rounded ends. Avatars, progress tracks, round affordances.
  static const double pill = 999;

  /// Rows are contiguous slices of a list/menu, rather than separate pills.
  /// Their enclosing card or menu clips the outer corners.
  static const BorderRadius row = BorderRadius.zero;

  static const BorderRadius allXs = BorderRadius.all(Radius.circular(xs));
  static const BorderRadius allSm = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius allMd = BorderRadius.all(Radius.circular(md));
  static const BorderRadius allLg = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius allPill = BorderRadius.all(Radius.circular(pill));
}
