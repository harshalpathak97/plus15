import 'package:flutter/material.dart';

/// Brand palette for Plus15 Navigator.
///
/// Reference these tokens instead of inlining colors in widgets. The
/// `AppTheme` constructs a `ColorScheme` from these values; everything else
/// (gradients, glass tints, glow colors) comes straight from here.
class P15Palette {
  P15Palette._();

  // Core brand
  static const electricBlue = Color(0xFF3D5BFE);
  static const violetAccent = Color(0xFF7C3AED);
  static const cyanGlow = Color(0xFF22D3EE);

  // Semantic accents
  static const sunsetOrange = Color(0xFFFB923C);
  static const limeSuccess = Color(0xFF84CC16);
  static const danger = Color(0xFFEF4444);
  static const amberWarn = Color(0xFFF59E0B);

  // Light surfaces
  static const surface0 = Color(0xFFF6F7FB);
  static const surface1 = Color(0xFFFFFFFF);
  static const surfaceMuted = Color(0xFFEEF1F8);
  static const borderLight = Color(0xFFE3E7F0);
  static const onSurface = Color(0xFF0B0F1A);
  static const onSurfaceMuted = Color(0xFF6B7280);

  // Dark surfaces
  static const surfaceDark0 = Color(0xFF06080F);
  static const surfaceDark1 = Color(0xFF0E1322);
  static const surfaceDarkMuted = Color(0xFF161D31);
  static const borderDark = Color(0xFF22293F);
  static const onSurfaceDark = Color(0xFFEDF2FA);
  static const onSurfaceDarkMuted = Color(0xFF8B93A8);

  // Building-type colors for both 2D markers and 3D extrusions.
  static const typeOffice = Color(0xFF64748B);
  static const typeRetail = Color(0xFF8B5CF6);
  static const typeHotel = Color(0xFFF59E0B);
  static const typeLandmark = Color(0xFFEF4444);
  static const typeGovernment = Color(0xFF06B6D4);
  static const typeConvention = Color(0xFF10B981);
  static const typeResidential = Color(0xFF94A3B8);
  static const typeParking = Color(0xFFA8B2C7);
  static const typeEntertainment = Color(0xFFD946EF);
  static const typeTransit = Color(0xFF22C55E);
  static const typePark = Color(0xFF65A30D);

  static Color colorForType(String type) {
    switch (type) {
      case 'retail':
        return typeRetail;
      case 'hotel':
        return typeHotel;
      case 'landmark':
        return typeLandmark;
      case 'government':
        return typeGovernment;
      case 'convention':
        return typeConvention;
      case 'residential':
        return typeResidential;
      case 'parking':
        return typeParking;
      case 'entertainment':
        return typeEntertainment;
      case 'park':
        return typePark;
      case 'office':
      default:
        return typeOffice;
    }
  }

  // Brand gradient — used on +15 mark, primary CTAs, route highlights.
  static const brandGradient = LinearGradient(
    colors: [electricBlue, violetAccent],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const routeGradient = LinearGradient(
    colors: [limeSuccess, cyanGlow, violetAccent, danger],
    stops: [0.0, 0.4, 0.75, 1.0],
  );

  static const skyGradientLight = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFE9E4FF), Color(0xFFF6F7FB)],
  );

  static const skyGradientDark = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF1B1740), Color(0xFF06080F)],
  );
}
