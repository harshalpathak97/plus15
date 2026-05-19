import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../design/palette.dart';

class AppTheme {
  AppTheme._();

  static const _seedColor = P15Palette.electricBlue;

  static ThemeData light({ColorScheme? dynamicScheme}) {
    final scheme = _resolveScheme(
      brightness: Brightness.light,
      dynamicScheme: dynamicScheme,
    );
    return _build(scheme, Brightness.light);
  }

  static ThemeData dark({ColorScheme? dynamicScheme}) {
    final scheme = _resolveScheme(
      brightness: Brightness.dark,
      dynamicScheme: dynamicScheme,
    );
    return _build(scheme, Brightness.dark);
  }

  /// Blend a device Material You scheme with the brand seed scheme so the
  /// app keeps its identity but adapts to the user's wallpaper colors.
  static ColorScheme _resolveScheme({
    required Brightness brightness,
    ColorScheme? dynamicScheme,
  }) {
    final brand = ColorScheme.fromSeed(
      seedColor: _seedColor,
      brightness: brightness,
    );
    if (dynamicScheme == null) return brand;
    final harmonized = dynamicScheme.harmonized();
    return ColorScheme(
      brightness: brightness,
      primary: Color.lerp(brand.primary, harmonized.primary, 0.3)!,
      onPrimary: brand.onPrimary,
      primaryContainer:
          Color.lerp(brand.primaryContainer, harmonized.primaryContainer, 0.3)!,
      onPrimaryContainer: brand.onPrimaryContainer,
      secondary: Color.lerp(brand.secondary, harmonized.secondary, 0.4)!,
      onSecondary: brand.onSecondary,
      secondaryContainer: Color.lerp(
          brand.secondaryContainer, harmonized.secondaryContainer, 0.4)!,
      onSecondaryContainer: brand.onSecondaryContainer,
      tertiary: Color.lerp(brand.tertiary, harmonized.tertiary, 0.5)!,
      onTertiary: brand.onTertiary,
      tertiaryContainer: Color.lerp(
          brand.tertiaryContainer, harmonized.tertiaryContainer, 0.5)!,
      onTertiaryContainer: brand.onTertiaryContainer,
      error: brand.error,
      onError: brand.onError,
      errorContainer: brand.errorContainer,
      onErrorContainer: brand.onErrorContainer,
      surface: brand.surface,
      onSurface: brand.onSurface,
      surfaceContainerHighest: brand.surfaceContainerHighest,
      onSurfaceVariant: brand.onSurfaceVariant,
      outline: brand.outline,
      outlineVariant: brand.outlineVariant,
      inverseSurface: brand.inverseSurface,
      onInverseSurface: brand.onInverseSurface,
      inversePrimary: brand.inversePrimary,
      shadow: brand.shadow,
      scrim: brand.scrim,
      surfaceTint: brand.surfaceTint,
    );
  }

  static ThemeData _build(ColorScheme scheme, Brightness brightness) {
    final isLight = brightness == Brightness.light;
    final scaffoldBg =
        isLight ? P15Palette.surface0 : P15Palette.surfaceDark0;
    final cardBg = isLight ? P15Palette.surface1 : P15Palette.surfaceDark1;
    final border = isLight ? P15Palette.borderLight : P15Palette.borderDark;
    final inputFill =
        isLight ? P15Palette.surfaceMuted : P15Palette.surfaceDarkMuted;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffoldBg,
      textTheme: _textTheme(brightness),
      cardTheme: CardTheme(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: border),
        ),
        color: cardBg,
      ),
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        backgroundColor: scaffoldBg,
        titleTextStyle: GoogleFonts.plusJakartaSans(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: isLight ? P15Palette.onSurface : P15Palette.onSurfaceDark,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        height: 72,
        backgroundColor: cardBg.withValues(alpha: 0.92),
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        labelTextStyle: WidgetStateProperty.all(
          GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: inputFill,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        side: BorderSide(color: border),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        ),
      ),
    );
  }

  static TextTheme _textTheme(Brightness brightness) {
    final color = brightness == Brightness.light
        ? P15Palette.onSurface
        : P15Palette.onSurfaceDark;

    return TextTheme(
      displayLarge: GoogleFonts.plusJakartaSans(
          fontSize: 32, fontWeight: FontWeight.w800, color: color),
      displayMedium: GoogleFonts.plusJakartaSans(
          fontSize: 28, fontWeight: FontWeight.w700, color: color),
      headlineLarge: GoogleFonts.plusJakartaSans(
          fontSize: 24, fontWeight: FontWeight.w700, color: color),
      headlineMedium: GoogleFonts.plusJakartaSans(
          fontSize: 20, fontWeight: FontWeight.w600, color: color),
      titleLarge: GoogleFonts.plusJakartaSans(
          fontSize: 18, fontWeight: FontWeight.w600, color: color),
      titleMedium: GoogleFonts.inter(
          fontSize: 16, fontWeight: FontWeight.w500, color: color),
      titleSmall: GoogleFonts.inter(
          fontSize: 14, fontWeight: FontWeight.w500, color: color),
      bodyLarge: GoogleFonts.inter(
          fontSize: 16, fontWeight: FontWeight.w400, color: color),
      bodyMedium: GoogleFonts.inter(
          fontSize: 14, fontWeight: FontWeight.w400, color: color),
      bodySmall: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: color.withValues(alpha: 0.7)),
      labelLarge: GoogleFonts.inter(
          fontSize: 14, fontWeight: FontWeight.w600, color: color),
      labelSmall: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: color.withValues(alpha: 0.6)),
    );
  }
}
