import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

/// Simple internet connectivity service
class InternetConnectivityService {
  static final Connectivity _connectivity = Connectivity();
  static StreamSubscription<List<ConnectivityResult>>? _subscription;

  /// Callback when connectivity changes
  static VoidCallback? _onConnectivityChanged;

  /// Last known connectivity status
  static List<ConnectivityResult> _lastStatus = [];

  /// Check if device currently has internet connection
  static Future<bool> hasInternetConnection() async {
    try {
      final result = await _connectivity.checkConnectivity();
      return _isConnected(result);
    } catch (e) {
      debugPrint('Error checking connectivity: $e');
      return false;
    }
  }

  /// Check if result indicates connected state
  static bool _isConnected(List<ConnectivityResult> result) {
    return !result.contains(ConnectivityResult.none);
  }

  /// Start monitoring connectivity changes
  static void startMonitoring({
    VoidCallback? onConnectivityChanged,
  }) {
    _onConnectivityChanged = onConnectivityChanged;

    _subscription?.cancel();
    _subscription = _connectivity.onConnectivityChanged.listen((result) {
      _lastStatus = result;
      if (_onConnectivityChanged != null) {
        _onConnectivityChanged!();
      }
    });
  }

  /// Stop monitoring connectivity changes
  static void stopMonitoring() {
    _subscription?.cancel();
    _subscription = null;
    _onConnectivityChanged = null;
  }

  /// Get current connectivity status
  static List<ConnectivityResult> getLastStatus() {
    return _lastStatus;
  }

  /// Check if on mobile/cellular network
  static bool isOnMobileNetwork() {
    return _lastStatus.contains(ConnectivityResult.mobile);
  }

  /// Check if on WiFi network
  static bool isOnWiFi() {
    return _lastStatus.contains(ConnectivityResult.wifi);
  }
}
