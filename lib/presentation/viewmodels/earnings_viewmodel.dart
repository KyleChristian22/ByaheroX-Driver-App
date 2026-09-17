import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../services/firestore_service.dart';
import '../../services/driver_payout_service.dart';

class EarningsViewModel extends ChangeNotifier {
  double _earningsBalance = 0;
  double _lifetimeEarned = 0;
  double _lifetimeWithdrawn = 0;
  List<Map<String, dynamic>> _recentFares = [];
  List<Map<String, dynamic>> _payoutHistory = [];
  bool _isLoading = false;
  bool _isSubmitting = false;
  String? _error;
  StreamSubscription<Map<String, dynamic>?>? _earningsSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _payoutsSubscription;

  double get earningsBalance => _earningsBalance;
  double get lifetimeEarned => _lifetimeEarned;
  double get lifetimeWithdrawn => _lifetimeWithdrawn;
  List<Map<String, dynamic>> get recentFares => _recentFares;
  List<Map<String, dynamic>> get payoutHistory => _payoutHistory;
  Map<String, dynamic>? get activePayoutRequest {
    for (final payout in _payoutHistory) {
      if (_isActivePayoutStatus(payout['status'])) return payout;
    }
    return null;
  }

  bool get hasActivePayoutRequest => activePayoutRequest != null;
  bool get isLoading => _isLoading;
  bool get isSubmitting => _isSubmitting;
  String? get error => _error;

  void loadDriverEarnings(String driverId) {
    _isLoading = true;
    notifyListeners();

    _earningsSubscription?.cancel();
    _earningsSubscription =
        FirestoreService.driverEarningsStream(driverId).listen((data) {
      if (data != null) {
        _earningsBalance = (data['balance'] as num?)?.toDouble() ?? 0;
        _lifetimeEarned = (data['lifetimeEarned'] as num?)?.toDouble() ?? 0;
        _lifetimeWithdrawn =
            (data['lifetimeWithdrawn'] as num?)?.toDouble() ?? 0;
      } else {
        _earningsBalance = 0;
        _lifetimeEarned = 0;
        _lifetimeWithdrawn = 0;
      }
      _isLoading = false;
      notifyListeners();
    }, onError: (error) {
      _error = error.toString();
      _isLoading = false;
      notifyListeners();
    });
  }

  void watchPayoutHistory(String driverId) {
    _payoutsSubscription?.cancel();
    _payoutsSubscription =
        FirestoreService.driverPayoutsStream(driverId).listen((data) {
      _payoutHistory = data;
      notifyListeners();
    }, onError: (error) {
      debugPrint('[EarningsViewModel] Payout stream error: $error');
    });
  }

  Future<void> loadRecentFares({
    String? jeepneyId,
    String? driverId,
  }) async {
    _isLoading = true;
    notifyListeners();

    try {
      _recentFares = await FirestoreService.getRecentFareEarnings(
        jeepneyId: jeepneyId,
        driverId: driverId,
      ).then(
        (fares) => fares.where(
          (fare) {
            final method =
                fare['paymentMethod']?.toString().toLowerCase() ?? '';
            final rfidTag = fare['rfidTag']?.toString().trim() ?? '';
            return method == 'rfid' || rfidTag.isNotEmpty;
          },
        ).toList(),
      );
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> submitPayoutRequest({
    required String driverId,
    required double amount,
  }) async {
    if (hasActivePayoutRequest) {
      _error = 'A payout request is already pending.';
      notifyListeners();
      return false;
    }

    _isSubmitting = true;
    _error = null;
    notifyListeners();

    try {
      final result = await DriverPayoutService.requestCashPayout(
        driverId: driverId,
        amount: amount,
      );
      return result['success'] == true;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  Future<bool> cancelPayoutRequest({
    required String payoutId,
  }) async {
    _isSubmitting = true;
    _error = null;
    notifyListeners();

    try {
      final result = await DriverPayoutService.cancelCashPayout(
        payoutId: payoutId,
      );
      return result['success'] == true;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _earningsSubscription?.cancel();
    _payoutsSubscription?.cancel();
    super.dispose();
  }
}

bool _isActivePayoutStatus(dynamic value) {
  final status = value?.toString().trim().toLowerCase() ?? 'requested';
  return status != 'paid' &&
      status != 'completed' &&
      status != 'rejected' &&
      status != 'failed' &&
      status != 'cancelled' &&
      status != 'canceled';
}
