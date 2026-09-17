import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../services/analytics_tracking_service.dart';
import '../../viewmodels/language_viewmodel.dart';
import '../../widgets/driver_app_background.dart';

class TripHistoryScreen extends StatelessWidget {
  const TripHistoryScreen({super.key});

  static String _formatDate(DateTime? date, bool isTagalog) {
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

  static String _formatTime(DateTime? date) {
    if (date == null) return '--:--';
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  static String _formatDuration(int minutes, bool isTagalog) {
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
    final passengerCount = _intValue(trip['passengerCount']) ?? 0;
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
              const SizedBox(height: 12),
              _buildDetailRow(
                  Icons.groups,
                  isTagalog ? 'Pasahero' : 'Passengers',
                  passengerCount.toString(),
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

  static int? _intValue(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  @override
  Widget build(BuildContext context) {
    final languageViewModel = context.watch<LanguageViewModel>();
    final isTagalog = languageViewModel.isTagalog;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(isTagalog ? 'Kasaysayan ng Biyahe' : 'Trip History'),
      ),
      body: DriverAppBackground(
        safeArea: false,
        child: StreamBuilder<List<Map<String, dynamic>>>(
          stream: AnalyticsTrackingService.tripHistoryStream(limit: 50),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(),
              );
            }

            if (snapshot.hasError) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error_outline,
                        size: 48, color: Colors.grey[400]),
                    const SizedBox(height: 12),
                    Text(
                      isTagalog
                          ? 'Hindi makuha ang kasaysayan ng biyahe'
                          : 'Unable to load trip history',
                      style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                    ),
                  ],
                ),
              );
            }

            final trips = snapshot.data ?? [];

            if (trips.isEmpty) {
              return _EmptyState(isTagalog: isTagalog);
            }

            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: trips.length,
              itemBuilder: (context, index) {
                final trip = trips[index];
                return _TripHistoryItem(
                  trip: trip,
                  isTagalog: isTagalog,
                  onTap: () => _showTripDetailDialog(context, trip, isTagalog),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool isTagalog;

  const _EmptyState({required this.isTagalog});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.history_outlined,
            size: 80,
            color: Colors.grey[300],
          ),
          const SizedBox(height: 20),
          Text(
            isTagalog ? 'Walang Kasaysayan ng Biyahe' : 'No Trip History',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isTagalog
                ? 'Magsimula ng biyahe upang makita rito ang iyong mga nakaraan'
                : 'Start a trip to see your past trips here',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _TripHistoryItem extends StatelessWidget {
  final Map<String, dynamic> trip;
  final bool isTagalog;
  final VoidCallback onTap;

  const _TripHistoryItem({
    required this.trip,
    required this.isTagalog,
    required this.onTap,
  });

  static String _formatDate(DateTime? date, bool isTagalog) {
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

  static String _formatDuration(int minutes, bool isTagalog) {
    if (minutes < 1) return isTagalog ? '1 min' : '1 min';
    if (minutes < 60) return '$minutes ${isTagalog ? 'min' : 'min'}';
    final hours = minutes ~/ 60;
    final remainingMinutes = minutes % 60;
    if (remainingMinutes == 0) return '$hours ${isTagalog ? 'hr' : 'hr'}';
    return '$hours${isTagalog ? 'hr' : 'hr'} ${remainingMinutes}min';
  }

  @override
  Widget build(BuildContext context) {
    final startedAt = trip['startedAt'] as DateTime?;
    final duration = trip['durationMinutes'] as int? ?? 0;
    final routeName = trip['routeName'] as String? ??
        (isTagalog ? 'Hindi kilalang Ruta' : 'Unknown Route');
    final origin = trip['originTerminal'] as String? ?? '';
    final destination = trip['destinationTerminal'] as String? ?? '';
    final passengerCount =
        TripHistoryScreen._intValue(trip['passengerCount']) ?? 0;

    return DriverGlassSurface(
      margin: const EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.zero,
      borderRadius: BorderRadius.circular(12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryBlue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.directions_bus,
                    color: AppTheme.primaryBlue,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        routeName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.darkBlue,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        origin.isNotEmpty && destination.isNotEmpty
                            ? '$origin → $destination'
                            : (isTagalog
                                ? 'Hindi matukoy na ruta'
                                : 'Unknown route'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.calendar_today,
                              size: 13, color: Colors.grey[400]),
                          const SizedBox(width: 4),
                          Text(
                            _formatDate(startedAt, isTagalog),
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[500],
                            ),
                          ),
                          const SizedBox(width: 16),
                          Icon(Icons.timelapse,
                              size: 13, color: Colors.grey[400]),
                          const SizedBox(width: 4),
                          Text(
                            _formatDuration(duration, isTagalog),
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[500],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 12,
                        runSpacing: 6,
                        children: [
                          _miniMetric(
                            Icons.groups,
                            passengerCount.toString(),
                            isTagalog ? 'pasahero' : 'passengers',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  color: Colors.grey,
                  size: 24,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _miniMetric(IconData icon, String value, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppTheme.primaryBlue),
        const SizedBox(width: 4),
        Text(
          '$value $label',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppTheme.primaryBlue,
          ),
        ),
      ],
    );
  }
}
