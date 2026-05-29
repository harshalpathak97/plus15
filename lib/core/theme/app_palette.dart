import 'package:flutter/material.dart';

/// Central brand + semantic color tokens for Plus15 Navigator.
///
/// Everything visual in the app should reference these tokens instead of
/// hard-coding hex values, so the look stays cohesive and is themeable from a
/// single place. The identity: a confident indigo brand paired with a luminous
/// "skywalk" teal that represents the elevated +15 bridge network itself.
class AppPalette {
  AppPalette._();

  // --- Brand -------------------------------------------------------------
  /// Primary brand color. Used for the app seed, primary actions, the active
  /// route line and selected states.
  static const Color brand = Color(0xFF4F46E5);
  static const Color brandDeep = Color(0xFF4338CA);
  static const Color brandSoft = Color(0xFF818CF8);

  /// The +15 skywalk network. This is the signature color of the map — the
  /// glowing vector lines that connect every building.
  static const Color skywalk = Color(0xFF0EA5B7);
  static const Color skywalkBright = Color(0xFF22D3EE);

  // --- Semantic ----------------------------------------------------------
  static const Color origin = Color(0xFF10B981);
  static const Color destination = Color(0xFFF43F5E);
  static const Color warning = Color(0xFFF59E0B);
  static const Color danger = Color(0xFFEF4444);
  static const Color transit = Color(0xFF10B981);

  // --- Neutrals (light) --------------------------------------------------
  static const Color ink = Color(0xFF0B1020);
  static const Color inkMuted = Color(0xFF64748B);
  static const Color surfaceLight = Color(0xFFF6F7FB);
  static const Color cardLight = Color(0xFFFFFFFF);
  static const Color borderLight = Color(0xFFE7E9F2);

  // --- Neutrals (dark) ---------------------------------------------------
  static const Color inkDark = Color(0xFFF4F5FB);
  static const Color inkMutedDark = Color(0xFF94A3B8);
  static const Color surfaceDark = Color(0xFF080A14);
  static const Color cardDark = Color(0xFF12141F);
  static const Color borderDark = Color(0xFF222637);

  // --- Building / place type accents ------------------------------------
  static Color typeColor(String type) {
    switch (type) {
      case 'hotel':
        return const Color(0xFFF59E0B);
      case 'retail':
        return const Color(0xFF8B5CF6);
      case 'landmark':
        return const Color(0xFFF43F5E);
      case 'entertainment':
        return const Color(0xFFF97316);
      case 'government':
        return const Color(0xFF06B6D4);
      case 'convention':
        return const Color(0xFF10B981);
      case 'park':
        return const Color(0xFF22C55E);
      case 'residential':
        return const Color(0xFF6366F1);
      default:
        return brand;
    }
  }

  static Color amenityColor(String amenity) {
    switch (amenity) {
      case 'food':
        return const Color(0xFFF43F5E);
      case 'retail':
        return const Color(0xFF8B5CF6);
      case 'transit':
        return const Color(0xFF10B981);
      case 'washroom':
        return const Color(0xFF06B6D4);
      case 'hotel':
        return const Color(0xFFF59E0B);
      case 'health':
        return const Color(0xFFEC4899);
      case 'entertainment':
        return const Color(0xFFF97316);
      default:
        return inkMuted;
    }
  }

  /// The signature brand gradient used on primary surfaces and the route bar.
  static const LinearGradient brandGradient = LinearGradient(
    colors: [brand, skywalk],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
