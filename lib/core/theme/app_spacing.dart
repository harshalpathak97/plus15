import 'package:flutter/material.dart';

/// Central spacing, radius and component-size tokens.
///
/// Mirrors [AppPalette]'s style (private ctor, static consts) so the layout
/// language stays consistent and tweakable from one place. New code should
/// reference these instead of sprinkling magic numbers.
class AppSpacing {
  AppSpacing._();

  // --- Spacing scale -----------------------------------------------------
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;

  /// Standard screen edge padding for the scrollable tabs.
  static const EdgeInsets screenPadding = EdgeInsets.fromLTRB(lg, lg, lg, 0);

  /// Bottom padding for scrollable lists so content clears the floating nav
  /// bar. Replaces the scattered hard-coded `108`.
  static const double bottomScrollClearance = 108;
}

/// Corner radius tokens.
class AppRadii {
  AppRadii._();

  static const double chip = 12;
  static const double control = 14;
  static const double card = 18;
  static const double cardLg = 20;
  static const double sheet = 28;
  static const double brandMark = 16;

  static const BorderRadius rChip = BorderRadius.all(Radius.circular(chip));
  static const BorderRadius rControl =
      BorderRadius.all(Radius.circular(control));
  static const BorderRadius rCard = BorderRadius.all(Radius.circular(card));
  static const BorderRadius rSheetTop =
      BorderRadius.vertical(top: Radius.circular(sheet));
}

/// Shared component dimensions and the bottom-sheet snap fractions.
class AppDims {
  AppDims._();

  /// Floating glass nav bar pill height (matches [AppTheme] navigation theme).
  static const double navBarHeight = 66;

  /// Square map control button (zoom / locate / recenter).
  static const double mapControlSize = 46;

  // Map bottom-sheet snap fractions.
  static const double sheetMin = 0.13;
  static const double sheetIdle = 0.26;
  static const double sheetMid = 0.45;
  static const double sheetMax = 0.82;
}

/// Common animation timings and curves used across the app.
class AppMotion {
  AppMotion._();

  static const Duration fast = Duration(milliseconds: 220);
  static const Duration normal = Duration(milliseconds: 300);
  static const Duration slow = Duration(milliseconds: 400);
  static const Curve curve = Curves.easeOutCubic;
}
