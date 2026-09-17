import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

class DriverAppBackground extends StatelessWidget {
  const DriverAppBackground({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.safeArea = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool safeArea;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: padding,
      child: child,
    );

    return Stack(
      children: [
        Positioned.fill(
          child: Image.asset(
            'assets/images/bg_app.png',
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
            errorBuilder: (_, __, ___) => const _DriverFallbackBackground(),
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.white.withValues(alpha: 0.08),
                  AppTheme.blueSurface.withValues(alpha: 0.04),
                  Colors.white.withValues(alpha: 0.06),
                ],
              ),
            ),
          ),
        ),
        safeArea ? SafeArea(child: content) : content,
      ],
    );
  }
}

class DriverGlassSurface extends StatelessWidget {
  const DriverGlassSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.borderRadius,
    this.borderColor,
    this.backgroundColor,
    this.width,
    this.height,
    this.blur = 7,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final BorderRadius? borderRadius;
  final Color? borderColor;
  final Color? backgroundColor;
  final double? width;
  final double? height;
  final double blur;

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? BorderRadius.circular(16);

    return Container(
      width: width,
      height: height,
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryBlue.withValues(alpha: 0.09),
            blurRadius: 22,
            spreadRadius: 1,
            offset: const Offset(0, 14),
          ),
          BoxShadow(
            color: AppTheme.accentBlue.withValues(alpha: 0.10),
            blurRadius: 16,
            spreadRadius: -3,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: backgroundColor ?? Colors.white.withValues(alpha: 0.34),
              borderRadius: radius,
              border: Border.all(
                color: borderColor ?? Colors.white.withValues(alpha: 0.46),
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

class _DriverFallbackBackground extends StatelessWidget {
  const _DriverFallbackBackground();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFFEFF6FF),
            AppTheme.blueSurface,
            Colors.white,
            AppTheme.primaryRed.withValues(alpha: 0.16),
          ],
        ),
      ),
    );
  }
}
