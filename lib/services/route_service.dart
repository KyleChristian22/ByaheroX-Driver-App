import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

class RouteService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static const String activeRoutesCollection = 'active_routes';

  /// IMPORTANT:
  /// Commuter app usually watches this collection for live jeepney markers.
  /// Kaya dapat dito rin naka-sync ang isOnTrip.
  static const String locationsCollection = 'locations';

  /// Minimum distance between saved route points.
  /// Helps reduce Firestore document size and map rendering load.
  static const double defaultMinPointDistanceMeters = 5.0;

  /// Firestore document limit is around 1MB, so avoid saving extremely large routes.
  static const int maxSavedRoutePoints = 2500;

  /// Saves the active route of a jeepney to Firestore.
  ///
  /// IMPORTANT:
  /// Firestore does not allow nested arrays.
  ///
  /// Do NOT save coordinates like this:
  /// [
  ///   [121.123, 14.123],
  ///   [121.456, 14.456]
  /// ]
  ///
  /// Use map/object format instead:
  /// [
  ///   {'lat': 14.123, 'lng': 121.123},
  ///   {'lat': 14.456, 'lng': 121.456}
  /// ]
  static Future<void> saveRouteToFirestore(
    String jeepneyId,
    List<LatLng> routePoints,
    String? destination, {
    String? routeId,
    String? originTerminal,
    String? destinationTerminal,
    bool isOnTrip = true,
    double minPointDistanceMeters = defaultMinPointDistanceMeters,
  }) async {
    final cleanJeepneyId = jeepneyId.trim();

    if (cleanJeepneyId.isEmpty) {
      debugPrint('[RouteService] saveRouteToFirestore: jeepneyId is empty');
      return;
    }

    final cleanRouteId = routeId?.trim() ?? '';
    final cleanOriginTerminal = originTerminal?.trim() ?? '';
    final cleanDestinationTerminal = destinationTerminal?.trim() ?? '';

    final rawDestination = destination?.trim() ?? '';
    final cleanDestination =
        rawDestination.isNotEmpty ? rawDestination : cleanDestinationTerminal;

    /// VERY IMPORTANT FIX:
    /// Even if routePoints are not yet enough to save a polyline,
    /// still update locations/{jeepneyId} so commuter app can see the driver.
    ///
    /// Screenshot issue:
    /// locations/JEEP001 had isOnTrip: false.
    ///
    /// This makes sure Start Trip / active route updates the live location doc too.
    await _syncLocationTripState(
      jeepneyId: cleanJeepneyId,
      isOnTrip: isOnTrip,
      isOnline: true,
      routeId: cleanRouteId,
      originTerminal: cleanOriginTerminal,
      destinationTerminal: cleanDestinationTerminal,
      destination: cleanDestination,
    );

    final validPoints = routePoints.where(_isValidLatLng).toList();

    if (validPoints.length < 2) {
      debugPrint(
        '[RouteService] saveRouteToFirestore: routePoints must have at least 2 valid points. '
        'Location trip state was still synced.',
      );
      return;
    }

    final simplifiedPoints = _limitRoutePoints(
      simplifyRoutePoints(
        validPoints,
        minDistanceMeters: minPointDistanceMeters,
      ),
      maxSavedRoutePoints,
    );

    if (simplifiedPoints.length < 2) {
      debugPrint(
        '[RouteService] saveRouteToFirestore: simplified route has less than 2 points. '
        'Location trip state was still synced.',
      );
      return;
    }

    /// Firestore-safe app format.
    ///
    /// This is the main format your app should read.
    final coordinates = simplifiedPoints.map((point) {
      return <String, double>{
        'lat': point.latitude,
        'lng': point.longitude,
      };
    }).toList();

    /// Firestore-safe GeoJSON-like format.
    ///
    /// Real GeoJSON uses nested arrays:
    /// coordinates: [[lng, lat], [lng, lat]]
    ///
    /// But Firestore does not support nested arrays, so we use maps instead:
    /// coordinates: [{lng: 121.123, lat: 14.123}]
    ///
    /// This keeps the lng/lat ordering idea without violating Firestore rules.
    final geoJsonSafeCoordinates = simplifiedPoints.map((point) {
      return <String, double>{
        'lng': point.longitude,
        'lat': point.latitude,
      };
    }).toList();

    final bounds = _calculateBounds(simplifiedPoints);
    final distanceMeters = calculateRouteDistance(simplifiedPoints);

    debugPrint(
      '[RouteService] Saving active route for $cleanJeepneyId. '
      'original=${routePoints.length}, '
      'valid=${validPoints.length}, '
      'saved=${simplifiedPoints.length}, '
      'isOnTrip=$isOnTrip',
    );

    try {
      await _firestore
          .collection(activeRoutesCollection)
          .doc(cleanJeepneyId)
          .set({
        'jeepneyId': cleanJeepneyId,
        'routeId': cleanRouteId,
        'originTerminal': cleanOriginTerminal,
        'destinationTerminal': cleanDestinationTerminal,
        'destination': cleanDestination,

        /// App-friendly Firestore-safe route format.
        'route': {
          'type': 'LineString',
          'format': 'lat_lng_map_list',
          'coordinates': coordinates,
        },

        /// GeoJSON-like but Firestore-safe.
        ///
        /// This is NOT strict GeoJSON because strict GeoJSON needs nested arrays.
        /// It is intentionally map-based to avoid:
        /// [cloud_firestore/unknown] Invalid data. Nested arrays are not supported.
        'geoJsonRoute': {
          'type': 'LineString',
          'format': 'lng_lat_map_list',
          'coordinates': geoJsonSafeCoordinates,
        },

        'pointCount': simplifiedPoints.length,
        'originalPointCount': routePoints.length,
        'distanceMeters': distanceMeters,
        'distanceKm': distanceMeters / 1000,
        'bounds': bounds,
        'isActive': true,
        'isOnTrip': isOnTrip,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'timestamp': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      debugPrint('[RouteService] Route saved successfully for $cleanJeepneyId');
    } catch (e, stackTrace) {
      debugPrint('[RouteService] saveRouteToFirestore error: $e');
      debugPrint('[RouteService] stackTrace: $stackTrace');
      rethrow;
    }
  }

  static Future<void> clearRouteFromFirestore(
    String jeepneyId, {
    bool deleteDocument = false,
  }) async {
    final cleanJeepneyId = jeepneyId.trim();

    if (cleanJeepneyId.isEmpty) {
      debugPrint('[RouteService] clearRouteFromFirestore: jeepneyId is empty');
      return;
    }

    debugPrint('[RouteService] Clearing route for $cleanJeepneyId');

    try {
      final docRef =
          _firestore.collection(activeRoutesCollection).doc(cleanJeepneyId);

      if (deleteDocument) {
        await docRef.delete();

        await _syncLocationTripState(
          jeepneyId: cleanJeepneyId,
          isOnTrip: false,
          isOnline: true,
          markEnded: true,
        );

        debugPrint(
          '[RouteService] Active route document deleted for $cleanJeepneyId',
        );

        return;
      }

      await docRef.set({
        'jeepneyId': cleanJeepneyId,
        'isActive': false,
        'isOnTrip': false,
        'route': FieldValue.delete(),
        'geoJsonRoute': FieldValue.delete(),
        'pointCount': 0,
        'originalPointCount': 0,
        'distanceMeters': 0,
        'distanceKm': 0,
        'bounds': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
        'clearedAt': FieldValue.serverTimestamp(),
        'timestamp': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      /// VERY IMPORTANT FIX:
      /// End Trip should also update locations/{jeepneyId}
      /// so commuter app stops showing this jeepney.
      await _syncLocationTripState(
        jeepneyId: cleanJeepneyId,
        isOnTrip: false,
        isOnline: true,
        markEnded: true,
      );

      debugPrint(
        '[RouteService] Route cleared successfully for $cleanJeepneyId',
      );
    } catch (e, stackTrace) {
      debugPrint('[RouteService] clearRouteFromFirestore error: $e');
      debugPrint('[RouteService] stackTrace: $stackTrace');
      rethrow;
    }
  }

  /// Sync trip status to locations/{jeepneyId}.
  ///
  /// This is needed because commuter app displays jeepneys from locations,
  /// not only from active_routes.
  static Future<void> _syncLocationTripState({
    required String jeepneyId,
    required bool isOnTrip,
    bool isOnline = true,
    String? routeId,
    String? originTerminal,
    String? destinationTerminal,
    String? destination,
    bool markEnded = false,
  }) async {
    final cleanJeepneyId = jeepneyId.trim();

    if (cleanJeepneyId.isEmpty) {
      debugPrint('[RouteService] _syncLocationTripState: jeepneyId is empty');
      return;
    }

    final cleanRouteId = routeId?.trim() ?? '';
    final cleanOriginTerminal = originTerminal?.trim() ?? '';
    final cleanDestinationTerminal = destinationTerminal?.trim() ?? '';
    final cleanDestination = destination?.trim() ?? '';

    final data = <String, dynamic>{
      'jeepneyId': cleanJeepneyId,
      'isOnTrip': isOnTrip,
      'onTrip': isOnTrip,
      'isOnline': isOnline,
      'online': isOnline,
      'status': isOnTrip ? 'active' : 'completed',
      'tripStatus': isOnTrip ? 'active' : 'completed',
      'updatedAt': FieldValue.serverTimestamp(),
      'timestamp': FieldValue.serverTimestamp(),
    };

    if (cleanRouteId.isNotEmpty) {
      data['routeId'] = cleanRouteId;
    }

    if (cleanOriginTerminal.isNotEmpty) {
      data['originTerminal'] = cleanOriginTerminal;
    }

    if (cleanDestinationTerminal.isNotEmpty) {
      data['destinationTerminal'] = cleanDestinationTerminal;
    }

    if (cleanDestination.isNotEmpty) {
      data['destination'] = cleanDestination;
    }

    if (isOnTrip) {
      data['tripStartedAt'] = FieldValue.serverTimestamp();
      data['tripEndedAt'] = FieldValue.delete();
      data['endedAt'] = FieldValue.delete();
    }

    if (markEnded) {
      data['tripEndedAt'] = FieldValue.serverTimestamp();
      data['endedAt'] = FieldValue.serverTimestamp();
      data['crowdStatus'] = FieldValue.delete();
    }

    try {
      await _firestore
          .collection(locationsCollection)
          .doc(cleanJeepneyId)
          .set(data, SetOptions(merge: true));

      debugPrint(
        '[RouteService] Synced locations/$cleanJeepneyId: '
        'isOnTrip=$isOnTrip, isOnline=$isOnline',
      );
    } catch (e, stackTrace) {
      debugPrint('[RouteService] _syncLocationTripState error: $e');
      debugPrint('[RouteService] stackTrace: $stackTrace');
      rethrow;
    }
  }

  static Stream<List<LatLng>?> watchActiveRoute(String jeepneyId) {
    final cleanJeepneyId = jeepneyId.trim();

    if (cleanJeepneyId.isEmpty) {
      return Stream<List<LatLng>?>.value(null);
    }

    return _firestore
        .collection(activeRoutesCollection)
        .doc(cleanJeepneyId)
        .snapshots()
        .map(parseRouteFromSnapshot);
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> watchAllActiveRoutes({
    String? routeId,
  }) {
    Query<Map<String, dynamic>> query = _firestore
        .collection(activeRoutesCollection)
        .where('isActive', isEqualTo: true);

    final cleanRouteId = routeId?.trim();

    if (cleanRouteId != null && cleanRouteId.isNotEmpty) {
      query = query.where('routeId', isEqualTo: cleanRouteId);
    }

    return query.snapshots();
  }

  static Future<List<LatLng>?> getActiveRoute(String jeepneyId) async {
    final cleanJeepneyId = jeepneyId.trim();

    if (cleanJeepneyId.isEmpty) {
      return null;
    }

    try {
      final doc = await _firestore
          .collection(activeRoutesCollection)
          .doc(cleanJeepneyId)
          .get();

      return parseRouteFromSnapshot(doc);
    } catch (e, stackTrace) {
      debugPrint('[RouteService] getActiveRoute error: $e');
      debugPrint('[RouteService] stackTrace: $stackTrace');
      return null;
    }
  }

  static List<LatLng>? parseRouteFromSnapshot(DocumentSnapshot doc) {
    try {
      if (!doc.exists) return null;

      final rawData = doc.data();

      if (rawData == null || rawData is! Map<String, dynamic>) {
        return null;
      }

      final isActive = rawData['isActive'] == true;

      if (!isActive) return null;

      final route = rawData['route'];
      final geoJsonRoute = rawData['geoJsonRoute'];

      List<dynamic>? coordinates;

      /// First priority:
      /// route.coordinates = [
      ///   {'lat': 14.123, 'lng': 121.456}
      /// ]
      if (route is Map<String, dynamic>) {
        final rawCoordinates = route['coordinates'];

        if (rawCoordinates is List && rawCoordinates.isNotEmpty) {
          coordinates = rawCoordinates;
        }
      }

      /// Second priority:
      /// geoJsonRoute.coordinates = [
      ///   {'lng': 121.456, 'lat': 14.123}
      /// ]
      ///
      /// Also supports old data if you previously saved:
      /// [[lng, lat]]
      ///
      /// Note:
      /// We support reading old nested arrays, but we no longer save nested arrays.
      if ((coordinates == null || coordinates.isEmpty) &&
          geoJsonRoute is Map<String, dynamic>) {
        final rawCoordinates = geoJsonRoute['coordinates'];

        if (rawCoordinates is List && rawCoordinates.isNotEmpty) {
          coordinates = rawCoordinates;
        }
      }

      if (coordinates == null || coordinates.isEmpty) {
        return null;
      }

      final points = <LatLng>[];

      for (final coord in coordinates) {
        final point = _parseCoordinate(coord);

        if (point != null && _isValidLatLng(point)) {
          points.add(point);
        }
      }

      if (points.length < 2) return null;

      return points;
    } catch (e, stackTrace) {
      debugPrint('[RouteService] parseRouteFromSnapshot error: $e');
      debugPrint('[RouteService] stackTrace: $stackTrace');
      return null;
    }
  }

  static LatLng? _parseCoordinate(dynamic coord) {
    try {
      /// Supported Firestore-safe format:
      /// {
      ///   "lat": 14.123,
      ///   "lng": 121.456
      /// }
      ///
      /// Also supports:
      /// {
      ///   "latitude": 14.123,
      ///   "longitude": 121.456
      /// }
      if (coord is Map<String, dynamic>) {
        final lat = _toDouble(coord['lat'] ?? coord['latitude']);
        final lng = _toDouble(coord['lng'] ?? coord['longitude']);

        if (lat != null && lng != null) {
          return LatLng(lat, lng);
        }
      }

      /// Backup support for old GeoJSON-like array format:
      /// [lng, lat]
      ///
      /// This is only for reading old/local data.
      /// Do not save this format to Firestore.
      if (coord is List && coord.length >= 2) {
        final lng = _toDouble(coord[0]);
        final lat = _toDouble(coord[1]);

        if (lat != null && lng != null) {
          return LatLng(lat, lng);
        }
      }

      return null;
    } catch (e) {
      debugPrint('[RouteService] _parseCoordinate error: $e');
      return null;
    }
  }

  static List<LatLng> simplifyRoutePoints(
    List<LatLng> points, {
    double minDistanceMeters = defaultMinPointDistanceMeters,
  }) {
    final validPoints = points.where(_isValidLatLng).toList();

    if (validPoints.length <= 2) return validPoints;

    final simplified = <LatLng>[validPoints.first];
    LatLng lastKept = validPoints.first;

    for (int i = 1; i < validPoints.length - 1; i++) {
      final current = validPoints[i];

      if (calculateDistance(lastKept, current) >= minDistanceMeters) {
        simplified.add(current);
        lastKept = current;
      }
    }

    if (simplified.last != validPoints.last) {
      simplified.add(validPoints.last);
    }

    return simplified;
  }

  static List<LatLng> _limitRoutePoints(List<LatLng> points, int maxPoints) {
    if (points.length <= maxPoints) return points;

    final limited = <LatLng>[];
    final step = points.length / maxPoints;

    for (int i = 0; i < maxPoints; i++) {
      final index = (i * step).floor().clamp(0, points.length - 1);
      limited.add(points[index]);
    }

    if (limited.isNotEmpty && limited.last != points.last) {
      limited[limited.length - 1] = points.last;
    }

    return limited;
  }

  static Map<String, double> _calculateBounds(List<LatLng> points) {
    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;

    for (final point in points) {
      minLat = math.min(minLat, point.latitude);
      maxLat = math.max(maxLat, point.latitude);
      minLng = math.min(minLng, point.longitude);
      maxLng = math.max(maxLng, point.longitude);
    }

    return {
      'minLat': minLat,
      'maxLat': maxLat,
      'minLng': minLng,
      'maxLng': maxLng,
    };
  }

  static double calculateRouteDistance(List<LatLng> points) {
    if (points.length < 2) return 0.0;

    double total = 0.0;

    for (int i = 0; i < points.length - 1; i++) {
      total += calculateDistance(points[i], points[i + 1]);
    }

    return total;
  }

  static double calculateDistance(LatLng point1, LatLng point2) {
    const earthRadius = 6371000.0;

    final dLat = _toRadians(point2.latitude - point1.latitude);
    final dLng = _toRadians(point2.longitude - point1.longitude);

    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(point1.latitude)) *
            math.cos(_toRadians(point2.latitude)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);

    final c = 2 *
        math.atan2(
          math.sqrt(a),
          math.sqrt(1 - a),
        );

    return earthRadius * c;
  }

  static bool _isValidLatLng(LatLng point) {
    final lat = point.latitude;
    final lng = point.longitude;

    if (lat.isNaN || lng.isNaN) return false;
    if (lat.isInfinite || lng.isInfinite) return false;

    /// Usually invalid placeholder location.
    if (lat == 0.0 && lng == 0.0) return false;

    return lat >= -90.0 && lat <= 90.0 && lng >= -180.0 && lng <= 180.0;
  }

  static double? _toDouble(dynamic value) {
    if (value == null) return null;

    if (value is num) {
      final result = value.toDouble();

      if (result.isNaN || result.isInfinite) return null;

      return result;
    }

    final result = double.tryParse(value.toString());

    if (result == null || result.isNaN || result.isInfinite) {
      return null;
    }

    return result;
  }

  static double _toRadians(double degrees) {
    return degrees * math.pi / 180.0;
  }
}
