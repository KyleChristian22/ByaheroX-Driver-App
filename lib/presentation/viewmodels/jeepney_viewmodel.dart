import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/firestore_service.dart';
import '../../services/heavy_data_loader.dart';

/// Jeepney ViewModel for Driver App
class JeepneyViewModel extends ChangeNotifier {
  String _driverName = 'Driver';
  String _driverId = '';
  String _jeepneyId = 'No Jeepney Assigned';
  String _plateNumber = 'N/A';
  String _currentRouteName = 'No Route Assigned';
  int _capacity = 0;
  String _scheduleTime = '';
  bool _isLoading = false;
  String? _error;

  StreamSubscription<DocumentSnapshot>? _driverDocSubscription;
  StreamSubscription<DocumentSnapshot>? _assignmentDocSubscription;
  StreamSubscription<DocumentSnapshot>? _jeepneyDocSubscription;

  // Getters
  String get driverName => _driverName;
  String get driverId => _driverId;
  String get jeepneyId => _jeepneyId;
  String get plateNumber => _plateNumber;
  String get currentRouteName => _currentRouteName;
  int get capacity => _capacity;
  String get scheduleTime => _scheduleTime;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// Check if driver has an assigned jeepney
  /// Returns false when loading (empty jeepneyId) or when no jeepney is assigned
  bool get hasAssignedJeepney =>
      _jeepneyId.isNotEmpty && _jeepneyId != 'No Jeepney Assigned';

  JeepneyViewModel() {
    // Don't load here - wait for user to be authenticated first
    // loadDriverData() will be called explicitly after login
  }

  /// Load driver data from Firestore (using background isolate to prevent ANR)
  Future<void> loadDriverData() async {
    // Don't start loading if not authenticated
    final firebaseUid = FirebaseAuth.instance.currentUser?.uid;
    if (firebaseUid == null) {
      _error = 'Not logged in';
      _isLoading = false;
      notifyListeners();
      return;
    }

    _isLoading = true;
    _error = null;
    // Clear current jeepney data while loading to avoid showing stale data
    _jeepneyId = '';
    _plateNumber = '';
    notifyListeners();

    try {
      // Run heavy data loading in background isolate to avoid blocking main thread
      final result =
          await HeavyDataLoader.loadDriverDataInBackground(firebaseUid);

      if (result.error != null) {
        _error = result.error;
        // Fallback to email-based name
        final driverEmail = FirestoreService.getCurrentDriverEmail();
        if (driverEmail != null) {
          _driverName = driverEmail.split('@').first;
          _driverName = _driverName[0].toUpperCase() + _driverName.substring(1);
        }
      } else {
        if (result.driverName != null) {
          _driverName = result.driverName!;
        }
        if (result.driverId != null) {
          _driverId = result.driverId!;
        }
        if (result.jeepneyId != null) {
          _jeepneyId = result.jeepneyId!;
          _plateNumber = result.plateNumber ?? 'N/A';
          _currentRouteName = result.routeName ?? 'No Route Assigned';
          _capacity = result.capacity ?? 0;
          _scheduleTime = result.scheduleTime ?? '';
        } else {
          _jeepneyId = 'No Jeepney Assigned';
          _plateNumber = 'N/A';
          _currentRouteName = 'No Route Assigned';
          _scheduleTime = '';
        }
      }

      _isLoading = false;
      notifyListeners();

      // Set up real-time listener on the driver document after successful load
      _startWatchingDriverAssignment();
    } catch (e) {
      _error = FirestoreService.userFriendlyMessageForError(e);
      _isLoading = false;
      final driverEmail = FirestoreService.getCurrentDriverEmail();
      if (driverEmail != null) {
        _driverName = driverEmail.split('@').first;
        _driverName = _driverName[0].toUpperCase() + _driverName.substring(1);
      }
      _jeepneyId = 'No Jeepney Assigned';
      _plateNumber = 'N/A';
      _currentRouteName = 'No Route Assigned';
      _scheduleTime = '';
      notifyListeners();
    }
  }

  void _startWatchingDriverAssignment() {
    _cancelSubscriptions();

    final driverDocId = _driverId.isNotEmpty ? _driverId : null;
    final firebaseEmail = FirebaseAuth.instance.currentUser?.email;
    if (driverDocId == null && firebaseEmail == null) return;

    // Watch the driver document for changes to assignedJeepneyId
    if (driverDocId != null) {
      _driverDocSubscription = FirebaseFirestore.instance
          .collection('driver')
          .doc(driverDocId)
          .snapshots()
          .listen((snapshot) {
        if (!snapshot.exists) return;
        final data = snapshot.data()!;
        final assignedId = _extractAssignedId(data);
        final currentId = _jeepneyId == 'No Jeepney Assigned' ? '' : _jeepneyId;

        if (assignedId == null || assignedId.isEmpty) {
          if (currentId.isNotEmpty) {
            _jeepneyId = 'No Jeepney Assigned';
            _plateNumber = 'N/A';
            _currentRouteName = 'No Route Assigned';
            _capacity = 0;
            _scheduleTime = '';
            _stopWatchingAssignedJeepney();
            notifyListeners();
          }
        } else if (assignedId != currentId) {
          _jeepneyId = assignedId;
          _currentRouteName = '';
          _capacity = 0;
          _scheduleTime = '';
          _startWatchingAssignedJeepney(assignedId);
          notifyListeners();
        }
      }, onError: (error) {
        debugPrint('[JeepneyViewModel] Error watching driver doc: $error');
      });
    }

    // Also watch the trip_schedule_driver_assignments doc for today
    final today = FirestoreService.getTodayDateKey();
    final watchId = driverDocId ?? firebaseEmail;
    if (watchId != null) {
      final safeId = FirestoreService.safeFirestoreId(watchId);
      _assignmentDocSubscription = FirebaseFirestore.instance
          .collection('trip_schedule_driver_assignments')
          .doc('${today}_$safeId')
          .snapshots()
          .listen((snapshot) {
        if (!snapshot.exists && driverDocId != null) {
          FirebaseFirestore.instance
              .collection('driver')
              .doc(driverDocId)
              .get()
              .then((driverSnapshot) {
            if (!driverSnapshot.exists) return;
            final data = driverSnapshot.data()!;
            final assignedId = _extractAssignedId(data);
            if (assignedId == null || assignedId.isEmpty) {
              _jeepneyId = 'No Jeepney Assigned';
              _plateNumber = 'N/A';
              _currentRouteName = 'No Route Assigned';
              _capacity = 0;
              _scheduleTime = '';
              _stopWatchingAssignedJeepney();
              notifyListeners();
            }
          });
        }
      }, onError: (error) {
        debugPrint('[JeepneyViewModel] Error watching assignment doc: $error');
      });
    }

    _startWatchingAssignedJeepney(_jeepneyId);
  }

  void _startWatchingAssignedJeepney(String jeepneyId) {
    final normalizedId = jeepneyId.trim();
    if (normalizedId.isEmpty || normalizedId == 'No Jeepney Assigned') {
      _stopWatchingAssignedJeepney();
      return;
    }

    _jeepneyDocSubscription?.cancel();
    _jeepneyDocSubscription = FirebaseFirestore.instance
        .collection('jeeps')
        .doc(normalizedId)
        .snapshots()
        .listen((snapshot) {
      final rawData = snapshot.data();
      if (rawData is! Map<String, dynamic>) return;

      var changed = false;
      final capacity = _intFromJeepneyData(rawData);
      if (capacity > 0 && capacity != _capacity) {
        _capacity = capacity;
        changed = true;
      }

      final plateNumber = rawData['plateNumber']?.toString().trim() ?? '';
      if (plateNumber.isNotEmpty && plateNumber != _plateNumber) {
        _plateNumber = plateNumber;
        changed = true;
      }

      if (changed) notifyListeners();
    }, onError: (error) {
      debugPrint('[JeepneyViewModel] Error watching jeepney doc: $error');
    });
  }

  void _stopWatchingAssignedJeepney() {
    _jeepneyDocSubscription?.cancel();
    _jeepneyDocSubscription = null;
  }

  int _intFromJeepneyData(Map<String, dynamic> data) {
    for (final key in const [
      'maxCapacity',
      'capacity',
      'seatingCapacity',
      'maxPassengers',
    ]) {
      final value = data[key];
      if (value is int) return value;
      if (value is num) return value.round();
      if (value is String) {
        final parsed = int.tryParse(value.trim());
        if (parsed != null) return parsed;
      }
    }
    return 0;
  }

  String? _extractAssignedId(Map<String, dynamic> data) {
    final raw = data['assignedJeepneyId'];
    if (raw != null) {
      final val = raw.toString().trim();
      if (val.isNotEmpty && val.toLowerCase() != 'null') return val;
    }
    final raw2 = data['assignedJeepId'];
    if (raw2 != null) {
      final val = raw2.toString().trim();
      if (val.isNotEmpty && val.toLowerCase() != 'null') return val;
    }
    return null;
  }

  void _cancelSubscriptions() {
    _driverDocSubscription?.cancel();
    _driverDocSubscription = null;
    _assignmentDocSubscription?.cancel();
    _assignmentDocSubscription = null;
    _jeepneyDocSubscription?.cancel();
    _jeepneyDocSubscription = null;
  }

  /// Refresh driver data
  Future<void> refresh() async {
    _cancelSubscriptions();
    await loadDriverData();
    notifyListeners();
  }

  /// Initialize driver data - call this after login
  Future<void> initializeAfterLogin() async {
    await loadDriverData();
  }

  /// Clear error
  void clearError() {
    _error = null;
    notifyListeners();
  }

  void resetState() {
    _cancelSubscriptions();
    _driverName = 'Driver';
    _driverId = '';
    _jeepneyId = 'No Jeepney Assigned';
    _plateNumber = 'N/A';
    _currentRouteName = 'No Route Assigned';
    _capacity = 0;
    _scheduleTime = '';
    _isLoading = false;
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _cancelSubscriptions();
    super.dispose();
  }
}
