import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants/booking_status.dart';

class CompletedTrip {
  final String bookingId;
  final String commuterId;
  final String commuterName;
  final String driverId;
  final String driverName;
  final String jeepneyId;
  final String plateNumber;
  final String tripScheduleId;
  final String routeId;
  final String routeName;
  final String originTerminal;
  final String destinationTerminal;
  final DateTime? onBoardAt;
  final DateTime? offboardAt;
  final bool hasFeedback;
  final String feedbackId;
  final int? rating;

  const CompletedTrip({
    required this.bookingId,
    required this.commuterId,
    required this.commuterName,
    required this.driverId,
    required this.driverName,
    required this.jeepneyId,
    required this.plateNumber,
    required this.tripScheduleId,
    required this.routeId,
    required this.routeName,
    required this.originTerminal,
    required this.destinationTerminal,
    this.onBoardAt,
    this.offboardAt,
    this.hasFeedback = false,
    this.feedbackId = '',
    this.rating,
  });

  bool get canRate =>
      !hasFeedback &&
      commuterId.trim().isNotEmpty &&
      bookingId.trim().isNotEmpty &&
      jeepneyId.trim().isNotEmpty &&
      (tripScheduleId.trim().isNotEmpty || bookingId.trim().isNotEmpty);

  String get displayRoute {
    if (routeName.trim().isNotEmpty) return routeName.trim();
    if (originTerminal.trim().isNotEmpty ||
        destinationTerminal.trim().isNotEmpty) {
      final from = originTerminal.trim().isEmpty ? 'Origin' : originTerminal;
      final to = destinationTerminal.trim().isEmpty
          ? 'Destination'
          : destinationTerminal;
      return '$from to $to';
    }
    return routeId.trim().isEmpty ? 'Completed trip' : routeId.trim();
  }

  factory CompletedTrip.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? <String, dynamic>{};
    return CompletedTrip(
      bookingId: _readString(data, ['id', 'bookingId'], fallback: doc.id),
      commuterId: _readString(data, ['commuterId']),
      commuterName: _readString(data, ['commuterName', 'displayName']),
      driverId: _readString(data, ['driverDocId', 'driverId']),
      driverName: _readString(data, ['driverName', 'assignedDriverName']),
      jeepneyId: _readString(data, ['jeepneyId']),
      plateNumber: _readString(data, ['plateNumber', 'jeepneyId']),
      tripScheduleId: _readString(data, ['tripScheduleId']),
      routeId: _readString(data, ['routeId']),
      routeName: _readString(data, ['routeName', 'route']),
      originTerminal: _readString(data, ['originTerminal', 'origin']),
      destinationTerminal: _readString(data, [
        'destinationTerminal',
        'destination',
      ]),
      onBoardAt: _toDateTime(data['onBoardAt'] ?? data['bookedAt']),
      offboardAt: _toDateTime(data['offboardAt']),
      hasFeedback: _toBool(data['hasFeedback']),
      feedbackId: _readString(data, ['feedbackId']),
      rating: _toInt(data['rating']),
    );
  }
}

class RideFeedbackSubmission {
  final CompletedTrip trip;
  final int rating;
  final String comment;
  final List<String> tags;

  const RideFeedbackSubmission({
    required this.trip,
    required this.rating,
    this.comment = '',
    this.tags = const [],
  });
}

class RideFeedbackService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static Stream<List<CompletedTrip>> watchCompletedTrips(String commuterId) {
    final cleanCommuterId = commuterId.trim();
    if (cleanCommuterId.isEmpty) {
      return const Stream<List<CompletedTrip>>.empty();
    }

    return _db
        .collection('bookings')
        .where('commuterId', isEqualTo: cleanCommuterId)
        .snapshots()
        .map((snapshot) {
          final trips = <CompletedTrip>[];
          for (final doc in snapshot.docs) {
            final data = doc.data();
            if (!_isCompletedTripData(data)) continue;
            final trip = CompletedTrip.fromFirestore(doc);
            if (trip.commuterId == cleanCommuterId) trips.add(trip);
          }
          trips.sort((a, b) {
            final aTime = a.offboardAt ?? a.onBoardAt ?? DateTime(1970);
            final bTime = b.offboardAt ?? b.onBoardAt ?? DateTime(1970);
            return bTime.compareTo(aTime);
          });
          return trips;
        });
  }

  static Future<CompletedTrip?> getLatestUnratedCompletedTrip(
    String commuterId,
  ) async {
    final cleanCommuterId = commuterId.trim();
    if (cleanCommuterId.isEmpty) return null;

    final snapshot = await _db
        .collection('bookings')
        .where('commuterId', isEqualTo: cleanCommuterId)
        .limit(30)
        .get();

    final trips = snapshot.docs
        .where((doc) => _isCompletedTripData(doc.data()))
        .map(CompletedTrip.fromFirestore)
        .where((trip) => trip.commuterId == cleanCommuterId && trip.canRate)
        .toList();
    trips.sort((a, b) {
      final aTime = a.offboardAt ?? a.onBoardAt ?? DateTime(1970);
      final bTime = b.offboardAt ?? b.onBoardAt ?? DateTime(1970);
      return bTime.compareTo(aTime);
    });
    return trips.isEmpty ? null : trips.first;
  }

  static Future<void> submitFeedback(RideFeedbackSubmission submission) async {
    final trip = submission.trip;
    final cleanBookingId = _safeFirestoreId(trip.bookingId);
    final cleanCommuterId = trip.commuterId.trim();
    final cleanComment = submission.comment.trim();
    final cleanTags = submission.tags
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toSet()
        .toList();

    if (submission.rating < 1 || submission.rating > 5) {
      throw StateError('Please choose a rating from 1 to 5 stars.');
    }
    if (cleanBookingId.isEmpty || cleanCommuterId.isEmpty) {
      throw StateError('Completed trip data is incomplete.');
    }

    final bookingRef = _db.collection('bookings').doc(cleanBookingId);
    final feedbackRef = _db.collection('ride_feedback').doc(cleanBookingId);
    final notificationRef = _db.collection('notifications').doc();

    await _db.runTransaction((transaction) async {
      final bookingDoc = await transaction.get(bookingRef);
      if (!bookingDoc.exists) {
        throw StateError('Completed trip was not found.');
      }

      final bookingData = bookingDoc.data() ?? <String, dynamic>{};
      final storedCommuterId = _readString(bookingData, ['commuterId']);
      if (storedCommuterId != cleanCommuterId) {
        throw StateError('This completed trip belongs to another commuter.');
      }

      if (!_isCompletedTripData(bookingData)) {
        throw StateError('Only completed rides can be rated.');
      }

      if (_toBool(bookingData['hasFeedback'])) {
        throw StateError('This ride has already been rated.');
      }

      final existingFeedback = await transaction.get(feedbackRef);
      if (existingFeedback.exists) {
        throw StateError('This ride has already been rated.');
      }

      final jeepneyId = _firstNonEmpty([
        bookingData['jeepneyId'],
        trip.jeepneyId,
      ]);
      if (jeepneyId.isEmpty) {
        throw StateError('This completed trip is missing jeepney data.');
      }

      final locationRef = _db.collection('locations').doc(jeepneyId);
      final locationDoc = await transaction.get(locationRef);
      final locationData = locationDoc.data() ?? <String, dynamic>{};

      final driverId = _firstNonEmpty([
        bookingData['driverDocId'],
        bookingData['driverId'],
        locationData['driverDocId'],
        locationData['driverId'],
        trip.driverId,
      ]);
      if (driverId.isEmpty) {
        throw StateError('This completed trip is missing driver data.');
      }

      final driverSummaryRef = _db
          .collection('driver_rating_summary')
          .doc(_safeFirestoreId(driverId));
      final jeepneySummaryRef = _db
          .collection('jeepney_rating_summary')
          .doc(_safeFirestoreId(jeepneyId));
      final driverSummaryDoc = await transaction.get(driverSummaryRef);
      final jeepneySummaryDoc = await transaction.get(jeepneySummaryRef);

      final now = FieldValue.serverTimestamp();
      final plateNumber = _firstNonEmpty([
        bookingData['plateNumber'],
        locationData['plateNumber'],
        trip.plateNumber,
        jeepneyId,
      ]);
      final driverName = _firstNonEmpty([
        bookingData['driverName'],
        locationData['driverName'],
        trip.driverName,
      ]);
      final tripScheduleId = _firstNonEmpty([
        bookingData['tripScheduleId'],
        trip.tripScheduleId,
      ]);
      final routeId = _firstNonEmpty([bookingData['routeId'], trip.routeId]);

      transaction.set(feedbackRef, {
        'id': cleanBookingId,
        'feedbackId': cleanBookingId,
        'bookingId': cleanBookingId,
        'commuterId': cleanCommuterId,
        'commuterName': _firstNonEmpty([
          bookingData['commuterName'],
          trip.commuterName,
        ]),
        'driverId': driverId,
        'driverDocId': driverId,
        'driverUid': _firstNonEmpty([
          bookingData['driverUid'],
          locationData['driverUid'],
        ]),
        'driverName': driverName,
        'jeepneyId': jeepneyId,
        'plateNumber': plateNumber,
        'tripScheduleId': tripScheduleId,
        'routeId': routeId,
        'routeName': _firstNonEmpty([
          bookingData['routeName'],
          bookingData['route'],
          trip.routeName,
        ]),
        'originTerminal': _firstNonEmpty([
          bookingData['originTerminal'],
          trip.originTerminal,
        ]),
        'destinationTerminal': _firstNonEmpty([
          bookingData['destinationTerminal'],
          trip.destinationTerminal,
        ]),
        'rating': submission.rating,
        'comment': cleanComment,
        'tags': cleanTags,
        'status': 'submitted',
        'offboardAt': bookingData['offboardAt'],
        'createdAt': now,
        'updatedAt': now,
      });

      transaction.set(bookingRef, {
        'hasFeedback': true,
        'feedbackId': cleanBookingId,
        'rating': submission.rating,
        'feedbackSubmittedAt': now,
        'updatedAt': now,
      }, SetOptions(merge: true));

      transaction.set(
        driverSummaryRef,
        _nextSummaryData(
          driverSummaryDoc.data(),
          idField: 'driverDocId',
          id: driverId,
          rating: submission.rating,
          timestamp: now,
        ),
        SetOptions(merge: true),
      );

      transaction.set(
        jeepneySummaryRef,
        _nextSummaryData(
          jeepneySummaryDoc.data(),
          idField: 'jeepneyId',
          id: jeepneyId,
          rating: submission.rating,
          timestamp: now,
        ),
        SetOptions(merge: true),
      );

      transaction.set(notificationRef, {
        'driverId': driverId,
        'driverDocId': driverId,
        'jeepneyId': jeepneyId,
        'type': 'ride_feedback',
        'title': 'New Ride Feedback',
        'message': 'You received ${submission.rating} stars.',
        'rating': submission.rating,
        'feedbackId': cleanBookingId,
        'bookingId': cleanBookingId,
        'tripScheduleId': tripScheduleId,
        'isRead': false,
        'createdAt': now,
      });
    });
  }

  static Map<String, dynamic> _nextSummaryData(
    Map<String, dynamic>? current, {
    required String idField,
    required String id,
    required int rating,
    required FieldValue timestamp,
  }) {
    final existingCount = _toInt(current?['ratingCount']) ?? 0;
    final existingAverage = _toDouble(current?['averageRating']) ?? 0.0;
    final nextCount = existingCount + 1;
    final nextAverage =
        ((existingAverage * existingCount) + rating) / nextCount;

    return {
      idField: id,
      'averageRating': nextAverage,
      'ratingCount': nextCount,
      'oneStarCount':
          (_toInt(current?['oneStarCount']) ?? 0) + (rating == 1 ? 1 : 0),
      'twoStarCount':
          (_toInt(current?['twoStarCount']) ?? 0) + (rating == 2 ? 1 : 0),
      'threeStarCount':
          (_toInt(current?['threeStarCount']) ?? 0) + (rating == 3 ? 1 : 0),
      'fourStarCount':
          (_toInt(current?['fourStarCount']) ?? 0) + (rating == 4 ? 1 : 0),
      'fiveStarCount':
          (_toInt(current?['fiveStarCount']) ?? 0) + (rating == 5 ? 1 : 0),
      'lastFeedbackAt': timestamp,
      'updatedAt': timestamp,
    };
  }
}

String _readString(
  Map<String, dynamic> data,
  List<String> keys, {
  String fallback = '',
}) {
  for (final key in keys) {
    final value = data[key]?.toString().trim() ?? '';
    if (value.isNotEmpty && value.toLowerCase() != 'null') return value;
  }
  return fallback;
}

String _firstNonEmpty(List<dynamic> values) {
  for (final value in values) {
    final text = value?.toString().trim() ?? '';
    if (text.isNotEmpty && text.toLowerCase() != 'null') return text;
  }
  return '';
}

String _safeFirestoreId(String value) {
  return value.trim().replaceAll(RegExp(r'[/#?\[\]]'), '_');
}

DateTime? _toDateTime(dynamic value) {
  if (value == null) return null;
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}

bool _toBool(dynamic value) {
  if (value is bool) return value;
  if (value is num) return value == 1;
  if (value is String) {
    final text = value.trim().toLowerCase();
    return text == 'true' || text == '1' || text == 'yes';
  }
  return false;
}

bool _isCompletedTripData(Map<String, dynamic> data) {
  final status = _readString(data, ['status']).toLowerCase();
  final rideStatus = _readString(data, ['rideStatus']).toLowerCase();
  return BookingStatus.isOffboard(status) ||
      status == 'completed' ||
      BookingStatus.isOffboard(rideStatus) ||
      rideStatus == 'completed' ||
      _toBool(data['completedForCommuter']) ||
      data['offboardAt'] != null;
}

int? _toInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

double? _toDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}
