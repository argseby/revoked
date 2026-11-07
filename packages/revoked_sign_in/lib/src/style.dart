import 'package:flutter/widgets.dart';

/// The wording on the button.
enum RevokedLabel {
  /// "Continue with Revoked". The default: one button for new and returning
  /// people, since Revoked has no separate registration.
  continueWith,

  /// "Sign in with Revoked", for pages that only sign in.
  signIn,

  /// "Sign up with Revoked", for registration pages.
  signUp,

  /// The mark alone. The [continueWith] label becomes its accessible name.
  iconOnly,
}

/// The button's colours. The theme also tells the button what the page behind
/// it looks like, so the error line under it stays readable.
enum RevokedTheme {
  /// Black button, for light pages. The default.
  black,

  /// White button, for dark pages and photos.
  white,

  /// Transparent, in the surrounding text colour.
  outline,

  /// Black in light mode, white in dark mode.
  auto,
}

/// Corner style.
enum RevokedShape { rounded, pill }

/// Minimum heights 36, 44 and 52. [small] is for pointer-only toolbars;
/// [medium] and [large] meet the 44-point touch target.
enum RevokedSize { small, medium, large }

/// The measurements of spec v1, in logical pixels.
@immutable
class RevokedSizeSpec {
  const RevokedSizeSpec._({
    required this.minHeight,
    required this.paddingX,
    required this.gap,
    required this.fontSize,
    required this.radius,
  });

  final double minHeight;
  final double paddingX;
  final double gap;
  final double fontSize;
  final double radius;

  /// The mark is 1.125 times the label size, and 1.25 times when it stands
  /// alone, so it scales with the label.
  double get markSize => fontSize * 1.125;
  double get iconMarkSize => fontSize * 1.25;

  static const small = RevokedSizeSpec._(minHeight: 36, paddingX: 14, gap: 8, fontSize: 14, radius: 8);
  static const medium = RevokedSizeSpec._(minHeight: 44, paddingX: 18, gap: 10, fontSize: 16, radius: 10);
  static const large = RevokedSizeSpec._(minHeight: 52, paddingX: 22, gap: 12, fontSize: 17, radius: 12);

  static RevokedSizeSpec of(RevokedSize size) => switch (size) {
    RevokedSize.small => small,
    RevokedSize.medium => medium,
    RevokedSize.large => large,
  };
}

/// The colours one theme resolves to.
@immutable
class RevokedPalette {
  const RevokedPalette({
    required this.background,
    required this.foreground,
    required this.edge,
    required this.hover,
    required this.pressed,
    required this.error,
  });

  final Color background;
  final Color foreground;
  final Color edge;
  final Color hover;
  final Color pressed;
  final Color error;

  static const _black = RevokedPalette(
    background: Color(0xFF000000),
    foreground: Color(0xFFFFFFFF),
    edge: Color(0x33FFFFFF),
    hover: Color(0xFF24272D),
    pressed: Color(0xFF383C44),
    error: Color(0xFFB3261E),
  );

  static const _white = RevokedPalette(
    background: Color(0xFFFFFFFF),
    foreground: Color(0xFF000000),
    edge: Color(0x29000000),
    hover: Color(0xFFEEF0F3),
    pressed: Color(0xFFE0E3E8),
    error: Color(0xFFFFB4AB),
  );

  /// Resolves [theme] for the current light or dark mode. [text] is the
  /// surrounding text colour, which the outline theme takes on.
  static RevokedPalette resolve(
    RevokedTheme theme, {
    required Brightness brightness,
    required Color text,
    bool highContrast = false,
  }) {
    final palette = switch (theme) {
      RevokedTheme.black => _black,
      RevokedTheme.white => _white,
      RevokedTheme.auto => brightness == Brightness.dark ? _white : _black,
      RevokedTheme.outline => RevokedPalette(
        background: const Color(0x00000000),
        foreground: text,
        edge: text,
        hover: const Color(0x1F7F7F7F),
        pressed: const Color(0x337F7F7F),
        error: text,
      ),
    };
    if (!highContrast || theme == RevokedTheme.outline) return palette;
    // With "increase contrast" on, the edge is drawn in full and the error
    // colour moves further from the page.
    final onDark = palette.background == _white.background;
    return RevokedPalette(
      background: palette.background,
      foreground: palette.foreground,
      edge: onDark ? const Color(0xFF000000) : const Color(0xFFFFFFFF),
      hover: palette.hover,
      pressed: palette.pressed,
      error: onDark ? const Color(0xFFFFDAD6) : const Color(0xFF8C1D18),
    );
  }
}

/// The panel's colours, which follow light and dark mode.
@immutable
class RevokedPanelColors {
  const RevokedPanelColors._({
    required this.foreground,
    required this.background,
    required this.line,
    required this.solid,
    required this.onSolid,
  });

  final Color foreground;
  final Color background;
  final Color line;
  final Color solid;
  final Color onSolid;

  static const light = RevokedPanelColors._(
    foreground: Color(0xFF191C20),
    background: Color(0xFFFFFFFF),
    line: Color(0xFFD9DDE5),
    solid: Color(0xFF000000),
    onSolid: Color(0xFFFFFFFF),
  );

  static const dark = RevokedPanelColors._(
    foreground: Color(0xFFE1E2E8),
    background: Color(0xFF181C21),
    line: Color(0xFF2C3137),
    solid: Color(0xFFFFFFFF),
    onSolid: Color(0xFF000000),
  );

  static RevokedPanelColors of(Brightness brightness) => brightness == Brightness.dark ? dark : light;
}
