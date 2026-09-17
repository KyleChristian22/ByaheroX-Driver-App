import 'dart:async';
import 'dart:convert';
import 'dart:io' show File;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';

class RoutingException implements Exception {
  final String message;
  final String? code;

  RoutingException(this.message, {this.code});

  @override
  String toString() {
    return 'RoutingException: $message${code != null ? ' ($code)' : ''}';
  }
}

class LocationPermissionException implements Exception {
  final String message;

  LocationPermissionException(this.message);

  @override
  String toString() => 'LocationPermissionException: $message';
}

class RouteResult {
  final List<LatLng> points;
  final double distance;
  final double duration;
  final List<String> instructions;
  final List<dynamic>? rawGeometry;

  RouteResult({
    required this.points,
    required this.distance,
    required this.duration,
    required this.instructions,
    this.rawGeometry,
  });

  bool get isValid => points.length >= 2 && distance > 0;

  String get distanceText {
    if (distance < 1000) return '${distance.toStringAsFixed(0)} m';
    return '${(distance / 1000).toStringAsFixed(1)} km';
  }

  String get durationText {
    final minutes = (duration / 60).round();

    if (minutes < 1) return '<1 min';
    if (minutes < 60) return '$minutes min';

    final hours = minutes ~/ 60;
    final mins = minutes % 60;

    if (mins == 0) return '${hours}h';

    return '${hours}h ${mins}m';
  }

  double get averageSpeedMps {
    if (duration <= 0) return 0.0;
    return distance / duration;
  }

  double get averageSpeedKph => averageSpeedMps * 3.6;
}

class RouteNearestPointResult {
  final LatLng point;
  final int segmentIndex;
  final double distanceFromGpsMeters;
  final double progressMeters;
  final double progressRatio;

  RouteNearestPointResult({
    required this.point,
    required this.segmentIndex,
    required this.distanceFromGpsMeters,
    required this.progressMeters,
    required this.progressRatio,
  });
}

class RoutingService {
  static const String _osrmBaseUrl = 'https://router.project-osrm.org';
  static const String _nominatimBaseUrl = 'https://nominatim.openstreetmap.org';
  static const String _userAgent = 'ByaheroXDriverApp/1.0';

  static const Duration _gpsTimeout = Duration(seconds: 12);
  static const Duration _httpTimeout = Duration(seconds: 15);

  static const int _maxRouteRetries = 2;
  static const String _osrmProfile = 'driving';

  // ---------------------------------------------------------------------------
  // GPS LOCATION
  // ---------------------------------------------------------------------------

  static Future<LatLng> getCurrentGpsLocation({
    LocationAccuracy accuracy = LocationAccuracy.high,
    Duration timeout = _gpsTimeout,
    bool allowLastKnownFallback = true,
  }) async {
    final position = await getCurrentGpsPosition(
      accuracy: accuracy,
      timeout: timeout,
      allowLastKnownFallback: allowLastKnownFallback,
    );

    return LatLng(position.latitude, position.longitude);
  }

  static Future<Position> getCurrentGpsPosition({
    LocationAccuracy accuracy = LocationAccuracy.high,
    Duration timeout = _gpsTimeout,
    bool allowLastKnownFallback = true,
  }) async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) {
      throw LocationPermissionException(
        'Location services are disabled. Please enable GPS.',
      );
    }

    var permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      throw LocationPermissionException(
        'Location permission denied. Please allow location access.',
      );
    }

    if (permission == LocationPermission.deniedForever) {
      throw LocationPermissionException(
        'Location permission permanently denied. Please enable it in app settings.',
      );
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: accuracy,
          timeLimit: timeout,
        ),
      ).timeout(timeout);

      if (!_isValidLatLng(position.latitude, position.longitude)) {
        throw RoutingException(
          'GPS returned invalid coordinates.',
          code: 'invalid-gps',
        );
      }

      return position;
    } on TimeoutException {
      if (!allowLastKnownFallback) {
        throw RoutingException(
          'GPS request timed out. Please try again outside or near a window.',
          code: 'gps-timeout',
        );
      }

      final lastKnown = await Geolocator.getLastKnownPosition();

      if (lastKnown != null &&
          _isValidLatLng(lastKnown.latitude, lastKnown.longitude)) {
        debugPrint(
          '[RoutingService] Using last known GPS position because current GPS timed out.',
        );

        return lastKnown;
      }

      throw RoutingException(
        'GPS request timed out and no last known location was available.',
        code: 'gps-timeout',
      );
    } catch (e) {
      if (allowLastKnownFallback) {
        final lastKnown = await Geolocator.getLastKnownPosition();

        if (lastKnown != null &&
            _isValidLatLng(lastKnown.latitude, lastKnown.longitude)) {
          debugPrint(
            '[RoutingService] Using last known GPS position after GPS error: $e',
          );

          return lastKnown;
        }
      }

      if (e is RoutingException || e is LocationPermissionException) {
        rethrow;
      }

      throw RoutingException(
        'Failed to get current GPS location.',
        code: 'gps-error',
      );
    }
  }

  static Future<bool> hasLocationPermission() async {
    final permission = await Geolocator.checkPermission();

    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  static Future<void> openLocationSettings() async {
    await Geolocator.openLocationSettings();
  }

  static Future<void> openAppSettings() async {
    await Geolocator.openAppSettings();
  }

  // ---------------------------------------------------------------------------
  // GEOCODING
  // ---------------------------------------------------------------------------

  static Future<LatLng?> geocodeAddress(String address) async {
    final cleanAddress = address.trim();

    if (cleanAddress.isEmpty) return null;

    final uri = Uri.parse('$_nominatimBaseUrl/search').replace(
      queryParameters: {
        'format': 'json',
        'q': cleanAddress,
        'limit': '1',
        'addressdetails': '1',
      },
    );

    try {
      final response = await http.get(
        uri,
        headers: const {
          'User-Agent': _userAgent,
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        debugPrint('[RoutingService] Nominatim failed: ${response.statusCode}');
        return null;
      }

      final decoded = json.decode(response.body);

      if (decoded is! List || decoded.isEmpty) return null;

      final first = decoded.first;

      if (first is! Map<String, dynamic>) return null;

      final lat = double.tryParse(first['lat']?.toString() ?? '');
      final lon = double.tryParse(first['lon']?.toString() ?? '');

      if (lat == null || lon == null) return null;

      if (!_isValidLatLng(lat, lon)) return null;

      return LatLng(lat, lon);
    } on TimeoutException {
      debugPrint('[RoutingService] Nominatim timeout.');
      return null;
    } catch (e) {
      debugPrint('[RoutingService] Could not geocode address: $e');
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // OSRM ROUTING
  // ---------------------------------------------------------------------------

  static Future<RouteResult?> getRoute(
    LatLng start,
    LatLng end, {
    bool includeSteps = true,
    int maxRetries = _maxRouteRetries,
  }) async {
    if (!_isValidLatLng(start.latitude, start.longitude)) {
      throw RoutingException(
        'Start location is invalid.',
        code: 'invalid-start',
      );
    }

    if (!_isValidLatLng(end.latitude, end.longitude)) {
      throw RoutingException(
        'Destination location is invalid.',
        code: 'invalid-destination',
      );
    }

    final directDistance = calculateDistance(start, end);

    if (directDistance < 5) {
      return RouteResult(
        points: [start, end],
        distance: directDistance,
        duration: 0,
        instructions: const ['You are already near the destination.'],
        rawGeometry: [
          [start.longitude, start.latitude],
          [end.longitude, end.latitude],
        ],
      );
    }

    final coordinates =
        '${_formatCoordinate(start.longitude)},${_formatCoordinate(start.latitude)};'
        '${_formatCoordinate(end.longitude)},${_formatCoordinate(end.latitude)}';

    final uri = Uri.parse(
      '$_osrmBaseUrl/route/v1/$_osrmProfile/$coordinates',
    ).replace(
      queryParameters: {
        'overview': 'full',
        'geometries': 'geojson',
        'steps': includeSteps ? 'true' : 'false',
        'alternatives': 'false',
      },
    );

    debugPrint('[RoutingService] OSRM getRoute called.');
    debugPrint('[RoutingService] Start: ${start.latitude}, ${start.longitude}');
    debugPrint('[RoutingService] End: ${end.latitude}, ${end.longitude}');
    debugPrint(
      '[RoutingService] Direct distance: ${directDistance.toStringAsFixed(1)}m',
    );
    debugPrint('[RoutingService] OSRM URL: $uri');

    Object? lastError;

    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        final response = await http.get(
          uri,
          headers: const {
            'User-Agent': _userAgent,
            'Accept': 'application/json',
          },
        ).timeout(_httpTimeout);

        debugPrint(
          '[RoutingService] OSRM response status: ${response.statusCode}',
        );

        if (response.statusCode != 200) {
          throw RoutingException(
            'OSRM API error: ${response.statusCode}',
            code: response.statusCode.toString(),
          );
        }

        final decoded = json.decode(response.body);

        if (decoded is! Map<String, dynamic>) {
          throw RoutingException(
            'Invalid OSRM response format.',
            code: 'invalid-response',
          );
        }

        final code = decoded['code']?.toString();

        if (code != 'Ok') {
          throw RoutingException(
            decoded['message']?.toString() ?? 'Unknown OSRM error.',
            code: code,
          );
        }

        final routes = decoded['routes'];

        if (routes is! List || routes.isEmpty) {
          throw RoutingException(
            'No route found between points.',
            code: 'no-route',
          );
        }

        final route = routes.first;

        if (route is! Map<String, dynamic>) {
          throw RoutingException(
            'Invalid route object from OSRM.',
            code: 'invalid-route',
          );
        }

        final geometry = route['geometry'];
        final rawCoordinates = _extractRawCoordinates(geometry);
        final points = _parseOsrmGeometry(geometry);

        if (points == null || points.length < 2) {
          throw RoutingException(
            'Failed to parse route geometry.',
            code: 'geometry-parse-failed',
          );
        }

        final distance = _toDouble(route['distance']) ?? 0.0;
        final duration = _toDouble(route['duration']) ?? 0.0;

        final instructions =
            includeSteps ? _parseOsrmInstructions(route['legs']) : <String>[];

        debugPrint(
          '[RoutingService] Route loaded. points=${points.length}, distance=${distance.toStringAsFixed(1)}m, duration=${duration.toStringAsFixed(1)}s',
        );

        return RouteResult(
          points: points,
          distance: distance,
          duration: duration,
          instructions: instructions,
          rawGeometry: rawCoordinates,
        );
      } on TimeoutException catch (e) {
        lastError = e;
        debugPrint(
          '[RoutingService] OSRM timeout. attempt=${attempt + 1}/${maxRetries + 1}',
        );
      } catch (e) {
        lastError = e;
        debugPrint(
          '[RoutingService] OSRM error. attempt=${attempt + 1}/${maxRetries + 1}: $e',
        );

        if (e is RoutingException) {
          final nonRetryable = e.code == 'no-route' ||
              e.code == 'invalid-start' ||
              e.code == 'invalid-destination' ||
              e.code == 'geometry-parse-failed';

          if (nonRetryable) rethrow;
        }
      }

      if (attempt < maxRetries) {
        await Future.delayed(Duration(milliseconds: 400 * (attempt + 1)));
      }
    }

    if (lastError is RoutingException) throw lastError;

    throw RoutingException(
      'Could not connect to routing server. Please check your internet connection.',
      code: 'routing-unavailable',
    );
  }

  static Future<RouteResult?> getRouteToDestination(
    LatLng destination, {
    String? destinationName,
    bool includeSteps = true,
  }) async {
    final start = await getCurrentGpsLocation();

    return getRoute(
      start,
      destination,
      includeSteps: includeSteps,
    );
  }

  static Future<RouteResult?> getRouteToAddress(
    String address, {
    bool includeSteps = true,
  }) async {
    final start = await getCurrentGpsLocation();
    final end = await geocodeAddress(address);

    if (end == null) {
      throw RoutingException(
        'Could not find coordinates for address: $address',
        code: 'geocoding-failed',
      );
    }

    return getRoute(
      start,
      end,
      includeSteps: includeSteps,
    );
  }

  // ---------------------------------------------------------------------------
  // GEOJSON
  // ---------------------------------------------------------------------------

  static Map<String, dynamic> createGeoJsonFeatureCollection(
    List<LatLng> points, {
    String name = 'Route',
    String description = 'Generated route from OSRM',
  }) {
    final validPoints =
        points.where((p) => _isValidLatLng(p.latitude, p.longitude)).toList();

    final coordinates = validPoints
        .map((p) => [
              p.longitude,
              p.latitude,
            ])
        .toList();

    return {
      'type': 'FeatureCollection',
      'features': [
        {
          'type': 'Feature',
          'properties': {
            'name': name,
            'description': description,
            'pointCount': validPoints.length,
            'createdAt': DateTime.now().toIso8601String(),
          },
          'geometry': {
            'type': 'LineString',
            'coordinates': coordinates,
          },
        },
      ],
    };
  }

  static Future<String?> saveRouteToFile(
    List<LatLng> points,
    String fileName, {
    String name = 'Route',
    String description = 'Generated route from OSRM',
  }) async {
    try {
      if (kIsWeb) {
        debugPrint(
          '[RoutingService] saveRouteToFile is not supported on Flutter Web.',
        );
        return null;
      }

      final cleanFileName = _sanitizeFileName(fileName);

      final geoJson = createGeoJsonFeatureCollection(
        points,
        name: name,
        description: description,
      );

      final jsonString = const JsonEncoder.withIndent('  ').convert(geoJson);

      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$cleanFileName');

      await file.writeAsString(jsonString);

      debugPrint('[RoutingService] Route saved to: ${file.path}');

      return file.path;
    } catch (e) {
      debugPrint('[RoutingService] Could not save route to file: $e');
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // ROUTE HELPERS FOR GPS MOVEMENT
  // ---------------------------------------------------------------------------

  static double calculateDistance(LatLng point1, LatLng point2) {
    const earthRadius = 6371000.0;

    final dLat = _toRadians(point2.latitude - point1.latitude);
    final dLng = _toRadians(point2.longitude - point1.longitude);

    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(point1.latitude)) *
            math.cos(_toRadians(point2.latitude)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);

    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

    return earthRadius * c;
  }

  static double calculateBearing(LatLng start, LatLng end) {
    final startLat = _toRadians(start.latitude);
    final startLng = _toRadians(start.longitude);
    final endLat = _toRadians(end.latitude);
    final endLng = _toRadians(end.longitude);

    final dLng = endLng - startLng;

    final y = math.sin(dLng) * math.cos(endLat);
    final x = math.cos(startLat) * math.sin(endLat) -
        math.sin(startLat) * math.cos(endLat) * math.cos(dLng);

    final bearing = _toDegrees(math.atan2(y, x));

    return (bearing + 360.0) % 360.0;
  }

  static double calculateRouteDistance(List<LatLng> points) {
    if (points.length < 2) return 0.0;

    double total = 0.0;

    for (int i = 0; i < points.length - 1; i++) {
      total += calculateDistance(points[i], points[i + 1]);
    }

    return total;
  }

  static RouteNearestPointResult? findNearestPointOnRoute(
    LatLng gpsPosition,
    List<LatLng> routePoints, {
    double maxSnapDistanceMeters = 80.0,
  }) {
    if (!_isValidLatLng(gpsPosition.latitude, gpsPosition.longitude)) {
      return null;
    }

    if (routePoints.length < 2) return null;

    final routeTotalDistance = calculateRouteDistance(routePoints);

    if (routeTotalDistance <= 0) return null;

    double bestDistance = double.infinity;
    LatLng? bestPoint;
    int bestSegmentIndex = 0;
    double bestProgressMeters = 0.0;

    double progressBeforeSegment = 0.0;

    for (int i = 0; i < routePoints.length - 1; i++) {
      final start = routePoints[i];
      final end = routePoints[i + 1];

      final projected = _nearestPointOnSegment(gpsPosition, start, end);
      final distanceFromGps = calculateDistance(gpsPosition, projected);
      final segmentLength = calculateDistance(start, end);
      final progressOnSegment = calculateDistance(start, projected);

      if (distanceFromGps < bestDistance) {
        bestDistance = distanceFromGps;
        bestPoint = projected;
        bestSegmentIndex = i;
        bestProgressMeters =
            progressBeforeSegment + progressOnSegment.clamp(0.0, segmentLength);
      }

      progressBeforeSegment += segmentLength;
    }

    if (bestPoint == null) return null;

    if (bestDistance > maxSnapDistanceMeters) return null;

    final progressRatio =
        (bestProgressMeters / routeTotalDistance).clamp(0.0, 1.0);

    return RouteNearestPointResult(
      point: bestPoint,
      segmentIndex: bestSegmentIndex,
      distanceFromGpsMeters: bestDistance,
      progressMeters: bestProgressMeters,
      progressRatio: progressRatio,
    );
  }

  static List<LatLng> simplifyRoutePoints(
    List<LatLng> points, {
    double minDistanceMeters = 5.0,
  }) {
    if (points.length <= 2) return points;

    final simplified = <LatLng>[points.first];
    LatLng lastKept = points.first;

    for (int i = 1; i < points.length - 1; i++) {
      final current = points[i];

      if (calculateDistance(lastKept, current) >= minDistanceMeters) {
        simplified.add(current);
        lastKept = current;
      }
    }

    simplified.add(points.last);

    return simplified;
  }

  // ---------------------------------------------------------------------------
  // PARSERS
  // ---------------------------------------------------------------------------

  static List<LatLng>? _parseOsrmGeometry(dynamic geometry) {
    final coordinates = _extractRawCoordinates(geometry);

    if (coordinates == null || coordinates.isEmpty) return null;

    final points = <LatLng>[];

    for (final coord in coordinates) {
      if (coord is! List || coord.length < 2) continue;

      final lng = _toDouble(coord[0]);
      final lat = _toDouble(coord[1]);

      if (lat == null || lng == null) continue;

      if (!_isValidLatLng(lat, lng)) continue;

      points.add(LatLng(lat, lng));
    }

    if (points.isEmpty) return null;

    return points;
  }

  static List<dynamic>? _extractRawCoordinates(dynamic geometry) {
    if (geometry is! Map<String, dynamic>) return null;

    final coordinates = geometry['coordinates'];

    if (coordinates is! List) return null;

    return coordinates;
  }

  static List<String> _parseOsrmInstructions(dynamic legs) {
    final instructions = <String>[];

    if (legs is! List) return instructions;

    for (final leg in legs) {
      if (leg is! Map<String, dynamic>) continue;

      final steps = leg['steps'];

      if (steps is! List) continue;

      for (final step in steps) {
        if (step is! Map<String, dynamic>) continue;

        final maneuver = step['maneuver'];

        String type = '';
        String modifier = '';
        String roadName = '';

        if (maneuver is Map<String, dynamic>) {
          type = maneuver['type']?.toString() ?? '';
          modifier = maneuver['modifier']?.toString() ?? '';
        }

        roadName = step['name']?.toString() ?? '';

        final readable = _buildInstructionText(
          type: type,
          modifier: modifier,
          roadName: roadName,
        );

        if (readable.trim().isNotEmpty) {
          instructions.add(readable);
        }
      }
    }

    return instructions;
  }

  static String _buildInstructionText({
    required String type,
    required String modifier,
    required String roadName,
  }) {
    final cleanType = type.trim();
    final cleanModifier = modifier.trim();
    final cleanRoadName = roadName.trim();

    if (cleanType.isEmpty && cleanRoadName.isEmpty) return '';

    switch (cleanType) {
      case 'depart':
        if (cleanRoadName.isNotEmpty) return 'Start on $cleanRoadName';
        return 'Start driving';

      case 'arrive':
        return 'Arrive at destination';

      case 'turn':
        if (cleanRoadName.isNotEmpty) {
          return 'Turn $cleanModifier onto $cleanRoadName'.trim();
        }
        return 'Turn $cleanModifier'.trim();

      case 'new name':
        if (cleanRoadName.isNotEmpty) return 'Continue onto $cleanRoadName';
        return 'Continue';

      case 'continue':
        if (cleanRoadName.isNotEmpty) return 'Continue on $cleanRoadName';
        return 'Continue';

      case 'merge':
        if (cleanRoadName.isNotEmpty) {
          return 'Merge $cleanModifier onto $cleanRoadName'.trim();
        }
        return 'Merge $cleanModifier'.trim();

      case 'roundabout':
      case 'rotary':
        if (cleanRoadName.isNotEmpty) {
          return 'Take the roundabout toward $cleanRoadName';
        }
        return 'Enter the roundabout';

      case 'fork':
        if (cleanRoadName.isNotEmpty) {
          return 'Keep $cleanModifier toward $cleanRoadName'.trim();
        }
        return 'Keep $cleanModifier'.trim();

      case 'end of road':
        if (cleanRoadName.isNotEmpty) {
          return 'At the end of the road, continue to $cleanRoadName';
        }
        return 'Continue at the end of the road';

      default:
        final pieces = <String>[
          cleanType,
          cleanModifier,
          if (cleanRoadName.isNotEmpty) cleanRoadName,
        ].where((p) => p.trim().isNotEmpty).join(' ');

        return pieces.trim();
    }
  }

  // ---------------------------------------------------------------------------
  // INTERNAL UTILS
  // ---------------------------------------------------------------------------

  static bool _isValidLatLng(double lat, double lng) {
    if (lat.isNaN || lng.isNaN) return false;
    if (lat.isInfinite || lng.isInfinite) return false;
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

    if (result == null || result.isNaN || result.isInfinite) return null;

    return result;
  }

  static String _formatCoordinate(double value) {
    return value.toStringAsFixed(6);
  }

  static String _sanitizeFileName(String fileName) {
    var clean = fileName.trim();

    if (clean.isEmpty) {
      clean = 'route.geojson';
    }

    clean = clean.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');

    if (!clean.toLowerCase().endsWith('.geojson')) {
      clean = '$clean.geojson';
    }

    return clean;
  }

  static LatLng _nearestPointOnSegment(
    LatLng point,
    LatLng start,
    LatLng end,
  ) {
    final latScale = math.cos(
      _toRadians((start.latitude + end.latitude) / 2),
    );

    final px = point.longitude * latScale;
    final py = point.latitude;

    final sx = start.longitude * latScale;
    final sy = start.latitude;

    final ex = end.longitude * latScale;
    final ey = end.latitude;

    final dx = ex - sx;
    final dy = ey - sy;

    if (dx == 0 && dy == 0) {
      return start;
    }

    final t = (((px - sx) * dx) + ((py - sy) * dy)) / ((dx * dx) + (dy * dy));

    final clampedT = t.clamp(0.0, 1.0);

    final nearestLngScaled = sx + clampedT * dx;
    final nearestLat = sy + clampedT * dy;

    final nearestLng = nearestLngScaled / latScale;

    return LatLng(nearestLat, nearestLng);
  }

  static double _toRadians(double degrees) {
    return degrees * math.pi / 180.0;
  }

  static double _toDegrees(double radians) {
    return radians * 180.0 / math.pi;
  }
}
