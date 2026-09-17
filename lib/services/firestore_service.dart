import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../core/booking_status.dart';

class FirestoreErrorCode {
  static const String permissionDenied = 'permission-denied';
  static const String unavailable = 'unavailable';
  static const String notFound = 'not-found';
  static const String invalidArgument = 'invalid-argument';
  static const String unknown = 'unknown';
}

class FirestoreResult<T> {
  final bool success;
  final T? data;
  final String message;
  final String? errorCode;

  const FirestoreResult({
    required this.success,
    this.data,
    required this.message,
    this.errorCode,
  });

  const FirestoreResult.success({
    this.data,
    this.message = 'Operation completed successfully.',
    this.errorCode,
  }) : success = true;

  const FirestoreResult.failure({
    required this.message,
    this.errorCode = FirestoreErrorCode.unknown,
  })  : success = false,
        data = null;

  bool get isNotFound => !success && errorCode == FirestoreErrorCode.notFound;
}

/// Firestore Service for ByaheroX Driver App.
///
/// Handles:
/// - Driver profile lookup
/// - Assigned jeepney lookup
/// - Route lookup
/// - Real-time jeepney location updates
/// - Online/offline status
/// - Crowd status
/// - Driver notifications
class FirestoreService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  static String? _cachedDriverDocId;
  static String? _cachedDriverUid;
  static String? _cachedDriverEmail;

  // ---------------------------------------------------------------------------
  // ERROR HELPERS
  // ---------------------------------------------------------------------------

  static String userFriendlyMessageForError(Object error) {
    return _messageForErrorCode(_errorCodeFromError(error));
  }

  static String _messageForErrorCode(String? errorCode) {
    switch (errorCode) {
      case FirestoreErrorCode.permissionDenied:
        return 'You do not have permission to access this driver data. Please contact support.';

      case FirestoreErrorCode.unavailable:
        return 'We could not reach the server. Check your internet connection and try again.';

      case FirestoreErrorCode.notFound:
        return 'The requested driver data was not found.';

      case FirestoreErrorCode.invalidArgument:
        return 'Some location data was invalid. Please try again.';

      case FirestoreErrorCode.unknown:
      default:
        return 'Something went wrong while loading driver data. Please try again.';
    }
  }

  static String _errorCodeFromError(Object error) {
    if (error is FirebaseException) {
      switch (error.code) {
        case 'permission-denied':
          return FirestoreErrorCode.permissionDenied;

        case 'unavailable':
        case 'deadline-exceeded':
        case 'network-request-failed':
        case 'network-error':
          return FirestoreErrorCode.unavailable;

        case 'not-found':
          return FirestoreErrorCode.notFound;

        case 'invalid-argument':
          return FirestoreErrorCode.invalidArgument;

        default:
          return error.code.isNotEmpty
              ? error.code
              : FirestoreErrorCode.unknown;
      }
    }

    return FirestoreErrorCode.unknown;
  }

  static FirestoreResult<T> _notFound<T>(
    String operation,
    String message,
  ) {
    debugPrint('[FirestoreService] $operation: $message');

    return FirestoreResult<T>.failure(
      message: message,
      errorCode: FirestoreErrorCode.notFound,
    );
  }

  static FirestoreResult<T> _invalid<T>(
    String operation,
    String message,
  ) {
    debugPrint('[FirestoreService] $operation invalid: $message');

    return FirestoreResult<T>.failure(
      message: message,
      errorCode: FirestoreErrorCode.invalidArgument,
    );
  }

  static FirestoreResult<T> _failure<T>(
    String operation,
    Object error,
    StackTrace stackTrace,
  ) {
    final errorCode = _errorCodeFromError(error);
    final message = _messageForErrorCode(errorCode);

    debugPrint('[FirestoreService] $operation failed.');
    debugPrint('[FirestoreService] code=$errorCode, error=$error');
    debugPrint('[FirestoreService] stackTrace=$stackTrace');

    return FirestoreResult<T>.failure(
      message: message,
      errorCode: errorCode,
    );
  }

  // ---------------------------------------------------------------------------
  // AUTH / CURRENT DRIVER HELPERS
  // ---------------------------------------------------------------------------

  static String? getCurrentDriverId() {
    return _auth.currentUser?.uid;
  }

  static String? getCurrentDriverEmail() {
    return _auth.currentUser?.email;
  }

  static void clearDriverCache() {
    _cachedDriverDocId = null;
    _cachedDriverUid = null;
    _cachedDriverEmail = null;
  }

  /// Gets current driver's document ID from the `driver` collection.
  ///
  /// Important ito dahil minsan ang Admin app ay gumagamit ng document IDs like:
  /// - DRV001
  /// - DRV002
  ///
  /// habang ang Firebase Auth ay gumagamit ng UID.
  static Future<String?> getCurrentDriverDocId() async {
    final result = await getCurrentDriverDocIdResult();
    return result.data;
  }

  static Future<FirestoreResult<String>> getCurrentDriverDocIdResult() async {
    try {
      final currentUser = _auth.currentUser;
      final currentUid = currentUser?.uid;
      final currentEmail = currentUser?.email?.trim().toLowerCase();

      if (currentUser == null) {
        return _notFound(
          'getCurrentDriverDocId',
          'No signed-in driver was found.',
        );
      }

      if (_cachedDriverUid == currentUid &&
          _cachedDriverDocId != null &&
          _cachedDriverDocId!.isNotEmpty) {
        return FirestoreResult<String>.success(
          data: _cachedDriverDocId,
          message: 'Driver document ID loaded from cache.',
        );
      }

      if (currentUid != null && currentUid.isNotEmpty) {
        final directDoc = await _db.collection('driver').doc(currentUid).get();

        if (directDoc.exists) {
          _cachedDriverUid = currentUid;
          _cachedDriverEmail = currentEmail;
          _cachedDriverDocId = directDoc.id;

          return FirestoreResult<String>.success(
            data: directDoc.id,
            message: 'Driver document ID loaded successfully.',
          );
        }
      }

      if (currentUid != null && currentUid.isNotEmpty) {
        final uidQuery = await _db
            .collection('driver')
            .where('uid', isEqualTo: currentUid)
            .limit(1)
            .get();

        if (uidQuery.docs.isNotEmpty) {
          _cachedDriverUid = currentUid;
          _cachedDriverEmail = currentEmail;
          _cachedDriverDocId = uidQuery.docs.first.id;

          return FirestoreResult<String>.success(
            data: uidQuery.docs.first.id,
            message: 'Driver document ID loaded successfully.',
          );
        }
      }

      if (currentEmail != null && currentEmail.isNotEmpty) {
        final emailQuery = await _db
            .collection('driver')
            .where('email', isEqualTo: currentEmail)
            .limit(1)
            .get();

        if (emailQuery.docs.isNotEmpty) {
          _cachedDriverUid = currentUid;
          _cachedDriverEmail = currentEmail;
          _cachedDriverDocId = emailQuery.docs.first.id;

          return FirestoreResult<String>.success(
            data: emailQuery.docs.first.id,
            message: 'Driver document ID loaded successfully.',
          );
        }
      }

      return _notFound(
        'getCurrentDriverDocId',
        'Driver profile not found for the signed-in account.',
      );
    } catch (e, stackTrace) {
      return _failure('getCurrentDriverDocId', e, stackTrace);
    }
  }

  static Future<DocumentSnapshot<Map<String, dynamic>>?>
      _getCurrentDriverDocument() async {
    final result = await _getCurrentDriverDocumentResult();
    return result.data;
  }

  static Future<FirestoreResult<DocumentSnapshot<Map<String, dynamic>>>>
      _getCurrentDriverDocumentResult() async {
    try {
      final currentUser = _auth.currentUser;
      final currentUid = currentUser?.uid;
      final currentEmail = currentUser?.email?.trim().toLowerCase();

      if (currentUser == null) {
        return _notFound(
          'getCurrentDriverDocument',
          'No signed-in driver was found.',
        );
      }

      if (_cachedDriverUid == currentUid &&
          _cachedDriverDocId != null &&
          _cachedDriverDocId!.isNotEmpty) {
        final cachedDoc =
            await _db.collection('driver').doc(_cachedDriverDocId).get();

        if (cachedDoc.exists) {
          return FirestoreResult<
              DocumentSnapshot<Map<String, dynamic>>>.success(
            data: cachedDoc,
            message: 'Current driver document loaded from cache.',
          );
        }

        clearDriverCache();
      }

      if (currentUid != null && currentUid.isNotEmpty) {
        final directDoc = await _db.collection('driver').doc(currentUid).get();

        if (directDoc.exists) {
          _cachedDriverUid = currentUid;
          _cachedDriverEmail = currentEmail;
          _cachedDriverDocId = directDoc.id;

          return FirestoreResult<
              DocumentSnapshot<Map<String, dynamic>>>.success(
            data: directDoc,
            message: 'Current driver document loaded successfully.',
          );
        }
      }

      if (currentUid != null && currentUid.isNotEmpty) {
        final uidQuery = await _db
            .collection('driver')
            .where('uid', isEqualTo: currentUid)
            .limit(1)
            .get();

        if (uidQuery.docs.isNotEmpty) {
          _cachedDriverUid = currentUid;
          _cachedDriverEmail = currentEmail;
          _cachedDriverDocId = uidQuery.docs.first.id;

          return FirestoreResult<
              DocumentSnapshot<Map<String, dynamic>>>.success(
            data: uidQuery.docs.first,
            message: 'Current driver document loaded successfully.',
          );
        }
      }

      if (currentEmail != null && currentEmail.isNotEmpty) {
        final emailQuery = await _db
            .collection('driver')
            .where('email', isEqualTo: currentEmail)
            .limit(1)
            .get();

        if (emailQuery.docs.isNotEmpty) {
          _cachedDriverUid = currentUid;
          _cachedDriverEmail = currentEmail;
          _cachedDriverDocId = emailQuery.docs.first.id;

          return FirestoreResult<
              DocumentSnapshot<Map<String, dynamic>>>.success(
            data: emailQuery.docs.first,
            message: 'Current driver document loaded successfully.',
          );
        }
      }

      return _notFound(
        'getCurrentDriverDocument',
        'Driver profile not found. Please contact the administrator.',
      );
    } catch (e, stackTrace) {
      return _failure('getCurrentDriverDocument', e, stackTrace);
    }
  }

  static Future<Map<String, dynamic>> _currentDriverLocationMetadata() async {
    final user = _auth.currentUser;

    if (user != null &&
        _cachedDriverUid == user.uid &&
        _cachedDriverDocId != null &&
        _cachedDriverDocId!.isNotEmpty) {
      return <String, dynamic>{
        'driverUid': user.uid,
        if (user.email != null) 'driverEmail': user.email!.toLowerCase(),
        'driverDocId': _cachedDriverDocId,
      };
    }

    final driverDoc = await _getCurrentDriverDocument();

    _cachedDriverUid = user?.uid;
    _cachedDriverEmail = user?.email?.toLowerCase();
    _cachedDriverDocId = driverDoc?.id;

    return <String, dynamic>{
      if (user != null) 'driverUid': user.uid,
      if (_cachedDriverEmail != null) 'driverEmail': _cachedDriverEmail,
      if (driverDoc != null) 'driverDocId': driverDoc.id,
    };
  }

  // ---------------------------------------------------------------------------
  // DRIVER PROFILE
  // ---------------------------------------------------------------------------

  static Future<DriverProfile?> getDriverProfile(String driverId) async {
    final result = await getDriverProfileResult(driverId);
    return result.data;
  }

  static Future<FirestoreResult<DriverProfile>> getDriverProfileResult(
    String driverId,
  ) async {
    try {
      final cleanDriverId = driverId.trim();

      if (cleanDriverId.isEmpty) {
        return _notFound(
          'getDriverProfile',
          'Driver ID is missing.',
        );
      }

      final doc = await _db.collection('driver').doc(cleanDriverId).get();

      if (doc.exists) {
        return FirestoreResult<DriverProfile>.success(
          data: DriverProfile.fromFirestore(doc),
          message: 'Driver profile loaded successfully.',
        );
      }

      final uidQuery = await _db
          .collection('driver')
          .where('uid', isEqualTo: cleanDriverId)
          .limit(1)
          .get();

      if (uidQuery.docs.isNotEmpty) {
        return FirestoreResult<DriverProfile>.success(
          data: DriverProfile.fromFirestore(uidQuery.docs.first),
          message: 'Driver profile loaded successfully.',
        );
      }

      final currentEmail = getCurrentDriverEmail()?.trim().toLowerCase();

      if (currentEmail != null && currentEmail.isNotEmpty) {
        final emailQuery = await _db
            .collection('driver')
            .where('email', isEqualTo: currentEmail)
            .limit(1)
            .get();

        if (emailQuery.docs.isNotEmpty) {
          debugPrint('[FirestoreService] Found driver by email: $currentEmail');

          return FirestoreResult<DriverProfile>.success(
            data: DriverProfile.fromFirestore(emailQuery.docs.first),
            message: 'Driver profile loaded successfully.',
          );
        }
      }

      return _notFound(
        'getDriverProfile',
        'Driver profile not found. Please contact the administrator.',
      );
    } catch (e, stackTrace) {
      return _failure('getDriverProfile', e, stackTrace);
    }
  }

  static Future<DriverProfile?> getCurrentDriverProfile() async {
    final result = await getCurrentDriverProfileResult();
    return result.data;
  }

  static Future<FirestoreResult<DriverProfile>>
      getCurrentDriverProfileResult() async {
    try {
      final docResult = await _getCurrentDriverDocumentResult();

      if (!docResult.success) {
        return FirestoreResult<DriverProfile>.failure(
          message: docResult.message,
          errorCode: docResult.errorCode,
        );
      }

      final doc = docResult.data;

      if (doc == null || !doc.exists) {
        return _notFound(
          'getCurrentDriverProfile',
          docResult.message,
        );
      }

      return FirestoreResult<DriverProfile>.success(
        data: DriverProfile.fromFirestore(doc),
        message: 'Driver profile loaded successfully.',
      );
    } catch (e, stackTrace) {
      return _failure('getCurrentDriverProfile', e, stackTrace);
    }
  }

  static Future<bool> markCurrentDriverPasswordSetupComplete() async {
    try {
      final doc = await _getCurrentDriverDocument();

      if (doc == null) {
        return false;
      }

      await _db.collection('driver').doc(doc.id).set({
        'mustSetPassword': false,
        'accountStatus': 'active',
        'passwordSetAt': FieldValue.serverTimestamp(),
        'passwordChangedAt': FieldValue.serverTimestamp(),
        'temporaryPasswordClearedAt': FieldValue.serverTimestamp(),
        'lastLoginAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      return true;
    } catch (e) {
      debugPrint(
          '[FirestoreService] Error marking password setup complete: $e');
      return false;
    }
  }

  static Future<bool> updateCurrentDriverLastLogin() async {
    try {
      final doc = await _getCurrentDriverDocument();

      if (doc == null) {
        return false;
      }

      await _db.collection('driver').doc(doc.id).set({
        'lastLoginAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      return true;
    } catch (e) {
      debugPrint('[FirestoreService] Error updating last login timestamp: $e');
      return false;
    }
  }

  static Future<bool> markCurrentDriverTemporaryPasswordLoginConsumed() async {
    try {
      final doc = await _getCurrentDriverDocument();

      if (doc == null) {
        return false;
      }

      await _db.collection('driver').doc(doc.id).set({
        'temporaryPasswordLoginConsumed': true,
        'temporaryPasswordLoginConsumedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      return true;
    } catch (e) {
      debugPrint(
          '[FirestoreService] Error marking temporary password login consumed: $e');
      return false;
    }
  }

  static Future<bool> markCurrentDriverEmailVerified() async {
    try {
      final doc = await _getCurrentDriverDocument();

      if (doc == null) {
        return false;
      }

      await _db.collection('driver').doc(doc.id).set({
        'emailVerified': true,
        'emailVerifiedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      return true;
    } catch (e) {
      debugPrint('[FirestoreService] Error marking driver email verified: $e');
      return false;
    }
  }

  static Future<bool> updateCurrentDriverFcmToken(String token) async {
    try {
      final cleanToken = token.trim();

      if (cleanToken.isEmpty) {
        return false;
      }

      final doc = await _getCurrentDriverDocument();

      if (doc == null) {
        return false;
      }

      await _db.collection('driver').doc(doc.id).set({
        'fcmToken': cleanToken,
        'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      return true;
    } catch (e) {
      debugPrint('[FirestoreService] Error updating FCM token: $e');
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // JEEPNEY
  // ---------------------------------------------------------------------------

  static Future<Jeepney?> getJeepneyById(String jeepneyId) async {
    final result = await getJeepneyByIdResult(jeepneyId);
    return result.data;
  }

  static Future<FirestoreResult<Jeepney>> getJeepneyByIdResult(
    String jeepneyId,
  ) async {
    try {
      final cleanJeepneyId = jeepneyId.trim();

      if (cleanJeepneyId.isEmpty) {
        return _notFound(
          'getJeepneyById',
          'Jeepney ID is missing.',
        );
      }

      final doc = await _db.collection('jeeps').doc(cleanJeepneyId).get();

      if (doc.exists) {
        debugPrint('[FirestoreService] Found jeepney by ID: $cleanJeepneyId');

        return FirestoreResult<Jeepney>.success(
          data: Jeepney.fromFirestore(doc),
          message: 'Jeepney loaded successfully.',
        );
      }

      debugPrint(
          '[FirestoreService] Jeepney not found for ID: $cleanJeepneyId');

      return _notFound(
        'getJeepneyById',
        'Jeepney not found. Please contact support.',
      );
    } catch (e, stackTrace) {
      return _failure('getJeepneyById', e, stackTrace);
    }
  }

  static Future<Jeepney?> getJeepneyByDriver(String driverId) async {
    final result = await getJeepneyByDriverResult(driverId);
    return result.data;
  }

  static Future<FirestoreResult<Jeepney>> getJeepneyByDriverResult(
    String driverId,
  ) async {
    final cleanDriverId = driverId.trim();

    if (cleanDriverId.isEmpty) {
      return _notFound(
        'getJeepneyByDriver',
        'Driver ID is missing.',
      );
    }

    Object? parseError;
    StackTrace? parseStackTrace;

    FirestoreResult<Jeepney>? parseDoc(
      DocumentSnapshot<Map<String, dynamic>> doc,
      String source,
    ) {
      try {
        debugPrint('[FirestoreService] Found jeepney by $source');

        return FirestoreResult<Jeepney>.success(
          data: Jeepney.fromFirestore(doc),
          message: 'Jeepney loaded successfully.',
        );
      } catch (e, stackTrace) {
        parseError ??= e;
        parseStackTrace ??= stackTrace;

        debugPrint('[FirestoreService] Error parsing jeepney from $source: $e');

        return null;
      }
    }

    Future<FirestoreResult<Jeepney>?> queryJeepney({
      required String field,
      required String value,
      required String source,
    }) async {
      final snapshot = await _db
          .collection('jeeps')
          .where(field, isEqualTo: value)
          .limit(1)
          .get();

      if (snapshot.docs.isEmpty) {
        return null;
      }

      return parseDoc(snapshot.docs.first, source);
    }

    try {
      final byAssignedDriverUid = await queryJeepney(
        field: 'assignedDriver',
        value: cleanDriverId,
        source: 'assignedDriver field using Firebase UID',
      );

      if (byAssignedDriverUid != null) {
        return byAssignedDriverUid;
      }

      final byDriverIdUid = await queryJeepney(
        field: 'driverId',
        value: cleanDriverId,
        source: 'driverId field using Firebase UID',
      );

      if (byDriverIdUid != null) {
        return byDriverIdUid;
      }

      DocumentSnapshot<Map<String, dynamic>>? driverDoc;

      final directDriverDoc =
          await _db.collection('driver').doc(cleanDriverId).get();

      if (directDriverDoc.exists) {
        driverDoc = directDriverDoc;
      } else {
        driverDoc = await _getCurrentDriverDocument();
      }

      if (driverDoc != null && driverDoc.exists) {
        final driverData = driverDoc.data() ?? <String, dynamic>{};

        final assignedJeepneyId =
            _toStringOrNull(driverData['assignedJeepneyId']) ??
                _toStringOrNull(driverData['assignedJeepId']);

        debugPrint(
          '[FirestoreService] Driver doc found: ${driverDoc.id}, assignedJeepneyId=$assignedJeepneyId',
        );

        if (assignedJeepneyId != null && assignedJeepneyId.isNotEmpty) {
          final jeepneyById =
              await _db.collection('jeeps').doc(assignedJeepneyId).get();

          if (jeepneyById.exists) {
            final result = parseDoc(
              jeepneyById,
              'driver.assignedJeepneyId',
            );

            if (result != null) {
              return result;
            }
          }
        }
      }

      final driverDocIdResult = await getCurrentDriverDocIdResult();
      final driverDocId = driverDocIdResult.data;

      if (driverDocId != null && driverDocId.isNotEmpty) {
        final byDriverDocIdField = await queryJeepney(
          field: 'driverId',
          value: driverDocId,
          source: 'driverId field using driver document ID',
        );

        if (byDriverDocIdField != null) {
          return byDriverDocIdField;
        }

        final byAssignedDriverDocId = await queryJeepney(
          field: 'assignedDriver',
          value: driverDocId,
          source: 'assignedDriver field using driver document ID',
        );

        if (byAssignedDriverDocId != null) {
          return byAssignedDriverDocId;
        }
      }

      if (parseError != null && parseStackTrace != null) {
        return _failure(
          'getJeepneyByDriver parse jeepney document',
          parseError!,
          parseStackTrace!,
        );
      }

      return _notFound(
        'getJeepneyByDriver',
        'No jeepney assignment was found for this driver.',
      );
    } catch (e, stackTrace) {
      return _failure('getJeepneyByDriver', e, stackTrace);
    }
  }

  // ---------------------------------------------------------------------------
  // DAILY TRIP SCHEDULE ASSIGNMENT
  // ---------------------------------------------------------------------------

  /// Returns today's date as YYYY-MM-DD string (matching admin's _todayDateKey)
  static String getTodayDateKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  static String _todayDateKey() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  /// Sanitize a string for use as a Firestore document ID
  /// (matches admin's _safeFirestoreId)
  static String safeFirestoreId(String value) {
    final sanitized = value.trim().replaceAll(RegExp(r'[/#?\[\]]'), '_');
    return sanitized.isEmpty ? 'unknown' : sanitized;
  }

  static String _safeFirestoreId(String value) => safeFirestoreId(value);

  static bool _isTerminalCashBookingData(
    Map<String, dynamic> waitingData,
    Map<String, dynamic>? passengerData,
  ) {
    String read(String key) {
      final passengerValue = passengerData?[key]?.toString().trim() ?? '';
      if (passengerValue.isNotEmpty) return passengerValue;
      return waitingData[key]?.toString().trim() ?? '';
    }

    final paymentMethod = read('paymentMethod').toLowerCase();
    final anonymousCash = waitingData['anonymousCash'] == true ||
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

  static List<String> _rfidLookupCandidates(String value) {
    final candidates = <String>{};

    for (final rawPart in value.split(RegExp(r'[|,;]'))) {
      final compact = rawPart.replaceAll(RegExp(r'[\r\n\t ]+'), '').trim();
      final alphanumeric = compact.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
      candidates.addAll([
        compact,
        compact.toUpperCase(),
        compact.toLowerCase(),
        alphanumeric,
        alphanumeric.toUpperCase(),
        alphanumeric.toLowerCase(),
      ]);

      BigInt? numberValue;
      if (alphanumeric.isNotEmpty && RegExp(r'^\d+$').hasMatch(alphanumeric)) {
        numberValue = BigInt.tryParse(alphanumeric);
      } else if (alphanumeric.isNotEmpty &&
          RegExp(r'^[0-9A-Fa-f]+$').hasMatch(alphanumeric)) {
        numberValue = BigInt.tryParse(alphanumeric, radix: 16);
      }

      if (numberValue != null) {
        final decimal = numberValue.toString();
        final hex = numberValue.toRadixString(16);
        candidates.addAll([
          decimal,
          decimal.padLeft(10, '0'),
          hex,
          hex.toUpperCase(),
          hex.padLeft(8, '0'),
          hex.padLeft(8, '0').toUpperCase(),
        ]);
      }

      final normalizedHex =
          alphanumeric.length.isOdd ? '0$alphanumeric' : alphanumeric;
      if (normalizedHex.length >= 2 &&
          RegExp(r'^[0-9A-Fa-f]+$').hasMatch(normalizedHex)) {
        final reversedHex = <String>[];
        for (var index = normalizedHex.length; index > 0; index -= 2) {
          reversedHex.add(normalizedHex.substring(index - 2, index));
        }
        final reversed = reversedHex.join();
        final reversedNumber = BigInt.tryParse(reversed, radix: 16);
        candidates.addAll([
          reversed,
          reversed.toUpperCase(),
          if (reversedNumber != null) reversedNumber.toString(),
        ]);
      }
    }

    return candidates.where((candidate) => candidate.isNotEmpty).toList();
  }

  static String _rfidComparable(String value) {
    return value.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').trim().toUpperCase();
  }

  static Future<QueryDocumentSnapshot<Map<String, dynamic>>?>
      _findCommuterByRfidTag(String scannedRfid) async {
    final scannedCandidates = _rfidLookupCandidates(scannedRfid)
        .map(_rfidComparable)
        .where((candidate) => candidate.isNotEmpty)
        .toSet();

    for (final candidate in scannedCandidates) {
      final exactSnapshot = await _db
          .collection('commuters')
          .where('rfidCard', isEqualTo: candidate)
          .limit(1)
          .get();
      if (exactSnapshot.docs.isNotEmpty) {
        return exactSnapshot.docs.first;
      }
    }

    final commuterSnapshot = await _db
        .collection('commuters')
        .where('rfidCard', isGreaterThan: '')
        .limit(500)
        .get();
    debugPrint(
      '[FirestoreService] RFID fallback comparing against '
      '${commuterSnapshot.docs.length} stored commuter RFID card(s).',
    );

    for (final doc in commuterSnapshot.docs) {
      final storedRfid = doc.data()['rfidCard']?.toString() ?? '';
      final storedCandidates = _rfidLookupCandidates(storedRfid)
          .map(_rfidComparable)
          .where((candidate) => candidate.isNotEmpty)
          .toSet();
      if (storedCandidates.intersection(scannedCandidates).isNotEmpty) {
        return doc;
      }
    }

    return null;
  }

  /// Get today's driver assignment from trip_schedule_driver_assignments.
  ///
  /// The document is stored with ID format: {today}_{driverDocId}
  /// Returns null if no daily assignment exists for today.
  static Future<Map<String, dynamic>?> getTodayDriverAssignment(
    String driverDocId,
  ) async {
    try {
      final today = _todayDateKey();
      final assignmentDocId = '${today}_${_safeFirestoreId(driverDocId)}';

      final doc = await _db
          .collection('trip_schedule_driver_assignments')
          .doc(assignmentDocId)
          .get();

      if (doc.exists) {
        debugPrint(
          '[FirestoreService] Found today assignment for '
          '$driverDocId: ${doc.data()}',
        );
        return doc.data();
      }

      debugPrint(
        '[FirestoreService] No today assignment for $driverDocId',
      );
      return null;
    } catch (e) {
      debugPrint(
        '[FirestoreService] Error fetching today assignment: $e',
      );
      return null;
    }
  }

  /// Fetch today's trip schedule for a given jeepney ID.
  /// Returns the trip schedule document data with id, or null if not found.
  static Future<Map<String, dynamic>?> getTodayTripSchedule(
    String jeepneyId,
  ) async {
    try {
      final today = _todayDateKey();
      final schedules = await getTodayTripSchedules(jeepneyId);
      if (schedules.isEmpty) return null;

      final now = DateTime.now();
      final selectableSchedules =
          schedules.where((data) => !_isCompletedSchedule(data)).toList();

      if (selectableSchedules.isEmpty) return null;

      final active = selectableSchedules.where((data) {
        final status = data['status']?.toString().trim().toLowerCase() ?? '';
        return status == 'active' ||
            status == 'ontrip' ||
            status == 'on-trip' ||
            status == 'on trip' ||
            data['isOnTrip'] == true ||
            data['onTrip'] == true;
      }).toList();
      if (active.isNotEmpty) return active.first;

      selectableSchedules.sort((a, b) {
        final aTime = _scheduleDateTime(data: a, fallbackDate: today);
        final bTime = _scheduleDateTime(data: b, fallbackDate: today);
        if (aTime != null && bTime != null) {
          final aDiff = aTime.difference(now).abs();
          final bDiff = bTime.difference(now).abs();
          final diffCompare = aDiff.compareTo(bDiff);
          if (diffCompare != 0) return diffCompare;
          return aTime.compareTo(bTime);
        }
        if (aTime != null) return -1;
        if (bTime != null) return 1;
        final aOrder = _intValue(a['scheduleOrder']) ?? 0;
        final bOrder = _intValue(b['scheduleOrder']) ?? 0;
        return aOrder.compareTo(bOrder);
      });

      return selectableSchedules.first;
    } catch (e) {
      debugPrint('[FirestoreService] Error fetching today trip schedule: $e');
      return null;
    }
  }

  /// Fetch all of today's trip schedules for a given jeepney ID.
  static Future<List<Map<String, dynamic>>> getTodayTripSchedules(
    String jeepneyId,
  ) async {
    try {
      final cleanJeepneyId = jeepneyId.trim();
      if (cleanJeepneyId.isEmpty) return [];

      final today = _todayDateKey();
      final snapshot = await _db
          .collection('trip_schedules')
          .where('scheduleDate', isEqualTo: today)
          .where('jeepneyId', isEqualTo: cleanJeepneyId)
          .get();

      final schedules =
          snapshot.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList()
            ..sort((a, b) {
              final aTime = _scheduleDateTime(data: a, fallbackDate: today);
              final bTime = _scheduleDateTime(data: b, fallbackDate: today);
              if (aTime != null && bTime != null) return aTime.compareTo(bTime);
              if (aTime != null) return -1;
              if (bTime != null) return 1;
              final aOrder = _intValue(a['scheduleOrder']) ?? 0;
              final bOrder = _intValue(b['scheduleOrder']) ?? 0;
              return aOrder.compareTo(bOrder);
            });

      return schedules;
    } catch (e) {
      debugPrint('[FirestoreService] Error fetching today trip schedules: $e');
      return [];
    }
  }

  static String _scheduleStationKey(Map<String, dynamic> data) {
    final raw = _firstNonEmpty([
      data['station'],
      data['stationLabel'],
      data['originTerminal'],
      data['startTerminal'],
      data['terminal'],
    ]);
    final normalized = raw.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (normalized.contains('lucban')) return 'lucban';
    if (normalized.contains('stacruz') || normalized.contains('santacruz')) {
      return 'stacruz';
    }
    return normalized;
  }

  static Future<FirestoreResult<void>> openNextScheduleBookingAfterTripStart({
    required Map<String, dynamic> startedSchedule,
  }) async {
    try {
      final startedScheduleId = _firstNonEmpty([
        startedSchedule['id'],
        startedSchedule['tripId'],
        startedSchedule['tripScheduleId'],
      ]);
      final scheduleDate = _firstNonEmpty([
        startedSchedule['scheduleDate'],
        startedSchedule['tripDate'],
        _todayDateKey(),
      ]);
      final station = _scheduleStationKey(startedSchedule);
      final startedScheduledAt = _scheduleDateTime(
        data: startedSchedule,
        fallbackDate: scheduleDate,
      );
      if (startedScheduleId.isEmpty ||
          scheduleDate.isEmpty ||
          station.isEmpty ||
          startedScheduledAt == null) {
        return const FirestoreResult<void>.success(
          message: 'No next schedule booking window update was needed.',
        );
      }

      final now = DateTime.now();

      final snapshot = await _db
          .collection('trip_schedules')
          .where('scheduleDate', isEqualTo: scheduleDate)
          .get();

      final candidates = snapshot.docs
          .map((doc) => {'id': doc.id, ...doc.data()})
          .where((data) {
        if (_firstNonEmpty([data['id']]) == startedScheduleId) {
          return false;
        }
        if (_scheduleStationKey(data) != station) return false;
        if (_isFinalTripScheduleData(data) || _isActiveTripData(data)) {
          return false;
        }
        final scheduledAt = _scheduleDateTime(
          data: data,
          fallbackDate: scheduleDate,
        );
        return scheduledAt != null && scheduledAt.isAfter(startedScheduledAt);
      }).toList()
        ..sort(
          (a, b) => _compareScheduleDataOrder(
            a,
            b,
            fallbackDate: scheduleDate,
          ),
        );

      if (candidates.isEmpty) {
        return const FirestoreResult<void>.success(
          message: 'No next jeep schedule found for early booking.',
        );
      }

      final nextScheduleId = _firstNonEmpty([candidates.first['id']]);
      if (nextScheduleId.isEmpty) {
        return const FirestoreResult<void>.success(
          message: 'Next jeep schedule was missing an id.',
        );
      }

      final transactionError =
          await _db.runTransaction<String?>((transaction) async {
        final startedRef =
            _db.collection('trip_schedules').doc(startedScheduleId);
        final nextRef = _db.collection('trip_schedules').doc(nextScheduleId);
        final startedDoc = await transaction.get(startedRef);
        final nextDoc = await transaction.get(nextRef);

        if (!startedDoc.exists || !nextDoc.exists) return null;

        final freshStartedData = startedDoc.data() ?? <String, dynamic>{};
        if (!_isActiveTripData(freshStartedData)) return null;

        final freshStartedScheduledAt = _scheduleDateTime(
          data: freshStartedData,
          fallbackDate: scheduleDate,
        );
        if (freshStartedScheduledAt == null) {
          return null;
        }

        final nextData = nextDoc.data() ?? <String, dynamic>{};
        if (_isFinalTripScheduleData(nextData) || _isActiveTripData(nextData)) {
          return null;
        }

        final nextScheduledAt = _scheduleDateTime(
          data: nextData,
          fallbackDate: scheduleDate,
        );
        if (nextScheduledAt == null || !now.isBefore(nextScheduledAt)) {
          return null;
        }

        final currentOpenAt = _bookingOpensAtForSchedule(nextData);
        if (currentOpenAt != null && !now.isBefore(currentOpenAt)) {
          return null;
        }

        final passengerCount =
            _intValue(freshStartedData['passengerCount']) ?? 0;
        final capacity = _capacityFromDataSources([freshStartedData]);
        final isEarlyFullStart = now.isBefore(freshStartedScheduledAt) &&
            capacity > 0 &&
            passengerCount >= capacity;

        if (isEarlyFullStart) {
          transaction.set(
            startedRef,
            {
              'manualStartedEarly': true,
              'manualStartReason': 'capacity_full',
              'earlyStartedAt': FieldValue.serverTimestamp(),
              'earlyStartOriginalScheduledAt':
                  Timestamp.fromDate(freshStartedScheduledAt),
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
        }

        transaction.set(
          nextRef,
          {
            'bookingOpensAt': Timestamp.fromDate(now),
            'earlyBookingReason': isEarlyFullStart
                ? 'previous_jeep_full_started'
                : 'previous_jeep_started',
            'earlyBookingFromTripScheduleId': startedScheduleId,
            'earlyBookingGrantedAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
        return null;
      });

      if (transactionError != null) {
        return FirestoreResult<void>.failure(
          message: transactionError,
          errorCode: FirestoreErrorCode.invalidArgument,
        );
      }

      return const FirestoreResult<void>.success(
        message: 'Next jeep booking window opened.',
      );
    } catch (e, stackTrace) {
      return _failure<void>(
        'openNextScheduleBookingAfterTripStart',
        e,
        stackTrace,
      );
    }
  }

  static Future<FirestoreResult<void>> openNextScheduleBookingAfterFullStart({
    required Map<String, dynamic> startedSchedule,
  }) {
    return openNextScheduleBookingAfterTripStart(
      startedSchedule: startedSchedule,
    );
  }

  static bool _isCompletedSchedule(Map<String, dynamic> data) {
    final status = _firstNonEmpty([
      data['status'],
      data['tripStatus'],
      data['historyStatus'],
    ]).toLowerCase();
    return status == 'completed' ||
        status == 'done' ||
        status == 'finished' ||
        status == 'cancelled' ||
        status == 'canceled' ||
        _isPastScheduledTripWindow(data, fallbackDate: _todayDateKey());
  }

  static bool _isActiveTripData(Map<String, dynamic> data) {
    final status = _firstNonEmpty([
      data['status'],
      data['tripStatus'],
    ]).toLowerCase();
    return status == 'active' ||
        status == 'ontrip' ||
        status == 'on-trip' ||
        status == 'on trip' ||
        data['isOnTrip'] == true ||
        data['onTrip'] == true;
  }

  static bool _isFinalTripScheduleData(Map<String, dynamic> data) {
    final status = _firstNonEmpty([
      data['status'],
      data['tripStatus'],
      data['historyStatus'],
    ]).toLowerCase();
    return status == 'completed' ||
        status == 'done' ||
        status == 'finished' ||
        status == 'cancelled' ||
        status == 'canceled';
  }

  static bool _isBookableScheduleData(Map<String, dynamic> data) {
    return !_isCompletedSchedule(data) &&
        !_isActiveTripData(data) &&
        _isWithinScheduleBookingWindow(data);
  }

  static bool _isWithinScheduleBookingWindow(Map<String, dynamic> data) {
    final fallbackDate = _firstNonEmpty([
      data['scheduleDate'],
      data['tripDate'],
      _todayDateKey(),
    ]);
    final scheduledAt = _scheduleDateTime(
      data: data,
      fallbackDate: fallbackDate,
    );
    if (scheduledAt == null) return false;

    final now = DateTime.now();
    final defaultBookingStartsAt =
        scheduledAt.subtract(const Duration(minutes: 25));
    final customBookingStartsAt = _dateTimeValue(data['bookingOpensAt']);
    final bookingStartsAt = customBookingStartsAt != null &&
            customBookingStartsAt.isBefore(defaultBookingStartsAt)
        ? customBookingStartsAt
        : defaultBookingStartsAt;
    return !now.isBefore(bookingStartsAt) && now.isBefore(scheduledAt);
  }

  static int _capacityFromDataSources(
    Iterable<Map<String, dynamic>> sources,
  ) {
    for (final data in sources) {
      for (final key in const [
        'maxCapacity',
        'capacity',
        'seatingCapacity',
        'maxPassengers',
      ]) {
        final capacity = _intValue(data[key]);
        if (capacity != null && capacity > 0) return capacity;
      }
    }
    return 0;
  }

  static DateTime? _bookingOpensAtForSchedule(Map<String, dynamic> data) {
    final fallbackDate = _firstNonEmpty([
      data['scheduleDate'],
      data['tripDate'],
      _todayDateKey(),
    ]);
    final scheduledAt = _scheduleDateTime(
      data: data,
      fallbackDate: fallbackDate,
    );
    if (scheduledAt == null) return null;

    final defaultBookingStartsAt =
        scheduledAt.subtract(const Duration(minutes: 25));
    final customBookingStartsAt = _dateTimeValue(data['bookingOpensAt']);
    return customBookingStartsAt != null &&
            customBookingStartsAt.isBefore(defaultBookingStartsAt)
        ? customBookingStartsAt
        : defaultBookingStartsAt;
  }

  static int _compareScheduleDataOrder(
    Map<String, dynamic> a,
    Map<String, dynamic> b, {
    required String fallbackDate,
  }) {
    final aTime = _scheduleDateTime(data: a, fallbackDate: fallbackDate);
    final bTime = _scheduleDateTime(data: b, fallbackDate: fallbackDate);
    if (aTime != null && bTime != null) return aTime.compareTo(bTime);
    if (aTime != null) return -1;
    if (bTime != null) return 1;
    final aOrder = _intValue(a['scheduleOrder']) ?? 0;
    final bOrder = _intValue(b['scheduleOrder']) ?? 0;
    return aOrder.compareTo(bOrder);
  }

  static Future<FirestoreResult<void>> requestAssignedTripCancellation({
    required Map<String, dynamic> schedule,
    required String reason,
  }) async {
    try {
      final tripId = _firstNonEmpty([schedule['id'], schedule['tripId']]);
      if (tripId.isEmpty) {
        return const FirestoreResult<void>.failure(
          message: 'Trip schedule is missing.',
          errorCode: FirestoreErrorCode.invalidArgument,
        );
      }

      final driverResult = await getCurrentDriverDocIdResult();
      if (!driverResult.success || (driverResult.data ?? '').isEmpty) {
        return FirestoreResult<void>.failure(
          message: driverResult.message,
          errorCode: driverResult.errorCode,
        );
      }

      final driverId = driverResult.data!.trim();
      final cleanReason = reason.trim();
      if (cleanReason.isEmpty) {
        return const FirestoreResult<void>.failure(
          message: 'Cancellation reason is required.',
          errorCode: FirestoreErrorCode.invalidArgument,
        );
      }

      final transactionError =
          await _db.runTransaction<String?>((transaction) async {
        final scheduleRef = _db.collection('trip_schedules').doc(tripId);
        final scheduleDoc = await transaction.get(scheduleRef);
        if (!scheduleDoc.exists) {
          return 'This trip schedule no longer exists.';
        }

        final scheduleData = scheduleDoc.data() ?? <String, dynamic>{};
        if (_isFinalTripScheduleData(scheduleData)) {
          return 'This trip schedule is already final and cannot be cancelled.';
        }

        final requestStatus = _firstNonEmpty([
          scheduleData['cancellationRequestStatus'],
        ]).toLowerCase();
        if (requestStatus == 'pending') {
          return 'A cancellation request for this trip is already pending dispatcher review.';
        }

        final assignedDriverId = _firstNonEmpty([
          scheduleData['driverId'],
          scheduleData['assignedDriver'],
          scheduleData['assignedDriverId'],
        ]);
        if (assignedDriverId.isNotEmpty && assignedDriverId != driverId) {
          return 'Only the assigned driver can cancel this trip schedule.';
        }

        final jeepneyId = _firstNonEmpty([
          scheduleData['jeepneyId'],
          scheduleData['assignedJeepneyId'],
          scheduleData['assignedJeepId'],
          schedule['jeepneyId'],
        ]);
        final scheduleDate = _firstNonEmpty([
          scheduleData['scheduleDate'],
          schedule['scheduleDate'],
          _todayDateKey(),
        ]);
        final requestId =
            '${_safeFirestoreId(tripId)}_${_safeFirestoreId(driverId)}';
        final requestRef =
            _db.collection('trip_cancellation_requests').doc(requestId);
        final requestDoc = await transaction.get(requestRef);
        if (requestDoc.exists) {
          final existingStatus = _firstNonEmpty([
            requestDoc.data()?['status'],
          ]).toLowerCase();
          if (existingStatus == 'pending') {
            return 'A cancellation request for this trip is already pending dispatcher review.';
          }
        }

        final driverName = _firstNonEmpty([
          scheduleData['driverName'],
          scheduleData['assignedDriverName'],
          schedule['driverName'],
          schedule['assignedDriverName'],
        ]);
        final plateNumber = _firstNonEmpty([
          scheduleData['plateNumber'],
          schedule['plateNumber'],
          jeepneyId,
        ]);
        final scheduleTime = _firstNonEmpty([
          scheduleData['scheduleTime'],
          scheduleData['departureTime'],
          schedule['scheduleTime'],
          schedule['departureTime'],
        ]);
        final station = _firstNonEmpty([
          scheduleData['station'],
          scheduleData['stationLabel'],
          schedule['station'],
          schedule['stationLabel'],
        ]);
        final routeId = _firstNonEmpty([
          scheduleData['routeId'],
          scheduleData['route'],
          schedule['routeId'],
          schedule['route'],
        ]);

        transaction.set(
            requestRef,
            {
              'id': requestId,
              'status': 'pending',
              'tripScheduleId': tripId,
              'scheduleDate': scheduleDate,
              'scheduleTime': scheduleTime,
              'station': station,
              'routeId': routeId,
              'jeepneyId': jeepneyId,
              'plateNumber': plateNumber,
              'driverId': _firstNonEmpty([assignedDriverId, driverId]),
              'driverName': driverName,
              'reason': cleanReason,
              'requestedBy': 'driver',
              'requestedByDriverId': driverId,
              'requestedAt': FieldValue.serverTimestamp(),
              'reviewedBy': null,
              'reviewedAt': null,
              'reviewDecision': null,
              'reviewReason': null,
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true));

        transaction.set(
            scheduleRef,
            {
              'cancellationRequestStatus': 'pending',
              'cancellationRequestId': requestId,
              'cancellationRequestedAt': FieldValue.serverTimestamp(),
              'cancellationRequestedByDriverId': driverId,
              'cancellationReason': cleanReason,
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true));

        transaction.set(_db.collection('notifications').doc(), {
          'type': 'trip_cancellation_request',
          'targetRole': 'dispatcher',
          if (station.isNotEmpty) 'station': station,
          'title': 'Trip cancellation request',
          'message':
              '${driverName.isEmpty ? 'A driver' : driverName} requested to cancel ${scheduleTime.isEmpty ? 'a trip' : scheduleTime}.',
          'tripScheduleId': tripId,
          'cancellationRequestId': requestId,
          'driverId': driverId,
          'jeepneyId': jeepneyId,
          'isRead': false,
          'createdAt': FieldValue.serverTimestamp(),
        });

        return null;
      });

      if (transactionError != null) {
        return FirestoreResult<void>.failure(
          message: transactionError,
          errorCode: FirestoreErrorCode.invalidArgument,
        );
      }

      return const FirestoreResult<void>.success(
        message: 'Cancellation request sent to dispatcher for review.',
      );
    } catch (e, stackTrace) {
      return _failure<void>('requestAssignedTripCancellation', e, stackTrace);
    }
  }

  static bool _isPastScheduledTripWindow(
    Map<String, dynamic> data, {
    required String fallbackDate,
  }) {
    final scheduledAt = _scheduleDateTime(
      data: data,
      fallbackDate: fallbackDate,
    );
    if (scheduledAt == null) return false;

    return DateTime.now().isAfter(scheduledAt.add(const Duration(hours: 3)));
  }

  static DateTime? _scheduleDateTime({
    required Map<String, dynamic> data,
    required String fallbackDate,
  }) {
    final scheduledAt = data['scheduledAt'];
    if (scheduledAt is Timestamp) return scheduledAt.toDate();
    if (scheduledAt is DateTime) return scheduledAt;
    if (scheduledAt is String) {
      final parsed = DateTime.tryParse(scheduledAt);
      if (parsed != null) return parsed;
    }

    final scheduleDate = _firstNonEmpty([
      data['scheduleDate'],
      data['tripDate'],
      fallbackDate,
    ]);
    final scheduleTime = _firstNonEmpty([
      data['scheduleTime'],
      data['departureTime'],
      data['tripTime'],
    ]);
    final dateMatch =
        RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(scheduleDate);
    final time = _parseScheduleTime(scheduleTime);
    if (dateMatch == null || time == null) return null;

    return DateTime(
      int.parse(dateMatch.group(1)!),
      int.parse(dateMatch.group(2)!),
      int.parse(dateMatch.group(3)!),
      time[0],
      time[1],
    );
  }

  static List<int>? _parseScheduleTime(String value) {
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
      return [hour, minute];
    }

    final twentyFourHourMatch =
        RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(normalized);
    if (twentyFourHourMatch != null) {
      final hour = int.parse(twentyFourHourMatch.group(1)!);
      final minute = int.parse(twentyFourHourMatch.group(2)!);
      if (hour > 23 || minute > 59) return null;
      return [hour, minute];
    }

    return null;
  }

  static int? _intValue(dynamic value) {
    if (value is int) return value;
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

  static double _positiveFare(double value, double fallback) {
    if (value > 0) return value;
    return fallback > 0 ? fallback : 0;
  }

  static DateTime? _dateTimeValue(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  static bool _hasActiveApprovedDiscount(Map<String, dynamic> commuterData) {
    final status =
        commuterData['discountStatus']?.toString().trim().toLowerCase() ?? '';
    final expiresAt = _dateTimeValue(commuterData['discountExpiresAt']);
    return status == 'approved' &&
        expiresAt != null &&
        expiresAt.isAfter(DateTime.now());
  }

  static Map<String, dynamic> _fareSnapshot({
    required String paymentMethod,
    required String fareType,
    required bool discountApplied,
    required String discountType,
    required String discountSource,
    required String discountStatusAtBooking,
    required double regularFare,
    required double chargedFare,
    dynamic discountExpiresAt,
  }) {
    final safeRegular = _positiveFare(regularFare, chargedFare);
    final safeCharged = _positiveFare(chargedFare, safeRegular);
    return {
      'fare': safeCharged,
      'chargedFare': safeCharged,
      'regularFare': safeRegular,
      'discountAmount': discountApplied
          ? (safeRegular - safeCharged).clamp(0, safeRegular)
          : 0,
      'fareType': fareType,
      'discountApplied': discountApplied,
      'discountType': discountType,
      'discountSource': discountSource,
      'discountStatusAtBooking': discountStatusAtBooking,
      if (discountExpiresAt != null)
        'discountExpiresAtAtBooking': discountExpiresAt,
      'paymentMethod': paymentMethod,
    };
  }

  static Map<String, dynamic> _cashFareSnapshot({
    required String fareType,
    required double regularFare,
    required double discountedFare,
    required double chargedFare,
  }) {
    final normalizedType = fareType.trim().toLowerCase();
    final isDiscounted = normalizedType != 'regular';
    return _fareSnapshot(
      paymentMethod: 'cash',
      fareType: isDiscounted ? 'discounted' : 'regular',
      discountApplied: isDiscounted,
      discountType: isDiscounted ? 'manual_cash' : 'none',
      discountSource: isDiscounted ? 'driver_manual_cash' : 'none',
      discountStatusAtBooking: isDiscounted ? 'manual_cash' : 'none',
      regularFare: regularFare,
      chargedFare: chargedFare > 0
          ? chargedFare
          : isDiscounted
              ? _positiveFare(discountedFare, regularFare)
              : regularFare,
    );
  }

  static Map<String, dynamic> _rfidFareSnapshot({
    required Map<String, dynamic> commuterData,
    required double regularFare,
    required double discountedFare,
  }) {
    final rawStatus =
        commuterData['discountStatus']?.toString().trim().toLowerCase() ?? '';
    final discountType =
        commuterData['discountType']?.toString().trim().toLowerCase() ?? '';
    final expiresAt = commuterData['discountExpiresAt'];
    final hasDiscount = _hasActiveApprovedDiscount(commuterData);
    final chargedFare = hasDiscount
        ? _positiveFare(discountedFare, regularFare)
        : _positiveFare(regularFare, discountedFare);
    final statusAtBooking = hasDiscount
        ? 'approved'
        : rawStatus == 'approved'
            ? 'expired'
            : rawStatus.isEmpty
                ? 'none'
                : rawStatus;

    return _fareSnapshot(
      paymentMethod: 'rfid',
      fareType:
          hasDiscount && discountType.isNotEmpty ? discountType : 'regular',
      discountApplied: hasDiscount,
      discountType: hasDiscount ? discountType : 'none',
      discountSource: hasDiscount ? 'commuter_profile' : 'none',
      discountStatusAtBooking: statusAtBooking,
      regularFare: regularFare,
      chargedFare: chargedFare,
      discountExpiresAt: expiresAt,
    );
  }

  static bool _rfidStillMatchesCommuter(
    Map<String, dynamic> commuterData,
    String scannedRfid,
  ) {
    final storedRfid = commuterData['rfidCard']?.toString() ?? '';
    if (storedRfid.trim().isEmpty || scannedRfid.trim().isEmpty) return false;
    final stored =
        _rfidLookupCandidates(storedRfid).map(_rfidComparable).toSet();
    final scanned =
        _rfidLookupCandidates(scannedRfid).map(_rfidComparable).toSet();
    return stored.intersection(scanned).isNotEmpty;
  }

  /// Mark a cash-paying passenger as cash collected in the trip schedule.
  /// Creates a fare_transactions entry and credits the driver's earnings.
  /// Uses WriteBatch for atomicity.
  static Future<bool> markCashCollected(
    String tripScheduleId,
    String commuterId,
  ) async {
    try {
      final doc =
          await _db.collection('trip_schedules').doc(tripScheduleId).get();
      if (!doc.exists) return false;
      final data = doc.data()!;
      final passengers = List<Map<String, dynamic>>.from(
        (data['bookedPassengers'] as List<dynamic>?)
                ?.cast<Map<String, dynamic>>() ??
            [],
      );

      Map<String, dynamic>? matchedPassenger;
      var matchIndex = -1;
      for (var i = 0; i < passengers.length; i++) {
        if (passengers[i]['commuterId'] == commuterId) {
          matchedPassenger = passengers[i];
          matchIndex = i;
          break;
        }
      }
      if (matchedPassenger == null) return false;

      final fare = (matchedPassenger['fare'] as num?)?.toDouble() ?? 0;
      final paymentMethod =
          (matchedPassenger['paymentMethod'] as String?) ?? 'cash';
      final commuterName = (matchedPassenger['commuterName'] as String?) ?? '';
      final jeepneyId = (data['jeepneyId'] as String?) ?? '';
      final plateNumber = (data['plateNumber'] as String?) ?? '';
      final scheduleDate = (data['scheduleDate'] as String?) ?? '';

      final driverId = await getCurrentDriverDocId();

      final batch = _db.batch();

      passengers[matchIndex]['cashCollected'] = true;
      passengers[matchIndex]['cashCollectedAt'] = FieldValue.serverTimestamp();

      batch.update(
        _db.collection('trip_schedules').doc(tripScheduleId),
        {
          'bookedPassengers': passengers,
          'updatedAt': FieldValue.serverTimestamp(),
        },
      );

      final txnRef = _db.collection('fare_transactions').doc();
      batch.set(txnRef, {
        'commuterId': commuterId,
        'commuterName': commuterName,
        'driverId': driverId ?? '',
        'type': 'fare',
        'amount': fare,
        'paymentMethod': paymentMethod,
        'fareType': matchedPassenger['fareType'] ?? 'regular',
        'discountApplied': matchedPassenger['discountApplied'] == true,
        'discountType': matchedPassenger['discountType'] ?? 'none',
        'discountSource': matchedPassenger['discountSource'] ?? 'none',
        'discountStatusAtBooking':
            matchedPassenger['discountStatusAtBooking'] ?? 'none',
        'regularFare': matchedPassenger['regularFare'] ?? fare,
        'chargedFare': matchedPassenger['chargedFare'] ?? fare,
        'discountAmount': matchedPassenger['discountAmount'] ?? 0,
        'tripScheduleId': tripScheduleId,
        'scheduleDate': scheduleDate,
        'jeepneyId': jeepneyId,
        'plateNumber': plateNumber,
        'collected': true,
        'collectedAt': FieldValue.serverTimestamp(),
        'claimed': true,
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (driverId != null) {
        final earningsRef = _db.collection('driver_earnings').doc(driverId);
        batch.set(
            earningsRef,
            {
              'driverId': driverId,
              'balance': FieldValue.increment(fare),
              'lifetimeEarned': FieldValue.increment(fare),
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true));
      }

      await batch.commit();
      return true;
    } catch (e) {
      debugPrint('[FirestoreService] Error marking cash collected: $e');
      return false;
    }
  }

  /// Book a passenger directly from the driver's assigned schedule.
  ///
  /// This is the driver-side home for the old dispatcher live-monitoring
  /// booking transaction. Keep the written fields compatible with the existing
  /// passenger list, commuter drop-off, fare, and earnings flows.
  static Future<FirestoreResult<void>> bookCommuterOnAssignedSchedule({
    required Map<String, dynamic> trip,
    String commuterId = '',
    String commuterName = '',
    String passengerName = 'Cash passenger',
    String rfidTag = '',
    required double fare,
    double regularFare = 0,
    double discountedFare = 0,
    String fareType = 'regular',
    required String paymentMethod,
    String? driverId,
    String? driverName,
  }) async {
    final cleanPaymentMethod = paymentMethod.trim().toLowerCase();
    var cleanRfidTag = rfidTag.replaceAll(RegExp(r'[\r\n\t ]+'), '').trim();
    final cleanFareType = fareType.trim().toLowerCase();
    final baseRegularFare = _positiveFare(regularFare, fare);
    final baseDiscountedFare = _positiveFare(discountedFare, baseRegularFare);
    final scheduleDate =
        _firstNonEmpty([trip['scheduleDate'], _todayDateKey()]);
    final tripId = _firstNonEmpty([trip['id']]);
    var cleanCommuterId = commuterId.trim();
    var cleanCommuterName = commuterName.trim();
    var isAnonymousCash = cleanPaymentMethod != 'rfid';

    if (tripId.isEmpty) {
      return const FirestoreResult.failure(
        message:
            'This trip is no longer available. Please refresh and try again.',
        errorCode: FirestoreErrorCode.invalidArgument,
      );
    }
    if (cleanPaymentMethod == 'rfid' && cleanRfidTag.isEmpty) {
      return const FirestoreResult.failure(
        message: 'RFID payment requires scanning the card first.',
        errorCode: FirestoreErrorCode.invalidArgument,
      );
    }

    try {
      final preflightJeepneyId = _firstNonEmpty([
        trip['jeepneyId'],
        trip['assignedJeepneyId'],
        trip['assignedJeepId'],
      ]);
      if (scheduleDate.isNotEmpty && preflightJeepneyId.isNotEmpty) {
        final sameDaySnapshot = await _db
            .collection('trip_schedules')
            .where('scheduleDate', isEqualTo: scheduleDate)
            .where('jeepneyId', isEqualTo: preflightJeepneyId)
            .get();
        final nearestBookable = sameDaySnapshot.docs
            .map((doc) => {'id': doc.id, ...doc.data()})
            .where(_isBookableScheduleData)
            .toList()
          ..sort(
            (a, b) => _compareScheduleDataOrder(
              a,
              b,
              fallbackDate: scheduleDate,
            ),
          );
        if (nearestBookable.isNotEmpty &&
            _firstNonEmpty([nearestBookable.first['id']]) != tripId) {
          return const FirestoreResult<void>.failure(
            message:
                'Booking is only allowed for the nearest upcoming schedule.',
            errorCode: FirestoreErrorCode.invalidArgument,
          );
        }
      }

      if (cleanPaymentMethod == 'rfid') {
        final rfidCandidates = _rfidLookupCandidates(cleanRfidTag);
        debugPrint(
          '[FirestoreService] RFID booking lookup: '
          '${rfidCandidates.length} candidate(s), scanned '
          '${cleanRfidTag.length} chars',
        );
        final commuterDoc = await _findCommuterByRfidTag(cleanRfidTag);

        if (commuterDoc == null) {
          return const FirestoreResult.failure(
            message: 'No commuter account owns this RFID card.',
            errorCode: FirestoreErrorCode.notFound,
          );
        }
        final commuterData = commuterDoc.data();
        debugPrint(
          '[FirestoreService] RFID booking matched commuter ${commuterDoc.id}.',
        );
        final rfidStatus =
            commuterData['rfidStatus']?.toString().trim() ?? 'active';
        final rfidActive = commuterData['rfidActive'] as bool? ?? true;
        if (!rfidActive ||
            rfidStatus == 'deactivated' ||
            rfidStatus == 'blocked' ||
            rfidStatus == 'deactivation_pending') {
          return const FirestoreResult.failure(
            message:
                'This RFID card is not active. Please ask the commuter to use a reassigned card.',
            errorCode: FirestoreErrorCode.permissionDenied,
          );
        }
        cleanCommuterId = commuterDoc.id;
        cleanRfidTag = _firstNonEmpty([commuterData['rfidCard'], cleanRfidTag]);
        cleanCommuterName = _firstNonEmpty([
          '${commuterData['firstName'] ?? ''} ${commuterData['lastName'] ?? ''}',
          commuterData['displayName'],
          commuterData['name'],
          cleanCommuterId,
        ]);
        isAnonymousCash = false;
      } else {
        cleanCommuterId =
            'cash_${_safeFirestoreId(tripId)}_${DateTime.now().microsecondsSinceEpoch}';
        cleanCommuterName = passengerName.trim().isEmpty
            ? 'Cash passenger'
            : passengerName.trim();
      }

      final transactionError =
          await _db.runTransaction<String?>((transaction) async {
        final scheduleRef = _db.collection('trip_schedules').doc(tripId);
        final scheduleDoc = await transaction.get(scheduleRef);
        if (!scheduleDoc.exists) {
          return 'This trip is no longer available. Please refresh and try again.';
        }

        final scheduleData = scheduleDoc.data() ?? <String, dynamic>{};
        if (_isActiveTripData(scheduleData)) {
          return 'Booking is disabled because this jeepney is already on trip.';
        }
        if (!_isWithinScheduleBookingWindow(scheduleData)) {
          return 'Booking is available only within 25 minutes before the schedule.';
        }

        final jeepneyId = _firstNonEmpty([
          scheduleData['jeepneyId'],
          trip['jeepneyId'],
        ]);
        final locationRef = jeepneyId.isNotEmpty
            ? _db.collection('locations').doc(jeepneyId)
            : null;
        final locationDoc =
            locationRef == null ? null : await transaction.get(locationRef);
        final locationData = locationDoc?.data() ?? <String, dynamic>{};
        if (_isActiveTripData(locationData)) {
          return 'Booking is disabled because this jeepney already left the terminal.';
        }

        DocumentSnapshot<Map<String, dynamic>>? jeepDoc;
        if (jeepneyId.isNotEmpty) {
          jeepDoc =
              await transaction.get(_db.collection('jeeps').doc(jeepneyId));
        }
        final jeepData = jeepDoc?.data() ?? <String, dynamic>{};
        final currentPassengers =
            _intValue(scheduleData['passengerCount']) ?? 0;
        final maxCapacity = _capacityFromDataSources([
          scheduleData,
          locationData,
          jeepData,
        ]);
        if (maxCapacity > 0 && currentPassengers >= maxCapacity) {
          return 'Jeep is full. Start the trip or wait for the next schedule.';
        }

        final nextPassengerCount = currentPassengers + 1;
        if (maxCapacity > 0 && nextPassengerCount > maxCapacity) {
          return 'This booking would exceed the jeep capacity.';
        }
        final reachedCapacity =
            maxCapacity > 0 && nextPassengerCount >= maxCapacity;
        final cleanDriverId = _firstNonEmpty([
          driverId,
          scheduleData['driverId'],
          trip['driverId'],
        ]);
        final cleanDriverName = _firstNonEmpty([
          driverName,
          scheduleData['driverName'],
          trip['driverName'],
          scheduleData['driverFullName'],
          trip['driverFullName'],
          scheduleData['assignedDriverName'],
          trip['assignedDriverName'],
        ]);
        final bookingId =
            '${_safeFirestoreId(tripId)}_${_safeFirestoreId(cleanCommuterId)}';
        final bookingRef = _db.collection('bookings').doc(bookingId);
        final existingBooking = await transaction.get(bookingRef);
        if (existingBooking.exists) {
          return 'This commuter is already booked on this trip.';
        }

        Map<String, dynamic> fareSnapshot;
        if (cleanPaymentMethod == 'rfid') {
          final commuterRef = _db.collection('commuters').doc(cleanCommuterId);
          final commuterDoc = await transaction.get(commuterRef);
          if (!commuterDoc.exists) {
            return 'The commuter account linked to this RFID was not found.';
          }
          final commuterData = commuterDoc.data() ?? <String, dynamic>{};
          if (!_rfidStillMatchesCommuter(commuterData, cleanRfidTag)) {
            return 'This RFID card changed before booking was saved. Please scan again.';
          }
          final rfidStatus =
              commuterData['rfidStatus']?.toString().trim() ?? 'active';
          final rfidActive = commuterData['rfidActive'] as bool? ?? true;
          if (!rfidActive ||
              rfidStatus == 'deactivated' ||
              rfidStatus == 'blocked' ||
              rfidStatus == 'deactivation_pending') {
            return 'This RFID card is not active. Please ask the commuter to use a reassigned card.';
          }
          fareSnapshot = _rfidFareSnapshot(
            commuterData: commuterData,
            regularFare: baseRegularFare,
            discountedFare: baseDiscountedFare,
          );
        } else {
          fareSnapshot = _cashFareSnapshot(
            fareType: cleanFareType,
            regularFare: baseRegularFare,
            discountedFare: baseDiscountedFare,
            chargedFare: fare,
          );
        }
        final chargedFare = (fareSnapshot['chargedFare'] as num).toDouble();

        final shouldChargeWallet = cleanPaymentMethod == 'rfid' &&
            cleanRfidTag.isNotEmpty &&
            chargedFare > 0;
        final walletRef = shouldChargeWallet
            ? _db.collection('commuter_wallets').doc(cleanCommuterId)
            : null;
        final walletDoc =
            walletRef == null ? null : await transaction.get(walletRef);
        final currentBalance =
            walletDoc == null ? 0.0 : _walletBalanceFromDoc(walletDoc);
        if (shouldChargeWallet && currentBalance < chargedFare) {
          return 'Insufficient wallet balance. Current balance is PHP ${currentBalance.toStringAsFixed(2)}, but the fare is PHP ${chargedFare.toStringAsFixed(2)}.';
        }

        final bookedAt = Timestamp.now();
        final scheduleLocation = _scheduledLocationFallback(scheduleData, trip);
        final locationLat = locationData['lat'] is num
            ? (locationData['lat'] as num).toDouble()
            : scheduleLocation?.latitude;
        final locationLng = locationData['lng'] is num
            ? (locationData['lng'] as num).toDouble()
            : scheduleLocation?.longitude;

        final booking = <String, dynamic>{
          'id': bookingId,
          'bookingId': bookingId,
          'commuterId': cleanCommuterId,
          'commuterName': cleanCommuterName,
          'rfidTag': cleanRfidTag.isNotEmpty ? cleanRfidTag : null,
          ...fareSnapshot,
          'paymentMethod': cleanPaymentMethod,
          'waitingCount': 1,
          'passengerCount': 1,
          'status': BookingStatus.onboard,
          'source': 'driver_terminal_booking',
          'bookedBy': 'driver',
          'onBoard': true,
          'onBoardSource': 'driver',
          'onBoardAt': bookedAt,
          'cashCollected': false,
          'anonymousCash': isAnonymousCash,
          'requireDispatcherRebook': false,
          'bookedAt': bookedAt,
        };

        transaction.update(scheduleRef, {
          'passengerCount': nextPassengerCount,
          'bookedPassengers': FieldValue.arrayUnion([booking]),
          if (reachedCapacity) 'bookingClosed': true,
          if (reachedCapacity) 'bookingClosedReason': 'capacity_reached',
          if (reachedCapacity) 'capacityReached': true,
          if (reachedCapacity) 'manualStartEligible': true,
          if (reachedCapacity) 'fullAt': bookedAt,
          'updatedAt': FieldValue.serverTimestamp(),
        });

        transaction.set(
          bookingRef,
          {
            ...booking,
            'id': bookingId,
            'tripScheduleId': tripId,
            'scheduleDate': scheduleDate,
            'jeepneyId': jeepneyId,
            'driverId': cleanDriverId,
            'driverName': cleanDriverName,
            'plateNumber': _firstNonEmpty([
              scheduleData['plateNumber'],
              trip['plateNumber'],
              jeepneyId,
            ]),
            'routeId':
                _firstNonEmpty([scheduleData['routeId'], trip['routeId']]),
            'originTerminal': _firstNonEmpty([
              scheduleData['originTerminal'],
              trip['originTerminal'],
            ]),
            'destinationTerminal': _firstNonEmpty([
              scheduleData['destinationTerminal'],
              trip['destinationTerminal'],
            ]),
            'scheduleTime': _firstNonEmpty([
              scheduleData['scheduleTime'],
              trip['scheduleTime'],
            ]),
            'scheduledAt': scheduleData['scheduledAt'] ?? trip['scheduledAt'],
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );

        transaction.set(
          _db.collection('commuter_waiting_location').doc(cleanCommuterId),
          {
            'commuterId': cleanCommuterId,
            if (cleanCommuterName.isNotEmpty) 'commuterName': cleanCommuterName,
            'jeepneyId': jeepneyId,
            'tripScheduleId': tripId,
            if (locationLat != null) 'lat': locationLat,
            if (locationLng != null) 'lng': locationLng,
            'destinationTerminal': _firstNonEmpty([
              scheduleData['destinationTerminal'],
              trip['destinationTerminal'],
            ]),
            'id': bookingId,
            'bookingId': bookingId,
            'waitingCount': 1,
            'passengerCount': 1,
            'dropOffCount': 1,
            'status': BookingStatus.onboard,
            'paymentMethod': cleanPaymentMethod,
            'anonymousCash': isAnonymousCash,
            'autoDropOffDeductsPassengerCount': !isAnonymousCash,
            'manualPassengerCountRequired': isAnonymousCash,
            'source': 'driver_terminal_booking',
            'bookedBy': 'driver',
            'onBoard': true,
            'onBoardSource': 'driver',
            'onBoardAt': bookedAt,
            'isSharing': false,
            'requireDispatcherRebook': false,
            'timestamp': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );

        if (locationRef != null) {
          final hasLocation =
              locationData['lat'] is num && locationData['lng'] is num;
          final locationUpdate = <String, dynamic>{
            'jeepneyId': jeepneyId,
            'driverId': cleanDriverId,
            if (cleanDriverName.isNotEmpty) 'driverName': cleanDriverName,
            'plateNumber': _firstNonEmpty([
              scheduleData['plateNumber'],
              trip['plateNumber'],
              jeepneyId,
            ]),
            'routeId':
                _firstNonEmpty([scheduleData['routeId'], trip['routeId']]),
            'originTerminal': _firstNonEmpty([
              scheduleData['originTerminal'],
              trip['originTerminal'],
            ]),
            'destinationTerminal': _firstNonEmpty([
              scheduleData['destinationTerminal'],
              trip['destinationTerminal'],
            ]),
            'passengerCount': nextPassengerCount,
            'currentPassengerCount': nextPassengerCount,
            if (maxCapacity > 0) 'capacity': maxCapacity,
            if (reachedCapacity) 'capacityReached': true,
            if (reachedCapacity) 'manualStartEligible': true,
            if (reachedCapacity) 'fullAt': bookedAt,
            'tripScheduleId': tripId,
            'scheduleDate': scheduleDate,
            'scheduleTime': _firstNonEmpty([
              scheduleData['scheduleTime'],
              trip['scheduleTime'],
            ]),
            'scheduledAt': scheduleData['scheduledAt'] ?? trip['scheduledAt'],
            'scheduledVisible': true,
            'visibleFromSchedule': true,
            'passengerUpdatedAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          };
          if (!hasLocation && scheduleLocation != null) {
            locationUpdate['lat'] = scheduleLocation.latitude;
            locationUpdate['lng'] = scheduleLocation.longitude;
            locationUpdate['geoPoint'] = GeoPoint(
              scheduleLocation.latitude,
              scheduleLocation.longitude,
            );
          }
          transaction.set(locationRef, locationUpdate, SetOptions(merge: true));
        }

        if (shouldChargeWallet && walletRef != null) {
          final newBalance = currentBalance - chargedFare;
          transaction.set(
            walletRef,
            {
              'commuterId': cleanCommuterId,
              'balance': newBalance,
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );

          final txnRef = _db.collection('fare_transactions').doc();
          transaction.set(txnRef, {
            'commuterId': cleanCommuterId,
            'commuterName': cleanCommuterName,
            'driverId': cleanDriverId,
            'driverName': cleanDriverName,
            'type': 'fare',
            'amount': chargedFare,
            ...fareSnapshot,
            'paymentMethod': 'rfid',
            'rfidTag': cleanRfidTag,
            'bookingId': bookingId,
            'balanceBefore': currentBalance,
            'balanceAfter': newBalance,
            'tripScheduleId': tripId,
            'scheduleDate': scheduleDate,
            'jeepneyId': jeepneyId,
            'plateNumber': _firstNonEmpty([
              scheduleData['plateNumber'],
              trip['plateNumber'],
              jeepneyId,
            ]),
            'collected': true,
            'claimed': true,
            'createdAt': FieldValue.serverTimestamp(),
          });

          if (cleanDriverId.isNotEmpty) {
            final driverEarningsRef =
                _db.collection('driver_earnings').doc(cleanDriverId);
            transaction.set(
              driverEarningsRef,
              {
                'driverId': cleanDriverId,
                'balance': FieldValue.increment(chargedFare),
                'lifetimeEarned': FieldValue.increment(chargedFare),
                'updatedAt': FieldValue.serverTimestamp(),
              },
              SetOptions(merge: true),
            );
          }
        }

        return null;
      });

      if (transactionError != null) {
        debugPrint('[FirestoreService] RFID/cash booking failed: '
            '$transactionError');
        return FirestoreResult.failure(message: transactionError);
      }

      debugPrint(
        '[FirestoreService] ${cleanPaymentMethod.toUpperCase()} booking saved '
        'for trip $tripId, commuter $cleanCommuterId.',
      );

      return FirestoreResult.success(
        message: cleanPaymentMethod == 'rfid'
            ? 'Booked $cleanCommuterName. RFID fare was resolved from the commuter profile.'
            : 'Booked $cleanCommuterName - PHP ${fare.toStringAsFixed(2)} (Cash).',
      );
    } catch (e, stackTrace) {
      debugPrint('[FirestoreService] Error booking passenger: $e');
      debugPrint('[FirestoreService] Booking stack trace: $stackTrace');
      return FirestoreResult.failure(
        message: userFriendlyMessageForError(e),
        errorCode: _errorCodeFromError(e),
      );
    }
  }

  static double _walletBalanceFromDoc(DocumentSnapshot doc) {
    if (!doc.exists) return 0.0;
    final data = doc.data() as Map<String, dynamic>?;
    if (data == null) return 0.0;
    final balance = data['balance'];
    if (balance is num) return balance.toDouble();
    return 0.0;
  }

  static LatLng? _scheduledLocationFallback(
    Map<String, dynamic> scheduleData,
    Map<String, dynamic> trip,
  ) {
    final origin = _firstNonEmpty([
      scheduleData['originTerminal'],
      trip['originTerminal'],
    ]);
    final destination = _firstNonEmpty([
      scheduleData['destinationTerminal'],
      trip['destinationTerminal'],
    ]);

    return _terminalLocationForLabel(origin) ??
        _terminalLocationForLabel(destination);
  }

  static LatLng? _terminalLocationForLabel(String label) {
    final normalized = label.trim().toLowerCase();
    if (normalized.isEmpty) return null;

    if (normalized.contains('lucban')) {
      return const LatLng(14.1149875, 121.551859375);
    }
    if (normalized.contains('luisiana')) {
      return const LatLng(14.186126, 121.507152);
    }
    if (normalized.contains('sta. cruz') ||
        normalized.contains('sta cruz') ||
        normalized.contains('santa cruz') ||
        normalized.contains('stacruz')) {
      return const LatLng(14.2659625, 121.425578125);
    }

    return null;
  }

  // ---------------------------------------------------------------------------
  // LOCATION STREAMS
  // ---------------------------------------------------------------------------

  static Stream<List<JeepneyLocation>> getJeepneyLocationsStream() {
    return _db
        .collection('locations')
        .where('isOnline', isEqualTo: true)
        .snapshots()
        .map((snapshot) {
      final locations = snapshot.docs
          .map((doc) => JeepneyLocation.fromFirestore(doc))
          .where((location) => location.hasValidPosition)
          .toList();

      locations.sort((a, b) {
        final aTime = a.timestamp;
        final bTime = b.timestamp;

        if (aTime == null && bTime == null) return 0;
        if (aTime == null) return 1;
        if (bTime == null) return -1;

        return bTime.compareTo(aTime);
      });

      return locations;
    });
  }

  static Future<JeepneyLocation?> getJeepneyLocation(String jeepneyId) async {
    final result = await getJeepneyLocationResult(jeepneyId);
    return result.data;
  }

  static Future<FirestoreResult<JeepneyLocation>> getJeepneyLocationResult(
    String jeepneyId,
  ) async {
    try {
      final cleanJeepneyId = jeepneyId.trim();

      if (cleanJeepneyId.isEmpty) {
        return _notFound(
          'getJeepneyLocation',
          'Jeepney ID is missing.',
        );
      }

      final doc = await _db.collection('locations').doc(cleanJeepneyId).get();

      if (doc.exists) {
        final location = JeepneyLocation.fromFirestore(doc);

        if (!location.hasValidPosition) {
          return _invalid(
            'getJeepneyLocation',
            'Jeepney location has invalid coordinates.',
          );
        }

        return FirestoreResult<JeepneyLocation>.success(
          data: location,
          message: 'Jeepney location loaded successfully.',
        );
      }

      return _notFound(
        'getJeepneyLocation',
        'Jeepney location was not found.',
      );
    } catch (e, stackTrace) {
      return _failure('getJeepneyLocation', e, stackTrace);
    }
  }

  // ---------------------------------------------------------------------------
  // ROUTES
  // ---------------------------------------------------------------------------

  static Future<RouteInfo?> getRouteInfo(String? routeId) async {
    final result = await getRouteInfoResult(routeId);
    return result.data;
  }

  static Future<FirestoreResult<RouteInfo>> getRouteInfoResult(
    String? routeId,
  ) async {
    final cleanRouteId = routeId?.trim();

    if (cleanRouteId == null || cleanRouteId.isEmpty) {
      return _notFound(
        'getRouteInfo',
        'Route ID is missing.',
      );
    }

    try {
      final doc = await _db.collection('routes').doc(cleanRouteId).get();

      if (doc.exists) {
        return FirestoreResult<RouteInfo>.success(
          data: RouteInfo.fromFirestore(doc),
          message: 'Route loaded successfully.',
        );
      }

      return _notFound(
        'getRouteInfo',
        'Route information was not found.',
      );
    } catch (e, stackTrace) {
      return _failure('getRouteInfo', e, stackTrace);
    }
  }

  // ---------------------------------------------------------------------------
  // STATUS UPDATES
  // ---------------------------------------------------------------------------

  static Future<FirestoreResult<void>> updateDriverStatus(
    String driverId,
    String status,
  ) async {
    try {
      final cleanDriverId = driverId.trim();

      if (cleanDriverId.isEmpty) {
        return _notFound(
          'updateDriverStatus',
          'Driver ID is missing.',
        );
      }

      await _db.collection('driver').doc(cleanDriverId).set({
        'status': status,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      return const FirestoreResult<void>.success(
        message: 'Driver status updated successfully.',
      );
    } catch (e, stackTrace) {
      return _failure<void>('updateDriverStatus', e, stackTrace);
    }
  }

  static Future<FirestoreResult<void>> updateJeepneyStatus(
    String jeepneyId,
    bool isActive,
  ) async {
    try {
      final cleanJeepneyId = jeepneyId.trim();

      if (cleanJeepneyId.isEmpty) {
        return _notFound(
          'updateJeepneyStatus',
          'Jeepney ID is missing.',
        );
      }

      await _db.collection('jeeps').doc(cleanJeepneyId).set({
        'isActive': isActive,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      return const FirestoreResult<void>.success(
        message: 'Jeepney status updated successfully.',
      );
    } catch (e, stackTrace) {
      return _failure<void>('updateJeepneyStatus', e, stackTrace);
    }
  }

  // ---------------------------------------------------------------------------
  // REAL-TIME JEEPNEY LOCATION
  // ---------------------------------------------------------------------------

  static Future<FirestoreResult<void>> updateJeepneyLocation(
    String jeepneyId,
    double lat,
    double lng,
    double heading,
    double speedMps,
    String? routeId, {
    bool isOnTrip = false,
    String? crowdStatus,
    String? originTerminal,
    String? destinationTerminal,
  }) async {
    try {
      final cleanJeepneyId = jeepneyId.trim();

      if (cleanJeepneyId.isEmpty) {
        return _notFound(
          'updateJeepneyLocation',
          'Jeepney ID is missing.',
        );
      }

      if (!_isValidLatLng(lat, lng)) {
        return _invalid(
          'updateJeepneyLocation',
          'Invalid GPS coordinates: lat=$lat, lng=$lng',
        );
      }

      final safeHeading = _normalizeHeading(heading);
      final safeSpeedMps = _safeSpeed(speedMps);
      final cleanRouteId = routeId?.trim() ?? '';

      final data = <String, dynamic>{
        'jeepneyId': cleanJeepneyId,
        'lat': lat,
        'lng': lng,
        'geoPoint': GeoPoint(lat, lng),
        'heading': safeHeading,
        'speedMps': safeSpeedMps,
        'isOnline': true,
        'isOnTrip': isOnTrip,
        'routeId': cleanRouteId,
        'originTerminal': originTerminal?.trim() ?? '',
        'destinationTerminal': destinationTerminal?.trim() ?? '',
        'timestamp': FieldValue.serverTimestamp(),
        'locationUpdatedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      data.addAll(await _currentDriverLocationMetadata());

      final cleanCrowdStatus = crowdStatus?.trim();
      if (cleanCrowdStatus != null && cleanCrowdStatus.isNotEmpty) {
        data['crowdStatus'] = cleanCrowdStatus;
      }

      await _db
          .collection('locations')
          .doc(cleanJeepneyId)
          .set(data, SetOptions(merge: true));

      return const FirestoreResult<void>.success(
        message: 'Jeepney location updated successfully.',
      );
    } catch (e, stackTrace) {
      return _failure<void>('updateJeepneyLocation', e, stackTrace);
    }
  }

  static Future<FirestoreResult<void>> setJeepneyOnlineStatus(
    String jeepneyId,
    bool isOnline, {
    String? routeId,
    bool isOnTrip = false,
    String? crowdStatus,
    bool clearCrowdStatus = false,
    String? originTerminal,
    String? destinationTerminal,
  }) async {
    try {
      final cleanJeepneyId = jeepneyId.trim();

      if (cleanJeepneyId.isEmpty) {
        return _notFound(
          'setJeepneyOnlineStatus',
          'Jeepney ID is missing.',
        );
      }

      if (isOnline || isOnTrip) {
        final data = <String, dynamic>{
          'jeepneyId': cleanJeepneyId,
          'isOnline': isOnline,
          'isOnTrip': isOnTrip,
          'routeId': routeId?.trim() ?? '',
          'originTerminal': originTerminal?.trim() ?? '',
          'destinationTerminal': destinationTerminal?.trim() ?? '',
          'timestamp': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        };

        data.addAll(await _currentDriverLocationMetadata());

        if (clearCrowdStatus) {
          data['crowdStatus'] = FieldValue.delete();
        } else {
          final cleanCrowdStatus = crowdStatus?.trim();
          if (cleanCrowdStatus != null && cleanCrowdStatus.isNotEmpty) {
            data['crowdStatus'] = cleanCrowdStatus;
          }
        }

        await _db
            .collection('locations')
            .doc(cleanJeepneyId)
            .set(data, SetOptions(merge: true));

        return const FirestoreResult<void>.success(
          message: 'Jeepney online status updated successfully.',
        );
      }

      await _db.collection('locations').doc(cleanJeepneyId).delete();

      return const FirestoreResult<void>.success(
        message: 'Jeepney location deleted successfully.',
      );
    } catch (e, stackTrace) {
      return _failure<void>('setJeepneyOnlineStatus', e, stackTrace);
    }
  }

  static Future<FirestoreResult<void>> setJeepneyOfflineStatus(
    String jeepneyId, {
    bool keepTripData = true,
  }) async {
    try {
      final cleanJeepneyId = jeepneyId.trim();

      if (cleanJeepneyId.isEmpty) {
        return _notFound(
          'setJeepneyOfflineStatus',
          'Jeepney ID is missing.',
        );
      }

      if (keepTripData) {
        final data = <String, dynamic>{
          'jeepneyId': cleanJeepneyId,
          'isOnline': false,
          'updatedAt': FieldValue.serverTimestamp(),
        };

        data.addAll(await _currentDriverLocationMetadata());

        await _db
            .collection('locations')
            .doc(cleanJeepneyId)
            .set(data, SetOptions(merge: true));

        return const FirestoreResult<void>.success(
          message: 'Jeepney offline status updated successfully.',
        );
      }

      await _db.collection('locations').doc(cleanJeepneyId).delete();

      return const FirestoreResult<void>.success(
        message: 'Jeepney location deleted successfully.',
      );
    } catch (e, stackTrace) {
      return _failure<void>('setJeepneyOfflineStatus', e, stackTrace);
    }
  }

  static Future<FirestoreResult<void>> deleteJeepneyLocation(
    String jeepneyId,
  ) async {
    try {
      final cleanJeepneyId = jeepneyId.trim();

      if (cleanJeepneyId.isEmpty) {
        return _notFound(
          'deleteJeepneyLocation',
          'Jeepney ID is missing.',
        );
      }

      await _db.collection('locations').doc(cleanJeepneyId).delete();

      return const FirestoreResult<void>.success(
        message: 'Jeepney location deleted successfully.',
      );
    } catch (e, stackTrace) {
      return _failure<void>('deleteJeepneyLocation', e, stackTrace);
    }
  }

  static Future<FirestoreResult<void>> updateCrowdStatus(
    String jeepneyId,
    String level,
  ) async {
    try {
      final cleanJeepneyId = jeepneyId.trim();
      final cleanLevel = level.trim();

      if (cleanJeepneyId.isEmpty) {
        return _notFound(
          'updateCrowdStatus',
          'Jeepney ID is missing.',
        );
      }

      if (cleanLevel.isEmpty) {
        return _invalid(
          'updateCrowdStatus',
          'Crowd status is missing.',
        );
      }

      final data = <String, dynamic>{
        'crowdStatus': cleanLevel,
        'jeepneyId': cleanJeepneyId,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      data.addAll(await _currentDriverLocationMetadata());

      await _db
          .collection('locations')
          .doc(cleanJeepneyId)
          .set(data, SetOptions(merge: true));

      return const FirestoreResult<void>.success(
        message: 'Crowd status updated successfully.',
      );
    } catch (e, stackTrace) {
      return _failure<void>('updateCrowdStatus', e, stackTrace);
    }
  }

  // ---------------------------------------------------------------------------
  // NOTIFICATIONS
  // ---------------------------------------------------------------------------

  static Future<List<NotificationData>> getDriverNotifications(
    String driverId,
  ) async {
    try {
      final requestedDriverId = driverId.trim();

      if (requestedDriverId.isEmpty) {
        return [];
      }

      final currentUser = _auth.currentUser;
      if (currentUser == null) {
        return [];
      }

      final driverDocResult = await _getCurrentDriverDocumentResult();
      final driverDoc = driverDocResult.data;
      if (!driverDocResult.success || driverDoc == null || !driverDoc.exists) {
        return [];
      }

      final currentDriverId = driverDoc.id.trim();
      if (currentDriverId.isEmpty || currentDriverId != requestedDriverId) {
        return [];
      }

      final driverData = driverDoc.data() ?? <String, dynamic>{};
      final accountCreatedAt =
          _ModelParser.toDateTime(driverData['createdAt']) ??
              currentUser.metadata.creationTime;

      final querySnapshot = await _db
          .collection('notifications')
          .where('driverId', isEqualTo: currentDriverId)
          .orderBy('createdAt', descending: true)
          .limit(20)
          .get();

      return querySnapshot.docs
          .where((doc) => _notificationBelongsToCurrentDriver(
                doc.data(),
                currentDriverId: currentDriverId,
                currentUid: currentUser.uid,
                accountCreatedAt: accountCreatedAt,
              ))
          .map((doc) => NotificationData.fromFirestore(doc))
          .toList();
    } catch (e) {
      debugPrint('[FirestoreService] Error fetching notifications: $e');
      return [];
    }
  }

  static bool _notificationBelongsToCurrentDriver(
    Map<String, dynamic> data, {
    required String currentDriverId,
    required String currentUid,
    DateTime? accountCreatedAt,
  }) {
    if (_ModelParser.toBool(data['archived'])) {
      return false;
    }

    final recipientUid = data['recipientUid']?.toString().trim() ?? '';
    if (recipientUid.isNotEmpty && recipientUid != currentUid) {
      return false;
    }

    final recipientDriverId =
        data['recipientDriverId']?.toString().trim() ?? '';
    if (recipientDriverId.isNotEmpty && recipientDriverId != currentDriverId) {
      return false;
    }

    final notificationDriverId = _firstNonEmpty([
      data['driverId'],
      data['driverDocId'],
    ]);
    if (notificationDriverId != currentDriverId) {
      return false;
    }

    final notificationCreatedAt = _ModelParser.toDateTime(data['createdAt']);
    if (accountCreatedAt != null) {
      if (notificationCreatedAt == null) {
        return false;
      }
      if (notificationCreatedAt.isBefore(accountCreatedAt)) {
        return false;
      }
    }

    return true;
  }

  static Future<void> markNotificationAsRead(String notificationId) async {
    try {
      final cleanNotificationId = notificationId.trim();

      if (cleanNotificationId.isEmpty) {
        return;
      }

      await _db.collection('notifications').doc(cleanNotificationId).set({
        'isRead': true,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[FirestoreService] Error marking notification as read: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // COMMUTER WAITING LOCATIONS
  // ---------------------------------------------------------------------------

  static Stream<List<CommuterWaitingLocation>> watchSharedCommuterLocations({
    String? destinationTerminal,
  }) {
    Query<Map<String, dynamic>> query =
        _db.collection('commuter_waiting_location');

    final destination = destinationTerminal?.trim();

    if (destination == null || destination.isEmpty) {
      return Stream<List<CommuterWaitingLocation>>.value(const []);
    }

    query = query.where('destinationTerminal', isEqualTo: destination);

    return query.snapshots().map((snapshot) {
      final locations = snapshot.docs
          .map((doc) => CommuterWaitingLocation.fromFirestore(doc))
          .where((location) => location.hasCoordinates && location.isActive)
          .toList();

      locations.sort((a, b) {
        final aTime = a.timestamp;
        final bTime = b.timestamp;

        if (aTime == null && bTime == null) return 0;
        if (aTime == null) return 1;
        if (bTime == null) return -1;

        return bTime.compareTo(aTime);
      });

      return locations;
    });
  }

  /// Shows current commuter locations by destination.
  static Stream<List<CommuterWaitingLocation>> watchAllCommuterLocations({
    String? destinationTerminal,
  }) {
    Query<Map<String, dynamic>> query =
        _db.collection('commuter_waiting_location');

    final destination = destinationTerminal?.trim();

    if (destination == null || destination.isEmpty) {
      return Stream<List<CommuterWaitingLocation>>.value(const []);
    }

    query = query.where('destinationTerminal', isEqualTo: destination);

    return query.snapshots().map((snapshot) {
      final locations = snapshot.docs
          .map((doc) => CommuterWaitingLocation.fromFirestore(doc))
          .where((location) => location.hasCoordinates && location.isActive)
          .toList();

      locations.sort((a, b) {
        final aTime = a.timestamp;
        final bTime = b.timestamp;

        if (aTime == null && bTime == null) return 0;
        if (aTime == null) return 1;
        if (bTime == null) return -1;

        return bTime.compareTo(aTime);
      });

      return locations;
    });
  }

  static Stream<List<CommuterWaitingLocation>> watchDropOffAlerts({
    required String jeepneyId,
  }) {
    final cleanJeepneyId = jeepneyId.trim();
    if (cleanJeepneyId.isEmpty) {
      return const Stream<List<CommuterWaitingLocation>>.empty();
    }

    return _db
        .collection('commuter_waiting_location')
        .where('jeepneyId', isEqualTo: cleanJeepneyId)
        .where('status', isEqualTo: BookingStatus.offboard)
        .snapshots()
        .map((snapshot) {
      final locations = snapshot.docs
          .map((doc) => CommuterWaitingLocation.fromFirestore(doc))
          .where((location) => !location.driverDropOffAcknowledged)
          .toList();

      locations.sort((a, b) {
        final aTime = a.offboardAt;
        final bTime = b.offboardAt;

        if (aTime == null && bTime == null) return 0;
        if (aTime == null) return 1;
        if (bTime == null) return -1;

        return aTime.compareTo(bTime);
      });

      return locations;
    });
  }

  static Future<void> acknowledgeDropOffAlert(String commuterId) async {
    final cleanCommuterId = commuterId.trim();
    if (cleanCommuterId.isEmpty) return;

    await _db.collection('commuter_waiting_location').doc(cleanCommuterId).set({
      'driverDropOffAcknowledged': true,
      'driverDropOffAcknowledgedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Mark a dispatcher-booked commuter as offboarded.
  static Future<bool> markCommuterOffboard(
    String commuterId, {
    String? tripScheduleId,
    String? jeepneyId,
  }) async {
    final cleanCommuterId = commuterId.trim();
    if (cleanCommuterId.isEmpty) return false;

    try {
      return await _db.runTransaction<bool>((transaction) async {
        final waitingRef =
            _db.collection('commuter_waiting_location').doc(cleanCommuterId);
        final waitingDoc = await transaction.get(waitingRef);
        if (!waitingDoc.exists) return false;

        final waitingData = waitingDoc.data() ?? <String, dynamic>{};
        final currentStatus =
            waitingData['status']?.toString().trim().toLowerCase() ?? '';
        if (BookingStatus.isOffboard(currentStatus)) return false;

        final cleanJeepneyId = _firstNonEmpty([
          jeepneyId,
          waitingData['jeepneyId'],
        ]);

        DocumentReference<Map<String, dynamic>>? locationRef;
        DocumentSnapshot<Map<String, dynamic>>? locationDoc;
        Map<String, dynamic> locationData = <String, dynamic>{};
        if (cleanJeepneyId.isNotEmpty) {
          locationRef = _db.collection('locations').doc(cleanJeepneyId);
          locationDoc = await transaction.get(locationRef);
          locationData = locationDoc.data() ?? <String, dynamic>{};
        }

        final cleanTripScheduleId = _firstNonEmpty([
          tripScheduleId,
          waitingData['tripScheduleId'],
          locationData['tripScheduleId'],
        ]);
        final targetBookingId = _targetBookingId(
          waitingData,
          cleanTripScheduleId,
          cleanCommuterId,
        );
        final targetPaymentMethod =
            waitingData['paymentMethod']?.toString().trim() ?? '';

        final waitingCount =
            _ModelParser.toInt(waitingData['waitingCount']) ?? 1;
        final offboardAt = Timestamp.now();

        DocumentReference<Map<String, dynamic>>? scheduleRef;
        DocumentSnapshot<Map<String, dynamic>>? scheduleDoc;
        Map<String, dynamic> scheduleData = <String, dynamic>{};
        List<dynamic> passengers = <dynamic>[];
        Map<String, dynamic>? matchedPassenger;

        if (cleanTripScheduleId.isNotEmpty) {
          scheduleRef =
              _db.collection('trip_schedules').doc(cleanTripScheduleId);
          scheduleDoc = await transaction.get(scheduleRef);
          if (scheduleDoc.exists) {
            scheduleData = scheduleDoc.data() ?? <String, dynamic>{};
            passengers = (scheduleData['bookedPassengers'] as List<dynamic>?)
                    ?.map((passenger) => passenger is Map
                        ? Map<String, dynamic>.from(passenger)
                        : passenger)
                    .toList() ??
                <dynamic>[];
            for (final passenger in passengers) {
              if (passenger is! Map<String, dynamic>) continue;
              if (_matchesDropOffPassenger(
                passenger,
                commuterId: cleanCommuterId,
                bookingId: targetBookingId,
                paymentMethod: targetPaymentMethod,
              )) {
                matchedPassenger = passenger;
                break;
              }
            }
          }
        }

        final shouldAutoDeductPassengerCount =
            !_isTerminalCashBookingData(waitingData, matchedPassenger);
        final dropOffCount = waitingCount < 1 ? 1 : waitingCount;

        if (shouldAutoDeductPassengerCount &&
            scheduleRef != null &&
            scheduleDoc?.exists == true &&
            matchedPassenger == null) {
          return false;
        }

        transaction.set(
            waitingRef,
            {
              'status': BookingStatus.offboard,
              'offboardAt': offboardAt,
              'dropOffCount': dropOffCount,
              'autoDropOffDeductsPassengerCount':
                  shouldAutoDeductPassengerCount,
              'manualPassengerCountRequired': !shouldAutoDeductPassengerCount,
              if (!shouldAutoDeductPassengerCount)
                'driverDropOffAcknowledged': true,
              if (!shouldAutoDeductPassengerCount)
                'driverDropOffAcknowledgedAt': offboardAt,
              'isSharing': false,
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true));

        if (shouldAutoDeductPassengerCount &&
            scheduleRef != null &&
            scheduleDoc?.exists == true) {
          final currentPassengerCount =
              _ModelParser.toInt(scheduleData['passengerCount']) ?? 0;
          final nextPassengerCount =
              (currentPassengerCount - dropOffCount).clamp(0, 999999);
          final updatedPassengers = passengers.map((passenger) {
            if (passenger is! Map<String, dynamic>) return passenger;
            if (!_matchesDropOffPassenger(
              passenger,
              commuterId: cleanCommuterId,
              bookingId: targetBookingId,
              paymentMethod: targetPaymentMethod,
            )) {
              return passenger;
            }

            return <String, dynamic>{
              ...passenger,
              'status': BookingStatus.offboard,
              'onBoard': false,
              'offboardAt': offboardAt,
              'updatedAt': offboardAt,
            };
          }).toList();
          transaction.set(
              scheduleRef,
              {
                'passengerCount': nextPassengerCount,
                'bookedPassengers': updatedPassengers,
                'updatedAt': FieldValue.serverTimestamp(),
              },
              SetOptions(merge: true));
        }

        if (shouldAutoDeductPassengerCount && locationRef != null) {
          final currentLocationCount =
              _ModelParser.toInt(locationData['passengerCount']) ??
                  _ModelParser.toInt(locationData['currentPassengerCount']) ??
                  0;
          final nextLocationCount =
              (currentLocationCount - dropOffCount).clamp(0, 999999);
          transaction.set(
              locationRef,
              {
                'passengerCount': nextLocationCount,
                'currentPassengerCount': nextLocationCount,
                'passengerUpdatedAt': FieldValue.serverTimestamp(),
                'updatedAt': FieldValue.serverTimestamp(),
              },
              SetOptions(merge: true));
        }

        if (cleanTripScheduleId.isNotEmpty) {
          final bookingId = targetBookingId.isNotEmpty
              ? targetBookingId
              : '${_safeFirestoreId(cleanTripScheduleId)}_${_safeFirestoreId(cleanCommuterId)}';
          transaction.set(
            _db.collection('bookings').doc(bookingId),
            {
              'rideStatus': BookingStatus.offboard,
              'completedForCommuter': true,
              if (shouldAutoDeductPassengerCount) ...{
                'status': BookingStatus.offboard,
                'onBoard': false,
              },
              if (!shouldAutoDeductPassengerCount) ...{
                'cashDropOffRequested': true,
                'dropOffRequestedAt': offboardAt,
              },
              'offboardAt': offboardAt,
              'autoDropOffDeductsPassengerCount':
                  shouldAutoDeductPassengerCount,
              'manualPassengerCountRequired': !shouldAutoDeductPassengerCount,
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
        }

        return true;
      });
    } catch (e) {
      debugPrint('[FirestoreService] Error marking commuter offboard: $e');
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // UTILS
  // ---------------------------------------------------------------------------

  static bool _isValidLatLng(double lat, double lng) {
    if (lat.isNaN || lng.isNaN) return false;
    if (lat.isInfinite || lng.isInfinite) return false;
    if (lat == 0.0 && lng == 0.0) return false;

    return lat >= -90.0 && lat <= 90.0 && lng >= -180.0 && lng <= 180.0;
  }

  static double _safeSpeed(double value) {
    if (value.isNaN || value.isInfinite || value < 0) {
      return 0.0;
    }

    return value;
  }

  static double _normalizeHeading(double heading) {
    if (heading.isNaN || heading.isInfinite || heading < 0) {
      return 0.0;
    }

    double result = heading % 360.0;

    if (result < 0) {
      result += 360.0;
    }

    return result;
  }

  static String? _toStringOrNull(dynamic value) {
    if (value == null) return null;

    final text = value.toString().trim();

    if (text.isEmpty || text.toLowerCase() == 'null') {
      return null;
    }

    return text;
  }

  // ---------------------------------------------------------------------------
  // DRIVER EARNINGS & CASH PAYOUTS
  // ---------------------------------------------------------------------------

  /// Stream driver earnings document for real-time balance updates.
  static Stream<Map<String, dynamic>?> driverEarningsStream(String driverId) {
    return _db
        .collection('driver_earnings')
        .doc(driverId)
        .snapshots()
        .map((doc) => doc.exists ? {'id': doc.id, ...doc.data()!} : null);
  }

  /// Stream payout history for a driver.
  static Stream<List<Map<String, dynamic>>> driverPayoutsStream(
      String driverId) {
    return _db
        .collection('driver_payouts')
        .where('driverId', isEqualTo: driverId)
        .snapshots()
        .map((snapshot) {
      final payouts =
          snapshot.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();
      payouts.sort((a, b) {
        final aDate = a['requestedAt'] is Timestamp
            ? (a['requestedAt'] as Timestamp).toDate()
            : DateTime(1970);
        final bDate = b['requestedAt'] is Timestamp
            ? (b['requestedAt'] as Timestamp).toDate()
            : DateTime(1970);
        return bDate.compareTo(aDate);
      });
      return payouts;
    });
  }

  /// Get recent fare earnings for a driver.
  ///
  /// Driver earnings are payment records, so prefer driverId when available.
  /// The jeepneyId fallback keeps older fare documents visible.
  static Future<List<Map<String, dynamic>>> getRecentFareEarnings({
    String? jeepneyId,
    String? driverId,
    int limit = 200,
  }) async {
    try {
      final transactions = <String, Map<String, dynamic>>{};
      final cleanDriverId = driverId?.trim() ?? '';
      if (cleanDriverId.isNotEmpty) {
        final byDriver = await _db
            .collection('fare_transactions')
            .where('driverId', isEqualTo: cleanDriverId)
            .limit(limit)
            .get();
        for (final doc in byDriver.docs) {
          transactions[doc.id] = {'id': doc.id, ...doc.data()};
        }
      }

      final cleanJeepneyId = jeepneyId?.trim() ?? '';
      if (cleanJeepneyId.isEmpty) {
        return _sortFareTransactions(transactions.values.toList())
            .take(limit)
            .toList();
      }

      final byJeepney = await _db
          .collection('fare_transactions')
          .where('jeepneyId', isEqualTo: cleanJeepneyId)
          .limit(limit)
          .get();
      for (final doc in byJeepney.docs) {
        transactions[doc.id] = {'id': doc.id, ...doc.data()};
      }
      return _sortFareTransactions(transactions.values.toList())
          .take(limit)
          .toList();
    } catch (e) {
      debugPrint('[FirestoreService] Error fetching recent fare earnings: $e');
      return [];
    }
  }

  static List<Map<String, dynamic>> _sortFareTransactions(
    List<Map<String, dynamic>> transactions,
  ) {
    transactions.sort((a, b) {
      final aDate = a['createdAt'] is Timestamp
          ? (a['createdAt'] as Timestamp).toDate()
          : DateTime(1970);
      final bDate = b['createdAt'] is Timestamp
          ? (b['createdAt'] as Timestamp).toDate()
          : DateTime(1970);
      return bDate.compareTo(aDate);
    });
    return transactions;
  }

  /// Mark a road pickup commuter as onboard and record it across histories.
  static Future<RoadPickupOnboardResult> markCommuterOnboard(
    String commuterId, {
    String? tripScheduleId,
    String? jeepneyId,
    String? driverId,
    String? driverName,
  }) async {
    final cleanCommuterId = commuterId.trim();
    if (cleanCommuterId.isEmpty) {
      return RoadPickupOnboardResult.failure(
        'Road pickup passenger is missing.',
      );
    }

    try {
      final success = await _db.runTransaction<bool>((transaction) async {
        final waitingRef =
            _db.collection('commuter_waiting_location').doc(cleanCommuterId);
        final waitingDoc = await transaction.get(waitingRef);
        if (!waitingDoc.exists) return false;

        final waitingData = waitingDoc.data() ?? <String, dynamic>{};
        final currentStatus =
            waitingData['status']?.toString().trim().toLowerCase() ?? '';
        if (BookingStatus.isOnboard(currentStatus)) return false;

        final cleanJeepneyId = _firstNonEmpty([
          jeepneyId,
          waitingData['jeepneyId'],
        ]);

        DocumentReference<Map<String, dynamic>>? locationRef;
        DocumentSnapshot<Map<String, dynamic>>? locationDoc;
        Map<String, dynamic> locationData = <String, dynamic>{};
        if (cleanJeepneyId.isNotEmpty) {
          locationRef = _db.collection('locations').doc(cleanJeepneyId);
          locationDoc = await transaction.get(locationRef);
          locationData = locationDoc.data() ?? <String, dynamic>{};
        }

        DocumentSnapshot<Map<String, dynamic>>? jeepDoc;
        Map<String, dynamic> jeepData = <String, dynamic>{};
        if (cleanJeepneyId.isNotEmpty) {
          jeepDoc = await transaction.get(
            _db.collection('jeeps').doc(cleanJeepneyId),
          );
          jeepData = jeepDoc.data() ?? <String, dynamic>{};
        }

        final cleanTripScheduleId = _firstNonEmpty([
          tripScheduleId,
          waitingData['tripScheduleId'],
          locationData['tripScheduleId'],
        ]);
        final cleanDriverId = _firstNonEmpty([
          driverId,
          locationData['driverId'],
          locationData['assignedDriver'],
        ]);
        final cleanDriverName = _firstNonEmpty([
          driverName,
          locationData['driverName'],
          locationData['driverFullName'],
          locationData['assignedDriverName'],
        ]);
        final waitingCount =
            _ModelParser.toInt(waitingData['waitingCount']) ?? 1;
        final safeWaitingCount = waitingCount < 1 ? 1 : waitingCount;
        final onboardAt = Timestamp.now();

        DocumentReference<Map<String, dynamic>>? scheduleRef;
        DocumentSnapshot<Map<String, dynamic>>? scheduleDoc;
        Map<String, dynamic> scheduleData = <String, dynamic>{};
        if (cleanTripScheduleId.isNotEmpty) {
          scheduleRef =
              _db.collection('trip_schedules').doc(cleanTripScheduleId);
          scheduleDoc = await transaction.get(scheduleRef);
          scheduleData = scheduleDoc.data() ?? <String, dynamic>{};
        }

        final currentPassengerCount = _roadPickupCurrentPassengerCount(
          scheduleData: scheduleData,
          locationData: locationData,
        );
        final maxCapacity = _roadPickupMaxCapacity(
          scheduleData: scheduleData,
          locationData: locationData,
          jeepData: jeepData,
        );
        if (maxCapacity > 0 &&
            currentPassengerCount + safeWaitingCount > maxCapacity) {
          throw StateError(RoadPickupOnboardResult.jeepFullMessage);
        }

        final pickupId = cleanTripScheduleId.isNotEmpty
            ? '${_safeFirestoreId(cleanTripScheduleId)}_${_safeFirestoreId(cleanCommuterId)}'
            : '${_safeFirestoreId(cleanJeepneyId)}_${_safeFirestoreId(cleanCommuterId)}';
        final passengerRecord = <String, dynamic>{
          'id': pickupId,
          'commuterId': cleanCommuterId,
          'commuterName': _firstNonEmpty([
            waitingData['commuterName'],
            waitingData['displayName'],
            cleanCommuterId,
          ]),
          'tripScheduleId': cleanTripScheduleId,
          'jeepneyId': cleanJeepneyId,
          'driverId': cleanDriverId,
          'driverName': cleanDriverName,
          'routeId': _firstNonEmpty([
            waitingData['routeId'],
            scheduleData['routeId'],
            locationData['routeId'],
          ]),
          'originTerminal': _firstNonEmpty([
            scheduleData['originTerminal'],
            locationData['originTerminal'],
          ]),
          'destinationTerminal': _firstNonEmpty([
            waitingData['destinationTerminal'],
            scheduleData['destinationTerminal'],
            locationData['destinationTerminal'],
          ]),
          'waitingCount': safeWaitingCount,
          'passengerCount': safeWaitingCount,
          'source': 'road_pickup',
          'status': BookingStatus.onboard,
          'onBoard': true,
          'onBoardSource': 'road_pickup',
          'onBoardAt': onboardAt,
        };
        final pickupRecord = <String, dynamic>{
          ...passengerRecord,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        };

        transaction.set(
            waitingRef,
            {
              ...pickupRecord,
              'isSharing': false,
            },
            SetOptions(merge: true));

        if (scheduleRef != null && scheduleDoc?.exists == true) {
          final currentPassengerCount =
              _ModelParser.toInt(scheduleData['passengerCount']) ?? 0;
          final nextPassengerCount = currentPassengerCount + safeWaitingCount;
          transaction.set(
              scheduleRef,
              {
                'passengerCount': nextPassengerCount,
                'bookedPassengers': FieldValue.arrayUnion([passengerRecord]),
                'updatedAt': FieldValue.serverTimestamp(),
              },
              SetOptions(merge: true));
        }

        if (locationRef != null) {
          final currentLocationCount =
              _ModelParser.toInt(locationData['passengerCount']) ??
                  _ModelParser.toInt(locationData['currentPassengerCount']) ??
                  0;
          final nextLocationCount = currentLocationCount + safeWaitingCount;
          transaction.set(
              locationRef,
              {
                'passengerCount': nextLocationCount,
                'currentPassengerCount': nextLocationCount,
                'passengerUpdatedAt': FieldValue.serverTimestamp(),
                'updatedAt': FieldValue.serverTimestamp(),
              },
              SetOptions(merge: true));
        }

        transaction.set(
          _db.collection('bookings').doc(pickupId),
          pickupRecord,
          SetOptions(merge: true),
        );
        transaction.set(
          _db.collection('road_pickup_history').doc(pickupId),
          pickupRecord,
          SetOptions(merge: true),
        );
        transaction.set(
          _db.collection('commuter_pickup_history').doc(pickupId),
          pickupRecord,
          SetOptions(merge: true),
        );
        transaction.set(
          _db.collection('driver_pickup_history').doc(pickupId),
          pickupRecord,
          SetOptions(merge: true),
        );

        return true;
      });

      return success
          ? RoadPickupOnboardResult.success()
          : RoadPickupOnboardResult.failure(
              'Road pickup was already recorded or could not be updated.',
            );
    } catch (e) {
      debugPrint('[FirestoreService] Error marking commuter onboard: $e');
      final message =
          e.toString().contains(RoadPickupOnboardResult.jeepFullMessage)
              ? RoadPickupOnboardResult.jeepFullMessage
              : 'Road pickup was not saved. No passenger data was updated.';
      return RoadPickupOnboardResult.failure(message);
    }
  }

  static int _roadPickupCurrentPassengerCount({
    required Map<String, dynamic> scheduleData,
    required Map<String, dynamic> locationData,
  }) {
    final scheduleCount = _ModelParser.toInt(scheduleData['passengerCount']);
    if (scheduleCount != null && scheduleCount >= 0) return scheduleCount;

    return _ModelParser.toInt(locationData['passengerCount']) ??
        _ModelParser.toInt(locationData['currentPassengerCount']) ??
        _ModelParser.toInt(locationData['currentPassengers']) ??
        0;
  }

  static int _roadPickupMaxCapacity({
    required Map<String, dynamic> scheduleData,
    required Map<String, dynamic> locationData,
    required Map<String, dynamic> jeepData,
  }) {
    for (final data in [scheduleData, locationData, jeepData]) {
      for (final key in const [
        'maxCapacity',
        'capacity',
        'seatingCapacity',
        'maxPassengers',
      ]) {
        final capacity = _ModelParser.toInt(data[key]);
        if (capacity != null && capacity > 0) return capacity;
      }
    }
    return 0;
  }

  /// Creates/updates a [commuter_waiting_location] doc with status='onboard'
  /// for a commuter booked by the dispatcher (no prior doc exists).
  /// This allows the commuter app to detect they are onboard and show "Drop Off".
  static Future<bool> dispatcherCommuterOnboard({
    required String commuterId,
    required String jeepneyId,
    required double lat,
    required double lng,
    String? tripScheduleId,
    String? destinationTerminal,
    int waitingCount = 1,
  }) async {
    final cleanId = commuterId.trim();
    if (cleanId.isEmpty) return false;
    try {
      final docRef = _db.collection('commuter_waiting_location').doc(cleanId);
      final doc = await docRef.get();
      if (doc.exists) {
        final status =
            doc.data()?['status']?.toString().trim().toLowerCase() ?? '';
        if (BookingStatus.isOnboard(status) ||
            BookingStatus.isOffboard(status)) {
          return false;
        }
      }
      await docRef.set({
        'commuterId': cleanId,
        'jeepneyId': jeepneyId,
        if (tripScheduleId != null && tripScheduleId.trim().isNotEmpty)
          'tripScheduleId': tripScheduleId.trim(),
        'lat': lat,
        'lng': lng,
        'destinationTerminal': destinationTerminal ?? '',
        'waitingCount': waitingCount,
        'passengerCount': waitingCount,
        'dropOffCount': waitingCount,
        'status': BookingStatus.onboard,
        'source': 'dispatcher',
        'onBoard': true,
        'onBoardSource': 'dispatcher',
        'bookedBy': 'dispatcher',
        'onBoardAt': FieldValue.serverTimestamp(),
        'isSharing': false,
        'requireDispatcherRebook': true,
        'rebookOnlyBy': 'dispatcher',
        'timestamp': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return true;
    } catch (e) {
      debugPrint('[FirestoreService] Error in dispatcherCommuterOnboard: $e');
      return false;
    }
  }
}

// -----------------------------------------------------------------------------
// MODELS
// -----------------------------------------------------------------------------

class RoadPickupOnboardResult {
  static const String jeepFullMessage =
      'Jeep is full. Cannot mark this road pickup passenger onboard.';

  final bool success;
  final String message;

  const RoadPickupOnboardResult({
    required this.success,
    required this.message,
  });

  factory RoadPickupOnboardResult.success() {
    return const RoadPickupOnboardResult(
      success: true,
      message: 'Road pickup passenger marked onboard.',
    );
  }

  factory RoadPickupOnboardResult.failure(String message) {
    return RoadPickupOnboardResult(success: false, message: message);
  }
}

class DriverProfile {
  final String id;
  final String name;
  final String email;
  final String phone;
  final String role;
  final String status;
  final bool mustSetPassword;
  final String accountStatus;
  final String? assignedJeepneyId;
  final String? assignedJeepId;
  final String? assignedRouteId;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? passwordSetAt;
  final DateTime? lastLoginAt;
  final DateTime? setupEmailSentAt;
  final bool emailVerified;
  final DateTime? emailVerifiedAt;
  final bool temporaryPasswordLoginConsumed;

  DriverProfile({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.role,
    required this.status,
    required this.mustSetPassword,
    required this.accountStatus,
    this.assignedJeepneyId,
    this.assignedJeepId,
    this.assignedRouteId,
    required this.isActive,
    this.createdAt,
    this.passwordSetAt,
    this.lastLoginAt,
    this.setupEmailSentAt,
    required this.emailVerified,
    this.emailVerifiedAt,
    required this.temporaryPasswordLoginConsumed,
  });

  factory DriverProfile.fromFirestore(DocumentSnapshot doc) {
    final rawData = doc.data();
    final data =
        rawData is Map<String, dynamic> ? rawData : <String, dynamic>{};

    final status = data['status']?.toString() ?? 'inactive';
    final isActiveValue = data['isActive'];

    var isActive = status.toLowerCase() == 'active';

    if (isActiveValue is bool) {
      isActive = isActiveValue;
    } else if (isActiveValue is String) {
      isActive = isActiveValue.toLowerCase() == 'true';
    } else if (isActiveValue is num) {
      isActive = isActiveValue == 1;
    }

    return DriverProfile(
      id: doc.id,
      name: data['name']?.toString() ?? '',
      email: data['email']?.toString() ?? '',
      phone: data['phone']?.toString() ?? '',
      role: data['role']?.toString() ?? 'driver',
      status: status,
      mustSetPassword: data['mustSetPassword'] == true,
      accountStatus: data['accountStatus']?.toString() ?? 'active',
      assignedJeepneyId: _ModelParser.toStringOrNull(data['assignedJeepneyId']),
      assignedJeepId: _ModelParser.toStringOrNull(data['assignedJeepId']),
      assignedRouteId: _ModelParser.toStringOrNull(data['assignedRouteId']),
      isActive: isActive,
      createdAt: _ModelParser.toDateTime(data['createdAt']),
      passwordSetAt: _ModelParser.toDateTime(data['passwordSetAt']),
      lastLoginAt: _ModelParser.toDateTime(data['lastLoginAt']),
      setupEmailSentAt: _ModelParser.toDateTime(data['setupEmailSentAt']),
      emailVerified: data['emailVerified'] == true,
      emailVerifiedAt: _ModelParser.toDateTime(data['emailVerifiedAt']),
      temporaryPasswordLoginConsumed:
          data['temporaryPasswordLoginConsumed'] == true,
    );
  }
}

class Jeepney {
  final String id;
  final String plateNumber;
  final String assignedDriver;
  final String driverId;
  final String routeId;
  final String capacity;
  final bool isActive;
  final DateTime? createdAt;

  Jeepney({
    required this.id,
    required this.plateNumber,
    required this.assignedDriver,
    this.driverId = '',
    required this.routeId,
    required this.capacity,
    required this.isActive,
    this.createdAt,
  });

  factory Jeepney.fromFirestore(DocumentSnapshot doc) {
    final rawData = doc.data();
    final data =
        rawData is Map<String, dynamic> ? rawData : <String, dynamic>{};

    return Jeepney(
      id: doc.id,
      plateNumber: _ModelParser.toStringSafe(data['plateNumber']),
      assignedDriver: _ModelParser.toStringSafe(data['assignedDriver']),
      driverId: _ModelParser.toStringSafe(data['driverId']),
      routeId: _ModelParser.toStringSafe(data['routeId']),
      capacity: _ModelParser.toStringSafe(data['capacity']),
      isActive: _ModelParser.toBool(data['isActive']),
      createdAt: _ModelParser.toDateTime(data['createdAt']),
    );
  }
}

class JeepneyLocation {
  final String jeepneyId;
  final String routeId;
  final LatLng position;
  final double heading;
  final double speedMps;
  final bool isOnline;
  final bool isOnTrip;
  final String crowdStatus;
  final String originTerminal;
  final String destinationTerminal;
  final String driverUid;
  final String driverDocId;
  final String driverEmail;
  final int passengerCount;
  final String scheduleTime;
  final DateTime? timestamp;
  final DateTime? updatedAt;

  JeepneyLocation({
    required this.jeepneyId,
    required this.routeId,
    required this.position,
    required this.heading,
    required this.speedMps,
    required this.isOnline,
    required this.isOnTrip,
    required this.crowdStatus,
    required this.originTerminal,
    required this.destinationTerminal,
    required this.driverUid,
    required this.driverDocId,
    required this.driverEmail,
    this.passengerCount = 0,
    this.scheduleTime = '',
    this.timestamp,
    this.updatedAt,
  });

  bool get hasValidPosition {
    final lat = position.latitude;
    final lng = position.longitude;

    if (lat.isNaN || lng.isNaN) return false;
    if (lat.isInfinite || lng.isInfinite) return false;
    if (lat == 0.0 && lng == 0.0) return false;

    return lat >= -90.0 && lat <= 90.0 && lng >= -180.0 && lng <= 180.0;
  }

  String get crowdLevel {
    if (crowdStatus.trim().isNotEmpty) {
      return crowdStatus.toUpperCase();
    }

    if (speedMps < 2) return 'PUNO';
    if (speedMps < 5) return 'SAKTO';
    return 'MALUWAG';
  }

  factory JeepneyLocation.fromFirestore(DocumentSnapshot doc) {
    final rawData = doc.data();
    final data =
        rawData is Map<String, dynamic> ? rawData : <String, dynamic>{};

    final lat = _ModelParser.toDouble(data['lat'] ?? data['latitude']) ?? 0.0;
    final lng = _ModelParser.toDouble(data['lng'] ?? data['longitude']) ?? 0.0;

    return JeepneyLocation(
      jeepneyId: data['jeepneyId']?.toString() ?? doc.id,
      routeId: data['routeId']?.toString() ?? '',
      position: LatLng(lat, lng),
      heading: _ModelParser.toDouble(data['heading']) ?? 0.0,
      speedMps: _ModelParser.toDouble(data['speedMps']) ?? 0.0,
      isOnline: _ModelParser.toBool(data['isOnline']),
      isOnTrip: _ModelParser.toBool(data['isOnTrip']),
      crowdStatus: data['crowdStatus']?.toString() ?? '',
      originTerminal: data['originTerminal']?.toString() ?? '',
      destinationTerminal: data['destinationTerminal']?.toString() ?? '',
      driverUid: data['driverUid']?.toString() ?? '',
      driverDocId: data['driverDocId']?.toString() ?? '',
      driverEmail: data['driverEmail']?.toString() ?? '',
      passengerCount: _ModelParser.toInt(
            data['passengerCount'] ??
                data['currentPassengerCount'] ??
                data['currentPassengers'],
          ) ??
          0,
      scheduleTime: data['scheduleTime']?.toString() ?? '',
      timestamp: _ModelParser.toDateTime(data['timestamp']),
      updatedAt: _ModelParser.toDateTime(data['updatedAt']),
    );
  }
}

class RouteInfo {
  final String id;
  final String name;
  final String startTerminal;
  final String endTerminal;
  final String status;
  final DateTime? createdAt;

  RouteInfo({
    required this.id,
    required this.name,
    required this.startTerminal,
    required this.endTerminal,
    required this.status,
    this.createdAt,
  });

  factory RouteInfo.fromFirestore(DocumentSnapshot doc) {
    final rawData = doc.data();
    final data =
        rawData is Map<String, dynamic> ? rawData : <String, dynamic>{};

    return RouteInfo(
      id: doc.id,
      name: data['name']?.toString() ?? '',
      startTerminal: data['startTerminal']?.toString() ?? '',
      endTerminal: data['endTerminal']?.toString() ?? '',
      status: data['status']?.toString() ?? 'inactive',
      createdAt: _ModelParser.toDateTime(data['createdAt']),
    );
  }
}

class NotificationData {
  final String id;
  final String driverId;
  final String title;
  final String message;
  final String type;
  final bool isRead;
  final DateTime? createdAt;

  NotificationData({
    required this.id,
    required this.driverId,
    required this.title,
    required this.message,
    required this.type,
    required this.isRead,
    this.createdAt,
  });

  factory NotificationData.fromFirestore(DocumentSnapshot doc) {
    final rawData = doc.data();
    final data =
        rawData is Map<String, dynamic> ? rawData : <String, dynamic>{};

    return NotificationData(
      id: doc.id,
      driverId: data['driverId']?.toString() ?? '',
      title: data['title']?.toString() ?? '',
      message: data['message']?.toString() ?? '',
      type: data['type']?.toString() ?? 'info',
      isRead: _ModelParser.toBool(data['isRead']),
      createdAt: _ModelParser.toDateTime(data['createdAt']),
    );
  }
}

class CommuterWaitingLocation {
  final String id;
  final String commuterId;
  final double? lat;
  final double? lng;
  final String routeId;
  final String jeepneyId;
  final int waitingCount;
  final String destinationTerminal;
  final bool isSharing;
  final String status;
  final String source;
  final String onBoardSource;
  final String bookedBy;
  final String paymentMethod;
  final bool anonymousCash;
  final DateTime? timestamp;
  final DateTime? expiresAt;
  final DateTime? cancelledAt;
  final DateTime? offboardAt;
  final int dropOffCount;
  final bool driverDropOffAcknowledged;
  final bool autoDropOffDeductsPassengerCount;

  static const Duration activeDuration = Duration(minutes: 15);

  CommuterWaitingLocation({
    required this.id,
    required this.commuterId,
    required this.lat,
    required this.lng,
    required this.routeId,
    required this.jeepneyId,
    required this.waitingCount,
    required this.destinationTerminal,
    required this.isSharing,
    this.status = BookingStatus.waiting,
    this.source = '',
    this.onBoardSource = '',
    this.bookedBy = '',
    this.paymentMethod = '',
    this.anonymousCash = false,
    this.timestamp,
    this.expiresAt,
    this.cancelledAt,
    this.offboardAt,
    this.dropOffCount = 0,
    this.driverDropOffAcknowledged = false,
    this.autoDropOffDeductsPassengerCount = true,
  });

  bool get hasCoordinates {
    if (lat == null || lng == null) return false;
    if (lat!.isNaN || lng!.isNaN) return false;
    if (lat!.isInfinite || lng!.isInfinite) return false;
    if (lat == 0.0 && lng == 0.0) return false;

    return lat! >= -90.0 && lat! <= 90.0 && lng! >= -180.0 && lng! <= 180.0;
  }

  bool get isActive {
    if (!isSharing) return false;

    final now = DateTime.now();

    if (expiresAt != null) {
      return expiresAt!.isAfter(now);
    }

    if (timestamp == null) return false;

    return now.difference(timestamp!) <= activeDuration;
  }

  bool get isTerminalCashBooking {
    final method = paymentMethod.trim().toLowerCase();
    if (method != 'cash' && !anonymousCash) return false;

    final sourceText = source.toLowerCase();
    final onBoardSourceText = onBoardSource.toLowerCase();
    final bookedByText = bookedBy.toLowerCase();

    return sourceText.contains('terminal') ||
        sourceText.contains('dispatcher') ||
        sourceText.contains('driver') ||
        onBoardSourceText.contains('dispatcher') ||
        onBoardSourceText.contains('driver') ||
        bookedByText.contains('dispatcher') ||
        bookedByText.contains('driver');
  }

  String get shortCommuterId {
    if (commuterId.isEmpty) return '';

    if (commuterId.length <= 6) {
      return commuterId.toUpperCase();
    }

    return commuterId.substring(commuterId.length - 6).toUpperCase();
  }

  String get displayName {
    if (shortCommuterId.isEmpty) return 'Commuter';
    return 'Commuter $shortCommuterId';
  }

  factory CommuterWaitingLocation.fromFirestore(DocumentSnapshot doc) {
    final rawData = doc.data();
    final data =
        rawData is Map<String, dynamic> ? rawData : <String, dynamic>{};

    return CommuterWaitingLocation(
      id: doc.id,
      commuterId: data['commuterId']?.toString() ?? doc.id,
      lat: _ModelParser.toDouble(data['lat'] ?? data['latitude']),
      lng: _ModelParser.toDouble(data['lng'] ?? data['longitude']),
      routeId: data['routeId']?.toString() ?? '',
      jeepneyId: data['jeepneyId']?.toString() ?? '',
      waitingCount: _ModelParser.toInt(data['waitingCount']) ?? 1,
      destinationTerminal: data['destinationTerminal']?.toString() ?? '',
      isSharing: _ModelParser.toBool(data['isSharing']),
      status: _normalizedBookingStatus(data['status']),
      source: data['source']?.toString() ?? '',
      onBoardSource: data['onBoardSource']?.toString() ?? '',
      bookedBy: data['bookedBy']?.toString() ?? '',
      paymentMethod: data['paymentMethod']?.toString() ?? '',
      anonymousCash: _ModelParser.toBool(data['anonymousCash']),
      timestamp: _ModelParser.toDateTime(data['timestamp']),
      expiresAt: _ModelParser.toDateTime(data['expiresAt']),
      cancelledAt: _ModelParser.toDateTime(data['cancelledAt']),
      offboardAt: _ModelParser.toDateTime(data['offboardAt']),
      dropOffCount: _ModelParser.toInt(
            data['dropOffCount'] ?? data['passengerCount'],
          ) ??
          0,
      driverDropOffAcknowledged:
          _ModelParser.toBool(data['driverDropOffAcknowledged']),
      autoDropOffDeductsPassengerCount:
          data['autoDropOffDeductsPassengerCount'] is bool
              ? data['autoDropOffDeductsPassengerCount'] as bool
              : true,
    );
  }
}

String _normalizedBookingStatus(dynamic value) {
  final status = BookingStatus.normalize(value?.toString());
  return status.isEmpty ? BookingStatus.waiting : status;
}

class _ModelParser {
  static String toStringSafe(dynamic value) {
    if (value == null) return '';
    return value.toString();
  }

  static String? toStringOrNull(dynamic value) {
    if (value == null) return null;

    final text = value.toString().trim();

    if (text.isEmpty || text.toLowerCase() == 'null') {
      return null;
    }

    return text;
  }

  static bool toBool(dynamic value) {
    if (value == null) return false;

    if (value is bool) return value;

    if (value is num) return value == 1;

    if (value is String) {
      final lower = value.trim().toLowerCase();

      return lower == 'true' ||
          lower == '1' ||
          lower == 'yes' ||
          lower == 'active' ||
          lower == 'online';
    }

    return false;
  }

  static double? toDouble(dynamic value) {
    if (value == null) return null;

    if (value is num) {
      final result = value.toDouble();

      if (result.isNaN || result.isInfinite) {
        return null;
      }

      return result;
    }

    final parsed = double.tryParse(value.toString());

    if (parsed == null || parsed.isNaN || parsed.isInfinite) {
      return null;
    }

    return parsed;
  }

  static int? toInt(dynamic value) {
    if (value == null) return null;

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(value.toString());
  }

  static DateTime? toDateTime(dynamic value) {
    if (value == null) return null;

    if (value is Timestamp) {
      return value.toDate();
    }

    if (value is DateTime) {
      return value;
    }

    if (value is String) {
      return DateTime.tryParse(value);
    }

    return null;
  }
}
