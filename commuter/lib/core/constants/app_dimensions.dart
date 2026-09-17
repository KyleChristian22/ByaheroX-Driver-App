import 'package:flutter/material.dart';

/// App dimensions for consistent spacing and sizing
/// Based on 8pt grid system
class AppDimensions {
  AppDimensions._();

  // Spacing (8pt grid)
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 16.0;
  static const double lg = 24.0;
  static const double xl = 32.0;
  static const double xxl = 48.0;
  static const double xxxl = 64.0;

  // Border Radius
  static const double radiusXs = 4.0;
  static const double radiusSm = 8.0;
  static const double radiusMd = 12.0;
  static const double radiusLg = 16.0;
  static const double radiusXl = 24.0;
  static const double radiusFull = 9999.0;

  // Border Radius - EdgeInsets
  static const EdgeInsets paddingXs = EdgeInsets.all(xs);
  static const EdgeInsets paddingSm = EdgeInsets.all(sm);
  static const EdgeInsets paddingMd = EdgeInsets.all(md);
  static const EdgeInsets paddingLg = EdgeInsets.all(lg);
  static const EdgeInsets paddingXl = EdgeInsets.all(xl);

  // Horizontal Padding
  static const EdgeInsets paddingHorizontalSm =
      EdgeInsets.symmetric(horizontal: sm);
  static const EdgeInsets paddingHorizontalMd =
      EdgeInsets.symmetric(horizontal: md);
  static const EdgeInsets paddingHorizontalLg =
      EdgeInsets.symmetric(horizontal: lg);

  // Vertical Padding
  static const EdgeInsets paddingVerticalSm =
      EdgeInsets.symmetric(vertical: sm);
  static const EdgeInsets paddingVerticalMd =
      EdgeInsets.symmetric(vertical: md);
  static const EdgeInsets paddingVerticalLg =
      EdgeInsets.symmetric(vertical: lg);

  // Screen Padding
  static const EdgeInsets screenPadding =
      EdgeInsets.symmetric(horizontal: md, vertical: sm);

  // Card Padding
  static const EdgeInsets cardPadding =
      EdgeInsets.all(md);
  static const EdgeInsets cardPaddingCompact =
      EdgeInsets.all(sm);

  // Icon Sizes
  static const double iconXs = 16.0;
  static const double iconSm = 20.0;
  static const double iconMd = 24.0;
  static const double iconLg = 32.0;
  static const double iconXl = 48.0;

  // Button Heights
  static const double buttonHeightSm = 48.0;
  static const double buttonHeightMd = 56.0;
  static const double buttonHeightLg = 60.0;

  // Touch Target (minimum 48x48 for accessibility)
  static const double touchTargetMin = 48.0;

  // Input Field Heights
  static const double inputHeight = 56.0;
  static const double inputHeightCompact = 52.0;

  // Bottom Navigation
  static const double bottomNavHeight = 80.0;
  static const double bottomNavIconSize = 28.0;

  // App Bar
  static const double appBarHeight = 56.0;
  static const double appBarElevation = 0.0;

  // Card Elevation
  static const double elevationNone = 0.0;
  static const double elevationSm = 2.0;
  static const double elevationMd = 4.0;
  static const double elevationLg = 8.0;

  // Map Marker Size
  static const double markerSizeSm = 32.0;
  static const double markerSizeMd = 40.0;
  static const double markerSizeLg = 48.0;

  // Shadow Blur Values
  static const double shadowBlurSm = 4.0;
  static const double shadowBlurMd = 8.0;
  static const double shadowBlurLg = 16.0;

  // Bottom Sheet
  static const double bottomSheetHandleWidth = 40.0;
  static const double bottomSheetHandleHeight = 4.0;
  static const double bottomSheetRadius = 24.0;

  // Avatar Sizes
  static const double avatarSm = 32.0;
  static const double avatarMd = 40.0;
  static const double avatarLg = 56.0;
  static const double avatarXl = 80.0;

  // Divider
  static const double dividerThickness = 1.0;

  // Border Width
  static const double borderWidth = 1.0;
  static const double borderWidthThick = 2.0;

  // Animation Durations (in milliseconds)
  static const int animationFast = 150;
  static const int animationNormal = 300;
  static const int animationSlow = 500;

  // Splash Screen
  static const int splashDuration = 2500; // milliseconds

  // Border Radius - BorderRadius objects
  static final BorderRadius borderRadiusXs =
      BorderRadius.circular(radiusXs);
  static final BorderRadius borderRadiusSm =
      BorderRadius.circular(radiusSm);
  static final BorderRadius borderRadiusMd =
      BorderRadius.circular(radiusMd);
  static final BorderRadius borderRadiusLg =
      BorderRadius.circular(radiusLg);
  static final BorderRadius borderRadiusXl =
      BorderRadius.circular(radiusXl);
  static final BorderRadius borderRadiusFull =
      BorderRadius.circular(radiusFull);

  // Common Box Shadows
  static List<BoxShadow> get shadowSm => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.05),
          blurRadius: 4,
          offset: const Offset(0, 2),
        ),
      ];

  static List<BoxShadow> get shadowMd => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.08),
          blurRadius: 8,
          offset: const Offset(0, 4),
        ),
      ];

  static List<BoxShadow> get shadowLg => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.12),
          blurRadius: 16,
          offset: const Offset(0, 8),
        ),
      ];

  static List<BoxShadow> get shadowTop => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.1),
          blurRadius: 8,
          offset: const Offset(0, -2),
        ),
      ];
}
