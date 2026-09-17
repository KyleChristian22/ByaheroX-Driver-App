import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

/// Service for reading active route polylines from Firestore.
///
/// Expected Firestore collection:
/// active_routes/{documentId}
///
/// Recommended fields:
/// {
///   "isActive": true,
///   "isOnTrip": true, // optional fallback
///   "jeepneyId": "JEEP001",
///   "driverUid": "...",
///   "routeId": "ROUTE001",
///   "destination": "Sta.Cruz Terminal",
///   "destinationTerminal": "Sta.Cruz Terminal",
///   "route": {
///     "coordinates": [
///       {"lat": 14.123, "lng": 121.456},
///       {"lat": 14.124, "lng": 121.457}
///     ]
///   },
///   "updatedAt": Timestamp
/// }
class DriverRouteService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  static const String _collectionName = 'active_routes';

  /// Load all active driver routes.
  ///
  /// This is used by the commuter map to draw route polylines.
  /// Jeepney markers should still come from the live driver location collection,
  /// usually `locations`.
  static Future<List<DriverRouteInfo>> getActiveRoutes() async {
    try {
      final firebaseUser = _auth.currentUser;
      debugPrint(
        'DriverRouteService: Loading active routes. '
        'firebaseUid=${firebaseUser?.uid ?? 'null'}, '
        'isAnonymous=${firebaseUser?.isAnonymous ?? false}',
      );

      QuerySnapshot<Map<String, dynamic>> snapshot;

      try {
        snapshot = await _firestore
            .collection(_collectionName)
            .where('isActive', isEqualTo: true)
            .get();
      } catch (e) {
        if (e is FirebaseException && e.code == 'permission-denied') {
          debugPrint(
            'DriverRouteService: Permission denied reading active_routes. '
            'Returning empty list.',
          );
          return [];
        }

        debugPrint(
          'DriverRouteService: isActive query failed, trying fallback. Error: $e',
        );

        snapshot = await _firestore.collection(_collectionName).get();
      }

      debugPrint(
        'DriverRouteService: Found ${snapshot.docs.length} possible active route docs.',
      );

      final routes = <DriverRouteInfo>[];

      for (final doc in snapshot.docs) {
        final data = doc.data();

        final isActive = _readBool(data, [
          'isActive',
          'active',
          'isOnTrip',
          'onTrip',
        ]);

        if (!isActive) {
          debugPrint(
            'DriverRouteService: Skipped ${doc.id} because it is not active.',
          );
          continue;
        }

        final points = _extractRoutePoints(data);

        if (points.isEmpty) {
          debugPrint(
            'DriverRouteService: Skipped ${doc.id} because route points are empty.',
          );
          continue;
        }

        final routeInfo = DriverRouteInfo(
          id: doc.id,
          jeepneyId: _readString(data, [
            'jeepneyId',
            'jeepneyDocId',
            'vehicleId',
          ]),
          driverUid: _readString(data, ['driverUid', 'driverId', 'uid']),
          routeId: _readString(data, ['routeId', 'routeDocId']),
          origin: _readNullableString(data, [
            'origin',
            'originTerminal',
            'from',
          ]),
          destination: _readNullableString(data, [
            'destination',
            'destinationTerminal',
            'to',
          ]),
          points: points,
          isActive: isActive,
          updatedAt: _readTimestamp(data, [
            'updatedAt',
            'timestamp',
            'lastUpdated',
          ]),
        );

        routes.add(routeInfo);

        debugPrint(
          'DriverRouteService: Loaded active route: '
          'doc=${routeInfo.id}, '
          'jeepneyId=${routeInfo.jeepneyId}, '
          'routeId=${routeInfo.routeId}, '
          'destination=${routeInfo.destination}, '
          'points=${routeInfo.points.length}',
        );
      }

      return routes;
    } catch (e, stackTrace) {
      debugPrint('DriverRouteService: Error loading active routes: $e');
      debugPrint('DriverRouteService stackTrace: $stackTrace');
      return [];
    }
  }

  /// Optional helper kung gusto mong kumuha agad ng active routes by destination.
  static Future<List<DriverRouteInfo>> getActiveRoutesByDestination(
    String destination,
  ) async {
    final routes = await getActiveRoutes();

    return routes.where((route) {
      return _destinationMatches(route.destination, destination);
    }).toList();
  }

  /// Real-time stream of active driver routes.
  ///
  /// Replaces the 5-second polling interval for smoother polyline updates.
  static Stream<List<DriverRouteInfo>> watchActiveRoutes() {
    try {
      return _firestore
          .collection(_collectionName)
          .snapshots()
          .asyncMap((snapshot) async {
            debugPrint(
              'DriverRouteService.watchActiveRoutes: '
              'docs read=${snapshot.docs.length}',
            );

            final routes = <DriverRouteInfo>[];

            for (final doc in snapshot.docs) {
              final data = doc.data();

              final isActive = _readBool(data, [
                'isActive',
                'active',
                'isOnTrip',
                'onTrip',
              ]);

              if (!isActive) continue;

              final points = _extractRoutePoints(data);
              if (points.isEmpty) continue;

              routes.add(
                DriverRouteInfo(
                  id: doc.id,
                  jeepneyId: _readString(data, [
                    'jeepneyId',
                    'jeepneyDocId',
                    'vehicleId',
                  ]),
                  driverUid: _readString(data, [
                    'driverUid',
                    'driverId',
                    'uid',
                  ]),
                  routeId: _readString(data, ['routeId', 'routeDocId']),
                  origin: _readNullableString(data, [
                    'origin',
                    'originTerminal',
                    'from',
                  ]),
                  destination: _readNullableString(data, [
                    'destination',
                    'destinationTerminal',
                    'to',
                  ]),
                  points: points,
                  isActive: isActive,
                  updatedAt: _readTimestamp(data, [
                    'updatedAt',
                    'timestamp',
                    'lastUpdated',
                  ]),
                ),
              );
            }

            return routes;
          })
          .handleError((error) {
            debugPrint(
              'DriverRouteService.watchActiveRoutes stream error: $error',
            );
            return Stream.value(<DriverRouteInfo>[]);
          });
    } catch (e) {
      debugPrint('DriverRouteService.watchActiveRoutes error: $e');
      return Stream.value([]);
    }
  }

  /// Extract route polyline points from different possible Firestore structures.
  static List<LatLng> _extractRoutePoints(Map<String, dynamic> data) {
    dynamic rawCoordinates;

    final route = data['route'];

    if (route is Map<String, dynamic>) {
      rawCoordinates =
          route['coordinates'] ??
          route['points'] ??
          route['polyline'] ??
          route['polylinePoints'];
    }

    rawCoordinates ??=
        data['coordinates'] ??
        data['points'] ??
        data['polyline'] ??
        data['polylinePoints'];

    if (rawCoordinates is! List) {
      return [];
    }

    final points = <LatLng>[];

    for (final item in rawCoordinates) {
      final point = _parseLatLng(item);

      if (point != null && _isValidLatLng(point)) {
        points.add(point);
      }
    }

    return points;
  }

  /// Supports:
  /// { "lat": 14.1, "lng": 121.5 }
  /// { "latitude": 14.1, "longitude": 121.5 }
  /// GeoPoint
  /// [lat, lng]
  /// [lng, lat] fallback detection
  static LatLng? _parseLatLng(dynamic item) {
    try {
      if (item is GeoPoint) {
        return LatLng(item.latitude, item.longitude);
      }

      if (item is Map) {
        final latValue = item['lat'] ?? item['latitude'] ?? item['_latitude'];

        final lngValue =
            item['lng'] ??
            item['lon'] ??
            item['long'] ??
            item['longitude'] ??
            item['_longitude'];

        final lat = _toDouble(latValue);
        final lng = _toDouble(lngValue);

        if (lat == null || lng == null) return null;

        return LatLng(lat, lng);
      }

      if (item is List && item.length >= 2) {
        final first = _toDouble(item[0]);
        final second = _toDouble(item[1]);

        if (first == null || second == null) return null;

        // Normal case: [lat, lng]
        if (_isValidLatitude(first) && _isValidLongitude(second)) {
          return LatLng(first, second);
        }

        // Fallback case: [lng, lat]
        if (_isValidLongitude(first) && _isValidLatitude(second)) {
          return LatLng(second, first);
        }
      }

      return null;
    } catch (_) {
      return null;
    }
  }

  static bool _readBool(
    Map<String, dynamic> data,
    List<String> keys, {
    bool defaultValue = false,
  }) {
    var foundFalse = false;

    for (final key in keys) {
      final parsed = _toBool(data[key]);

      if (parsed == null) {
        continue;
      }

      if (parsed) {
        return true;
      }

      foundFalse = true;
    }

    return foundFalse ? false : defaultValue;
  }

  static bool? _toBool(dynamic value) {
    if (value == null) {
      return null;
    }

    if (value is bool) {
      return value;
    }

    if (value is num) {
      return value != 0;
    }

    if (value is String) {
      final normalized = value.trim().toLowerCase();

      if (normalized == 'true' ||
          normalized == 'yes' ||
          normalized == '1' ||
          normalized == 'active' ||
          normalized == 'online' ||
          normalized == 'ontrip' ||
          normalized == 'on trip' ||
          normalized == 'on_trip') {
        return true;
      }

      if (normalized == 'false' ||
          normalized == 'no' ||
          normalized == '0' ||
          normalized == 'inactive' ||
          normalized == 'offline' ||
          normalized == 'not active' ||
          normalized == 'not ontrip' ||
          normalized == 'not on trip' ||
          normalized == 'not_on_trip') {
        return false;
      }
    }

    return null;
  }

  static String _readString(
    Map<String, dynamic> data,
    List<String> keys, {
    String defaultValue = '',
  }) {
    for (final key in keys) {
      final value = data[key];

      if (value == null) continue;

      final text = value.toString().trim();

      if (text.isNotEmpty) {
        return text;
      }
    }

    return defaultValue;
  }

  static String? _readNullableString(
    Map<String, dynamic> data,
    List<String> keys,
  ) {
    final value = _readString(data, keys);

    if (value.trim().isEmpty) {
      return null;
    }

    return value;
  }

  static DateTime? _readTimestamp(
    Map<String, dynamic> data,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = data[key];

      if (value is Timestamp) {
        return value.toDate();
      }

      if (value is DateTime) {
        return value;
      }

      if (value is String) {
        final parsed = DateTime.tryParse(value);

        if (parsed != null) {
          return parsed;
        }
      }
    }

    return null;
  }

  static double? _toDouble(dynamic value) {
    if (value == null) return null;

    if (value is num) {
      return value.toDouble();
    }

    if (value is String) {
      return double.tryParse(value.trim());
    }

    return null;
  }

  static bool _isValidLatLng(LatLng point) {
    return _isValidLatitude(point.latitude) &&
        _isValidLongitude(point.longitude);
  }

  static bool _isValidLatitude(double value) {
    return value.isFinite && value >= -90 && value <= 90;
  }

  static bool _isValidLongitude(double value) {
    return value.isFinite && value >= -180 && value <= 180;
  }

  static bool _destinationMatches(String? routeDestination, String selected) {
    final routeDest = _normalizeDestination(routeDestination);
    final selectedDest = _normalizeDestination(selected);

    if (routeDest.isEmpty || selectedDest.isEmpty) {
      return false;
    }

    return routeDest == selectedDest ||
        routeDest.contains(selectedDest) ||
        selectedDest.contains(routeDest);
  }

  static String _normalizeDestination(String? value) {
    if (value == null) return '';

    final cleaned = value
        .trim()
        .toLowerCase()
        .replaceAll('.', '')
        .replaceAll('-', ' ')
        .replaceAll('_', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final key = cleaned.replaceAll(RegExp(r'[^a-z0-9]'), '');

    if (key == 'terminala' || key.contains('lucban')) {
      return 'lucban';
    }

    if (key == 'terminalb' ||
        key.contains('stacruz') ||
        key.contains('santacruz')) {
      return 'sta_cruz';
    }

    return cleaned;
  }
}

class DriverRouteInfo {
  final String id;
  final String jeepneyId;
  final String driverUid;
  final String routeId;
  final String? origin;
  final String? destination;
  final List<LatLng> points;
  final bool isActive;
  final DateTime? updatedAt;

  const DriverRouteInfo({
    required this.id,
    required this.jeepneyId,
    required this.driverUid,
    required this.routeId,
    required this.origin,
    required this.destination,
    required this.points,
    required this.isActive,
    required this.updatedAt,
  });

  bool get hasValidRoute => points.isNotEmpty;

  @override
  String toString() {
    return 'DriverRouteInfo('
        'id: $id, '
        'jeepneyId: $jeepneyId, '
        'driverUid: $driverUid, '
        'routeId: $routeId, '
        'origin: $origin, '
        'destination: $destination, '
        'points: ${points.length}, '
        'isActive: $isActive, '
        'updatedAt: $updatedAt'
        ')';
  }
}
