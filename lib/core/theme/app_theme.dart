import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_palette.dart';

class AppTheme {
  static const _seedColor = AppPalette.brand;

  static final light = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: ColorScheme.fromSeed(
      seedColor: _seedColor,
      brightness: Brightness.light,
    ).copyWith(
      primary: AppPalette.brand,
      secondary: AppPalette.skywalk,
      surface: AppPalette.cardLight,
    ),
    scaffoldBackgroundColor: AppPalette.surfaceLight,
    textTheme: _textTheme(Brightness.light),
    dividerColor: AppPalette.borderLight,
    cardTheme: CardTheme(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppPalette.borderLight),
      ),
      color: AppPalette.cardLight,
      surfaceTintColor: Colors.transparent,
    ),
    appBarTheme: AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      backgroundColor: AppPalette.surfaceLight,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: GoogleFonts.plusJakartaSans(
        fontSize: 20,
        fontWeight: FontWeight.w800,
        color: AppPalette.ink,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      elevation: 0,
      height: 72,
      backgroundColor: Colors.transparent,
      indicatorShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      labelTextStyle: WidgetStateProperty.all(
        GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppPalette.borderLight),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppPalette.borderLight),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppPalette.brand, width: 1.6),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      side: const BorderSide(color: AppPalette.borderLight),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppPalette.brand,
        foregroundColor: Colors.white,
        elevation: 0,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle:
            GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      showDragHandle: true,
      backgroundColor: AppPalette.surfaceLight,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
  );

  static final dark = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: _seedColor,
      brightness: Brightness.dark,
    ).copyWith(
      primary: AppPalette.brandSoft,
      secondary: AppPalette.skywalkBright,
      surface: AppPalette.cardDark,
    ),
    scaffoldBackgroundColor: AppPalette.surfaceDark,
    textTheme: _textTheme(Brightness.dark),
    dividerColor: AppPalette.borderDark,
    cardTheme: CardTheme(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppPalette.borderDark),
      ),
      color: AppPalette.cardDark,
      surfaceTintColor: Colors.transparent,
    ),
    appBarTheme: AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      backgroundColor: AppPalette.surfaceDark,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: GoogleFonts.plusJakartaSans(
        fontSize: 20,
        fontWeight: FontWeight.w800,
        color: AppPalette.inkDark,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      elevation: 0,
      height: 72,
      backgroundColor: Colors.transparent,
      indicatorShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      labelTextStyle: WidgetStateProperty.all(
        GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppPalette.cardDark,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppPalette.borderDark),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppPalette.borderDark),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppPalette.brandSoft, width: 1.6),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      side: const BorderSide(color: AppPalette.borderDark),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppPalette.brand,
        foregroundColor: Colors.white,
        elevation: 0,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle:
            GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      showDragHandle: true,
      backgroundColor: AppPalette.surfaceDark,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
  );

  static TextTheme _textTheme(Brightness brightness) {
    final color =
        brightness == Brightness.light ? AppPalette.ink : AppPalette.inkDark;
    final muted = brightness == Brightness.light
        ? AppPalette.inkMuted
        : AppPalette.inkMutedDark;

    return TextTheme(
      displayLarge: GoogleFonts.plusJakartaSans(
          fontSize: 34, fontWeight: FontWeight.w800, color: color, letterSpacing: -0.5),
      displayMedium: GoogleFonts.plusJakartaSans(
          fontSize: 28, fontWeight: FontWeight.w800, color: color, letterSpacing: -0.4),
      headlineLarge: GoogleFonts.plusJakartaSans(
          fontSize: 24, fontWeight: FontWeight.w700, color: color),
      headlineMedium: GoogleFonts.plusJakartaSans(
          fontSize: 20, fontWeight: FontWeight.w700, color: color),
      titleLarge: GoogleFonts.plusJakartaSans(
          fontSize: 18, fontWeight: FontWeight.w700, color: color),
      titleMedium: GoogleFonts.inter(
          fontSize: 16, fontWeight: FontWeight.w600, color: color),
      titleSmall: GoogleFonts.inter(
          fontSize: 14, fontWeight: FontWeight.w600, color: color),
      bodyLarge: GoogleFonts.inter(
          fontSize: 16, fontWeight: FontWeight.w400, color: color),
      bodyMedium: GoogleFonts.inter(
          fontSize: 14, fontWeight: FontWeight.w400, color: color),
      bodySmall:
          GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w400, color: muted),
      labelLarge: GoogleFonts.inter(
          fontSize: 14, fontWeight: FontWeight.w600, color: color),
      labelSmall:
          GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w500, color: muted),
    );
  }
}
