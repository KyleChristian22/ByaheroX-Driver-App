import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart' hide Distance;
import '../../domain/entities/jeepney.dart';
import '../../domain/entities/route.dart';
import '../../core/utils/distance_calculator.dart' as utils;

class NearestJeepneyResult {
  final Jeepney jeepney;
  final double distanceKm;
  final int estimatedTimeMinutes;
  final LatLng currentLocation;

  const NearestJeepneyResult({
    required this.jeepney,
    required this.distanceKm,
    required this.estimatedTimeMinutes,
    required this.currentLocation,
  });
}

class NearestJeepneyService {
  static const double defaultRadiusKm = 5.0;
  static const int defaultTopResults = 5;
  static const double defaultAverageSpeedKmh = 20.0;

  final FirebaseFirestore _firestore;

  NearestJeepneyService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  /// Main method to find nearest jeepneys based on user location and route
  /// Returns list of nearest jeepneys sorted by distance
  Future<List<NearestJeepneyResult>> findNearestJeepneys({
    required double userLat,
    required double userLng,
    required String? routeId,
    double radiusKm = defaultRadiusKm,
    int topResults = defaultTopResults,
  }) async {
    final activeJeepneys = await _fetchActiveJeepneys();

    if (activeJeepneys.isEmpty) {
      return [];
    }

    List<Jeepney> filteredJeepneys = activeJeepneys;

    if (routeId != null && routeId.isNotEmpty) {
      filteredJeepneys = activeJeepneys
          .where((j) => j.routeId == routeId)
          .toList();
    }

    if (filteredJeepneys.isEmpty) {
      return [];
    }

    final List<NearestJeepneyResult> results = [];

    for (final jeepney in filteredJeepneys) {
      final distance = utils.DistanceCalculator.calculateDistance(
        userLat,
        userLng,
        jeepney.latitude,
        jeepney.longitude,
      );

      if (distance <= radiusKm) {
        final estimatedTime = utils.DistanceCalculator.calculateEstimatedTime(
          distance,
          speedKmh: jeepney.speed > 0 ? jeepney.speed : defaultAverageSpeedKmh,
        );

        results.add(
          NearestJeepneyResult(
            jeepney: jeepney,
            distanceKm: distance,
            estimatedTimeMinutes: estimatedTime,
            currentLocation: LatLng(jeepney.latitude, jeepney.longitude),
          ),
        );
      }
    }

    results.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));

    return results.take(topResults).toList();
  }

  /// Fetch all active jeepneys (isOnline = true AND isOnTrip = true)
  Future<List<Jeepney>> _fetchActiveJeepneys() async {
    final QuerySnapshot snapshot = await _firestore
        .collection('locations')
        .where('isOnline', isEqualTo: true)
        .where('isOnTrip', isEqualTo: true)
        .get();

    final List<Jeepney> jeepneys = [];

    for (final doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final routeId = data['routeId'] as String?;

      if (routeId == null || routeId.isEmpty) {
        continue;
      }

      final speedMps = (data['speedMps'] ?? 0.0).toDouble();
      final crowdStatusStr = data['crowdStatus'] as String? ?? 'maluwag';

      jeepneys.add(
        Jeepney(
          id: _readString(data, ['jeepneyId'], defaultValue: doc.id),
          plateNumber: _readPlateNumber(data),
          routeId: routeId,
          latitude: (data['lat'] ?? 0.0).toDouble(),
          longitude: (data['lng'] ?? 0.0).toDouble(),
          speed: speedMps * 3.6,
          crowdLevel: _crowdLevelFromStatus(crowdStatusStr),
          estimatedArrivalMinutes: 0,
          lastUpdated: data['timestamp'] != null
              ? (data['timestamp'] as Timestamp).toDate()
              : DateTime.now(),
          isActive: data['isOnTrip'] ?? false,
        ),
      );
    }

    return jeepneys;
  }

  CrowdLevel _crowdLevelFromStatus(String status) {
    switch (status.toLowerCase()) {
      case 'maluwag':
        return CrowdLevel.maliwag;
      case 'sakto':
        return CrowdLevel.sakto;
      case 'puno':
        return CrowdLevel.puno;
      default:
        return CrowdLevel.maliwag;
    }
  }

  String _readPlateNumber(Map<String, dynamic> data) {
    return _readString(data, [
      'plateNumber',
      'plate_number',
      'plateNo',
      'plate_no',
      'plate',
      'vehiclePlateNumber',
      'vehiclePlateNo',
      'vehiclePlate',
      'jeepneyPlateNumber',
      'jeepneyPlateNo',
      'bodyNumber',
    ]);
  }

  String _readString(
    Map<String, dynamic> data,
    List<String> keys, {
    String defaultValue = '',
  }) {
    for (final key in keys) {
      final value = data[key];
      if (value == null) continue;

      final text = value.toString().trim();
      if (text.isNotEmpty) return text;
    }

    return defaultValue;
  }

  /// Get available routes for filtering
  Future<List<Route>> getAvailableRoutes() async {
    final QuerySnapshot snapshot = await _firestore.collection('routes').get();

    return snapshot.docs.map((doc) {
      final data = doc.data() as Map<String, dynamic>;
      return Route(
        id: doc.id,
        name: data['name'] ?? '',
        description: data['description'] ?? '',
        stops: const [],
        polylineCoordinates: const [],
        isActive: data['isActive'] ?? true,
      );
    }).toList();
  }

  /// Stream-based method for real-time updates
  Stream<List<NearestJeepneyResult>> watchNearestJeepneys({
    required double userLat,
    required double userLng,
    required String? routeId,
    double radiusKm = defaultRadiusKm,
    int topResults = defaultTopResults,
  }) {
    return _firestore
        .collection('locations')
        .where('isOnline', isEqualTo: true)
        .where('isOnTrip', isEqualTo: true)
        .snapshots()
        .asyncMap((snapshot) async {
          final List<Jeepney> activeJeepneys = [];

          for (final doc in snapshot.docs) {
            final Map<String, dynamic> data = doc.data();
            final routeId = data['routeId'] as String?;

            if (routeId == null || routeId.isEmpty) {
              continue;
            }

            final speedMps = (data['speedMps'] ?? 0.0).toDouble();
            final crowdStatusStr = data['crowdStatus'] as String? ?? 'maluwag';

            activeJeepneys.add(
              Jeepney(
                id: _readString(data, ['jeepneyId'], defaultValue: doc.id),
                plateNumber: _readPlateNumber(data),
                routeId: routeId,
                latitude: (data['lat'] ?? 0.0).toDouble(),
                longitude: (data['lng'] ?? 0.0).toDouble(),
                speed: speedMps * 3.6,
                crowdLevel: _crowdLevelFromStatus(crowdStatusStr),
                estimatedArrivalMinutes: 0,
                lastUpdated: data['timestamp'] != null
                    ? (data['timestamp'] as Timestamp).toDate()
                    : DateTime.now(),
                isActive: data['isOnTrip'] ?? false,
              ),
            );
          }

          List<Jeepney> filteredJeepneys = activeJeepneys;
          if (routeId != null && routeId.isNotEmpty) {
            filteredJeepneys = activeJeepneys
                .where((j) => j.routeId == routeId)
                .toList();
          }

          if (filteredJeepneys.isEmpty) {
            return [];
          }

          final List<NearestJeepneyResult> results = [];

          for (final jeepney in filteredJeepneys) {
            final distance = utils.DistanceCalculator.calculateDistance(
              userLat,
              userLng,
              jeepney.latitude,
              jeepney.longitude,
            );

            if (distance <= radiusKm) {
              final estimatedTime =
                  utils.DistanceCalculator.calculateEstimatedTime(
                    distance,
                    speedKmh: jeepney.speed > 0
                        ? jeepney.speed
                        : defaultAverageSpeedKmh,
                  );

              results.add(
                NearestJeepneyResult(
                  jeepney: jeepney,
                  distanceKm: distance,
                  estimatedTimeMinutes: estimatedTime,
                  currentLocation: LatLng(jeepney.latitude, jeepney.longitude),
                ),
              );
            }
          }

          results.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));

          return results.take(topResults).toList();
        });
  }
}
