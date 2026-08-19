import 'package:flutter/material.dart';

import 'package:revoked_app/core/design/radius.dart';

/// Builds the app's Material 3 theme for a given [Brightness], so light and dark
/// share one definition (only the seeded [ColorScheme] flips).
class AppTheme {
  AppTheme._();

  /// Deep green: `active` renders as [ColorScheme.primary], so the traffic-light
  /// reading of a status list — green active, amber paused, red revoked — falls
  /// out of the scheme instead of being painted on top of it.
  static const Color seed = Color(0xFF00674F);

  static ThemeData build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    );

    // One background for every surface — page, card, sheet, dialog, menu, bar.
    // Material 3 tints each of those a different shade by elevation, which
    // reads as a patchwork of near-but-not-quite backgrounds. Separation here
    // comes from the outline and the modal scrim instead, so `surfaceTintColor`
    // is switched off everywhere rather than left to blend elevation back in.
    final surface = scheme.surface;
    final outline = BorderSide(color: scheme.outlineVariant);

    InputBorder field(Color color) => OutlineInputBorder(
      borderRadius: AppRadius.allMd,
      borderSide: BorderSide(color: color),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: surface,
      canvasColor: surface,
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.allLg,
          side: outline,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        modalBackgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        modalElevation: 0,
      ),
      cardTheme: CardThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.allLg,
          side: outline,
        ),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(surface),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
      ),
      // Hover and press feedback follows the shape of the thing being touched:
      // Material paints a rectangle unless the surface says otherwise, which
      // is where every square highlight in the app came from.
      listTileTheme: const ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: AppRadius.allMd),
      ),
      menuButtonTheme: const MenuButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: AppRadius.allSm),
          ),
        ),
      ),
      tabBarTheme: const TabBarThemeData(splashBorderRadius: AppRadius.allMd),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        border: field(scheme.outlineVariant),
        enabledBorder: field(scheme.outlineVariant),
        focusedBorder: field(scheme.primary),
        errorBorder: field(scheme.error),
        focusedErrorBorder: field(scheme.error),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: 56,
        shape: Border(bottom: outline),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.secondaryContainer,
        elevation: 0,
        height: 64,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 24,
            color: states.contains(WidgetState.selected)
                ? scheme.onSecondaryContainer
                : scheme.onSurfaceVariant,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? scheme.onSurface
                : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
