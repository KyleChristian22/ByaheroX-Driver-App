import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../domain/entities/jeepney.dart';
import '../jeepney/crowd_indicator.dart';

/// Custom jeepney marker widget for the map.
class JeepneyMarker extends StatelessWidget {
  final Jeepney jeepney;
  final VoidCallback? onTap;

  const JeepneyMarker({super.key, required this.jeepney, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Jeepney ${jeepney.plateNumber}',
      child: Semantics(
        button: onTap != null,
        label:
            'Jeepney ${jeepney.plateNumber}, crowd level ${jeepney.crowdLevelString}',
        child: GestureDetector(
          onTap: onTap,
          child: Transform.translate(
            offset: const Offset(0, -10),
            child: Container(
              width: AppDimensions.markerSizeLg,
              height: AppDimensions.markerSizeLg,
              decoration: BoxDecoration(
                color: AppColors.surface,
                shape: BoxShape.circle,
                boxShadow: AppDimensions.shadowMd,
                border: Border.all(color: _getCrowdColor(), width: 3),
              ),
              child: Stack(
                children: [
                  const Center(
                    child: Icon(
                      Icons.directions_bus_filled_outlined,
                      color: AppColors.primary,
                      size: 24,
                    ),
                  ),
                  Positioned(
                    top: 0,
                    right: 0,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: _getCrowdColor(),
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.surface, width: 2),
                      ),
                      child: const Icon(
                        Icons.circle,
                        color: AppColors.textOnPrimary,
                        size: 6,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Color _getCrowdColor() {
    switch (jeepney.crowdLevel) {
      case CrowdLevel.maliwag:
        return AppColors.crowdMaliwag;
      case CrowdLevel.sakto:
        return AppColors.crowdSakto;
      case CrowdLevel.puno:
        return AppColors.crowdPuno;
    }
  }
}

/// Small preview marker showing ETA.
class JeepneyMarkerPreview extends StatelessWidget {
  final Jeepney jeepney;

  const JeepneyMarkerPreview({super.key, required this.jeepney});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Estimated arrival ${jeepney.estimatedArrivalMinutes} minutes',
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppDimensions.sm,
          vertical: AppDimensions.xs,
        ),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppDimensions.borderRadiusFull,
          boxShadow: AppDimensions.shadowSm,
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CrowdDot(crowdLevel: jeepney.crowdLevel),
            const SizedBox(width: AppDimensions.xs),
            Text(
              '${jeepney.estimatedArrivalMinutes} min',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
