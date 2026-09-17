import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class AnalyticsTrackingService {
  static const String _appSessionsCollection = 'app_sessions';
  static const String _tripHistoryCollection = 'trip_history';
  static const Duration _staleSessionThreshold = Duration(minutes: 5);

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  static String? _activeTripId;

  static Future<void> startOrResumeDriverSession() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      final driverId = await _resolveDriverId();
      if (driverId == null || driverId.isEmpty) return;

      final sessionRef =
          _firestore.collection(_appSessionsCollection).doc('driver_$driverId');
      final sessionSnapshot = await sessionRef.get();
      final sessionData = sessionSnapshot.data();
      final lastSeenAt = _toDateTime(sessionData?['lastSeenAt']);
      final shouldRestart = !sessionSnapshot.exists ||
          sessionData?['isActive'] != true ||
          lastSeenAt == null ||
          DateTime.now().difference(lastSeenAt) > _staleSessionThreshold;

      final payload = <String, dynamic>{
        'role': 'driver',
        'userId': driverId,
        'authUid': user.uid,
        'email': user.email ?? '',
        'displayName':
            user.displayName?.trim().isNotEmpty == true ? user.displayName : '',
        'isActive': true,
        'lastSeenAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (shouldRestart) {
        payload['startedAt'] = FieldValue.serverTimestamp();
        payload['endedAt'] = FieldValue.delete();
      }

      await sessionRef.set(payload, SetOptions(merge: true));
    } catch (error) {
      debugPrint('Failed to start driver app session: $error');
    }
  }

  static Future<void> heartbeatDriverSession() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      final driverId = await _resolveDriverId();
      if (driverId == null || driverId.isEmpty) return;

      await _firestore
          .collection(_appSessionsCollection)
          .doc('driver_$driverId')
          .set({
        'role': 'driver',
        'userId': driverId,
        'authUid': user.uid,
        'email': user.email ?? '',
        'isActive': true,
        'lastSeenAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (error) {
      debugPrint('Failed to refresh driver app session: $error');
    }
  }

  static Future<void> stopDriverSession() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      final driverId = await _resolveDriverId();
      if (driverId == null || driverId.isEmpty) return;

      await _firestore
          .collection(_appSessionsCollection)
          .doc('driver_$driverId')
          .set({
        'role': 'driver',
        'userId': driverId,
        'authUid': user.uid,
        'email': user.email ?? '',
        'isActive': false,
        'lastSeenAt': FieldValue.serverTimestamp(),
        'endedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (error) {
      debugPrint('Failed to stop driver app session: $error');
    }
  }

  static Future<void> startTrip({
    required String jeepneyId,
    String? routeId,
    String? routeName,
    String? originTerminal,
    String? destinationTerminal,
    String? tripScheduleId,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null || jeepneyId.trim().isEmpty) return;

      final driverId = await _resolveDriverId();
      if (driverId == null || driverId.isEmpty) return;

      final activeTripRef = await _resolveActiveTripRef(
        driverId: driverId,
        jeepneyId: jeepneyId,
      );

      final payload = <String, dynamic>{
        'driverId': driverId,
        'authUid': user.uid,
        'jeepneyId': jeepneyId.trim(),
        'routeId': (routeId ?? '').trim(),
        'routeName': (routeName ?? '').trim(),
        'originTerminal': (originTerminal ?? '').trim(),
        'destinationTerminal': (destinationTerminal ?? '').trim(),
        'tripScheduleId': (tripScheduleId ?? '').trim(),
        'status': 'active',
        'dayKey': _buildDayKey(DateTime.now()),
        'startedAt': FieldValue.serverTimestamp(),
        'lastUpdatedAt': FieldValue.serverTimestamp(),
        'endedAt': FieldValue.delete(),
      };

      await activeTripRef.set(payload, SetOptions(merge: true));
      _activeTripId = activeTripRef.id;
    } catch (error) {
      debugPrint('Failed to start trip history log: $error');
    }
  }

  static Future<void> endTrip({
    String? jeepneyId,
    String? tripScheduleId,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      final driverId = await _resolveDriverId();
      if (driverId == null || driverId.isEmpty) return;

      final tripRef = await _resolveActiveTripRef(
        driverId: driverId,
        jeepneyId: jeepneyId,
      );
      final snapshot = await tripRef.get();
      if (!snapshot.exists) {
        _activeTripId = null;
        return;
      }

      final startedAt = _toDateTime(snapshot.data()?['startedAt']);
      final resolvedTripScheduleId = (tripScheduleId ?? '').trim().isNotEmpty
          ? tripScheduleId!.trim()
          : (snapshot.data()?['tripScheduleId']?.toString().trim() ?? '');
      final durationMinutes = startedAt == null
          ? null
          : DateTime.now().difference(startedAt).inMinutes;
      final paymentTotals = await _tripPaymentTotals(
        driverId: driverId,
        tripScheduleId: resolvedTripScheduleId,
        jeepneyId: (jeepneyId ?? snapshot.data()?['jeepneyId'] ?? '')
            .toString()
            .trim(),
        startedAt: startedAt,
      );

      final payload = <String, dynamic>{
        'status': 'completed',
        if (resolvedTripScheduleId.isNotEmpty)
          'tripScheduleId': resolvedTripScheduleId,
        'passengerCount': paymentTotals.passengerCount,
        'totalPaymentCollected': paymentTotals.totalCollected,
        'cashPaymentCollected': paymentTotals.cashCollected,
        'rfidPaymentCollected': paymentTotals.rfidCollected,
        'fareTransactionCount': paymentTotals.transactionCount,
        'endedAt': FieldValue.serverTimestamp(),
        'lastUpdatedAt': FieldValue.serverTimestamp(),
      };

      if (durationMinutes != null && durationMinutes >= 0) {
        payload['durationMinutes'] = durationMinutes;
      }

      await tripRef.update(payload);
      _activeTripId = null;
    } catch (error) {
      debugPrint('Failed to close trip history log: $error');
    }
  }

  static Future<void> cancelTrip({
    String? jeepneyId,
    String? reason,
    String? tripScheduleId,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      final driverId = await _resolveDriverId();
      if (driverId == null || driverId.isEmpty) return;

      final tripRef = await _resolveActiveTripRef(
        driverId: driverId,
        jeepneyId: jeepneyId,
      );
      final snapshot = await tripRef.get();
      if (!snapshot.exists) {
        _activeTripId = null;
        return;
      }

      final startedAt = _toDateTime(snapshot.data()?['startedAt']);
      final durationMinutes = startedAt == null
          ? null
          : DateTime.now().difference(startedAt).inMinutes;

      final payload = <String, dynamic>{
        'status': 'cancelled',
        'historyStatus': 'cancelled',
        'cancelledAt': FieldValue.serverTimestamp(),
        'endedAt': FieldValue.serverTimestamp(),
        'lastUpdatedAt': FieldValue.serverTimestamp(),
        'cancelledBy': 'driver',
        if ((reason ?? '').trim().isNotEmpty) 'cancelReason': reason!.trim(),
        if ((tripScheduleId ?? '').trim().isNotEmpty)
          'tripScheduleId': tripScheduleId!.trim(),
      };

      if (durationMinutes != null && durationMinutes >= 0) {
        payload['durationMinutes'] = durationMinutes;
      }

      await tripRef.update(payload);
      _activeTripId = null;
    } catch (error) {
      debugPrint('Failed to cancel trip history log: $error');
    }
  }

  static Future<_TripPaymentTotals> _tripPaymentTotals({
    required String driverId,
    required String tripScheduleId,
    required String jeepneyId,
    DateTime? startedAt,
  }) async {
    final transactions = <String, Map<String, dynamic>>{};

    if (tripScheduleId.isNotEmpty) {
      final bySchedule = await _firestore
          .collection('fare_transactions')
          .where('tripScheduleId', isEqualTo: tripScheduleId)
          .get();
      for (final doc in bySchedule.docs) {
        transactions[doc.id] = doc.data();
      }
    }

    if (transactions.isEmpty && driverId.isNotEmpty && startedAt != null) {
      final byDriver = await _firestore
          .collection('fare_transactions')
          .where('driverId', isEqualTo: driverId)
          .where('createdAt',
              isGreaterThanOrEqualTo: Timestamp.fromDate(startedAt))
          .get();
      for (final doc in byDriver.docs) {
        transactions[doc.id] = doc.data();
      }
    }

    if (transactions.isEmpty && jeepneyId.isNotEmpty && startedAt != null) {
      final byJeepney = await _firestore
          .collection('fare_transactions')
          .where('jeepneyId', isEqualTo: jeepneyId)
          .where('createdAt',
              isGreaterThanOrEqualTo: Timestamp.fromDate(startedAt))
          .get();
      for (final doc in byJeepney.docs) {
        transactions[doc.id] = doc.data();
      }
    }

    var passengerCount = 0;
    var totalCollected = 0.0;
    var cashCollected = 0.0;
    var rfidCollected = 0.0;

    for (final tx in transactions.values) {
      if (tx['type']?.toString() != 'fare') continue;
      final amount = _toDouble(tx['amount'] ?? tx['fare']);
      final units = _toInt(tx['passengerCount'] ?? tx['waitingCount']) ?? 1;
      final paymentMethod = tx['paymentMethod']?.toString().toLowerCase() ?? '';
      passengerCount += units < 1 ? 1 : units;
      totalCollected += amount;
      if (paymentMethod == 'rfid') {
        rfidCollected += amount;
      } else {
        cashCollected += amount;
      }
    }

    final schedulePassengerCount =
        await _tripSchedulePassengerCount(tripScheduleId);

    return _TripPaymentTotals(
      passengerCount:
          schedulePassengerCount > 0 ? schedulePassengerCount : passengerCount,
      totalCollected: totalCollected,
      cashCollected: cashCollected,
      rfidCollected: rfidCollected,
      transactionCount: transactions.length,
    );
  }

  static Future<int> _tripSchedulePassengerCount(String tripScheduleId) async {
    if (tripScheduleId.trim().isEmpty) return 0;

    try {
      final scheduleSnapshot = await _firestore
          .collection('trip_schedules')
          .doc(tripScheduleId.trim())
          .get();
      final passengers = scheduleSnapshot.data()?['bookedPassengers'];
      if (passengers is! List) return 0;

      final seen = <String>{};
      var total = 0;

      for (final passenger in passengers) {
        if (passenger is! Map) continue;
        final data = Map<String, dynamic>.from(passenger);
        final status = data['status']?.toString().trim().toLowerCase() ?? '';
        if (_isExcludedPassengerStatus(status)) continue;

        final key = _firstNonEmpty([
          data['id'],
          data['bookingId'],
          data['pickupId'],
          data['commuterId'],
        ]);
        if (key.isNotEmpty && !seen.add(key)) continue;

        final units =
            _toInt(data['passengerCount'] ?? data['waitingCount']) ?? 1;
        total += units < 1 ? 1 : units;
      }

      return total;
    } catch (error) {
      debugPrint('Failed to count trip schedule passengers: $error');
      return 0;
    }
  }

  static bool _isExcludedPassengerStatus(String status) {
    return status == 'cancelled' ||
        status == 'canceled' ||
        status == 'rejected' ||
        status == 'declined' ||
        status == 'no_show';
  }

  static Future<DocumentReference<Map<String, dynamic>>> _resolveActiveTripRef({
    required String driverId,
    String? jeepneyId,
  }) async {
    if (_activeTripId != null && _activeTripId!.isNotEmpty) {
      return _firestore.collection(_tripHistoryCollection).doc(_activeTripId);
    }

    Query<Map<String, dynamic>> query = _firestore
        .collection(_tripHistoryCollection)
        .where('driverId', isEqualTo: driverId)
        .where('status', isEqualTo: 'active')
        .limit(1);

    if (jeepneyId != null && jeepneyId.trim().isNotEmpty) {
      query = query.where('jeepneyId', isEqualTo: jeepneyId.trim());
    }

    final snapshot = await query.get();
    if (snapshot.docs.isNotEmpty) {
      _activeTripId = snapshot.docs.first.id;
      return snapshot.docs.first.reference;
    }

    final newRef = _firestore.collection(_tripHistoryCollection).doc();
    _activeTripId = newRef.id;
    return newRef;
  }

  static Future<String?> _resolveDriverId() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return null;

      final directSnapshot =
          await _firestore.collection('driver').doc(user.uid).get();
      if (directSnapshot.exists) {
        return directSnapshot.id;
      }

      final uidQuery = await _firestore
          .collection('driver')
          .where('uid', isEqualTo: user.uid)
          .limit(1)
          .get();
      if (uidQuery.docs.isNotEmpty) {
        return uidQuery.docs.first.id;
      }

      final email = user.email?.trim().toLowerCase();
      if (email != null && email.isNotEmpty) {
        final emailQuery = await _firestore
            .collection('driver')
            .where('email', isEqualTo: email)
            .limit(1)
            .get();
        if (emailQuery.docs.isNotEmpty) {
          return emailQuery.docs.first.id;
        }
      }
    } catch (error) {
      debugPrint('Failed to resolve driver id for analytics: $error');
    }

    return null;
  }

  static DateTime? _toDateTime(Object? value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);

    if (value is Map) {
      final seconds = value['seconds'] ?? value['_seconds'];
      final nanoseconds = value['nanoseconds'] ?? value['_nanoseconds'] ?? 0;
      if (seconds is num) {
        return DateTime.fromMillisecondsSinceEpoch(
          seconds.toInt() * 1000 + ((nanoseconds as num) / 1000000).floor(),
        );
      }
    }

    return null;
  }

  static String _buildDayKey(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }

  static double _toDouble(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  static int? _toInt(Object? value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  static String _firstNonEmpty(List<dynamic> values) {
    for (final value in values) {
      final text = value?.toString().trim() ?? '';
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  /// Fetches trip history for the current driver
  static Future<List<Map<String, dynamic>>> getTripHistory(
      {int limit = 10}) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return [];

      final driverId = await _resolveDriverId();
      if (driverId == null || driverId.isEmpty) return [];

      final snapshot = await _firestore
          .collection(_tripHistoryCollection)
          .where('driverId', isEqualTo: driverId)
          .where('status', whereIn: ['completed', 'cancelled'])
          .orderBy('endedAt', descending: true)
          .limit(limit)
          .get();

      return snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'routeName': data['routeName'] ?? 'Unknown Route',
          'originTerminal': data['originTerminal'] ?? '',
          'destinationTerminal': data['destinationTerminal'] ?? '',
          'jeepneyId': data['jeepneyId'] ?? '',
          'startedAt': _toDateTime(data['startedAt']),
          'endedAt': _toDateTime(data['endedAt']),
          'durationMinutes': data['durationMinutes'] ?? 0,
          'passengerCount': data['passengerCount'] ?? 0,
          'totalPaymentCollected': data['totalPaymentCollected'] ?? 0,
          'cashPaymentCollected': data['cashPaymentCollected'] ?? 0,
          'rfidPaymentCollected': data['rfidPaymentCollected'] ?? 0,
          'status': data['status'] ?? 'completed',
        };
      }).toList();
    } catch (error) {
      debugPrint('Failed to fetch trip history: $error');
      return [];
    }
  }

  /// Stream of trip history for real-time updates
  static Stream<List<Map<String, dynamic>>> tripHistoryStream(
      {int limit = 10}) async* {
    final user = _auth.currentUser;
    if (user == null) {
      yield [];
      return;
    }

    final driverId = await _resolveDriverId();
    if (driverId == null || driverId.isEmpty) {
      debugPrint('[TripHistory] No driverId resolved');
      yield [];
      return;
    }

    debugPrint('[TripHistory] Fetching for driverId: $driverId');

    Stream<List<Map<String, dynamic>>> stream;
    try {
      stream = _firestore
          .collection(_tripHistoryCollection)
          .where('driverId', isEqualTo: driverId)
          .where('status', whereIn: ['completed', 'cancelled'])
          .orderBy('endedAt', descending: true)
          .limit(limit)
          .snapshots()
          .map(_mapTripSnapshot);
    } catch (e) {
      debugPrint('[TripHistory] Exception creating stream: $e');
      stream = _createFallbackTripHistoryStream(driverId, limit);
    }

    try {
      await for (final trips in stream) {
        yield trips;
      }
    } catch (e) {
      debugPrint('[TripHistory] Stream error, trying fallback: $e');
      try {
        final fallbackStream =
            _createFallbackTripHistoryStream(driverId, limit);
        await for (final trips in fallbackStream) {
          yield trips;
        }
      } catch (fallbackError) {
        debugPrint('[TripHistory] Fallback also failed: $fallbackError');
        yield [];
      }
    }
  }

  static List<Map<String, dynamic>> _mapTripSnapshot(QuerySnapshot snapshot) {
    debugPrint(
        '[TripHistory] Got ${snapshot.docs.length} trips from Firestore');
    return snapshot.docs.map((doc) {
      final data = doc.data() as Map<String, dynamic>;
      return {
        'id': doc.id,
        'routeName': data['routeName'] ?? 'Unknown Route',
        'originTerminal': data['originTerminal'] ?? '',
        'destinationTerminal': data['destinationTerminal'] ?? '',
        'jeepneyId': data['jeepneyId'] ?? '',
        'startedAt': _toDateTime(data['startedAt']),
        'endedAt': _toDateTime(data['endedAt']),
        'durationMinutes': data['durationMinutes'] ?? 0,
        'passengerCount': data['passengerCount'] ?? 0,
        'totalPaymentCollected': data['totalPaymentCollected'] ?? 0,
        'cashPaymentCollected': data['cashPaymentCollected'] ?? 0,
        'rfidPaymentCollected': data['rfidPaymentCollected'] ?? 0,
        'status': data['status'] ?? 'completed',
      };
    }).toList();
  }

  static Stream<List<Map<String, dynamic>>> _createFallbackTripHistoryStream(
    String driverId,
    int limit,
  ) {
    return _firestore
        .collection(_tripHistoryCollection)
        .where('driverId', isEqualTo: driverId)
        .where('status', whereIn: ['completed', 'cancelled'])
        .limit(limit)
        .snapshots()
        .map((snapshot) {
          debugPrint(
              '[TripHistory] Fallback query: Got ${snapshot.docs.length} trips');
          final trips = snapshot.docs.map((doc) {
            final data = doc.data();
            return {
              'id': doc.id,
              'routeName': data['routeName'] ?? 'Unknown Route',
              'originTerminal': data['originTerminal'] ?? '',
              'destinationTerminal': data['destinationTerminal'] ?? '',
              'jeepneyId': data['jeepneyId'] ?? '',
              'startedAt': _toDateTime(data['startedAt']),
              'endedAt': _toDateTime(data['endedAt']),
              'durationMinutes': data['durationMinutes'] ?? 0,
              'passengerCount': data['passengerCount'] ?? 0,
              'totalPaymentCollected': data['totalPaymentCollected'] ?? 0,
              'cashPaymentCollected': data['cashPaymentCollected'] ?? 0,
              'rfidPaymentCollected': data['rfidPaymentCollected'] ?? 0,
              'status': data['status'] ?? 'completed',
            };
          }).toList();
          trips.sort((a, b) {
            final aDate = a['endedAt'] as DateTime?;
            final bDate = b['endedAt'] as DateTime?;
            if (aDate == null || bDate == null) return 0;
            return bDate.compareTo(aDate);
          });
          return trips;
        });
  }
}

class _TripPaymentTotals {
  const _TripPaymentTotals({
    required this.passengerCount,
    required this.totalCollected,
    required this.cashCollected,
    required this.rfidCollected,
    required this.transactionCount,
  });

  final int passengerCount;
  final double totalCollected;
  final double cashCollected;
  final double rfidCollected;
  final int transactionCount;
}
