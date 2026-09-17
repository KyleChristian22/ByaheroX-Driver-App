import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../domain/entities/jeepney.dart';
import '../../domain/entities/route.dart';
import '../../domain/entities/route_stop.dart';
import '../../domain/repositories/jeepney_repository.dart';

/// Implementation of JeepneyRepository using Firebase Firestore.
///
/// Important collections used by Commuter app:
///
/// 1. locations
///    - live driver location written by Driver app
///    - used for live jeepney markers on commuter map
///
/// 2. jeepneys
///    - static jeepney data
///
/// 3. routes
///    - static route data
class JeepneyRepositoryImpl implements JeepneyRepository {
  final FirebaseFirestore _firestore;
  final Map<String, int> _capacityCache = {};
  final Map<String, String> _plateNumberCache = {};

  JeepneyRepositoryImpl({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  static const String _locationsCollection = 'locations';
  static const String _jeepneysCollection = 'jeepneys';
  static const String _routesCollection = 'routes';
  static const Duration _locationFreshnessWindow = Duration(seconds: 90);

  // Cache for routes
  List<Route>? _cachedRoutes;
  DateTime? _routesCacheTime;
  static const Duration _routesCacheDuration = Duration(minutes: 5);

  // ---------------------------------------------------------------------------
  // JEEPNEY METHODS
  // ---------------------------------------------------------------------------

  @override
  Future<List<Jeepney>> getJeepneys(String routeId) async {
    try {
      final snapshot = await _firestore.collection(_locationsCollection).get();

      debugPrint(
        'JeepneyRepositoryImpl.getJeepneys: '
        'locations docs read=${snapshot.docs.length}, routeId=$routeId',
      );

      final jeepneys = <Jeepney>[];

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final skipReason = _locationSkipReason(data);

        if (skipReason != null) {
          debugPrint('  Skipped ${doc.id}: $skipReason');
          continue;
        }
        final scheduleSkipReason = await _tripScheduleSkipReason(data);
        if (scheduleSkipReason != null) {
          debugPrint('  Skipped ${doc.id}: $scheduleSkipReason');
          continue;
        }

        if (!_sameRoute(
          _readString(data, ['routeId', 'routeDocId']),
          routeId,
        )) {
          debugPrint(
            '  Skipped ${doc.id}: route mismatch. '
            'selectedRouteId=$routeId, docRouteId=${_readString(data, ['routeId', 'routeDocId'])}',
          );
          continue;
        }

        final jeepney = _jeepneyFromLocationDoc(doc);

        if (!_hasValidCoordinates(jeepney)) {
          debugPrint(
            '  Skipped ${doc.id}: invalid coordinates '
            'lat=${jeepney.latitude}, lng=${jeepney.longitude}',
          );
          continue;
        }

        jeepneys.add(jeepney);
      }

      debugPrint(
        'JeepneyRepositoryImpl.getJeepneys: '
        'active/on-trip jeepneys after filtering=${jeepneys.length}',
      );

      return jeepneys;
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        debugPrint(
          'JeepneyRepositoryImpl.getJeepneys: '
          'Permission denied reading locations. User may not be authenticated.',
        );
        return [];
      }
      debugPrint('JeepneyRepositoryImpl.getJeepneys error: ${e.message}');
      return [];
    } catch (e, stackTrace) {
      debugPrint('JeepneyRepositoryImpl.getJeepneys error: $e');
      debugPrint('StackTrace: $stackTrace');
      return [];
    }
  }

  @override
  Future<List<Jeepney>> getAllActiveJeepneys() async {
    try {
      final snapshot = await _firestore.collection(_locationsCollection).get();

      debugPrint(
        'JeepneyRepositoryImpl.getAllActiveJeepneys: '
        'locations docs read=${snapshot.docs.length}',
      );

      final jeepneys = <Jeepney>[];

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final skipReason = _locationSkipReason(data);

        if (skipReason != null) {
          debugPrint('  Skipped ${doc.id}: $skipReason');
          continue;
        }
        final scheduleSkipReason = await _tripScheduleSkipReason(data);
        if (scheduleSkipReason != null) {
          debugPrint('  Skipped ${doc.id}: $scheduleSkipReason');
          continue;
        }

        final jeepney = _jeepneyFromLocationDoc(doc);

        if (!_hasValidCoordinates(jeepney)) {
          debugPrint(
            '  Skipped ${doc.id}: invalid coordinates '
            'lat=${jeepney.latitude}, lng=${jeepney.longitude}',
          );
          continue;
        }

        jeepneys.add(jeepney);
      }

      debugPrint(
        'JeepneyRepositoryImpl.getAllActiveJeepneys: '
        'active/on-trip jeepneys after filtering=${jeepneys.length}',
      );

      await _fillMissingStaticJeepneyData(jeepneys);

      for (final jeepney in jeepneys) {
        debugPrint(
          '  Active jeepney: '
          'id=${jeepney.id}, '
          'plate=${jeepney.plateNumber}, '
          'routeId=${jeepney.routeId}, '
          'destination=${jeepney.destinationTerminal}, '
          'lat=${jeepney.latitude}, '
          'lng=${jeepney.longitude}, '
          'isActive=${jeepney.isActive}, '
          'maxCapacity=${jeepney.maxCapacity}',
        );
      }

      return jeepneys;
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        debugPrint(
          'JeepneyRepositoryImpl.getAllActiveJeepneys: '
          'Permission denied reading locations. User may not be authenticated.',
        );
        return [];
      }
      debugPrint('JeepneyRepositoryImpl.getAllActiveJeepneys error: ${e.message}');
      return [];
    } catch (e, stackTrace) {
      debugPrint('JeepneyRepositoryImpl.getAllActiveJeepneys error: $e');
      debugPrint('StackTrace: $stackTrace');
      return [];
    }
  }

  @override
  Stream<List<Jeepney>> watchAllActiveJeepneys() {
    return watchActiveJeepneyLocations();
  }

  /// Watch active jeepneys with real-time location from Driver app.
  ///
  /// Reads from:
  /// locations/{jeepneyId}
  ///
  /// This is the most important method for showing jeepney markers
  /// on the Commuter map.
  Stream<List<Jeepney>> watchActiveJeepneyLocations() {
    try {
      debugPrint('JeepneyRepositoryImpl: Watching locations collection...');

      return _firestore
          .collection(_locationsCollection)
          .snapshots()
          .asyncMap((snapshot) async {
            debugPrint(
              'JeepneyRepositoryImpl.watchActiveJeepneyLocations: '
              'locations docs read=${snapshot.docs.length}',
            );

            final jeepneys = <Jeepney>[];

            for (final doc in snapshot.docs) {
              final data = doc.data();

              debugPrint('  Location doc ${doc.id}: $data');

              final skipReason = _locationSkipReason(data);

              if (skipReason != null) {
                debugPrint('  Skipped ${doc.id}: $skipReason');
                continue;
              }
              final scheduleSkipReason = await _tripScheduleSkipReason(data);
              if (scheduleSkipReason != null) {
                debugPrint('  Skipped ${doc.id}: $scheduleSkipReason');
                continue;
              }

              final jeepney = _jeepneyFromLocationDoc(doc);

              if (!_hasValidCoordinates(jeepney)) {
                debugPrint(
                  '  Skipped ${doc.id}: invalid coordinates '
                  'lat=${jeepney.latitude}, lng=${jeepney.longitude}',
                );
                continue;
              }

              jeepneys.add(jeepney);
            }

            await _fillMissingStaticJeepneyData(jeepneys);

            debugPrint(
              'JeepneyRepositoryImpl.watchActiveJeepneyLocations: '
              'active/on-trip jeepneys after filtering=${jeepneys.length}',
            );

            return jeepneys;
          })
          .transform(
            StreamTransformer<List<Jeepney>, List<Jeepney>>.fromHandlers(
              handleError: (error, stackTrace, sink) {
                debugPrint(
                  'JeepneyRepositoryImpl.watchActiveJeepneyLocations stream error: '
                  '$error',
                );

                if (error is FirebaseException &&
                    error.code == 'permission-denied') {
                  debugPrint(
                    'JeepneyRepositoryImpl.watchActiveJeepneyLocations: '
                    'Permission denied for stream. User may need to re-authenticate.',
                  );
                  sink.add(<Jeepney>[]);
                  return;
                }

                debugPrint('StackTrace: $stackTrace');
                sink.addError(error, stackTrace);
              },
            ),
          );
    } catch (e, stackTrace) {
      debugPrint('JeepneyRepositoryImpl.watchActiveJeepneyLocations error: $e');
      debugPrint('StackTrace: $stackTrace');
      return Stream.value([]);
    }
  }

  @override
  Stream<List<Jeepney>> watchJeepneys(String routeId) {
    try {
      return watchActiveJeepneyLocations().map((jeepneys) {
        final filtered = jeepneys.where((jeepney) {
          return _sameRoute(jeepney.routeId, routeId);
        }).toList();

        debugPrint(
          'JeepneyRepositoryImpl.watchJeepneys: '
          'routeId=$routeId, count=${filtered.length}',
        );

        return filtered;
      });
    } catch (e, stackTrace) {
      debugPrint('JeepneyRepositoryImpl.watchJeepneys error: $e');
      debugPrint('StackTrace: $stackTrace');
      return Stream.value([]);
    }
  }

  @override
  Future<Jeepney?> getJeepneyById(String jeepneyId) async {
    try {
      // First attempt: locations/{jeepneyId}
      final directDoc = await _firestore
          .collection(_locationsCollection)
          .doc(jeepneyId)
          .get();

      if (directDoc.exists && directDoc.data() != null) {
        final data = directDoc.data()!;

        if (!_isActiveLocationData(data)) {
          final skipReason = _locationSkipReason(data);
          debugPrint(
            'JeepneyRepositoryImpl.getJeepneyById: '
            '$jeepneyId skipped: ${skipReason ?? 'not active/on-trip'}.',
          );
          return null;
        }
        final scheduleSkipReason = await _tripScheduleSkipReason(data);
        if (scheduleSkipReason != null) {
          debugPrint(
            'JeepneyRepositoryImpl.getJeepneyById: '
            '$jeepneyId skipped: $scheduleSkipReason.',
          );
          return null;
        }

        final jeepney = _jeepneyFromLocationDoc(directDoc);

        if (_hasValidCoordinates(jeepney)) {
          return jeepney;
        }

        return null;
      }

      // Second attempt: find by jeepneyId field
      final querySnapshot = await _firestore
          .collection(_locationsCollection)
          .where('jeepneyId', isEqualTo: jeepneyId)
          .limit(1)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        final doc = querySnapshot.docs.first;
        final data = doc.data();

        if (!_isActiveLocationData(data)) {
          final skipReason = _locationSkipReason(data);
          debugPrint(
            'JeepneyRepositoryImpl.getJeepneyById: '
            '${doc.id} skipped: ${skipReason ?? 'not active/on-trip'}.',
          );
          return null;
        }
        final scheduleSkipReason = await _tripScheduleSkipReason(data);
        if (scheduleSkipReason != null) {
          debugPrint(
            'JeepneyRepositoryImpl.getJeepneyById: '
            '${doc.id} skipped: $scheduleSkipReason.',
          );
          return null;
        }

        final jeepney = _jeepneyFromLocationDoc(doc);

        if (_hasValidCoordinates(jeepney)) {
          return jeepney;
        }
      }

      return null;
    } catch (e, stackTrace) {
      debugPrint('JeepneyRepositoryImpl.getJeepneyById error: $e');
      debugPrint('StackTrace: $stackTrace');
      return null;
    }
  }

  Future<Jeepney?> getJeepneyStaticData(String jeepneyId) async {
    try {
      final doc = await _firestore
          .collection(_jeepneysCollection)
          .doc(jeepneyId)
          .get();

      if (doc.exists && doc.data() != null) {
        return _jeepneyFromStaticDoc(doc);
      }

      return null;
    } catch (e, stackTrace) {
      debugPrint('JeepneyRepositoryImpl.getJeepneyStaticData error: $e');
      debugPrint('StackTrace: $stackTrace');
      return null;
    }
  }

  @override
  Future<List<Jeepney>> getJeepneysNearLocation(
    double latitude,
    double longitude,
    double radiusKm,
  ) async {
    try {
      final jeepneys = await getAllActiveJeepneys();

      final nearbyJeepneys = jeepneys.where((jeepney) {
        final distanceKm = _calculateDistanceKm(
          latitude,
          longitude,
          jeepney.latitude,
          jeepney.longitude,
        );

        return distanceKm <= radiusKm;
      }).toList();

      debugPrint(
        'JeepneyRepositoryImpl.getJeepneysNearLocation: '
        'nearby count=${nearbyJeepneys.length}',
      );

      return nearbyJeepneys;
    } catch (e, stackTrace) {
      debugPrint('JeepneyRepositoryImpl.getJeepneysNearLocation error: $e');
      debugPrint('StackTrace: $stackTrace');
      return [];
    }
  }

  @override
  Future<void> refreshJeepneys(String routeId) async {
    // Firestore snapshots are realtime.
    // This method is kept for interface compatibility.
  }

  // ---------------------------------------------------------------------------
  // ROUTE METHODS
  // ---------------------------------------------------------------------------

  Future<List<Route>> getRoutes() async {
    if (_cachedRoutes != null &&
        _routesCacheTime != null &&
        DateTime.now().difference(_routesCacheTime!) < _routesCacheDuration) {
      return _cachedRoutes!;
    }

    try {
      final snapshot = await _firestore
          .collection(_routesCollection)
          .where('isActive', isEqualTo: true)
          .get();

      final routes = snapshot.docs.map(_routeFromFirestore).toList();

      _cachedRoutes = routes;
      _routesCacheTime = DateTime.now();

      debugPrint('JeepneyRepositoryImpl.getRoutes: count=${routes.length}');

      return routes;
    } catch (e, stackTrace) {
      debugPrint('JeepneyRepositoryImpl.getRoutes error: $e');
      debugPrint('StackTrace: $stackTrace');
      return [];
    }
  }

  Future<Route?> getRouteById(String routeId) async {
    try {
      final doc = await _firestore
          .collection(_routesCollection)
          .doc(routeId)
          .get();

      if (doc.exists && doc.data() != null) {
        return _routeFromFirestore(doc);
      }

      return null;
    } catch (e, stackTrace) {
      debugPrint('JeepneyRepositoryImpl.getRouteById error: $e');
      debugPrint('StackTrace: $stackTrace');
      return null;
    }
  }

  Future<Route?> getMainRoute() async {
    try {
      final snapshot = await _firestore
          .collection(_routesCollection)
          .where('isActive', isEqualTo: true)
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty) {
        return _routeFromFirestore(snapshot.docs.first);
      }

      return null;
    } catch (e, stackTrace) {
      debugPrint('JeepneyRepositoryImpl.getMainRoute error: $e');
      debugPrint('StackTrace: $stackTrace');
      return null;
    }
  }

  Future<List<Route>> searchRoutes(String query) async {
    final routes = await getRoutes();
    final normalizedQuery = query.trim().toLowerCase();

    if (normalizedQuery.isEmpty) {
      return routes;
    }

    return routes.where((route) {
      return route.name.toLowerCase().contains(normalizedQuery) ||
          route.description.toLowerCase().contains(normalizedQuery);
    }).toList();
  }

  Future<List<Route>> getFavoriteRoutes(List<String> routeIds) async {
    final routes = await getRoutes();
    return routes.where((route) => routeIds.contains(route.id)).toList();
  }

  Future<void> addToFavorites(String routeId) async {
    // Handled by AuthRepository.
  }

  Future<void> removeFromFavorites(String routeId) async {
    // Handled by AuthRepository.
  }

  // ---------------------------------------------------------------------------
  // FIRESTORE TO ENTITY MAPPERS
  // ---------------------------------------------------------------------------

  /// Converts live driver location document into Jeepney entity.
  ///
  /// This mapper is based on your Firestore screenshot:
  ///
  /// locations/JEEP001
  /// {
  ///   crowdStatus: "sakto",
  ///   destinationTerminal: "Sta.Cruz Terminal",
  ///   driverDocId: "DRV001",
  ///   driverEmail: "...",
  ///   driverUid: "...",
  ///   heading: "...",
  ///   isOnTrip: true,
  ///   isOnline: true,
  ///   jeepneyId: "JEEP001",
  ///   lat: 14.2730,
  ///   lng: 121.4031,
  ///   originTerminal: "Lucban Terminal",
  ///   routeId: "ROUTE001",
  ///   speedMps: 3,
  ///   timestamp: Timestamp,
  ///   updatedAt: Timestamp
  /// }
  Jeepney _jeepneyFromLocationDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};

    final jeepneyId = _readString(data, [
      'jeepneyId',
      'jeepneyDocId',
      'vehicleId',
      'vehicleDocId',
    ], defaultValue: doc.id);

    final plateNumber = _readString(data, [
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

    final latitude = _readDouble(data, [
      'lat',
      'latitude',
      '_latitude',
    ], defaultValue: 0.0);

    final longitude = _readDouble(data, [
      'lng',
      'lon',
      'long',
      'longitude',
      '_longitude',
    ], defaultValue: 0.0);

    final speedKmh = _readSpeedKmh(data);

    final passengerCount = _readInt(data, [
      'passengerCount',
      'currentPassengerCount',
      'currentPassengers',
      'passengers',
    ], defaultValue: 0);
    final maxCapacity = _readInt(data, [
      'maxCapacity',
      'capacity',
      'seatingCapacity',
      'maxPassengers',
    ], defaultValue: 0);

    final lastUpdated = _readDateTime(data, [
      'locationUpdatedAt',
      'updatedAt',
      'timestamp',
      'lastUpdated',
      'lastLocationUpdate',
    ], defaultValue: DateTime.now());

    final isActive = _isActiveLocationData(data);

    return Jeepney(
      id: jeepneyId,
      plateNumber: plateNumber,
      routeId: _readString(data, ['routeId', 'routeDocId']),
      latitude: latitude,
      longitude: longitude,
      speed: speedKmh,
      crowdLevel: _crowdLevelFromPassengerCount(passengerCount, maxCapacity),
      estimatedArrivalMinutes: _readInt(data, [
        'estimatedArrivalMinutes',
        'etaMinutes',
        'eta',
      ], defaultValue: 0),
      lastUpdated: lastUpdated,
      isActive: isActive,
      originTerminal: _readNullableString(data, [
        'originTerminal',
        'origin',
        'from',
      ]),
      destinationTerminal: _readNullableString(data, [
        'destinationTerminal',
        'destination',
        'to',
      ]),
      driverName: _readDriverName(data),
      passengerCount: passengerCount,
      maxCapacity: maxCapacity,
      scheduleTime: _readNullableString(data, [
        'scheduleTime',
        'departureTime',
        'tripTime',
      ]),
      scheduledAt: _readNullableDateTime(data, ['scheduledAt', 'departureAt']),
    );
  }

  /// Converts static jeepney document into Jeepney entity.
  Jeepney _jeepneyFromStaticDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};

    final lastUpdated = _readDateTime(data, [
      'lastUpdated',
      'updatedAt',
      'timestamp',
    ], defaultValue: DateTime.now());

    return Jeepney(
      id: doc.id,
      plateNumber: _readString(data, [
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
      ]),
      routeId: _readString(data, ['routeId', 'routeDocId']),
      latitude: _readDouble(data, ['latitude', 'lat'], defaultValue: 0.0),
      longitude: _readDouble(data, ['longitude', 'lng'], defaultValue: 0.0),
      speed: _readDouble(data, ['speedKmh', 'speed'], defaultValue: 0.0),
      crowdLevel: _crowdLevelFromString(
        _readString(data, ['crowdLevel', 'crowdStatus'], defaultValue: 'sakto'),
      ),
      estimatedArrivalMinutes: _readInt(data, [
        'estimatedArrivalMinutes',
        'etaMinutes',
      ], defaultValue: 0),
      lastUpdated: lastUpdated,
      isActive: _readBool(data, [
        'isActive',
        'active',
        'isOnTrip',
      ], defaultValue: true),
      originTerminal: _readNullableString(data, [
        'originTerminal',
        'origin',
        'from',
      ]),
      destinationTerminal: _readNullableString(data, [
        'destinationTerminal',
        'destination',
        'to',
      ]),
      maxCapacity: _readInt(data, [
        'capacity',
        'seatingCapacity',
        'maxCapacity',
        'maxPassengers',
      ], defaultValue: 0),
    );
  }

  Route _routeFromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};

    final stopsList = data['stops'] as List<dynamic>? ?? [];

    final stops = stopsList.map((item) {
      final stopMap = _asMap(item);

      return RouteStop(
        id: _readString(stopMap, ['id']),
        name: _readString(stopMap, ['name']),
        latitude: _readDouble(stopMap, ['latitude', 'lat'], defaultValue: 0.0),
        longitude: _readDouble(stopMap, [
          'longitude',
          'lng',
        ], defaultValue: 0.0),
        sequence: _readInt(stopMap, ['sequence', 'order'], defaultValue: 0),
      );
    }).toList();

    final polylineRaw =
        data['polylineCoordinates'] ??
        data['coordinates'] ??
        data['points'] ??
        data['polyline'];

    final polylineCoordinates = _parseRouteCoordinates(polylineRaw);

    return Route(
      id: doc.id,
      name: _readString(data, ['name', 'routeName'], defaultValue: doc.id),
      description: _readString(data, ['description']),
      stops: stops,
      polylineCoordinates: polylineCoordinates,
      isActive: _readBool(data, ['isActive', 'active'], defaultValue: true),
    );
  }

  List<RouteCoordinate> _parseRouteCoordinates(dynamic raw) {
    if (raw is! List) {
      return [];
    }

    final coordinates = <RouteCoordinate>[];

    for (final item in raw) {
      if (item is GeoPoint) {
        coordinates.add(
          RouteCoordinate(latitude: item.latitude, longitude: item.longitude),
        );
        continue;
      }

      if (item is List && item.length >= 2) {
        final first = _toDouble(item[0]);
        final second = _toDouble(item[1]);

        if (first == null || second == null) {
          continue;
        }

        // Normal case: [lat, lng]
        if (_isValidLatitude(first) && _isValidLongitude(second)) {
          coordinates.add(RouteCoordinate(latitude: first, longitude: second));
          continue;
        }

        // Fallback case: [lng, lat]
        if (_isValidLongitude(first) && _isValidLatitude(second)) {
          coordinates.add(RouteCoordinate(latitude: second, longitude: first));
          continue;
        }
      }

      final map = _asMap(item);

      if (map.isEmpty) {
        continue;
      }

      final lat = _readDouble(map, [
        'latitude',
        'lat',
        '_latitude',
      ], defaultValue: double.nan);

      final lng = _readDouble(map, [
        'longitude',
        'lng',
        'lon',
        '_longitude',
      ], defaultValue: double.nan);

      if (_isValidLatitude(lat) && _isValidLongitude(lng)) {
        coordinates.add(RouteCoordinate(latitude: lat, longitude: lng));
      }
    }

    return coordinates;
  }

  // ---------------------------------------------------------------------------
  // DATA VALIDATION / NORMALIZATION
  // ---------------------------------------------------------------------------

  bool _isActiveLocationData(Map<String, dynamic> data) {
    return _locationSkipReason(data) == null;
  }

  String? _locationSkipReason(Map<String, dynamic> data) {
    final isOnTrip = _readBool(data, [
      'isOnTrip',
      'onTrip',
    ], defaultValue: false);

    final scheduledVisible = _isScheduledVisible(data);

    if (!isOnTrip && !scheduledVisible) {
      return 'not onTrip (isOnTrip/onTrip is not true)';
    }

    if (!_hasAssignedDriver(data)) {
      return 'missing assigned driver';
    }

    final scheduledAt = _scheduleDateTime(data);
    if (scheduledAt != null &&
        DateTime.now().isAfter(scheduledAt.add(const Duration(hours: 3)))) {
      return 'location passed its trip window';
    }

    final isOnline = _readBool(data, [
      'isOnline',
      'online',
    ], defaultValue: false);

    if (!isOnline && !scheduledVisible) {
      return 'offline (isOnline/online is not true)';
    }

    final lat = _readNullableDouble(data, ['lat', 'latitude', '_latitude']);

    final lng = _readNullableDouble(data, [
      'lng',
      'longitude',
      'lon',
      'long',
      '_longitude',
    ]);

    if (lat == null || lng == null) {
      return 'invalid coordinates (lat/lng missing or not numeric)';
    }

    if (!_isValidLatitude(lat) || !_isValidLongitude(lng)) {
      return 'invalid coordinates lat=$lat, lng=$lng';
    }

    if (lat == 0 && lng == 0) {
      return 'invalid coordinates lat=0, lng=0';
    }

    if (isOnTrip) {
      final locationUpdatedAt = _readNullableDateTime(data, [
        'locationUpdatedAt',
        'timestamp',
      ]);
      if (locationUpdatedAt == null) {
        return 'missing live location timestamp';
      }
      if (DateTime.now().difference(locationUpdatedAt) >
          _locationFreshnessWindow) {
        return 'stale location update';
      }
    }

    return null;
  }

  bool _hasAssignedDriver(Map<String, dynamic> data) {
    return _readString(data, [
      'driverId',
      'assignedDriver',
      'assignedDriverId',
      'driverDocId',
      'driverUid',
      'uid',
    ]).isNotEmpty;
  }

  Future<String?> _tripScheduleSkipReason(Map<String, dynamic> data) async {
    final tripScheduleId = _readString(data, [
      'tripScheduleId',
      'scheduleId',
      'tripId',
    ]).trim();

    try {
      if (tripScheduleId.isNotEmpty) {
        final scheduleDoc = await _firestore
            .collection('trip_schedules')
            .doc(tripScheduleId)
            .get();
        final schedule = scheduleDoc.data();
        final skipReason = _scheduleSkipReason(schedule);
        if (skipReason != null) return skipReason;
      }

      final jeepneyId = _readString(data, ['jeepneyId', 'vehicleId']).trim();
      final scheduleDate = _readString(data, [
        'scheduleDate',
        'tripDate',
      ], defaultValue: _todayDateKey()).trim();

      if (jeepneyId.isEmpty || scheduleDate.isEmpty) return null;

      final scheduleSnapshot = await _firestore
          .collection('trip_schedules')
          .where('jeepneyId', isEqualTo: jeepneyId)
          .where('scheduleDate', isEqualTo: scheduleDate)
          .get();

      for (final doc in scheduleSnapshot.docs) {
        final schedule = doc.data();
        if (!_sameScheduleTime(data, schedule)) continue;

        final skipReason = _scheduleSkipReason(schedule);
        if (skipReason != null) return skipReason;
      }

      return null;
    } catch (error) {
      debugPrint(
        'JeepneyRepositoryImpl: could not verify trip schedule: $error',
      );
      return 'trip schedule verification failed';
    }
  }

  String? _scheduleSkipReason(Map<String, dynamic>? schedule) {
    if (schedule == null) return null;

    final status = _readString(schedule, [
      'status',
      'tripStatus',
      'historyStatus',
    ]).trim().toLowerCase();

    if (status == 'completed' || status == 'done' || status == 'finished') {
      return 'linked trip schedule is done';
    }

    final endedAt = _readNullableDateTime(schedule, ['tripEndedAt', 'endedAt']);
    if (endedAt != null) {
      return 'linked trip schedule has ended';
    }

    final scheduledAt = _scheduleDateTime(schedule);
    if (scheduledAt != null &&
        DateTime.now().isAfter(scheduledAt.add(const Duration(hours: 3)))) {
      return 'linked trip schedule passed its trip window';
    }

    return null;
  }

  bool _sameScheduleTime(
    Map<String, dynamic> locationData,
    Map<String, dynamic> scheduleData,
  ) {
    final locationTime = _scheduleDateTime(locationData);
    final scheduleTime = _scheduleDateTime(scheduleData);
    if (locationTime != null && scheduleTime != null) {
      return locationTime.isAtSameMomentAs(scheduleTime);
    }

    final locationLabel = _normalizeText(
      _readString(locationData, ['scheduleTime', 'departureTime', 'tripTime']),
    );
    final scheduleLabel = _normalizeText(
      _readString(scheduleData, ['scheduleTime', 'departureTime', 'tripTime']),
    );

    return locationLabel.isNotEmpty && locationLabel == scheduleLabel;
  }

  DateTime? _scheduleDateTime(Map<String, dynamic> data) {
    final scheduledAt = _readNullableDateTime(data, [
      'scheduledAt',
      'departureAt',
    ]);
    if (scheduledAt != null) return scheduledAt;

    final scheduleDate = _readString(data, [
      'scheduleDate',
      'tripDate',
    ], defaultValue: _todayDateKey());
    final scheduleTime = _readString(data, [
      'scheduleTime',
      'departureTime',
      'tripTime',
    ]);
    final dateMatch = RegExp(
      r'^(\d{4})-(\d{2})-(\d{2})$',
    ).firstMatch(scheduleDate);
    final time = _parseScheduleTimeOfDay(scheduleTime);
    if (dateMatch == null || time == null) return null;

    return DateTime(
      int.parse(dateMatch.group(1)!),
      int.parse(dateMatch.group(2)!),
      int.parse(dateMatch.group(3)!),
      time[0],
      time[1],
    );
  }

  List<int>? _parseScheduleTimeOfDay(String value) {
    final normalized = value.trim().toUpperCase();
    if (normalized.isEmpty) return null;

    final twelveHourMatch = RegExp(
      r'^(\d{1,2}):(\d{2})\s*(AM|PM)$',
    ).firstMatch(normalized);
    if (twelveHourMatch != null) {
      var hour = int.parse(twelveHourMatch.group(1)!);
      final minute = int.parse(twelveHourMatch.group(2)!);
      final period = twelveHourMatch.group(3)!;
      if (hour < 1 || hour > 12 || minute > 59) return null;
      if (period == 'AM' && hour == 12) hour = 0;
      if (period == 'PM' && hour != 12) hour += 12;
      return [hour, minute];
    }

    final twentyFourHourMatch = RegExp(
      r'^(\d{1,2}):(\d{2})$',
    ).firstMatch(normalized);
    if (twentyFourHourMatch != null) {
      final hour = int.parse(twentyFourHourMatch.group(1)!);
      final minute = int.parse(twentyFourHourMatch.group(2)!);
      if (hour > 23 || minute > 59) return null;
      return [hour, minute];
    }

    return null;
  }

  String _todayDateKey() {
    final now = DateTime.now();
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    return '${now.year}-$month-$day';
  }

  bool _isScheduledVisible(Map<String, dynamic> data) {
    final hasScheduleVisibility = _readBool(data, [
      'scheduledVisible',
      'visibleFromSchedule',
    ], defaultValue: false);

    if (!hasScheduleVisibility) {
      return false;
    }

    final scheduledAt = _readNullableDateTime(data, [
      'scheduledAt',
      'departureAt',
    ]);
    if (scheduledAt == null) {
      return false;
    }

    if (_isEndedTripLocation(data, scheduledAt: scheduledAt)) {
      return false;
    }

    final now = DateTime.now();
    return !now.isBefore(scheduledAt) &&
        now.difference(scheduledAt) <= const Duration(hours: 3);
  }

  bool _isEndedTripLocation(
    Map<String, dynamic> data, {
    DateTime? scheduledAt,
  }) {
    final status = _readString(data, [
      'status',
      'tripStatus',
    ]).trim().toLowerCase();

    final endedAt = _readNullableDateTime(data, ['tripEndedAt', 'endedAt']);
    if (status == 'completed' || status == 'done' || status == 'finished') {
      if (endedAt != null &&
          scheduledAt != null &&
          scheduledAt.isAfter(endedAt)) {
        return false;
      }
      return true;
    }
    if (endedAt == null) return false;
    if (scheduledAt != null && scheduledAt.isAfter(endedAt)) return false;
    return true;
  }

  bool _hasValidCoordinates(Jeepney jeepney) {
    final lat = jeepney.latitude;
    final lng = jeepney.longitude;

    return _isValidLatitude(lat) &&
        _isValidLongitude(lng) &&
        !(lat == 0 && lng == 0);
  }

  bool _isValidLatitude(double value) {
    return value.isFinite && value >= -90 && value <= 90;
  }

  bool _isValidLongitude(double value) {
    return value.isFinite && value >= -180 && value <= 180;
  }

  bool _sameRoute(String? value, String? routeId) {
    final a = _normalizeText(value);
    final b = _normalizeText(routeId);

    if (b.isEmpty) {
      return true;
    }

    return a == b;
  }

  String _normalizeText(String? value) {
    if (value == null) return '';

    return value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[\s\-_]+'), '')
        .replaceAll(RegExp(r'[^\w]'), '');
  }

  CrowdLevel _crowdLevelFromString(String? value) {
    final normalized = value?.trim().toLowerCase() ?? '';

    switch (normalized) {
      case 'maluwag':
      case 'maliwag':
      case 'available':
      case 'light':
      case 'low':
        return CrowdLevel.maliwag;

      case 'sakto':
      case 'moderate':
      case 'medium':
      case 'normal':
        return CrowdLevel.sakto;

      case 'puno':
      case 'full':
      case 'high':
      case 'crowded':
        return CrowdLevel.puno;

      default:
        return CrowdLevel.sakto;
    }
  }

  CrowdLevel _crowdLevelFromPassengerCount(
    int passengerCount,
    int maxCapacity,
  ) {
    final safeCount = passengerCount < 0 ? 0 : passengerCount;
    if (maxCapacity > 0 && safeCount >= maxCapacity) {
      return CrowdLevel.puno;
    }
    if (safeCount >= 18) return CrowdLevel.puno;
    if (safeCount >= 9) return CrowdLevel.sakto;
    return CrowdLevel.maliwag;
  }

  double _readSpeedKmh(Map<String, dynamic> data) {
    final speedKmh = _readNullableDouble(data, [
      'speedKmh',
      'speedKmH',
      'speedKilometersPerHour',
    ]);

    if (speedKmh != null) {
      return speedKmh;
    }

    final genericSpeed = _readNullableDouble(data, ['speed']);

    if (genericSpeed != null) {
      return genericSpeed;
    }

    final speedMps = _readNullableDouble(data, [
      'speedMps',
      'speedMetersPerSecond',
    ]);

    if (speedMps != null) {
      return speedMps * 3.6;
    }

    return 0.0;
  }

  // ---------------------------------------------------------------------------
  // SAFE READ HELPERS
  // ---------------------------------------------------------------------------

  String _readString(
    Map<String, dynamic> data,
    List<String> keys, {
    String defaultValue = '',
  }) {
    for (final key in keys) {
      final value = data[key];

      if (value == null) {
        continue;
      }

      final text = value.toString().trim();

      if (text.isNotEmpty) {
        return text;
      }
    }

    return defaultValue;
  }

  String? _readNullableString(Map<String, dynamic> data, List<String> keys) {
    final text = _readString(data, keys);

    if (text.trim().isEmpty) {
      return null;
    }

    return text;
  }

  String? _readDriverName(Map<String, dynamic> data) {
    final name = _readNullableString(data, [
      'driverName',
      'driverFullName',
      'assignedDriverName',
      'driverDisplayName',
    ]);
    if (name != null) return name;

    final email = _readNullableString(data, ['driverEmail', 'email']);
    if (email != null) {
      final atIndex = email.indexOf('@');
      if (atIndex > 0) {
        final derived = email.substring(0, atIndex);
        return derived[0].toUpperCase() + derived.substring(1);
      }
      return email;
    }

    return null;
  }

  Future<void> _fillMissingStaticJeepneyData(List<Jeepney> jeepneys) async {
    final missing = jeepneys
        .where((j) => j.maxCapacity <= 0 || _isMissingPlateNumber(j))
        .toList();
    if (missing.isEmpty) return;

    final idsToFetch = <String>{};
    for (final j in missing) {
      if (!_capacityCache.containsKey(j.id) ||
          !_plateNumberCache.containsKey(j.id)) {
        idsToFetch.add(j.id);
      }
    }

    if (idsToFetch.isNotEmpty) {
      for (final jeepneyId in idsToFetch) {
        int cap = 0;
        String plateNumber = '';
        String foundIn = 'none';
        for (final col in ['jeeps', _jeepneysCollection]) {
          try {
            final doc = await _firestore.collection(col).doc(jeepneyId).get();
            if (doc.exists) {
              foundIn = col;
              final data = doc.data()!;
              debugPrint('JeepneyRepositoryImpl: $col/$jeepneyId data=$data');
              cap = _readInt(data, [
                'capacity',
                'seatingCapacity',
                'maxCapacity',
                'maxPassengers',
              ], defaultValue: 0);
              plateNumber = _readString(data, [
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
              if (cap > 0 && plateNumber.isNotEmpty) break;
            } else {
              debugPrint(
                'JeepneyRepositoryImpl: $col/$jeepneyId does NOT exist',
              );
            }
          } catch (e) {
            debugPrint(
              'JeepneyRepositoryImpl: error reading $col/$jeepneyId: $e',
            );
          }
        }
        debugPrint(
          'JeepneyRepositoryImpl._fillMissingStaticJeepneyData: '
          'jeepneyId=$jeepneyId, capacity=$cap, plate=$plateNumber, '
          'foundIn=$foundIn',
        );
        _capacityCache[jeepneyId] = cap;
        _plateNumberCache[jeepneyId] = plateNumber;
      }
    }

    for (int i = 0; i < jeepneys.length; i++) {
      final j = jeepneys[i];
      final cachedCapacity = _capacityCache[j.id] ?? 0;
      final cachedPlate = _plateNumberCache[j.id] ?? '';
      final updatesCapacity = j.maxCapacity <= 0 && cachedCapacity > 0;
      final updatesPlate = _isMissingPlateNumber(j) && cachedPlate.isNotEmpty;

      if (updatesCapacity || updatesPlate) {
        jeepneys[i] = j.copyWith(
          maxCapacity: updatesCapacity ? cachedCapacity : null,
          plateNumber: updatesPlate ? cachedPlate : null,
        );
      }
    }
  }

  bool _isMissingPlateNumber(Jeepney jeepney) {
    final plateNumber = jeepney.plateNumber.trim();
    if (plateNumber.isEmpty) return true;
    return _normalizeId(plateNumber) == _normalizeId(jeepney.id);
  }

  String _normalizeId(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  bool _readBool(
    Map<String, dynamic> data,
    List<String> keys, {
    required bool defaultValue,
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

  bool? _toBool(dynamic value) {
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
          normalized == '1' ||
          normalized == 'yes' ||
          normalized == 'active' ||
          normalized == 'online' ||
          normalized == 'ontrip' ||
          normalized == 'on trip' ||
          normalized == 'on_trip') {
        return true;
      }

      if (normalized == 'false' ||
          normalized == '0' ||
          normalized == 'no' ||
          normalized == 'inactive' ||
          normalized == 'offline' ||
          normalized == 'not active' ||
          normalized == 'not online' ||
          normalized == 'not ontrip' ||
          normalized == 'not on trip' ||
          normalized == 'not_on_trip') {
        return false;
      }
    }

    return null;
  }

  int _readInt(
    Map<String, dynamic> data,
    List<String> keys, {
    required int defaultValue,
  }) {
    for (final key in keys) {
      final value = data[key];

      if (value == null) {
        continue;
      }

      if (value is int) {
        return value;
      }

      if (value is num) {
        return value.toInt();
      }

      if (value is String) {
        final parsed = int.tryParse(value.trim());

        if (parsed != null) {
          return parsed;
        }
      }
    }

    return defaultValue;
  }

  double _readDouble(
    Map<String, dynamic> data,
    List<String> keys, {
    required double defaultValue,
  }) {
    final value = _readNullableDouble(data, keys);

    if (value == null) {
      return defaultValue;
    }

    return value;
  }

  double? _readNullableDouble(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key];

      final parsed = _toDouble(value);

      if (parsed != null) {
        return parsed;
      }
    }

    return null;
  }

  double? _toDouble(dynamic value) {
    if (value == null) {
      return null;
    }

    if (value is num) {
      return value.toDouble();
    }

    if (value is String) {
      return double.tryParse(value.trim());
    }

    return null;
  }

  DateTime _readDateTime(
    Map<String, dynamic> data,
    List<String> keys, {
    required DateTime defaultValue,
  }) {
    for (final key in keys) {
      final value = data[key];

      if (value == null) {
        continue;
      }

      if (value is Timestamp) {
        return value.toDate();
      }

      if (value is DateTime) {
        return value;
      }

      if (value is String) {
        final parsed = DateTime.tryParse(value.trim());

        if (parsed != null) {
          return parsed;
        }
      }

      if (value is int) {
        try {
          if (value < 1000000000000) {
            return DateTime.fromMillisecondsSinceEpoch(value * 1000);
          }

          return DateTime.fromMillisecondsSinceEpoch(value);
        } catch (_) {
          continue;
        }
      }
    }

    return defaultValue;
  }

  DateTime? _readNullableDateTime(
    Map<String, dynamic> data,
    List<String> keys,
  ) {
    final fallback = DateTime.fromMillisecondsSinceEpoch(0);
    final value = _readDateTime(data, keys, defaultValue: fallback);
    return value == fallback ? null : value;
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }

    if (value is Map) {
      return value.map(
        (key, dynamic mapValue) => MapEntry(key.toString(), mapValue),
      );
    }

    return <String, dynamic>{};
  }

  // ---------------------------------------------------------------------------
  // DISTANCE HELPER
  // ---------------------------------------------------------------------------

  double _calculateDistanceKm(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const earthRadiusKm = 6371.0;

    final dLat = _degreesToRadians(lat2 - lat1);
    final dLon = _degreesToRadians(lon2 - lon1);

    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degreesToRadians(lat1)) *
            math.cos(_degreesToRadians(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);

    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

    return earthRadiusKm * c;
  }

  double _degreesToRadians(double degrees) {
    return degrees * math.pi / 180.0;
  }
}
