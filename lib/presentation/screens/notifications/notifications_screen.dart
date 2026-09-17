import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../../core/booking_status.dart';
import '../../../core/theme/app_theme.dart';
import '../../../services/firestore_service.dart';
import '../../viewmodels/jeepney_viewmodel.dart';
import '../../viewmodels/trip_viewmodel.dart';
import '../../widgets/commuter_waiting_location_tile.dart';
import '../../widgets/driver_app_background.dart';

/// Notifications Screen for Driver App
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  LatLng? _driverLocation;

  @override
  void initState() {
    super.initState();
    _getDriverLocation();
  }

  Future<void> _getDriverLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
        ),
      );
      if (mounted) {
        setState(() {
          _driverLocation = LatLng(position.latitude, position.longitude);
        });
      }
    } catch (e) {
      debugPrint('Error getting driver location: $e');
    }
  }

  Future<void> _refreshLocation() async {
    await _getDriverLocation();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Location refreshed'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final destinationTerminal =
        context.watch<TripViewModel>().destinationTerminal;
    final driverId = context.watch<JeepneyViewModel>().driverId.trim();

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Alerts'),
        actions: [
          IconButton(
            icon: const Icon(Icons.my_location),
            tooltip: 'Refresh my location',
            onPressed: _refreshLocation,
          ),
        ],
      ),
      body: DriverAppBackground(
        safeArea: false,
        child: SafeArea(
          child: StreamBuilder<List<CommuterWaitingLocation>>(
            stream: FirestoreService.watchAllCommuterLocations(
              destinationTerminal: destinationTerminal,
            ),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return _MessageState(
                  icon: Icons.error_outline,
                  title: 'Unable to load alerts',
                  message: snapshot.error.toString(),
                );
              }

              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final commuters = snapshot.data ?? [];
              if (commuters.isEmpty) {
                return Column(
                  children: [
                    _DriverAppNotifications(driverId: driverId),
                    Expanded(
                      child: WaitingCommutersEmptyState(
                        destinationTerminal: destinationTerminal,
                      ),
                    ),
                  ],
                );
              }

              final waitingCommuters = commuters.where(
                (c) => BookingStatus.isWaiting(c.status),
              );
              final totalWaiting = waitingCommuters.fold<int>(
                0,
                (total, commuter) => total + commuter.waitingCount,
              );

              return Column(
                children: [
                  _DriverAppNotifications(driverId: driverId),
                  _WaitingSummary(
                    totalWaiting: totalWaiting,
                    sharedLocationCount: commuters.length,
                    destinationTerminal: destinationTerminal,
                  ),
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: commuters.length,
                      separatorBuilder: (_, __) => const Divider(
                        height: 1,
                        indent: 68,
                      ),
                      itemBuilder: (context, index) {
                        final commuter = commuters[index];
                        return CommuterWaitingLocationTile(
                          location: commuter,
                          driverLocation: _driverLocation,
                          showCoordinates: true,
                          onOnboard: BookingStatus.isWaiting(commuter.status)
                              ? () async {
                                  final result = await FirestoreService
                                      .markCommuterOnboard(
                                    commuter.commuterId,
                                  );
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          result.success
                                              ? '${commuter.displayName} marked as onboard'
                                              : result.message,
                                        ),
                                        behavior: SnackBarBehavior.floating,
                                        backgroundColor: result.success
                                            ? Colors.green
                                            : Colors.orange,
                                      ),
                                    );
                                  }
                                }
                              : null,
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _DriverAppNotifications extends StatelessWidget {
  final String driverId;

  const _DriverAppNotifications({required this.driverId});

  @override
  Widget build(BuildContext context) {
    if (driverId.isEmpty) return const SizedBox.shrink();

    return FutureBuilder<List<NotificationData>>(
      future: FirestoreService.getDriverNotifications(driverId),
      builder: (context, snapshot) {
        final notifications = (snapshot.data ?? [])
            .where((notification) =>
                notification.type.startsWith('driver_payout_'))
            .take(3)
            .toList();

        if (notifications.isEmpty) return const SizedBox.shrink();

        return DriverGlassSurface(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          borderRadius: BorderRadius.circular(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Account Notifications',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF1E293B),
                    ),
              ),
              const SizedBox(height: 8),
              ...notifications.map(
                (notification) => _DriverNotificationTile(
                  notification: notification,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DriverNotificationTile extends StatelessWidget {
  final NotificationData notification;

  const _DriverNotificationTile({required this.notification});

  @override
  Widget build(BuildContext context) {
    final isPaid = notification.type == 'driver_payout_paid';
    final color = isPaid ? Colors.green : Colors.red;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isPaid ? Icons.check_circle_outline : Icons.cancel_outlined,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  notification.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  notification.message,
                  style: TextStyle(
                    color: Colors.grey[700],
                    fontSize: 13,
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

class _WaitingSummary extends StatelessWidget {
  final int totalWaiting;
  final int sharedLocationCount;
  final String destinationTerminal;

  const _WaitingSummary({
    required this.totalWaiting,
    required this.sharedLocationCount,
    required this.destinationTerminal,
  });

  @override
  Widget build(BuildContext context) {
    final routeText = destinationTerminal.isNotEmpty
        ? 'Bound for $destinationTerminal'
        : 'All active shared locations';
    final locationLabel = sharedLocationCount == 1
        ? '1 shared location'
        : '$sharedLocationCount shared locations';
    final passengerLabel =
        totalWaiting == 1 ? '1 passenger' : '$totalWaiting passengers';

    return DriverGlassSurface(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      backgroundColor: AppTheme.lightBlue.withValues(alpha: 0.34),
      borderColor: AppTheme.primaryBlue.withValues(alpha: 0.24),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppTheme.primaryBlue,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.groups_2_outlined,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  passengerLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF1E293B),
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '$locationLabel - $routeText',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.grey[700],
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
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

class _MessageState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _MessageState({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 64,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey.shade700,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
