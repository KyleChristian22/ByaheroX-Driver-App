import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// Location smoothing and filtering utility.
///
/// Purpose:
/// - Reduce GPS jitter.
/// - Avoid impossible GPS jumps.
/// - Keep marker responsive enough for live map movement.
/// - Avoid being too strict with phone GPS accuracy.
///
/// Important:
/// This class only filters/smooths local GPS readings.
/// Firestore update frequency should still be controlled in trip_screen.dart.
class LocationSmoother {
  /// Minimum distance in meters before accepting small movement.
  ///
  /// Lower value = marker moves more often.
  /// 1.5m is better for live map display than 3m.
  static const double minDistanceThreshold = 1.5;

  /// Maximum accepted GPS accuracy in meters.
  ///
  /// 20m is too strict for real phones, especially outside ideal conditions.
  /// 100m keeps real phones visible during weak GPS moments while still
  /// rejecting very poor readings.
  static const double maxAccuracyThreshold = 100.0;

  /// Maximum possible jump in meters.
  ///
  /// If GPS suddenly jumps this far, it is likely a bad reading.
  static const double maxJumpThreshold = 300.0;

  /// Smoothing factor for position.
  ///
  /// Higher = more responsive.
  /// Lower = smoother but delayed.
  ///
  /// 0.55 gives better real-time movement than 0.30.
  static const double smoothingFactor = 0.55;

  /// Smoothing factor when GPS accuracy is poor but still acceptable.
  ///
  /// This prevents noisy readings from moving the marker too aggressively.
  static const double lowConfidenceSmoothingFactor = 0.30;

  /// Accuracy value where we start treating the reading as low confidence.
  static const double lowConfidenceAccuracy = 35.0;

  LatLng? _lastPosition;
  LatLng? _previousRawPosition;

  DateTime? _lastTimestamp;

  double _smoothedSpeed = 0.0;
  double _smoothedHeading = 0.0;

  /// Filter and smooth a new GPS position.
  ///
  /// Returns null if the position should be ignored.
  FilteredLocation? filterAndSmooth(Position position) {
    final currentPosition = LatLng(position.latitude, position.longitude);
    final currentAccuracy = position.accuracy;
    final currentTimestamp = DateTime.now();

    if (!_isValidLatLng(currentPosition)) {
      debugPrint('Location filtered: invalid latitude/longitude');
      return null;
    }

    if (currentAccuracy.isNaN || currentAccuracy <= 0) {
      debugPrint('Location filtered: invalid accuracy');
      return null;
    }

    // 1. Ignore very poor GPS readings.
    if (currentAccuracy > maxAccuracyThreshold) {
      debugPrint(
        'Location filtered: poor accuracy (${currentAccuracy.toStringAsFixed(1)}m)',
      );
      return null;
    }

    // 2. Ignore impossible jumps from the previous raw GPS reading.
    if (_previousRawPosition != null) {
      final rawJumpDistance = _calculateDistance(
        _previousRawPosition!,
        currentPosition,
      );

      if (rawJumpDistance > maxJumpThreshold) {
        debugPrint(
          'Location filtered: impossible jump (${rawJumpDistance.toStringAsFixed(1)}m)',
        );

        // Do not update _previousRawPosition here.
        // Keeping the previous good raw position helps detect repeated bad jumps.
        return null;
      }
    }

    _previousRawPosition = currentPosition;

    // 3. First valid reading: accept immediately.
    if (_lastPosition == null) {
      final safeHeading = _safeHeading(position.heading, fallback: 0.0);
      final safeSpeed = _safeSpeed(position.speed);

      _lastPosition = currentPosition;
      _lastTimestamp = currentTimestamp;
      _smoothedSpeed = safeSpeed;
      _smoothedHeading = safeHeading;

      return FilteredLocation(
        position: currentPosition,
        accuracy: currentAccuracy,
        speed: safeSpeed,
        heading: safeHeading,
        isFiltered: false,
        rawDistance: null,
      );
    }

    // 4. Distance from last smoothed location.
    final distanceFromLast = _calculateDistance(
      _lastPosition!,
      currentPosition,
    );

    // 5. Ignore tiny movement to reduce jitter.
    if (distanceFromLast < minDistanceThreshold) {
      _lastTimestamp = currentTimestamp;

      debugPrint(
        'Location filtered: tiny movement (${distanceFromLast.toStringAsFixed(2)}m)',
      );

      return null;
    }

    // 6. Compute time difference.
    double timeDiffSeconds = 1.0;

    if (_lastTimestamp != null) {
      timeDiffSeconds =
          currentTimestamp.difference(_lastTimestamp!).inMilliseconds / 1000.0;

      if (timeDiffSeconds < 0.1) {
        timeDiffSeconds = 0.1;
      }
    }

    // 7. Use dynamic smoothing.
    //
    // If GPS accuracy is weaker, smooth more.
    // If GPS accuracy is good, marker follows faster.
    final double factor = currentAccuracy > lowConfidenceAccuracy
        ? lowConfidenceSmoothingFactor
        : smoothingFactor;

    final smoothedLat = _lastPosition!.latitude +
        factor * (currentPosition.latitude - _lastPosition!.latitude);

    final smoothedLng = _lastPosition!.longitude +
        factor * (currentPosition.longitude - _lastPosition!.longitude);

    final smoothedPosition = LatLng(smoothedLat, smoothedLng);

    // 8. Smooth speed.
    final measuredSpeed = _safeSpeed(position.speed);

    _smoothedSpeed = (_smoothedSpeed * 0.65) + (measuredSpeed * 0.35);

    // 9. Smooth heading.
    //
    // If Geolocator heading is invalid, calculate heading from movement.
    final rawHeading = _safeHeading(
      position.heading,
      fallback: _bearingBetween(_lastPosition!, currentPosition),
    );

    _smoothedHeading = _smoothHeading(_smoothedHeading, rawHeading);

    _lastPosition = smoothedPosition;
    _lastTimestamp = currentTimestamp;

    return FilteredLocation(
      position: smoothedPosition,
      accuracy: currentAccuracy,
      speed: _smoothedSpeed,
      heading: _smoothedHeading,
      isFiltered: false,
      rawDistance: distanceFromLast,
      timeDiffSeconds: timeDiffSeconds,
    );
  }

  LatLng? get lastPosition => _lastPosition;

  void reset() {
    _lastPosition = null;
    _previousRawPosition = null;
    _lastTimestamp = null;
    _smoothedSpeed = 0.0;
    _smoothedHeading = 0.0;
  }

  bool _isValidLatLng(LatLng point) {
    if (point.latitude.isNaN || point.longitude.isNaN) return false;
    if (point.latitude == 0 && point.longitude == 0) return false;

    return point.latitude >= -90 &&
        point.latitude <= 90 &&
        point.longitude >= -180 &&
        point.longitude <= 180;
  }

  double _safeSpeed(double speed) {
    if (speed.isNaN || speed < 0) return 0.0;
    return speed;
  }

  double _safeHeading(double heading, {required double fallback}) {
    if (heading.isNaN || heading < 0) {
      return _normalizeHeading(fallback);
    }

    return _normalizeHeading(heading);
  }

  double _normalizeHeading(double heading) {
    if (heading.isNaN) return 0.0;

    double result = heading % 360;

    if (result < 0) {
      result += 360;
    }

    return result;
  }

  double _smoothHeading(double oldHeading, double newHeading) {
    double diff = newHeading - oldHeading;

    if (diff > 180) diff -= 360;
    if (diff < -180) diff += 360;

    final result = oldHeading + smoothingFactor * diff;

    return _normalizeHeading(result);
  }

  double _bearingBetween(LatLng start, LatLng end) {
    final lat1 = _toRadians(start.latitude);
    final lat2 = _toRadians(end.latitude);
    final dLng = _toRadians(end.longitude - start.longitude);

    final y = math.sin(dLng) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLng);

    final bearing = math.atan2(y, x) * 180 / math.pi;

    return _normalizeHeading(bearing);
  }

  double _calculateDistance(LatLng point1, LatLng point2) {
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

  double _toRadians(double degrees) {
    return degrees * math.pi / 180;
  }
}

/// Filtered location result.
class FilteredLocation {
  final LatLng position;
  final double accuracy;
  final double speed;
  final double heading;
  final bool isFiltered;
  final double? rawDistance;
  final double? timeDiffSeconds;

  FilteredLocation({
    required this.position,
    required this.accuracy,
    required this.speed,
    required this.heading,
    required this.isFiltered,
    this.rawDistance,
    this.timeDiffSeconds,
  });
}

/// Route snap-to-road utility.
///
/// Snaps GPS position to the nearest point on a route polyline.
class RouteSnapper {
  final List<LatLng> routePoints;

  /// Search radius in meters.
  ///
  /// If too low, marker will not snap often.
  /// If too high, marker may snap to the wrong nearby route.
  final double searchRadius;

  RouteSnapper({
    required this.routePoints,
    this.searchRadius = 55.0,
  });

  /// Snap a GPS position to the nearest point on the route.
  ///
  /// Returns null if no route point/segment is within searchRadius.
  LatLng? snapToRoute(LatLng position) {
    if (routePoints.isEmpty) return null;
    if (routePoints.length == 1) return routePoints.first;

    double minDistance = double.infinity;
    LatLng? nearestPoint;

    for (int i = 0; i < routePoints.length - 1; i++) {
      final start = routePoints[i];
      final end = routePoints[i + 1];

      final projectedPoint = _closestPointOnSegment(
        start,
        end,
        position,
      );

      final distance = _calculateDistance(position, projectedPoint);

      if (distance < minDistance) {
        minDistance = distance;
        nearestPoint = projectedPoint;
      }
    }

    if (nearestPoint == null) return null;

    if (minDistance > searchRadius) {
      debugPrint(
        'Route snap skipped: nearest route is ${minDistance.toStringAsFixed(1)}m away',
      );
      return null;
    }

    return nearestPoint;
  }

  /// Finds closest point on a segment using local meter-based projection.
  ///
  /// This avoids the old bug where degrees were mixed with meter distance.
  LatLng _closestPointOnSegment(
    LatLng start,
    LatLng end,
    LatLng point,
  ) {
    final refLat = _toRadians((start.latitude + end.latitude) / 2.0);

    final startXY = _toLocalMeters(start, refLat);
    final endXY = _toLocalMeters(end, refLat);
    final pointXY = _toLocalMeters(point, refLat);

    final dx = endXY.x - startXY.x;
    final dy = endXY.y - startXY.y;

    final segmentLengthSquared = dx * dx + dy * dy;

    if (segmentLengthSquared == 0) {
      return start;
    }

    final t = ((pointXY.x - startXY.x) * dx + (pointXY.y - startXY.y) * dy) /
        segmentLengthSquared;

    final clampedT = t.clamp(0.0, 1.0);

    final projectedX = startXY.x + clampedT * dx;
    final projectedY = startXY.y + clampedT * dy;

    return _fromLocalMeters(
      projectedX,
      projectedY,
      refLat,
    );
  }

  _XY _toLocalMeters(LatLng point, double refLatRadians) {
    const earthRadius = 6371000.0;

    final x =
        _toRadians(point.longitude) * earthRadius * math.cos(refLatRadians);
    final y = _toRadians(point.latitude) * earthRadius;

    return _XY(x, y);
  }

  LatLng _fromLocalMeters(
    double x,
    double y,
    double refLatRadians,
  ) {
    const earthRadius = 6371000.0;

    final lat = (y / earthRadius) * 180 / math.pi;
    final lng = (x / (earthRadius * math.cos(refLatRadians))) * 180 / math.pi;

    return LatLng(lat, lng);
  }

  double _calculateDistance(LatLng point1, LatLng point2) {
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

  double _toRadians(double degrees) {
    return degrees * math.pi / 180;
  }
}

class _XY {
  final double x;
  final double y;

  const _XY(this.x, this.y);
}
