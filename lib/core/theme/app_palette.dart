import 'package:flutter/material.dart';

/// Central brand + semantic color tokens for Plus15 Navigator.
///
/// Everything visual in the app should reference these tokens instead of
/// hard-coding hex values, so the look stays cohesive and is themeable from a
/// single place.
///
/// The identity is "warm minimal": soft, warm paper-like neutrals (never cold
/// blue-grey) paired with a single confident deep-emerald accent that
/// represents the +15 skywalk network. No neon, no glow, no AI-default
/// indigo/cyan — calm, premium, and highly legible like a fine transit map.
class AppPalette {
  AppPalette._();

  // --- Brand (deep emerald) ---------------------------------------------
  /// Primary brand color. Used for the app seed, primary actions, the active
  /// route line and selected states.
  static const Color brand = Color(0xFF1F7A5C);
  static const Color brandDeep = Color(0xFF155C45);
  static const Color brandSoft = Color(0xFF5FA98C);

  /// The +15 skywalk network — drawn in the brand emerald. [skywalkBright] is
  /// a touch lighter for legibility against the dark map.
  static const Color skywalk = Color(0xFF1F7A5C);
  static const Color skywalkBright = Color(0xFF4FB892);

  // --- Semantic (warm-tuned) --------------------------------------------
  static const Color origin = Color(0xFF1F8A5B);
  static const Color destination = Color(0xFFD96A4A);
  static const Color warning = Color(0xFFD9943B);
  static const Color danger = Color(0xFFC9503C);
  static const Color transit = Color(0xFF3F8F6F);

  // --- Neutrals (light — warm paper) ------------------------------------
  static const Color ink = Color(0xFF22201C);
  static const Color inkMuted = Color(0xFF7C746A);
  static const Color surfaceLight = Color(0xFFF7F4EF);
  static const Color cardLight = Color(0xFFFFFDFA);
  static const Color borderLight = Color(0xFFE9E3D9);

  // --- Neutrals (dark — warm charcoal) ----------------------------------
  static const Color inkDark = Color(0xFFF3EFE8);
  static const Color inkMutedDark = Color(0xFFAAA194);
  static const Color surfaceDark = Color(0xFF1A1815);
  static const Color cardDark = Color(0xFF252220);
  static const Color borderDark = Color(0xFF36322C);

  // --- Building / place type accents (muted, warm) ----------------------
  static Color typeColor(String type) {
    switch (type) {
      case 'hotel':
        return const Color(0xFFD9943B);
      case 'retail':
        return const Color(0xFF9A7BC0);
      case 'landmark':
        return const Color(0xFFD96A4A);
      case 'entertainment':
        return const Color(0xFFD98843);
      case 'government':
        return const Color(0xFF4F8DA6);
      case 'convention':
        return const Color(0xFF1F8A5B);
      case 'park':
        return const Color(0xFF5C9A52);
      case 'residential':
        return const Color(0xFF7E8B9C);
      default:
        return brand;
    }
  }

  static Color amenityColor(String amenity) {
    switch (amenity) {
      case 'food':
        return const Color(0xFFD96A4A);
      case 'retail':
        return const Color(0xFF9A7BC0);
      case 'transit':
        return const Color(0xFF3F8F6F);
      case 'washroom':
        return const Color(0xFF4F8DA6);
      case 'hotel':
        return const Color(0xFFD9943B);
      case 'health':
        return const Color(0xFFC76B9C);
      case 'entertainment':
        return const Color(0xFFD98843);
      default:
        return inkMuted;
    }
  }

  /// Color for a shop category. Keyed by [ShopCategory.name] so this stays
  /// decoupled from the data layer. Shared by Search and the shop detail sheet.
  static Color categoryColor(String category) {
    switch (category) {
      case 'food':
        return destination;
      case 'retail':
        return const Color(0xFF9A7BC0);
      case 'services':
        return brand;
      case 'transit':
        return transit;
      case 'washroom':
        return const Color(0xFF4F8DA6);
      case 'hotel':
        return warning;
      case 'health':
        return const Color(0xFFC76B9C);
      case 'entertainment':
        return const Color(0xFFD98843);
      default:
        return brand;
    }
  }

  /// The signature brand gradient. Kept very subtle (two close emerald tones)
  /// so surfaces read as a calm solid, not a loud AI gradient.
  static const LinearGradient brandGradient = LinearGradient(
    colors: [brand, brandDeep],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
