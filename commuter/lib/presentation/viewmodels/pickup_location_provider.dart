import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../../core/constants/booking_status.dart';
import '../../data/services/pickup_location_service.dart';

class PickupLocationProvider extends ChangeNotifier {
  LatLng? _pickupLocation;
  bool _isLoading = false;
  bool _isSharing = false;
  String? _routeId;
  String? _jeepneyId;
  int? _waitingCount;
  String? _destinationTerminal;
  String? _status;
  String? _source;
  String? _onBoardSource;
  String? _bookedBy;
  bool _onBoard = false;
  String? _errorMessage;
  bool? _previousOnBoardState;
  bool _pendingOnboardNotification = false;
  StreamSubscription? _locationSubscription;
  StreamSubscription? _jeepneyLocationSubscription;
  Timer? _sharingExpiryTimer;

  LatLng? get pickupLocation => _pickupLocation;
  bool get isLoading => _isLoading;
  bool get isSharing => _isSharing;
  bool get hasLocation => _pickupLocation != null;
  String? get routeId => _routeId;
  String? get jeepneyId => _jeepneyId;
  String? get destinationTerminal => _destinationTerminal;
  int? get waitingCount => _waitingCount;
  int get passengerCount {
    final count = _waitingCount ?? 1;
    return count < 1 ? 1 : count;
  }

  String get passengerLabel =>
      passengerCount == 1 ? '1 passenger' : '$passengerCount passengers';
  String? get status => _status;
  String? get errorMessage => _errorMessage;
  bool get _hasInactiveStatus => BookingStatus.isInactive(_status);
  bool get isGuest => FirebaseAuth.instance.currentUser?.isAnonymous ?? false;
  bool get hasActiveBooking =>
      !_hasInactiveStatus &&
      _jeepneyId != null &&
      _jeepneyId!.trim().isNotEmpty &&
      (_isSharing ||
          BookingStatus.isWaiting(_status) ||
          _isOnboardStatus(_status) ||
          _onBoard ||
          isTerminalBooked);
  bool get isOnboard =>
      _isOnboardStatus(_status) ||
      (!_hasInactiveStatus &&
          _jeepneyId != null &&
          _jeepneyId!.trim().isNotEmpty &&
          _onBoard) ||
      (!_hasInactiveStatus &&
          _jeepneyId != null &&
          (_isTerminalBookedValue(_source) ||
              _isTerminalBookedValue(_onBoardSource) ||
              _isTerminalBookedValue(_bookedBy)));
  bool get isDispatcherBooked =>
      _jeepneyId != null &&
      (_isDispatcherValue(_source) ||
          _isDispatcherValue(_onBoardSource) ||
          _isDispatcherValue(_bookedBy));
  bool get isTerminalBooked =>
      !_hasInactiveStatus &&
      _jeepneyId != null &&
      (_isTerminalBookedValue(_source) ||
          _isTerminalBookedValue(_onBoardSource) ||
          _isTerminalBookedValue(_bookedBy));

  bool get pendingOnboardNotification => _pendingOnboardNotification;

  void consumeOnboardNotification() {
    _pendingOnboardNotification = false;
    notifyListeners();
  }

  @visibleForTesting
  void detectOnboardTransition(String? status, bool onBoard) {
    final currentlyOnBoard = _isOnboardStatus(status) || onBoard;
    if (_previousOnBoardState != null &&
        _previousOnBoardState == false &&
        currentlyOnBoard) {
      _pendingOnboardNotification = true;
    }
    _previousOnBoardState = currentlyOnBoard;
  }

  bool canDropOffForJeepney(String jeepneyId) {
    final targetJeepneyId = jeepneyId.trim();
    final currentJeepneyId = _jeepneyId?.trim() ?? '';
    if (targetJeepneyId.isEmpty || currentJeepneyId != targetJeepneyId) {
      return false;
    }

    return !_hasInactiveStatus &&
        (_isOnboardStatus(_status) || _onBoard || isTerminalBooked);
  }

  bool isBookedForJeepney(String jeepneyId) {
    final targetJeepneyId = jeepneyId.trim();
    final currentJeepneyId = _jeepneyId?.trim() ?? '';
    return targetJeepneyId.isNotEmpty &&
        currentJeepneyId == targetJeepneyId &&
        hasActiveBooking;
  }

  bool isBookedOnAnotherJeepney(String jeepneyId) {
    final targetJeepneyId = jeepneyId.trim();
    final currentJeepneyId = _jeepneyId?.trim() ?? '';
    return targetJeepneyId.isNotEmpty &&
        currentJeepneyId.isNotEmpty &&
        currentJeepneyId != targetJeepneyId &&
        hasActiveBooking;
  }

  bool _isDispatcherValue(String? value) {
    return value?.toLowerCase().contains('dispatcher') == true;
  }

  bool _isTerminalBookedValue(String? value) {
    final text = value?.trim().toLowerCase() ?? '';
    return text.contains('terminal') ||
        text.contains('dispatcher') ||
        text == 'driver' ||
        text.contains('driver_terminal_booking');
  }

  bool _isOnboardStatus(String? value) {
    return BookingStatus.isOnboard(value);
  }

  void startWatching(String commuterId) {
    _locationSubscription?.cancel();
    _locationSubscription =
        PickupLocationService.watchPickupLocation(commuterId).listen(
          (doc) async {
            if (doc.exists) {
              final data = doc.data() as Map<String, dynamic>?;
              final status = data?['status']?.toString();
              if (data != null &&
                  (PickupLocationService.isPickupLocationActive(data) ||
                      _isOnboardStatus(status) ||
                      data['jeepneyId']?.toString().trim().isNotEmpty ==
                          true)) {
                final bool onboardCandidate =
                    _isOnboardStatus(status) || data['onBoard'] == true;

                if (onboardCandidate) {
                  final jeepneyId =
                      data['jeepneyId']?.toString().trim() ?? '';
                  if (jeepneyId.isNotEmpty) {
                    final stillOnTrip =
                        await _isJeepneyStillOnTrip(jeepneyId);
                    if (!stillOnTrip) {
                      debugPrint(
                        'PickupLocationProvider: Stale onboard doc — '
                        'jeepney $jeepneyId is no longer on trip. Clearing.',
                      );
                      _clearLocalLocation();
                      unawaited(
                        PickupLocationService.forceDeletePickupLocation(
                          commuterId,
                        ),
                      );
                      notifyListeners();
                      return;
                    }
                  }
                }

                final lat = data['lat'];
                final lng = data['lng'];
                _pickupLocation = lat is num && lng is num
                    ? LatLng(lat.toDouble(), lng.toDouble())
                    : null;
                _routeId = data['routeId'] as String?;
                _jeepneyId = data['jeepneyId'] as String?;
                _waitingCount = _intValue(
                  data['passengerCount'] ?? data['waitingCount'],
                );
                _destinationTerminal = data['destinationTerminal'] as String?;
                _status = status;
                _source = data['source']?.toString() ?? '';
                _onBoardSource = data['onBoardSource']?.toString() ?? '';
                _bookedBy = data['bookedBy']?.toString() ?? '';
                _onBoard = data['onBoard'] == true;
                _isSharing = data['isSharing'] == true;

                detectOnboardTransition(status, _onBoard);

                if (_isOnboardStatus(status) || _onBoard) {
                  _startWatchingJeepneyLocation(_jeepneyId);
                }

                if (_isSharing) {
                  _scheduleSharingExpiry(
                    PickupLocationService.pickupLocationExpiresAt(data),
                    commuterId,
                  );
                } else {
                  _sharingExpiryTimer?.cancel();
                  _sharingExpiryTimer = null;
                }
              } else {
                _clearLocalLocation();
                if (data != null && data['isSharing'] == true) {
                  unawaited(
                    PickupLocationService.expirePickupLocation(commuterId),
                  );
                }
              }
              notifyListeners();
            } else {
              final booking =
                  await PickupLocationService.getLatestOnboardBooking(
                    commuterId,
                  );
              if (booking != null) {
                final jeepneyId =
                    booking['jeepneyId']?.toString().trim() ?? '';
                if (jeepneyId.isNotEmpty) {
                  final stillOnTrip =
                      await _isJeepneyStillOnTrip(jeepneyId);
                  if (!stillOnTrip) {
                    _clearLocalLocation();
                    notifyListeners();
                    return;
                  }
                }
                _applyLocationData(booking);
                detectOnboardTransition(_status, _onBoard);
              } else {
                _clearLocalLocation();
              }
              notifyListeners();
            }
          },
          onError: (e) {
            debugPrint('Error watching pickup location: $e');
          },
        );
  }

  Future<bool> _isJeepneyStillOnTrip(String jeepneyId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('locations')
          .doc(jeepneyId)
          .get();
      if (!doc.exists) return false;
      final data = doc.data();
      if (data == null) return false;

      final isOnTrip = data['isOnTrip'] ?? data['onTrip'];
      if (isOnTrip == false) return false;

      final status = (data['status'] ?? data['tripStatus'] ?? '')
          .toString()
          .toLowerCase();
      if (status == 'completed' || status == 'done' || status == 'finished') {
        return false;
      }

      return true;
    } catch (e) {
      debugPrint('Error checking jeepney trip status: $e');
      return true;
    }
  }

  void stopWatching() {
    _locationSubscription?.cancel();
    _locationSubscription = null;
    _jeepneyLocationSubscription?.cancel();
    _jeepneyLocationSubscription = null;
    _sharingExpiryTimer?.cancel();
    _sharingExpiryTimer = null;
  }

  void _startWatchingJeepneyLocation(String? jeepneyId) {
    _jeepneyLocationSubscription?.cancel();
    _jeepneyLocationSubscription = null;

    if (jeepneyId == null || jeepneyId.trim().isEmpty) return;

    try {
      _jeepneyLocationSubscription = FirebaseFirestore.instance
          .collection('locations')
          .doc(jeepneyId.trim())
          .snapshots()
          .listen(
        (doc) {
          if (!doc.exists) return;
          final data = doc.data();
          if (data == null) return;

          if (!isOnboard) return;

          final isTripEnded = _isTripEndedByDriver(data);
          if (!isTripEnded) return;

          debugPrint(
            'PickupLocationProvider: Driver ended trip for $jeepneyId. '
            'Auto-dropping off.',
          );

          final commuterId = FirebaseAuth.instance.currentUser?.uid;
          if (commuterId == null || commuterId.isEmpty) return;

          final dropOffCount = passengerCount;
          offboardPickupLocation(commuterId, dropOffCount: dropOffCount);
        },
        onError: (e) {
          debugPrint('Error watching jeepney location for auto-dropoff: $e');
        },
      );
    } catch (e) {
      debugPrint('Failed to start watching jeepney location: $e');
    }
  }

  bool _isTripEndedByDriver(Map<String, dynamic> data) {
    final scheduledRaw = data['scheduledAt'] ?? data['departureAt'];
    DateTime? scheduledTime;
    if (scheduledRaw is DateTime) {
      scheduledTime = scheduledRaw;
    } else if (scheduledRaw is Timestamp) {
      scheduledTime = scheduledRaw.toDate();
    } else if (scheduledRaw != null) {
      scheduledTime = DateTime.tryParse(scheduledRaw.toString());
    }
    if (scheduledTime != null && DateTime.now().isBefore(scheduledTime)) {
      return false;
    }

    final isOnTrip = data['isOnTrip'] ?? data['onTrip'];
    if (isOnTrip == false) return true;

    final tripEndedAt = data['tripEndedAt'] ?? data['endedAt'];
    if (tripEndedAt != null) return true;

    final status = (data['status'] ?? data['tripStatus'] ?? '')
        .toString()
        .toLowerCase();
    if (status == 'completed' || status == 'done' || status == 'finished') {
      return true;
    }

    return false;
  }

  Future<bool> setPickupLocationFromGps({
    required String commuterId,
    required LatLng location,
    String? routeId,
    String? jeepneyId,
    int? waitingCount,
    String? destinationTerminal,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await PickupLocationService.savePickupLocation(
        commuterId: commuterId,
        location: location,
        routeId: routeId,
        jeepneyId: jeepneyId,
        waitingCount: waitingCount,
        destinationTerminal: destinationTerminal,
      );

      _pickupLocation = location;
      _routeId = routeId;
      _jeepneyId = jeepneyId;
      _waitingCount = waitingCount;
      _destinationTerminal = destinationTerminal;
      _status = BookingStatus.waiting;
      _isSharing = true;
      _isLoading = false;
      _scheduleSharingExpiry(
        DateTime.now().add(PickupLocationService.activeSharingDuration),
        commuterId,
      );
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Error saving pickup location: $e');
      _errorMessage = _friendlyPermissionError(e);
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> setPickupLocationManually({
    required String commuterId,
    required LatLng location,
    String? routeId,
    String? jeepneyId,
    int? waitingCount,
    String? destinationTerminal,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await PickupLocationService.savePickupLocation(
        commuterId: commuterId,
        location: location,
        routeId: routeId,
        jeepneyId: jeepneyId,
        waitingCount: waitingCount,
        destinationTerminal: destinationTerminal,
      );

      _pickupLocation = location;
      _routeId = routeId;
      _jeepneyId = jeepneyId;
      _waitingCount = waitingCount;
      _destinationTerminal = destinationTerminal;
      _status = BookingStatus.waiting;
      _isSharing = true;
      _isLoading = false;
      _scheduleSharingExpiry(
        DateTime.now().add(PickupLocationService.activeSharingDuration),
        commuterId,
      );
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Error saving manual pickup location: $e');
      _errorMessage = _friendlyPermissionError(e);
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> clearPickupLocation(String commuterId, {bool force = false}) async {
    _isLoading = true;
    notifyListeners();

    try {
      final cleared = await PickupLocationService.clearPickupLocation(
        commuterId,
        force: force,
      );
      if (cleared) _clearLocalLocation();
      _isLoading = false;
      notifyListeners();
      return cleared;
    } catch (e) {
      debugPrint('Error clearing pickup location: $e');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> cancelPickupLocation(String commuterId) async {
    _isLoading = true;
    notifyListeners();

    try {
      final cancelled = await PickupLocationService.cancelPickupLocation(
        commuterId,
      );
      if (cancelled) _clearLocalLocation();
      _isLoading = false;
      notifyListeners();
      return cancelled;
    } catch (e) {
      debugPrint('Error cancelling pickup location: $e');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<PickupDropOffResult?> offboardPickupLocation(
    String commuterId, {
    required int dropOffCount,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final result = await PickupLocationService.offboardPickupLocation(
        commuterId,
        dropOffCount: dropOffCount,
      );
      if (result == null) {
        _errorMessage = 'Could not record drop off. Please try again.';
      }
      if (result?.fullyOffboard == true) {
        _clearLocalLocation();
      } else if (result != null) {
        _waitingCount = result.remainingPassengerCount;
        _isSharing = false;
        _status = BookingStatus.onboard;
        _onBoard = true;
      }
      _isLoading = false;
      notifyListeners();
      return result;
    } catch (e) {
      debugPrint('Error offboarding pickup location: $e');
      _errorMessage = _friendlyPermissionError(e);
      _isLoading = false;
      notifyListeners();
      return null;
    }
  }

  void _scheduleSharingExpiry(DateTime? expiresAt, String commuterId) {
    _sharingExpiryTimer?.cancel();

    if (expiresAt == null) return;

    final delay = expiresAt.difference(DateTime.now());
    if (delay <= Duration.zero) {
      _clearLocalLocation();
      unawaited(PickupLocationService.expirePickupLocation(commuterId));
      return;
    }

    _sharingExpiryTimer = Timer(delay, () {
      _clearLocalLocation();
      notifyListeners();
      unawaited(PickupLocationService.expirePickupLocation(commuterId));
    });
  }

  void _clearLocalLocation() {
    _sharingExpiryTimer?.cancel();
    _sharingExpiryTimer = null;
    _pickupLocation = null;
    _routeId = null;
    _jeepneyId = null;
    _waitingCount = null;
    _destinationTerminal = null;
    _status = null;
    _source = null;
    _onBoardSource = null;
    _bookedBy = null;
    _onBoard = false;
    _isSharing = false;
    _previousOnBoardState = null;
    _pendingOnboardNotification = false;
  }

  void _applyLocationData(Map<String, dynamic> data) {
    final lat = data['lat'];
    final lng = data['lng'];
    _pickupLocation = lat is num && lng is num
        ? LatLng(lat.toDouble(), lng.toDouble())
        : null;
    _routeId = data['routeId'] as String?;
    _jeepneyId = data['jeepneyId'] as String?;
    _waitingCount = _intValue(data['passengerCount'] ?? data['waitingCount']);
    _destinationTerminal = data['destinationTerminal'] as String?;
    _status = data['status']?.toString();
    _source = data['source']?.toString() ?? '';
    _onBoardSource = data['onBoardSource']?.toString() ?? '';
    _bookedBy = data['bookedBy']?.toString() ?? '';
    _onBoard = data['onBoard'] == true;
    _isSharing = data['isSharing'] == true;
  }

  void updateWaitingCount(int count) {
    _waitingCount = count;
    notifyListeners();
  }

  int? _intValue(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  String _friendlyPermissionError(Object error) {
    final message = error.toString();

    if (message.contains('permission-denied') ||
        message.contains('missing-or-insufficient-permissions')) {
      if (isGuest) {
        return 'Please sign in to notify drivers. Guest users can only view jeepneys.';
      }
      return 'You don\'t have permission to perform this action. Please ensure you\'re signed in with the correct account.';
    }

    if (message.contains('booked by the dispatcher')) {
      return 'This passenger was booked by the dispatcher. Please ask the dispatcher to rebook them.';
    }
    if (message.contains('already boarded this jeepney')) {
      return 'You already boarded this jeep. You can book another pickup after this trip ends.';
    }
    if (message.contains('already on board this jeep')) {
      return 'You are already on board this jeep. You can notify the driver again after you drop off.';
    }
    if (message.contains('just dropped off from this jeep')) {
      return 'You just dropped off from this jeep. Please wait before notifying the same driver again.';
    }
    if (message.contains('Jeep is full')) {
      return 'Jeep is full. Please choose another jeep or wait for available seats.';
    }
    if (message.contains('No active onboard ride')) {
      return 'No active onboard ride was found for drop off.';
    }
    if (message.contains('already marked as dropped off')) {
      return 'This ride is already marked as dropped off.';
    }
    if (message.contains('active passenger list')) {
      return 'Could not match your ride with the driver passenger list. Please ask the driver to verify the passenger record.';
    }
    if (_isNetworkErrorMessage(message)) {
      return 'Network connection lost. Please reconnect to the internet and try again.';
    }
    return 'Could not complete this action. Please try again.';
  }

  bool _isNetworkErrorMessage(String message) {
    final lower = message.toLowerCase();
    return lower.contains('unavailable') ||
        lower.contains('unable to resolve host') ||
        lower.contains('unknownhost') ||
        lower.contains('network') ||
        lower.contains('firestore.googleapis.com') ||
        lower.contains('failed to resolve');
  }

  Future<bool> updateWaitingCountAndSave(String commuterId, int count) async {
    try {
      await PickupLocationService.updateWaitingCount(commuterId, count);
      _waitingCount = count;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Error updating waiting count: $e');
      return false;
    }
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    _jeepneyLocationSubscription?.cancel();
    _sharingExpiryTimer?.cancel();
    super.dispose();
  }
}
