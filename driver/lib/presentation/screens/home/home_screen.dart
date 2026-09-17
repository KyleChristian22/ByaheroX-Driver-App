import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/booking_status.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../icons/jeep_icon.dart';
import '../../../services/analytics_tracking_service.dart';
import '../../../services/firestore_service.dart';
import '../../viewmodels/jeepney_viewmodel.dart';
import '../../viewmodels/language_viewmodel.dart';
import '../../widgets/driver_app_background.dart';
import '../../widgets/passenger_list_sheet.dart';
import '../trip/trip_history_screen.dart';

/// Home Screen for Driver App - Modern Dashboard Design
class HomeScreen extends StatefulWidget {
  final Function(int) onNavigate;

  const HomeScreen({super.key, required this.onNavigate});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    // Auto-refresh data when screen is first shown
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<JeepneyViewModel>().refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<JeepneyViewModel>(
      builder: (context, jeepneyViewModel, _) {
        return SafeArea(
          child: RefreshIndicator(
            onRefresh: jeepneyViewModel.refresh,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. Top Welcome Header - Compact Gradient Card
                  const _WelcomeHeader(),
                  const SizedBox(height: 20),

                  // 2. Vehicle Information Card
                  _VehicleInfoCard(
                    plateNumber: jeepneyViewModel.plateNumber,
                    routeName: jeepneyViewModel.currentRouteName,
                    jeepneyId: jeepneyViewModel.jeepneyId,
                    status: jeepneyViewModel.isLoading
                        ? 'Offline'
                        : (jeepneyViewModel.hasAssignedJeepney
                            ? 'Online'
                            : 'No Jeepney'),
                  ),
                  const SizedBox(height: 16),

                  _TodayScheduleCard(
                    jeepneyId: jeepneyViewModel.jeepneyId,
                    driverId: jeepneyViewModel.driverId,
                    driverName: jeepneyViewModel.driverName,
                    hasAssignedJeepney: jeepneyViewModel.hasAssignedJeepney,
                  ),
                  const SizedBox(height: 24),

                  _DashboardQuickActions(onNavigate: widget.onNavigate),
                  const SizedBox(height: 24),

                  // 4. Trip History Card
                  const _TripHistoryCard(),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 1. Welcome Header - Compact Gradient Card
class _WelcomeHeader extends StatelessWidget {
  const _WelcomeHeader();

  @override
  Widget build(BuildContext context) {
    const primaryBlue = AppTheme.primaryBlue;

    return Consumer<JeepneyViewModel>(
      builder: (context, viewModel, _) {
        return DriverGlassSurface(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          backgroundColor: primaryBlue.withValues(alpha: 0.48),
          borderColor: Colors.white.withValues(alpha: 0.48),
          child: Row(
            children: [
              // Vehicle Icon
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const JeepIcon(color: Colors.white, size: 24),
              ),
              const SizedBox(width: 12),
              // Welcome Message
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'ByaheroX',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 0,
                      ),
                    ),
                    Consumer<LanguageViewModel>(
                      builder: (context, languageViewModel, _) {
                        final isTagalog = languageViewModel.isTagalog;
                        return Text(
                          viewModel.isLoading
                              ? (isTagalog ? 'Naglo-load...' : 'Loading...')
                              : (isTagalog
                                  ? 'Maligayang pagdating, ${viewModel.driverName}!'
                                  : 'Welcome, ${viewModel.driverName}!'),
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.white.withValues(alpha: 0.85),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 2. Vehicle Information Card
class _VehicleInfoCard extends StatelessWidget {
  final String plateNumber;
  final String routeName;
  final String jeepneyId;
  final String status;

  const _VehicleInfoCard({
    required this.plateNumber,
    required this.routeName,
    required this.jeepneyId,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<LanguageViewModel>(
      builder: (context, languageViewModel, _) {
        final isTagalog = languageViewModel.isTagalog;
        final assignedJeepneyText =
            isTagalog ? 'Nakatalagang Jeepney' : 'Assigned Jeepney';

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: jeepneyId.trim().isEmpty || jeepneyId == 'No Jeepney Assigned'
              ? null
              : FirebaseFirestore.instance
                  .collection('trip_schedules')
                  .where(
                    'scheduleDate',
                    isEqualTo: FirestoreService.getTodayDateKey(),
                  )
                  .where('jeepneyId', isEqualTo: jeepneyId)
                  .snapshots(),
          builder: (context, snapshot) {
            final scheduleRoute = _resolveScheduleRoute(snapshot.data);
            final displayRoute = _displayRoute(
              routeName,
              scheduleRoute: scheduleRoute,
            );

            return DriverGlassSurface(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryBlue,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.directions_car,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              assignedJeepneyText,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    plateNumber,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.darkBlue,
                                    ),
                                  ),
                                ),
                                if (displayRoute.isNotEmpty) ...[
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: AppTheme.primarySkyBlue
                                            .withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        displayRoute,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                          color: AppTheme.primaryBlue,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                      _StatusBadge(status: status, isTagalog: isTagalog),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  static String _displayRoute(
    String routeName, {
    required String scheduleRoute,
  }) {
    final cleanRoute = routeName.trim();
    if (cleanRoute.isNotEmpty &&
        cleanRoute.toLowerCase() != 'no route assigned') {
      return cleanRoute;
    }
    return scheduleRoute;
  }

  static String _resolveScheduleRoute(
    QuerySnapshot<Map<String, dynamic>>? snapshot,
  ) {
    final docs = snapshot?.docs ?? const [];
    if (docs.isEmpty) return '';

    final schedules = docs.map((doc) => doc.data()).toList()
      ..sort((a, b) {
        final aTime = _scheduleDateTime(a);
        final bTime = _scheduleDateTime(b);
        if (aTime != null && bTime != null) {
          final now = DateTime.now();
          return aTime.difference(now).abs().compareTo(
                bTime.difference(now).abs(),
              );
        }
        if (aTime != null) return -1;
        if (bTime != null) return 1;
        return 0;
      });

    for (final schedule in schedules) {
      final route = _routeFromSchedule(schedule);
      if (route.isNotEmpty) return route;
    }
    return '';
  }

  static String _routeFromSchedule(Map<String, dynamic> schedule) {
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
      schedule['currentRoute'],
    ]);
  }

  static String _firstNonEmpty(List<dynamic> values) {
    for (final value in values) {
      final text = value?.toString().trim() ?? '';
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  static DateTime? _scheduleDateTime(Map<String, dynamic> schedule) {
    final scheduledAt = schedule['scheduledAt'];
    if (scheduledAt is Timestamp) return scheduledAt.toDate();
    if (scheduledAt is DateTime) return scheduledAt;
    if (scheduledAt is String) return DateTime.tryParse(scheduledAt);
    return null;
  }
}

class _TodayScheduleCard extends StatelessWidget {
  final String jeepneyId;
  final String driverId;
  final String driverName;
  final bool hasAssignedJeepney;

  const _TodayScheduleCard({
    required this.jeepneyId,
    required this.driverId,
    required this.driverName,
    required this.hasAssignedJeepney,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<LanguageViewModel>(
      builder: (context, languageViewModel, _) {
        final isTagalog = languageViewModel.isTagalog;

        return DriverGlassSurface(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryBlue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.event_note_rounded,
                      color: AppTheme.primaryBlue,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      isTagalog ? 'Iskedyul Ngayon' : 'Today\'s Schedule',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.darkBlue,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (!hasAssignedJeepney)
                Text(
                  isTagalog
                      ? 'Walang nakatalagang jeepney.'
                      : 'No assigned jeepney.',
                  style: TextStyle(color: Colors.grey[600]),
                )
              else
                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('trip_schedules')
                      .where(
                        'scheduleDate',
                        isEqualTo: FirestoreService.getTodayDateKey(),
                      )
                      .where('jeepneyId', isEqualTo: jeepneyId)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 18),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }

                    final schedules = (snapshot.data?.docs ?? const [])
                        .map((doc) => {'id': doc.id, ...doc.data()})
                        .toList()
                      ..sort((a, b) {
                        final aTime = _homeScheduleDateTime(a);
                        final bTime = _homeScheduleDateTime(b);
                        if (aTime != null && bTime != null) {
                          return aTime.compareTo(bTime);
                        }
                        if (aTime != null) return -1;
                        if (bTime != null) return 1;
                        return 0;
                      });
                    if (schedules.isEmpty) {
                      return Text(
                        isTagalog
                            ? 'Walang schedule para ngayong araw.'
                            : 'No schedule found for today.',
                        style: TextStyle(color: Colors.grey[600]),
                      );
                    }

                    return Column(
                      children: schedules.map((schedule) {
                        final status = _homeScheduleStatus(schedule);
                        final color = _homeScheduleStatusColor(status);
                        final backgroundColor = color.withValues(alpha: 0.12);
                        final isDone = status == 'Done';
                        final onboardCount =
                            isDone ? 0 : _homeScheduleOnBoardCount(schedule);
                        final totalCount =
                            isDone ? 0 : _homeSchedulePassengerTotal(schedule);

                        return InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: totalCount > 0 && !isDone
                              ? () => _showPassengers(context, schedule)
                              : null,
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: backgroundColor,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: color.withValues(alpha: 0.28),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  status == 'Done'
                                      ? Icons.check_circle_outline
                                      : Icons.schedule_rounded,
                                  color: color,
                                  size: 22,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _homeScheduleTime(schedule),
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w800,
                                          color: AppTheme.darkBlue,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        _homeScheduleRoute(schedule),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: AppTheme.darkBlue,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      if (totalCount > 0 && !isDone) ...[
                                        const SizedBox(height: 3),
                                        Text(
                                          'On board: $onboardCount / $totalCount',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: AppTheme.darkBlue,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: color.withValues(alpha: 0.25),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    status,
                                    style: TextStyle(
                                      color: color,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                                if (totalCount > 0 && !isDone) ...[
                                  const SizedBox(width: 4),
                                  IconButton(
                                    tooltip: 'View passengers',
                                    onPressed: () =>
                                        _showPassengers(context, schedule),
                                    icon: const Icon(
                                      Icons.groups_outlined,
                                      size: 20,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  static String _firstNonEmpty(List<dynamic> values) {
    for (final value in values) {
      final text = value?.toString().trim() ?? '';
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  static String _homeScheduleTime(Map<String, dynamic> schedule) {
    final label = _firstNonEmpty([
      schedule['scheduleTime'],
      schedule['departureTime'],
      schedule['tripTime'],
    ]);
    if (label.isNotEmpty) return label;

    final scheduledAt = _homeScheduleDateTime(schedule);
    if (scheduledAt == null) return 'No time set';

    final hour = scheduledAt.hour % 12 == 0 ? 12 : scheduledAt.hour % 12;
    final minute = scheduledAt.minute.toString().padLeft(2, '0');
    final period = scheduledAt.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }

  static String _homeScheduleRoute(Map<String, dynamic> schedule) {
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

  static String _homeScheduleStatus(Map<String, dynamic> schedule) {
    final status = _firstNonEmpty([
      schedule['status'],
      schedule['tripStatus'],
      schedule['historyStatus'],
    ]).toLowerCase();

    if (status == 'completed' ||
        status == 'done' ||
        status == 'finished' ||
        _homeScheduleWindowDone(schedule)) {
      return 'Done';
    }
    if (status == 'active' ||
        status == 'ontrip' ||
        status == 'on-trip' ||
        status == 'on trip' ||
        schedule['isOnTrip'] == true ||
        schedule['onTrip'] == true ||
        _homeScheduleTimePassed(schedule)) {
      return 'On Trip';
    }
    return 'Scheduled';
  }

  static void _showPassengers(
    BuildContext context,
    Map<String, dynamic> schedule,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => PassengerListSheet(tripSchedule: schedule),
    );
  }

  static int _homeScheduleOnBoardCount(Map<String, dynamic> schedule) {
    final passengers = schedule['bookedPassengers'];
    if (passengers is! List) return 0;

    return passengers.fold<int>(0, (total, passenger) {
      if (passenger is! Map) return total;
      final data = Map<String, dynamic>.from(passenger);
      if (!_homePassengerOnBoard(data)) return total;
      return total + _homePassengerUnitCount(data);
    });
  }

  static int _homeSchedulePassengerTotal(Map<String, dynamic> schedule) {
    final passengers = schedule['bookedPassengers'];
    if (passengers is! List) return 0;

    return passengers.fold<int>(0, (total, passenger) {
      if (passenger is! Map) return total;
      return total +
          _homePassengerUnitCount(
            Map<String, dynamic>.from(passenger),
          );
    });
  }

  static bool _homePassengerOnBoard(Map<String, dynamic> passenger) {
    final status = passenger['status']?.toString();
    if (BookingStatus.isInactive(status)) {
      return false;
    }
    final source = passenger['source']?.toString().trim().toLowerCase() ?? '';
    final onBoardSource =
        passenger['onBoardSource']?.toString().trim().toLowerCase() ?? '';
    final bookedBy =
        passenger['bookedBy']?.toString().trim().toLowerCase() ?? '';

    return passenger['onBoard'] == true ||
        BookingStatus.isOnboard(status) ||
        source.contains('dispatcher') ||
        onBoardSource.contains('dispatcher') ||
        bookedBy.contains('dispatcher');
  }

  static int _homePassengerUnitCount(Map<String, dynamic> passenger) {
    final value = passenger['passengerCount'] ??
        passenger['waitingCount'] ??
        passenger['count'] ??
        passenger['quantity'];
    if (value is int) return value < 1 ? 1 : value;
    if (value is num) {
      final count = value.toInt();
      return count < 1 ? 1 : count;
    }
    final parsed = int.tryParse(value?.toString() ?? '');
    if (parsed == null || parsed < 1) return 1;
    return parsed;
  }

  static Color _homeScheduleStatusColor(String status) {
    if (status == 'Done') return Colors.grey;
    if (status == 'On Trip') return const Color(0xFF10B981);
    return AppTheme.primaryBlue;
  }

  static bool _homeScheduleTimePassed(Map<String, dynamic> schedule) {
    final scheduledAt = _homeScheduleDateTime(schedule);
    return scheduledAt != null && DateTime.now().isAfter(scheduledAt);
  }

  static bool _homeScheduleWindowDone(Map<String, dynamic> schedule) {
    final scheduledAt = _homeScheduleDateTime(schedule);
    return scheduledAt != null &&
        DateTime.now().isAfter(scheduledAt.add(const Duration(hours: 3)));
  }

  static DateTime? _homeScheduleDateTime(Map<String, dynamic> schedule) {
    final scheduledAt = schedule['scheduledAt'];
    if (scheduledAt is Timestamp) return scheduledAt.toDate();
    if (scheduledAt is DateTime) return scheduledAt;
    if (scheduledAt is String) return DateTime.tryParse(scheduledAt);

    final scheduleDate = _firstNonEmpty([
      schedule['scheduleDate'],
      schedule['tripDate'],
    ]);
    final scheduleTime = _firstNonEmpty([
      schedule['scheduleTime'],
      schedule['departureTime'],
      schedule['tripTime'],
    ]);
    final dateMatch =
        RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(scheduleDate);
    final timeMatch =
        RegExp(r'^(\d{1,2}):(\d{2})\s*(AM|PM)?$', caseSensitive: false)
            .firstMatch(scheduleTime.trim());
    if (dateMatch == null || timeMatch == null) return null;

    var hour = int.parse(timeMatch.group(1)!);
    final minute = int.parse(timeMatch.group(2)!);
    final period = timeMatch.group(3)?.toUpperCase();
    if (period == 'AM' && hour == 12) hour = 0;
    if (period == 'PM' && hour != 12) hour += 12;
    if (hour > 23 || minute > 59) return null;

    return DateTime(
      int.parse(dateMatch.group(1)!),
      int.parse(dateMatch.group(2)!),
      int.parse(dateMatch.group(3)!),
      hour,
      minute,
    );
  }
}

/// Status Badge with Color Coding
class _StatusBadge extends StatelessWidget {
  final String status;
  final bool isTagalog;

  const _StatusBadge({required this.status, required this.isTagalog});

  @override
  Widget build(BuildContext context) {
    Color backgroundColor;
    Color textColor;
    IconData icon;

    String displayStatus;
    switch (status.toLowerCase()) {
      case 'active':
      case 'online':
        backgroundColor = const Color(0xFF10B981).withValues(alpha: 0.15);
        textColor = const Color(0xFF10B981);
        icon = Icons.check_circle;
        displayStatus = isTagalog ? 'Online' : 'Online';
        break;
      case 'paused':
        backgroundColor = const Color(0xFFF59E0B).withValues(alpha: 0.15);
        textColor = const Color(0xFFF59E0B);
        icon = Icons.pause_circle;
        displayStatus = isTagalog ? 'Nakahinto' : 'Paused';
        break;
      case 'offline':
        backgroundColor = Colors.grey.withValues(alpha: 0.15);
        textColor = Colors.grey;
        icon = Icons.cancel;
        displayStatus = isTagalog ? 'Offline' : 'Offline';
        break;
      case 'no jeepney':
        backgroundColor = Colors.grey.withValues(alpha: 0.15);
        textColor = Colors.grey;
        icon = Icons.cancel;
        displayStatus = isTagalog ? 'Walang Jeepney' : 'No Jeepney';
        break;
      default:
        backgroundColor = Colors.grey.withValues(alpha: 0.15);
        textColor = Colors.grey;
        icon = Icons.cancel;
        displayStatus = status;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: textColor),
          const SizedBox(width: 4),
          Text(
            displayStatus,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardQuickActions extends StatelessWidget {
  final Function(int) onNavigate;

  const _DashboardQuickActions({required this.onNavigate});

  @override
  Widget build(BuildContext context) {
    final isTagalog = context.watch<LanguageViewModel>().isTagalog;

    return DriverGlassSurface(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isTagalog ? 'Mabilis na Aksyon' : 'Quick Actions',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 520;
              return GridView.count(
                crossAxisCount: isWide ? 4 : 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: isWide ? 1.25 : 1.18,
                children: [
                  _QuickActionCard(
                    icon: Icons.route_rounded,
                    title: isTagalog ? 'Biyahe' : 'Trip',
                    subtitle: isTagalog ? 'Map at kontrol' : 'Map and controls',
                    color: AppTheme.primaryBlue,
                    onTap: () => onNavigate(1),
                  ),
                  _QuickActionCard(
                    icon: Icons.groups_2_rounded,
                    title: isTagalog ? 'Pasahero' : 'Passengers',
                    subtitle:
                        isTagalog ? 'Tingnan ang pila' : 'View waiting list',
                    color: AppTheme.primaryRed,
                    onTap: () => AppRouter.goToNotifications(context),
                  ),
                  _QuickActionCard(
                    icon: Icons.notifications_active_outlined,
                    title: isTagalog ? 'Alerts' : 'Alerts',
                    subtitle: isTagalog ? 'Mga notification' : 'Notifications',
                    color: AppTheme.warning,
                    onTap: () => AppRouter.goToNotifications(context),
                  ),
                  _QuickActionCard(
                    icon: Icons.account_balance_wallet_outlined,
                    title: isTagalog ? 'Kita' : 'Wallet',
                    subtitle: isTagalog ? 'Payout at history' : 'Payouts',
                    color: AppTheme.success,
                    onTap: () => onNavigate(2),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _QuickActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.20)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: Colors.white, size: 25),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.2,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 4. Trip History Card - Shows driver's past trips
class _TripHistoryCard extends StatelessWidget {
  const _TripHistoryCard();

  String _formatDate(DateTime? date, bool isTagalog) {
    if (date == null) return isTagalog ? 'Hindi matukoy' : 'Unknown';
    final months = isTagalog
        ? [
            'Ene',
            'Peb',
            'Mar',
            'Abr',
            'May',
            'Hun',
            'Hul',
            'Ago',
            'Set',
            'Okt',
            'Nob',
            'Dis'
          ]
        : [
            'Jan',
            'Feb',
            'Mar',
            'Apr',
            'May',
            'Jun',
            'Jul',
            'Aug',
            'Sep',
            'Oct',
            'Nov',
            'Dec'
          ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  String _formatTime(DateTime? date) {
    if (date == null) return '--:--';
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String _formatDuration(int minutes, bool isTagalog) {
    if (minutes < 1) return isTagalog ? '1 min' : '1 min';
    if (minutes < 60) return '$minutes ${isTagalog ? 'min' : 'min'}';
    final hours = minutes ~/ 60;
    final remainingMinutes = minutes % 60;
    if (remainingMinutes == 0) return '$hours ${isTagalog ? 'hr' : 'hr'}';
    return '$hours${isTagalog ? 'hr' : 'hr'} ${remainingMinutes}min';
  }

  void _showTripDetailDialog(
      BuildContext context, Map<String, dynamic> trip, bool isTagalog) {
    final startedAt = trip['startedAt'] as DateTime?;
    final endedAt = trip['endedAt'] as DateTime?;
    final duration = trip['durationMinutes'] as int? ?? 0;
    final routeName = trip['routeName'] as String? ??
        (isTagalog ? 'Hindi kilalang Ruta' : 'Unknown Route');
    final origin = trip['originTerminal'] as String? ?? '';
    final destination = trip['destinationTerminal'] as String? ?? '';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.primarySkyBlue.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.history,
                  color: AppTheme.primarySkyBlue, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                isTagalog ? 'Detalye ng Biyahe' : 'Trip Details',
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDetailRow(
                  Icons.route, isTagalog ? 'Ruta' : 'Route', routeName),
              const SizedBox(height: 12),
              if (origin.isNotEmpty)
                _buildDetailRow(Icons.trip_origin,
                    isTagalog ? 'Pinagmulan' : 'Origin', origin),
              if (origin.isNotEmpty) const SizedBox(height: 12),
              if (destination.isNotEmpty)
                _buildDetailRow(Icons.location_on,
                    isTagalog ? 'Destinasyon' : 'Destination', destination),
              if (destination.isNotEmpty) const SizedBox(height: 12),
              _buildDetailRow(
                  Icons.calendar_today,
                  isTagalog ? 'Petsa' : 'Date',
                  _formatDate(startedAt, isTagalog)),
              const SizedBox(height: 12),
              _buildDetailRow(
                  Icons.access_time,
                  isTagalog ? 'Oras ng Simula' : 'Start Time',
                  _formatTime(startedAt)),
              const SizedBox(height: 12),
              _buildDetailRow(
                  Icons.access_time_filled,
                  isTagalog ? 'Oras ng Pagtapos' : 'End Time',
                  _formatTime(endedAt)),
              const SizedBox(height: 12),
              _buildDetailRow(Icons.timelapse, isTagalog ? 'Tagal' : 'Duration',
                  _formatDuration(duration, isTagalog),
                  isHighlighted: true),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(isTagalog ? 'Isara' : 'Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value,
      {bool isHighlighted = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon,
            size: 18,
            color: isHighlighted ? AppTheme.primaryBlue : Colors.grey),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isHighlighted ? FontWeight.bold : FontWeight.w600,
                  color: isHighlighted ? AppTheme.primaryBlue : Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<LanguageViewModel>(
      builder: (context, languageViewModel, _) {
        final isTagalog = languageViewModel.isTagalog;

        return DriverGlassSurface(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.primarySkyBlue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.history,
                      color: AppTheme.primarySkyBlue,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      isTagalog ? 'Kasaysayan ng Biyahe' : 'Trip History',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.darkBlue,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              StreamBuilder<List<Map<String, dynamic>>>(
                stream: AnalyticsTrackingService.tripHistoryStream(limit: 3),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    );
                  }

                  final trips = snapshot.data ?? [];

                  if (trips.isEmpty) {
                    return Center(
                      child: Column(
                        children: [
                          Icon(
                            Icons.history,
                            size: 48,
                            color: Colors.grey.withValues(alpha: 0.3),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            isTagalog
                                ? 'Walang nakuhang kasaysayan ng biyahe'
                                : 'No trip history available',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[500],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            isTagalog
                                ? 'Magsimula ng biyahe upang makita rito'
                                : 'Start a trip to see history here',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[400],
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return Column(
                    children: trips.map((trip) {
                      final startedAt = trip['startedAt'] as DateTime?;
                      final duration = trip['durationMinutes'] as int? ?? 0;
                      final origin = trip['originTerminal'] as String? ?? '';
                      final destination =
                          trip['destinationTerminal'] as String? ?? '';

                      return InkWell(
                        onTap: () =>
                            _showTripDetailDialog(context, trip, isTagalog),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.grey[50],
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey[200]!),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: AppTheme.primarySkyBlue
                                      .withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.directions_bus,
                                  color: AppTheme.primarySkyBlue,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      origin.isNotEmpty &&
                                              destination.isNotEmpty
                                          ? '$origin → $destination'
                                          : (isTagalog
                                              ? 'Hindi matukoy na ruta'
                                              : 'Unknown route'),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.darkBlue,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        Icon(Icons.calendar_today,
                                            size: 12, color: Colors.grey[400]),
                                        const SizedBox(width: 4),
                                        Text(
                                          _formatDate(startedAt, isTagalog),
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey[500],
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Icon(Icons.timelapse,
                                            size: 12, color: Colors.grey[400]),
                                        const SizedBox(width: 4),
                                        Text(
                                          _formatDuration(duration, isTagalog),
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey[500],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(
                                Icons.chevron_right,
                                color: Colors.grey,
                                size: 20,
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
              const SizedBox(height: 12),
              // View All Button
              InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const TripHistoryScreen(),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: AppTheme.primarySkyBlue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        isTagalog ? 'Tingnan Lahat' : 'View All',
                        style: const TextStyle(
                          color: AppTheme.primaryBlue,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.arrow_forward_ios,
                        color: AppTheme.primaryBlue,
                        size: 14,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
