import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';

/// Primary button widget for ByaheroX app
class AppButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool isOutlined;
  final IconData? icon;
  final double? width;

  const AppButton({
    super.key,
    required this.text,
    this.onPressed,
    this.isLoading = false,
    this.isOutlined = false,
    this.icon,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    final isDisabled = onPressed == null || isLoading;
    final borderRadius = AppDimensions.borderRadiusMd;
    final child = isLoading
        ? Semantics(
            label: '$text loading',
            liveRegion: true,
            child: const SizedBox(
              height: 22,
              width: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: AppColors.textOnPrimary,
              ),
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 22),
                const SizedBox(width: AppDimensions.sm),
              ],
              Flexible(
                child: Text(
                  text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          );

    final foreground = isOutlined ? AppColors.primaryBlue : AppColors.surface;
    final borderColor = isDisabled
        ? AppColors.border.withValues(alpha: 0.5)
        : isOutlined
            ? AppColors.primaryBlue.withValues(alpha: 0.75)
            : AppColors.neonBlue.withValues(alpha: 0.9);

    return SizedBox(
      width: width ?? double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          boxShadow: isDisabled
              ? const []
              : [
                  BoxShadow(
                    color: AppColors.primaryBlue.withValues(alpha: 0.12),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                  BoxShadow(
                    color: AppColors.surface.withValues(alpha: 0.3),
                    blurRadius: 10,
                    spreadRadius: -4,
                    offset: const Offset(-3, -3),
                  ),
                ],
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: AppDimensions.buttonHeightMd,
            minWidth: AppDimensions.touchTargetMin,
          ),
          child: FilledButton(
            onPressed: isDisabled ? null : onPressed,
            style: FilledButton.styleFrom(
              backgroundColor: isOutlined
                  ? AppColors.surface.withValues(alpha: 0.3)
                  : AppColors.primaryBlue.withValues(alpha: 0.9),
              disabledBackgroundColor:
                  AppColors.surface.withValues(alpha: 0.24),
              foregroundColor: foreground,
              disabledForegroundColor: AppColors.disabled,
              elevation: 0,
              padding: const EdgeInsets.symmetric(
                horizontal: AppDimensions.lg,
                vertical: AppDimensions.md,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: borderRadius,
                side: BorderSide(color: borderColor, width: 1.6),
              ),
              textStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Secondary/Ghost button
class AppButtonSecondary extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final IconData? icon;

  const AppButtonSecondary({
    super.key,
    required this.text,
    this.onPressed,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.2),
        borderRadius: AppDimensions.borderRadiusFull,
        border: Border.all(color: AppColors.surface.withValues(alpha: 0.38)),
      ),
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primaryBlue,
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimensions.md,
            vertical: AppDimensions.sm,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 22),
              const SizedBox(width: AppDimensions.sm),
            ],
            Flexible(
              child: Text(
                text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
