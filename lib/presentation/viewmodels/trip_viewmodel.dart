import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import '../../services/eta_service.dart';
import '../../utils/location_service.dart';

enum CrowdLevel {
  maluwag,
  sakto,
  puno,
}

enum Terminal {
  terminalA,
  terminalB,
}

class TripViewModel extends ChangeNotifier {
  static String? _lastJeepneyId;
  static bool _isTripActiveStatic = false;

  bool _isTripActive = false;
  CrowdLevel? _crowdLevel;
  String _currentRoute = '';
  DateTime? _tripStartTime;
  Terminal? _destination;
  String? _currentJeepneyId;

  LatLng? _currentLocation;
  double _currentSpeedMps = 0;
  EtaResult? _etaResult;
  int _remainingStops = 0;
  double _trafficFactorMinutes = 0;

  bool get isTripActive => _isTripActive;
  CrowdLevel? get crowdLevel => _crowdLevel;
  bool get hasCrowdLevel => _crowdLevel != null;

  String get crowdLevelDisplayName {
    final crowdLevel = _crowdLevel;
    if (crowdLevel == null) return 'Not selected';

    switch (crowdLevel) {
      case CrowdLevel.maluwag:
        return 'Maluwag';
      case CrowdLevel.sakto:
        return 'Sakto';
      case CrowdLevel.puno:
        return 'Puno';
    }
  }

  String get currentRoute => _currentRoute;
  DateTime? get tripStartTime => _tripStartTime;
  Terminal? get destination => _destination;
  String? get currentJeepneyId => _currentJeepneyId;
  static String? get lastJeepneyId => _lastJeepneyId;
  static bool get isTripActiveStatic => _isTripActiveStatic;

  void setCurrentJeepneyId(String? jeepneyId) {
    _currentJeepneyId = jeepneyId;
    _lastJeepneyId = jeepneyId;
    notifyListeners();
  }

  LatLng? get currentLocation => _currentLocation;
  double get currentSpeedMps => _currentSpeedMps;
  EtaResult? get etaResult => _etaResult;
  int get remainingStops => _remainingStops;

  int? get etaMinutes => _etaResult?.etaMinutes;
  String get etaText => _etaResult?.etaText ?? '--';
  bool get isEtaAvailable => _etaResult?.isAvailable ?? false;
  bool get hasArrived => _etaResult?.hasArrived ?? false;
  double get remainingDistanceKm => _etaResult?.distanceKm ?? 0;

  String get destinationName {
    if (_destination == null) return 'Not Set';
    switch (_destination!) {
      case Terminal.terminalA:
        return 'Lucban Terminal';
      case Terminal.terminalB:
        return 'Sta.Cruz Terminal';
    }
  }

  bool get hasDestination => _destination != null;

  String get originTerminal {
    if (_destination == null) return '';
    switch (_destination!) {
      case Terminal.terminalA:
        return 'Sta.Cruz Terminal';
      case Terminal.terminalB:
        return 'Lucban Terminal';
    }
  }

  String get destinationTerminal {
    if (_destination == null) return '';
    switch (_destination!) {
      case Terminal.terminalA:
        return 'Lucban Terminal';
      case Terminal.terminalB:
        return 'Sta.Cruz Terminal';
    }
  }

  LatLng? get destinationCoordinates {
    if (_destination == null) return null;
    switch (_destination!) {
      case Terminal.terminalA:
        return const LatLng(14.1149875, 121.551859375);
      case Terminal.terminalB:
        return const LatLng(14.2659625, 121.425578125);
    }
  }

  void startTrip() {
    _isTripActive = true;
    _isTripActiveStatic = true;
    _tripStartTime = DateTime.now();
    _etaResult = null;
    notifyListeners();
  }

  void endTrip() {
    _isTripActive = false;
    _isTripActiveStatic = false;
    _tripStartTime = null;
    _currentLocation = null;
    _currentSpeedMps = 0;
    _etaResult = null;
    _crowdLevel = null;
    notifyListeners();
  }

  void setCrowdLevel(CrowdLevel level) {
    _crowdLevel = level;
    notifyListeners();
  }

  void setRoute(String route) {
    _currentRoute = route;
    notifyListeners();
  }

  bool setDestination(Terminal? terminal) {
    if (_isTripActive) {
      return false;
    }
    _destination = terminal;
    if (terminal != null) {
      _currentRoute = terminal == Terminal.terminalA
          ? 'Sta. Cruz to Lucban'
          : 'Lucban to Sta. Cruz';
    } else {
      _currentRoute = '';
    }
    _updateEta();
    notifyListeners();
    return true;
  }

  void clearDestination() {
    _destination = null;
    _currentRoute = '';
    _etaResult = null;
    notifyListeners();
  }

  void updateLocation(FilteredLocation location) {
    _currentLocation = location.position;
    _currentSpeedMps = location.speed;
    _updateEta();
    notifyListeners();
  }

  void setRemainingStops(int stops) {
    _remainingStops = stops;
    _updateEta();
    notifyListeners();
  }

  void setTrafficFactor(double minutes) {
    _trafficFactorMinutes = minutes;
    _updateEta();
    notifyListeners();
  }

  void _updateEta() {
    if (_currentLocation == null || _destination == null) {
      _etaResult = EtaResult.unavailable();
      return;
    }

    final destinationCoords = destinationCoordinates;
    if (destinationCoords == null) {
      _etaResult = EtaResult.unavailable();
      return;
    }

    _etaResult = EtaService.calculateEta(
      currentLocation: _currentLocation!,
      destination: destinationCoords,
      currentSpeedMps: _currentSpeedMps > 0 ? _currentSpeedMps : null,
      stopCountEstimate: _remainingStops,
      trafficFactorMinutes: _trafficFactorMinutes,
    );
  }

  Duration? get tripDuration {
    if (_tripStartTime == null) return null;
    return DateTime.now().difference(_tripStartTime!);
  }

  void reset() {
    _isTripActive = false;
    _isTripActiveStatic = false;
    _lastJeepneyId = null;
    _crowdLevel = null;
    _currentRoute = '';
    _tripStartTime = null;
    _destination = null;
    _currentJeepneyId = null;
    _currentLocation = null;
    _currentSpeedMps = 0;
    _etaResult = null;
    _remainingStops = 0;
    _trafficFactorMinutes = 0;
    notifyListeners();
  }
}
