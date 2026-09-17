import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../services/firestore_service.dart';
import '../viewmodels/trip_viewmodel.dart';
import 'commuter_waiting_location_tile.dart';

/// Notification menu button for the driver app.
class DriverNotificationButton extends StatelessWidget {
  final Color backgroundColor;
  final Color iconColor;
  final LatLng? driverLocation;

  const DriverNotificationButton({
    super.key,
    this.backgroundColor = Colors.white,
    this.iconColor = AppTheme.primaryBlue,
    this.driverLocation,
  });

  @override
  Widget build(BuildContext context) {
    final destinationTerminal =
        context.watch<TripViewModel>().destinationTerminal;

    return PopupMenuButton<String>(
      icon: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(
          Icons.notifications_outlined,
          color: iconColor,
          size: 20,
        ),
      ),
      onSelected: (value) {
        if (value == 'view_all') {
          AppRouter.goToNotifications(context);
        }
      },
      itemBuilder: (context) => [
        _buildNotificationDropdown(context, destinationTerminal),
      ],
    );
  }

  PopupMenuItem<String> _buildNotificationDropdown(
    BuildContext context,
    String destinationTerminal,
  ) {
    return PopupMenuItem<String>(
      enabled: false,
      child: StreamBuilder<List<CommuterWaitingLocation>>(
        stream: FirestoreService.watchSharedCommuterLocations(
          destinationTerminal: destinationTerminal,
        ),
        builder: (context, snapshot) {
          final commuters = snapshot.data ?? [];
          final waitingCount = commuters.fold<int>(
            0,
            (total, commuter) => total + commuter.waitingCount,
          );

          return Container(
            width: 300,
            constraints: const BoxConstraints(maxHeight: 350),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'Waiting Commuters',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1E293B),
                            ),
                          ),
                          if (waitingCount > 0) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.red,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '$waitingCount',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => Navigator.of(context).pop(),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Flexible(
                  child: snapshot.connectionState == ConnectionState.waiting
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        )
                      : commuters.isEmpty
                          ? WaitingCommutersEmptyState(
                              destinationTerminal: destinationTerminal,
                            )
                          : ListView.builder(
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          itemCount:
                              commuters.length > 4 ? 4 : commuters.length,
                          itemBuilder: (context, index) {
                            final commuter = commuters[index];
                            return CommuterWaitingLocationTile(
                              location: commuter,
                              dense: true,
                              driverLocation: driverLocation,
                              onTap: () {
                                Navigator.of(context).pop();
                                AppRouter.goToNotifications(context);
                              },
                            );
                          },
                        ),
                ),
                const Divider(height: 1),
                InkWell(
                  onTap: () {
                    Navigator.of(context).pop();
                    AppRouter.goToNotifications(context);
                  },
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'View All',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.primaryBlue,
                          ),
                        ),
                        SizedBox(width: 4),
                        Icon(
                          Icons.arrow_forward,
                          size: 14,
                          color: AppTheme.primaryBlue,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
