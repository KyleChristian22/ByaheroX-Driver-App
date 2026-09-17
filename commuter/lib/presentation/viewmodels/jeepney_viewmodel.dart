import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../../core/constants/terminal_constants.dart';
import '../../data/repositories/jeepney_repository_impl.dart';
import '../../data/services/nearest_jeepney_service.dart';
import '../../domain/entities/jeepney.dart';
import '../../domain/entities/route.dart';
import '../../domain/models/route_filter.dart';
import '../../domain/repositories/jeepney_repository.dart';

/// ViewModel for managing jeepney state in Commuter app.
///
/// Main responsibility:
/// - Watch live driver locations from Firestore.
/// - Store all active/on-trip jeepneys.
/// - Apply selected destination filter.
/// - Notify HomeScreen so jeepney markers update on the map.
///
/// Important:
/// Jeepney markers shown in HomeScreen should come from:
///   activeDriverLocations
///
/// Firestore expected live location collection:
///   locations/{jeepneyId}
///
/// Expected fields from Driver app:
/// {
///   "isOnTrip": true,
///   "isOnline": true,
///   "lat": 14.2730,
///   "lng": 121.4031,
///   "destinationTerminal": "Sta.Cruz Terminal",
///   "originTerminal": "Lucban Terminal",
///   "routeId": "ROUTE001",
///   "jeepneyId": "JEEP001",
///   "crowdStatus": "sakto",
///   "speedMps": 3,
///   "updatedAt": Timestamp
/// }
class JeepneyViewModel extends ChangeNotifier {
  final JeepneyRepository _repository;

  JeepneyViewModel({JeepneyRepository? repository})
    : _repository = repository ?? JeepneyRepositoryImpl();

  // Jeepney data
  List<Jeepney> _jeepneys = [];
  List<Jeepney> _allActiveJeepneys = [];
  List<Jeepney> _activeDriverLocations = [];
  Jeepney? _selectedJeepney;

  // Loading states
  bool _isLoading = false;
  bool _isWatching = false;
  bool _isRefreshing = false;
  bool _isInitialized = false;
  String? _error;

  // Filters
  String? _originTerminal;
  String? _destinationTerminal;
  RouteFilter? _routeFilter;
  Route? _selectedRoute;
  bool _showAllJeepneys = true;
  LatLng? _userLocation;

  // Last update time
  DateTime? _lastUpdated;

  // Stream subscriptions
  StreamSubscription<List<Jeepney>>? _driverLocationsSubscription;

  // ---------------------------------------------------------------------------
  // Getters
  // ---------------------------------------------------------------------------

  List<Jeepney> get jeepneys => List.unmodifiable(_jeepneys);

  List<Jeepney> get allActiveJeepneys => List.unmodifiable(_allActiveJeepneys);

  List<Jeepney> get activeDriverLocations =>
      List.unmodifiable(_activeDriverLocations);

  Jeepney? get selectedJeepney => _selectedJeepney;

  bool get isLoading => _isLoading;

  bool get isWatching => _isWatching;

  bool get isRefreshing => _isRefreshing;

  bool get isInitialized => _isInitialized;

  String? get error => _error;

  String? get originTerminal => _originTerminal;

  String? get destinationTerminal => _destinationTerminal;

  RouteFilter? get routeFilter => _routeFilter;

  Route? get selectedRoute => _selectedRoute;

  bool get showAllJeepneys => _showAllJeepneys;

  bool get showAllJeepneysState => _showAllJeepneys;

  LatLng? get userLocation => _userLocation;

  DateTime? get lastUpdated => _lastUpdated;

  bool get hasJeepneys => _jeepneys.isNotEmpty;

  bool get hasActiveDriverLocations => _activeDriverLocations.isNotEmpty;

  bool get hasSelection => _selectedJeepney != null;

  bool get hasRouteFilter => _routeFilter != null && _routeFilter!.isValid;

  /// Currently available route list.
  ///
  /// Keep empty muna kung wala ka pang route repository sa commuter app.
  List<Route> get availableRoutes => const [];

  /// Currently nearest jeepneys.
  ///
  /// Keep empty muna unless may implemented logic ka na sa nearest service.
  List<NearestJeepneyResult> get nearestJeepneys => const [];

  /// Warning message for route selection.
  String? get routeSelectionValidationMessage {
    if (_routeFilter == null) {
      return 'Please select a route first.';
    }

    return RouteFilter.validationMessage(
      routeId: _routeFilter!.routeId,
      originTerminal: _routeFilter!.originTerminal,
      destinationTerminal: _routeFilter!.destinationTerminal,
    );
  }

  // ---------------------------------------------------------------------------
  // Initialization
  // ---------------------------------------------------------------------------

  void initialize() {
    if (_isInitialized) {
      debugPrint('JeepneyViewModel: Already initialized.');
      return;
    }

    _isInitialized = true;
    _startWatchingDriverLocations();
  }

  void _startWatchingDriverLocations() {
    _driverLocationsSubscription?.cancel();

    _isLoading = true;
    _isWatching = true;
    _error = null;
    notifyListeners();

    try {
      final firebaseUser = firebase_auth.FirebaseAuth.instance.currentUser;
      debugPrint(
        'JeepneyViewModel: Active jeepney listener started. '
        'source=locations, '
        'firebaseUid=${firebaseUser?.uid ?? 'null'}, '
        'isAnonymous=${firebaseUser?.isAnonymous ?? false}',
      );

      _driverLocationsSubscription = _repository.watchAllActiveJeepneys().listen(
        (jeepneys) {
          debugPrint(
            '================ JEEPNEY VIEWMODEL UPDATE ================',
          );
          debugPrint(
            'JeepneyViewModel: Received ${jeepneys.length} active driver locations.',
          );

          for (final jeepney in jeepneys) {
            debugPrint(
              'JeepneyViewModel: '
              'id=${jeepney.id}, '
              'routeId=${jeepney.routeId}, '
              'destination=${jeepney.destinationTerminal}, '
              'lat=${jeepney.latitude}, '
              'lng=${jeepney.longitude}, '
              'isActive=${jeepney.isActive}',
            );
          }

          _activeDriverLocations = _sanitizeJeepneys(jeepneys);
          _allActiveJeepneys = List<Jeepney>.from(_activeDriverLocations);
          _syncFilteredJeepneys();

          _isLoading = false;
          _isWatching = true;
          _isRefreshing = false;
          _lastUpdated = DateTime.now();
          _error = null;

          debugPrint(
            'JeepneyViewModel: After sanitize/filter: '
            'activeDriverLocations=${_activeDriverLocations.length}, '
            'jeepneys=${_jeepneys.length}',
          );
          debugPrint(
            '===========================================================',
          );

          notifyListeners();
        },
        onError: (error, stackTrace) {
          debugPrint('JeepneyViewModel: Stream error: $error');
          debugPrint('JeepneyViewModel: StackTrace: $stackTrace');

          _isLoading = false;
          _isWatching = false;
          _isRefreshing = false;
          _error = error.toString();

          notifyListeners();
        },
      );
    } catch (e, stackTrace) {
      debugPrint('JeepneyViewModel: Failed to start watching locations: $e');
      debugPrint('JeepneyViewModel: StackTrace: $stackTrace');

      _isLoading = false;
      _isWatching = false;
      _isRefreshing = false;
      _error = e.toString();

      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // Route filter
  // ---------------------------------------------------------------------------

  bool setDestinationFilter(String destinationTerminal) {
    final normalizedDestinationCode = _normalizeCode(destinationTerminal);

    final newOrigin = normalizedDestinationCode == TerminalConstants.lucbanCode
        ? TerminalConstants.staCruzCode
        : TerminalConstants.lucbanCode;

    final routeId = RouteDirections.getRouteIdForDirection(
      newOrigin,
      normalizedDestinationCode,
    );

    final validationMessage = RouteFilter.validationMessage(
      routeId: routeId,
      originTerminal: newOrigin,
      destinationTerminal: normalizedDestinationCode,
    );

    if (validationMessage != null) {
      debugPrint(
        'JeepneyViewModel: Invalid destination filter. Message: $validationMessage',
      );

      _routeFilter = null;
      _originTerminal = null;
      _destinationTerminal = null;
      _selectedRoute = null;
      _showAllJeepneys = true;
      _syncFilteredJeepneys();

      notifyListeners();
      return false;
    }

    _routeFilter = RouteFilter(
      routeId: routeId,
      originTerminal: newOrigin,
      destinationTerminal: normalizedDestinationCode,
    );

    _originTerminal = newOrigin;
    _destinationTerminal = normalizedDestinationCode;
    _showAllJeepneys = false;

    _syncFilteredJeepneys();

    debugPrint(
      'JeepneyViewModel: Destination filter set. '
      'origin=$_originTerminal, '
      'destination=$_destinationTerminal, '
      'routeId=$routeId, '
      'filteredJeepneys=${_jeepneys.length}',
    );

    notifyListeners();
    return true;
  }

  bool setRouteFilter({
    required String originTerminal,
    required String destinationTerminal,
  }) {
    final normalizedOrigin = _normalizeCode(originTerminal);
    final normalizedDestination = _normalizeCode(destinationTerminal);

    final routeId = RouteDirections.getRouteIdForDirection(
      normalizedOrigin,
      normalizedDestination,
    );

    final validationMessage = RouteFilter.validationMessage(
      routeId: routeId,
      originTerminal: normalizedOrigin,
      destinationTerminal: normalizedDestination,
    );

    if (validationMessage != null) {
      debugPrint(
        'JeepneyViewModel: Invalid route filter. Message: $validationMessage',
      );

      _routeFilter = null;
      _originTerminal = null;
      _destinationTerminal = null;
      _selectedRoute = null;
      _showAllJeepneys = true;
      _syncFilteredJeepneys();

      notifyListeners();
      return false;
    }

    _routeFilter = RouteFilter(
      routeId: routeId,
      originTerminal: normalizedOrigin,
      destinationTerminal: normalizedDestination,
    );

    _originTerminal = normalizedOrigin;
    _destinationTerminal = normalizedDestination;
    _showAllJeepneys = false;

    _syncFilteredJeepneys();

    debugPrint(
      'JeepneyViewModel: Route filter set. '
      'origin=$_originTerminal, '
      'destination=$_destinationTerminal, '
      'routeId=$routeId, '
      'filteredJeepneys=${_jeepneys.length}',
    );

    notifyListeners();
    return true;
  }

  void clearRouteFilter() {
    _routeFilter = null;
    _originTerminal = null;
    _destinationTerminal = null;
    _selectedRoute = null;
    _showAllJeepneys = true;

    _syncFilteredJeepneys();

    debugPrint('JeepneyViewModel: Route filter cleared.');

    notifyListeners();
  }

  String? validateRouteSelection({
    required String? routeId,
    required String? originTerminal,
    required String? destinationTerminal,
  }) {
    return RouteFilter.validationMessage(
      routeId: routeId,
      originTerminal: originTerminal,
      destinationTerminal: destinationTerminal,
    );
  }

  // ---------------------------------------------------------------------------
  // Selection
  // ---------------------------------------------------------------------------

  void selectJeepney(Jeepney jeepney) {
    _selectedJeepney = jeepney;
    notifyListeners();
  }

  void clearSelectedJeepney() {
    _selectedJeepney = null;
    notifyListeners();
  }

  void selectRoute(Route route) {
    _selectedRoute = route;
    _showAllJeepneys = false;
    notifyListeners();
  }

  void clearSelectedRoute() {
    _selectedRoute = null;
    notifyListeners();
  }

  void toggleShowAllJeepneys() {
    _showAllJeepneys = !_showAllJeepneys;
    _syncFilteredJeepneys();

    debugPrint(
      'JeepneyViewModel: showAllJeepneys=$_showAllJeepneys, '
      'jeepneys=${_jeepneys.length}',
    );

    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Location
  // ---------------------------------------------------------------------------

  void updateUserLocation(double lat, double lng) {
    if (!_isValidLatLng(lat, lng)) {
      debugPrint(
        'JeepneyViewModel: Ignored invalid user location: lat=$lat, lng=$lng',
      );
      return;
    }

    _userLocation = LatLng(lat, lng);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Refresh
  // ---------------------------------------------------------------------------

  Future<void> refresh({bool showLoading = true}) async {
    if (showLoading) {
      _isRefreshing = true;
      _error = null;
      notifyListeners();
    }

    try {
      debugPrint('JeepneyViewModel: Manual refresh started.');

      final jeepneys = await _repository.getAllActiveJeepneys();

      _activeDriverLocations = _sanitizeJeepneys(jeepneys);
      _allActiveJeepneys = List<Jeepney>.from(_activeDriverLocations);
      _syncFilteredJeepneys();

      _lastUpdated = DateTime.now();
      _error = null;

      debugPrint(
        'JeepneyViewModel: Manual refresh complete. '
        'activeDriverLocations=${_activeDriverLocations.length}, '
        'jeepneys=${_jeepneys.length}',
      );
    } catch (e, stackTrace) {
      debugPrint('JeepneyViewModel: Refresh error: $e');
      debugPrint('JeepneyViewModel: StackTrace: $stackTrace');

      _error = e.toString();
    } finally {
      if (showLoading) {
        _isRefreshing = false;
      }

      notifyListeners();
    }
  }

  void restartWatching() {
    debugPrint('JeepneyViewModel: Restart watching requested.');
    _startWatchingDriverLocations();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Internal filtering helpers
  // ---------------------------------------------------------------------------

  void _syncFilteredJeepneys() {
    if (_activeDriverLocations.isEmpty) {
      _jeepneys = [];
      return;
    }

    if (!hasRouteFilter || _showAllJeepneys) {
      _jeepneys = List<Jeepney>.from(_activeDriverLocations);
      return;
    }

    final selectedDestination = _routeFilter!.destinationTerminal;

    debugPrint(
      'JeepneyViewModel: Applying selected destination filter. '
      'selectedDestination=$selectedDestination, '
      'activeDriverLocations=${_activeDriverLocations.length}',
    );

    _jeepneys = _activeDriverLocations.where((jeepney) {
      final destinationMatches = _destinationMatches(
        jeepney.destinationTerminal,
        selectedDestination,
      );

      if (!destinationMatches) {
        debugPrint(
          'JeepneyViewModel: Skipped ${jeepney.id}: destination mismatch. '
          'selectedDestination=$selectedDestination, '
          'jeepneyDestination=${jeepney.destinationTerminal}',
        );
      }

      return destinationMatches;
    }).toList();

    debugPrint(
      'JeepneyViewModel: Active/on-trip jeepneys after selected filter: '
      '${_jeepneys.length}',
    );
  }

  List<Jeepney> _sanitizeJeepneys(List<Jeepney> jeepneys) {
    final sanitized = <Jeepney>[];

    for (final jeepney in jeepneys) {
      final hasValidLocation = _isValidLatLng(
        jeepney.latitude,
        jeepney.longitude,
      );

      if (!hasValidLocation) {
        debugPrint(
          'JeepneyViewModel: Skipped jeepney with invalid location. '
          'id=${jeepney.id}, '
          'lat=${jeepney.latitude}, '
          'lng=${jeepney.longitude}',
        );
        continue;
      }

      if (!jeepney.isActive) {
        debugPrint(
          'JeepneyViewModel: Skipped inactive jeepney. '
          'id=${jeepney.id}, '
          'reason=not onTrip or offline, '
          'destination=${jeepney.destinationTerminal}',
        );
        continue;
      }

      sanitized.add(jeepney);
    }

    return sanitized;
  }

  bool _destinationMatches(String? jeepneyDestination, String selectedValue) {
    final jeepDest = _normalizeDestination(jeepneyDestination);
    final selectedCode = _normalizeCode(selectedValue);
    final selectedDisplay = _normalizeDestination(
      TerminalConstants.fromCode(selectedCode),
    );

    if (jeepDest.isEmpty) {
      return false;
    }

    return jeepDest == selectedCode ||
        jeepDest == selectedDisplay ||
        jeepDest.contains(selectedCode) ||
        selectedCode.contains(jeepDest) ||
        jeepDest.contains(selectedDisplay) ||
        selectedDisplay.contains(jeepDest);
  }

  String _normalizeCode(String value) {
    final normalized = value.trim().toLowerCase();
    final key = normalized.replaceAll(RegExp(r'[^a-z0-9]'), '');

    if (normalized == TerminalConstants.lucbanCode ||
        key == 'terminala' ||
        key.contains('lucban')) {
      return TerminalConstants.lucbanCode;
    }

    if (normalized == TerminalConstants.staCruzCode ||
        key == 'terminalb' ||
        key.contains('stacruz') ||
        key.contains('santacruz')) {
      return TerminalConstants.staCruzCode;
    }

    return normalized;
  }

  String _normalizeDestination(String? value) {
    if (value == null) {
      return '';
    }

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
      return TerminalConstants.lucbanCode;
    }

    if (key == 'terminalb' ||
        key.contains('stacruz') ||
        key.contains('santacruz')) {
      return TerminalConstants.staCruzCode;
    }

    return cleaned;
  }

  bool _isValidLatLng(double lat, double lng) {
    return lat.isFinite &&
        lng.isFinite &&
        lat >= -90 &&
        lat <= 90 &&
        lng >= -180 &&
        lng <= 180 &&
        !(lat == 0 && lng == 0);
  }

  // ---------------------------------------------------------------------------
  // Dispose
  // ---------------------------------------------------------------------------

  @override
  void dispose() {
    _driverLocationsSubscription?.cancel();
    _isWatching = false;
    super.dispose();
  }
}
