import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/router/app_router.dart';
import '../../../data/services/ride_feedback_service.dart';
import '../../viewmodels/auth_viewmodel.dart';
import '../../widgets/common/app_background.dart';
import '../../widgets/ride_feedback_sheet.dart';

class CompletedTripsScreen extends StatefulWidget {
  const CompletedTripsScreen({super.key});

  @override
  State<CompletedTripsScreen> createState() => _CompletedTripsScreenState();
}

class _CompletedTripsScreenState extends State<CompletedTripsScreen> {
  static const int _tripsPerPage = 5;
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    final authViewModel = context.watch<AuthViewModel>();
    final user = authViewModel.currentUser;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) context.go(AppRouter.profile);
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Back',
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.go(AppRouter.profile),
          ),
          title: const Text('Completed Trips'),
          backgroundColor: Colors.transparent,
          foregroundColor: AppColors.textPrimary,
        ),
        body: SafeArea(
          child: user.isGuest
              ? const _EmptyState(
                  icon: Icons.lock_outline,
                  title: 'Login required',
                  message: 'Sign in to view and rate your completed trips.',
                )
              : StreamBuilder<List<CompletedTrip>>(
                  stream: RideFeedbackService.watchCompletedTrips(user.id),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return const _EmptyState(
                        icon: Icons.error_outline,
                        title: 'Could not load trips',
                        message:
                            'Please check your connection and try again later.',
                      );
                    }

                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final trips = snapshot.data ?? const <CompletedTrip>[];
                    if (trips.isEmpty) {
                      return const _EmptyState(
                        icon: Icons.route_outlined,
                        title: 'No completed trips yet',
                        message:
                            'Finished rides will appear here after drop off.',
                      );
                    }

                    final totalPages =
                        ((trips.length - 1) ~/ _tripsPerPage) + 1;
                    final safePage = _page.clamp(0, totalPages - 1);
                    if (safePage != _page) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) setState(() => _page = safePage);
                      });
                    }
                    final start = safePage * _tripsPerPage;
                    final end = (start + _tripsPerPage) > trips.length
                        ? trips.length
                        : start + _tripsPerPage;
                    final visibleTrips = trips.sublist(start, end);

                    return ListView.separated(
                      padding: const EdgeInsets.all(AppDimensions.md),
                      itemCount: visibleTrips.length + 1,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: AppDimensions.sm),
                      itemBuilder: (context, index) {
                        if (index == visibleTrips.length) {
                          if (trips.length <= _tripsPerPage) {
                            return const SizedBox.shrink();
                          }
                          return _TripsPaginationControls(
                            currentPage: safePage,
                            totalPages: totalPages,
                            onPrevious: safePage == 0
                                ? null
                                : () => setState(() => _page--),
                            onNext: safePage >= totalPages - 1
                                ? null
                                : () => setState(() => _page++),
                          );
                        }
                        return _CompletedTripCard(trip: visibleTrips[index]);
                      },
                    );
                  },
                ),
        ),
      ),
    );
  }
}

class _TripsPaginationControls extends StatelessWidget {
  const _TripsPaginationControls({
    required this.currentPage,
    required this.totalPages,
    required this.onPrevious,
    required this.onNext,
  });

  final int currentPage;
  final int totalPages;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppDimensions.sm),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: onPrevious,
              icon: const Icon(Icons.chevron_left),
              label: const Text('Previous'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppDimensions.sm),
            child: Text(
              '${currentPage + 1} / $totalPages',
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: onNext,
              icon: const Icon(Icons.chevron_right),
              label: const Text('Next'),
            ),
          ),
        ],
      ),
    );
  }
}

class _CompletedTripCard extends StatelessWidget {
  final CompletedTrip trip;

  const _CompletedTripCard({required this.trip});

  Future<void> _rate(BuildContext context) async {
    final submitted = await showRideFeedbackSheet(context, trip: trip);
    if (!context.mounted) return;
    if (submitted == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Feedback submitted. Thank you.'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final date = trip.offboardAt ?? trip.onBoardAt;
    final dateText = date == null
        ? 'Completed'
        : DateFormat('MMM d, yyyy - h:mm a').format(date);

    return Material(
      color: Colors.transparent,
      borderRadius: AppDimensions.borderRadiusMd,
      child: GlassSurface(
        padding: const EdgeInsets.all(AppDimensions.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: AppDimensions.borderRadiusMd,
                  ),
                  child: const Icon(
                    Icons.directions_bus_filled_outlined,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        trip.plateNumber.isEmpty
                            ? trip.jeepneyId
                            : trip.plateNumber,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        trip.driverName.isEmpty
                            ? trip.displayRoute
                            : '${trip.driverName} - ${trip.displayRoute}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        dateText,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                if (trip.hasFeedback) ...[
                  Icon(Icons.star, color: Colors.amber.shade700, size: 18),
                  const SizedBox(width: 4),
                  Text(
                    trip.rating == null ? 'Rated' : 'Rated ${trip.rating}/5',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ] else ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      'Not rated',
                      style: TextStyle(
                        color: AppColors.warning,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                FilledButton.icon(
                  onPressed: trip.canRate ? () => _rate(context) : null,
                  icon: Icon(
                    trip.hasFeedback ? Icons.check_circle : Icons.star_border,
                    size: 18,
                  ),
                  label: Text(trip.hasFeedback ? 'Submitted' : 'Rate Ride'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 54, color: AppColors.textTertiary),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
