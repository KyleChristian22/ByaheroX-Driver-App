import 'dart:math' as math;
import 'package:latlong2/latlong.dart';

class EtaConfig {
  static const double defaultAverageSpeedKmh = 20.0;
  static const double stopTimeSeconds = 30.0;
  static const double minValidSpeedKmh = 1.0;
  static const double maxValidSpeedKmh = 150.0;
  static const double arrivalThresholdMeters = 50.0;
}

class EtaResult {
  final int? etaMinutes;
  final double distanceKm;
  final double usableSpeedKmh;
  final int stopDelayMinutes;
  final bool isAvailable;
  final String etaText;
  final bool hasArrived;

  EtaResult({
    this.etaMinutes,
    required this.distanceKm,
    required this.usableSpeedKmh,
    required this.stopDelayMinutes,
    required this.isAvailable,
    required this.etaText,
    required this.hasArrived,
  });

  factory EtaResult.unavailable() {
    return EtaResult(
      etaMinutes: null,
      distanceKm: 0,
      usableSpeedKmh: 0,
      stopDelayMinutes: 0,
      isAvailable: false,
      etaText: '--',
      hasArrived: false,
    );
  }
}

class EtaService {
  static double calculateDistanceKm(LatLng from, LatLng to) {
    const earthRadius = 6371.0;
    final dLat = _toRadians(to.latitude - from.latitude);
    final dLng = _toRadians(to.longitude - from.longitude);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(from.latitude)) *
            math.cos(_toRadians(to.latitude)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  static double _toRadians(double degrees) => degrees * math.pi / 180;

  static double getUsableSpeed(double? currentSpeedMps) {
    if (currentSpeedMps == null || currentSpeedMps <= 0) {
      return EtaConfig.defaultAverageSpeedKmh;
    }
    
    final speedKmh = currentSpeedMps * 3.6;
    
    if (speedKmh < EtaConfig.minValidSpeedKmh || 
        speedKmh > EtaConfig.maxValidSpeedKmh) {
      return EtaConfig.defaultAverageSpeedKmh;
    }
    
    return speedKmh;
  }

  static int estimateStopDelayMinutes(int stopCount) {
    return (stopCount * (EtaConfig.stopTimeSeconds / 60)).round();
  }

  static EtaResult calculateEta({
    required LatLng currentLocation,
    required LatLng destination,
    double? currentSpeedMps,
    int stopCountEstimate = 0,
    double trafficFactorMinutes = 0,
  }) {
    final distanceKm = calculateDistanceKm(currentLocation, destination);
    
    if (distanceKm <= 0) {
      return EtaResult.unavailable();
    }

    final usableSpeed = getUsableSpeed(currentSpeedMps);
    
    final travelTimeHours = distanceKm / usableSpeed;
    final travelTimeMinutes = travelTimeHours * 60;
    
    final stopDelayMinutes = estimateStopDelayMinutes(stopCountEstimate);
    
    final totalEtaMinutes = (travelTimeMinutes + stopDelayMinutes + trafficFactorMinutes).round();
    final etaText = _formatEtaText(totalEtaMinutes);
    final hasArrived = distanceKm * 1000 <= EtaConfig.arrivalThresholdMeters;

    return EtaResult(
      etaMinutes: totalEtaMinutes,
      distanceKm: distanceKm,
      usableSpeedKmh: usableSpeed,
      stopDelayMinutes: stopDelayMinutes,
      isAvailable: true,
      etaText: etaText,
      hasArrived: hasArrived,
    );
  }

  static String _formatEtaText(int minutes) {
    if (minutes <= 0) return 'Arriving';
    if (minutes < 1) return '< 1 min';
    if (minutes < 60) return '$minutes min';
    
    final hours = minutes ~/ 60;
    final remainingMinutes = minutes % 60;
    
    if (remainingMinutes == 0) {
      return '$hours hr';
    }
    return '$hours hr $remainingMinutes min';
  }
}