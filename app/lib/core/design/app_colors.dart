import 'package:flutter/material.dart';

/// Every colour the app draws with, per brightness.
///
/// The values are chosen, not derived from a seed, so the contrast they were
/// checked for is the contrast that ships: `test/contrast_test.dart` holds
/// each pair to WCAG AA (4.5:1 for text, 3:1 for borders, focus rings and
/// state indicators). Change a value here and that test says whether it still
/// passes.
///
/// The look is ink on paper: near-black ink for text, primary buttons and
/// rules on a warm paper tone, flipped to paper on ink in dark mode. Colour is
/// kept for status — active, paused, danger — so it stands out.
abstract final class AppPalette {
  // Light.
  static const lightPaper = Color(0xFFF6F5F1);
  static const lightWhite = Color(0xFFFFFFFF);
  static const lightCard = Color(0xFFEFEDE7);
  static const lightCardHigh = Color(0xFFE9E7E0);
  static const lightCardHighest = Color(0xFFE3E0D8);
  static const lightInk = Color(0xFF14171C);
  static const lightSecondaryText = Color(0xFF5A5F68);
  static const lightControlBorder = Color(0xFF7F7B73);
  static const lightDivider = Color(0xFFDAD7CF);
  static const lightAccent = Color(0xFF2F4156);
  static const lightSuccess = Color(0xFF216A4D);
  static const lightSuccessContainer = Color(0xFFDDF0E6);
  static const lightWarning = Color(0xFF7A5900);
  static const lightWarningContainer = Color(0xFFFFE9B8);
  static const lightDanger = Color(0xFFB42318);
  static const lightDangerContainer = Color(0xFFFCE4E1);
  static const lightDangerFill = Color(0xFFC62828);

  // Dark.
  static const darkPage = Color(0xFF0F1114);
  static const darkSurface = Color(0xFF171A1F);
  static const darkCard = Color(0xFF1F232A);
  static const darkCardHigh = Color(0xFF23272E);
  static const darkCardHighest = Color(0xFF272B32);
  static const darkInk = Color(0xFFF2F1EC);
  static const darkOnInk = Color(0xFF14171C);
  static const darkSecondaryText = Color(0xFFA3A8B0);
  static const darkControlBorder = Color(0xFF727883);
  static const darkDivider = Color(0xFF2E333B);
  static const darkAccent = Color(0xFFA9C3E0);
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
