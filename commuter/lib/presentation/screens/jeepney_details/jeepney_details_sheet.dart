import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/constants/app_strings.dart';
import '../../../domain/entities/jeepney.dart';
import '../../../domain/models/route_filter.dart';
import '../../../data/services/ride_feedback_service.dart';
import '../../viewmodels/auth_viewmodel.dart';
import '../../viewmodels/jeepney_viewmodel.dart';
import '../../viewmodels/pickup_location_provider.dart';
import '../../widgets/common/app_background.dart';
import '../../widgets/ride_feedback_sheet.dart';

/// Bottom sheet showing jeepney details
class JeepneyDetailsSheet extends StatelessWidget {
  final Jeepney jeepney;
  final VoidCallback? onClose;

  const JeepneyDetailsSheet({super.key, required this.jeepney, this.onClose});

  String _jeepneyDisplayName() {
    final plateNumber = jeepney.plateNumber.trim();
    if (plateNumber.isNotEmpty && plateNumber != jeepney.id.trim()) {
      return plateNumber;
    }

    return 'Jeepney';
  }

  @override
  Widget build(BuildContext context) {
    final crowdColor = AppColors.getCrowdColor(jeepney.crowdLevelString);
    final bottomPadding =
        MediaQuery.of(context).padding.bottom + AppDimensions.md;

    return GlassSurface(
      padding: EdgeInsets.zero,
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppDimensions.bottomSheetRadius),
      ),
      backgroundColor: AppColors.surface.withValues(alpha: 0.38),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Top section with drag handle
          Padding(
            padding: const EdgeInsets.only(top: AppDimensions.sm),
            child: Container(
              width: AppDimensions.bottomSheetHandleWidth,
              height: AppDimensions.bottomSheetHandleHeight,
              decoration: BoxDecoration(
                color: AppColors.textTertiary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Main content
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppDimensions.md,
              AppDimensions.md,
              AppDimensions.md,
              0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header row: Jeep icon, info, close button
                Row(
                  children: [
                    // Jeep icon with crowd color background
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: crowdColor.withValues(alpha: 0.12),
                        borderRadius: AppDimensions.borderRadiusMd,
                      ),
                      child: Icon(
                        Icons.directions_car,
                        color: crowdColor,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: AppDimensions.md),

                    // Jeep info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _jeepneyDisplayName(),
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          // Status indicator with color
                          Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: crowdColor,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                jeepney.crowdLevelDisplayName,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: crowdColor,
                                      fontWeight: FontWeight.w500,
                                    ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Close button
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        onClose?.call();
                        Navigator.of(context).maybePop();
                      },
                    ),
                  ],
                ),

                const SizedBox(height: AppDimensions.md),

                // Arriving Soon Warning
                if (jeepney.isArrivingSoon)
                  Column(
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(AppDimensions.md),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withValues(alpha: 0.1),
                          borderRadius: AppDimensions.borderRadiusMd,
                          border: Border.all(
                            color: AppColors.warning.withValues(alpha: 0.3),
                            width: 1.5,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(
                                    AppDimensions.sm,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.warning,
                                    borderRadius: BorderRadius.circular(
                                      AppDimensions.radiusSm,
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.schedule,
                                    size: 20,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(width: AppDimensions.sm),
                                Text(
                                  AppStrings.arrivingSoon,
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.warning,
                                      ),
                                ),
                              ],
                            ),
                            const SizedBox(height: AppDimensions.sm),
                            Text(
                              AppStrings.proceedToPickup,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppDimensions.md),
                    ],
                  ),

                // Info cards row - compact
                Row(
                  children: [
                    // ETA Card - color based on jeepney status
                    Expanded(
                      child: _buildInfoCard(
                        context,
                        icon: Icons.access_time,
                        label: AppStrings.eta,
                        value: jeepney.isArrivingSoon
                            ? '${jeepney.estimatedArrivalMinutes} ${AppStrings.minutes}'
                            : '${jeepney.estimatedArrivalMinutes} min',
                        valueColor: crowdColor,
                        backgroundColor: crowdColor.withValues(alpha: 0.1),
                      ),
                    ),
                    const SizedBox(width: AppDimensions.sm),

                    // Speed Card - color based on jeepney status
                    Expanded(
                      child: _buildInfoCard(
                        context,
                        icon: Icons.speed,
                        label: AppStrings.speed,
                        value:
                            '${jeepney.speed.toStringAsFixed(0)} ${AppStrings.kmh}',
                        valueColor: crowdColor,
                        backgroundColor: crowdColor.withValues(alpha: 0.1),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: AppDimensions.sm),

                if ((jeepney.driverName ?? '').trim().isNotEmpty) ...[
                  _buildInfoCard(
                    context,
                    icon: Icons.person,
                    label: 'Driver',
                    value: jeepney.driverName!.trim(),
                    valueColor: AppColors.primary,
                    backgroundColor: AppColors.primary.withValues(alpha: 0.08),
                    isFullWidth: true,
                  ),
                  const SizedBox(height: AppDimensions.sm),
                ],

                // Passenger status card (full width)
                _buildInfoCard(
                  context,
                  icon: Icons.people,
                  label: 'Passengers',
                  value: jeepney.maxCapacity > 0
                      ? '${jeepney.passengerCount} / ${jeepney.maxCapacity} on board'
                      : jeepney.passengerCount > 0
                      ? '${jeepney.passengerCount} on board'
                      : jeepney.crowdLevelDisplayName,
                  valueColor: crowdColor,
                  backgroundColor: crowdColor.withValues(alpha: 0.08),
                  isFullWidth: true,
                ),

                if ((jeepney.scheduleTime ?? '').isNotEmpty) ...[
                  const SizedBox(height: AppDimensions.sm),
                  _buildInfoCard(
                    context,
                    icon: Icons.event_available,
                    label: 'Trip schedule',
                    value: jeepney.scheduleTime!,
                    valueColor: AppColors.primary,
                    backgroundColor: AppColors.primary.withValues(alpha: 0.08),
                    isFullWidth: true,
                  ),
                ],

                const SizedBox(height: AppDimensions.lg),

                // Action buttons - stacked vertically, full width
                _buildActionButtons(context),
              ],
            ),
          ),

          // Bottom safe area padding
          SizedBox(height: bottomPadding),
        ],
      ),
    );
  }

  Widget _buildInfoCard(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    required Color valueColor,
    required Color backgroundColor,
    bool isFullWidth = false,
  }) {
    return GlassSurface(
      width: isFullWidth ? double.infinity : null,
      padding: const EdgeInsets.all(AppDimensions.md),
      backgroundColor: backgroundColor.withValues(alpha: 0.72),
      borderColor: valueColor.withValues(alpha: 0.18),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(AppDimensions.sm),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
            ),
            child: Icon(icon, size: 20, color: valueColor),
          ),
          const SizedBox(width: AppDimensions.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: valueColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    return Consumer3<AuthViewModel, PickupLocationProvider, JeepneyViewModel>(
      builder: (context, authViewModel, pickupProvider, jeepneyViewModel, _) {
        final isLoggedIn = !authViewModel.currentUser.isGuest;
        final isSharingLocation = pickupProvider.isSharing;
        final isOnboardForThis = pickupProvider.canDropOffForJeepney(
          jeepney.id,
        );
        final isBookedForThis = pickupProvider.isBookedForJeepney(jeepney.id);
        final isBookedOnAnotherJeepney = pickupProvider
            .isBookedOnAnotherJeepney(jeepney.id);
        final canUnshareThisLocation = isSharingLocation && isBookedForThis;
        final isFull = _isJeepFull(jeepney);
        final isNotifyBlockedByFull =
            isFull &&
            !isOnboardForThis &&
            !isBookedOnAnotherJeepney &&
            !canUnshareThisLocation;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (isOnboardForThis) ...[
              _buildOnboardNotice(context, pickupProvider),
              const SizedBox(height: AppDimensions.md),
            ],
            if (isBookedOnAnotherJeepney) ...[
              _buildAlreadyBookedNotice(context, pickupProvider),
              const SizedBox(height: AppDimensions.md),
            ],
            if (isLoggedIn)
              _ActionButton(
                label: isOnboardForThis
                    ? 'Drop Off'
                    : isBookedOnAnotherJeepney
                    ? 'Already Booked'
                    : canUnshareThisLocation
                    ? AppStrings.unshareMyLocation
                    : isNotifyBlockedByFull
                    ? 'Jeep is full'
                    : AppStrings.getNotifications,
                icon: isOnboardForThis
                    ? Icons.logout_outlined
                    : isBookedOnAnotherJeepney
                    ? Icons.lock_outline
                    : canUnshareThisLocation
                    ? Icons.location_off_outlined
                    : isNotifyBlockedByFull
                    ? Icons.event_busy_outlined
                    : Icons.notifications_outlined,
                backgroundColor: isOnboardForThis
                    ? AppColors.secondary
                    : isBookedOnAnotherJeepney
                    ? AppColors.textSecondary
                    : canUnshareThisLocation
                    ? AppColors.error
                    : isNotifyBlockedByFull
                    ? AppColors.textSecondary
                    : null,
                enabled: !isBookedOnAnotherJeepney && !isNotifyBlockedByFull,
                onPressed: () async {
                  if (isOnboardForThis) {
                    final result = await pickupProvider.offboardPickupLocation(
                      authViewModel.currentUser.id,
                      dropOffCount: 1,
                    );
                    if (!context.mounted) return;

                    final success = result != null;
                    final message = result == null
                        ? pickupProvider.errorMessage ??
                              'Could not record drop off.'
                        : result.fullyOffboard
                        ? 'Drop off recorded.'
                        : '${result.dropOffCount} dropped off. ${result.remainingPassengerCount} still on board.';
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(message),
                        behavior: SnackBarBehavior.floating,
                        backgroundColor: success
                            ? AppColors.success
                            : AppColors.error,
                      ),
                    );
                    if (result?.fullyOffboard == true) {
                      final completedTrip =
                          await RideFeedbackService.getLatestUnratedCompletedTrip(
                            authViewModel.currentUser.id,
                          );
                      if (!context.mounted || completedTrip == null) return;
                      await showPostRideFeedbackPrompt(
                        context,
                        trip: completedTrip,
                      );
                    }
                    return;
                  }

                  if (canUnshareThisLocation) {
                    final success = await pickupProvider.clearPickupLocation(
                      authViewModel.currentUser.id,
                    );
                    if (!context.mounted) return;

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          success
                              ? AppStrings.locationSharingStopped
                              : AppStrings.locationSharingStopFailed,
                        ),
                        behavior: SnackBarBehavior.floating,
                        backgroundColor: success
                            ? AppColors.success
                            : AppColors.error,
                      ),
                    );
                    return;
                  }

                  final selectedJeepneyIsOnTrip = jeepneyViewModel
                      .activeDriverLocations
                      .any((j) => j.id == jeepney.id && j.isActive);
                  if (!selectedJeepneyIsOnTrip) {
                    Navigator.pop(context);
                    onClose?.call();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(AppStrings.cannotShareNoDriverOnTrip),
                        behavior: SnackBarBehavior.floating,
                        backgroundColor: AppColors.warning,
                      ),
                    );
                    return;
                  }

                  if (_isJeepFull(jeepney)) {
                    _showJeepFullSnackBar(context);
                    return;
                  }

                  final routeValidationMessage = RouteFilter.validationMessage(
                    routeId: jeepney.routeId,
                    originTerminal: jeepney.originTerminal,
                    destinationTerminal: jeepney.destinationTerminal,
                  );
                  if (routeValidationMessage != null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(routeValidationMessage),
                        behavior: SnackBarBehavior.floating,
                        backgroundColor: AppColors.warning,
                      ),
                    );
                    return;
                  }

                  final userLocation = jeepneyViewModel.userLocation;

                  if (userLocation == null) {
                    Navigator.pop(context);
                    onClose?.call();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Location not available. Please enable GPS.',
                        ),
                        behavior: SnackBarBehavior.floating,
                        backgroundColor: AppColors.warning,
                      ),
                    );
                    return;
                  }

                  final success = await pickupProvider.setPickupLocationFromGps(
                    commuterId: authViewModel.currentUser.id,
                    location: userLocation,
                    routeId: jeepney.routeId,
                    jeepneyId: jeepney.id,
                    waitingCount: 1,
                    destinationTerminal: jeepney.destinationTerminal,
                  );
                  if (success && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Naipadala sa driver: 1 passenger waiting.',
                        ),
                        behavior: SnackBarBehavior.floating,
                        backgroundColor: AppColors.success,
                      ),
                    );
                  } else if (!success && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          pickupProvider.errorMessage ??
                              'Could not notify driver. Please try again.',
                        ),
                        behavior: SnackBarBehavior.floating,
                        backgroundColor: AppColors.warning,
                      ),
                    );
                  }
                },
              ),
          ],
        );
      },
    );
  }

  bool _isJeepFull(Jeepney jeepney) {
    return jeepney.maxCapacity > 0 &&
        jeepney.passengerCount >= jeepney.maxCapacity;
  }

  void _showJeepFullSnackBar(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Jeep is full. Please choose another jeep or wait for available seats.',
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.warning,
      ),
    );
  }

  Widget _buildAlreadyBookedNotice(
    BuildContext context,
    PickupLocationProvider pickupProvider,
  ) {
    final destination = pickupProvider.destinationTerminal?.trim() ?? '';
    final subtitle = destination.isNotEmpty
        ? '${pickupProvider.passengerLabel} already booked - To $destination'
        : '${pickupProvider.passengerLabel} already booked with another driver';

    return Container(
      padding: const EdgeInsets.all(AppDimensions.md),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.08),
        borderRadius: AppDimensions.borderRadiusMd,
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.lock_outline,
              color: AppColors.warning,
              size: 20,
            ),
          ),
          const SizedBox(width: AppDimensions.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Already booked',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: AppColors.warning,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOnboardNotice(
    BuildContext context,
    PickupLocationProvider pickupProvider,
  ) {
    final destination = pickupProvider.destinationTerminal?.trim() ?? '';
    final subtitle = destination.isNotEmpty
        ? '${pickupProvider.passengerLabel} on board - To $destination'
        : '${pickupProvider.passengerLabel} on board';

    return Container(
      padding: const EdgeInsets.all(AppDimensions.md),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.08),
        borderRadius: AppDimensions.borderRadiusMd,
        border: Border.all(color: AppColors.success.withValues(alpha: 0.24)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.event_seat_outlined,
              color: AppColors.success,
              size: 22,
            ),
          ),
          const SizedBox(width: AppDimensions.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'You are on board',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: AppColors.success,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Reusable action button with consistent styling
class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final Color? backgroundColor;
  final bool enabled;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.backgroundColor,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AppDimensions.buttonHeightMd,
      child: FilledButton.icon(
        onPressed: enabled ? onPressed : null,
        icon: Icon(icon, size: 20),
        label: Text(label),
        style: FilledButton.styleFrom(
          backgroundColor: backgroundColor,
          shape: RoundedRectangleBorder(
            borderRadius: AppDimensions.borderRadiusMd,
          ),
        ),
      ),
    );
  }
}
