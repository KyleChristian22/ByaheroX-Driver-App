import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../../services/commuter_location_service.dart';

/// ViewModel for managing commuter waiting locations in Driver app
///
/// Responsibilities:
/// - Watch active commuter locations from Firestore
/// - Calculate distances from driver's location to each commuter
/// - Notify UI to update commuter markers on the map
class CommuterLocationViewModel extends ChangeNotifier {
  List<CommuterWaitingLocation> _commuterLocations = [];
  LatLng? _driverLocation;
  StreamSubscription? _commuterLocationsSubscription;
  bool _isWatching = false;
  String? _error;

  // Getters
  List<CommuterWaitingLocation> get commuterLocations =>
      List.unmodifiable(_commuterLocations);

  bool get isWatching => _isWatching;
  String? get error => _error;
  int get activeCommuterCount => _commuterLocations.length;

  /// Get commuter locations with distance from driver's current position
  List<CommuterLocationWithDistance> get commuterLocationsWithDistance {
    if (_driverLocation == null) {
      return _commuterLocations
          .map((loc) => CommuterLocationWithDistance(
                location: loc,
                distanceKm: null,
                formattedDistance: 'Distance unknown',
              ))
          .toList();
    }

    return _commuterLocations.map((loc) {
      final distanceKm = calculateDistance(
        _driverLocation!,
        loc.location,
      );
      return CommuterLocationWithDistance(
        location: loc,
        distanceKm: distanceKm,
        formattedDistance: _formatDistance(distanceKm),
      );
    }).toList()
      ..sort((a, b) {
        // Sort by distance (null distances at the end)
        if (a.distanceKm == null && b.distanceKm == null) return 0;
        if (a.distanceKm == null) return 1;
        if (b.distanceKm == null) return -1;
        return a.distanceKm!.compareTo(b.distanceKm!);
      });
  }

  /// Start watching commuter locations from Firestore
  void startWatching() {
    if (_isWatching) return;

    _isWatching = true;
    _error = null;
    notifyListeners();

    _commuterLocationsSubscription =
        CommuterLocationService.watchActiveCommuterLocations().listen(
      (locations) {
        _commuterLocations = locations;
        _error = null;
        notifyListeners();
      },
      onError: (error) {
        _error = 'Failed to load commuter locations: $error';
        _isWatching = false;
        notifyListeners();
      },
    );
  }

  /// Stop watching commuter locations
  void stopWatching() {
    _commuterLocationsSubscription?.cancel();
    _commuterLocationsSubscription = null;
    _isWatching = false;
    notifyListeners();
  }

  /// Update driver's current location and recalculate distances
  void updateDriverLocation(double lat, double lng) {
    _driverLocation = LatLng(lat, lng);
    notifyListeners();
  }

  /// Calculate distance between two points using Haversine formula
  /// Returns distance in kilometers
  static double calculateDistance(LatLng from, LatLng to) {
    const earthRadiusKm = 6371.0;

    final lat1 = _degreesToRadians(from.latitude);
    final lat2 = _degreesToRadians(to.latitude);
    final dLat = _degreesToRadians(to.latitude - from.latitude);
    final dLon = _degreesToRadians(to.longitude - from.longitude);

    final a = (math.sin(dLat / 2) * math.sin(dLat / 2)) +
        (math.cos(lat1) *
            math.cos(lat2) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2));
    final c = 2 * math.asin(math.sqrt(a));

    return earthRadiusKm * c;
  }

  static double _degreesToRadians(double degrees) {
    return degrees * (math.pi / 180);
  }

  /// Format distance for display
  static String _formatDistance(double km) {
    if (km < 0.1) {
      return '${(km * 1000).toStringAsFixed(0)} m';
    } else if (km < 1) {
      return '${(km * 1000).toStringAsFixed(0)} m';
    } else if (km < 10) {
      return '${km.toStringAsFixed(1)} km';
    } else {
      return '${km.toStringAsFixed(0)} km';
    }
  }

  @override
  void dispose() {
    stopWatching();
    super.dispose();
  }
}

/// Wrapper class that includes distance information
class CommuterLocationWithDistance {
  final CommuterWaitingLocation location;
  final double? distanceKm;
  final String formattedDistance;

  CommuterLocationWithDistance({
    required this.location,
    required this.distanceKm,
    required this.formattedDistance,
  });
}
