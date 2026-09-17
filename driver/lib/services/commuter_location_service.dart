import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';

import '../core/booking_status.dart';

/// Service to watch commuter waiting locations for the driver app
class CommuterLocationService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Stream of all active commuter waiting locations
  static Stream<List<CommuterWaitingLocation>> watchActiveCommuterLocations() {
    return _firestore
        .collection('commuter_waiting_location')
        .where('isSharing', isEqualTo: true)
        .snapshots()
        .map((snapshot) {
      final now = DateTime.now();
      return snapshot.docs
          .where((doc) => _isLocationActive(doc.data(), now))
          .map((doc) => CommuterWaitingLocation.fromFirestore(doc))
          .toList();
    });
  }

  /// Get all active commuter locations once
  static Future<List<CommuterWaitingLocation>>
      getActiveCommuterLocations() async {
    final snapshot = await _firestore
        .collection('commuter_waiting_location')
        .where('isSharing', isEqualTo: true)
        .get();

    final now = DateTime.now();
    return snapshot.docs
        .where((doc) => _isLocationActive(doc.data(), now))
        .map((doc) => CommuterWaitingLocation.fromFirestore(doc))
        .toList();
  }

  static bool _isLocationActive(Map<String, dynamic> data, DateTime now) {
    if (data['isSharing'] != true) return false;

    final expiresAt = _toDateTime(data['expiresAt']);
    if (expiresAt != null) {
      return expiresAt.isAfter(now);
    }

    final timestamp = _toDateTime(data['timestamp']);
    if (timestamp == null) return false;

    return now.difference(timestamp) <= const Duration(minutes: 15);
  }

  static DateTime? _toDateTime(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }
}

/// Model representing a commuter waiting location
class CommuterWaitingLocation {
  final String commuterId;
  final LatLng location;
  final String? routeId;
  final String? destinationTerminal;
  final int waitingCount;
  final String status;
  final DateTime? timestamp;
  final DateTime? expiresAt;
  final DateTime? cancelledAt;

  CommuterWaitingLocation({
    required this.commuterId,
    required this.location,
    this.routeId,
    this.destinationTerminal,
    required this.waitingCount,
    this.status = BookingStatus.waiting,
    this.timestamp,
    this.expiresAt,
    this.cancelledAt,
  });

  factory CommuterWaitingLocation.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final status = BookingStatus.normalize(data['status']?.toString());
    return CommuterWaitingLocation(
      commuterId: doc.id,
      location: LatLng(
        (data['lat'] as num).toDouble(),
        (data['lng'] as num).toDouble(),
      ),
      routeId: data['routeId'] as String?,
      destinationTerminal: data['destinationTerminal'] as String?,
      waitingCount: (data['waitingCount'] as num?)?.toInt() ?? 1,
      status: status.isEmpty ? BookingStatus.waiting : status,
      timestamp: data['timestamp'] != null
          ? (data['timestamp'] as Timestamp).toDate()
          : null,
      expiresAt: data['expiresAt'] != null
          ? (data['expiresAt'] as Timestamp).toDate()
          : null,
      cancelledAt: data['cancelledAt'] != null
          ? (data['cancelledAt'] as Timestamp).toDate()
          : null,
    );
  }
}
