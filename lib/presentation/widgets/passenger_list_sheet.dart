import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/booking_status.dart';
import '../../services/firestore_service.dart';
import '../../../core/theme/app_theme.dart';
import 'app_feedback.dart';
import 'driver_app_background.dart';

class PassengerListSheet extends StatefulWidget {
  final Map<String, dynamic> tripSchedule;

  const PassengerListSheet({super.key, required this.tripSchedule});

  @override
  State<PassengerListSheet> createState() => _PassengerListSheetState();
}

class _PassengerListSheetState extends State<PassengerListSheet> {
  late List<Map<String, dynamic>> _passengers;
  String get _tripScheduleId => widget.tripSchedule['id']?.toString() ?? '';

  int get _onBoardPassengerCount {
    return _passengers.fold<int>(0, (total, passenger) {
      if (!_isOnBoardPassenger(passenger)) return total;
      return total + _passengerUnitCount(passenger);
    });
  }

  int get _totalPassengerCount {
    return _passengers.fold<int>(0, (total, passenger) {
      return total + _passengerUnitCount(passenger);
    });
  }

  @override
  void initState() {
    super.initState();
    final raw = widget.tripSchedule['bookedPassengers'];
    if (raw is List) {
      _passengers =
          raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } else {
      _passengers = [];
    }
  }

  // ignore: unused_element
  Future<void> _markCollected(int index) async {
    final passenger = _passengers[index];
    final tripId = widget.tripSchedule['id']?.toString() ?? '';
    final commuterId = passenger['commuterId']?.toString() ?? '';
    if (tripId.isEmpty || commuterId.isEmpty) return;

    final success =
        await FirestoreService.markCashCollected(tripId, commuterId);
    if (!mounted) return;
    if (success) {
      setState(() {
        _passengers[index]['cashCollected'] = true;
      });
      AppFeedback.show(
        context,
        message:
            'Cash collected from ${passenger['commuterName'] ?? 'passenger'}',
        backgroundColor: Colors.green,
      );
    } else {
      AppFeedback.show(
        context,
        message: 'Failed to update. Try again.',
        backgroundColor: Colors.red,
      );
    }
  }

  bool _isOnBoardPassenger(Map<String, dynamic> passenger) {
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

  int _passengerUnitCount(Map<String, dynamic> passenger) {
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

  @override
  Widget build(BuildContext context) {
    if (_tripScheduleId.isNotEmpty) {
      return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('trip_schedules')
            .doc(_tripScheduleId)
            .snapshots(),
        builder: (context, snapshot) {
          final data = snapshot.data?.data();
          final raw = data?['bookedPassengers'];
          if (raw is List) {
            _passengers = raw
                .whereType<Map>()
                .map((passenger) => Map<String, dynamic>.from(passenger))
                .toList();
          }

          return _buildPassengerContent(context);
        },
      );
    }

    return _buildPassengerContent(context);
  }

  bool _isScheduleCompleted() {
    final status =
        (widget.tripSchedule['status']?.toString() ?? '').toLowerCase();
    final tripStatus =
        (widget.tripSchedule['tripStatus']?.toString() ?? '').toLowerCase();
    return status == 'completed' ||
        status == 'done' ||
        tripStatus == 'completed' ||
        tripStatus == 'done';
  }

  Widget _buildPassengerContent(BuildContext context) {
    if (_isScheduleCompleted()) {
      return Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Text('Trip completed',
                style: TextStyle(color: Colors.grey[600], fontSize: 16)),
            const SizedBox(height: 4),
            Text('No active passengers for this trip',
                style: TextStyle(color: Colors.grey[500], fontSize: 13)),
          ],
        ),
      );
    }

    if (_passengers.isEmpty) {
      return DriverGlassSurface(
        backgroundColor: Colors.white,
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.people_outline, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Text('No booked passengers',
                style: TextStyle(color: Colors.grey[600], fontSize: 16)),
            const SizedBox(height: 4),
            Text('Passengers booked by the office will appear here',
                style: TextStyle(color: Colors.grey[500], fontSize: 13)),
          ],
        ),
      );
    }

    return DriverGlassSurface(
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Icon(Icons.people, size: 20),
                const SizedBox(width: 8),
                Text(
                  'On Board ($_onBoardPassengerCount / $_totalPassengerCount)',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.5,
            ),
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _passengers.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final p = _passengers[index];
                final name = p['commuterName']?.toString() ?? 'Unknown';
                final commuterId = p['commuterId']?.toString().trim() ?? '';
                final fare =
                    (p['fare'] is num) ? (p['fare'] as num).toDouble() : 0.0;
                final method =
                    (p['paymentMethod']?.toString() ?? 'cash').toLowerCase();
                final fareType =
                    (p['fareType']?.toString() ?? 'regular').toLowerCase();
                final discountApplied = p['discountApplied'] == true;
                final source = (p['source']?.toString() ?? '').toLowerCase();
                final isRoadPickup = source == 'road_pickup';
                final showFare = !isRoadPickup;
                final showCommuterId =
                    method == 'rfid' && commuterId.isNotEmpty;
                final onBoard = _isOnBoardPassenger(p);
                final passengerCount = _passengerUnitCount(p);
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor:
                            AppTheme.primaryBlue.withValues(alpha: 0.1),
                        child: Text(
                          (name.isNotEmpty ? name[0] : '?').toUpperCase(),
                          style: const TextStyle(
                            color: AppTheme.primaryBlue,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600, fontSize: 14)),
                            if (showCommuterId) ...[
                              const SizedBox(height: 2),
                              Text(
                                'Commuter ID: $commuterId',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey[600],
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                if (onBoard) ...[
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color:
                                          Colors.green.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      'ON BOARD',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.green,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                ],
                                if (passengerCount > 1) ...[
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color:
                                          Colors.purple.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      'x$passengerCount',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.purple[800],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                ],
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: isRoadPickup
                                        ? Colors.green.withValues(alpha: 0.1)
                                        : method == 'cash'
                                            ? Colors.orange
                                                .withValues(alpha: 0.1)
                                            : Colors.blue
                                                .withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    isRoadPickup
                                        ? 'ROAD PICKUP'
                                        : _fareBadgeLabel(
                                            method,
                                            fareType,
                                            discountApplied,
                                          ),
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: isRoadPickup
                                          ? Colors.green[800]
                                          : method == 'cash'
                                              ? Colors.orange[800]
                                              : Colors.blue[800],
                                    ),
                                  ),
                                ),
                                if (showFare) ...[
                                  const SizedBox(width: 8),
                                  Text(
                                    '₱${fare.toStringAsFixed(2)}',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.green[700],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (isRoadPickup)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.directions_walk,
                                  size: 14, color: Colors.green),
                              SizedBox(width: 4),
                              Text(
                                'Cash only',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.green,
                                ),
                              ),
                            ],
                          ),
                        )
                      else if (method == 'cash')
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.money, size: 14, color: Colors.orange),
                              SizedBox(width: 4),
                              Text(
                                'Cash',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.orange,
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.blue.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.credit_card,
                                  size: 14, color: Colors.blue),
                              SizedBox(width: 4),
                              Text(
                                'Prepaid',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.blue,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _fareBadgeLabel(
    String method,
    String fareType,
    bool discountApplied,
  ) {
    final methodLabel = method.toUpperCase();
    if (!discountApplied) return '$methodLabel - REGULAR';
    if (fareType == 'student') return '$methodLabel - STUDENT';
    if (fareType == 'pwd') return '$methodLabel - PWD';
    return '$methodLabel - STUDENT/PWD';
  }
}
