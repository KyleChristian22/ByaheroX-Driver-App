import 'dart:math';

class DistanceCalculator {
  static const double earthRadiusKm = 6371.0;

  /// Calculate distance between two coordinates using Haversine formula
  /// Returns distance in kilometers
  static double calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    final double lat1Rad = _degreesToRadians(lat1);
    final double lat2Rad = _degreesToRadians(lat2);
    final double deltaLat = _degreesToRadians(lat2 - lat1);
    final double deltaLon = _degreesToRadians(lon2 - lon1);

    final double sinDeltaLat = sin(deltaLat / 2);
    final double sinDeltaLon = sin(deltaLon / 2);

    final double a = sinDeltaLat * sinDeltaLat +
        cos(lat1Rad) * cos(lat2Rad) * sinDeltaLon * sinDeltaLon;

    final double c = 2 * asin(sqrt(a));

    return earthRadiusKm * c;
  }

  static double _degreesToRadians(double degrees) {
    return degrees * (pi / 180.0);
  }

  /// Calculate estimated time in minutes based on distance and average speed
  /// Average jeepney speed in km/h (default 20 km/h in city areas)
  static int calculateEstimatedTime(double distanceKm, {double speedKmh = 20.0}) {
    if (speedKmh <= 0) return 0;
    final double timeHours = distanceKm / speedKmh;
    return (timeHours * 60).ceil();
  }
}