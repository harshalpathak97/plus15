import 'package:flutter/material.dart';

/// Central brand + semantic color tokens for Plus15 Navigator.
///
/// Everything visual in the app should reference these tokens instead of
/// hard-coding hex values, so the look stays cohesive and is themeable from a
/// single place. The identity is deliberately restrained: warm graphite
/// neutrals, the +15 network drawn as a quiet steel substrate (like the City's
/// own map), and one signature teal reserved for *your* route and selection.
class AppPalette {
  AppPalette._();

  // --- Brand -------------------------------------------------------------
  /// Signature +15 teal: the active route, selection and accents.
  static const Color brand = Color(0xFF0B7C74);
  static const Color brandDeep = Color(0xFF07716A);
  /// Brighter teal for dark surfaces and the route on the dark map.
  static const Color brandSoft = Color(0xFF3FD0C1);

  /// The +15 network itself: a neutral steel substrate so the route is the
  /// only saturated line on the map.
  static const Color skywalk = Color(0xFF6F7E8B);
  static const Color skywalkBright = Color(0xFFA3AFB9);

  // --- Semantic ----------------------------------------------------------
  static const Color origin = Color(0xFF1F9D55);
  static const Color destination = Color(0xFFE8553D);
  static const Color warning = Color(0xFFE09A00);
  static const Color danger = Color(0xFFD92D20);
  static const Color transit = Color(0xFF1F9D55);

  // --- Neutrals (light) --------------------------------------------------
  static const Color ink = Color(0xFF121417);
  static const Color inkMuted = Color(0xFF6B7079);
  static const Color surfaceLight = Color(0xFFF4F4F1);
  static const Color cardLight = Color(0xFFFFFFFF);
  static const Color borderLight = Color(0xFFE6E5E0);

  // --- Neutrals (dark) ---------------------------------------------------
  static const Color inkDark = Color(0xFFF1F2EE);
  static const Color inkMutedDark = Color(0xFF959AA2);
  static const Color surfaceDark = Color(0xFF0B0C0E);
  static const Color cardDark = Color(0xFF15171A);
  static const Color borderDark = Color(0xFF26292E);

  // --- Building / place type accents ------------------------------------
  static Color typeColor(String type) {
    switch (type) {
      case 'hotel':
        return const Color(0xFFC28A1E);
      case 'retail':
        return const Color(0xFF2E7FD1);
      case 'landmark':
        return destination;
      case 'entertainment':
        return const Color(0xFFD9682B);
      case 'government':
        return const Color(0xFF3C8DA3);
      case 'convention':
        return const Color(0xFF1F9D55);
      case 'transit':
        return transit;
      case 'parking':
        return inkMuted;
      case 'residential':
        return const Color(0xFF8A7B6A);
      default:
        return brand;
    }
  }

  static Color amenityColor(String amenity) {
    switch (amenity) {
      case 'food':
        return const Color(0xFFD9682B);
      case 'shopping':
      case 'retail':
        return const Color(0xFF2E7FD1);
      case 'transit':
        return transit;
      case 'washroom':
        return const Color(0xFF3C8DA3);
      case 'hotel':
        return const Color(0xFFC28A1E);
      case 'health':
        return const Color(0xFFC2414F);
      case 'entertainment':
        return const Color(0xFFD9682B);
      default:
        return inkMuted;
    }
  }

  /// Color for a shop category. Keyed by [ShopCategory.name] so this stays
  /// decoupled from the data layer. Shared by Search and the shop detail sheet.
  static Color categoryColor(String category) {
    switch (category) {
      case 'food':
        return const Color(0xFFD9682B);
      case 'retail':
        return const Color(0xFF2E7FD1);
      case 'services':
        return brand;
      case 'transit':
        return transit;
      case 'washroom':
        return const Color(0xFF3C8DA3);
      case 'hotel':
        return const Color(0xFFC28A1E);
      case 'health':
        return const Color(0xFFC2414F);
      case 'entertainment':
        return const Color(0xFFD9682B);
      default:
        return brand;
    }
  }
}
