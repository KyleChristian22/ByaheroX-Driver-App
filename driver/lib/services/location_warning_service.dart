import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:app_settings/app_settings.dart';

/// Location Warning Service - Manages GPS and location permission warnings
///
/// Features:
/// - Prevents SnackBar spam with cooldown mechanism
/// - Only shows warnings when state changes
/// - Clear, user-friendly messages
/// - Action buttons for settings access
enum LocationWarningType {
  locationServiceDisabled,
  permissionDenied,
  permissionDeniedForever,
  weakSignal,
}

class LocationWarningState {
  final LocationWarningType type;
  final DateTime timestamp;

  LocationWarningState({
    required this.type,
    required this.timestamp,
  });
}

class LocationWarningService {
  /// Cooldown duration between showing the same warning
  static const Duration _warningCooldown = Duration(seconds: 45);

  /// Track last warning state by type
  static final Map<LocationWarningType, LocationWarningState>
      _lastWarningState = {};

  /// Check if enough time has passed to show another warning of the same type
  static bool _canShowWarning(LocationWarningType type) {
    final lastState = _lastWarningState[type];
    if (lastState == null) {
      return true;
    }

    final timeSinceLastWarning = DateTime.now().difference(lastState.timestamp);
    return timeSinceLastWarning >= _warningCooldown;
  }

  /// Record that a warning was shown
  static void _recordWarning(LocationWarningType type) {
    _lastWarningState[type] = LocationWarningState(
      type: type,
      timestamp: DateTime.now(),
    );
  }

  /// Show a warning SnackBar if cooldown allows
  static void _showWarningSnackBar({
    required BuildContext context,
    required LocationWarningType type,
    required String message,
    required String? actionLabel,
    required VoidCallback? onAction,
    Color backgroundColor = Colors.red,
  }) {
    if (!_canShowWarning(type)) {
      debugPrint('SnackBar cooldown active for warning type: $type');
      return;
    }

    _recordWarning(type);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: backgroundColor,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
        action: actionLabel != null && onAction != null
            ? SnackBarAction(
                label: actionLabel,
                textColor: Colors.white,
                onPressed: onAction,
              )
            : null,
      ),
    );
  }

  /// Check location service and permission, return true if all is good
  /// Shows appropriate warnings if issues are found
  static Future<bool> checkLocationServiceAndPermission(
    BuildContext context, {
    bool showWarnings = true,
    bool requestIfDenied = true,
  }) async {
    // Check if location service is enabled
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) {
      if (showWarnings && context.mounted) {
        _showWarningSnackBar(
          context: context,
          type: LocationWarningType.locationServiceDisabled,
          message:
              'Live tracking is paused because GPS is turned off. Turn on Location/GPS to share your jeepney location.',
          actionLabel: 'Enable GPS',
          onAction: () => Geolocator.openLocationSettings(),
          backgroundColor: Colors.red,
        );
      }
      return false;
    }

    // Check location permission
    LocationPermission permission = await Geolocator.checkPermission();

    // Request permission if not yet determined
    if (permission == LocationPermission.denied) {
      if (requestIfDenied) {
        permission = await Geolocator.requestPermission();
      }

      // If still denied after request
      if (permission == LocationPermission.denied) {
        if (showWarnings && context.mounted) {
          _showWarningSnackBar(
            context: context,
            type: LocationWarningType.permissionDenied,
            message:
                'Location permission was denied. Allow location access so passengers can see your live jeepney location.',
            actionLabel: 'Allow',
            onAction: () => Geolocator.requestPermission(),
            backgroundColor: Colors.red,
          );
        }
        return false;
      }
    }

    // Permission permanently denied
    if (permission == LocationPermission.deniedForever) {
      if (showWarnings && context.mounted) {
        _showWarningSnackBar(
          context: context,
          type: LocationWarningType.permissionDeniedForever,
          message:
              'Location permission is permanently denied. Open app settings and allow location access to resume live tracking.',
          actionLabel: 'Open Settings',
          onAction: () => AppSettings.openAppSettings(),
          backgroundColor: Colors.red,
        );
      }
      return false;
    }

    return true;
  }

  /// Show warning for GPS service disabled
  static void showGpsDisabledWarning(BuildContext context) {
    _showWarningSnackBar(
      context: context,
      type: LocationWarningType.locationServiceDisabled,
      message:
          'Live tracking is paused because GPS is turned off. Turn on Location/GPS to share your jeepney location.',
      actionLabel: 'Enable GPS',
      onAction: () => Geolocator.openLocationSettings(),
      backgroundColor: Colors.red,
    );
  }

  /// Show warning for permission denied
  static void showPermissionDeniedWarning(BuildContext context) {
    _showWarningSnackBar(
      context: context,
      type: LocationWarningType.permissionDenied,
      message:
          'Location permission was denied. Allow location access so passengers can see your live jeepney location.',
      actionLabel: 'Allow',
      onAction: () => Geolocator.requestPermission(),
      backgroundColor: Colors.red,
    );
  }

  /// Show warning for permission permanently denied
  static void showPermissionPermanentlyDeniedWarning(BuildContext context) {
    _showWarningSnackBar(
      context: context,
      type: LocationWarningType.permissionDeniedForever,
      message:
          'Location permission is permanently denied. Open app settings and allow location access to resume live tracking.',
      actionLabel: 'Open Settings',
      onAction: () => AppSettings.openAppSettings(),
      backgroundColor: Colors.red,
    );
  }

  /// Show warning for weak internet connection
  static void showWeakSignalWarning(BuildContext context) {
    _showWarningSnackBar(
      context: context,
      type: LocationWarningType.weakSignal,
      message:
          'Weak internet connection. Your live location update failed and may be delayed.',
      actionLabel: null,
      onAction: null,
      backgroundColor: const Color(0xFFF59E0B), // Orange for warnings
    );
  }

  /// Clear all warning cooldowns (useful for testing or app restart)
  static void resetWarningCooldowns() {
    _lastWarningState.clear();
  }
}
