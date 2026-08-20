import 'package:flutter/material.dart';

/// Color roles Material 3 does not define, derived from the active scheme so
/// they flip with brightness like every built-in role does.
///
/// Nothing in the app names a raw `Colors.*` swatch: a fixed swatch is tuned
/// for one background and goes illegible on the other.
extension AppColorRoles on ColorScheme {
  /// Caution — paused links, unverified identities. Not a failure, so it must
  /// not reuse [error], and not a success, so it must not reuse [primary].
  Color get warning =>
      brightness == Brightness.light ? _warningLight : _warningDark;

  /// [warning] as a fill behind [warning]-colored text.
  Color get warningContainer => brightness == Brightness.light
      ? _warningContainerLight
      : _warningContainerDark;

  /// Security alarm — an unverified or spoofed domain.
  ///
  /// Deliberately not [error]: the seeded error tone is `#FFB4AB` on a dark
  /// surface, which reads as salmon rather than red. A phishing warning has to
  /// look like a stop sign, so this is a saturated red picked per brightness
  /// for legibility rather than derived from the seed.
  Color get danger =>
      brightness == Brightness.light ? _dangerLight : _dangerDark;

  /// [danger] as a filled bar. Fixed across brightness — it is paired with
  /// [onDangerFill] rather than sitting on the page background, so it stays
  /// legible either way.
  Color get dangerFill => _dangerFill;

  /// Text and icons drawn on [dangerFill].
  Color get onDangerFill => _onDangerFill;

  /// The error role legible against [inverseSurface]. A surface painted in the
  /// opposite brightness needs the opposite scheme's error, not this one's.
  Color get inverseError =>
      brightness == Brightness.light ? _errorDark : _errorLight;
}

const Color _warningLight = Color(0xFF7A5900);
const Color _warningDark = Color(0xFFF2C24B);
const Color _warningContainerLight = Color(0xFFFFDF9E);
const Color _warningContainerDark = Color(0xFF5C4200);

const Color _dangerLight = Color(0xFFC62828);
const Color _dangerDark = Color(0xFFFF6259);
const Color _dangerFill = Color(0xFFD32F2F);
const Color _onDangerFill = Color(0xFFFFFFFF);

// Material 3's own baseline error tones, kept as constants so [inverseError]
// does not have to build a second ColorScheme on every toast.
const Color _errorLight = Color(0xFFB3261E);
const Color _errorDark = Color(0xFFFFB4AB);
