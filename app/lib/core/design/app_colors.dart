import 'package:flutter/material.dart';

/// Every colour the app draws with, per brightness.
///
/// The values are chosen, not derived from a seed, so the contrast they were
/// checked for is the contrast that ships: `test/contrast_test.dart` holds
/// each pair to WCAG AA (4.5:1 for text, 3:1 for borders, focus rings and
/// state indicators). Change a value here and that test says whether it still
/// passes.
///
/// Ink on paper, with one signature colour: indigo marks the main action,
/// links, focus and the current destination. Red, amber and green stay
/// reserved for status, so indigo never has to mean "danger" or "done".
abstract final class AppPalette {
  // Light.
  static const lightPaper = Color(0xFFFAF9F6);
  static const lightWhite = Color(0xFFFFFFFF);
  static const lightCard = Color(0xFFF2F0F6);
  static const lightCardHigh = Color(0xFFECEAF2);
  static const lightCardHighest = Color(0xFFE6E3EE);
  static const lightInk = Color(0xFF16151F);
  static const lightSecondaryText = Color(0xFF575569);
  static const lightControlBorder = Color(0xFF7D798F);
  static const lightDivider = Color(0xFFE1DEE8);
  static const lightBrand = Color(0xFF3D35B5);
  static const lightBrandContainer = Color(0xFFE9E6FB);
  static const lightOnBrandContainer = Color(0xFF2A2390);
  static const lightSuccess = Color(0xFF1D6B4C);
  static const lightSuccessContainer = Color(0xFFD7F0E3);
  static const lightWarning = Color(0xFF7A5600);
  static const lightWarningContainer = Color(0xFFFFEFC9);
  static const lightDanger = Color(0xFFB42318);
  static const lightDangerContainer = Color(0xFFFCE4E1);
  static const lightDangerFill = Color(0xFFC62828);

  // Dark.
  static const darkPage = Color(0xFF0E0D14);
  static const darkSurface = Color(0xFF15141C);
  static const darkCard = Color(0xFF1D1C26);
  static const darkCardHigh = Color(0xFF22212C);
  static const darkCardHighest = Color(0xFF282632);
  static const darkInk = Color(0xFFF1F0F7);
  static const darkOnInk = Color(0xFF16151F);
  static const darkSecondaryText = Color(0xFFA9A6BC);
  static const darkControlBorder = Color(0xFF77748C);
  static const darkDivider = Color(0xFF2E2C3A);
  static const darkBrand = Color(0xFFB3ACFF);
  static const darkOnBrand = Color(0xFF16133F);
  static const darkBrandContainer = Color(0xFF2E2870);
  static const darkOnBrandContainer = Color(0xFFDCD8FF);
  static const darkSuccess = Color(0xFF8ED5B1);
  static const darkSuccessContainer = Color(0xFF12352A);
  static const darkWarning = Color(0xFFF2C24B);
  static const darkWarningContainer = Color(0xFF3D2E05);
  static const darkDanger = Color(0xFFFF6259);
  static const darkDangerContainer = Color(0xFF3F1512);
  static const darkDangerFill = Color(0xFFD32F2F);

  /// White on either theme's [dangerFill].
  static const onDangerFill = Color(0xFFFFFFFF);
}

/// Colour roles Material 3 does not define, flipping with brightness like
/// every built-in role does.
///
/// Nothing in the app names a raw `Colors.*` swatch: a fixed swatch is tuned
/// for one background and goes illegible on the other.
extension AppColorRoles on ColorScheme {
  bool get _light => brightness == Brightness.light;

  /// Good — an active link, a completed request, a verified sender. A status
  /// list reads as a traffic light: green active, amber paused, red danger.
  Color get success =>
      _light ? AppPalette.lightSuccess : AppPalette.darkSuccess;

  /// [success] as a fill behind [success]-coloured text.
  Color get successContainer => _light
      ? AppPalette.lightSuccessContainer
      : AppPalette.darkSuccessContainer;

  /// Caution — paused links, links ending soon. Not a failure, so it must not
  /// reuse [error], and not a success, so it must not reuse [success].
  Color get warning =>
      _light ? AppPalette.lightWarning : AppPalette.darkWarning;

  /// [warning] as a fill behind [warning]-coloured text.
  Color get warningContainer => _light
      ? AppPalette.lightWarningContainer
      : AppPalette.darkWarningContainer;

  /// Security alarm — an unverified or spoofed domain. A phishing warning has
  /// to look like a stop sign. The same value as [error], named for intent.
  Color get danger => _light ? AppPalette.lightDanger : AppPalette.darkDanger;

  /// [danger] as a fill behind [danger]-coloured text.
  Color get dangerContainer =>
      _light ? AppPalette.lightDangerContainer : AppPalette.darkDangerContainer;

  /// [danger] as a solid button — revoke, delete — under [onDangerFill]. A
  /// shade of its own because the text tone of dark mode is too light to
  /// carry white.
  Color get dangerFill =>
      _light ? AppPalette.lightDangerFill : AppPalette.darkDangerFill;

  /// Text and icons drawn on [dangerFill].
  Color get onDangerFill => AppPalette.onDangerFill;

  /// Links and the keyboard focus ring. Inline links are also underlined:
  /// the accent is too close to body text to mark a link by colour alone.
  Color get accent => tertiary;

  /// The error role legible against [inverseSurface]. A surface painted in the
  /// opposite brightness needs the opposite scheme's error, not this one's.
  Color get inverseError =>
      _light ? AppPalette.darkDanger : AppPalette.lightDanger;
}
