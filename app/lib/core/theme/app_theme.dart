import 'package:flutter/material.dart';
import 'package:revoked_app/core/design/app_colors.dart';
import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/design/text_styles.dart';

/// Builds the app's Material 3 theme for a given [Brightness], so light and dark
/// share one definition (only the [ColorScheme] flips).
class AppTheme {
  AppTheme._();

  /// The two schemes, spelled out role by role from [AppPalette]. A seeded
  /// scheme picks its own tones, and those were never checked for contrast;
  /// these are, by `test/contrast_test.dart`.
  static ColorScheme scheme(Brightness brightness) {
    return brightness == Brightness.light ? _light : _dark;
  }

  static const _light = ColorScheme(
    brightness: Brightness.light,
    primary: AppPalette.lightInk,
    onPrimary: AppPalette.lightWhite,
    primaryContainer: AppPalette.lightCardHighest,
    onPrimaryContainer: AppPalette.lightInk,
    secondary: AppPalette.lightSecondaryText,
    onSecondary: AppPalette.lightWhite,
    secondaryContainer: AppPalette.lightCard,
    onSecondaryContainer: AppPalette.lightInk,
    tertiary: AppPalette.lightAccent,
    onTertiary: AppPalette.lightWhite,
    tertiaryContainer: AppPalette.lightCard,
    onTertiaryContainer: AppPalette.lightAccent,
    error: AppPalette.lightDanger,
    onError: AppPalette.lightWhite,
    errorContainer: AppPalette.lightDangerContainer,
    onErrorContainer: AppPalette.lightDanger,
    surface: AppPalette.lightPaper,
    onSurface: AppPalette.lightInk,
    onSurfaceVariant: AppPalette.lightSecondaryText,
    surfaceContainerLowest: AppPalette.lightWhite,
    surfaceContainerLow: AppPalette.lightPaper,
    surfaceContainer: AppPalette.lightCard,
    surfaceContainerHigh: AppPalette.lightCardHigh,
    surfaceContainerHighest: AppPalette.lightCardHighest,
    outline: AppPalette.lightControlBorder,
    outlineVariant: AppPalette.lightDivider,
    shadow: Colors.black,
    scrim: Colors.black,
    inverseSurface: AppPalette.lightInk,
    onInverseSurface: AppPalette.lightPaper,
    inversePrimary: AppPalette.darkAccent,
    surfaceTint: Colors.transparent,
  );

  static const _dark = ColorScheme(
    brightness: Brightness.dark,
    primary: AppPalette.darkInk,
    onPrimary: AppPalette.darkOnInk,
    primaryContainer: AppPalette.darkCardHighest,
    onPrimaryContainer: AppPalette.darkInk,
    secondary: AppPalette.darkSecondaryText,
    onSecondary: AppPalette.darkOnInk,
    secondaryContainer: AppPalette.darkCard,
    onSecondaryContainer: AppPalette.darkInk,
    tertiary: AppPalette.darkAccent,
    onTertiary: AppPalette.darkOnInk,
    tertiaryContainer: AppPalette.darkCard,
    onTertiaryContainer: AppPalette.darkAccent,
    error: AppPalette.darkDanger,
    onError: AppPalette.darkOnInk,
    errorContainer: AppPalette.darkDangerContainer,
    onErrorContainer: AppPalette.darkDanger,
    surface: AppPalette.darkSurface,
    onSurface: AppPalette.darkInk,
    onSurfaceVariant: AppPalette.darkSecondaryText,
    surfaceContainerLowest: AppPalette.darkPage,
    surfaceContainerLow: AppPalette.darkSurface,
    surfaceContainer: AppPalette.darkCard,
    surfaceContainerHigh: AppPalette.darkCardHigh,
    surfaceContainerHighest: AppPalette.darkCardHighest,
    outline: AppPalette.darkControlBorder,
    outlineVariant: AppPalette.darkDivider,
    shadow: Colors.black,
    scrim: Colors.black,
    inverseSurface: AppPalette.darkInk,
    onInverseSurface: AppPalette.darkOnInk,
    inversePrimary: AppPalette.lightAccent,
    surfaceTint: Colors.transparent,
  );

  static ThemeData build(Brightness brightness) {
    final scheme = AppTheme.scheme(brightness);

    // One background for every surface — page, card, sheet, dialog, menu, bar.
    // Material 3 tints each of those a different shade by elevation, which
    // reads as a patchwork of near-but-not-quite backgrounds. Separation here
    // comes from the outline and the modal scrim instead, so `surfaceTintColor`
    // is switched off everywhere rather than left to blend elevation back in.
    final surface = scheme.surface;
    final outline = BorderSide(color: scheme.outlineVariant);

    InputBorder field(Color color, {double width = 1}) => OutlineInputBorder(
      borderRadius: AppRadius.allMd,
      borderSide: BorderSide(color: color, width: width),
    );

    // Body 16 and small 13: the sizes of `AppText`, so a plain `Text` and a
    // Material widget's own labels read at the same sizes as the rest.
    final base = ThemeData(brightness: brightness).textTheme;
    final textTheme = base.copyWith(
      bodyLarge: base.bodyLarge?.copyWith(fontSize: AppTextSize.body),
      bodyMedium: base.bodyMedium?.copyWith(
        fontSize: AppTextSize.body,
        height: AppTextSize.bodyHeight,
      ),
      bodySmall: base.bodySmall?.copyWith(fontSize: AppTextSize.small),
      labelLarge: base.labelLarge?.copyWith(
        fontSize: AppTextSize.body,
        fontWeight: FontWeight.w600,
      ),
      labelMedium: base.labelMedium?.copyWith(fontSize: AppTextSize.small),
      titleMedium: base.titleMedium?.copyWith(fontSize: AppTextSize.body),
      titleLarge: base.titleLarge?.copyWith(fontSize: AppTextSize.header),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      textTheme: textTheme,
      scaffoldBackgroundColor: surface,
      canvasColor: surface,
      // Every control is at least 48 logical pixels to touch, on desktop too:
      // the desktop default packs them tighter than a shaky hand can hit.
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
      // Keyboard focus fills the focused row faintly; the ring around it comes
      // from `AppFocusRing` and the button style.
      focusColor: scheme.accent.withValues(alpha: 0.12),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.allLg,
          side: outline,
        ),
      ),
      // The date and time pickers are dialogs too, and Material gives them a
      // shape of their own unless told otherwise.
      datePickerTheme: DatePickerThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.allLg,
          side: outline,
        ),
      ),
      timePickerTheme: TimePickerThemeData(
        backgroundColor: surface,
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
          side: WidgetStatePropertyAll(outline),
          elevation: const WidgetStatePropertyAll(2),
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
          minimumSize: WidgetStatePropertyAll(Size(0, 48)),
        ),
      ),
      tabBarTheme: const TabBarThemeData(splashBorderRadius: AppRadius.allMd),
      // A field's edge is what says "type here", so it meets 3:1 against the
      // page (the control border, not the divider). Focus thickens it in the
      // accent.
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        hintStyle: TextStyle(color: scheme.onSurfaceVariant),
        border: field(scheme.outline),
        enabledBorder: field(scheme.outline),
        focusedBorder: field(scheme.accent, width: 2),
        errorBorder: field(scheme.error),
        focusedErrorBorder: field(scheme.error, width: 2),
      ),
      // The one New button: ink, flat, like the primary buttons.
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.allLg),
        extendedTextStyle: textTheme.labelLarge,
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
      // The current destination is an ink pill behind a light icon: a state
      // marker strong enough to meet 3:1 against the bar, not a faint tint.
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primary,
        elevation: 0,
        height: 68,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 24,
            color: states.contains(WidgetState.selected)
                ? scheme.onPrimary
                : scheme.onSurfaceVariant,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: AppTextSize.small,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? scheme.onSurface
                : scheme.onSurfaceVariant,
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: surface,
        indicatorColor: scheme.primary,
        selectedIconTheme: IconThemeData(size: 24, color: scheme.onPrimary),
        unselectedIconTheme: IconThemeData(
          size: 24,
          color: scheme.onSurfaceVariant,
        ),
        selectedLabelTextStyle: TextStyle(
          fontSize: AppTextSize.small,
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
        ),
        unselectedLabelTextStyle: TextStyle(
          fontSize: AppTextSize.small,
          fontWeight: FontWeight.w500,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
