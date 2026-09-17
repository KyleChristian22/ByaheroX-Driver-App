import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../viewmodels/commuter_location_viewmodel.dart';
import '../../widgets/commuter_marker.dart';

/// Example integration for Driver Home Screen
///
/// This shows how to integrate commuter location viewing in the driver app.
/// Add this to your actual driver home screen.
class DriverHomeScreenWithCommuterLocations extends StatefulWidget {
  const DriverHomeScreenWithCommuterLocations({super.key});

  @override
  State<DriverHomeScreenWithCommuterLocations> createState() =>
      _DriverHomeScreenWithCommuterLocationsState();
}

class _DriverHomeScreenWithCommuterLocationsState
    extends State<DriverHomeScreenWithCommuterLocations> {
  final MapController _mapController = MapController();
  LatLng? _driverLocation;

  @override
  void initState() {
    super.initState();
    // Start watching commuter locations
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CommuterLocationViewModel>().startWatching();
    });
  }

  @override
  void dispose() {
    context.read<CommuterLocationViewModel>().stopWatching();
    super.dispose();
  }

  /// Call this whenever driver's GPS location updates
  void _onDriverLocationUpdate(double lat, double lng) {
    setState(() {
      _driverLocation = LatLng(lat, lng);
    });
    context.read<CommuterLocationViewModel>().updateDriverLocation(lat, lng);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Map
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _driverLocation ?? const LatLng(14.2793, 121.4121),
              initialZoom: 15,
              onPositionChanged: (position, hasGesture) {
                // Update driver location when map moves (for demo)
                // In real app, use GPS location updates
                if (hasGesture) {
                  final center = position.center;
                  _onDriverLocationUpdate(center.latitude, center.longitude);
                }
              },
            ),
            children: [
              // Base map tile layer
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              ),

              // Commuter waiting location markers
              Consumer<CommuterLocationViewModel>(
                builder: (context, viewModel, _) {
                  return CommuterMarkersLayer(
                    commuterLocations: viewModel.commuterLocationsWithDistance,
                    onCommuterTap: (commuterData) {
                      _showCommuterDetails(context, commuterData);
                    },
                  );
                },
              ),

              // Driver's current location marker
              if (_driverLocation != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _driverLocation!,
                      width: 50,
                      height: 50,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.blue.shade600,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                        ),
                        child: const Icon(
                          Icons.local_taxi,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),

          // Commuter count indicator
          Positioned(
            top: 60,
            right: 16,
            child: Consumer<CommuterLocationViewModel>(
              builder: (context, viewModel, _) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade600,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.person_pin,
                        color: Colors.white,
                        size: 20,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${viewModel.activeCommuterCount} waiting',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showCommuterDetails(
    BuildContext context,
    CommuterLocationWithDistance commuterData,
  ) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.person_pin,
                  color: Colors.orange.shade600,
                  size: 32,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Commuter Waiting',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        'Total: ${commuterData.formattedDistance}',
                        style: TextStyle(
                          color: Colors.orange.shade700,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (commuterData.location.destinationTerminal != null)
              _buildInfoRow(
                Icons.location_on,
                'Destination: ${commuterData.location.destinationTerminal}',
              ),
            _buildInfoRow(
              Icons.people,
              'Waiting Count: ${commuterData.location.waitingCount}',
            ),
            if (commuterData.distanceKm != null)
              _buildInfoRow(
                Icons.straighten,
                'Total Distance: ${commuterData.distanceKm!.toStringAsFixed(2)} km (Driver GPS → Commuter GPS)',
              ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  // Navigate to commuter location
                  _mapController.move(
                    commuterData.location.location,
                    18,
                  );
                  Navigator.pop(context);
                },
                icon: const Icon(Icons.navigation),
                label: const Text('Navigate to Location'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey.shade600),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: Colors.grey.shade800),
            ),
          ),
        ],
      ),
    );
  }
}
