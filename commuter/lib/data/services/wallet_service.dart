import 'package:cloud_firestore/cloud_firestore.dart';

class WalletService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static Future<double> getBalance(String commuterId) async {
    try {
      final doc = await _firestore
          .collection('commuter_wallets')
          .doc(commuterId)
          .get();
      if (doc.exists) {
        final balance = doc.data()?['balance'];
        if (balance is num) return balance.toDouble();
      }
      return 0.0;
    } catch (e) {
      return 0.0;
    }
  }

  static Stream<double> balanceStream(String commuterId) {
    return _firestore
        .collection('commuter_wallets')
        .doc(commuterId)
        .snapshots()
        .map((doc) {
          if (!doc.exists) return 0.0;
          final balance = doc.data()?['balance'];
          if (balance is num) return balance.toDouble();
          return 0.0;
        });
  }

  static Future<void> testTopUp({
    required String commuterId,
    required double amount,
    required String paymentMethod,
  }) async {
    final walletRef = _firestore.collection('commuter_wallets').doc(commuterId);
    final transactionRef = _firestore.collection('fare_transactions').doc();

    await _firestore.runTransaction((transaction) async {
      final walletDoc = await transaction.get(walletRef);
      final currentBalance = walletDoc.exists
          ? ((walletDoc.data()?['balance'] as num?)?.toDouble() ?? 0.0)
          : 0.0;

      transaction.set(walletRef, {
        'commuterId': commuterId,
        'balance': currentBalance + amount,
        'status': 'active',
        'updatedAt': FieldValue.serverTimestamp(),
        if (!walletDoc.exists) 'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      transaction.set(transactionRef, {
        'commuterId': commuterId,
        'type': 'topup',
        'amount': amount,
        'paymentMethod': paymentMethod,
        'status': 'test',
        'createdAt': Timestamp.now(),
      });
    });
  }

  static Future<List<Map<String, dynamic>>> getTransactions(
    String commuterId, {
    int limit = 50,
  }) async {
    try {
      final snapshot = await _firestore
          .collection('fare_transactions')
          .where('commuterId', isEqualTo: commuterId)
          .limit(limit)
          .get();
      final transactions = snapshot.docs.map((doc) {
        final data = doc.data();
        return {'id': doc.id, ...data};
      }).toList();
      _sortNewestFirst(transactions);
      return transactions;
    } catch (e) {
      return [];
    }
  }

  static Stream<List<Map<String, dynamic>>> transactionsStream(
    String commuterId, {
    int limit = 50,
  }) {
    return _firestore
        .collection('fare_transactions')
        .where('commuterId', isEqualTo: commuterId)
        .snapshots()
        .map((snapshot) {
          final transactions = snapshot.docs.map((doc) {
            final data = doc.data();
            return {'id': doc.id, ...data};
          }).toList();
          _sortNewestFirst(transactions);
          return transactions.take(limit).toList();
        });
  }

  static Stream<Map<String, dynamic>?> blockingTopupRequestStream(
    String commuterId,
  ) {
    return _firestore
        .collection('topup_requests')
        .where('commuterId', isEqualTo: commuterId)
        .snapshots()
        .map((snapshot) {
          final blockingRequests = snapshot.docs
              .where((doc) {
                final status =
                    doc.data()['status']?.toString().trim().toLowerCase() ?? '';
                return !_isFinalTopupStatus(status);
              })
              .map((doc) => {'id': doc.id, ...doc.data()})
              .toList();

          if (blockingRequests.isEmpty) return null;

          blockingRequests.sort((a, b) {
            final aDate = _toDateTime(a['submittedAt'] ?? a['createdAt']);
            final bDate = _toDateTime(b['submittedAt'] ?? b['createdAt']);
            return bDate.compareTo(aDate);
          });

          return blockingRequests.first;
        });
  }

  static Stream<bool> hasBlockingTopupRequestStream(String commuterId) {
    return blockingTopupRequestStream(
      commuterId,
    ).map((request) => request != null);
  }

  static Stream<Map<String, dynamic>?> blockingRfidDeactivationRequestStream(
    String commuterId,
  ) {
    return _firestore
        .collection('rfid_deactivation_requests')
        .where('commuterId', isEqualTo: commuterId)
        .snapshots()
        .map((snapshot) {
          final blockingRequests = snapshot.docs
              .where((doc) {
                final status =
                    doc.data()['status']?.toString().trim().toLowerCase() ?? '';
                return !_isFinalRfidDeactivationStatus(status);
              })
              .map((doc) => {'id': doc.id, ...doc.data()})
              .toList();

          if (blockingRequests.isEmpty) return null;

          blockingRequests.sort((a, b) {
            final aDate = _toDateTime(a['requestedAt'] ?? a['createdAt']);
            final bDate = _toDateTime(b['requestedAt'] ?? b['createdAt']);
            return bDate.compareTo(aDate);
          });

          return blockingRequests.first;
        });
  }

  static Stream<Map<String, dynamic>?> rfidDeactivationRequestStream(
    String requestId,
  ) {
    final cleanRequestId = requestId.trim();
    if (cleanRequestId.isEmpty) return Stream.value(null);

    return _firestore
        .collection('rfid_deactivation_requests')
        .doc(cleanRequestId)
        .snapshots()
        .map((doc) {
          final data = doc.data();
          if (!doc.exists || data == null) return null;
          return {'id': doc.id, ...data};
        });
  }

  static bool isFinalTopupStatus(String status) {
    return _isFinalTopupStatus(status.trim().toLowerCase());
  }

  static bool isCancellableTopupStatus(String status) {
    final normalized = status.trim().toLowerCase();
    return normalized == 'needs_review' ||
        normalized == 'pending' ||
        normalized == 'requested' ||
        normalized.isEmpty;
  }

  static String topupStatusLabel(String status) {
    switch (status.trim().toLowerCase()) {
      case 'needs_review':
      case 'pending':
      case 'requested':
        return 'Waiting for treasurer review';
      case 'approved':
      case 'auto_approved':
        return 'Approved';
      case 'rejected':
        return 'Rejected';
      case 'ai_failed':
        return 'Scan failed';
      case 'canceled':
      case 'cancelled':
      case 'commuter_canceled':
      case 'commuter_cancelled':
        return 'Cancelled';
      default:
        return status.trim().isEmpty ? 'Waiting for treasurer review' : status;
    }
  }

  static String rfidDeactivationStatusLabel(String status) {
    switch (status.trim().toLowerCase()) {
      case 'pending':
      case 'requested':
        return 'Waiting for dispatcher review';
      case 'approved':
        return 'Approved';
      case 'rejected':
        return 'Rejected';
      case 'canceled':
      case 'cancelled':
      case 'commuter_canceled':
      case 'commuter_cancelled':
        return 'Cancelled';
      default:
        return status.trim().isEmpty
            ? 'Waiting for dispatcher review'
            : status.replaceAll('_', ' ');
    }
  }

  static Future<void> requestRfidDeactivation({
    required String commuterId,
    required String rfidCard,
  }) async {
    final cleanCommuterId = commuterId.trim();
    final cleanRfidCard = rfidCard.trim();
    if (cleanCommuterId.isEmpty || cleanRfidCard.isEmpty) {
      throw Exception('No active RFID card found for this account');
    }

    final commuterRef = _firestore.collection('commuters').doc(cleanCommuterId);
    final requestRef = _firestore
        .collection('rfid_deactivation_requests')
        .doc();
    final auditRef = _firestore.collection('fare_transactions').doc();

    final existingRequest = await _firestore
        .collection('rfid_deactivation_requests')
        .where('commuterId', isEqualTo: cleanCommuterId)
        .get();
    final hasPendingRequest = existingRequest.docs.any((doc) {
      final status =
          doc.data()['status']?.toString().trim().toLowerCase() ?? '';
      return !_isFinalRfidDeactivationStatus(status);
    });
    if (hasPendingRequest) {
      throw Exception('You already have a pending RFID deactivation request');
    }

    await _firestore.runTransaction((transaction) async {
      final commuterDoc = await transaction.get(commuterRef);
      if (!commuterDoc.exists) {
        throw Exception('Commuter account was not found');
      }

      final data = commuterDoc.data() ?? {};
      final currentRfid = data['rfidCard']?.toString().trim() ?? '';
      final rfidStatus = data['rfidStatus']?.toString().trim() ?? 'active';
      final commuterName =
          '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}'.trim();
      if (currentRfid != cleanRfidCard || currentRfid.isEmpty) {
        throw Exception('Your RFID card changed. Please refresh and try again');
      }
      if (rfidStatus == 'deactivation_pending') {
        throw Exception('You already have a pending RFID deactivation request');
      }
      if (rfidStatus == 'deactivated') {
        throw Exception('This RFID card is already deactivated');
      }

      transaction.set(requestRef, {
        'commuterId': cleanCommuterId,
        if (commuterName.isNotEmpty) 'commuterName': commuterName,
        'rfidCard': cleanRfidCard,
        'auditTransactionId': auditRef.id,
        'status': 'pending',
        'reason': 'lost_card',
        'requestedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      transaction.set(commuterRef, {
        'rfidStatus': 'deactivation_pending',
        'rfidDeactivationRequestId': requestRef.id,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      transaction.set(auditRef, {
        'commuterId': cleanCommuterId,
        if (commuterName.isNotEmpty) 'commuterName': commuterName,
        'rfidCard': cleanRfidCard,
        'type': 'rfid_deactivation_request',
        'status': 'pending',
        'note': 'RFID deactivation requested by commuter',
        'requestId': requestRef.id,
        'visibleToCommuter': true,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  }

  static void _sortNewestFirst(List<Map<String, dynamic>> transactions) {
    transactions.sort((a, b) {
      final aDate = _toDateTime(a['createdAt']);
      final bDate = _toDateTime(b['createdAt']);
      return bDate.compareTo(aDate);
    });
  }

  static DateTime _toDateTime(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value) ?? DateTime(1970);
    return DateTime(1970);
  }

  static bool _isFinalTopupStatus(String status) {
    return status == 'approved' ||
        status == 'auto_approved' ||
        status == 'rejected' ||
        status == 'ai_failed' ||
        status == 'canceled' ||
        status == 'cancelled' ||
        status == 'commuter_canceled' ||
        status == 'commuter_cancelled';
  }

  static bool _isFinalRfidDeactivationStatus(String status) {
    return status == 'approved' ||
        status == 'rejected' ||
        status == 'canceled' ||
        status == 'cancelled' ||
        status == 'commuter_canceled' ||
        status == 'commuter_cancelled';
  }
}
