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

  /// The error role legible against [inverseSurface]. A surface painted in the
  /// opposite brightness needs the opposite scheme's error, not this one's.
  Color get inverseError =>
      brightness == Brightness.light ? _errorDark : _errorLight;
}

const Color _warningLight = Color(0xFF7A5900);
const Color _warningDark = Color(0xFFF2C24B);
const Color _warningContainerLight = Color(0xFFFFDF9E);
const Color _warningContainerDark = Color(0xFF5C4200);

// Material 3's own baseline error tones, kept as constants so [inverseError]
// does not have to build a second ColorScheme on every toast.
const Color _errorLight = Color(0xFFB3261E);
const Color _errorDark = Color(0xFFFFB4AB);
