import 'package:cloud_firestore/cloud_firestore.dart';

class DriverRatingSummary {
  final double averageRating;
  final int ratingCount;

  const DriverRatingSummary({
    required this.averageRating,
    required this.ratingCount,
  });

  factory DriverRatingSummary.empty() {
    return const DriverRatingSummary(averageRating: 0, ratingCount: 0);
  }

  factory DriverRatingSummary.fromData(Map<String, dynamic>? data) {
    if (data == null) return DriverRatingSummary.empty();
    return DriverRatingSummary(
      averageRating: _toDouble(data['averageRating']) ?? 0,
      ratingCount: _toInt(data['ratingCount']) ?? 0,
    );
  }
}

class DriverFeedback {
  final String id;
  final int rating;
  final String comment;
  final List<String> tags;
  final String plateNumber;
  final String routeName;
  final String originTerminal;
  final String destinationTerminal;
  final DateTime? createdAt;

  const DriverFeedback({
    required this.id,
    required this.rating,
    required this.comment,
    required this.tags,
    required this.plateNumber,
    required this.routeName,
    required this.originTerminal,
    required this.destinationTerminal,
    this.createdAt,
  });

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
    return 'Completed trip';
  }

  factory DriverFeedback.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? <String, dynamic>{};
    final rawTags = data['tags'];
    return DriverFeedback(
      id: doc.id,
      rating: _toInt(data['rating']) ?? 0,
      comment: data['comment']?.toString() ?? '',
      tags: rawTags is List
          ? rawTags.map((tag) => tag.toString()).toList()
          : const <String>[],
      plateNumber: data['plateNumber']?.toString() ?? '',
      routeName: data['routeName']?.toString() ?? '',
      originTerminal: data['originTerminal']?.toString() ?? '',
      destinationTerminal: data['destinationTerminal']?.toString() ?? '',
      createdAt: _toDateTime(data['createdAt']),
    );
  }
}

class FeedbackService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static Stream<DriverRatingSummary> watchDriverRatingSummary(
    String driverId,
  ) {
    final cleanDriverId = _safeFirestoreId(driverId);
    if (cleanDriverId.isEmpty) {
      return Stream.value(DriverRatingSummary.empty());
    }

    return _db
        .collection('driver_rating_summary')
        .doc(cleanDriverId)
        .snapshots()
        .map((doc) => DriverRatingSummary.fromData(doc.data()));
  }

  static Stream<List<DriverFeedback>> watchRecentDriverFeedback(
    String driverId, {
    int limit = 3,
  }) {
    return watchAllDriverFeedback(driverId).map(
      (feedback) => feedback.take(limit).toList(),
    );
  }

  static Stream<List<DriverFeedback>> watchAllDriverFeedback(
    String driverId,
  ) {
    final cleanDriverId = driverId.trim();
    if (cleanDriverId.isEmpty) return Stream.value(const <DriverFeedback>[]);

    return _db
        .collection('ride_feedback')
        .where('driverDocId', isEqualTo: cleanDriverId)
        .snapshots()
        .map((snapshot) {
      final feedback = snapshot.docs
          .where((doc) {
            final data = doc.data();
            final status =
                data['status']?.toString().trim().toLowerCase() ?? '';
            final rating = _toInt(data['rating']) ?? 0;
            return status != 'hidden' && rating > 0;
          })
          .map(DriverFeedback.fromFirestore)
          .toList();
      feedback.sort((a, b) {
        final aTime = a.createdAt ?? DateTime(1970);
        final bTime = b.createdAt ?? DateTime(1970);
        return bTime.compareTo(aTime);
      });
      return feedback;
    });
  }
}

String _safeFirestoreId(String value) {
  return value.trim().replaceAll(RegExp(r'[/#?\[\]]'), '_');
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

DateTime? _toDateTime(dynamic value) {
  if (value == null) return null;
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}
