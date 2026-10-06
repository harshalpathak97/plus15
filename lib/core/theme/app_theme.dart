import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'app_palette.dart';
import 'app_spacing.dart';

/// The app's single Material theme, built once per brightness.
///
/// Type is Apple's San Francisco everywhere it may be used: the system SF Pro
/// (Text and Display) on iPhone, iPad and Mac. SF Pro's licence only covers
/// Apple platforms, so Android and the web use the bundled Inter, the closest
/// open equivalent, set with SF-style tracking. Bundled fonts render the same
/// offline and on first launch. Every text style the app uses is defined here with an
/// explicit line height; widgets should take styles from `textTheme` and
/// colours from `colorScheme` rather than hard-coding them.
class AppTheme {
  AppTheme._();

  static final bool _apple = !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);
  /// SF Pro Display (≥ 20 pt) and SF Pro Text on Apple platforms, else Inter.
  static final display = _apple ? 'CupertinoSystemDisplay' : 'Inter';
  static final body = _apple ? 'CupertinoSystemText' : 'Inter';
  static const _fallback = ['Inter'];

  static final light = _build(Brightness.light);
  static final dark = _build(Brightness.dark);

  /// Digits that don't jump as distances and times update.
  static const tabular = [FontFeature.tabularFigures()];

  static ThemeData _build(Brightness b) {
    final isLight = b == Brightness.light;
    final ink = isLight ? AppPalette.ink : AppPalette.inkDark;
    final muted = isLight ? AppPalette.inkMuted : AppPalette.inkMutedDark;
    final border = isLight ? AppPalette.borderLight : AppPalette.borderDark;
    final card = isLight ? AppPalette.cardLight : AppPalette.cardDark;
    final surface = isLight ? AppPalette.surfaceLight : AppPalette.surfaceDark;
    final primary = isLight ? AppPalette.brand : AppPalette.brandSoft;
    final onPrimary = isLight ? Colors.white : AppPalette.surfaceDark;

    final scheme = ColorScheme.fromSeed(seedColor: AppPalette.brand, brightness: b).copyWith(
      primary: primary,
      onPrimary: onPrimary,
      primaryContainer: isLight ? const Color(0xFFDDF1EE) : const Color(0xFF0F2E2B),
      onPrimaryContainer: isLight ? AppPalette.brandDeep : AppPalette.brandSoft,
      secondary: ink,
      onSecondary: card,
      secondaryContainer: isLight ? const Color(0xFFEDEDE9) : const Color(0xFF23262B),
      onSecondaryContainer: ink,
      tertiary: isLight ? AppPalette.brandDeep : AppPalette.brandSoft,
      error: AppPalette.danger,
      surface: card,
      onSurface: ink,
      onSurfaceVariant: muted,
      surfaceTint: Colors.transparent,
      surfaceContainerLowest: isLight ? Colors.white : const Color(0xFF08090B),
      surfaceContainerLow: isLight ? const Color(0xFFF9F9F7) : const Color(0xFF111316),
      surfaceContainer: isLight ? const Color(0xFFF2F2EF) : const Color(0xFF181A1E),
      surfaceContainerHigh: isLight ? const Color(0xFFECECE8) : const Color(0xFF1E2125),
      surfaceContainerHighest: isLight ? const Color(0xFFE5E5E0) : const Color(0xFF25282D),
      outline: isLight ? const Color(0xFFBDBCB5) : const Color(0xFF474B52),
      outlineVariant: border,
      inverseSurface: isLight ? const Color(0xFF1C1E21) : const Color(0xFFEDEEEA),
      onInverseSurface: isLight ? Colors.white : AppPalette.ink,
      inversePrimary: isLight ? AppPalette.brandSoft : AppPalette.brand,
    );
    final text = _textTheme(ink, muted);
    const controlShape = RoundedRectangleBorder(borderRadius: AppRadii.rControl);
    final buttonText = text.labelLarge!.copyWith(fontSize: 15);

    return ThemeData(
      useMaterial3: true,
      brightness: b,
      colorScheme: scheme,
      fontFamily: body,
      fontFamilyFallback: _fallback,
      textTheme: text,
      scaffoldBackgroundColor: surface,
      canvasColor: surface,
      dividerColor: border,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),
      iconTheme: IconThemeData(color: ink, size: 22),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: primary,
        linearTrackColor: scheme.surfaceContainerHigh,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: primary,
        selectionColor: primary.withValues(alpha: 0.25),
        selectionHandleColor: primary,
      ),
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        backgroundColor: surface,
        foregroundColor: ink,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: text.titleLarge,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.rCard,
          side: BorderSide(color: border),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: onPrimary,
          disabledBackgroundColor: scheme.surfaceContainerHigh,
          disabledForegroundColor: muted,
          minimumSize: const Size(64, AppDims.buttonHeight),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          shape: controlShape,
          textStyle: buttonText,
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          minimumSize: const Size(64, AppDims.buttonHeight),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          shape: controlShape,
          side: BorderSide(color: scheme.outline),
          textStyle: buttonText,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: isLight ? AppPalette.brandDeep : AppPalette.brandSoft,
          minimumSize: const Size(48, 44),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          shape: controlShape,
          textStyle: buttonText,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: card,
          foregroundColor: ink,
          minimumSize: const Size(64, AppDims.buttonHeight),
          shape: controlShape,
          textStyle: buttonText,
          elevation: 0,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: ink,
          minimumSize: const Size(44, 44),
          shape: controlShape,
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          foregroundColor: ink,
          selectedForegroundColor: scheme.onPrimaryContainer,
          selectedBackgroundColor: scheme.primaryContainer,
          side: BorderSide(color: border),
          minimumSize: const Size(0, 44),
          textStyle: text.labelLarge,
          shape: controlShape,
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? onPrimary : scheme.outline),
        trackColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? primary : scheme.surfaceContainerHighest),
        trackOutlineColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? Colors.transparent : scheme.outline),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: muted,
        titleTextStyle: text.titleMedium,
        subtitleTextStyle: text.bodyMedium!.copyWith(color: muted),
        minVerticalPadding: 12,
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        shape: controlShape,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: card,
        selectedColor: scheme.primaryContainer,
        labelStyle: text.labelLarge,
        side: BorderSide(color: border),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        shape: const RoundedRectangleBorder(borderRadius: AppRadii.rChip),
        showCheckmark: false,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: card,
        hintStyle: text.bodyLarge!.copyWith(color: muted),
        border: OutlineInputBorder(
          borderRadius: AppRadii.rControl,
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadii.rControl,
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadii.rControl,
          borderSide: BorderSide(color: primary, width: 1.6),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: AppDims.navBarHeight,
        elevation: 0,
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primaryContainer,
        indicatorShape: const StadiumBorder(),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
            size: 24,
            color: s.contains(WidgetState.selected) ? scheme.onPrimaryContainer : muted)),
        labelTextStyle: WidgetStateProperty.resolveWith((s) => text.labelMedium!.copyWith(
            color: s.contains(WidgetState.selected) ? ink : muted,
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        showDragHandle: true,
        backgroundColor: surface,
        modalBackgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        dragHandleColor: scheme.outline,
        dragHandleSize: const Size(36, 4),
        shape: const RoundedRectangleBorder(borderRadius: AppRadii.rSheetTop),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(24))),
        titleTextStyle: text.headlineSmall,
        contentTextStyle: text.bodyMedium,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: text.bodyMedium!.copyWith(color: scheme.onInverseSurface),
        actionTextColor: scheme.inversePrimary,
        shape: const RoundedRectangleBorder(borderRadius: AppRadii.rControl),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: scheme.inverseSurface,
          borderRadius: const BorderRadius.all(Radius.circular(8)),
        ),
        textStyle: text.labelMedium!.copyWith(color: scheme.onInverseSurface),
      ),
    );
  }

  /// Tracking for SF Pro (Apple's published values) or for Inter.
  static double t(double sf, double inter) => _apple ? sf : inter;

  static TextTheme _textTheme(Color ink, Color muted) {
    TextStyle s(String family, double size, FontWeight w, double height,
            {double tracking = 0, Color? color}) =>
        TextStyle(
          fontFamily: family,
          fontFamilyFallback: _fallback,
          fontSize: size,
          fontWeight: w,
          height: height,
          letterSpacing: tracking,
          color: color ?? ink,
        );
    return TextTheme(
      // Apple's type ramp (Large Title 34, Title 1 28, Title 2 22, Title 3 20,
      // Headline 17, Body 17/15, Footnote 13, Caption 12/11). Inter runs a
      // little wide, so it gets SF's tighter tracking at large sizes.
      displayLarge: s(display, 34, FontWeight.w700, 1.18, tracking: t(0.4, -0.9)),
      displayMedium: s(display, 28, FontWeight.w700, 1.2, tracking: t(0.38, -0.6)),
      displaySmall: s(display, 24, FontWeight.w700, 1.25, tracking: t(0.35, -0.4)),
      headlineLarge: s(display, 24, FontWeight.w700, 1.25, tracking: t(0.35, -0.4)),
      headlineMedium: s(display, 22, FontWeight.w700, 1.27, tracking: t(0.35, -0.35)),
      headlineSmall: s(display, 20, FontWeight.w600, 1.3, tracking: t(0.38, -0.3)),
      titleLarge: s(body, 18, FontWeight.w600, 1.3, tracking: t(-0.43, -0.25)),
      titleMedium: s(body, 16, FontWeight.w600, 1.35, tracking: t(-0.32, -0.15)),
      titleSmall: s(body, 14, FontWeight.w600, 1.4, tracking: t(-0.15, -0.1)),
      bodyLarge: s(body, 16, FontWeight.w400, 1.47, tracking: t(-0.32, -0.15)),
      bodyMedium: s(body, 14, FontWeight.w400, 1.43, tracking: t(-0.15, -0.1)),
      bodySmall: s(body, 13, FontWeight.w400, 1.38, tracking: t(-0.08, -0.05), color: muted),
      labelLarge: s(body, 14, FontWeight.w600, 1.3, tracking: t(-0.15, -0.1)),
      labelMedium: s(body, 12, FontWeight.w500, 1.3, tracking: t(0, 0)),
      labelSmall: s(body, 11, FontWeight.w500, 1.3, tracking: t(0.07, 0.1), color: muted),
    );
  }
}
