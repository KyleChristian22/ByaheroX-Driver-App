import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

class AppPermissionService {
  const AppPermissionService._();

  static const MethodChannel _deviceSettingsChannel =
      MethodChannel('byaherox/device_settings');

  static Future<void> requestStartupPermissions() async {
    final openedLocationSettings = await _requestLocationPermission();
    if (openedLocationSettings) return;

    await _activateNfcIfAvailable();
  }

  static Future<bool> _requestLocationPermission() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();

      if (!serviceEnabled) {
        debugPrint('Location service is off. Opening location settings.');
        await Geolocator.openLocationSettings();
        return true;
      }

      var permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      debugPrint('Location permission status: $permission');
    } catch (error) {
      debugPrint('Location permission request failed: $error');
    }

    return false;
  }

  static Future<void> _activateNfcIfAvailable() async {
    try {
      final status = await _deviceSettingsChannel.invokeMapMethod<String, bool>(
        'getNfcStatus',
      );

      final supported = status?['supported'] ?? false;
      final enabled = status?['enabled'] ?? false;

      debugPrint('NFC status: supported=$supported, enabled=$enabled');

      if (supported && !enabled) {
        debugPrint('NFC is off. Opening NFC settings.');
        await _deviceSettingsChannel.invokeMethod<void>('openNfcSettings');
      }
    } on MissingPluginException {
      debugPrint('NFC settings activation is not available on this platform.');
    } catch (error) {
      debugPrint('NFC activation check failed: $error');
    }
  }
}
