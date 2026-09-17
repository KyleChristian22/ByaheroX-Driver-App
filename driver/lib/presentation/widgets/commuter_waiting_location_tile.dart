import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../core/booking_status.dart';
import '../../core/theme/app_theme.dart';
import '../../services/firestore_service.dart';
import 'driver_app_background.dart';

class CommuterWaitingLocationTile extends StatelessWidget {
  final CommuterWaitingLocation location;
  final bool dense;
  final bool showCoordinates;
  final VoidCallback? onTap;
  final VoidCallback? onOnboard;
  final LatLng? driverLocation;

  const CommuterWaitingLocationTile({
    super.key,
    required this.location,
    this.dense = false,
    this.showCoordinates = false,
    this.onTap,
    this.onOnboard,
    this.driverLocation,
  });

  @override
  Widget build(BuildContext context) {
    final passengerLabel = location.waitingCount == 1
        ? '1 passenger waiting'
        : '${location.waitingCount} passengers waiting';
    final destinationLabel = location.destinationTerminal.isNotEmpty
        ? 'To: ${location.destinationTerminal}'
        : 'Destination not set';
    final timeLabel = _formatRelativeTime(location.timestamp);

    // Calculate distance from driver to commuter
    final distanceText = _calculateDistanceText();

    return DriverGlassSurface(
      margin: EdgeInsets.symmetric(
        horizontal: dense ? 0 : 12,
        vertical: dense ? 4 : 6,
      ),
      padding: EdgeInsets.zero,
      borderRadius: BorderRadius.circular(14),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: dense ? 12 : 16,
              vertical: dense ? 10 : 14,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: dense ? 34 : 40,
                  height: dense ? 34 : 40,
                  decoration: BoxDecoration(
                    color: AppTheme.primarySkyBlue.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.person_pin_circle_outlined,
                    color: AppTheme.primarySkyBlue,
                    size: dense ? 20 : 24,
                  ),
                ),
                SizedBox(width: dense ? 10 : 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              location.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: dense ? 13 : 15,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF1E293B),
                              ),
                            ),
                          ),
                          if (timeLabel.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Text(
                              timeLabel,
                              style: TextStyle(
                                fontSize: dense ? 10 : 12,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        passengerLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: dense ? 11 : 13,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.primaryBlue,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(
                            Icons.location_on_outlined,
                            size: dense ? 12 : 14,
                            color: Colors.grey[600],
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              destinationLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: dense ? 11 : 13,
                                color: Colors.grey[700],
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (distanceText != null) ...[
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Icon(
                              Icons.social_distance_outlined,
                              size: dense ? 12 : 14,
                              color: AppTheme.primaryBlue,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              distanceText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: dense ? 11 : 13,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.primaryBlue,
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (showCoordinates && location.hasCoordinates) ...[
                        const SizedBox(height: 3),
                        Text(
                          '${location.lat!.toStringAsFixed(5)}, ${location.lng!.toStringAsFixed(5)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                      if (!dense &&
                          BookingStatus.isWaiting(location.status) &&
                          onOnboard != null) ...[
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.tonalIcon(
                            onPressed: onOnboard,
                            icon: const Icon(Icons.directions_walk, size: 16),
                            label: const Text('Mark Onboard'),
                            style: FilledButton.styleFrom(
                              backgroundColor:
                                  Colors.green.withValues(alpha: 0.15),
                              foregroundColor: Colors.green.shade700,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                        ),
                      ],
                      if (BookingStatus.isOnboard(location.status)) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(
                              Icons.check_circle,
                              size: 14,
                              color: Colors.green.shade700,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Onboard',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.green.shade700,
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (BookingStatus.normalize(location.status) ==
                          BookingStatus.cancelled) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(
                              Icons.cancel,
                              size: 14,
                              color: Colors.red.shade600,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Cancelled',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.red.shade600,
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (BookingStatus.isOffboard(location.status) ||
                          BookingStatus.normalize(location.status) ==
                              BookingStatus.expired) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(
                              Icons.timer_off_outlined,
                              size: 14,
                              color: Colors.orange.shade700,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Expired',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.orange.shade700,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String? _calculateDistanceText() {
    if (driverLocation == null || !location.hasCoordinates) {
      return null;
    }

    final commuterLocation = LatLng(location.lat!, location.lng!);
    final distance = const Distance()
        .as(LengthUnit.Kilometer, driverLocation!, commuterLocation);

    if (distance < 1) {
      final meters = (distance * 1000).round();
      return '${meters}m away';
    } else if (distance < 10) {
      return '${distance.toStringAsFixed(1)} km away';
    } else {
      return '${distance.round()} km away';
    }
  }
}

class WaitingCommutersEmptyState extends StatelessWidget {
  final String? destinationTerminal;

  const WaitingCommutersEmptyState({
    super.key,
    this.destinationTerminal,
  });

  @override
  Widget build(BuildContext context) {
    final destination = destinationTerminal?.trim();
    final message = destination != null && destination.isNotEmpty
        ? 'No commuters waiting for $destination'
        : 'No shared commuter locations yet';

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.person_pin_circle_outlined,
              size: 64,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatRelativeTime(DateTime? timestamp) {
  if (timestamp == null) return '';

  final difference = DateTime.now().difference(timestamp);
  if (difference.inSeconds < 60) return 'now';
  if (difference.inMinutes < 60) return '${difference.inMinutes}m';
  if (difference.inHours < 24) return '${difference.inHours}h';
  if (difference.inDays < 7) return '${difference.inDays}d';
  return '${timestamp.month}/${timestamp.day}';
}
