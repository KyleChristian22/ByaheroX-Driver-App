import 'package:flutter/material.dart';

/// App color palette for ByaheroX.
/// Designed for high readability in outdoor commuter use.
class AppColors {
  AppColors._();

  // Blue transportation identity.
  static const Color primaryBlue = Color(0xFF155EEF);
  static const Color primaryBlueDark = Color(0xFF0B3B8C);
  static const Color primaryBlueLight = Color(0xFF5B8DEF);
  static const Color primaryBlueSurface = Color(0xFFEAF2FF);
  static const Color neonBlue = Color(0xFF35C7FF);
  static const Color electricBlue = Color(0xFF2563FF);
  static const Color midnight = Color(0xFF020817);
  static const Color midnightBlue = Color(0xFF061A44);
  static const Color glassBlue = Color(0xCC071A46);

  // Red accent for branding highlights and urgent travel states.
  static const Color accentRed = Color(0xFFD92D20);
  static const Color accentRedDark = Color(0xFFA61B14);
  static const Color accentRedSurface = Color(0xFFFEECEB);

  // Backward-compatible aliases used throughout the app.
  static const Color primary = primaryBlue;
  static const Color primaryDark = primaryBlueDark;
  static const Color primaryLight = primaryBlueLight;
  static const Color primarySurface = primaryBlueSurface;
  static const Color secondary = accentRed;
  static const Color secondaryDark = accentRedDark;
  static const Color secondaryLight = accentRedSurface;

  // Background Colors
  static const Color background = Color(0xFFF7F9FC);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceVariant = Color(0xFFF1F5F9);

  // Text Colors
  static const Color textPrimary = Color(0xFF172033);
  static const Color textSecondary = Color(0xFF475467);
  static const Color textTertiary = Color(0xFF667085);
  static const Color textOnPrimary = Color(0xFFFFFFFF);
  static const Color disabled = Color(0xFF98A2B3);
  static const Color focus = Color(0xFF155EEF);

  // Status Colors
  static const Color error = Color(0xFFB42318);
  static const Color errorLight = Color(0xFFFEECEB);
  static const Color success = Color(0xFF027A48);
  static const Color successLight = Color(0xFFECFDF3);
  static const Color warning = Color(0xFFB54708);
  static const Color warningLight = Color(0xFFFFF7E6);
  static const Color info = primaryBlue;
  static const Color infoLight = primaryBlueSurface;

  // Crowd Level Colors
  static const Color crowdMaliwag = Color(0xFF027A48);
  static const Color crowdSakto = Color(0xFFB54708);
  static const Color crowdPuno = accentRed;

  // Border Colors
  static const Color border = Color(0xFFCBD5E1);
  static const Color borderLight = Color(0xFFE2E8F0);
  static const Color divider = Color(0xFFCBD5E1);

  // Map Colors
  static const Color mapRouteLine = primaryBlue;
  static const Color mapRouteLineAlternate = accentRed;
  static const Color mapMarkerBackground = surface;
  static const Color mapOverlay = Color(0xB3172033);

  // Gradient Colors
  static const List<Color> primaryGradient = [
    primaryBlue,
    primaryBlueDark,
  ];

  static const List<Color> splashGradient = [
    primaryBlueDark,
    primaryBlue,
  ];

  /// Get crowd level color based on crowd level enum
  static Color getCrowdColor(String crowdLevel) {
    switch (crowdLevel.toLowerCase()) {
      case 'maluwag':
        return crowdMaliwag;
      case 'sakto':
        return crowdSakto;
      case 'puno':
        return crowdPuno;
      default:
        return crowdSakto;
    }
  }

  /// Get crowd level hex color string
  static String getCrowdColorHex(String crowdLevel) {
    switch (crowdLevel.toLowerCase()) {
      case 'maluwag':
        return '#027A48';
      case 'sakto':
        return '#B54708';
      case 'puno':
        return '#D92D20';
      default:
        return '#B54708';
    }
  }
}
