import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../../core/constants/booking_status.dart';

class PickupLocationService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const Duration activeSharingDuration = Duration(minutes: 10);
  static const Duration recentSameJeepOffboardBlockDuration =
      Duration(minutes: 15);
  static const String activeSameRideMessage =
      'You are already on board this jeep. You can notify the driver again after you drop off.';
  static const String recentSameRideOffboardMessage =
      'You just dropped off from this jeep. Please wait before notifying the same driver again.';
  static const String jeepFullMessage =
      'Jeep is full. Please choose another jeep or wait for available seats.';

  static Future<void> savePickupLocation({
    required String commuterId,
    required LatLng location,
    String? routeId,
    String? jeepneyId,
    int? waitingCount,
    String? destinationTerminal,
  }) async {
    final cleanCommuterId = commuterId.trim();
    if (cleanCommuterId.isEmpty) {
      throw StateError('Commuter account is missing. Please log in again.');
    }

    final docRef = _firestore
        .collection('commuter_waiting_location')
        .doc(cleanCommuterId);
    final cleanJeepneyId = jeepneyId?.trim() ?? '';
    final requestedCount = _safePassengerCount(waitingCount);

    final bookingBlockMessage = cleanJeepneyId.isEmpty
        ? null
        : await _sameJeepBookingBlockMessage(
            cleanCommuterId,
            cleanJeepneyId,
          );
    if (bookingBlockMessage != null) {
      throw StateError(bookingBlockMessage);
    }

    await _firestore.runTransaction<void>((transaction) async {
      final existingDoc = await transaction.get(docRef);
      final existingData = existingDoc.data();

      DocumentSnapshot<Map<String, dynamic>>? locationDoc;
      DocumentSnapshot<Map<String, dynamic>>? jeepDoc;
      if (cleanJeepneyId.isNotEmpty) {
        locationDoc = await transaction.get(
          _firestore.collection('locations').doc(cleanJeepneyId),
        );
        jeepDoc = await transaction.get(
          _firestore.collection('jeeps').doc(cleanJeepneyId),
        );
      }
      final locationData = locationDoc?.data();
      final jeepData = jeepDoc?.data();

      if (existingData != null && _mustRebookThroughDispatcher(existingData)) {
        throw StateError(
          'This commuter was booked by the dispatcher. Please ask the dispatcher to rebook this passenger.',
        );
      }
      if (existingData != null &&
          _isActiveBookingForAnotherJeepney(existingData, jeepneyId)) {
        throw StateError(
          'You are already booked with another driver. Finish or cancel that booking before notifying a different driver.',
        );
      }
      if (existingData != null &&
          _isActiveOnboardForSameJeepney(
            existingData,
            jeepneyId,
            currentTripScheduleId:
                locationData?['tripScheduleId']?.toString().trim(),
          )) {
        throw StateError(activeSameRideMessage);
      }
      if (existingData != null &&
          _isRecentOffboardForSameJeepney(
            existingData,
            jeepneyId,
            currentTripScheduleId:
                locationData?['tripScheduleId']?.toString().trim(),
          )) {
        throw StateError(recentSameRideOffboardMessage);
      }

      _assertJeepHasAvailableSeats(
        locationData: locationData,
        jeepData: jeepData,
        requestedPassengerCount: requestedCount,
      );

      final expiresAt = DateTime.now().add(activeSharingDuration);

      transaction.set(docRef, {
        'commuterId': cleanCommuterId,
        'lat': location.latitude,
        'lng': location.longitude,
        'routeId': routeId,
        'jeepneyId': cleanJeepneyId.isEmpty ? jeepneyId : cleanJeepneyId,
        'waitingCount': requestedCount,
        'passengerCount': requestedCount,
        'destinationTerminal': destinationTerminal,
        'isSharing': true,
        'status': BookingStatus.waiting,
        'source': 'commuter',
        'onBoard': false,
        'onBoardSource': FieldValue.delete(),
        'bookedBy': FieldValue.delete(),
        'requireDispatcherRebook': false,
        'rebookOnlyBy': FieldValue.delete(),
        'tripScheduleId': FieldValue.delete(),
        'dropOffCount': FieldValue.delete(),
        'lastDropOffCount': FieldValue.delete(),
        'remainingPassengerCount': FieldValue.delete(),
        'driverDropOffAcknowledged': FieldValue.delete(),
        'driverDropOffAcknowledgedAt': FieldValue.delete(),
        'offboardAt': FieldValue.delete(),
        'lastDropOffAt': FieldValue.delete(),
        'autoDropOffDeductsPassengerCount': FieldValue.delete(),
        'manualPassengerCountRequired': FieldValue.delete(),
        'timestamp': FieldValue.serverTimestamp(),
        'expiresAt': Timestamp.fromDate(expiresAt),
      }, SetOptions(merge: true));
    });
  }

  static Future<bool> clearPickupLocation(
    String commuterId, {
    bool force = false,
  }) async {
    final docRef = _firestore
        .collection('commuter_waiting_location')
        .doc(commuterId);
    return _firestore.runTransaction<bool>((transaction) async {
      final doc = await transaction.get(docRef);
      final data = doc.data();
      if (!doc.exists || data == null) return true;
      if (!force && !_canClearAsRoadPickup(data)) return false;

      transaction.delete(docRef);
      return true;
    });
  }

  static Future<void> forceDeletePickupLocation(String commuterId) async {
    final cleanCommuterId = commuterId.trim();
    if (cleanCommuterId.isEmpty) return;
    try {
      await _firestore
          .collection('commuter_waiting_location')
          .doc(cleanCommuterId)
          .delete();
    } catch (e) {
      debugPrint('forceDeletePickupLocation error: $e');
    }
  }

  static Future<bool> cancelPickupLocation(String commuterId) async {
    final docRef = _firestore
        .collection('commuter_waiting_location')
        .doc(commuterId);
    return _firestore.runTransaction<bool>((transaction) async {
      final doc = await transaction.get(docRef);
      final data = doc.data();
      if (!doc.exists || data == null) return false;
      if (!_canClearAsRoadPickup(data)) return false;

      transaction.update(docRef, {
        'status': BookingStatus.cancelled,
        'isSharing': false,
        'cancelledAt': FieldValue.serverTimestamp(),
      });
      return true;
    });
  }

  static Future<PickupDropOffResult?> offboardPickupLocation(
    String commuterId, {
    required int dropOffCount,
  }) async {
    if (dropOffCount < 1) {
      throw StateError('Drop-off count must be at least 1.');
    }

    final docRef = _firestore
        .collection('commuter_waiting_location')
        .doc(commuterId);
    final fallbackBooking = await getLatestOnboardBooking(commuterId);
    final dropOffEventRef = _firestore.collection('dropoff_events').doc();

    return _firestore.runTransaction<PickupDropOffResult?>((transaction) async {
      final doc = await transaction.get(docRef);
      final docData = doc.data();
      final data = doc.exists && docData != null ? docData : fallbackBooking;
      if (data == null) {
        throw StateError('No active onboard ride was found for drop off.');
      }

      final status = data['status']?.toString().trim().toLowerCase() ?? '';
      if (BookingStatus.isOffboard(status)) {
        throw StateError('This ride is already marked as dropped off.');
      }

      final currentPassengerCount = _intValue(
        data['passengerCount'] ?? data['waitingCount'],
      );
      final safePassengerCount = currentPassengerCount < 1
          ? 1
          : currentPassengerCount;
      final selectedDropOffCount = dropOffCount > safePassengerCount
          ? safePassengerCount
          : dropOffCount;
      final remainingCount = safePassengerCount - selectedDropOffCount;
      final isFullyOffboard = remainingCount <= 0;
      final offboardAt = Timestamp.now();
      final tripScheduleId = data['tripScheduleId']?.toString().trim() ?? '';
      final jeepneyId = data['jeepneyId']?.toString().trim() ?? '';
      final targetBookingId = _targetBookingId(
        data,
        tripScheduleId,
        commuterId,
      );
      final targetPaymentMethod =
          data['paymentMethod']?.toString().trim() ?? '';
      Map<String, dynamic>? matchedPassenger;
      var shouldAutoDeductPassengerCount = true;

      DocumentReference<Map<String, dynamic>>? scheduleRef;
      DocumentSnapshot<Map<String, dynamic>>? scheduleDoc;
      Map<String, dynamic> scheduleData = <String, dynamic>{};
      List<dynamic> passengers = <dynamic>[];
      if (tripScheduleId.isNotEmpty) {
        scheduleRef = _firestore
            .collection('trip_schedules')
            .doc(tripScheduleId);
        scheduleDoc = await transaction.get(scheduleRef);
        if (scheduleDoc.exists) {
          scheduleData = scheduleDoc.data() ?? <String, dynamic>{};
          passengers =
              (scheduleData['bookedPassengers'] as List<dynamic>?)
                  ?.map(
                    (passenger) => passenger is Map
                        ? Map<String, dynamic>.from(passenger)
                        : passenger,
                  )
                  .toList() ??
              <dynamic>[];
          for (final passenger in passengers) {
            if (passenger is! Map<String, dynamic>) continue;
            if (_matchesDropOffPassenger(
              passenger,
              commuterId: commuterId,
              bookingId: targetBookingId,
              paymentMethod: targetPaymentMethod,
            )) {
              matchedPassenger = passenger;
              break;
            }
          }
        }
      }

      shouldAutoDeductPassengerCount = !_isTerminalCashBooking(
        data,
        matchedPassenger,
      );

      DocumentReference<Map<String, dynamic>>? locationRef;
      DocumentSnapshot<Map<String, dynamic>>? locationDoc;
      if (jeepneyId.isNotEmpty) {
        locationRef = _firestore.collection('locations').doc(jeepneyId);
        locationDoc = await transaction.get(locationRef);
      }

      if (shouldAutoDeductPassengerCount &&
          scheduleRef != null &&
          scheduleDoc?.exists == true &&
          matchedPassenger == null) {
        throw StateError(
          'Could not match this commuter in the active passenger list.',
        );
      }

      transaction.set(docRef, {
        'status': isFullyOffboard
            ? BookingStatus.offboard
            : BookingStatus.onboard,
        'isSharing': false,
        'passengerCount': isFullyOffboard ? 0 : remainingCount,
        'waitingCount': isFullyOffboard ? 0 : remainingCount,
        'dropOffCount': selectedDropOffCount,
        'lastDropOffCount': selectedDropOffCount,
        'remainingPassengerCount': remainingCount,
        'totalDropOffCount': FieldValue.increment(selectedDropOffCount),
        'autoDropOffDeductsPassengerCount': shouldAutoDeductPassengerCount,
        'manualPassengerCountRequired': !shouldAutoDeductPassengerCount,
        'driverDropOffAcknowledged': isFullyOffboard ? false : true,
        'driverDropOffAcknowledgedAt': isFullyOffboard
            ? FieldValue.delete()
            : offboardAt,
        'lastDropOffAt': offboardAt,
        if (isFullyOffboard) 'offboardAt': offboardAt,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (shouldAutoDeductPassengerCount &&
          scheduleRef != null &&
          scheduleDoc?.exists == true) {
        final currentCount = _intValue(scheduleData['passengerCount']);
        final nextCount = (currentCount - selectedDropOffCount)
            .clamp(0, 999999)
            .toInt();
        final updatedPassengers = passengers.map((passenger) {
          if (passenger is! Map<String, dynamic>) return passenger;
          if (!_matchesDropOffPassenger(
            passenger,
            commuterId: commuterId,
            bookingId: targetBookingId,
            paymentMethod: targetPaymentMethod,
          )) {
            return passenger;
          }

          return <String, dynamic>{
            ...passenger,
            'status': isFullyOffboard
                ? BookingStatus.offboard
                : BookingStatus.onboard,
            'onBoard': !isFullyOffboard,
            'passengerCount': isFullyOffboard ? 0 : remainingCount,
            'waitingCount': isFullyOffboard ? 0 : remainingCount,
            'lastDropOffCount': selectedDropOffCount,
            'remainingPassengerCount': remainingCount,
            'lastDropOffAt': offboardAt,
            if (isFullyOffboard) 'offboardAt': offboardAt,
          };
        }).toList();
        transaction.set(scheduleRef, {
          'passengerCount': nextCount,
          'bookedPassengers': updatedPassengers,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      if (shouldAutoDeductPassengerCount &&
          locationRef != null &&
          locationDoc?.exists == true) {
        final locationData = locationDoc!.data() ?? <String, dynamic>{};
        final currentCount = _intValue(
          locationData['passengerCount'] ??
              locationData['currentPassengerCount'],
        );
        final nextCount = (currentCount - selectedDropOffCount)
            .clamp(0, 999999)
            .toInt();
        transaction.set(locationRef, {
          'passengerCount': nextCount,
          'currentPassengerCount': nextCount,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      if (tripScheduleId.isNotEmpty) {
        final bookingId = targetBookingId.isNotEmpty
            ? targetBookingId
            : '${_safeFirestoreId(tripScheduleId)}_${_safeFirestoreId(commuterId)}';
        final bookingRef = _firestore.collection('bookings').doc(bookingId);
        transaction.set(bookingRef, {
          'rideStatus': isFullyOffboard
              ? BookingStatus.offboard
              : BookingStatus.onboard,
          'completedForCommuter': isFullyOffboard,
          if (shouldAutoDeductPassengerCount) ...{
            'status': isFullyOffboard
                ? BookingStatus.offboard
                : BookingStatus.onboard,
            'onBoard': !isFullyOffboard,
          },
          if (!shouldAutoDeductPassengerCount) ...{
            'cashDropOffRequested': true,
            'dropOffRequestedAt': offboardAt,
          },
          'passengerCount': isFullyOffboard ? 0 : remainingCount,
          'waitingCount': isFullyOffboard ? 0 : remainingCount,
          'dropOffCount': selectedDropOffCount,
          'lastDropOffCount': selectedDropOffCount,
          'remainingPassengerCount': remainingCount,
          'totalDropOffCount': FieldValue.increment(selectedDropOffCount),
          'lastDropOffAt': offboardAt,
          if (isFullyOffboard) 'offboardAt': offboardAt,
          'autoDropOffDeductsPassengerCount': shouldAutoDeductPassengerCount,
          'manualPassengerCountRequired': !shouldAutoDeductPassengerCount,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        final historyUpdate = {
          'status': isFullyOffboard
              ? BookingStatus.offboard
              : BookingStatus.onboard,
          'rideStatus': isFullyOffboard
              ? BookingStatus.offboard
              : BookingStatus.onboard,
          'completedForCommuter': isFullyOffboard,
          'onBoard': !isFullyOffboard,
          'passengerCount': isFullyOffboard ? 0 : remainingCount,
          'waitingCount': isFullyOffboard ? 0 : remainingCount,
          'dropOffCount': selectedDropOffCount,
          'lastDropOffCount': selectedDropOffCount,
          'remainingPassengerCount': remainingCount,
          'totalDropOffCount': FieldValue.increment(selectedDropOffCount),
          'lastDropOffAt': offboardAt,
          if (isFullyOffboard) 'offboardAt': offboardAt,
          'updatedAt': FieldValue.serverTimestamp(),
        };
        transaction.set(
          _firestore.collection('road_pickup_history').doc(bookingId),
          historyUpdate,
          SetOptions(merge: true),
        );
        transaction.set(
          _firestore.collection('commuter_pickup_history').doc(bookingId),
          historyUpdate,
          SetOptions(merge: true),
        );
        transaction.set(
          _firestore.collection('driver_pickup_history').doc(bookingId),
          historyUpdate,
          SetOptions(merge: true),
        );
      }

      transaction.set(dropOffEventRef, {
        'commuterId': commuterId,
        'jeepneyId': jeepneyId,
        'tripScheduleId': tripScheduleId,
        'dropOffCount': selectedDropOffCount,
        'passengerCountBefore': safePassengerCount,
        'remainingPassengerCount': remainingCount,
        'fullyOffboard': isFullyOffboard,
        'source': 'commuter',
        'createdAt': FieldValue.serverTimestamp(),
      });

      return PickupDropOffResult(
        dropOffCount: selectedDropOffCount,
        remainingPassengerCount: remainingCount,
        fullyOffboard: isFullyOffboard,
      );
    });
  }

  static Future<bool> expirePickupLocation(String commuterId) async {
    final docRef = _firestore
        .collection('commuter_waiting_location')
        .doc(commuterId);
    return _firestore.runTransaction<bool>((transaction) async {
      final doc = await transaction.get(docRef);
      final data = doc.data();
      if (!doc.exists || data == null) return false;
      if (!_canClearAsRoadPickup(data)) return false;

      transaction.update(docRef, {
        'status': BookingStatus.expired,
        'isSharing': false,
        'expiredAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return true;
    });
  }

  static Future<void> updateWaitingCount(String commuterId, int count) async {
    final docRef = _firestore
        .collection('commuter_waiting_location')
        .doc(commuterId);
    await docRef.update({'waitingCount': count});
  }

  static Stream<DocumentSnapshot> watchPickupLocation(String commuterId) {
    return _firestore
        .collection('commuter_waiting_location')
        .doc(commuterId)
        .snapshots();
  }

  static Future<Map<String, dynamic>?> getLatestOnboardBooking(
    String commuterId,
  ) async {
    final cleanCommuterId = commuterId.trim();
    if (cleanCommuterId.isEmpty) return null;

    final snapshot = await _firestore
        .collection('bookings')
        .where('commuterId', isEqualTo: cleanCommuterId)
        .limit(20)
        .get();

    final bookings = snapshot.docs
        .map((doc) => {'id': doc.id, ...doc.data()})
        .where((data) => BookingStatus.isOnboard(data['status']?.toString()))
        .toList();
    if (bookings.isEmpty) return null;

    bookings.sort((a, b) {
      final aTime = _toDateTime(a['onBoardAt']) ?? _toDateTime(a['bookedAt']);
      final bTime = _toDateTime(b['onBoardAt']) ?? _toDateTime(b['bookedAt']);
      if (aTime == null && bTime == null) return 0;
      if (aTime == null) return 1;
      if (bTime == null) return -1;
      return bTime.compareTo(aTime);
    });

    return bookings.first;
  }

  static bool isPickupLocationActive(
    Map<String, dynamic> data, {
    DateTime? now,
  }) {
    if (data['isSharing'] != true) return false;

    final currentTime = now ?? DateTime.now();
    final expiresAt = pickupLocationExpiresAt(data);
    if (expiresAt != null) {
      return expiresAt.isAfter(currentTime);
    }

    final timestamp = _toDateTime(data['timestamp']);
    if (timestamp == null) return false;

    return currentTime.difference(timestamp) <= activeSharingDuration;
  }

  static bool _canClearAsRoadPickup(Map<String, dynamic> data) {
    final status = data['status']?.toString().trim().toLowerCase() ?? '';
    if (BookingStatus.isOnboard(status) || BookingStatus.isOffboard(status)) {
      return false;
    }

    final source = data['source']?.toString().trim().toLowerCase() ?? '';
    final onBoardSource =
        data['onBoardSource']?.toString().trim().toLowerCase() ?? '';
    final bookedBy = data['bookedBy']?.toString().trim().toLowerCase() ?? '';
    final isTerminalBooked =
        source.contains('terminal') ||
        source.contains('dispatcher') ||
        source.contains('driver') ||
        onBoardSource.contains('dispatcher') ||
        onBoardSource.contains('driver') ||
        bookedBy.contains('dispatcher') ||
        bookedBy.contains('driver');

    return !isTerminalBooked;
  }

  static DateTime? pickupLocationExpiresAt(Map<String, dynamic> data) {
    final explicitExpiry = _toDateTime(data['expiresAt']);
    if (explicitExpiry != null) return explicitExpiry;

    final timestamp = _toDateTime(data['timestamp']);
    return timestamp?.add(activeSharingDuration);
  }

  static Future<LatLng?> getPickupLocation(String commuterId) async {
    final doc = await _firestore
        .collection('commuter_waiting_location')
        .doc(commuterId)
        .get();

    final data = doc.data();
    if (doc.exists && data != null && isPickupLocationActive(data)) {
      return LatLng(
        (data['lat'] as num).toDouble(),
        (data['lng'] as num).toDouble(),
      );
    }
    return null;
  }

  static Stream<QuerySnapshot> watchAllActivePickupLocations() {
    return _firestore.collection('commuter_waiting_location').snapshots();
  }

  static Future<List<PickupLocationData>> getAllActivePickupLocations() async {
    final snapshot = await _firestore
        .collection('commuter_waiting_location')
        .get();

    return snapshot.docs
        .where((doc) {
          return isPickupLocationActive(doc.data());
        })
        .map((doc) {
          final data = doc.data();
          return PickupLocationData(
            commuterId: doc.id,
            location: LatLng(
              (data['lat'] as num).toDouble(),
              (data['lng'] as num).toDouble(),
            ),
            routeId: data['routeId'] as String?,
            jeepneyId: data['jeepneyId'] as String?,
            waitingCount: (data['waitingCount'] as num?)?.toInt() ?? 1,
            timestamp: data['timestamp'] as Timestamp?,
          );
        })
        .toList();
  }

  static DateTime? _toDateTime(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  static int _intValue(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static int _safePassengerCount(int? count) {
    final value = count ?? 1;
    return value < 1 ? 1 : value;
  }

  static int _firstPositiveInt(Map<String, dynamic>? data, List<String> keys) {
    if (data == null) return 0;
    for (final key in keys) {
      final value = _intValue(data[key]);
      if (value > 0) return value;
    }
    return 0;
  }

  static int _firstNonNegativeInt(
    Map<String, dynamic>? data,
    List<String> keys,
  ) {
    if (data == null) return 0;
    for (final key in keys) {
      final value = data[key];
      if (value == null) continue;
      final parsed = _intValue(value);
      if (parsed >= 0) return parsed;
    }
    return 0;
  }

  static void _assertJeepHasAvailableSeats({
    required Map<String, dynamic>? locationData,
    required Map<String, dynamic>? jeepData,
    required int requestedPassengerCount,
  }) {
    final maxCapacity = _firstPositiveInt(locationData, const [
      'maxCapacity',
      'capacity',
      'seatingCapacity',
      'maxPassengers',
    ]);
    final staticCapacity = _firstPositiveInt(jeepData, const [
      'maxCapacity',
      'capacity',
      'seatingCapacity',
      'maxPassengers',
    ]);
    final effectiveCapacity = maxCapacity > 0 ? maxCapacity : staticCapacity;
    if (effectiveCapacity <= 0) return;

    final currentPassengerCount = _firstNonNegativeInt(locationData, const [
      'passengerCount',
      'currentPassengerCount',
      'currentPassengers',
      'passengers',
    ]);
    if (currentPassengerCount + requestedPassengerCount > effectiveCapacity) {
      throw StateError(jeepFullMessage);
    }
  }

  static bool _isActiveOnboardForSameJeepney(
    Map<String, dynamic> data,
    String? jeepneyId, {
    String? currentTripScheduleId,
  }) {
    final requestedJeepneyId = jeepneyId?.trim() ?? '';
    if (requestedJeepneyId.isEmpty) return false;

    final existingJeepneyId = data['jeepneyId']?.toString().trim() ?? '';
    if (existingJeepneyId != requestedJeepneyId) return false;

    final status = data['status']?.toString().trim().toLowerCase() ?? '';
    if (!BookingStatus.isOnboard(status)) return false;
    if (data['completedForCommuter'] == true || data['onBoard'] == false) {
      return false;
    }

    final existingTripScheduleId =
        data['tripScheduleId']?.toString().trim() ?? '';
    final activeTripScheduleId = currentTripScheduleId?.trim() ?? '';
    if (existingTripScheduleId.isEmpty || activeTripScheduleId.isEmpty) {
      return true;
    }

    return existingTripScheduleId == activeTripScheduleId;
  }

  static bool _isRecentOffboardForSameJeepney(
    Map<String, dynamic> data,
    String? jeepneyId, {
    String? currentTripScheduleId,
  }) {
    final requestedJeepneyId = jeepneyId?.trim() ?? '';
    if (requestedJeepneyId.isEmpty) return false;

    final existingJeepneyId = data['jeepneyId']?.toString().trim() ?? '';
    if (existingJeepneyId != requestedJeepneyId) return false;

    final status = data['status']?.toString().trim().toLowerCase() ?? '';
    if (!BookingStatus.isOffboard(status)) return false;

    final existingTripScheduleId =
        data['tripScheduleId']?.toString().trim() ?? '';
    final activeTripScheduleId = currentTripScheduleId?.trim() ?? '';
    if (existingTripScheduleId.isNotEmpty &&
        activeTripScheduleId.isNotEmpty &&
        existingTripScheduleId == activeTripScheduleId) {
      return true;
    }

    final offboardAt =
        _toDateTime(data['offboardAt']) ?? _toDateTime(data['lastDropOffAt']);
    if (offboardAt == null) return true;

    return DateTime.now().isBefore(
      offboardAt.add(recentSameJeepOffboardBlockDuration),
    );
  }

  static bool _isActiveBookingForAnotherJeepney(
    Map<String, dynamic> data,
    String? jeepneyId,
  ) {
    final requestedJeepneyId = jeepneyId?.trim() ?? '';
    if (requestedJeepneyId.isEmpty) return false;

    final existingJeepneyId = data['jeepneyId']?.toString().trim() ?? '';
    if (existingJeepneyId.isEmpty || existingJeepneyId == requestedJeepneyId) {
      return false;
    }

    final status = data['status']?.toString().trim().toLowerCase() ?? '';
    if (BookingStatus.isInactive(status)) return false;

    final isSharing = data['isSharing'] == true && isPickupLocationActive(data);
    final source = data['source']?.toString().trim().toLowerCase() ?? '';
    final onBoardSource =
        data['onBoardSource']?.toString().trim().toLowerCase() ?? '';
    final bookedBy = data['bookedBy']?.toString().trim().toLowerCase() ?? '';
    final terminalBooked =
        source.contains('terminal') ||
        source.contains('dispatcher') ||
        source.contains('driver') ||
        onBoardSource.contains('dispatcher') ||
        onBoardSource.contains('driver') ||
        bookedBy.contains('dispatcher') ||
        bookedBy.contains('driver');

    return isSharing ||
        BookingStatus.isWaiting(status) ||
        BookingStatus.isOnboard(status) ||
        terminalBooked;
  }

  static Future<String?> _sameJeepBookingBlockMessage(
    String commuterId,
    String jeepneyId,
  ) async {
    try {
      final snapshot = await _firestore
          .collection('bookings')
          .where('commuterId', isEqualTo: commuterId)
          .limit(20)
          .get();

      if (snapshot.docs.isEmpty) return null;

      final requestedJeepneyId = jeepneyId.trim();
      for (final doc in snapshot.docs) {
        final booking = doc.data();
        final bookingJeepneyId =
            booking['jeepneyId']?.toString().trim() ?? '';
        if (bookingJeepneyId != requestedJeepneyId) continue;

        final status = booking['status']?.toString();
        if (BookingStatus.isOnboard(status)) {
          if (booking['completedForCommuter'] == true ||
              booking['onBoard'] == false) {
            continue;
          }

          final rideStatus = booking['rideStatus']?.toString();
          if (!BookingStatus.isInactive(rideStatus)) {
            return activeSameRideMessage;
          }
          continue;
        }

        if (!BookingStatus.isOffboard(status)) continue;

        final offboardAt =
            _toDateTime(booking['offboardAt']) ??
            _toDateTime(booking['lastDropOffAt']);
        if (offboardAt == null) return recentSameRideOffboardMessage;

        if (DateTime.now().isBefore(
          offboardAt.add(recentSameJeepOffboardBlockDuration),
        )) {
          return recentSameRideOffboardMessage;
        }
      }

      return null;
    } catch (e) {
      throw StateError(
        'Could not verify your current ride status. Please try again.',
      );
    }
  }

  static bool _mustRebookThroughDispatcher(Map<String, dynamic> data) {
    if (data['requireDispatcherRebook'] == true) return true;

    final rebookOnlyBy =
        data['rebookOnlyBy']?.toString().trim().toLowerCase() ?? '';
    if (rebookOnlyBy == 'dispatcher') return true;

    final source = data['source']?.toString().trim().toLowerCase() ?? '';
    final onBoardSource =
        data['onBoardSource']?.toString().trim().toLowerCase() ?? '';
    final bookedBy = data['bookedBy']?.toString().trim().toLowerCase() ?? '';
    final status = data['status']?.toString().trim().toLowerCase() ?? '';
    final isDispatcherBooking =
        source.contains('dispatcher') ||
        onBoardSource.contains('dispatcher') ||
        bookedBy.contains('dispatcher');
    final hasBoardingRecord =
        BookingStatus.isOnboard(status) || BookingStatus.isOffboard(status);

    return isDispatcherBooking && hasBoardingRecord;
  }

  static bool _isTerminalCashBooking(
    Map<String, dynamic> waitingData,
    Map<String, dynamic>? passengerData,
  ) {
    String read(String key) {
      final passengerValue = passengerData?[key]?.toString().trim() ?? '';
      if (passengerValue.isNotEmpty) return passengerValue;
      return waitingData[key]?.toString().trim() ?? '';
    }

    final paymentMethod = read('paymentMethod').toLowerCase();
    final anonymousCash =
        waitingData['anonymousCash'] == true ||
        passengerData?['anonymousCash'] == true;
    if (paymentMethod != 'cash' && !anonymousCash) return false;

    final source = read('source').toLowerCase();
    final onBoardSource = read('onBoardSource').toLowerCase();
    final bookedBy = read('bookedBy').toLowerCase();

    return source.contains('terminal') ||
        source.contains('dispatcher') ||
        source.contains('driver') ||
        onBoardSource.contains('dispatcher') ||
        onBoardSource.contains('driver') ||
        bookedBy.contains('dispatcher') ||
        bookedBy.contains('driver');
  }

  static String _targetBookingId(
    Map<String, dynamic> data,
    String tripScheduleId,
    String commuterId,
  ) {
    final explicitId = data['id']?.toString().trim() ?? '';
    if (explicitId.isNotEmpty) return explicitId;

    final bookingId = data['bookingId']?.toString().trim() ?? '';
    if (bookingId.isNotEmpty) return bookingId;

    if (tripScheduleId.isEmpty || commuterId.trim().isEmpty) return '';
    return '${_safeFirestoreId(tripScheduleId)}_${_safeFirestoreId(commuterId)}';
  }

  static bool _matchesDropOffPassenger(
    Map<String, dynamic> passenger, {
    required String commuterId,
    required String bookingId,
    required String paymentMethod,
  }) {
    final passengerId = passenger['id']?.toString().trim() ?? '';
    final passengerBookingId = passenger['bookingId']?.toString().trim() ?? '';
    if (bookingId.isNotEmpty) {
      final hasPassengerBookingIdentity =
          passengerId.isNotEmpty || passengerBookingId.isNotEmpty;
      if (hasPassengerBookingIdentity) {
        return passengerId == bookingId || passengerBookingId == bookingId;
      }
    }

    final passengerCommuterId =
        passenger['commuterId']?.toString().trim() ?? '';
    if (passengerCommuterId != commuterId.trim()) return false;

    final targetPayment = paymentMethod.trim().toLowerCase();
    if (targetPayment.isEmpty) return true;

    final passengerPayment =
        passenger['paymentMethod']?.toString().trim().toLowerCase() ?? '';
    if (passengerPayment.isEmpty) return true;

    return passengerPayment == targetPayment;
  }

  static String _safeFirestoreId(String value) {
    final sanitized = value.trim().replaceAll(RegExp(r'[/#?\[\]]'), '_');
    return sanitized.isEmpty ? 'unknown' : sanitized;
  }
}

class PickupLocationData {
  final String commuterId;
  final LatLng location;
  final String? routeId;
  final String? jeepneyId;
  final int waitingCount;
  final Timestamp? timestamp;

  PickupLocationData({
    required this.commuterId,
    required this.location,
    this.routeId,
    this.jeepneyId,
    this.waitingCount = 1,
    this.timestamp,
  });
}

class PickupDropOffResult {
  final int dropOffCount;
  final int remainingPassengerCount;
  final bool fullyOffboard;

  const PickupDropOffResult({
    required this.dropOffCount,
    required this.remainingPassengerCount,
    required this.fullyOffboard,
  });
}
