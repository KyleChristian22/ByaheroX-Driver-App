import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show
        HapticFeedback,
        MethodCall,
        MethodChannel,
        MissingPluginException,
        PlatformException;
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_map/flutter_map.dart' hide LatLngTween;
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../../core/booking_status.dart';
import '../../../core/theme/app_theme.dart';
import '../../../services/analytics_tracking_service.dart';
import '../../../services/firestore_service.dart';
import '../../../services/internet_connectivity_service.dart';
import '../../../services/location_warning_service.dart';
import '../../../services/route_service.dart';
import '../../../services/routing_service.dart';
import '../../../utils/latlng_tween.dart';
import '../../../utils/location_service.dart';
import '../../viewmodels/trip_viewmodel.dart';
import '../../viewmodels/language_viewmodel.dart';
import '../../viewmodels/jeepney_viewmodel.dart';
import '../../widgets/app_feedback.dart';
import '../../widgets/driver_app_background.dart';
import '../../widgets/passenger_list_sheet.dart';

enum _LocationUpdateNetworkState {
  online,
  noInternet,
  weakConnection,
}

/// Trip Screen for Driver App.
///
/// Updated fixes:
/// - Live GPS marker moves even before trip starts.
/// - Firestore location updates only happen while trip is active.
/// - Start Trip force-syncs locations/{jeepneyId} with commuter aliases.
/// - End Trip force-syncs locations/{jeepneyId}.isOnTrip/onTrip = false.
/// - RouteService.saveRouteToFirestore includes routeId and terminal data.
/// - Uses FirestoreService.watchSharedCommuterLocations instead of raw snapshot parsing.
/// - Safer marker animation to avoid stale animation callbacks.
/// - Safer jeepney initialization fallback using Firebase Auth UID.
/// - Avoids Provider access inside dispose.
class TripScreen extends StatefulWidget {
  const TripScreen({super.key});

  @override
  State<TripScreen> createState() => _TripScreenState();
}

class _TripScreenState extends State<TripScreen> with TickerProviderStateMixin {
  final MapController _mapController = MapController();
  final LocationSmoother _locationSmoother = LocationSmoother();
  static const MethodChannel _deviceSettingsChannel =
      MethodChannel('byaherox/device_settings');

  static const LatLng mapCenter = LatLng(14.196, 121.485);

  static const double _firestoreMinMovement = 5.0;
  static const Duration _forceLocationWriteInterval = Duration(seconds: 8);

  static const double _gpsJumpThresholdMeters = 250.0;
  static const double _maxAcceptedAccuracyMeters = 100.0;
  static const double _ignoreGpsNoiseMeters = 1.5;
  static const double _minimumAnimationDistanceMeters = 2.0;
  static const double _routeCardEstimatedHeight = 154.0;

  static const Duration _minimumMarkerAnimationDuration =
      Duration(milliseconds: 650);
  static const Duration _maximumMarkerAnimationDuration =
      Duration(milliseconds: 1700);
  static const Duration _maximumTripDuration = Duration(hours: 2);

  LatLng _currentLocation = mapCenter;
  double _currentHeading = 0.0;
  double _mapRotation = 0.0;
  double _currentSpeedMps = 0.0;

  bool _isLoadingLocation = false;
  bool _isLoadingRoute = false;
  int _routeFetchGeneration = 0;
  bool _isFirstLocationUpdate = true;
  bool _hasCenteredMapOnFirstFix = false;
  bool _hasRealLocationFix = false;
  bool _isTerminalFocusActive = false;
  bool _isFirestoreLocationUpdateInProgress = false;
  DateTime? _firestoreUpdateStartedAt;
  bool _isTripTrackingStarted = false;
  DateTime? _lastFirestoreLocationWriteAt;

  int _markerAnimationGeneration = 0;

  List<LatLng> _routePoints = [];
  RouteSnapper? _routeSnapper;
  EdgeInsets? _latestMapCameraPadding;
  Offset? _latestMapCameraOffset;

  String? _currentJeepneyId;
  LatLng? _lastFirestorePosition;

  LocationSettings _activeTripLocationSettings({
    int distanceFilter = 2,
  }) {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: distanceFilter,
        intervalDuration: const Duration(seconds: 5),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'ByaheroX live trip monitoring',
          notificationText:
              'Sharing jeepney location while this trip is active.',
          notificationChannelName: 'Live trip monitoring',
          enableWakeLock: true,
          setOngoing: true,
        ),
      );
    }

    return LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: distanceFilter,
    );
  }

  StreamSubscription<Position>? _gpsSubscription;
  Timer? _locationUpdateTimer;
  Timer? _autoStartTripTimer;
  Timer? _autoEndTripTimer;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
      _tripScheduleSubscription;
  StreamSubscription<List<CommuterWaitingLocation>>? _dropOffAlertSubscription;
  bool _isDropOffDialogShowing = false;
  final Set<String> _shownDropOffAlertIds = <String>{};
  final AudioPlayer _dropOffAlertPlayer = AudioPlayer();

  StreamSubscription<List<CommuterWaitingLocation>>?
      _commuterLocationsSubscription;
  List<CommuterWaitingLocation> _commuterLocations = [];
  Map<String, dynamic>? _currentTripSchedule;
  final Set<String> _autoOnboardedCommuters = {};
  List<Map<String, dynamic>> _todayTripSchedules = [];
  bool _isLoadingPassengers = false;
  bool _isUpdatingManualPassengerCount = false;
  bool _isAutoStartingTrip = false;

  late final AnimationController _markerAnimationController;
  Animation<LatLng>? _markerPositionAnimation;
  Animation<double>? _markerHeadingAnimation;

  _LocationUpdateNetworkState _locationUpdateNetworkState =
      _LocationUpdateNetworkState.online;

  @override
  void initState() {
    super.initState();

    _markerAnimationController = AnimationController(
      vsync: this,
      duration: _minimumMarkerAnimationDuration,
    )..addListener(_onMarkerAnimationTick);

    _getCurrentLocation();
    _startLiveMapLocationWatcher();
    _initializeJeepney();

    InternetConnectivityService.startMonitoring(
      onConnectivityChanged: _onConnectivityChanged,
    );
  }

  @override
  void dispose() {
    _markerAnimationGeneration++;

    _stopLocationTracking();
    _stopLiveMapLocationWatcher();
    _stopWatchingCommuterLocations();
    _stopWatchingDropOffAlerts();
    unawaited(_stopDropOffAlertSound());
    unawaited(_dropOffAlertPlayer.dispose());
    _autoStartTripTimer?.cancel();
    _autoEndTripTimer?.cancel();
    _tripScheduleSubscription?.cancel();

    _markerAnimationController.removeListener(_onMarkerAnimationTick);
    _markerAnimationController.stop();
    _markerAnimationController.dispose();

    _mapController.dispose();

    InternetConnectivityService.stopMonitoring();
    LocationWarningService.resetWarningCooldowns();

    super.dispose();
  }

  static String? _crowdStatusValue(CrowdLevel? level) {
    if (level == null) return null;

    switch (level) {
      case CrowdLevel.maluwag:
        return 'maluwag';
      case CrowdLevel.sakto:
        return 'sakto';
      case CrowdLevel.puno:
        return 'puno';
    }
  }

  static String _crowdStatusLabel(CrowdLevel level) {
    switch (level) {
      case CrowdLevel.maluwag:
        return 'Maluwag';
      case CrowdLevel.sakto:
        return 'Sakto';
      case CrowdLevel.puno:
        return 'Puno';
    }
  }

  static Color _crowdStatusColor(CrowdLevel level) {
    switch (level) {
      case CrowdLevel.maluwag:
        return const Color(0xFF16A34A);
      case CrowdLevel.sakto:
        return const Color(0xFFEAB308);
      case CrowdLevel.puno:
        return const Color(0xFFDC2626);
    }
  }

  String _terminalDisplayName(Terminal terminal) {
    switch (terminal) {
      case Terminal.terminalA:
        return 'Lucban';
      case Terminal.terminalB:
        return 'Sta. Cruz';
    }
  }

  String _terminalFullName(Terminal terminal) {
    return '${_terminalDisplayName(terminal)} Terminal';
  }

  bool _isTripScheduleCompleted(Map<String, dynamic> schedule) {
    final status = _firstNonEmpty([
      schedule['status'],
      schedule['tripStatus'],
      schedule['historyStatus'],
    ]).toLowerCase();
    return status == 'completed' ||
        status == 'done' ||
        status == 'finished' ||
        status == 'cancelled' ||
        status == 'canceled' ||
        _isPastScheduledTripWindow(schedule);
  }

  bool _isTripScheduleCancelled(Map<String, dynamic> schedule) {
    final status = _firstNonEmpty([
      schedule['status'],
      schedule['tripStatus'],
      schedule['historyStatus'],
    ]).toLowerCase();
    return status == 'cancelled' || status == 'canceled';
  }

  bool _isTripScheduleActive(Map<String, dynamic> schedule) {
    final status = _firstNonEmpty([
      schedule['status'],
      schedule['tripStatus'],
    ]).toLowerCase();
    return status == 'active' ||
        status == 'ontrip' ||
        status == 'on-trip' ||
        status == 'on trip' ||
        schedule['isOnTrip'] == true ||
        schedule['onTrip'] == true;
  }

  bool _isTripScheduleBookable(Map<String, dynamic> schedule) {
    return !_isTripScheduleCompleted(schedule) &&
        !_isTripScheduleActive(schedule) &&
        !_isScheduleFull(schedule) &&
        !_isScheduleTimePassed(schedule) &&
        _isWithinBookingWindow(schedule);
  }

  bool _isWithinBookingWindow(Map<String, dynamic> schedule) {
    final scheduledAt = _tripScheduledDateTime(schedule);
    if (scheduledAt == null) return false;

    final now = DateTime.now();
    final defaultBookingStartsAt =
        scheduledAt.subtract(const Duration(minutes: 25));
    final customBookingStartsAt = _dateTimeFromScheduleValue(
      schedule['bookingOpensAt'],
    );
    final bookingStartsAt = customBookingStartsAt != null &&
            customBookingStartsAt.isBefore(defaultBookingStartsAt)
        ? customBookingStartsAt
        : defaultBookingStartsAt;
    return !now.isBefore(bookingStartsAt) && now.isBefore(scheduledAt);
  }

  bool _isNearestBookableSchedule(
    Map<String, dynamic> schedule,
    List<Map<String, dynamic>> schedules,
  ) {
    if (!_isTripScheduleBookable(schedule)) return false;

    final bookable = schedules.where(_isTripScheduleBookable).toList()
      ..sort(_compareTripScheduleOrder);
    if (bookable.isEmpty) return false;

    final currentId = _firstNonEmpty([schedule['id']]);
    final nearestId = _firstNonEmpty([bookable.first['id']]);
    if (currentId.isNotEmpty && nearestId.isNotEmpty) {
      return currentId == nearestId;
    }
    return identical(schedule, bookable.first);
  }

  int _compareTripScheduleOrder(
    Map<String, dynamic> a,
    Map<String, dynamic> b,
  ) {
    final aTime = _tripScheduledDateTime(a);
    final bTime = _tripScheduledDateTime(b);
    if (aTime != null && bTime != null) return aTime.compareTo(bTime);
    if (aTime != null) return -1;
    if (bTime != null) return 1;

    final aOrder = int.tryParse(_firstNonEmpty([a['scheduleOrder']])) ?? 0;
    final bOrder = int.tryParse(_firstNonEmpty([b['scheduleOrder']])) ?? 0;
    return aOrder.compareTo(bOrder);
  }

  DateTime? _tripScheduledDateTime(Map<String, dynamic> schedule) {
    final scheduledAt = schedule['scheduledAt'];
    if (scheduledAt is Timestamp) return scheduledAt.toDate();
    if (scheduledAt is DateTime) return scheduledAt;
    if (scheduledAt is String) {
      final parsed = DateTime.tryParse(scheduledAt);
      if (parsed != null) return parsed;
    }

    final scheduleDate = _firstNonEmpty([
      schedule['scheduleDate'],
      schedule['tripDate'],
    ]);
    final scheduleTime = _firstNonEmpty([
      schedule['scheduleTime'],
      schedule['departureTime'],
      schedule['tripTime'],
    ]);

    final dateMatch =
        RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(scheduleDate);
    final parsedTime = _parseScheduleTimeOfDay(scheduleTime);

    if (dateMatch == null || parsedTime == null) return null;

    return DateTime(
      int.parse(dateMatch.group(1)!),
      int.parse(dateMatch.group(2)!),
      int.parse(dateMatch.group(3)!),
      parsedTime.hour,
      parsedTime.minute,
    );
  }

  DateTime? _dateTimeFromScheduleValue(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  TimeOfDay? _parseScheduleTimeOfDay(String value) {
    final normalized = value.trim().toUpperCase();
    if (normalized.isEmpty) return null;

    final twelveHourMatch =
        RegExp(r'^(\d{1,2}):(\d{2})\s*(AM|PM)$').firstMatch(normalized);
    if (twelveHourMatch != null) {
      var hour = int.parse(twelveHourMatch.group(1)!);
      final minute = int.parse(twelveHourMatch.group(2)!);
      final period = twelveHourMatch.group(3)!;
      if (hour < 1 || hour > 12 || minute > 59) return null;
      if (period == 'AM' && hour == 12) hour = 0;
      if (period == 'PM' && hour != 12) hour += 12;
      return TimeOfDay(hour: hour, minute: minute);
    }

    final twentyFourHourMatch =
        RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(normalized);
    if (twentyFourHourMatch != null) {
      final hour = int.parse(twentyFourHourMatch.group(1)!);
      final minute = int.parse(twentyFourHourMatch.group(2)!);
      if (hour > 23 || minute > 59) return null;
      return TimeOfDay(hour: hour, minute: minute);
    }

    return null;
  }

  String _firstNonEmpty(List<dynamic> values) {
    for (final value in values) {
      final text = value?.toString().trim() ?? '';
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  // ignore: unused_element
  String _todayDateKey() {
    final now = DateTime.now();
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    return '${now.year}-$month-$day';
  }

  Terminal? _terminalFromSchedule(Map<String, dynamic> schedule) {
    final destination = _firstNonEmpty([
      schedule['destinationTerminal'],
      schedule['destination'],
      schedule['to'],
    ]).toLowerCase();
    final route = _firstNonEmpty([
      schedule['routeName'],
      schedule['route'],
      schedule['currentRoute'],
    ]).toLowerCase();

    if (destination.contains('lucban')) return Terminal.terminalA;
    if (destination.contains('sta') || destination.contains('santa')) {
      return Terminal.terminalB;
    }

    if (route.contains('sta') &&
        route.contains('cruz') &&
        route.contains('lucban')) {
      final lucbanIndex = route.indexOf('lucban');
      final staIndex = route.indexOf('sta');
      return staIndex < lucbanIndex ? Terminal.terminalA : Terminal.terminalB;
    }

    return null;
  }

  Terminal _terminalFromScheduleOrRoute(Map<String, dynamic> schedule) {
    final terminal = _terminalFromSchedule(schedule);
    if (terminal != null) return terminal;

    final routeText = _tripRouteLabel(schedule).toLowerCase();
    final hasLucban = routeText.contains('lucban');
    final hasStaCruz = routeText.contains('sta') ||
        routeText.contains('santa') ||
        routeText.contains('cruz');

    if (hasLucban && hasStaCruz) {
      final lucbanIndex = routeText.indexOf('lucban');
      final staIndex = routeText.contains('sta')
          ? routeText.indexOf('sta')
          : routeText.indexOf('santa');
      if (lucbanIndex >= 0 && staIndex >= 0) {
        return staIndex < lucbanIndex ? Terminal.terminalA : Terminal.terminalB;
      }
    }

    return Terminal.terminalB;
  }

  CrowdLevel _crowdLevelFromSchedule(Map<String, dynamic> schedule) {
    final passengerCount = _intFromSchedule(schedule['passengerCount']) ??
        _bookedPassengerCount(schedule);
    return _crowdLevelForPassengerCount(
      passengerCount,
      _capacityFromSchedule(schedule),
    );
  }

  CrowdLevel _crowdLevelForPassengerCount(int passengerCount, int capacity) {
    final safeCount = math.max(0, passengerCount);
    if (capacity > 0 && safeCount >= capacity) return CrowdLevel.puno;
    if (safeCount >= 18) return CrowdLevel.puno;
    if (safeCount >= 9) return CrowdLevel.sakto;
    return CrowdLevel.maluwag;
  }

  CrowdLevel _automaticCrowdLevel() {
    final schedule = _currentTripSchedule;
    if (schedule != null) return _crowdLevelFromSchedule(schedule);
    return CrowdLevel.maluwag;
  }

  String _setAutomaticCrowdStatus(TripViewModel tripViewModel) {
    final crowdLevel = _automaticCrowdLevel();
    tripViewModel.setCrowdLevel(crowdLevel);
    return _crowdStatusValue(crowdLevel) ?? 'maluwag';
  }

  int? _intFromSchedule(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  int _bookedPassengerCount(Map<String, dynamic> schedule) {
    final passengers = schedule['bookedPassengers'];
    if (passengers is List) {
      return passengers.fold<int>(0, (total, passenger) {
        if (passenger is! Map) return total;
        final data = Map<String, dynamic>.from(passenger);
        final count = _intFromSchedule(
              data['passengerCount'] ??
                  data['waitingCount'] ??
                  data['count'] ??
                  data['quantity'],
            ) ??
            1;
        return total + math.max(1, count);
      });
    }
    return 0;
  }

  int _capacityFromSchedule(Map<String, dynamic> schedule) {
    try {
      final jeepneyCapacity = context.read<JeepneyViewModel>().capacity;
      if (jeepneyCapacity > 0) return jeepneyCapacity;
    } catch (_) {
      // Fall back to schedule mirrors when the view model is unavailable.
    }

    final fromSchedule = _intFromSchedule(schedule['maxCapacity']) ??
        _intFromSchedule(schedule['capacity']) ??
        _intFromSchedule(schedule['seatingCapacity']) ??
        _intFromSchedule(schedule['maxPassengers']);
    if (fromSchedule != null && fromSchedule > 0) return fromSchedule;
    return 0;
  }

  int _passengerCountFromSchedule(Map<String, dynamic> schedule) {
    return _intFromSchedule(
          schedule['passengerCount'] ??
              schedule['currentPassengerCount'] ??
              schedule['currentPassengers'] ??
              schedule['passengers'] ??
              schedule['occupancy'],
        ) ??
        _onBoardPassengerCount(schedule);
  }

  bool _isScheduleFull(Map<String, dynamic> schedule) {
    final capacity = _capacityFromSchedule(schedule);
    if (capacity <= 0) return false;
    return _passengerCountFromSchedule(schedule) >= capacity;
  }

  bool _canStartEarlyFullSchedule(Map<String, dynamic>? schedule) {
    if (schedule == null) return false;
    return !_isTripScheduleCompleted(schedule) &&
        !_isTripScheduleActive(schedule) &&
        !_isScheduleReadyToStart(schedule) &&
        _isScheduleFull(schedule);
  }

  bool _canStartScheduleNow(Map<String, dynamic>? schedule) {
    return _isScheduleReadyToStart(schedule) ||
        _canStartEarlyFullSchedule(schedule);
  }

  void _onMarkerAnimationTick() {
    if (!mounted) return;

    final positionAnimation = _markerPositionAnimation;
    final headingAnimation = _markerHeadingAnimation;

    if (positionAnimation == null) return;

    setState(() {
      _currentLocation = positionAnimation.value;

      if (headingAnimation != null) {
        _currentHeading = _normalizeHeading(headingAnimation.value);
      }
    });

    final tripViewModel = context.read<TripViewModel>();

    if (tripViewModel.isTripActive &&
        _hasCenteredMapOnFirstFix &&
        !_isTerminalFocusActive) {
      _moveMapSafely(
        _currentLocation,
        _mapController.camera.zoom,
      );
    }
  }

  double _normalizeHeading(double heading) {
    var normalized = heading % 360;

    if (normalized < 0) {
      normalized += 360;
    }

    return normalized;
  }

  double _validHeading(double? heading) {
    if (heading == null || heading.isNaN || heading.isInfinite || heading < 0) {
      return _currentHeading;
    }

    return _normalizeHeading(heading);
  }

  double _validSpeed(double? speed) {
    if (speed == null || speed.isNaN || speed.isInfinite || speed < 0) {
      return 0.0;
    }

    return speed;
  }

  bool _isValidLatLng(LatLng position) {
    final lat = position.latitude;
    final lng = position.longitude;

    if (lat.isNaN || lng.isNaN) return false;
    if (lat.isInfinite || lng.isInfinite) return false;
    if (lat == 0 && lng == 0) return false;

    return lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180;
  }

  double _calculateAnimatedHeading({
    required double from,
    required double to,
  }) {
    final normalizedFrom = _normalizeHeading(from);
    final normalizedTo = _normalizeHeading(to);

    double difference = normalizedTo - normalizedFrom;

    if (difference > 180) {
      difference -= 360;
    } else if (difference < -180) {
      difference += 360;
    }

    return normalizedFrom + difference;
  }

  bool _isReliablePosition(Position position) {
    if (position.latitude == 0 && position.longitude == 0) {
      debugPrint('Skipped invalid GPS reading: 0,0');
      return false;
    }

    if (position.latitude.isNaN || position.longitude.isNaN) {
      debugPrint('Skipped invalid GPS reading: NaN');
      return false;
    }

    if (position.latitude.isInfinite || position.longitude.isInfinite) {
      debugPrint('Skipped invalid GPS reading: Infinite');
      return false;
    }

    if (position.accuracy.isNaN ||
        position.accuracy.isInfinite ||
        position.accuracy <= 0) {
      debugPrint('Skipped invalid GPS accuracy');
      return false;
    }

    if (position.accuracy > _maxAcceptedAccuracyMeters) {
      debugPrint(
        'Skipped poor GPS reading. Accuracy: ${position.accuracy.toStringAsFixed(1)}m',
      );
      return false;
    }

    return true;
  }

  LatLng _snapPositionIfPossible(LatLng position) {
    final snapper = _routeSnapper;

    if (snapper == null || _routePoints.length < 2) {
      return position;
    }

    return snapper.snapToRoute(position) ?? position;
  }

  Duration _animationDurationForDistance(double distanceMeters) {
    final clamped = distanceMeters.clamp(2.0, 80.0);
    final factor = clamped / 80.0;

    final minMs = _minimumMarkerAnimationDuration.inMilliseconds;
    final maxMs = _maximumMarkerAnimationDuration.inMilliseconds;

    final durationMs = minMs + ((maxMs - minMs) * factor).round();

    return Duration(milliseconds: durationMs);
  }

  double _bearingBetween(LatLng start, LatLng end) {
    final lat1 = _degreesToRadians(start.latitude);
    final lon1 = _degreesToRadians(start.longitude);
    final lat2 = _degreesToRadians(end.latitude);
    final lon2 = _degreesToRadians(end.longitude);

    final dLon = lon2 - lon1;

    final y = math.sin(dLon) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);

    return _normalizeHeading(_radiansToDegrees(math.atan2(y, x)));
  }

  double _degreesToRadians(double degrees) {
    return degrees * math.pi / 180.0;
  }

  double _radiansToDegrees(double radians) {
    return radians * 180.0 / math.pi;
  }

  Future<void> _startLiveMapLocationWatcher() async {
    if (_gpsSubscription != null) return;

    final hasPermission = await _checkLocationPermission();

    if (!mounted || !hasPermission) return;

    _gpsSubscription = Geolocator.getPositionStream(
      locationSettings: _activeTripLocationSettings(distanceFilter: 2),
    ).listen(
      _handleLivePositionUpdate,
      onError: (Object e) {
        unawaited(_handleLocationTrackingError(e));
      },
    );
  }

  void _stopLiveMapLocationWatcher() {
    _gpsSubscription?.cancel();
    _gpsSubscription = null;
  }

  void _handleLivePositionUpdate(Position position) {
    if (!mounted) return;
    if (!_isReliablePosition(position)) return;

    final tripViewModel = context.read<TripViewModel>();
    final routeId = _getRouteIdFromName(tripViewModel.currentRoute);

    unawaited(_updateLocationInFirebase(position, routeId));
  }

  void _animateDriverMarkerTo(
    LatLng newPosition, {
    double? heading,
    Duration? duration,
    bool moveCamera = false,
    double? cameraZoom,
  }) {
    if (!mounted) return;

    final animationGeneration = ++_markerAnimationGeneration;

    final startPosition = _currentLocation;
    final distance = _calculateDistance(startPosition, newPosition);

    if (_isFirstLocationUpdate) {
      final initialHeading = _validHeading(heading);

      setState(() {
        _currentLocation = newPosition;
        _currentHeading = initialHeading;
        _isFirstLocationUpdate = false;
      });

      if (moveCamera) {
        _moveMapSafely(newPosition, cameraZoom ?? 16.0);
      }

      return;
    }

    if (distance < _ignoreGpsNoiseMeters) {
      if (moveCamera) {
        _moveMapSafely(newPosition, cameraZoom ?? _mapController.camera.zoom);
      }
      return;
    }

    double nextHeading = _validHeading(heading);

    if ((heading == null || heading.isNaN || heading < 0) &&
        distance >= _minimumAnimationDistanceMeters) {
      nextHeading = _bearingBetween(startPosition, newPosition);
    }

    final isHugeJump = distance > _gpsJumpThresholdMeters;

    if (isHugeJump) {
      debugPrint(
        'Large GPS jump detected: ${distance.toStringAsFixed(1)}m. Moving marker directly.',
      );

      _markerAnimationController.stop();

      setState(() {
        _currentLocation = newPosition;
        _currentHeading = nextHeading;
      });

      if (moveCamera) {
        _moveMapSafely(
          newPosition,
          cameraZoom ?? _mapController.camera.zoom,
        );
      }

      return;
    }

    if (distance < _minimumAnimationDistanceMeters) {
      setState(() {
        _currentLocation = newPosition;
        _currentHeading = nextHeading;
      });

      if (moveCamera) {
        _moveMapSafely(
          newPosition,
          cameraZoom ?? _mapController.camera.zoom,
        );
      }

      return;
    }

    _markerAnimationController.stop();

    final animationDuration =
        duration ?? _animationDurationForDistance(distance);

    _markerAnimationController.duration = animationDuration;

    final curvedAnimation = CurvedAnimation(
      parent: _markerAnimationController,
      curve: Curves.easeInOutCubic,
    );

    final animatedHeadingEnd = _calculateAnimatedHeading(
      from: _currentHeading,
      to: nextHeading,
    );

    _markerPositionAnimation = LatLngTween(
      begin: startPosition,
      end: newPosition,
    ).animate(curvedAnimation);

    _markerHeadingAnimation = Tween<double>(
      begin: _currentHeading,
      end: animatedHeadingEnd,
    ).animate(curvedAnimation);

    _markerAnimationController.forward(from: 0).whenComplete(() {
      if (!mounted) return;
      if (animationGeneration != _markerAnimationGeneration) return;

      setState(() {
        _currentLocation = newPosition;
        _currentHeading = nextHeading;
      });

      if (moveCamera) {
        _moveMapSafely(
          newPosition,
          cameraZoom ?? _mapController.camera.zoom,
        );
      }
    });
  }

  void _moveMapSafely(LatLng center, double zoom) {
    try {
      _mapController.move(center, zoom);
    } catch (_) {
      // Map is not ready yet.
    }
  }

  void _showCannotChangeDestinationSnackBar() {
    final languageViewModel = context.read<LanguageViewModel>();
    final isTagalog = languageViewModel.isTagalog;
    AppFeedback.show(
      context,
      message: isTagalog
          ? 'Hindi maaaring baguhin ang destinasyon habang may aktibong biyahe. Tapusin muna ang biyahe.'
          : 'Cannot change destination while trip is active. End trip first.',
      backgroundColor: const Color(0xFF3B82F6),
    );
  }

  Future<void> _handleDestinationSelection(Terminal? terminal) async {
    final tripViewModel = context.read<TripViewModel>();

    if (tripViewModel.isTripActive) {
      _showCannotChangeDestinationSnackBar();
      return;
    }

    if (terminal == null) {
      tripViewModel.clearDestination();
      _clearRoute();

      setState(() {
        _commuterLocations = [];
      });

      _stopWatchingCommuterLocations();

      if (mounted) {
        final languageViewModel = context.read<LanguageViewModel>();
        final isTagalog = languageViewModel.isTagalog;
        AppFeedback.show(
          context,
          message: isTagalog ? 'Nabura ang destinasyon' : 'Destination cleared',
          backgroundColor: Colors.grey,
        );
      }

      return;
    }

    final success = tripViewModel.setDestination(terminal);

    if (!success) {
      if (mounted) {
        AppFeedback.show(
          context,
          message: 'Failed to set destination',
          backgroundColor: Colors.red,
        );
      }

      return;
    }

    _clearRoute(clearFirestore: false);
    _startWatchingCommuterLocations();

    if (mounted) {
      AppFeedback.show(
        context,
        message: 'Destination set to ${_terminalFullName(terminal)}',
        backgroundColor: AppTheme.primaryBlue,
      );
    }

    await _fetchRoute(terminal);
  }

  Future<void> _fetchRoute(
    Terminal terminal, {
    bool showSnackBar = true,
  }) async {
    final generation = ++_routeFetchGeneration;

    setState(() {
      _isLoadingRoute = true;
    });

    try {
      if (!_hasRealLocationFix) {
        await _getCurrentLocation();
      }

      if (!_hasRealLocationFix) {
        throw Exception('Current GPS location is not available yet.');
      }

      final target = terminal == Terminal.terminalA
          ? const LatLng(14.1149875, 121.551859375)
          : const LatLng(14.2659625, 121.425578125);

      final routeResult = await RoutingService.getRoute(
        _currentLocation,
        target,
      );

      if (!mounted || _routeFetchGeneration != generation) {
        if (mounted) {
          setState(() {
            _isLoadingRoute = false;
          });
        }
        return;
      }

      if (routeResult == null || routeResult.points.length < 2) {
        throw Exception('No route result returned');
      }

      setState(() {
        _routePoints = routeResult.points;
        _routeSnapper = RouteSnapper(
          routePoints: routeResult.points,
          searchRadius: 45.0,
        );
        _isLoadingRoute = false;
      });

      _fitRouteToMap();

      final savedPath = await RoutingService.saveRouteToFile(
        routeResult.points,
        'route.geojson',
      );

      if (savedPath != null) {
        debugPrint('Route saved to: $savedPath');
      }

      if (mounted && showSnackBar) {
        final languageViewModel = context.read<LanguageViewModel>();
        final isTagalog = languageViewModel.isTagalog;
        AppFeedback.show(
          context,
          message: isTagalog
              ? 'Na-load ang ruta: ${routeResult.distanceText}, ${routeResult.durationText}'
              : 'Route loaded: ${routeResult.distanceText}, ${routeResult.durationText}',
          backgroundColor: Colors.green,
        );
      }
    } catch (e) {
      debugPrint('Route error: $e');

      if (!mounted) return;

      setState(() {
        _routePoints = [];
        _routeSnapper = null;
        _isLoadingRoute = false;
      });

      if (showSnackBar) {
        final languageViewModel = context.read<LanguageViewModel>();
        final isTagalog = languageViewModel.isTagalog;
        AppFeedback.show(
          context,
          message: isTagalog ? 'Error sa ruta: $e' : 'Route error: $e',
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        );
      }

      if (!showSnackBar) rethrow;
    }
  }

  EdgeInsets _cameraPaddingForVisibleMap({
    required double topPadding,
    required double bottomPanelHeight,
  }) {
    return EdgeInsets.fromLTRB(
      34,
      topPadding + _routeCardEstimatedHeight + 26,
      112,
      bottomPanelHeight + 26,
    );
  }

  Offset _cameraOffsetForFocusBox({
    required double screenWidth,
    required double screenHeight,
    required double topPadding,
    required double bottomPanelHeight,
  }) {
    final boxLeft = math.max(20.0, screenWidth * 0.04);
    final boxRight = screenWidth - math.max(174.0, screenWidth * 0.20);
    final boxTop = topPadding + _routeCardEstimatedHeight + 36.0;
    final boxBottom = screenHeight - bottomPanelHeight - 28.0;
    final boxCenter = Offset(
      (boxLeft + boxRight) / 2,
      (boxTop + boxBottom) / 2,
    );
    final screenCenter = Offset(screenWidth / 2, screenHeight / 2);

    return boxCenter - screenCenter;
  }

  void _fitRouteToMap({EdgeInsets? cameraPadding, Offset? cameraOffset}) {
    if (_routePoints.length < 2) return;

    final bounds = LatLngBounds.fromPoints(_routePoints);

    try {
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: cameraPadding ??
              _latestMapCameraPadding ??
              const EdgeInsets.fromLTRB(34, 220, 112, 138),
        ),
      );
      _mapController.move(
        bounds.center,
        _mapController.camera.zoom,
        offset: cameraOffset ?? _latestMapCameraOffset ?? Offset.zero,
      );
    } catch (e) {
      debugPrint('Fit route error: $e');
    }
  }

  void _focusTerminalPoints({EdgeInsets? cameraPadding}) {
    final bounds = LatLngBounds.fromPoints(
      [DriverMapWidget.terminalA, DriverMapWidget.terminalB],
    );

    try {
      _mapController.rotate(0);
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: cameraPadding ??
              _latestMapCameraPadding ??
              const EdgeInsets.fromLTRB(34, 220, 112, 138),
        ),
      );
      _mapController.move(
        bounds.center,
        _mapController.camera.zoom,
        offset: Offset.zero,
      );
      setState(() => _mapRotation = 0);
      _isTerminalFocusActive = true;
    } catch (e) {
      debugPrint('Focus terminals error: $e');
    }
  }

  void _clearRoute({bool clearFirestore = true}) {
    setState(() {
      _routePoints = [];
      _routeSnapper = null;
    });

    if (clearFirestore && _currentJeepneyId != null) {
      unawaited(RouteService.clearRouteFromFirestore(_currentJeepneyId!));
    }
  }

  Future<void> _initializeJeepney() async {
    final tripViewModel = context.read<TripViewModel>();

    final possibleDriverId =
        tripViewModel.currentJeepneyId ?? FirestoreService.getCurrentDriverId();

    if (possibleDriverId == null || possibleDriverId.trim().isEmpty) {
      if (mounted) {
        final languageViewModel = context.read<LanguageViewModel>();
        final isTagalog = languageViewModel.isTagalog;
        AppFeedback.show(
          context,
          message: isTagalog
              ? 'Walang nakalog-in na driver. Mangyaring mag-login ulit o makipag-ugnayan sa support.'
              : 'No signed-in driver found. Please login again or contact support.',
          backgroundColor: Colors.red,
        );
      }

      return;
    }

    try {
      final jeepneyResult =
          await FirestoreService.getJeepneyByDriverResult(possibleDriverId);

      final jeepney = jeepneyResult.data;

      if (!jeepneyResult.success) {
        if (mounted) {
          AppFeedback.show(
            context,
            message: jeepneyResult.message,
            backgroundColor: Colors.red,
          );
        }

        return;
      }

      if (jeepney != null && mounted) {
        setState(() {
          _currentJeepneyId = jeepney.id;
        });

        tripViewModel.setCurrentJeepneyId(jeepney.id);

        await _loadTripSchedule(jeepney.id);
        _startWatchingTripSchedules(jeepney.id);
        _startWatchingDropOffAlerts(jeepney.id);

        debugPrint('Jeepney initialized: $_currentJeepneyId');
      } else if (mounted) {
        AppFeedback.show(
          context,
          message: jeepneyResult.message,
          backgroundColor: Colors.red,
        );
      }
    } catch (e) {
      if (!mounted) return;

      final languageViewModel = context.read<LanguageViewModel>();
      final isTagalog = languageViewModel.isTagalog;
      AppFeedback.show(
        context,
        message: isTagalog
            ? 'Error sa pagkuha ng jeepney: $e'
            : 'Error getting jeepney: $e',
        backgroundColor: Colors.red,
      );
    }
  }

  void _startWatchingTripSchedules(String jeepneyId) {
    _tripScheduleSubscription?.cancel();
    final cleanJeepneyId = jeepneyId.trim();
    if (cleanJeepneyId.isEmpty) return;

    _tripScheduleSubscription = FirebaseFirestore.instance
        .collection('trip_schedules')
        .where('scheduleDate', isEqualTo: FirestoreService.getTodayDateKey())
        .where('jeepneyId', isEqualTo: cleanJeepneyId)
        .snapshots()
        .listen((snapshot) {
      final schedules =
          snapshot.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList()
            ..sort((a, b) {
              final aTime = _tripScheduledDateTime(a);
              final bTime = _tripScheduledDateTime(b);
              if (aTime != null && bTime != null) return aTime.compareTo(bTime);
              if (aTime != null) return -1;
              if (bTime != null) return 1;
              return 0;
            });
      _applyTripSchedules(schedules, showLoading: false);
    }, onError: (error) {
      debugPrint('[TripScreen] Error watching trip schedules: $error');
    });
  }

  Future<void> _loadTripSchedule(
    String jeepneyId, {
    bool showLoading = true,
  }) async {
    if (showLoading && mounted) {
      setState(() => _isLoadingPassengers = true);
    }
    final schedules = await FirestoreService.getTodayTripSchedules(jeepneyId);
    _applyTripSchedules(schedules, showLoading: showLoading);
  }

  void _applyTripSchedules(
    List<Map<String, dynamic>> schedules, {
    required bool showLoading,
  }) {
    final schedule = _selectCurrentSchedule(schedules);
    if (!mounted) return;

    setState(() {
      _todayTripSchedules = schedules;
      _currentTripSchedule = schedule;
      if (showLoading) _isLoadingPassengers = false;
    });

    final tripViewModel = context.read<TripViewModel>();
    final scheduleRoute = schedule == null ? '' : _tripRouteLabel(schedule);
    if (scheduleRoute.isNotEmpty && scheduleRoute != 'Route not set') {
      tripViewModel.setRoute(scheduleRoute);
    }
    if (!tripViewModel.isTripActive && schedule != null) {
      tripViewModel.setDestination(_terminalFromScheduleOrRoute(schedule));
    }
    if (tripViewModel.isTripActive) {
      if (!_isTripTrackingStarted) {
        unawaited(_resumeTripTracking(tripViewModel));
      }
      if (_todayTripSchedules.isNotEmpty &&
          _todayTripSchedules.every(_isTripScheduleCompleted)) {
        unawaited(_autoEndTrip());
      } else {
        unawaited(_syncTripStateToLocationDoc(
          isOnTrip: true,
          crowdStatus: _crowdStatusValue(tripViewModel.crowdLevel),
        ));
      }
    } else {
      _scheduleAutomaticTripStart(schedule);
    }

    // Ensure dispatcher-booked commuters have a commuter_waiting_location doc
    if (schedule != null && _currentJeepneyId != null) {
      _ensureDispatcherCommuterDocs(schedule);
    }
  }

  void _ensureDispatcherCommuterDocs(Map<String, dynamic> schedule) {
    final jeepneyId = _currentJeepneyId;
    if (jeepneyId == null) return;
    final passengers = schedule['bookedPassengers'];
    if (passengers is! List) return;
    final onboardPosition = _lastFirestorePosition ??
        (_hasRealLocationFix && _isValidLatLng(_currentLocation)
            ? _currentLocation
            : null);
    if (onboardPosition == null) {
      debugPrint(
        'Skipped dispatcher onboard commuter docs - no trusted jeep location yet.',
      );
      return;
    }
    final jeepneyLat = onboardPosition.latitude;
    final jeepneyLng = onboardPosition.longitude;
    for (final p in passengers) {
      if (p is! Map) continue;
      final commuterId = p['commuterId']?.toString() ?? '';
      if (commuterId.isEmpty) continue;
      final source = (p['source']?.toString() ?? '').toLowerCase();
      final onBoardSource =
          (p['onBoardSource']?.toString() ?? '').toLowerCase();
      final bookedBy = (p['bookedBy']?.toString() ?? '').toLowerCase();
      final isRoadPickup =
          source == 'road_pickup' || onBoardSource == 'road_pickup';
      final isDispatcher = _isDispatcherBookingSource(
            source: source,
            onBoardSource: onBoardSource,
            bookedBy: bookedBy,
          ) ||
          (p['onBoard'] == true && !isRoadPickup);
      if (!isDispatcher) continue;
      if (!_autoOnboardedCommuters.add(commuterId)) continue;
      final waitingCount =
          _intFromSchedule(p['waitingCount'] ?? p['passengerCount'] ?? 1) ?? 1;
      unawaited(FirestoreService.dispatcherCommuterOnboard(
        commuterId: commuterId,
        jeepneyId: jeepneyId,
        lat: jeepneyLat,
        lng: jeepneyLng,
        tripScheduleId: schedule['id']?.toString(),
        destinationTerminal: schedule['destinationTerminal']?.toString(),
        waitingCount: waitingCount,
      ));
    }
  }

  Map<String, dynamic>? _selectCurrentSchedule(
    List<Map<String, dynamic>> schedules,
  ) {
    final selectableSchedules = schedules
        .where((schedule) => !_isTripScheduleCompleted(schedule))
        .toList();
    if (selectableSchedules.isEmpty) return null;

    final activeSchedules =
        selectableSchedules.where(_isTripScheduleActive).toList();
    if (activeSchedules.isNotEmpty) return activeSchedules.first;

    final now = DateTime.now();
    selectableSchedules.sort((a, b) {
      final aTime = _tripScheduledDateTime(a);
      final bTime = _tripScheduledDateTime(b);
      if (aTime != null && bTime != null) {
        final aDiff = aTime.difference(now).abs();
        final bDiff = bTime.difference(now).abs();
        final diffCompare = aDiff.compareTo(bDiff);
        if (diffCompare != 0) return diffCompare;
        return aTime.compareTo(bTime);
      }
      if (aTime != null) return -1;
      if (bTime != null) return 1;
      return 0;
    });

    return selectableSchedules.first;
  }

  void _scheduleAutomaticTripStart(Map<String, dynamic>? schedule) {
    _autoStartTripTimer?.cancel();
    _autoStartTripTimer = null;

    if (schedule == null || _isTripScheduleCompleted(schedule)) return;

    final scheduledAt = _tripScheduledDateTime(schedule);
    if (scheduledAt == null) return;

    final now = DateTime.now();
    final delay =
        scheduledAt.isAfter(now) ? scheduledAt.difference(now) : Duration.zero;

    _autoStartTripTimer = Timer(delay, _tryAutoStartScheduledTrip);
  }

  bool _isScheduleReadyToStart(Map<String, dynamic>? schedule) {
    if (schedule == null) return true;

    final scheduledAt = _tripScheduledDateTime(schedule);
    if (scheduledAt == null) return true;

    return !DateTime.now().isBefore(scheduledAt);
  }

  String _scheduleStartBlockedMessage(
    Map<String, dynamic> schedule,
    bool isTagalog,
  ) {
    final scheduledAt = _tripScheduledDateTime(schedule);
    final timeText = scheduledAt == null
        ? _tripScheduleLabel(schedule)
        : (() {
            final hour =
                scheduledAt.hour % 12 == 0 ? 12 : scheduledAt.hour % 12;
            final minute = scheduledAt.minute.toString().padLeft(2, '0');
            final period = scheduledAt.hour >= 12 ? 'PM' : 'AM';
            return '$hour:$minute $period';
          })();

    return isTagalog
        ? 'Hindi pa oras ng nakatalagang biyahe. Magsisimula ito ng $timeText.'
        : 'This assigned trip is not ready yet. It starts at $timeText.';
  }

  Future<void> _tryAutoStartScheduledTrip() async {
    if (!mounted || _isAutoStartingTrip) return;

    final schedule = _currentTripSchedule;
    if (schedule == null || _isTripScheduleCompleted(schedule)) return;

    final scheduledAt = _tripScheduledDateTime(schedule);
    if (scheduledAt == null || DateTime.now().isBefore(scheduledAt)) {
      _scheduleAutomaticTripStart(schedule);
      return;
    }

    final tripViewModel = context.read<TripViewModel>();
    if (tripViewModel.isTripActive) return;

    final terminal = _terminalFromScheduleOrRoute(schedule);

    _isAutoStartingTrip = true;
    try {
      tripViewModel.setDestination(terminal);
      final crowdStatus = _setAutomaticCrowdStatus(tripViewModel);

      if (_routePoints.length < 2) {
        await _fetchRoute(terminal, showSnackBar: false);
      }

      await _performStartTrip(tripViewModel, crowdStatus);

      if (!mounted) return;
      final languageViewModel = context.read<LanguageViewModel>();
      _showTripActionSnackBar(
        languageViewModel.isTagalog
            ? 'Awtomatikong nagsimula ang nakatakdang biyahe.'
            : 'Scheduled trip started automatically.',
        Colors.green,
      );
    } catch (e) {
      debugPrint('[TripScreen] Auto start failed: $e');
      if (!mounted) return;
      if (_isNoInternetException(e)) return;

      final languageViewModel = context.read<LanguageViewModel>();
      _showTripActionSnackBar(
        languageViewModel.isTagalog
            ? 'Hindi awtomatikong nasimulan ang biyahe: $e'
            : 'Could not auto-start trip: $e',
        Colors.red,
      );
    } finally {
      _isAutoStartingTrip = false;
    }
  }

  Future<void> _markCurrentScheduleOnTrip() async {
    final scheduleId = _currentTripSchedule?['id']?.toString().trim() ?? '';
    if (scheduleId.isEmpty) return;

    await FirebaseFirestore.instance
        .collection('trip_schedules')
        .doc(scheduleId)
        .set({
      'status': 'active',
      'tripStatus': 'active',
      'historyStatus': FieldValue.delete(),
      'isOnTrip': true,
      'onTrip': true,
      'tripStartedAt': FieldValue.serverTimestamp(),
      'tripEndedAt': FieldValue.delete(),
      'endedAt': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (!mounted) return;
    setState(() {
      final updated = Map<String, dynamic>.from(_currentTripSchedule ?? {});
      updated['status'] = 'active';
      updated['tripStatus'] = 'active';
      updated.remove('historyStatus');
      updated['isOnTrip'] = true;
      updated['onTrip'] = true;
      _currentTripSchedule = updated;
    });
  }

  Future<bool> _markCurrentScheduleCompleted() async {
    final firestore = FirebaseFirestore.instance;
    final jeepneyId = _currentJeepneyId?.trim() ?? '';

    final currentScheduleId =
        _currentTripSchedule?['id']?.toString().trim() ?? '';
    if (currentScheduleId.isEmpty) {
      debugPrint('[TripScreen] No current schedule to mark completed');
      return true;
    }

    try {
      await firestore.runTransaction((transaction) async {
        final scheduleRef =
            firestore.collection('trip_schedules').doc(currentScheduleId);
        final locationRef = jeepneyId.isNotEmpty
            ? firestore.collection('locations').doc(jeepneyId)
            : null;
        final scheduleDoc = await transaction.get(scheduleRef);
        final locationDoc =
            locationRef != null ? await transaction.get(locationRef) : null;
        if (!scheduleDoc.exists) {
          throw StateError('Trip schedule not found');
        }
        final scheduleData = scheduleDoc.data() ?? {};
        final currentStatus =
            (scheduleData['status'] as String?)?.toLowerCase() ?? '';
        if (currentStatus == 'completed' ||
            currentStatus == 'done' ||
            currentStatus == 'finished') {
          return;
        }

        transaction.set(
            scheduleRef,
            {
              'status': 'completed',
              'tripStatus': 'completed',
              'historyStatus': 'done',
              'isOnTrip': false,
              'onTrip': false,
              'tripEndedAt': FieldValue.serverTimestamp(),
              'endedAt': FieldValue.serverTimestamp(),
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true));

        if (locationRef != null && locationDoc != null && locationDoc.exists) {
          transaction.set(
              locationRef,
              {
                'status': 'completed',
                'tripStatus': 'completed',
                'isOnTrip': false,
                'onTrip': false,
                'tripEndedAt': FieldValue.serverTimestamp(),
                'endedAt': FieldValue.serverTimestamp(),
                'updatedAt': FieldValue.serverTimestamp(),
                'timestamp': FieldValue.serverTimestamp(),
                'crowdStatus': FieldValue.delete(),
              },
              SetOptions(merge: true));
        }
      });

      _autoStartTripTimer?.cancel();
      _autoStartTripTimer = null;

      if (!mounted) return true;
      setState(() {
        final updated = Map<String, dynamic>.from(_currentTripSchedule ?? {});
        updated['status'] = 'completed';
        updated['tripStatus'] = 'completed';
        updated['historyStatus'] = 'done';
        updated['isOnTrip'] = false;
        updated['onTrip'] = false;
        _currentTripSchedule = updated;
      });

      final reloadJeepneyId = _currentJeepneyId;
      if (reloadJeepneyId != null && reloadJeepneyId.trim().isNotEmpty) {
        unawaited(_loadTripSchedule(reloadJeepneyId));
      }
      return true;
    } catch (e) {
      debugPrint('[TripScreen] Error marking schedule completed: $e');
      if (mounted) {
        final languageViewModel = context.read<LanguageViewModel>();
        final isTagalog = languageViewModel.isTagalog;
        _showTripActionSnackBar(
          isTagalog
              ? 'Nabigong tapusin ang biyahe. Walang nagbago sa data.'
              : 'Failed to complete trip. No data was changed.',
          Colors.red,
        );
      }
      return false;
    }
  }

  void _showPassengerList() {
    if (_isCurrentScheduleDoneForControls()) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (_) => PassengerListSheet(
          tripSchedule: _currentTripSchedule ?? <String, dynamic>{},
        ),
      );
      return;
    }
    final passengerSchedule = _scheduleForPassengerDisplay();
    if (passengerSchedule == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No booked onboard passengers found for today'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => PassengerListSheet(tripSchedule: passengerSchedule),
    );
  }

  Map<String, dynamic>? _scheduleForPassengerDisplay() {
    if (_currentTripSchedule != null &&
        _bookedPassengerCount(_currentTripSchedule!) > 0) {
      return _currentTripSchedule;
    }

    for (final schedule in _todayTripSchedules) {
      if (_bookedPassengerCount(schedule) > 0) {
        return schedule;
      }
    }

    return _currentTripSchedule;
  }

  void _showTripScheduleList() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        final schedules = _todayTripSchedules;
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.72,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.event_note_rounded,
                        color: AppTheme.primaryBlue,
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Today\'s Trip Schedule',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: schedules.isEmpty
                      ? const Center(
                          child: Text('No schedule found for this jeepney.'),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: schedules.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final schedule = schedules[index];
                            final isCancelled =
                                _isTripScheduleCancelled(schedule);
                            final isSelected =
                                _firstNonEmpty([schedule['id']]) ==
                                    _firstNonEmpty([
                                      _currentTripSchedule?['id'],
                                    ]);
                            final isDone = _isTripScheduleCompleted(schedule);
                            final isActive = _isTripScheduleActive(schedule) ||
                                _isScheduleTimePassed(schedule);
                            final isWithinBookingWindow =
                                _isWithinBookingWindow(schedule);
                            final isFull = _isScheduleFull(schedule);
                            final canBook =
                                _isNearestBookableSchedule(schedule, schedules);
                            final canCancel = !isDone;
                            final statusColor = isCancelled
                                ? Colors.red
                                : isDone
                                    ? Colors.grey
                                    : isActive
                                        ? const Color(0xFF10B981)
                                        : AppTheme.primaryBlue;

                            return InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: isDone
                                  ? null
                                  : () {
                                      setState(() {
                                        _currentTripSchedule = schedule;
                                      });
                                      _scheduleAutomaticTripStart(schedule);
                                    },
                              child: Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? AppTheme.primaryBlue.withValues(
                                          alpha: 0.08,
                                        )
                                      : Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isSelected
                                        ? AppTheme.primaryBlue
                                        : Colors.grey.shade200,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 42,
                                      height: 42,
                                      decoration: BoxDecoration(
                                        color: statusColor.withValues(
                                          alpha: 0.12,
                                        ),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        isDone
                                            ? Icons.check_rounded
                                            : Icons.schedule_rounded,
                                        color: statusColor,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            _tripScheduleLabel(schedule),
                                            style: const TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            _tripRouteLabel(schedule),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: AppTheme.darkBlue,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            _tripPassengerLabel(schedule),
                                            style: TextStyle(
                                              color: AppTheme.darkBlue,
                                              fontWeight: FontWeight.w800,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Flexible(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 6,
                                            ),
                                            decoration: BoxDecoration(
                                              color: statusColor.withValues(
                                                alpha: 0.12,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(999),
                                            ),
                                            child: Text(
                                              _tripStatusLabel(schedule),
                                              style: TextStyle(
                                                color: statusColor,
                                                fontSize: 12,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Wrap(
                                            spacing: 8,
                                            runSpacing: 8,
                                            alignment: WrapAlignment.end,
                                            children: [
                                              FilledButton.icon(
                                                onPressed: canBook
                                                    ? () =>
                                                        _showScheduleBookingDialog(
                                                          schedule,
                                                        )
                                                    : null,
                                                icon: const Icon(
                                                  Icons.person_add_alt_1,
                                                  size: 16,
                                                ),
                                                label: Text(
                                                  isActive
                                                      ? 'On Trip'
                                                      : canBook
                                                          ? 'Book'
                                                          : isFull
                                                              ? 'Full'
                                                              : !isWithinBookingWindow
                                                                  ? 'Too Early'
                                                                  : 'Upcoming',
                                                ),
                                                style: FilledButton.styleFrom(
                                                  backgroundColor: canBook
                                                      ? AppTheme.primaryBlue
                                                      : Colors.grey.shade300,
                                                  disabledBackgroundColor:
                                                      Colors.grey.shade300,
                                                  foregroundColor: Colors.white,
                                                  disabledForegroundColor:
                                                      Colors.grey.shade700,
                                                  visualDensity:
                                                      VisualDensity.compact,
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                    horizontal: 12,
                                                    vertical: 8,
                                                  ),
                                                ),
                                              ),
                                              OutlinedButton.icon(
                                                onPressed: canCancel
                                                    ? () =>
                                                        _cancelAssignedSchedule(
                                                          schedule,
                                                        )
                                                    : null,
                                                icon: const Icon(
                                                  Icons.cancel_outlined,
                                                  size: 16,
                                                ),
                                                label: const Text('Cancel'),
                                                style: OutlinedButton.styleFrom(
                                                  foregroundColor: Colors.red,
                                                  side: BorderSide(
                                                    color: canCancel
                                                        ? Colors.red
                                                        : Colors.grey.shade300,
                                                  ),
                                                  visualDensity:
                                                      VisualDensity.compact,
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                    horizontal: 12,
                                                    vertical: 8,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _cancelAssignedSchedule(Map<String, dynamic> schedule) async {
    var draftReason = '';
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final hasReason = draftReason.trim().isNotEmpty;
          return AlertDialog(
            title: const Text('Request Trip Cancellation'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Send a cancellation request for ${_tripScheduleLabel(schedule)} with ${_scheduleJeepneyLabel(schedule)}. The dispatcher must approve it before the trip is cancelled.',
                ),
                const SizedBox(height: 12),
                TextField(
                  maxLines: 3,
                  onChanged: (value) {
                    draftReason = value;
                    setDialogState(() {});
                  },
                  decoration: const InputDecoration(
                    labelText: 'Reason for cancellation',
                    helperText: 'Required for dispatcher review',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Back'),
              ),
              FilledButton.icon(
                onPressed: hasReason
                    ? () => Navigator.pop(
                          dialogContext,
                          draftReason.trim(),
                        )
                    : null,
                icon: const Icon(Icons.arrow_forward),
                label: const Text('Continue'),
              ),
            ],
          );
        },
      ),
    );

    if (reason == null || reason.trim().isEmpty || !mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Submit Cancellation Request?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This will send your cancellation request to the dispatcher for review. The trip is not cancelled until approved.',
            ),
            const SizedBox(height: 12),
            Text('Trip: ${_tripScheduleLabel(schedule)}'),
            Text('Jeepney: ${_scheduleJeepneyLabel(schedule)}'),
            const SizedBox(height: 8),
            Text('Reason: $reason'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Edit'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.send_outlined),
            label: const Text('Submit Request'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final result = await FirestoreService.requestAssignedTripCancellation(
      schedule: schedule,
      reason: reason,
    );

    if (!mounted) return;
    if (!result.success) {
      _showTripActionSnackBar(result.message, Colors.red);
      return;
    }

    _showTripActionSnackBar(result.message, Colors.orange);
    final reloadJeepneyId = _currentJeepneyId;
    if (reloadJeepneyId != null && reloadJeepneyId.trim().isNotEmpty) {
      await _loadTripSchedule(reloadJeepneyId);
    }
  }

  void _showScheduleBookingDialog(Map<String, dynamic> schedule) {
    final routes = <Map<String, dynamic>>[];
    var isLoadingRoutes = true;
    var selectedRoute = <String, dynamic>{};
    var paymentMethod = 'cash';
    var fareType = 'regular';
    var isSubmitting = false;

    showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          if (isLoadingRoutes) {
            isLoadingRoutes = false;
            _loadBookingRoutes(routes, setDialogState);
          }

          final hasRoute = selectedRoute.isNotEmpty;
          final regularFare = _fareForBookingType(selectedRoute, 'regular');
          final discountedFare =
              _fareForBookingType(selectedRoute, 'studentSenior');
          final fare = paymentMethod == 'rfid'
              ? regularFare
              : _fareForBookingType(selectedRoute, fareType);
          final terminalRoutes = routes
              .where((route) => _routeStartsFromScheduleTerminal(
                    schedule,
                    route,
                  ))
              .toList();
          terminalRoutes.sort((a, b) {
            final aFare = _fareForBookingType(a, 'regular');
            final bFare = _fareForBookingType(b, 'regular');
            if (aFare > 0 && bFare > 0) return aFare.compareTo(bFare);
            if (aFare > 0) return -1;
            if (bFare > 0) return 1;
            return _bookingRouteLabel(a).compareTo(_bookingRouteLabel(b));
          });
          if (hasRoute &&
              !_routeStartsFromScheduleTerminal(schedule, selectedRoute)) {
            selectedRoute = <String, dynamic>{};
          }
          final rfidAllowed =
              hasRoute && _canUseRfidForRoute(schedule, selectedRoute);
          if (!rfidAllowed && paymentMethod == 'rfid') {
            paymentMethod = 'cash';
          }
          final isFull = _isScheduleFull(schedule);

          Future<void> submitBooking({String rfidTag = ''}) async {
            if (!hasRoute || isSubmitting || isFull) return;
            if (paymentMethod == 'rfid' && rfidTag.trim().isEmpty) {
              return;
            }

            final jeepneyVM = context.read<JeepneyViewModel>();
            try {
              setDialogState(() => isSubmitting = true);
              debugPrint(
                '[TripScreen] Driver booking submit: '
                'method=$paymentMethod, rfidChars=${rfidTag.trim().length}',
              );
              final result =
                  await FirestoreService.bookCommuterOnAssignedSchedule(
                trip: schedule,
                passengerName: 'Cash passenger',
                rfidTag: rfidTag,
                fare: fare,
                regularFare: regularFare,
                discountedFare: discountedFare,
                fareType: fareType,
                paymentMethod: paymentMethod,
                driverId: jeepneyVM.driverId,
                driverName: jeepneyVM.driverName,
              );

              if (!dialogContext.mounted) return;
              debugPrint(
                '[TripScreen] Driver booking result: '
                'success=${result.success}, '
                'message=${result.message}',
              );
              if (result.success) {
                Navigator.pop(dialogContext);
                _showTripActionSnackBar(result.message, Colors.green);
              } else {
                setDialogState(() => isSubmitting = false);
                _showTripActionSnackBar(result.message, Colors.red);
              }
            } catch (error) {
              if (!dialogContext.mounted) return;
              setDialogState(() => isSubmitting = false);
              _showTripActionSnackBar(
                'Booking was not saved. Please try again.',
                Colors.red,
              );
            }
          }

          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.confirmation_number, color: AppTheme.primaryBlue),
                SizedBox(width: 10),
                Expanded(child: Text('Book Passenger')),
              ],
            ),
            content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isFull) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.orange.withValues(alpha: 0.28),
                          ),
                        ),
                        child: const Row(
                          children: [
                            Icon(
                              Icons.event_seat_rounded,
                              color: Colors.orange,
                              size: 20,
                            ),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Jeep is full. Start the trip or use the next schedule.',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.lightBlue.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: AppTheme.primaryBlue.withValues(alpha: 0.15),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _tripScheduleLabel(schedule),
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _tripRouteLabel(schedule),
                            style: TextStyle(
                              color: Colors.grey[700],
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<Map<String, dynamic>>(
                      initialValue: hasRoute ? selectedRoute : null,
                      isExpanded: true,
                      itemHeight: null,
                      menuMaxHeight: MediaQuery.of(context).size.height * 0.42,
                      decoration: const InputDecoration(
                        labelText: 'Passenger route',
                        border: OutlineInputBorder(),
                      ),
                      selectedItemBuilder: (context) {
                        return terminalRoutes.map((route) {
                          final label = _bookingRouteLabel(route);
                          final routeFare =
                              _fareForBookingType(route, 'regular');
                          return _BookingRouteDropdownItem(
                            label: label,
                            fare: routeFare,
                            isSelectedField: true,
                          );
                        }).toList();
                      },
                      items: terminalRoutes.map((route) {
                        final label = _bookingRouteLabel(route);
                        final routeFare = _fareForBookingType(route, 'regular');
                        return DropdownMenuItem<Map<String, dynamic>>(
                          value: route,
                          child: _BookingRouteDropdownItem(
                            label: label,
                            fare: routeFare,
                          ),
                        );
                      }).toList(),
                      onChanged: isSubmitting || isFull
                          ? null
                          : (route) {
                              if (route == null) return;
                              setDialogState(() {
                                selectedRoute = route;
                                if (!_canUseRfidForRoute(schedule, route)) {
                                  paymentMethod = 'cash';
                                }
                              });
                            },
                    ),
                    if (isLoadingRoutes)
                      const Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: LinearProgressIndicator(),
                      ),
                    if (!isLoadingRoutes && terminalRoutes.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          'No passenger routes found from ${_scheduleOriginTerminalLabel(schedule)}.',
                          style: TextStyle(
                            color: Colors.red[700],
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    if (hasRoute) ...[
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: _BookingChoiceTile(
                              title: 'Cash',
                              subtitle: 'No commuter account needed',
                              icon: Icons.payments_outlined,
                              selected: paymentMethod == 'cash',
                              onTap: isSubmitting || isFull
                                  ? null
                                  : () => setDialogState(
                                        () => paymentMethod = 'cash',
                                      ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _BookingChoiceTile(
                              title: 'RFID',
                              subtitle: rfidAllowed
                                  ? 'Terminal only'
                                  : 'Unavailable on this trip',
                              icon: Icons.credit_card,
                              selected: paymentMethod == 'rfid',
                              enabled: rfidAllowed,
                              onTap: isSubmitting || !rfidAllowed || isFull
                                  ? null
                                  : () => setDialogState(
                                        () {
                                          paymentMethod = 'rfid';
                                        },
                                      ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      if (paymentMethod == 'cash')
                        Row(
                          children: [
                            Expanded(
                              child: _BookingChoiceTile(
                                title: 'Regular',
                                subtitle:
                                    'PHP ${regularFare.toStringAsFixed(2)}',
                                icon: Icons.person,
                                selected: fareType == 'regular',
                                onTap: isSubmitting || isFull
                                    ? null
                                    : () => setDialogState(
                                          () => fareType = 'regular',
                                        ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _BookingChoiceTile(
                                title: 'Student / PWD',
                                subtitle:
                                    'PHP ${discountedFare.toStringAsFixed(2)}',
                                icon: Icons.badge_outlined,
                                selected: fareType == 'studentSenior',
                                onTap: isSubmitting || isFull
                                    ? null
                                    : () => setDialogState(
                                          () => fareType = 'studentSenior',
                                        ),
                              ),
                            ),
                          ],
                        )
                      else
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.blue.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.blue.withValues(alpha: 0.2),
                            ),
                          ),
                          child: const Row(
                            children: [
                              Icon(
                                Icons.auto_awesome_outlined,
                                color: Colors.blue,
                                size: 20,
                              ),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'RFID fare is automatic. Approved Student/PWD discounts are applied from the commuter profile; otherwise regular fare is used.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed:
                    isSubmitting ? null : () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                onPressed: !hasRoute || isSubmitting || isFull
                    ? null
                    : () async {
                        var rfidTag = '';
                        if (paymentMethod == 'rfid') {
                          final scanned = await _showBookingRfidScanDialog(
                            dialogContext,
                            fare: fare,
                          );
                          if (scanned == null) return;
                          rfidTag = scanned;
                        }
                        await submitBooking(rfidTag: rfidTag);
                      },
                icon: isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_circle),
                label: Text(
                  isFull
                      ? 'Jeep is full'
                      : !hasRoute
                          ? 'Select route'
                          : paymentMethod == 'rfid'
                              ? 'Scan RFID - Auto Fare'
                              : 'Confirm Cash - PHP ${fare.toStringAsFixed(2)}',
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _loadBookingRoutes(
    List<Map<String, dynamic>> routes,
    StateSetter setDialogState,
  ) async {
    if (routes.isNotEmpty) return;
    try {
      final snapshot =
          await FirebaseFirestore.instance.collection('routes').get();
      routes.addAll(
        snapshot.docs.map((doc) => {'id': doc.id, ...doc.data()}),
      );
      setDialogState(() {});
    } catch (error) {
      debugPrint('[TripScreen] Failed to load booking routes: $error');
      setDialogState(() {});
    }
  }

  Future<void> _stopNfcScanSafely() async {
    try {
      await _deviceSettingsChannel.invokeMethod<void>('stopNfcScan');
    } on MissingPluginException {
      debugPrint(
        '[TripScreen] stopNfcScan is not registered. '
        'Install a rebuilt APK with the native NFC methods.',
      );
    } catch (error) {
      debugPrint('[TripScreen] Failed to stop NFC scan: $error');
    }
  }

  Future<String?> _showBookingRfidScanDialog(
    BuildContext context, {
    required double fare,
  }) {
    String? errorText;
    var isScanning = false;
    var didStartScan = false;
    var submitted = false;

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          Future<void> startNfcScan() async {
            if (submitted || isScanning) return;
            setDialogState(() {
              isScanning = true;
              errorText = null;
            });

            _deviceSettingsChannel
                .setMethodCallHandler((MethodCall call) async {
              if (submitted ||
                  call.method != 'onNfcTagDiscovered' ||
                  !ctx.mounted) {
                return;
              }

              final data = Map<String, dynamic>.from(call.arguments as Map);
              final ndefValues = data['ndefValues'] is List
                  ? (data['ndefValues'] as List)
                  : const [];
              final scanned = [
                data['idHex'],
                data['idHexReversed'],
                data['idDecimal'],
                data['idDecimalReversed'],
                ...ndefValues,
              ]
                  .map(
                      (value) => _normalizeScannedRfid(value?.toString() ?? ''))
                  .where((value) => value.isNotEmpty)
                  .toSet()
                  .join('|');

              if (scanned.isEmpty) {
                setDialogState(() {
                  isScanning = false;
                  errorText = 'NFC card detected, but no card ID was read.';
                });
                return;
              }

              submitted = true;
              debugPrint(
                '[TripScreen] NFC RFID booking scan captured: '
                '${scanned.length} chars',
              );
              HapticFeedback.selectionClick();
              await _stopNfcScanSafely();
              if (ctx.mounted) {
                Navigator.pop(ctx, scanned);
              }
            });

            try {
              await _deviceSettingsChannel.invokeMethod<bool>('startNfcScan');
              debugPrint('[TripScreen] NFC scan modal session started.');
            } on MissingPluginException {
              setDialogState(() {
                isScanning = false;
                didStartScan = false;
                errorText =
                    'NFC scanner is not installed in this app build. Rebuild and reinstall the driver app.';
              });
            } on PlatformException catch (error) {
              setDialogState(() {
                isScanning = false;
                didStartScan = false;
                if (error.code == 'nfc_disabled') {
                  errorText = 'NFC is turned off. Enable NFC and try again.';
                } else if (error.code == 'nfc_not_supported') {
                  errorText = 'This phone does not support NFC scanning.';
                } else {
                  errorText = error.message ?? 'NFC scan failed to start.';
                }
              });
              if (error.code == 'nfc_disabled') {
                await _deviceSettingsChannel.invokeMethod<void>(
                  'openNfcSettings',
                );
              }
            } catch (error) {
              setDialogState(() {
                isScanning = false;
                didStartScan = false;
                errorText = 'NFC scan failed to start. Please try again.';
              });
            }
          }

          if (!didStartScan) {
            didStartScan = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (ctx.mounted) {
                unawaited(startNfcScan());
              }
            });
          }

          return AlertDialog(
            title: const Text('Tap RFID Card'),
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryBlue.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppTheme.primaryBlue.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.contactless_outlined,
                          size: 42,
                          color: AppTheme.primaryBlue,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          isScanning
                              ? 'Waiting for NFC tap'
                              : 'Ready to scan RFID',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Fare: PHP ${fare.toStringAsFixed(2)}',
                          style: TextStyle(
                            color: Colors.grey[700],
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isScanning) ...[
                    const SizedBox(height: 14),
                    const SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                  ],
                  if (errorText != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      errorText!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.red[700],
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    'Hold the RFID card near the phone NFC reader.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  await _stopNfcScanSafely();
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: const Text('Cancel'),
              ),
              TextButton.icon(
                onPressed: isScanning
                    ? null
                    : () {
                        didStartScan = true;
                        unawaited(startNfcScan());
                      },
                icon: const Icon(Icons.sensors),
                label: const Text('Scan Again'),
              ),
            ],
          );
        },
      ),
    ).whenComplete(() {
      unawaited(_stopNfcScanSafely());
      _deviceSettingsChannel.setMethodCallHandler(null);
    });
  }

  String _normalizeScannedRfid(String value) {
    return value.replaceAll(RegExp(r'[\r\n\t ]+'), '').trim();
  }

  bool _canUseRfidForRoute(
    Map<String, dynamic> schedule,
    Map<String, dynamic> route,
  ) {
    if (_isTripScheduleActive(schedule) || _isScheduleTimePassed(schedule)) {
      return false;
    }

    return _routeStartsFromScheduleTerminal(schedule, route);
  }

  bool _routeStartsFromScheduleTerminal(
    Map<String, dynamic> schedule,
    Map<String, dynamic> route,
  ) {
    final scheduleOrigin = _scheduleOriginTerminalLabel(schedule).toLowerCase();
    final routeOrigin = _bookingRouteFrom(route).toLowerCase();
    if (scheduleOrigin.isEmpty || routeOrigin.isEmpty) return false;

    final scheduleStaCruz =
        scheduleOrigin.contains('sta') && scheduleOrigin.contains('cruz');
    final routeStaCruz =
        routeOrigin.contains('sta') && routeOrigin.contains('cruz');
    final scheduleLucban = scheduleOrigin.contains('lucban');
    final routeLucban = routeOrigin.contains('lucban');

    return (scheduleStaCruz && routeStaCruz) || (scheduleLucban && routeLucban);
  }

  String _scheduleOriginTerminalLabel(Map<String, dynamic> schedule) {
    final routeLabel = _tripRouteLabel(schedule);
    final routeOrigin =
        routeLabel.contains(' to ') ? routeLabel.split(' to ').first : '';
    return _firstNonEmpty([
      schedule['originTerminal'],
      schedule['origin'],
      routeOrigin,
    ]);
  }

  String _bookingRouteLabel(Map<String, dynamic> route) {
    final from = _bookingRouteFrom(route);
    final to = _bookingRouteTo(route);
    if (from.isNotEmpty && to.isNotEmpty) return '$from to $to';
    return _firstNonEmpty(
        [route['routeName'], route['route'], 'Unknown route']);
  }

  String _bookingRouteFrom(Map<String, dynamic> route) {
    final entries = route['fareEntries'];
    if (entries is List && entries.isNotEmpty) {
      final first = entries.first;
      if (first is Map) {
        final from = first['from']?.toString().trim() ?? '';
        if (from.isNotEmpty) return from;
      }
    }
    return _firstNonEmpty([route['origin'], route['startTerminal']]);
  }

  String _bookingRouteTo(Map<String, dynamic> route) {
    final entries = route['fareEntries'];
    if (entries is List && entries.isNotEmpty) {
      final first = entries.first;
      if (first is Map) {
        final to = first['to']?.toString().trim() ?? '';
        if (to.isNotEmpty) return to;
      }
    }
    return _firstNonEmpty([route['destination'], route['endTerminal']]);
  }

  double _fareForBookingType(Map<String, dynamic> route, String type) {
    final entries = route['fareEntries'];
    if (entries is List && entries.isNotEmpty) {
      final first = entries.first;
      if (first is Map) {
        final fare = _doubleFromValue(first[type]);
        if (fare > 0) return fare;
      }
    }
    return _doubleFromValue(route['fare']);
  }

  double _doubleFromValue(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  String _tripScheduleLabel(Map<String, dynamic> schedule) {
    final label = _firstNonEmpty([
      schedule['scheduleTime'],
      schedule['departureTime'],
      schedule['tripTime'],
    ]);
    if (label.isNotEmpty) return label;

    final scheduledAt = _tripScheduledDateTime(schedule);
    if (scheduledAt == null) return 'No time set';

    final hour = scheduledAt.hour % 12 == 0 ? 12 : scheduledAt.hour % 12;
    final minute = scheduledAt.minute.toString().padLeft(2, '0');
    final period = scheduledAt.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }

  String _scheduleJeepneyLabel(Map<String, dynamic> schedule) {
    return _firstNonEmpty([
      schedule['plateNumber'],
      schedule['jeepneyId'],
      _currentJeepneyId,
      'Assigned jeepney',
    ]);
  }

  String _tripRouteLabel(Map<String, dynamic> schedule) {
    final origin = _firstNonEmpty([
      schedule['originTerminal'],
      schedule['origin'],
    ]);
    final destination = _firstNonEmpty([
      schedule['destinationTerminal'],
      schedule['destination'],
      schedule['to'],
    ]);
    if (origin.isNotEmpty && destination.isNotEmpty) {
      return '$origin to $destination';
    }
    return _firstNonEmpty([
      schedule['routeName'],
      schedule['route'],
      'Route not set',
    ]);
  }

  String _tripPassengerLabel(Map<String, dynamic> schedule) {
    if (_isTripScheduleCompleted(schedule)) return 'Trip completed';
    final total = _bookedPassengerCount(schedule);
    final onBoard = _onBoardPassengerCount(schedule);
    return 'On board: $onBoard / $total';
  }

  int _onBoardPassengerCount(Map<String, dynamic> schedule) {
    final passengers = schedule['bookedPassengers'];
    if (passengers is! List) {
      return _intFromSchedule(schedule['passengerCount']) ?? 0;
    }

    return passengers.fold<int>(0, (total, passenger) {
      if (passenger is! Map) return total;
      final data = Map<String, dynamic>.from(passenger);
      if (!_passengerIsOnBoard(data)) return total;
      return total + _passengerUnitCount(data);
    });
  }

  bool _passengerIsOnBoard(Map<String, dynamic> passenger) {
    final status = passenger['status']?.toString();
    if (BookingStatus.isInactive(status)) {
      return false;
    }
    final source = passenger['source']?.toString().trim().toLowerCase() ?? '';
    final onBoardSource =
        passenger['onBoardSource']?.toString().trim().toLowerCase() ?? '';
    final bookedBy =
        passenger['bookedBy']?.toString().trim().toLowerCase() ?? '';
    return passenger['onBoard'] == true ||
        BookingStatus.isOnboard(status) ||
        _isDispatcherBookingSource(
          source: source,
          onBoardSource: onBoardSource,
          bookedBy: bookedBy,
        );
  }

  bool _isDispatcherBookingSource({
    String source = '',
    String onBoardSource = '',
    String bookedBy = '',
  }) {
    return source.contains('dispatcher') ||
        onBoardSource.contains('dispatcher') ||
        bookedBy.contains('dispatcher');
  }

  bool _isDispatcherBookedCommuter(String commuterId) {
    final schedules = _todayTripSchedules.isNotEmpty
        ? _todayTripSchedules
        : (_currentTripSchedule != null
            ? [_currentTripSchedule!]
            : <Map<String, dynamic>>[]);
    for (final s in schedules) {
      final passengers = s['bookedPassengers'];
      if (passengers is! List) continue;
      final found = passengers.any((p) {
        if (p is! Map) return false;
        final id = p['commuterId']?.toString() ?? '';
        final status = p['status']?.toString();
        if (BookingStatus.isInactive(status)) {
          return false;
        }
        final source = (p['source']?.toString() ?? '').toLowerCase();
        final onBoardSource =
            (p['onBoardSource']?.toString() ?? '').toLowerCase();
        final bookedBy = (p['bookedBy']?.toString() ?? '').toLowerCase();
        final isRoadPickup =
            source == 'road_pickup' || onBoardSource == 'road_pickup';
        return id == commuterId &&
            (_isDispatcherBookingSource(
                  source: source,
                  onBoardSource: onBoardSource,
                  bookedBy: bookedBy,
                ) ||
                (p['onBoard'] == true && !isRoadPickup));
      });
      if (found) return true;
    }
    return false;
  }

  int _passengerUnitCount(Map<String, dynamic> passenger) {
    return _intFromSchedule(
          passenger['passengerCount'] ??
              passenger['waitingCount'] ??
              passenger['count'] ??
              passenger['quantity'],
        ) ??
        1;
  }

  int _currentOnBoardPassengerCount() {
    final schedule = _currentTripSchedule;
    if (schedule == null) return 0;
    return _intFromSchedule(schedule['passengerCount']) ??
        _onBoardPassengerCount(schedule);
  }

  bool _isScheduleTimePassed(Map<String, dynamic> schedule) {
    final scheduledAt = _tripScheduledDateTime(schedule);
    return scheduledAt != null && DateTime.now().isAfter(scheduledAt);
  }

  bool _isPastScheduledTripWindow(Map<String, dynamic> schedule) {
    final scheduledAt = _tripScheduledDateTime(schedule);
    return scheduledAt != null &&
        DateTime.now().isAfter(scheduledAt.add(_maximumTripDuration));
  }

  String _tripStatusLabel(Map<String, dynamic> schedule) {
    if (_isTripScheduleCancelled(schedule)) return 'Cancelled';
    if (_isTripScheduleCompleted(schedule)) return 'Done';
    if (_isTripScheduleActive(schedule) || _isScheduleTimePassed(schedule)) {
      return 'On Trip';
    }
    return 'Scheduled';
  }

  void _showCommuterSheet(CommuterWaitingLocation commuter) {
    final isCurrentScheduleFull =
        _currentTripSchedule != null && _isScheduleFull(_currentTripSchedule!);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.pink.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.person_pin_circle_outlined,
                    color: Colors.pink,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        commuter.displayName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${commuter.waitingCount} passenger(s) waiting',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (commuter.destinationTerminal.isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.flag_outlined, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 6),
                  Text(
                    'To: ${commuter.destinationTerminal}',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[700],
                    ),
                  ),
                ],
              ),
            ],
            if (BookingStatus.isOnboard(commuter.status) ||
                (BookingStatus.isWaiting(commuter.status) &&
                    (_isDispatcherBookedCommuter(commuter.commuterId) ||
                        _isDispatcherBookingSource(
                          source: commuter.source.toLowerCase(),
                          onBoardSource: commuter.onBoardSource.toLowerCase(),
                          bookedBy: commuter.bookedBy.toLowerCase(),
                        ) ||
                        (_currentJeepneyId != null &&
                            commuter.jeepneyId == _currentJeepneyId &&
                            _isDispatcherBookingSource(
                              source: commuter.source.toLowerCase(),
                              onBoardSource:
                                  commuter.onBoardSource.toLowerCase(),
                              bookedBy: commuter.bookedBy.toLowerCase(),
                            ))))) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    unawaited(_markDispatcherCommuterOffboard(commuter));
                  },
                  icon: const Icon(Icons.exit_to_app),
                  label: const Text('Offboard'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.orange.shade600,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ] else if (BookingStatus.isWaiting(commuter.status)) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: isCurrentScheduleFull
                      ? null
                      : () {
                          Navigator.pop(ctx);
                          unawaited(_markRoadPickupOnboard(commuter));
                        },
                  icon: const Icon(Icons.directions_walk),
                  label: Text(
                    isCurrentScheduleFull ? 'Jeep is full' : 'Mark Onboard',
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: isCurrentScheduleFull
                        ? Colors.grey.shade300
                        : Colors.green.shade600,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey.shade300,
                    disabledForegroundColor: Colors.grey.shade700,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
            SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
          ],
        ),
      ),
    );
  }

  Future<void> _markRoadPickupOnboard(CommuterWaitingLocation commuter) async {
    final jeepneyViewModel = context.read<JeepneyViewModel>();
    final tripScheduleId = _currentTripSchedule?['id']?.toString() ?? '';
    final jeepneyId = _currentJeepneyId ?? jeepneyViewModel.jeepneyId;

    final result = await FirestoreService.markCommuterOnboard(
      commuter.commuterId,
      tripScheduleId: tripScheduleId,
      jeepneyId: jeepneyId,
      driverId: jeepneyViewModel.driverId,
      driverName: jeepneyViewModel.driverName,
    );

    if (!mounted) return;

    if (result.success) {
      _showTripActionSnackBar(
        '${commuter.waitingCount} road pickup passenger(s) marked onboard.',
        Colors.green,
      );
    } else {
      _showTripActionSnackBar(
        result.message,
        Colors.orange,
      );
    }
  }

  Future<void> _markDispatcherCommuterOffboard(
      CommuterWaitingLocation commuter) async {
    final jeepneyViewModel = context.read<JeepneyViewModel>();
    final tripScheduleId = _currentTripSchedule?['id']?.toString() ?? '';
    final jeepneyId = _currentJeepneyId ?? jeepneyViewModel.jeepneyId;

    final success = await FirestoreService.markCommuterOffboard(
      commuter.commuterId,
      tripScheduleId: tripScheduleId,
      jeepneyId: jeepneyId,
    );

    if (!mounted) return;

    if (success) {
      _showTripActionSnackBar(
        '${commuter.waitingCount} passenger(s) offboarded.',
        Colors.orange,
      );
    } else {
      _showTripActionSnackBar(
        'Offboard could not be completed.',
        Colors.red,
      );
    }
  }

  Future<void> _onConnectivityChanged() async {
    debugPrint('Internet connectivity changed');

    if (!mounted) return;

    final tripViewModel = context.read<TripViewModel>();
    if (!tripViewModel.isTripActive) return;

    final hasInternet =
        await InternetConnectivityService.hasInternetConnection();

    if (!mounted) return;

    if (!hasInternet) {
      _setLocationUpdateNetworkState(_LocationUpdateNetworkState.noInternet);
    } else {
      _setLocationUpdateNetworkState(_LocationUpdateNetworkState.online);
    }
  }

  Future<void> _getCurrentLocation() async {
    if (!mounted) return;

    setState(() {
      _isLoadingLocation = true;
    });

    try {
      final hasPermission = await _checkLocationPermission();

      if (!hasPermission || !mounted) {
        if (mounted) {
          setState(() {
            _isLoadingLocation = false;
          });
        }
        return;
      }

      // Try to get best position from multiple readings
      Position? bestPosition;
      final readings = <Position>[];
      const maxAttempts = 3;
      const timeoutPerAttempt = Duration(seconds: 5);

      for (int i = 0; i < maxAttempts; i++) {
        try {
          final position = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.bestForNavigation,
            ),
          ).timeout(timeoutPerAttempt);

          readings.add(position);

          // Keep the most accurate reading
          if (bestPosition == null ||
              position.accuracy < bestPosition.accuracy) {
            bestPosition = position;
          }

          // If we got a very accurate reading, stop early
          if (position.accuracy <= 15) {
            break;
          }

          // Small delay between readings
          if (i < maxAttempts - 1) {
            await Future.delayed(const Duration(milliseconds: 500));
          }
        } catch (e) {
          debugPrint('[GPS] Attempt ${i + 1} failed: $e');
          continue;
        }
      }

      if (!mounted) return;

      if (bestPosition == null) {
        _showLocationErrorSnackbar();
        setState(() {
          _isLoadingLocation = false;
        });
        return;
      }

      // Use the best position even if not perfect (accept up to 50m accuracy after retries)

      final filtered = _locationSmoother.filterAndSmooth(bestPosition);

      final rawPosition = filtered?.position ??
          LatLng(bestPosition.latitude, bestPosition.longitude);
      final finalPosition = _snapPositionIfPossible(rawPosition);
      final heading = filtered?.heading ?? bestPosition.heading;

      _hasRealLocationFix = true;

      setState(() {
        _isLoadingLocation = false;
      });

      _animateDriverMarkerTo(
        finalPosition,
        heading: heading,
        duration: const Duration(milliseconds: 500),
        moveCamera: true,
        cameraZoom: 16.0,
      );

      _hasCenteredMapOnFirstFix = true;
      _isTerminalFocusActive = false;

      // Haptic feedback for success
      HapticFeedback.mediumImpact();
    } catch (e) {
      await _handleLocationTrackingError(e);

      if (!mounted) return;

      setState(() {
        _isLoadingLocation = false;
      });
    }
  }

  void _showLocationErrorSnackbar() {
    final languageViewModel = context.read<LanguageViewModel>();
    final isTagalog = languageViewModel.isTagalog;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isTagalog
              ? 'Hindi makuha ang lokasyon. Subukang muli.'
              : 'Could not get location. Please try again.',
          style: const TextStyle(fontSize: 14),
        ),
        backgroundColor: Colors.red.shade700,
        duration: const Duration(seconds: 3),
        action: SnackBarAction(
          label: isTagalog ? 'Subukan' : 'Retry',
          textColor: Colors.white,
          onPressed: _getCurrentLocation,
        ),
      ),
    );
  }

  void _showLowAccuracySnackbar(double accuracy) {
    final languageViewModel = context.read<LanguageViewModel>();
    final isTagalog = languageViewModel.isTagalog;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isTagalog
              ? 'Lokasyon hindi gaanong tumpak (±${accuracy.toStringAsFixed(0)}m). Nasa loob ng gusali?'
              : 'Location not very accurate (±${accuracy.toStringAsFixed(0)}m). Indoors?',
          style: const TextStyle(fontSize: 14),
        ),
        backgroundColor: Colors.orange.shade700,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _showHighAccuracySnackbar(double accuracy) {
    final languageViewModel = context.read<LanguageViewModel>();
    final isTagalog = languageViewModel.isTagalog;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isTagalog
              ? 'Lokasyon ay tumpak (±${accuracy.toStringAsFixed(0)}m)'
              : 'Location accurate (±${accuracy.toStringAsFixed(0)}m)',
          style: const TextStyle(fontSize: 14),
        ),
        backgroundColor: Colors.green.shade700,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<bool> _checkLocationPermission({
    bool requestIfDenied = true,
  }) async {
    if (!mounted) return false;

    return LocationWarningService.checkLocationServiceAndPermission(
      context,
      showWarnings: requestIfDenied,
    );
  }

  Future<bool> _showTripConfirmationDialog({
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    final languageViewModel = context.read<LanguageViewModel>();
    final isTagalog = languageViewModel.isTagalog;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(isTagalog ? 'Kanselahin' : 'Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );

    return confirmed ?? false;
  }

  void _showTripActionSnackBar(String message, Color backgroundColor) {
    AppFeedback.show(
      context,
      message: message,
      backgroundColor: backgroundColor,
    );
  }

  bool _isNoInternetException(Object error) {
    return error.toString().contains('No internet connection');
  }

  // ignore: unused_element
  Future<void> _startTrip() async {
    final tripViewModel = context.read<TripViewModel>();
    final languageViewModel = context.read<LanguageViewModel>();
    final isTagalog = languageViewModel.isTagalog;

    if (!tripViewModel.hasDestination) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  isTagalog
                      ? 'Mangyaring pumili ng terminal na destinasyon'
                      : 'Please choose a terminal destination',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFFF59E0B),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );

      return;
    }

    final schedule = _currentTripSchedule;
    final isEarlyFullStart = _canStartEarlyFullSchedule(schedule);
    if (!_canStartScheduleNow(schedule)) {
      if (schedule != null) {
        _scheduleAutomaticTripStart(schedule);
        _showTripActionSnackBar(
          _scheduleStartBlockedMessage(schedule, isTagalog),
          Colors.orange,
        );
      }
      return;
    }

    final crowdStatus = _setAutomaticCrowdStatus(tripViewModel);

    final confirmed = await _showTripConfirmationDialog(
      title: isTagalog ? 'Simulan ang Biyahe?' : 'Start Trip?',
      message: isEarlyFullStart
          ? (isTagalog
              ? 'Puno na ang jeep. Simulan na ang biyahe ngayon? Mananatili ang oras ng susunod na jeep, pero maaari na silang tumanggap ng pasahero nang mas maaga.'
              : 'Jeep is full. Start this trip now? The next jeep keeps its scheduled departure, but can accept passengers earlier.')
          : (isTagalog
              ? 'Sigurado ka bang gusto mong simulan ang biyahe na ito? Ang iyong live location ay ibabahagi.'
              : 'Are you sure you want to start this trip? Your live location will be shared.'),
      confirmLabel: isTagalog ? 'Simulan' : 'Start Trip',
    );

    if (!confirmed || !mounted) return;

    try {
      await _performStartTrip(tripViewModel, crowdStatus);

      if (!mounted) return;

      _showTripActionSnackBar(
        languageViewModel.isTagalog
            ? 'Matagumpay na nagsimula ang biyahe.'
            : 'Trip started successfully.',
        Colors.green,
      );
    } catch (e) {
      if (!mounted) return;
      if (_isNoInternetException(e)) return;

      _showTripActionSnackBar(
        languageViewModel.isTagalog
            ? 'Nabigong simulan ang biyahe: $e'
            : 'Failed to start trip: $e',
        Colors.red,
      );
    }
  }

  Future<void> _performStartTrip(
    TripViewModel tripViewModel,
    String crowdStatus,
  ) async {
    final schedule = _currentTripSchedule;
    if (!_canStartScheduleNow(schedule)) {
      if (schedule != null) {
        _scheduleAutomaticTripStart(schedule);
        throw Exception(_scheduleStartBlockedMessage(schedule, false));
      }
      throw Exception('This assigned trip is not ready yet.');
    }

    if (_currentJeepneyId == null) {
      await _initializeJeepney();
    }

    if (!mounted) return;

    final jeepneyId = _currentJeepneyId;

    if (jeepneyId == null || jeepneyId.trim().isEmpty) {
      throw Exception('No jeepney assigned.');
    }

    final hasLocationAccess = await _checkLocationPermission();

    if (!hasLocationAccess) {
      throw Exception('Location permission is required to start trip.');
    }

    final hasInternet =
        await InternetConnectivityService.hasInternetConnection();

    if (!hasInternet) {
      _setLocationUpdateNetworkState(_LocationUpdateNetworkState.noInternet);
      throw Exception('No internet connection.');
    }

    if (_routePoints.length < 2 && tripViewModel.destination != null) {
      await _fetchRoute(tripViewModel.destination!);
    }

    if (!mounted) return;

    if (_routePoints.length < 2) {
      throw Exception('Route is not loaded yet.');
    }

    final routeId = _getRouteIdFromName(tripViewModel.currentRoute);

    final startPosition = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
      ),
    );

    if (!_isReliablePosition(startPosition)) {
      throw Exception('Current GPS location is not available yet.');
    }

    tripViewModel.startTrip();

    final initialLocationUpdate = await _sendInitialLocationUpdate(
      position: startPosition,
      jeepneyId: jeepneyId,
      routeId: routeId,
      crowdStatus: crowdStatus,
      tripViewModel: tripViewModel,
      markTripStarted: true,
    );

    if (!initialLocationUpdate.success) {
      throw Exception(initialLocationUpdate.message);
    }

    await RouteService.saveRouteToFirestore(
      jeepneyId,
      _routePoints,
      tripViewModel.destinationName,
      routeId: routeId,
      originTerminal: tripViewModel.originTerminal,
      destinationTerminal: tripViewModel.destinationTerminal,
      isOnTrip: true,
    );

    await AnalyticsTrackingService.startTrip(
      jeepneyId: jeepneyId,
      routeId: routeId,
      routeName: tripViewModel.currentRoute,
      originTerminal: tripViewModel.originTerminal,
      destinationTerminal: tripViewModel.destinationName,
      tripScheduleId: _currentTripSchedule?['id']?.toString(),
    );

    await _markCurrentScheduleOnTrip();
    if (schedule != null) {
      final nextWindowResult =
          await FirestoreService.openNextScheduleBookingAfterTripStart(
        startedSchedule: schedule,
      );
      if (!nextWindowResult.success) {
        debugPrint(
          '[TripScreen] Next jeep booking window update failed: '
          '${nextWindowResult.message}',
        );
      }
    }

    _lastFirestorePosition = null;
    _hasCenteredMapOnFirstFix = true;

    _moveMapSafely(_currentLocation, 16.0);

    await _startLocationTracking();

    _startWatchingCommuterLocations();
    _scheduleAutomaticTripEnd();
    _isTripTrackingStarted = true;
  }

  Future<void> _endTrip() async {
    final languageViewModel = context.read<LanguageViewModel>();
    final isTagalog = languageViewModel.isTagalog;

    final confirmed = await _showTripConfirmationDialog(
      title: isTagalog ? 'Tapusin ang Biyahe?' : 'End Trip?',
      message: isTagalog
          ? 'Sigurado ka bang gusto mong tapusin ang biyahe na ito? Ang live tracking ay hihinto.'
          : 'Are you sure you want to end this trip? Live tracking will stop.',
      confirmLabel: isTagalog ? 'Tapusin' : 'End Trip',
    );

    if (!confirmed || !mounted) return;

    final tripViewModel = context.read<TripViewModel>();
    final routeName = tripViewModel.currentRoute;
    final passengerStatus = tripViewModel.crowdLevelDisplayName;

    try {
      await _finishTrip(
        tripViewModel: tripViewModel,
        showSummary: true,
        routeName: routeName,
        passengerStatus: passengerStatus,
      );

      if (!mounted) return;
      final languageViewModel = context.read<LanguageViewModel>();
      final isTagalog = languageViewModel.isTagalog;

      _showTripActionSnackBar(
        isTagalog
            ? 'Matagumpay na natapos ang biyahe.'
            : 'Trip ended successfully.',
        Colors.green,
      );
    } catch (e) {
      if (!mounted) return;

      final languageViewModel = context.read<LanguageViewModel>();
      final isTagalog = languageViewModel.isTagalog;

      _showTripActionSnackBar(
        isTagalog
            ? 'Nabigong tapusin ang biyahe: $e'
            : 'Failed to end trip: $e',
        Colors.red,
      );
    }
  }

  void _scheduleAutomaticTripEnd() {
    _autoEndTripTimer?.cancel();
    _autoEndTripTimer = Timer(_maximumTripDuration, _autoEndTrip);
  }

  Future<void> _autoEndTrip() async {
    if (!mounted) return;

    final tripViewModel = context.read<TripViewModel>();
    if (!tripViewModel.isTripActive) return;

    try {
      await _finishTrip(
        tripViewModel: tripViewModel,
        showSummary: false,
      );

      if (!mounted) return;
      final languageViewModel = context.read<LanguageViewModel>();
      _showTripActionSnackBar(
        languageViewModel.isTagalog
            ? 'Awtomatikong natapos ang biyahe matapos ang 2 oras.'
            : 'Trip automatically ended after 2 hours.',
        Colors.orange,
      );
    } catch (e) {
      debugPrint('[TripScreen] Auto end failed: $e');
      if (!mounted) return;
      _showTripActionSnackBar(
        'Auto end trip failed: $e',
        Colors.red,
      );
    }
  }

  Future<void> _finishTrip({
    required TripViewModel tripViewModel,
    required bool showSummary,
    String? routeName,
    String? passengerStatus,
  }) async {
    final jeepneyId = _currentJeepneyId;
    _autoEndTripTimer?.cancel();
    _autoEndTripTimer = null;

    if (jeepneyId != null && jeepneyId.trim().isNotEmpty) {
      try {
        final markedCompleted = await _markCurrentScheduleCompleted();
        if (!markedCompleted) return;

        _stopLocationTracking();

        await _syncTripStateToLocationDoc(
          isOnTrip: false,
          clearCrowdStatus: true,
        );

        await AnalyticsTrackingService.endTrip(
          jeepneyId: jeepneyId,
          tripScheduleId: _currentTripSchedule?['id']?.toString(),
        );
        await RouteService.clearRouteFromFirestore(jeepneyId);

        debugPrint('Trip schedule and route cleared on trip end');
      } catch (e) {
        debugPrint('[TripScreen] Error during finishTrip cleanup: $e');
      }
    }

    _clearRoute(clearFirestore: false);
    tripViewModel.endTrip();

    if (!mounted) return;

    _setLocationUpdateNetworkState(_LocationUpdateNetworkState.online);

    if (showSummary) {
      _showTripSummary(
        routeName: routeName ?? '',
        passengerStatus: passengerStatus ?? '',
      );
    }
  }

  Future<void> _startLocationTracking() async {
    final jeepneyId = _currentJeepneyId;

    if (jeepneyId == null || jeepneyId.trim().isEmpty) {
      debugPrint('Cannot start location tracking - no jeepney assigned');
      return;
    }

    final tripViewModel = context.read<TripViewModel>();
    final routeId = _getRouteIdFromName(tripViewModel.currentRoute);
    final crowdStatus = _setAutomaticCrowdStatus(tripViewModel);

    final hasLocationAccess = await _checkLocationPermission();

    if (!mounted) return;

    if (!hasLocationAccess) {
      debugPrint('Cannot start location tracking - no location permission');
      return;
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: _activeTripLocationSettings(distanceFilter: 0),
      );

      if (_isReliablePosition(position)) {
        await _sendInitialLocationUpdate(
          position: position,
          jeepneyId: jeepneyId,
          routeId: routeId,
          crowdStatus: crowdStatus,
          tripViewModel: tripViewModel,
        );
      }
    } catch (e) {
      debugPrint('Could not get initial location: $e');
      unawaited(_handleLocationTrackingError(e));

      await _syncTripStateToLocationDoc(
        isOnTrip: true,
        crowdStatus: crowdStatus,
      );
    }

    await _startLiveMapLocationWatcher();

    _locationUpdateTimer?.cancel();

    _locationUpdateTimer = Timer.periodic(
      const Duration(seconds: 10),
      (timer) async {
        if (!mounted) {
          timer.cancel();
          return;
        }

        final vm = context.read<TripViewModel>();

        if (!vm.isTripActive) {
          return;
        }

        try {
          final position = await Geolocator.getCurrentPosition(
            locationSettings: _activeTripLocationSettings(distanceFilter: 0),
          );

          if (!_isReliablePosition(position)) return;

          final latestRouteId = _getRouteIdFromName(vm.currentRoute);

          await _updateLocationInFirebase(position, latestRouteId);
        } catch (e) {
          debugPrint('Error getting position: $e');
          unawaited(_handleLocationTrackingError(e));
        }
      },
    );
  }

  Future<FirestoreResult<void>> _sendInitialLocationUpdate({
    required Position position,
    required String jeepneyId,
    required String? routeId,
    required String crowdStatus,
    required TripViewModel tripViewModel,
    bool markTripStarted = false,
  }) async {
    final filtered = _locationSmoother.filterAndSmooth(position);

    final rawPosition =
        filtered?.position ?? LatLng(position.latitude, position.longitude);
    final finalPosition = _snapPositionIfPossible(rawPosition);
    final heading = filtered?.heading ?? position.heading;
    final speed = _validSpeed(filtered?.speed ?? position.speed);

    _hasRealLocationFix = true;
    _currentSpeedMps = speed;

    if (mounted) {
      _animateDriverMarkerTo(
        finalPosition,
        heading: heading,
        duration: const Duration(milliseconds: 500),
        moveCamera: true,
        cameraZoom: 16.0,
      );
    }

    final updateResult = await _setActiveTripLocationDoc(
      jeepneyId: jeepneyId,
      position: finalPosition,
      heading: _validHeading(heading),
      speed: speed,
      routeId: routeId,
      crowdStatus: crowdStatus,
      tripViewModel: tripViewModel,
      markTripStarted: markTripStarted,
    );

    if (updateResult.success) {
      _setLocationUpdateNetworkState(_LocationUpdateNetworkState.online);
      _lastFirestorePosition = finalPosition;
      _lastFirestoreLocationWriteAt = DateTime.now();

      debugPrint(
        'Initial location set: lat=${finalPosition.latitude}, lng=${finalPosition.longitude}, isOnTrip=true',
      );
    } else if (updateResult.errorCode == FirestoreErrorCode.unavailable) {
      _setLocationUpdateNetworkState(
        _LocationUpdateNetworkState.weakConnection,
      );
    } else {
      debugPrint('Initial location update failed: ${updateResult.message}');
    }

    return updateResult;
  }

  Future<void> _resumeTripTracking(TripViewModel tripViewModel) async {
    _isTripTrackingStarted = true;
    await _startLocationTracking();
    _startWatchingCommuterLocations();
    if (_routePoints.length < 2 && tripViewModel.destination != null) {
      await _fetchRoute(tripViewModel.destination!, showSnackBar: false);
      if (_routePoints.length >= 2 && _currentJeepneyId != null) {
        final routeId = _getRouteIdFromName(tripViewModel.currentRoute);
        await RouteService.saveRouteToFirestore(
          _currentJeepneyId!,
          _routePoints,
          tripViewModel.destinationName,
          routeId: routeId,
          originTerminal: tripViewModel.originTerminal,
          destinationTerminal: tripViewModel.destinationTerminal,
          isOnTrip: true,
        );
      }
    }
    _scheduleAutomaticTripEnd();
    debugPrint('[TripScreen] Trip tracking resumed for auto-started trip');
  }

  void _stopLocationTracking() {
    _locationUpdateTimer?.cancel();
    _locationUpdateTimer = null;

    _lastFirestorePosition = null;
    _lastFirestoreLocationWriteAt = null;
    _isFirestoreLocationUpdateInProgress = false;
    _firestoreUpdateStartedAt = null;
    _isTripTrackingStarted = false;

    _markerAnimationController.stop();
  }

  Future<FirestoreResult<void>> _setActiveTripLocationDoc({
    required String jeepneyId,
    required LatLng position,
    required double heading,
    required double speed,
    required String? routeId,
    required String crowdStatus,
    required TripViewModel tripViewModel,
    bool markTripStarted = false,
  }) async {
    final cleanJeepneyId = jeepneyId.trim();

    if (cleanJeepneyId.isEmpty) {
      return const FirestoreResult<void>.failure(
        message: 'Jeepney ID is missing.',
        errorCode: FirestoreErrorCode.notFound,
      );
    }

    if (!_isValidLatLng(position)) {
      return FirestoreResult<void>.failure(
        message:
            'Invalid GPS coordinates: lat=${position.latitude}, lng=${position.longitude}',
        errorCode: FirestoreErrorCode.invalidArgument,
      );
    }

    final cleanCrowdStatus = crowdStatus.trim();
    final cleanRouteId = (routeId?.trim().isNotEmpty ?? false)
        ? routeId!.trim()
        : (_getRouteIdFromName(tripViewModel.currentRoute) ?? '');
    final cleanOriginTerminal = tripViewModel.originTerminal.trim();
    final cleanDestinationTerminal = tripViewModel.destinationTerminal.trim();
    final cleanDestination = tripViewModel.destinationName.trim();

    if (cleanCrowdStatus.isEmpty) {
      return const FirestoreResult<void>.failure(
        message: 'Crowd status is missing.',
        errorCode: FirestoreErrorCode.invalidArgument,
      );
    }

    final safeSpeed = _validSpeed(speed);
    final jeepneyViewModel = context.read<JeepneyViewModel>();

    final data = <String, dynamic>{
      'jeepneyId': cleanJeepneyId,
      'lat': position.latitude,
      'lng': position.longitude,
      'geoPoint': GeoPoint(position.latitude, position.longitude),
      'heading': _validHeading(heading),
      'speed': safeSpeed,
      'speedMps': safeSpeed,
      'isOnline': true,
      'online': true,
      'isOnTrip': true,
      'onTrip': true,
      'driverId': jeepneyViewModel.driverId,
      'driverName': jeepneyViewModel.driverName,
      'status': 'active',
      'tripStatus': 'active',
      'routeId': cleanRouteId,
      'originTerminal': cleanOriginTerminal,
      'destinationTerminal': cleanDestinationTerminal,
      'destination': cleanDestination,
      'crowdStatus': cleanCrowdStatus,
      'tripEndedAt': FieldValue.delete(),
      'endedAt': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
      'timestamp': FieldValue.serverTimestamp(),
      'locationUpdatedAt': FieldValue.serverTimestamp(),
    };

    if (_currentTripSchedule != null) {
      final passengerCount =
          _intFromSchedule(_currentTripSchedule!['passengerCount']) ??
              _bookedPassengerCount(_currentTripSchedule!);
      final capacity = _capacityFromSchedule(_currentTripSchedule!);
      data['passengerCount'] = passengerCount;
      data['currentPassengerCount'] = passengerCount;
      if (capacity > 0) {
        data['capacity'] = capacity;
        data['maxCapacity'] = capacity;
      }
      data['tripScheduleId'] = _currentTripSchedule!['id']?.toString() ?? '';
      data['scheduleDate'] =
          _currentTripSchedule!['scheduleDate']?.toString() ?? '';
      data['scheduleTime'] =
          _currentTripSchedule!['scheduleTime']?.toString() ?? '';
      final scheduledAt = _currentTripSchedule!['scheduledAt'];
      if (scheduledAt != null) {
        data['scheduledAt'] = scheduledAt;
      }
    }

    if (markTripStarted) {
      data['tripStartedAt'] = FieldValue.serverTimestamp();
    }

    try {
      await FirebaseFirestore.instance
          .collection('locations')
          .doc(cleanJeepneyId)
          .set(data, SetOptions(merge: true));

      return const FirestoreResult<void>.success(
        message: 'Jeepney location updated successfully.',
      );
    } catch (e) {
      debugPrint('Active trip location update failed: $e');

      return FirestoreResult<void>.failure(
        message: FirestoreService.userFriendlyMessageForError(e),
        errorCode: e is FirebaseException ? e.code : FirestoreErrorCode.unknown,
      );
    }
  }

  Future<void> _syncTripStateToLocationDoc({
    required bool isOnTrip,
    String? crowdStatus,
    bool clearCrowdStatus = false,
    bool markTripStarted = false,
  }) async {
    final jeepneyId = _currentJeepneyId;

    if (jeepneyId == null || jeepneyId.trim().isEmpty) {
      debugPrint('Cannot sync trip state - jeepneyId is null');
      return;
    }

    final cleanJeepneyId = jeepneyId.trim();

    if (!mounted) return;

    final tripViewModel = context.read<TripViewModel>();
    final jeepneyViewModel = context.read<JeepneyViewModel>();

    final routeId = isOnTrip
        ? (_getRouteIdFromName(tripViewModel.currentRoute) ?? '').trim()
        : '';
    final safeSpeed = isOnTrip ? _validSpeed(_currentSpeedMps) : 0.0;
    final cleanPlateNumber = _firstNonEmpty([
      jeepneyViewModel.plateNumber,
      _currentTripSchedule?['plateNumber'],
    ]).trim();
    final hasRealPlateNumber = cleanPlateNumber.isNotEmpty &&
        cleanPlateNumber.toLowerCase() != 'n/a' &&
        cleanPlateNumber != cleanJeepneyId;

    final data = <String, dynamic>{
      'jeepneyId': cleanJeepneyId,
      if (hasRealPlateNumber) 'plateNumber': cleanPlateNumber,
      'isOnline': true,
      'online': true,
      'isOnTrip': isOnTrip,
      'onTrip': isOnTrip,
      'driverId': jeepneyViewModel.driverId,
      'driverName': jeepneyViewModel.driverName,
      'status': isOnTrip ? 'active' : 'completed',
      'tripStatus': isOnTrip ? 'active' : 'completed',
      'routeId': routeId,
      'originTerminal': isOnTrip ? tripViewModel.originTerminal : '',
      'destinationTerminal': isOnTrip ? tripViewModel.destinationTerminal : '',
      'destination': isOnTrip ? tripViewModel.destinationName : '',
      'speed': safeSpeed,
      'speedMps': safeSpeed,
      if (isOnTrip) 'tripEndedAt': FieldValue.delete(),
      if (isOnTrip) 'endedAt': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (isOnTrip && _currentTripSchedule != null) {
      final passengerCount =
          (_currentTripSchedule!['passengerCount'] as num?)?.toInt() ??
              int.tryParse(
                _currentTripSchedule!['passengerCount']?.toString() ?? '',
              ) ??
              0;
      final capacity = _capacityFromSchedule(_currentTripSchedule!);
      data['passengerCount'] = passengerCount;
      data['currentPassengerCount'] = passengerCount;
      if (capacity > 0) {
        data['capacity'] = capacity;
        data['maxCapacity'] = capacity;
      }
      data['tripScheduleId'] = _currentTripSchedule!['id']?.toString() ?? '';
      data['scheduleDate'] =
          _currentTripSchedule!['scheduleDate']?.toString() ?? '';
      data['scheduleTime'] =
          _currentTripSchedule!['scheduleTime']?.toString() ?? '';
      final scheduledAt = _currentTripSchedule!['scheduledAt'];
      if (scheduledAt != null) {
        data['scheduledAt'] = scheduledAt;
      }
    }

    if (_hasRealLocationFix && _isValidLatLng(_currentLocation)) {
      data['lat'] = _currentLocation.latitude;
      data['lng'] = _currentLocation.longitude;
      data['geoPoint'] = GeoPoint(
        _currentLocation.latitude,
        _currentLocation.longitude,
      );
      data['heading'] = _validHeading(_currentHeading);
      data['timestamp'] = FieldValue.serverTimestamp();
      data['locationUpdatedAt'] = FieldValue.serverTimestamp();
    }

    if (isOnTrip) {
      if (markTripStarted) {
        data['tripStartedAt'] = FieldValue.serverTimestamp();
      }

      if (crowdStatus != null && crowdStatus.trim().isNotEmpty) {
        data['crowdStatus'] = crowdStatus.trim();
      }
    } else {
      data['tripEndedAt'] = FieldValue.serverTimestamp();
      data['endedAt'] = FieldValue.serverTimestamp();
      data['crowdStatus'] = FieldValue.delete();
    }

    if (clearCrowdStatus) {
      data['crowdStatus'] = FieldValue.delete();
    }

    await FirebaseFirestore.instance
        .collection('locations')
        .doc(cleanJeepneyId)
        .set(data, SetOptions(merge: true));

    debugPrint(
      'locations/$cleanJeepneyId synced: isOnline=true, online=true, isOnTrip=$isOnTrip, onTrip=$isOnTrip, crowdStatus=$crowdStatus',
    );
  }

  void _startWatchingCommuterLocations() {
    _commuterLocationsSubscription?.cancel();

    final tripViewModel = context.read<TripViewModel>();
    final driverDestination = tripViewModel.destinationTerminal.trim();

    if (driverDestination.isEmpty) {
      if (mounted) {
        setState(() {
          _commuterLocations = [];
        });
      }

      return;
    }

    debugPrint(
      'Watching commuter locations - driver destination: $driverDestination',
    );

    _commuterLocationsSubscription =
        FirestoreService.watchSharedCommuterLocations(
      destinationTerminal: driverDestination,
    ).listen(
      (locations) {
        if (!mounted) return;

        final jeepneyId = _currentJeepneyId;

        // Hide dispatcher-booked commuter markers (they're already onboarded
        // by _ensureDispatcherCommuterDocs via schedule data)
        List<CommuterWaitingLocation> visibleLocations = locations;
        if (jeepneyId != null) {
          visibleLocations = locations.where((loc) {
            if (BookingStatus.isWaiting(loc.status) &&
                loc.jeepneyId == jeepneyId) {
              final isDispatcher = _isDispatcherBookingSource(
                source: loc.source.toLowerCase(),
                onBoardSource: loc.onBoardSource.toLowerCase(),
                bookedBy: loc.bookedBy.toLowerCase(),
              );
              if (isDispatcher) return false;
            }
            return true;
          }).toList();
        }

        setState(() {
          _commuterLocations = visibleLocations;
        });

        debugPrint(
          'Commuter locations updated: ${locations.length}',
        );
      },
      onError: (e) {
        debugPrint('Error watching commuter locations: $e');
      },
    );
  }

  void _stopWatchingCommuterLocations() {
    _commuterLocationsSubscription?.cancel();
    _commuterLocationsSubscription = null;
    _autoOnboardedCommuters.clear();
  }

  void _startWatchingDropOffAlerts(String jeepneyId) {
    _dropOffAlertSubscription?.cancel();
    _dropOffAlertSubscription = FirestoreService.watchDropOffAlerts(
      jeepneyId: jeepneyId,
    ).listen(
      (alerts) {
        if (!mounted || alerts.isEmpty) return;
        if (_isDropOffDialogShowing) return;

        for (final alert in alerts) {
          if (_shownDropOffAlertIds.add(alert.id)) {
            unawaited(_showDropOffAlert(alert));
            break;
          }
        }
      },
      onError: (e) {
        debugPrint('Error watching drop off alerts: $e');
      },
    );
  }

  void _stopWatchingDropOffAlerts() {
    _dropOffAlertSubscription?.cancel();
    _dropOffAlertSubscription = null;
  }

  Future<void> _showDropOffAlert(CommuterWaitingLocation alert) async {
    if (!mounted || _isDropOffDialogShowing) return;

    _isDropOffDialogShowing = true;
    await _startDropOffAlertSound();
    if (!mounted) {
      await _stopDropOffAlertSound();
      _isDropOffDialogShowing = false;
      return;
    }
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Passenger Drop Off'),
          content: Text(
            '${alert.displayName} has dropped off from this jeep.',
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await FirestoreService.acknowledgeDropOffAlert(
                  alert.commuterId,
                );
                if (alert.autoDropOffDeductsPassengerCount &&
                    !alert.isTerminalCashBooking) {
                  _applyLocalDropOffCount(alert.dropOffCount);
                }
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
              },
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } finally {
      await _stopDropOffAlertSound();
      _isDropOffDialogShowing = false;
    }
  }

  Future<void> _startDropOffAlertSound() async {
    try {
      await _dropOffAlertPlayer.stop();
      await _dropOffAlertPlayer.setReleaseMode(ReleaseMode.loop);
      await _dropOffAlertPlayer.play(AssetSource('audio/Para ulet.m4a'));
    } catch (error) {
      debugPrint('[TripScreen] Failed to play drop-off alert sound: $error');
    }
  }

  Future<void> _stopDropOffAlertSound() async {
    try {
      await _dropOffAlertPlayer.stop();
    } catch (error) {
      debugPrint('[TripScreen] Failed to stop drop-off alert sound: $error');
    }
  }

  void _applyLocalDropOffCount(int dropOffCount) {
    final currentSchedule = _currentTripSchedule;
    if (!mounted || currentSchedule == null || dropOffCount <= 0) return;

    final currentPassengerCount =
        _intFromSchedule(currentSchedule['passengerCount']) ??
            _bookedPassengerCount(currentSchedule);
    final nextPassengerCount =
        math.max(0, currentPassengerCount - dropOffCount);

    setState(() {
      final updated = Map<String, dynamic>.from(currentSchedule);
      updated['passengerCount'] = nextPassengerCount;
      _currentTripSchedule = updated;
    });
  }

  Future<void> _adjustManualPassengerCount(int delta) async {
    final currentSchedule = _currentTripSchedule;
    if (_isUpdatingManualPassengerCount ||
        currentSchedule == null ||
        delta == 0) {
      return;
    }

    final scheduleId = currentSchedule['id']?.toString().trim() ?? '';
    final currentPassengerCount =
        _intFromSchedule(currentSchedule['passengerCount']) ??
            _onBoardPassengerCount(currentSchedule);
    final capacity = _capacityFromSchedule(currentSchedule);
    final nextPassengerCount = math.max(
      0,
      capacity > 0
          ? math.min(capacity, currentPassengerCount + delta)
          : currentPassengerCount + delta,
    );

    if (nextPassengerCount == currentPassengerCount) return;

    setState(() {
      _isUpdatingManualPassengerCount = true;
      final updated = Map<String, dynamic>.from(currentSchedule);
      updated['passengerCount'] = nextPassengerCount;
      updated['currentPassengerCount'] = nextPassengerCount;
      _currentTripSchedule = updated;
    });

    try {
      if (scheduleId.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('trip_schedules')
            .doc(scheduleId)
            .set({
          'passengerCount': nextPassengerCount,
          'currentPassengerCount': nextPassengerCount,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    } catch (error) {
      debugPrint('[TripScreen] Failed to update passenger count: $error');
      if (mounted) {
        setState(() {
          final reverted =
              Map<String, dynamic>.from(_currentTripSchedule ?? {});
          reverted['passengerCount'] = currentPassengerCount;
          reverted['currentPassengerCount'] = currentPassengerCount;
          _currentTripSchedule = reverted;
        });
        _showTripActionSnackBar(
          'Could not update passenger count. Please try again.',
          Colors.red,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUpdatingManualPassengerCount = false);
      }
    }
  }

  void _setLocationUpdateNetworkState(_LocationUpdateNetworkState nextState) {
    if (_locationUpdateNetworkState == nextState) return;

    _locationUpdateNetworkState = nextState;

    if (!mounted) return;

    switch (nextState) {
      case _LocationUpdateNetworkState.noInternet:
        debugPrint('Location update paused: no internet connection');
        break;
      case _LocationUpdateNetworkState.weakConnection:
        LocationWarningService.showWeakSignalWarning(context);
        break;
      case _LocationUpdateNetworkState.online:
        debugPrint('Location update connection restored');
        break;
    }
  }

  Future<void> _handleLocationTrackingError(Object error) async {
    debugPrint('Location tracking unavailable: $error');

    if (!mounted) return;

    await _checkLocationPermission(requestIfDenied: false);
  }

  Future<void> _updateLocationInFirebase(
    Position position,
    String? routeId,
  ) async {
    if (!_isReliablePosition(position)) return;

    final filtered = _locationSmoother.filterAndSmooth(position);

    if (filtered == null) {
      return;
    }

    final rawPosition = filtered.position;
    final finalPosition = _snapPositionIfPossible(rawPosition);
    final speed = _validSpeed(filtered.speed);

    _hasRealLocationFix = true;
    _currentSpeedMps = speed;

    if (mounted) {
      final tripViewModel = context.read<TripViewModel>();
      final shouldCenterCamera = !_hasCenteredMapOnFirstFix;

      _animateDriverMarkerTo(
        finalPosition,
        heading: filtered.heading,
        moveCamera: shouldCenterCamera ||
            (tripViewModel.isTripActive && !_isTerminalFocusActive),
        cameraZoom: shouldCenterCamera ? 16.0 : null,
      );

      if (shouldCenterCamera) {
        _hasCenteredMapOnFirstFix = true;
      }
    }

    final jeepneyId = _currentJeepneyId;

    if (jeepneyId == null || jeepneyId.trim().isEmpty) return;
    if (!mounted) return;

    final tripViewModel = context.read<TripViewModel>();

    if (!tripViewModel.isTripActive) {
      return;
    }

    if (_isFirestoreLocationUpdateInProgress) {
      if (_firestoreUpdateStartedAt != null &&
          DateTime.now().difference(_firestoreUpdateStartedAt!) <
              const Duration(seconds: 30)) {
        debugPrint('Skipped Firestore update - previous update still running');
        return;
      }
      debugPrint('Firestore update timeout exceeded - allowing update');
    }

    final hasInternet =
        await InternetConnectivityService.hasInternetConnection();

    if (!hasInternet) {
      _setLocationUpdateNetworkState(_LocationUpdateNetworkState.noInternet);
      return;
    }

    if (_locationUpdateNetworkState == _LocationUpdateNetworkState.noInternet) {
      _setLocationUpdateNetworkState(_LocationUpdateNetworkState.online);
    }

    final crowdStatus = _setAutomaticCrowdStatus(tripViewModel);

    bool shouldUpdateFirestore = true;

    if (_lastFirestorePosition != null) {
      final distance = _calculateDistance(
        _lastFirestorePosition!,
        finalPosition,
      );

      if (distance < _firestoreMinMovement) {
        final lastWriteAt = _lastFirestoreLocationWriteAt;
        final shouldForceFreshLocation = lastWriteAt == null ||
            DateTime.now().difference(lastWriteAt) >=
                _forceLocationWriteInterval;

        shouldUpdateFirestore = shouldForceFreshLocation;
      }
    }

    if (!shouldUpdateFirestore) {
      debugPrint('Skipped Firestore update - movement too small');
      return;
    }

    _isFirestoreLocationUpdateInProgress = true;
    _firestoreUpdateStartedAt = DateTime.now();

    try {
      final updateResult = await _setActiveTripLocationDoc(
        jeepneyId: jeepneyId,
        position: finalPosition,
        heading: _validHeading(filtered.heading),
        speed: speed,
        routeId: routeId,
        crowdStatus: crowdStatus,
        tripViewModel: tripViewModel,
      );

      if (updateResult.success) {
        _setLocationUpdateNetworkState(_LocationUpdateNetworkState.online);
        _lastFirestorePosition = finalPosition;
        _lastFirestoreLocationWriteAt = DateTime.now();

        debugPrint(
          'Location updated: lat=${finalPosition.latitude}, lng=${finalPosition.longitude}, isOnTrip=true',
        );
      } else if (updateResult.errorCode == FirestoreErrorCode.unavailable) {
        _setLocationUpdateNetworkState(
          _LocationUpdateNetworkState.weakConnection,
        );
      } else {
        debugPrint('Location update failed: ${updateResult.message}');
      }
    } catch (e) {
      debugPrint('Error updating location in Firebase: $e');

      final hasInternet =
          await InternetConnectivityService.hasInternetConnection();

      if (!hasInternet && mounted) {
        _setLocationUpdateNetworkState(
          _LocationUpdateNetworkState.noInternet,
        );
      }
    } finally {
      _isFirestoreLocationUpdateInProgress = false;
      _firestoreUpdateStartedAt = null;
    }
  }

  double _calculateDistance(LatLng point1, LatLng point2) {
    const earthRadius = 6371000.0;

    final dLat = _degreesToRadians(point2.latitude - point1.latitude);
    final dLng = _degreesToRadians(point2.longitude - point1.longitude);

    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degreesToRadians(point1.latitude)) *
            math.cos(_degreesToRadians(point2.latitude)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);

    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

    return earthRadius * c;
  }

  String? _getRouteIdFromName(String routeName) {
    switch (routeName.toLowerCase().trim()) {
      case 'lucban to sta. cruz':
      case 'lucban to sta cruz':
      case 'lucban - luisiana - sta. cruz':
        return 'ROUTE001';

      case 'sta. cruz to lucban':
      case 'sta cruz to lucban':
        return 'ROUTE002';

      case 'luisiana - sta. cruz':
        return 'ROUTE003';

      default:
        return 'ROUTE001';
    }
  }

  void _showTripSummary({
    required String routeName,
    required String passengerStatus,
  }) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        title: const Text('Trip Summary'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Route: $routeName'),
            const SizedBox(height: 8),
            Text('Passenger Status: $passengerStatus'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _zoomIn() {
    try {
      final currentZoom = _mapController.camera.zoom;

      if (currentZoom < 18.0) {
        _mapController.move(_mapController.camera.center, currentZoom + 1);
      }
    } catch (_) {
      // Map is not ready yet.
    }
  }

  void _zoomOut() {
    try {
      final currentZoom = _mapController.camera.zoom;

      if (currentZoom > 10.0) {
        _mapController.move(_mapController.camera.center, currentZoom - 1);
      }
    } catch (_) {
      // Map is not ready yet.
    }
  }

  void _resetMapNorth() {
    try {
      _mapController.rotate(0);
      setState(() => _mapRotation = 0);
    } catch (_) {
      // Map is not ready yet.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<TripViewModel>(
      builder: (context, tripViewModel, child) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final screenHeight = constraints.maxHeight;
            final topPadding = MediaQuery.of(context).padding.top;

            final bottomPanelHeight = math.min(
              math.max(screenHeight * 0.11, 88.0),
              112.0,
            );
            final mapCameraPadding = _cameraPaddingForVisibleMap(
              topPadding: topPadding,
              bottomPanelHeight: bottomPanelHeight,
            );
            final mapCameraOffset = _cameraOffsetForFocusBox(
              screenWidth: constraints.maxWidth,
              screenHeight: screenHeight,
              topPadding: topPadding,
              bottomPanelHeight: bottomPanelHeight,
            );
            _latestMapCameraPadding = mapCameraPadding;
            _latestMapCameraOffset = mapCameraOffset;
            final passengerCount = _currentOnBoardPassengerCount();
            final capacity = _currentTripSchedule == null
                ? context.watch<JeepneyViewModel>().capacity
                : _capacityFromSchedule(_currentTripSchedule!);
            final canStartEarlyFullTrip =
                _canStartEarlyFullSchedule(_currentTripSchedule);
            final crowdLevel =
                _crowdLevelForPassengerCount(passengerCount, capacity);
            final crowdColor = _crowdStatusColor(crowdLevel);
            final crowdLabel = _crowdStatusLabel(crowdLevel);

            return Scaffold(
              backgroundColor: Colors.transparent,
              body: Stack(
                children: [
                  Positioned.fill(
                    child: DriverMapWidget(
                      mapController: _mapController,
                      currentLocation: _currentLocation,
                      currentHeading: _currentHeading,
                      destination: tripViewModel.destination,
                      routePoints: _routePoints,
                      commuterLocations: _commuterLocations,
                      cameraPadding: mapCameraPadding,
                      passengerCount: passengerCount,
                      maxCapacity: capacity,
                      crowdLabel: crowdLabel,
                      crowdColor: crowdColor,
                      onCommuterTapped: _showCommuterSheet,
                      onMapRotationChanged: (rotation) {
                        if ((_mapRotation - rotation).abs() > 0.1) {
                          setState(() => _mapRotation = rotation);
                        }
                      },
                      onTerminalTapped: (terminal) {
                        if (tripViewModel.isTripActive) {
                          _showCannotChangeDestinationSnackBar();
                          return;
                        }

                        final terminalName = _terminalFullName(terminal);

                        final languageViewModel =
                            context.read<LanguageViewModel>();
                        final isTagalog = languageViewModel.isTagalog;

                        showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                            title: Text(isTagalog
                                ? 'Itakda ang Destinasyon'
                                : 'Set Destination'),
                            content: Text(
                              isTagalog
                                  ? 'Sigurado ka bang gusto mong itakda ang "$terminalName" bilang iyong destinasyon?'
                                  : 'Are you sure you want to set "$terminalName" as your destination?',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child:
                                    Text(isTagalog ? 'Kanselahin' : 'Cancel'),
                              ),
                              if (tripViewModel.hasDestination &&
                                  !tripViewModel.isTripActive)
                                TextButton(
                                  onPressed: () {
                                    Navigator.pop(context);
                                    unawaited(
                                      _handleDestinationSelection(null),
                                    );
                                  },
                                  child: Text(isTagalog ? 'Burahin' : 'Clear'),
                                ),
                              ElevatedButton(
                                onPressed: () {
                                  Navigator.pop(context);
                                  unawaited(
                                    _handleDestinationSelection(terminal),
                                  );
                                },
                                child:
                                    Text(isTagalog ? 'Kumpirmahin' : 'Confirm'),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  Positioned(
                    top: topPadding + 8,
                    left: 12,
                    right: 12,
                    child: _RouteCard(
                      routeName: tripViewModel.currentRoute,
                      scheduleRouteName: _currentTripSchedule == null
                          ? ''
                          : _tripRouteLabel(_currentTripSchedule!),
                      isActive: tripViewModel.isTripActive,
                      destinationName: tripViewModel.destinationName,
                      driverLocation: _currentLocation,
                      selectedDestination: tripViewModel.destination,
                      isLoadingRoute: _isLoadingRoute,
                      hasRoute: _routePoints.length >= 2,
                      terminalDisplayNameBuilder: _terminalDisplayName,
                      onDestinationChanged: (terminal) {
                        unawaited(_handleDestinationSelection(terminal));
                      },
                      onClearDestination: () {
                        unawaited(_handleDestinationSelection(null));
                      },
                      onFitRoute: () => _fitRouteToMap(
                        cameraPadding: mapCameraPadding,
                        cameraOffset: mapCameraOffset,
                      ),
                    ),
                  ),
                  if (tripViewModel.isTripActive)
                    Positioned(
                      left: 12,
                      bottom: bottomPanelHeight + 12,
                      child: _PassengerOnBoardControl(
                        passengerCount: passengerCount,
                        maxCapacity: capacity,
                        crowdLabel: crowdLabel,
                        crowdColor: crowdColor,
                        isLoading: _isUpdatingManualPassengerCount,
                        onIncrement: capacity <= 0 || passengerCount < capacity
                            ? () => _adjustManualPassengerCount(1)
                            : null,
                        onDecrement: passengerCount > 0
                            ? () => _adjustManualPassengerCount(-1)
                            : null,
                      ),
                    ),
                  Positioned(
                    right: 12,
                    bottom: bottomPanelHeight + 12,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _MapControlButton(
                          icon: Icons.center_focus_strong_rounded,
                          tooltip: 'Refocus terminals',
                          onTap: () => _focusTerminalPoints(
                            cameraPadding: mapCameraPadding,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _CompassMapControlButton(
                          rotation: _mapRotation,
                          onTap: _resetMapNorth,
                        ),
                        const SizedBox(height: 8),
                        _MapControlButton(
                          icon: Icons.add_rounded,
                          onTap: _zoomIn,
                        ),
                        const SizedBox(height: 8),
                        _MapControlButton(
                          icon: Icons.remove_rounded,
                          onTap: _zoomOut,
                        ),
                        const SizedBox(height: 8),
                        _MapControlButton(
                          icon: Icons.my_location_rounded,
                          isLoading: _isLoadingLocation,
                          onTap: _getCurrentLocation,
                        ),
                        const SizedBox(height: 8),
                        _MapControlButton(
                          icon: Icons.event_note_rounded,
                          isLoading: _isLoadingPassengers,
                          onTap: _showTripScheduleList,
                        ),
                        const SizedBox(height: 8),
                        _MapControlButton(
                          icon: _isCurrentScheduleDoneForControls()
                              ? Icons.check_circle_outline
                              : Icons.people_rounded,
                          isLoading: _isLoadingPassengers,
                          onTap: _showPassengerList,
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    height: bottomPanelHeight,
                    child: _BottomControlPanel(
                      isTripActive: tripViewModel.isTripActive,
                      isScheduleDone: _isCurrentScheduleDoneForControls(),
                      canStartTrip: canStartEarlyFullTrip,
                      onStartTrip: _startTrip,
                      onEndTrip: _endTrip,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  bool _isCurrentScheduleDoneForControls() {
    if (_currentTripSchedule != null) {
      return _isTripScheduleCompleted(_currentTripSchedule!);
    }
    return _todayTripSchedules.isNotEmpty &&
        _todayTripSchedules.every(_isTripScheduleCompleted);
  }
}

class _RouteProgressSegments {
  const _RouteProgressSegments({
    required this.consumed,
    required this.remaining,
  });

  final List<LatLng> consumed;
  final List<LatLng> remaining;

  factory _RouteProgressSegments.fromRoute({
    required List<LatLng> routePoints,
    required LatLng currentLocation,
  }) {
    if (routePoints.length < 2) {
      return const _RouteProgressSegments(consumed: [], remaining: []);
    }

    var nearestSegmentIndex = 0;
    var nearestPoint = routePoints.first;
    var nearestDistance = double.infinity;

    for (var i = 0; i < routePoints.length - 1; i++) {
      final projected = _closestPointOnSegment(
        routePoints[i],
        routePoints[i + 1],
        currentLocation,
      );
      final distance = _distanceMeters(currentLocation, projected);
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearestPoint = projected;
        nearestSegmentIndex = i;
      }
    }

    if (nearestDistance > 1000) {
      return _RouteProgressSegments(
        consumed: const [],
        remaining: routePoints,
      );
    }

    final consumed = <LatLng>[
      ...routePoints.take(nearestSegmentIndex + 1),
    ];
    if (!_samePoint(consumed.last, nearestPoint)) {
      consumed.add(nearestPoint);
    }

    final remaining = <LatLng>[nearestPoint];
    final nextPoints = routePoints.skip(nearestSegmentIndex + 1);
    for (final point in nextPoints) {
      if (!_samePoint(remaining.last, point)) {
        remaining.add(point);
      }
    }

    return _RouteProgressSegments(
      consumed: consumed.length >= 2 ? consumed : const [],
      remaining: remaining.length >= 2 ? remaining : const [],
    );
  }

  static LatLng _closestPointOnSegment(
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
    if (segmentLengthSquared == 0) return start;

    final t = ((pointXY.x - startXY.x) * dx + (pointXY.y - startXY.y) * dy) /
        segmentLengthSquared;
    final clampedT = t.clamp(0.0, 1.0).toDouble();

    return _fromLocalMeters(
      startXY.x + clampedT * dx,
      startXY.y + clampedT * dy,
      refLat,
    );
  }

  static _RouteXY _toLocalMeters(LatLng point, double refLatRadians) {
    const earthRadius = 6371000.0;
    final x =
        _toRadians(point.longitude) * earthRadius * math.cos(refLatRadians);
    final y = _toRadians(point.latitude) * earthRadius;
    return _RouteXY(x, y);
  }

  static LatLng _fromLocalMeters(
    double x,
    double y,
    double refLatRadians,
  ) {
    const earthRadius = 6371000.0;
    final lat = (y / earthRadius) * 180 / math.pi;
    final lng = (x / (earthRadius * math.cos(refLatRadians))) * 180 / math.pi;
    return LatLng(lat, lng);
  }

  static double _distanceMeters(LatLng a, LatLng b) {
    const earthRadius = 6371000.0;
    final dLat = _toRadians(b.latitude - a.latitude);
    final dLng = _toRadians(b.longitude - a.longitude);
    final value = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(a.latitude)) *
            math.cos(_toRadians(b.latitude)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(value), math.sqrt(1 - value));
    return earthRadius * c;
  }

  static bool _samePoint(LatLng a, LatLng b) {
    return (a.latitude - b.latitude).abs() < 0.0000001 &&
        (a.longitude - b.longitude).abs() < 0.0000001;
  }

  static double _toRadians(double degrees) {
    return degrees * math.pi / 180.0;
  }
}

class _RouteXY {
  const _RouteXY(this.x, this.y);

  final double x;
  final double y;
}

class DriverMapWidget extends StatelessWidget {
  final MapController mapController;
  final LatLng currentLocation;
  final double currentHeading;
  final Function(Terminal)? onTerminalTapped;
  final Terminal? destination;
  final List<LatLng> routePoints;
  final List<CommuterWaitingLocation> commuterLocations;
  final EdgeInsets cameraPadding;
  final int passengerCount;
  final int maxCapacity;
  final String crowdLabel;
  final Color crowdColor;
  final Function(CommuterWaitingLocation)? onCommuterTapped;
  final ValueChanged<double>? onMapRotationChanged;

  const DriverMapWidget({
    super.key,
    required this.mapController,
    required this.currentLocation,
    required this.currentHeading,
    this.onTerminalTapped,
    this.destination,
    this.routePoints = const [],
    this.commuterLocations = const [],
    this.cameraPadding = const EdgeInsets.fromLTRB(34, 220, 112, 26),
    this.passengerCount = 0,
    this.maxCapacity = 0,
    this.crowdLabel = 'Maluwag',
    this.crowdColor = const Color(0xFF16A34A),
    this.onCommuterTapped,
    this.onMapRotationChanged,
  });

  static const LatLng terminalA = LatLng(14.1149875, 121.551859375);
  static const LatLng terminalB = LatLng(14.2659625, 121.425578125);

  static Widget _buildTerminalMarker(Color color) {
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.45),
            blurRadius: 10,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Center(
        child: const Icon(
          Icons.location_city_rounded,
          color: Colors.white,
          size: 24,
        ),
      ),
    );
  }

  static List<Marker> _buildCommuterMarkers(
    List<CommuterWaitingLocation> locations, {
    LatLng? driverLocation,
    Function(CommuterWaitingLocation)? onTap,
  }) {
    return locations
        .where((location) => location.hasCoordinates)
        .map((location) {
      final point = LatLng(location.lat!, location.lng!);
      final commuterTap = onTap != null ? () => onTap(location) : null;
      if (driverLocation != null) {
        final dLat = (point.latitude - driverLocation.latitude).abs();
        final dLng = (point.longitude - driverLocation.longitude).abs();
        if (dLat < 0.002 && dLng < 0.002) {
          return Marker(
            point: LatLng(point.latitude, point.longitude + 0.0006),
            width: 48,
            height: 48,
            rotate: true,
            child: _CommuterMarker(
              waitingCount: location.waitingCount,
              onTap: commuterTap,
            ),
          );
        }
      }
      return Marker(
        point: point,
        width: 48,
        height: 48,
        rotate: true,
        child: _CommuterMarker(
          waitingCount: location.waitingCount,
          onTap: commuterTap,
        ),
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final routeProgress = _RouteProgressSegments.fromRoute(
      routePoints: routePoints,
      currentLocation: currentLocation,
    );

    return FlutterMap(
      mapController: mapController,
      options: MapOptions(
        initialCenter: currentLocation,
        initialZoom: 14.0,
        minZoom: 10.0,
        maxZoom: 18.0,
        initialCameraFit: CameraFit.bounds(
          bounds: LatLngBounds.fromPoints([terminalA, terminalB]),
          padding: cameraPadding,
        ),
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all,
        ),
        onMapEvent: (event) => onMapRotationChanged?.call(
          event.camera.rotation,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.byaherox.driver',
          maxZoom: 19,
        ),
        if (destination != null && routePoints.length >= 2)
          PolylineLayer(
            polylines: [
              Polyline(
                points: routePoints,
                strokeWidth: 10.0,
                color: Colors.white.withValues(alpha: 0.98),
              ),
            ],
          ),
        if (destination != null && routePoints.length >= 2)
          PolylineLayer(
            polylines: [
              if (routeProgress.consumed.isNotEmpty)
                Polyline(
                  points: routeProgress.consumed,
                  strokeWidth: 7.2,
                  color: const Color(0xFF64748B).withValues(alpha: 0.62),
                ),
              if (routeProgress.remaining.isNotEmpty)
                Polyline(
                  points: routeProgress.remaining,
                  strokeWidth: 7.2,
                  color: const Color(0xFF0F172A).withValues(alpha: 0.70),
                ),
            ],
          ),
        if (destination != null && routePoints.length >= 2)
          PolylineLayer(
            polylines: [
              if (routeProgress.consumed.isNotEmpty)
                Polyline(
                  points: routeProgress.consumed,
                  strokeWidth: 4.5,
                  color: const Color(0xFF94A3B8).withValues(alpha: 0.72),
                ),
              if (routeProgress.remaining.isNotEmpty)
                Polyline(
                  points: routeProgress.remaining,
                  strokeWidth: 4.5,
                  color: const Color(0xFF2563EB),
                ),
            ],
          ),
        if (commuterLocations.isNotEmpty)
          MarkerLayer(
            markers: _buildCommuterMarkers(
              commuterLocations,
              driverLocation: currentLocation,
              onTap: onCommuterTapped,
            ),
          ),
        MarkerLayer(
          markers: [
            Marker(
              point: terminalA,
              width: 50,
              height: 50,
              alignment: Alignment.center,
              rotate: true,
              child: GestureDetector(
                onTap: () => onTerminalTapped?.call(Terminal.terminalA),
                child: _buildTerminalMarker(Colors.green),
              ),
            ),
            Marker(
              point: terminalB,
              width: 50,
              height: 50,
              alignment: Alignment.center,
              rotate: true,
              child: GestureDetector(
                onTap: () => onTerminalTapped?.call(Terminal.terminalB),
                child: _buildTerminalMarker(Colors.orange),
              ),
            ),
            Marker(
              point: currentLocation,
              width: 112,
              height: 82,
              rotate: true,
              child: _DriverMarker(
                heading: currentHeading,
                passengerCount: passengerCount,
                maxCapacity: maxCapacity,
                crowdLabel: crowdLabel,
                crowdColor: crowdColor,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _DriverMarker extends StatelessWidget {
  final double heading;
  final int passengerCount;
  final int maxCapacity;
  final String crowdLabel;
  final Color crowdColor;

  const _DriverMarker({
    required this.heading,
    required this.passengerCount,
    required this.maxCapacity,
    required this.crowdLabel,
    required this.crowdColor,
  });

  @override
  Widget build(BuildContext context) {
    final rotationRadians = heading * math.pi / 180;
    final countLabel =
        maxCapacity > 0 ? '$passengerCount/$maxCapacity' : '$passengerCount';

    return SizedBox(
      width: 112,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: crowdColor, width: 1.5),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 6,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.groups_rounded, size: 12, color: crowdColor),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    countLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: crowdColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    crowdLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: crowdColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 3),
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: crowdColor.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: crowdColor.withValues(alpha: 0.55),
                    width: 2,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 6,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
              ),
              Container(
                width: 34,
                height: 34,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
              ),
              Transform.rotate(
                angle: rotationRadians,
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryBlue,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(
                      color: Colors.white,
                      width: 2,
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 4,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.navigation_rounded,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CommuterMarker extends StatelessWidget {
  final int waitingCount;
  final VoidCallback? onTap;

  const _CommuterMarker({required this.waitingCount, this.onTap});

  @override
  Widget build(BuildContext context) {
    final safeCount = waitingCount < 1 ? 1 : waitingCount;

    return GestureDetector(
      onTap: onTap,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.pink,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.pink.withValues(alpha: 0.4),
                  blurRadius: 8,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Center(
              child: Text(
                '$safeCount',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: Colors.purple,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1),
              ),
              child: const Icon(
                Icons.person,
                color: Colors.white,
                size: 10,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MapControlButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool isLoading;
  final String? tooltip;

  const _MapControlButton({
    required this.icon,
    required this.onTap,
    this.isLoading = false,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final button = DriverGlassSurface(
      width: 56,
      height: 56,
      padding: EdgeInsets.zero,
      borderRadius: BorderRadius.circular(16),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(15),
          onTap: onTap,
          child: SizedBox(
            width: 56,
            height: 56,
            child: Center(
              child: isLoading
                  ? const SizedBox(
                      width: 21,
                      height: 21,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.primaryBlue,
                      ),
                    )
                  : Icon(
                      icon,
                      color: AppTheme.primaryBlue,
                      size: 25,
                    ),
            ),
          ),
        ),
      ),
    );

    if (tooltip == null) return button;
    return Tooltip(
      message: tooltip!,
      child: button,
    );
  }
}

class _CompassMapControlButton extends StatelessWidget {
  final double rotation;
  final VoidCallback onTap;

  const _CompassMapControlButton({
    required this.rotation,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return DriverGlassSurface(
      width: 56,
      height: 56,
      padding: EdgeInsets.zero,
      borderRadius: BorderRadius.circular(16),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(15),
          onTap: onTap,
          child: SizedBox(
            width: 56,
            height: 56,
            child: Center(
              child: Transform.rotate(
                angle: -rotation * math.pi / 180,
                child: const Icon(
                  Icons.navigation_rounded,
                  color: AppTheme.primaryRed,
                  size: 27,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AwaitingScheduleNotice extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final languageViewModel = context.watch<LanguageViewModel>();
    final isTagalog = languageViewModel.isTagalog;
    return DriverGlassSurface(
      padding: EdgeInsets.zero,
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(24),
        topRight: Radius.circular(24),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.schedule, color: AppTheme.primaryBlue, size: 20),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  isTagalog
                      ? 'Naghihintay ng susunod na biyahe...'
                      : 'Awaiting next trip schedule...',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.primaryBlue,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PassengerOnBoardControl extends StatelessWidget {
  final int passengerCount;
  final int maxCapacity;
  final String crowdLabel;
  final Color crowdColor;
  final bool isLoading;
  final VoidCallback? onIncrement;
  final VoidCallback? onDecrement;

  const _PassengerOnBoardControl({
    required this.passengerCount,
    required this.maxCapacity,
    required this.crowdLabel,
    required this.crowdColor,
    required this.isLoading,
    required this.onIncrement,
    required this.onDecrement,
  });

  @override
  Widget build(BuildContext context) {
    final countText =
        maxCapacity > 0 ? '$passengerCount / $maxCapacity' : '$passengerCount';

    return DriverGlassSurface(
      width: 178,
      padding: const EdgeInsets.all(10),
      borderRadius: BorderRadius.circular(18),
      borderColor: crowdColor.withValues(alpha: 0.35),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.groups_rounded, color: crowdColor, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  crowdLabel,
                  style: TextStyle(
                    color: crowdColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            countText,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _PassengerCountButton(
                  icon: Icons.remove_rounded,
                  onTap: isLoading ? null : onDecrement,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _PassengerCountButton(
                  icon: Icons.add_rounded,
                  onTap: isLoading ? null : onIncrement,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PassengerCountButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _PassengerCountButton({
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: onTap == null
          ? Colors.grey.withValues(alpha: 0.12)
          : AppTheme.primaryBlue.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: SizedBox(
          height: 34,
          child: Icon(
            icon,
            color: onTap == null ? Colors.grey : AppTheme.primaryBlue,
            size: 20,
          ),
        ),
      ),
    );
  }
}

class _RouteCard extends StatelessWidget {
  final String routeName;
  final String scheduleRouteName;
  final bool isActive;
  final String destinationName;
  final LatLng driverLocation;
  final Terminal? selectedDestination;
  final bool isLoadingRoute;
  final bool hasRoute;
  final String Function(Terminal) terminalDisplayNameBuilder;
  final ValueChanged<Terminal> onDestinationChanged;
  final VoidCallback onClearDestination;
  final VoidCallback onFitRoute;

  const _RouteCard({
    required this.routeName,
    required this.scheduleRouteName,
    required this.isActive,
    required this.destinationName,
    required this.driverLocation,
    required this.selectedDestination,
    required this.isLoadingRoute,
    required this.hasRoute,
    required this.terminalDisplayNameBuilder,
    required this.onDestinationChanged,
    required this.onClearDestination,
    required this.onFitRoute,
  });

  String _terminalSubtitle(Terminal terminal) {
    switch (terminal) {
      case Terminal.terminalA:
        return 'Lucban Terminal';
      case Terminal.terminalB:
        return 'Sta. Cruz Terminal';
    }
  }

  @override
  Widget build(BuildContext context) {
    final routeLabel = scheduleRouteName.trim().isNotEmpty
        ? scheduleRouteName.trim()
        : routeName.trim().isNotEmpty
            ? routeName.trim()
            : 'No active route';
    final canFitRoute = hasRoute && !isLoadingRoute;

    return DriverGlassSurface(
      padding: const EdgeInsets.all(12),
      borderRadius: BorderRadius.circular(18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppTheme.primaryBlue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.route_rounded,
                  color: AppTheme.primaryBlue,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Choose destination',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      routeLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (canFitRoute)
                IconButton(
                  tooltip: 'Fit route',
                  onPressed: onFitRoute,
                  icon: const Icon(Icons.center_focus_strong_rounded),
                  color: AppTheme.primaryBlue,
                ),
            ],
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<Terminal>(
            initialValue: selectedDestination,
            isExpanded: true,
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: AppTheme.primaryBlue.withValues(alpha: 0.06),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
            hint: const Text('Choose destination'),
            items: Terminal.values.map((terminal) {
              return DropdownMenuItem<Terminal>(
                value: terminal,
                child: Text(
                  _terminalSubtitle(terminal),
                  overflow: TextOverflow.ellipsis,
                ),
              );
            }).toList(),
            selectedItemBuilder: (context) {
              return Terminal.values.map((terminal) {
                return Text(
                  terminalDisplayNameBuilder(terminal),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                );
              }).toList();
            },
            onChanged: isActive || isLoadingRoute
                ? null
                : (terminal) {
                    if (terminal != null) onDestinationChanged(terminal);
                  },
          ),
          if (selectedDestination != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    isActive ? 'On trip to $destinationName' : destinationName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isActive ? Colors.green[700] : Colors.grey[700],
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (!isActive)
                  TextButton(
                    onPressed: onClearDestination,
                    child: const Text('Clear'),
                  ),
              ],
            ),
          ],
          if (isLoadingRoute) ...[
            const SizedBox(height: 8),
            const LinearProgressIndicator(minHeight: 3),
          ],
        ],
      ),
    );
  }
}

class _BottomControlPanel extends StatelessWidget {
  final bool isTripActive;
  final bool isScheduleDone;
  final bool canStartTrip;
  final VoidCallback onStartTrip;
  final VoidCallback onEndTrip;

  const _BottomControlPanel({
    required this.isTripActive,
    required this.isScheduleDone,
    required this.canStartTrip,
    required this.onStartTrip,
    required this.onEndTrip,
  });

  @override
  Widget build(BuildContext context) {
    if (!isTripActive && !isScheduleDone && !canStartTrip) {
      return _AwaitingScheduleNotice();
    }
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ActionButton(
                isTripActive: isTripActive,
                isScheduleDone: isScheduleDone,
                canStartTrip: canStartTrip,
                onStartTrip: onStartTrip,
                onEndTrip: onEndTrip,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final bool isTripActive;
  final bool isScheduleDone;
  final bool canStartTrip;
  final VoidCallback onStartTrip;
  final VoidCallback onEndTrip;

  const _ActionButton({
    required this.isTripActive,
    required this.isScheduleDone,
    required this.canStartTrip,
    required this.onStartTrip,
    required this.onEndTrip,
  });

  @override
  Widget build(BuildContext context) {
    final languageViewModel = context.watch<LanguageViewModel>();
    final isTagalog = languageViewModel.isTagalog;

    final buttonColor = isScheduleDone
        ? Colors.grey
        : isTripActive
            ? const Color(0xFFEF4444)
            : const Color(0xFF10B981);

    final buttonText = isScheduleDone
        ? (isTagalog ? 'TAPOS NA ANG BIYAHE' : 'TRIP DONE')
        : isTripActive
            ? (isTagalog ? 'TAPUSIN ANG BIYAHE' : 'END TRIP')
            : (isTagalog ? 'SIMULAN NA' : 'START TRIP NOW');

    final buttonIcon = isScheduleDone
        ? Icons.check_circle_rounded
        : isTripActive
            ? Icons.stop_circle_rounded
            : Icons.play_circle_fill_rounded;

    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: isScheduleDone
            ? null
            : isTripActive
                ? onEndTrip
                : canStartTrip
                    ? onStartTrip
                    : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: buttonColor,
          foregroundColor: Colors.white,
          elevation: 4,
          shadowColor: buttonColor.withValues(alpha: 0.36),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(buttonIcon, size: 24),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                buttonText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BookingRouteDropdownItem extends StatelessWidget {
  const _BookingRouteDropdownItem({
    required this.label,
    required this.fare,
    this.isSelectedField = false,
  });

  final String label;
  final double fare;
  final bool isSelectedField;

  @override
  Widget build(BuildContext context) {
    final routeText = label.replaceAll(' to ', '\nto ');
    final priceText = fare > 0 ? 'PHP ${fare.toStringAsFixed(2)}' : '';

    return Padding(
      padding: EdgeInsets.symmetric(
        vertical: isSelectedField ? 2 : 10,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              routeText,
              softWrap: true,
              maxLines: isSelectedField ? 2 : 3,
              overflow: TextOverflow.visible,
              style: const TextStyle(
                color: AppTheme.primaryBlue,
                fontSize: 14,
                fontWeight: FontWeight.w800,
                height: 1.18,
              ),
            ),
          ),
          if (priceText.isNotEmpty) ...[
            const SizedBox(width: 12),
            Text(
              priceText,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: Colors.grey.shade700,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                height: 1.1,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BookingChoiceTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final bool enabled;
  final VoidCallback? onTap;

  const _BookingChoiceTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    this.enabled = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final canTap = enabled && onTap != null;
    final color = selected ? AppTheme.primaryBlue : Colors.grey.shade700;

    return InkWell(
      onTap: canTap ? onTap : null,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        constraints: const BoxConstraints(minHeight: 86),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.primaryBlue.withValues(alpha: 0.08)
              : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? AppTheme.primaryBlue : Colors.grey.shade300,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: canTap ? color : Colors.grey.shade400,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: canTap ? color : Colors.grey.shade400,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: canTap ? Colors.grey.shade700 : Colors.grey.shade400,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
