import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revoked_app/core/design/app_colors.dart';
import 'package:revoked_app/core/theme/app_theme.dart';

/// Every colour pair the app draws text or a control with, held to WCAG 2.2
/// AA: 4.5:1 for text, 3:1 for a control's edge, the focus ring and the
/// marker of the current destination. The palette was checked by hand once;
/// this keeps it checked whenever a value changes.
void main() {
  double luminance(Color c) {
    double channel(double v) => v <= 0.04045
        ? v / 12.92
        : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    return 0.2126 * channel(c.r) +
        0.7152 * channel(c.g) +
        0.0722 * channel(c.b);
  }

  double ratio(Color a, Color b) {
    final la = luminance(a), lb = luminance(b);
    final hi = math.max(la, lb), lo = math.min(la, lb);
    return (hi + 0.05) / (lo + 0.05);
  }

  for (final brightness in Brightness.values) {
    final s = AppTheme.scheme(brightness);
    final page = AppTheme.build(brightness).scaffoldBackgroundColor;
    final backgrounds = {
      'page': page,
      'surface': s.surface,
      'lowest': s.surfaceContainerLowest,
      'container': s.surfaceContainer,
      'high': s.surfaceContainerHigh,
      'highest': s.surfaceContainerHighest,
    };

    // Text, at 4.5:1, on every background it is drawn on.
    final text = {
      'body': s.onSurface,
      'secondary': s.onSurfaceVariant,
      'accent': s.accent,
      'success': s.success,
      'warning': s.warning,
      'danger': s.danger,
    };

    // Foreground on its own fill, at 4.5:1.
    final pairs = {
      'primary button': (s.onPrimary, s.primary),
      'primary container': (s.onPrimaryContainer, s.primaryContainer),
      'tonal button': (s.onSecondaryContainer, s.secondaryContainer),
      'tertiary': (s.onTertiary, s.tertiary),
      'error': (s.onError, s.error),
      'error container': (s.onErrorContainer, s.errorContainer),
      'success on its tint': (s.success, s.successContainer),
      'warning on its tint': (s.warning, s.warningContainer),
      'danger on its tint': (s.danger, s.dangerContainer),
      'revoke button': (s.onDangerFill, s.dangerFill),
      'tooltip': (s.onInverseSurface, s.inverseSurface),
    };

    // Not text, but still has to be seen, at 3:1: a field's edge, the focus
    // ring, the current-destination pill and the sidebar's ink bar.
    final controls = {
      'control border': s.outline,
      'focus ring': s.accent,
      'destination marker': s.primary,
    };

    group(brightness.name, () {
      for (final MapEntry(key: fgName, value: fg) in text.entries) {
        for (final MapEntry(key: bgName, value: bg) in backgrounds.entries) {
          test('$fgName text on $bgName', () {
            expect(ratio(fg, bg), greaterThanOrEqualTo(4.5));
          });
        }
      }
      for (final MapEntry(key: name, value: (fg, bg)) in pairs.entries) {
        test(name, () => expect(ratio(fg, bg), greaterThanOrEqualTo(4.5)));
      }
      for (final MapEntry(key: name, value: fg) in controls.entries) {
        for (final MapEntry(key: bgName, value: bg) in backgrounds.entries) {
          test('$name on $bgName', () {
            expect(ratio(fg, bg), greaterThanOrEqualTo(3));
          });
        }
      }
    });
  }

  test('the ratio matches the WCAG reference values', () {
    expect(ratio(Colors.black, Colors.white), closeTo(21, 0.01));
    expect(ratio(const Color(0xFF767676), Colors.white), closeTo(4.54, 0.01));
  });
}
