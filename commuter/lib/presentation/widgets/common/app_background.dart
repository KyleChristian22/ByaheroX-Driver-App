import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';

class AppBackground extends StatelessWidget {
  const AppBackground({super.key, required this.child});

  static const String assetPath = 'assets/images/bg_app.png';

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: Image.asset(
            assetPath,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const _FallbackBackground(),
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.surface.withValues(alpha: 0.08),
                  AppColors.primaryBlueSurface.withValues(alpha: 0.04),
                  AppColors.surface.withValues(alpha: 0.06),
                ],
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.padding = AppDimensions.paddingLg,
    this.margin,
    this.borderRadius,
    this.borderColor,
    this.backgroundColor,
    this.width,
    this.height,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final BorderRadius? borderRadius;
  final Color? borderColor;
  final Color? backgroundColor;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? AppDimensions.borderRadiusLg;

    return Container(
      width: width,
      height: height,
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryBlue.withValues(alpha: 0.09),
            blurRadius: 22,
            spreadRadius: 1,
            offset: const Offset(0, 14),
          ),
          BoxShadow(
            color: AppColors.neonBlue.withValues(alpha: 0.12),
            blurRadius: 16,
            spreadRadius: -3,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 7, sigmaY: 7),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: backgroundColor ??
                  AppColors.surface.withValues(alpha: 0.34),
              borderRadius: radius,
              border: Border.all(
                color:
                    borderColor ?? AppColors.surface.withValues(alpha: 0.46),
                width: 1.4,
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _FallbackBackground extends StatelessWidget {
  const _FallbackBackground();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFFEFF6FF),
            AppColors.primaryBlueSurface,
            AppColors.surface,
            AppColors.accentRedSurface.withValues(alpha: 0.36),
          ],
        ),
      ),
    );
  }
}
