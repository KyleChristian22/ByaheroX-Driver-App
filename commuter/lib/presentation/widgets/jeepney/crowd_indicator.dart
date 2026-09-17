import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../domain/entities/jeepney.dart';

/// Widget to display crowd level indicator
class CrowdIndicator extends StatelessWidget {
  final CrowdLevel crowdLevel;
  final bool showLabel;
  final double size;

  const CrowdIndicator({
    super.key,
    required this.crowdLevel,
    this.showLabel = true,
    this.size = 12,
  });

  @override
  Widget build(BuildContext context) {
    final color = _getColor();
    final label = _getLabel();
    final icon = _getIcon();

    return Semantics(
      label: 'Crowd level: $label',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: size.clamp(18.0, 24.0).toDouble()),
          if (showLabel) ...[
            const SizedBox(width: AppDimensions.xs),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDimensions.sm,
                vertical: AppDimensions.xs,
              ),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: AppDimensions.borderRadiusFull,
                border: Border.all(color: color.withValues(alpha: 0.35)),
              ),
              child: Text(
                label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Color _getColor() {
    switch (crowdLevel) {
      case CrowdLevel.maliwag:
        return AppColors.crowdMaliwag;
      case CrowdLevel.sakto:
        return AppColors.crowdSakto;
      case CrowdLevel.puno:
        return AppColors.crowdPuno;
    }
  }

  String _getLabel() {
    switch (crowdLevel) {
      case CrowdLevel.maliwag:
        return 'Maluwag';
      case CrowdLevel.sakto:
        return 'Sakto';
      case CrowdLevel.puno:
        return 'Puno';
    }
  }

  IconData _getIcon() {
    switch (crowdLevel) {
      case CrowdLevel.maliwag:
        return Icons.event_seat_outlined;
      case CrowdLevel.sakto:
        return Icons.groups_2_outlined;
      case CrowdLevel.puno:
        return Icons.no_transfer_outlined;
    }
  }
}

/// Small crowd dot indicator (for map markers)
class CrowdDot extends StatelessWidget {
  final CrowdLevel crowdLevel;

  const CrowdDot({
    super.key,
    required this.crowdLevel,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Crowd level marker',
      child: Icon(
        _getIcon(),
        color: _getColor(),
        size: 16,
      ),
    );
  }

  Color _getColor() {
    switch (crowdLevel) {
      case CrowdLevel.maliwag:
        return AppColors.crowdMaliwag;
      case CrowdLevel.sakto:
        return AppColors.crowdSakto;
      case CrowdLevel.puno:
        return AppColors.crowdPuno;
    }
  }

  IconData _getIcon() {
    switch (crowdLevel) {
      case CrowdLevel.maliwag:
        return Icons.event_seat_outlined;
      case CrowdLevel.sakto:
        return Icons.groups_2_outlined;
      case CrowdLevel.puno:
        return Icons.no_transfer_outlined;
    }
  }
}
