import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../icons/jeep_icon.dart';
import '../../../services/analytics_tracking_service.dart';
import '../../../services/firestore_service.dart';
import '../../viewmodels/trip_viewmodel.dart';
import '../../viewmodels/jeepney_viewmodel.dart';
import '../../viewmodels/language_viewmodel.dart';
import '../../utils/trip_lock_helper.dart';
import 'home_screen.dart';
import '../trip/trip_screen.dart';
import '../profile/profile_screen.dart';
import '../earnings/earnings_screen.dart';

/// Main Navigation Screen with Bottom Navigation Bar
class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen>
    with WidgetsBindingObserver {
  int _currentIndex = 0;
  bool _wasTripActive = false;
  bool _previousTripActiveState = false;
  int _tripScreenKey = 0;
  bool _isInitializing = true;

  late List<Widget> _screens;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
      _tripScheduleSubscription;
  Timer? _autoStartTripTimer;
  Timer? _reassignmentDebounceTimer;
  String? _lastWatchedJeepneyId;
  String? _autoStartedScheduleId;
  bool _isReassigning = false;

  @override
  void initState() {
    super.initState();
    debugPrint('[MainNav] initState STARTED');
    WidgetsBinding.instance.addObserver(this);
    _buildScreens();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      debugPrint('[MainNav] postFrameCallback STARTED');
      try {
        final jeepneyVM = context.read<JeepneyViewModel>();
        final tripVM = context.read<TripViewModel>();

        debugPrint('[MainNav] hasAssignedJeepney: ${jeepneyVM.hasAssignedJeepney}');
        debugPrint('[MainNav] jeepneyId: ${jeepneyVM.jeepneyId}');
        debugPrint('[MainNav] isTripActive: ${tripVM.isTripActive}');

        if (jeepneyVM.hasAssignedJeepney) {
          _lastWatchedJeepneyId = jeepneyVM.jeepneyId;
          debugPrint('[MainNav] Checking trip status for: ${jeepneyVM.jeepneyId}');
          final isOnTrip = await _checkJeepneyOnTrip(jeepneyVM.jeepneyId);
          debugPrint('[MainNav] isOnTrip result: $isOnTrip');
          if (isOnTrip && mounted) {
            debugPrint('[MainNav] ON-TRIP DETECTED! Navigating to Trip tab');
            if (!tripVM.isTripActive) {
              tripVM.startTrip();
            }
            setState(() => _currentIndex = 1);
            debugPrint('[MainNav] Current index set to: $_currentIndex');
          }
          _tryWatchSchedules(jeepneyVM.jeepneyId);
        } else {
          debugPrint('[MainNav] No jeepney assigned');
        }

        _previousTripActiveState = tripVM.isTripActive;
        debugPrint('[MainNav] _previousTripActiveState set to: $_previousTripActiveState');

        _isInitializing = false;
        tripVM.addListener(_onTripStateChanged);
        jeepneyVM.addListener(_onJeepneyChanged);
        debugPrint('[MainNav] postFrameCallback COMPLETED');
      } catch (e, stack) {
        debugPrint('[MainNav] ERROR in postFrameCallback: $e');
        debugPrint('[MainNav] Stack: $stack');
        _isInitializing = false;
      }
    });
  }

  void _buildScreens() {
    _screens = [
      HomeScreen(onNavigate: _onNavigate),
      TripScreen(key: ValueKey('trip_$_tripScreenKey')),
      const EarningsScreen(),
      const ProfileScreen(),
    ];
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final tripViewModel = context.read<TripViewModel>();
    if (tripViewModel.isTripActive) {
      TripLockHelper.handleAppLifecycle(context, state);
    }
  }

  void _handleTripStateChange(bool isTripActive) {
    if (isTripActive == _wasTripActive) return;
    _wasTripActive = isTripActive;
    if (isTripActive) {
      TripLockHelper.enableTripLockMode();
    } else {
      TripLockHelper.disableTripLockMode();
    }
  }

  void _onNavigate(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  void _onTripStateChanged() {
    if (!mounted) return;
    final tripVM = context.read<TripViewModel>();
    final bool isCurrentlyActive = tripVM.isTripActive;

    if (isCurrentlyActive != _previousTripActiveState) {
      debugPrint('[MainNav] Trip state changed: $_previousTripActiveState -> $isCurrentlyActive');
      if (isCurrentlyActive && _currentIndex != 1) {
        setState(() => _currentIndex = 1);
      } else if (!isCurrentlyActive && _currentIndex == 1) {
        setState(() => _currentIndex = 0);
      }
      _previousTripActiveState = isCurrentlyActive;
    }
  }

  Future<bool> _checkJeepneyOnTrip(String jeepneyId) async {
    debugPrint('[MainNav] _checkJeepneyOnTrip called for: $jeepneyId');
    try {
      final doc = await FirebaseFirestore.instance
          .collection('locations')
          .doc(jeepneyId)
          .get();
      debugPrint('[MainNav] Location doc exists: ${doc.exists}');
      if (doc.exists) {
        final data = doc.data()!;
        debugPrint('[MainNav] Location data keys: ${data.keys.join(", ")}');
        debugPrint('[MainNav] isOnTrip: ${data['isOnTrip']}');
        debugPrint('[MainNav] onTrip: ${data['onTrip']}');
        debugPrint('[MainNav] tripStatus: ${data['tripStatus']}');
        final isOnTrip = data['isOnTrip'] == true ||
            data['onTrip'] == true ||
            data['tripStatus'] == 'active';
        debugPrint('[MainNav] Result: isOnTrip = $isOnTrip');
        return isOnTrip;
      }
      debugPrint('[MainNav] Location document does NOT exist');
      return false;
    } catch (e) {
      debugPrint('[MainNav] Error checking trip: $e');
      return false;
    }
  }

  void _onJeepneyChanged() {
    if (_isReassigning || _isInitializing) return;

    final jeepneyVM = context.read<JeepneyViewModel>();
    final String? newId =
        jeepneyVM.hasAssignedJeepney ? jeepneyVM.jeepneyId : null;

    if (newId == null || newId == _lastWatchedJeepneyId) return;

    _reassignmentDebounceTimer?.cancel();
    _reassignmentDebounceTimer = Timer(const Duration(milliseconds: 500), () {
      if (!mounted || _isReassigning) return;
      final currentId = context.read<JeepneyViewModel>().hasAssignedJeepney
          ? context.read<JeepneyViewModel>().jeepneyId
          : null;
      if (currentId == null || currentId == _lastWatchedJeepneyId) return;
      unawaited(_handleReassignment(_lastWatchedJeepneyId, currentId));
    });
  }

  Future<void> _handleReassignment(
      String? oldJeepneyId, String? newJeepneyId) async {
    if (_isReassigning) return;
    if (newJeepneyId == null) {
      _lastWatchedJeepneyId = null;
      _tripScheduleSubscription?.cancel();
      _autoStartTripTimer?.cancel();
      context.read<TripViewModel>().reset();
      setState(() {
        _tripScreenKey++;
        _buildScreens();
      });
      return;
    }

    _isReassigning = true;

    debugPrint('[MainNav] Reassigned $oldJeepneyId -> $newJeepneyId');

    try {
      _tripScheduleSubscription?.cancel();
      _autoStartTripTimer?.cancel();
      _autoStartedScheduleId = null;

      if (oldJeepneyId != null) {
        final oldLocationDoc = await FirebaseFirestore.instance
            .collection('locations')
            .doc(oldJeepneyId)
            .get();
        final oldLocationData = oldLocationDoc.data() ?? <String, dynamic>{};
        final wasOnTrip = oldLocationData['isOnTrip'] == true ||
            oldLocationData['onTrip'] == true;

        if (wasOnTrip) {
          await AnalyticsTrackingService.startTrip(
            jeepneyId: oldJeepneyId,
            routeId: _firstNonEmpty([oldLocationData['routeId']]),
            routeName: _firstNonEmpty([
              oldLocationData['routeName'],
              oldLocationData['currentRoute'],
              oldLocationData['route'],
            ]),
            originTerminal: _firstNonEmpty([oldLocationData['originTerminal']]),
            destinationTerminal: _firstNonEmpty([
              oldLocationData['destinationTerminal'],
              oldLocationData['destination'],
            ]),
          );
          await AnalyticsTrackingService.endTrip(jeepneyId: oldJeepneyId);
        }

        await FirebaseFirestore.instance
            .collection('locations')
            .doc(oldJeepneyId)
            .set({
          'isOnTrip': false,
          'onTrip': false,
          'isOnline': false,
          'online': false,
          'status': 'offline',
          'tripStatus': 'ended',
          'tripEndedAt': FieldValue.serverTimestamp(),
          'endedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      if (!mounted) return;

      context.read<TripViewModel>().reset();

      setState(() {
        _tripScreenKey++;
        _buildScreens();
      });

      _lastWatchedJeepneyId = newJeepneyId;
      _tryWatchSchedules(newJeepneyId);

      final isNewOnTrip = await _checkJeepneyOnTrip(newJeepneyId);
      if (isNewOnTrip && mounted) {
        final tripVM = context.read<TripViewModel>();
        if (!tripVM.isTripActive) {
          tripVM.startTrip();
        }
        setState(() => _currentIndex = 1);
      }
    } finally {
      _isReassigning = false;
    }
  }

  void _tryWatchSchedules(String jeepneyId) {
    final cleanId = jeepneyId.trim();
    if (cleanId.isEmpty || cleanId == _lastWatchedJeepneyId) return;
    _lastWatchedJeepneyId = cleanId;
    _startWatchingTripSchedules(cleanId);
  }

  void _startWatchingTripSchedules(String jeepneyId) {
    _tripScheduleSubscription?.cancel();
    _autoStartTripTimer?.cancel();

    final cleanId = jeepneyId.trim();
    if (cleanId.isEmpty) return;

    final today = FirestoreService.getTodayDateKey();

    debugPrint('[MainNav] Watching trip schedules for $cleanId');

    _tripScheduleSubscription = FirebaseFirestore.instance
        .collection('trip_schedules')
        .where('scheduleDate', isEqualTo: today)
        .where('jeepneyId', isEqualTo: cleanId)
        .snapshots()
        .listen(
      (snapshot) {
        debugPrint(
            '[MainNav] Schedules snapshot received: ${snapshot.docs.length} docs');
        final schedules =
            snapshot.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();

        if (schedules.isEmpty) return;

        schedules.sort((a, b) {
          final aTime = _scheduleDateTime(a);
          final bTime = _scheduleDateTime(b);
          if (aTime != null && bTime != null) return aTime.compareTo(bTime);
          if (aTime != null) return -1;
          if (bTime != null) return 1;
          return 0;
        });

        Map<String, dynamic>? targetSchedule;
        for (final s in schedules) {
          if (_isCompleted(s)) continue;
          if (_isBeforeDriverAssignment(s)) continue;
          targetSchedule = s;
          break;
        }

        if (targetSchedule != null) {
          _scheduleAutoStart(targetSchedule);
        }
      },
      onError: (error) {
        debugPrint('[MainNav] Schedule listener error: $error');
      },
    );
  }

  void _scheduleAutoStart(Map<String, dynamic> schedule) {
    final scheduleId = (schedule['id'] ?? '').toString().trim();
    if (scheduleId.isEmpty) return;

    if (scheduleId == _autoStartedScheduleId) return;

    _autoStartTripTimer?.cancel();

    final scheduledAt = _scheduleDateTime(schedule);
    if (scheduledAt == null) return;
    if (_isBeforeDriverAssignment(schedule)) {
      debugPrint(
          '[MainNav] Schedule is before driver assignment - skipping auto-start');
      return;
    }

    final now = DateTime.now();

    final tripVM = context.read<TripViewModel>();
    if (tripVM.isTripActive) {
      debugPrint('[MainNav] Trip already active - skipping auto-start');
      return;
    }

    if (now.isBefore(scheduledAt)) {
      final delay = scheduledAt.difference(now);
      debugPrint('[MainNav] Auto-start scheduled in ${delay.inMinutes} min');
      _autoStartTripTimer = Timer(delay, () => _performAutoStart(schedule));
    } else {
      debugPrint('[MainNav] Schedule time passed - auto-starting now');
      _autoStartTripTimer =
          Timer(Duration.zero, () => _performAutoStart(schedule));
    }
  }

  Future<void> _performAutoStart(Map<String, dynamic> schedule) async {
    if (!mounted) return;

    final tripVM = context.read<TripViewModel>();
    if (tripVM.isTripActive) return;

    final jeepneyId = (schedule['jeepneyId'] ?? '').toString().trim();
    final scheduleId = (schedule['id'] ?? '').toString().trim();
    if (jeepneyId.isEmpty || scheduleId.isEmpty) return;

    if (_isCompleted(schedule)) return;
    if (_isBeforeDriverAssignment(schedule)) return;

    final scheduledAt = _scheduleDateTime(schedule);
    if (scheduledAt == null) return;

    final now = DateTime.now();
    if (now.isBefore(scheduledAt)) {
      final delay = scheduledAt.difference(now);
      debugPrint(
          '[MainNav] Auto-start blocked before schedule time; retrying in ${delay.inMinutes} min');
      _autoStartTripTimer?.cancel();
      _autoStartTripTimer = Timer(delay, () => _performAutoStart(schedule));
      return;
    }

    _autoStartedScheduleId = scheduleId;

    try {
      debugPrint('[MainNav] Auto-starting trip for jeepney $jeepneyId');

      await FirebaseFirestore.instance
          .collection('locations')
          .doc(jeepneyId)
          .set({
        'jeepneyId': jeepneyId,
        'isOnTrip': true,
        'onTrip': true,
        'isOnline': true,
        'online': true,
        'status': 'active',
        'tripStatus': 'active',
        'updatedAt': FieldValue.serverTimestamp(),
        'timestamp': FieldValue.serverTimestamp(),
        'tripStartedAt': FieldValue.serverTimestamp(),
        'tripEndedAt': FieldValue.delete(),
        'endedAt': FieldValue.delete(),
      }, SetOptions(merge: true));

      await FirebaseFirestore.instance
          .collection('trip_schedules')
          .doc(scheduleId)
          .set({
        'status': 'active',
        'tripStatus': 'active',
        'isOnTrip': true,
        'onTrip': true,
        'tripStartedAt': FieldValue.serverTimestamp(),
        'tripEndedAt': FieldValue.delete(),
        'endedAt': FieldValue.delete(),
        'historyStatus': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      final routeLabel = _tripRouteLabel(schedule);
      if (routeLabel.isNotEmpty && routeLabel != 'Route not set') {
        tripVM.setRoute(routeLabel);
      }
      final terminal = _terminalFromSchedule(schedule);
      if (terminal != null) {
        tripVM.setDestination(terminal);
      }

      tripVM.startTrip();
      await AnalyticsTrackingService.startTrip(
        jeepneyId: jeepneyId,
        routeId: _firstNonEmpty([schedule['routeId']]),
        routeName: routeLabel,
        originTerminal: _firstNonEmpty([
          schedule['originTerminal'],
          schedule['origin'],
          schedule['from'],
        ]),
        destinationTerminal: _firstNonEmpty([
          schedule['destinationTerminal'],
          schedule['destination'],
          schedule['to'],
        ]),
      );

      if (!mounted) return;

      final langVM = context.read<LanguageViewModel>();
      final isTagalog = langVM.isTagalog;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isTagalog
                ? 'Awtomatikong nagsimula ang nakatakdang biyahe'
                : 'Scheduled trip started automatically',
          ),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );

      if (_currentIndex != 1) {
        setState(() => _currentIndex = 1);
      }

      debugPrint('[MainNav] Auto-start complete for $jeepneyId');
    } catch (e) {
      debugPrint('[MainNav] Auto-start failed: $e');
    }
  }

  bool _isCompleted(Map<String, dynamic> schedule) {
    final status = (schedule['status'] ?? '').toString().trim().toLowerCase();
    return status == 'completed' ||
        status == 'done' ||
        status == 'finished' ||
        status == 'active';
  }

  bool _isBeforeDriverAssignment(Map<String, dynamic> schedule) {
    final scheduledAt = _scheduleDateTime(schedule);
    final assignedAt = _assignmentDateTime(schedule);
    if (scheduledAt == null || assignedAt == null) return false;
    return scheduledAt.isBefore(assignedAt);
  }

  DateTime? _assignmentDateTime(Map<String, dynamic> schedule) {
    for (final value in [
      schedule['driverAssignedAt'],
      schedule['assignedAt'],
      schedule['assignmentCreatedAt'],
    ]) {
      final parsed = _dateTimeFromValue(value);
      if (parsed != null) return parsed;
    }
    return null;
  }

  DateTime? _dateTimeFromValue(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  String _firstNonEmpty(List<dynamic> values) {
    for (final value in values) {
      final text = value?.toString().trim() ?? '';
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  String _tripRouteLabel(Map<String, dynamic> schedule) {
    final origin = _firstNonEmpty([
      schedule['originTerminal'],
      schedule['origin'],
    ]);
    final destination = _firstNonEmpty([
      schedule['destinationTerminal'],
      schedule['destination'],
      schedule['to'],
    ]);
    if (origin.isNotEmpty && destination.isNotEmpty) {
      return '$origin to $destination';
    }
    return _firstNonEmpty([
      schedule['routeName'],
      schedule['route'],
      'Route not set',
    ]);
  }

  Terminal? _terminalFromSchedule(Map<String, dynamic> schedule) {
    final destination = _firstNonEmpty([
      schedule['destinationTerminal'],
      schedule['destination'],
      schedule['to'],
    ]).toLowerCase();
    final route = _firstNonEmpty([
      schedule['routeName'],
      schedule['route'],
      schedule['currentRoute'],
    ]).toLowerCase();

    if (destination.contains('lucban')) return Terminal.terminalA;
    if (destination.contains('sta') || destination.contains('santa')) {
      return Terminal.terminalB;
    }

    if (route.contains('sta') &&
        route.contains('cruz') &&
        route.contains('lucban')) {
      final lucbanIndex = route.indexOf('lucban');
      final staIndex = route.indexOf('sta');
      return staIndex < lucbanIndex ? Terminal.terminalA : Terminal.terminalB;
    }

    return null;
  }

  DateTime? _scheduleDateTime(Map<String, dynamic> schedule) {
    final scheduledAt = schedule['scheduledAt'];
    if (scheduledAt is Timestamp) return scheduledAt.toDate();
    if (scheduledAt is DateTime) return scheduledAt;

    final date = (schedule['scheduleDate'] ?? '').toString().trim();
    final time = (schedule['scheduleTime'] ?? '').toString().trim();
    if (date.isEmpty || time.isEmpty) return null;

    try {
      final parts = date.split('-');
      if (parts.length != 3) return null;
      final year = int.parse(parts[0]);
      final month = int.parse(parts[1]);
      final day = int.parse(parts[2]);

      final timeUpper = time.toUpperCase();
      final match12 =
          RegExp(r'^(\d{1,2}):(\d{2})\s*(AM|PM)$').firstMatch(timeUpper);
      if (match12 != null) {
        var hour = int.parse(match12.group(1)!);
        final minute = int.parse(match12.group(2)!);
        final period = match12.group(3)!;
        if (period == 'PM' && hour != 12) hour += 12;
        if (period == 'AM' && hour == 12) hour = 0;
        return DateTime(year, month, day, hour, minute);
      }

      final match24 = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(time);
      if (match24 != null) {
        return DateTime(
          year,
          month,
          day,
          int.parse(match24.group(1)!),
          int.parse(match24.group(2)!),
        );
      }
    } catch (_) {}

    return null;
  }

  NavigationDestination _buildDestination({
    required int index,
    required Widget icon,
    required Widget selectedIcon,
    required String label,
    required bool isTripActive,
    bool isTripTab = false,
  }) {
    final isDisabled = isTripActive && !isTripTab;

    return NavigationDestination(
      icon: isDisabled
          ? Opacity(
              opacity: 0.4,
              child: icon,
            )
          : icon,
      selectedIcon: isDisabled
          ? Opacity(
              opacity: 0.4,
              child: selectedIcon,
            )
          : selectedIcon,
      label: label,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tripViewModel = context.watch<TripViewModel>();
    debugPrint('[MainNav] BUILD called, _currentIndex: $_currentIndex, isTripActive: ${tripViewModel.isTripActive}');

    _handleTripStateChange(tripViewModel.isTripActive);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (didPop) return;

        final languageViewModel = context.read<LanguageViewModel>();
        final isTagalog = languageViewModel.isTagalog;

        if (tripViewModel.isTripActive) {
          TripLockHelper.showTripLockWarning(
            context,
            customMessage: isTagalog
                ? 'Hindi maaaring lumabas habang may aktibong biyahe. Tapusin muna ang biyahe.'
                : 'Cannot exit app while trip is active. End the trip first.',
          );
          return;
        }

        final bool? shouldExit = await showDialog<bool>(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: Text(isTagalog ? 'Lumabas sa App' : 'Exit App'),
              content: Text(isTagalog
                  ? 'Sigurado ka bang gusto mong lumabas sa app?'
                  : 'Are you sure you want to exit the app?'),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(isTagalog ? 'Kanselahin' : 'Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text(isTagalog ? 'Lumabas' : 'Exit'),
                ),
              ],
            );
          },
        );

        if (shouldExit == true && context.mounted) {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: _screens[_currentIndex],
        bottomNavigationBar: Consumer<TripViewModel>(
          builder: (context, tripVM, child) {
            final isTripActive = tripVM.isTripActive;
            final languageViewModel = context.read<LanguageViewModel>();
            final isTagalog = languageViewModel.isTagalog;

            return NavigationBar(
              selectedIndex: _currentIndex,
              onDestinationSelected: (index) {
                if (isTripActive && index != 1) {
                  TripLockHelper.showTripLockWarning(
                    context,
                    customMessage: isTagalog
                        ? 'Hindi maaaring buksan ang ibang tab habang may aktibong biyahe. Tapusin muna ang biyahe.'
                        : 'Cannot open other tabs while a trip is active. End the trip first.',
                  );
                  return;
                }

                if (index == 1) {
                  final jeepneyViewModel = context.read<JeepneyViewModel>();
                  if (jeepneyViewModel.isLoading) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(isTagalog
                            ? 'Naglo-load ng data... Pakisubukan muli'
                            : 'Loading data... Please try again'),
                        duration: const Duration(seconds: 1),
                      ),
                    );
                    return;
                  }
                  if (!jeepneyViewModel.hasAssignedJeepney) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(isTagalog
                            ? 'Mangyaring maghintay ng jeepney assignment para ma-access ang Biyahe'
                            : 'Please wait for a jeepney assignment to access Trip'),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                    return;
                  }
                }
                setState(() {
                  _currentIndex = index;
                });
              },
              destinations: [
                _buildDestination(
                  index: 0,
                  icon: const Icon(Icons.home_outlined),
                  selectedIcon: const Icon(Icons.home, color: AppTheme.primaryBlue),
                  label: isTagalog ? 'Dashboard' : 'Dashboard',
                  isTripActive: isTripActive,
                ),
                NavigationDestination(
                  icon: Consumer<JeepneyViewModel>(
                    builder: (context, jeepneyViewModel, child) {
                      final bool hasJeepney = jeepneyViewModel.hasAssignedJeepney;
                      return Stack(
                        children: [
                          JeepIcon(
                            color: hasJeepney
                                ? Colors.grey
                                : Colors.grey.withValues(alpha: 0.4),
                            size: 28,
                          ),
                          Consumer<TripViewModel>(
                            builder: (context, tripViewModel, child) {
                              if (tripViewModel.isTripActive) {
                                return Positioned(
                                  right: -2,
                                  top: -2,
                                  child: Container(
                                    width: 12,
                                    height: 12,
                                    decoration: BoxDecoration(
                                      color: Colors.green,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.white,
                                        width: 2,
                                      ),
                                    ),
                                  ),
                                );
                              }
                              return const SizedBox.shrink();
                            },
                          ),
                        ],
                      );
                    },
                  ),
                  selectedIcon: Consumer<JeepneyViewModel>(
                    builder: (context, jeepneyViewModel, child) {
                      final bool hasJeepney = jeepneyViewModel.hasAssignedJeepney;
                      return Stack(
                        children: [
                          JeepIcon(
                            color: hasJeepney
                                ? AppTheme.primaryBlue
                                : Colors.grey.withValues(alpha: 0.4),
                            size: 28,
                          ),
                          Consumer<TripViewModel>(
                            builder: (context, tripViewModel, child) {
                              if (tripViewModel.isTripActive) {
                                return Positioned(
                                  right: -2,
                                  top: -2,
                                  child: Container(
                                    width: 12,
                                    height: 12,
                                    decoration: BoxDecoration(
                                      color: Colors.green,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.white,
                                        width: 2,
                                      ),
                                    ),
                                  ),
                                );
                              }
                              return const SizedBox.shrink();
                            },
                          ),
                        ],
                      );
                    },
                  ),
                  label: isTagalog ? 'Biyahe' : 'Trips',
                ),
                _buildDestination(
                  index: 2,
                  icon: const Icon(Icons.account_balance_wallet_outlined),
                  selectedIcon: const Icon(Icons.account_balance_wallet, color: AppTheme.primaryBlue),
                  label: isTagalog ? 'Kita' : 'Wallet',
                  isTripActive: isTripActive,
                ),
                _buildDestination(
                  index: 3,
                  icon: const Icon(Icons.person_outline),
                  selectedIcon: const Icon(Icons.person, color: AppTheme.primaryBlue),
                  label: isTagalog ? 'Profile' : 'Profile',
                  isTripActive: isTripActive,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    context.read<JeepneyViewModel>().removeListener(_onJeepneyChanged);
    context.read<TripViewModel>().removeListener(_onTripStateChanged);
    _tripScheduleSubscription?.cancel();
    _autoStartTripTimer?.cancel();
    _reassignmentDebounceTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    TripLockHelper.forceDisableLock();
    super.dispose();
  }
}
