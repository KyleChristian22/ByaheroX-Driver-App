import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/services/app_session_service.dart';
import '../viewmodels/auth_viewmodel.dart';
import '../viewmodels/pickup_location_provider.dart';

/// Observes app lifecycle and clears pickup location when app is closed or sent to background
class AppLifecycleObserver extends StatefulWidget {
  final Widget child;

  const AppLifecycleObserver({super.key, required this.child});

  @override
  State<AppLifecycleObserver> createState() => _AppLifecycleObserverState();
}

class _AppLifecycleObserverState extends State<AppLifecycleObserver>
    with WidgetsBindingObserver {
  Timer? _backgroundTimer;
  Timer? _sessionHeartbeatTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startSessionHeartbeat();
  }

  void _startSessionHeartbeat() {
    // Start session immediately
    AppSessionService.startOrResumeCommuterSession();

    // Set up periodic heartbeat every 30 seconds to keep session alive
    _sessionHeartbeatTimer?.cancel();
    _sessionHeartbeatTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => AppSessionService.heartbeatCommuterSession(),
    );
    debugPrint(
      'AppLifecycleObserver: Session heartbeat started (30s interval)',
    );
  }

  void _stopSessionHeartbeat() {
    _sessionHeartbeatTimer?.cancel();
    _sessionHeartbeatTimer = null;
    AppSessionService.stopCommuterSession();
    debugPrint('AppLifecycleObserver: Session heartbeat stopped');
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _backgroundTimer?.cancel();
    _sessionHeartbeatTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;

    final authViewModel = context.read<AuthViewModel>();
    final pickupProvider = context.read<PickupLocationProvider>();

    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        // App is going to background
        // Stop session heartbeat when app goes to background
        _stopSessionHeartbeat();

        // Start a timer to clear location after 5 minutes in background
        _backgroundTimer?.cancel();
        _backgroundTimer = Timer(const Duration(minutes: 5), () {
          if (!mounted) return;

          if (authViewModel.isLoggedIn && !authViewModel.currentUser.isGuest) {
            debugPrint(
              'AppLifecycleObserver: Clearing pickup location after 5 min in background',
            );
            pickupProvider.clearPickupLocation(authViewModel.currentUser.id);
          }
        });
        break;

      case AppLifecycleState.resumed:
        // App is back to foreground - restart session heartbeat
        _backgroundTimer?.cancel();
        _startSessionHeartbeat();
        debugPrint(
          'AppLifecycleObserver: App resumed, session heartbeat restarted',
        );
        break;

      case AppLifecycleState.detached:
        // App is being terminated - stop session
        _stopSessionHeartbeat();
        // Note: This may not always complete before app terminates
        if (authViewModel.isLoggedIn && !authViewModel.currentUser.isGuest) {
          debugPrint(
            'AppLifecycleObserver: App detached, clearing pickup location',
          );
          pickupProvider.clearPickupLocation(
            authViewModel.currentUser.id,
            force: true,
          );
        }
        break;

      case AppLifecycleState.hidden:
        // App is hidden (new in Flutter 3.13+)
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
