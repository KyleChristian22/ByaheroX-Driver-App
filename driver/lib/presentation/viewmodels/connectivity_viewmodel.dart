import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ConnectivityViewModel extends ChangeNotifier {
  ConnectivityViewModel() {
    _initialize();
  }

  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  Timer? _offlineRetryTimer;
  int _checkGeneration = 0;

  bool _isOffline = false;
  bool _hasCheckedConnection = false;

  bool get isOffline => _isOffline;
  bool get hasCheckedConnection => _hasCheckedConnection;

  Future<void> _initialize() async {
    await _checkCurrentConnection();
    _subscription = _connectivity.onConnectivityChanged.listen(
      (results) => _handleConnectivityChange(results),
      onError: (Object error) {
        debugPrint('Connectivity monitor error: $error');
      },
    );
  }

  Future<void> _checkCurrentConnection() async {
    try {
      final results = await _connectivity.checkConnectivity();
      await _updateConnectionStatus(results);
    } catch (error) {
      debugPrint('Connectivity check failed: $error');
      _setOffline(true, hasCheckedConnection: true);
    }
  }

  Future<void> _handleConnectivityChange(List<ConnectivityResult> results) {
    return _updateConnectionStatus(results);
  }

  Future<void> _updateConnectionStatus(List<ConnectivityResult> results) async {
    final generation = ++_checkGeneration;

    if (_isDisconnected(results)) {
      _setOffline(true, hasCheckedConnection: true);
      return;
    }

    if (kIsWeb) {
      _setOffline(false, hasCheckedConnection: true);
      return;
    }

    final hasInternet = await _hasInternetAccess();
    if (generation != _checkGeneration) return;

    _setOffline(!hasInternet, hasCheckedConnection: true);
  }

  bool _isDisconnected(List<ConnectivityResult> results) {
    return results.isEmpty ||
        results.every((result) => result == ConnectivityResult.none);
  }

  Future<bool> _hasInternetAccess() async {
    try {
      final response = await http
          .get(Uri.parse('https://www.gstatic.com/generate_204'))
          .timeout(const Duration(seconds: 4));

      return response.statusCode >= 200 && response.statusCode < 400;
    } catch (error) {
      debugPrint('Internet reachability check failed: $error');
      return false;
    }
  }

  void _setOffline(bool value, {required bool hasCheckedConnection}) {
    if (_isOffline == value && _hasCheckedConnection == hasCheckedConnection) {
      return;
    }

    _isOffline = value;
    _hasCheckedConnection = hasCheckedConnection;
    _syncOfflineRetryTimer();
    notifyListeners();
  }

  void _syncOfflineRetryTimer() {
    if (!_isOffline) {
      _offlineRetryTimer?.cancel();
      _offlineRetryTimer = null;
      return;
    }

    _offlineRetryTimer ??= Timer.periodic(
      const Duration(seconds: 5),
      (_) => _checkCurrentConnection(),
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _offlineRetryTimer?.cancel();
    super.dispose();
  }
}
