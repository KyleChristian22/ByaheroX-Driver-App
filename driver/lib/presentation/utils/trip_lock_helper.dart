import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../widgets/app_feedback.dart';

class TripLockHelper {
  static bool _isLockEnabled = false;

  static bool get isLockEnabled => _isLockEnabled;

  static Future<void> enableTripLockMode() async {
    if (_isLockEnabled) return;

    _isLockEnabled = true;

    await SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.immersiveSticky,
    );

    debugPrint('[TripLock] Enabled - immersive mode active');
  }

  static Future<void> disableTripLockMode() async {
    if (!_isLockEnabled) return;

    _isLockEnabled = false;

    await SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.edgeToEdge,
    );

    debugPrint('[TripLock] Disabled - normal UI restored');
  }

  static bool showTripLockWarning(
    BuildContext context, {
    String? customMessage,
  }) {
    if (!_isLockEnabled) return false;

    final message = customMessage ??
        'You cannot leave this screen while the trip is active.';

    AppFeedback.show(
      context,
      message: message,
      backgroundColor: const Color(0xFFDC2626),
    );

    return true;
  }

  static bool shouldBlockNavigation(BuildContext context) {
    if (!_isLockEnabled) return false;

    showTripLockWarning(context);
    return true;
  }

  static void handleAppLifecycle(
    BuildContext context,
    AppLifecycleState state,
  ) {
    switch (state) {
      case AppLifecycleState.resumed:
        if (_isLockEnabled) {
          SystemChrome.setEnabledSystemUIMode(
            SystemUiMode.immersiveSticky,
          );
          debugPrint('[TripLock] App resumed - immersive restored');
        }
        break;

      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        debugPrint('[TripLock] App backgrounded - lock state preserved');
        break;

      case AppLifecycleState.detached:
        debugPrint('[TripLock] App detached');
        break;
    }
  }

  static Future<void> forceDisableLock() async {
    _isLockEnabled = false;
    await SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.edgeToEdge,
    );
  }
}

mixin TripLockMixin<T extends StatefulWidget>
    on State<T>, WidgetsBindingObserver {
  void initTripLockObserver() {
    WidgetsBinding.instance.addObserver(this);
  }

  void disposeTripLockObserver() {
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    TripLockHelper.handleAppLifecycle(context, state);
  }
}
