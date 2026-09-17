import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/router/app_router.dart';
import '../../../services/feedback_service.dart';
import '../../../services/firestore_service.dart';
import '../../viewmodels/auth_viewmodel.dart';
import '../../viewmodels/jeepney_viewmodel.dart';
import '../../viewmodels/language_viewmodel.dart';
import '../../viewmodels/trip_viewmodel.dart';
import '../../widgets/driver_app_background.dart';
import 'driver_ratings_screen.dart';
import '../trip/trip_history_screen.dart';

/// Profile Screen for Driver App
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final languageViewModel = context.watch<LanguageViewModel>();
    final isTagalog = languageViewModel.isTagalog;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(isTagalog ? 'Profile' : 'Profile'),
      ),
      body: DriverAppBackground(
        safeArea: false,
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                // Profile Header
                Consumer<JeepneyViewModel>(
                  builder: (context, jeepneyViewModel, _) {
                    return DriverGlassSurface(
                      padding: const EdgeInsets.all(24),
                      borderRadius: BorderRadius.circular(18),
                      backgroundColor:
                          AppTheme.primaryBlue.withValues(alpha: 0.72),
                      borderColor: Colors.white.withValues(alpha: 0.32),
                      child: Column(
                        children: [
                          // Avatar
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.person,
                              size: 48,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 16),
                          // Name
                          Text(
                            jeepneyViewModel.driverName,
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          // Jeepney Info
                          Text(
                            jeepneyViewModel.plateNumber.isNotEmpty &&
                                    jeepneyViewModel.plateNumber != 'N/A'
                                ? jeepneyViewModel.plateNumber
                                : (isTagalog ? 'Walang jeepney' : 'No jeepney'),
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.white.withValues(alpha: 0.8),
                            ),
                          ),
                          if (jeepneyViewModel.currentRouteName.isNotEmpty &&
                              jeepneyViewModel.currentRouteName !=
                                  'No Route Assigned')
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                jeepneyViewModel.currentRouteName,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white.withValues(alpha: 0.6),
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 32),

                // Menu Items
                _MenuItem(
                  icon: Icons.notifications_outlined,
                  title: isTagalog
                      ? 'Tingnan ang lahat ng Notifications'
                      : 'View all Notifications',
                  onTap: () {
                    AppRouter.goToNotifications(context);
                  },
                ),
                const SizedBox(height: 16),

                // Trip History Button
                _MenuItem(
                  icon: Icons.history,
                  title: isTagalog ? 'Kasaysayan ng Biyahe' : 'Trip History',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const TripHistoryScreen(),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 24),

                const _RatingsFeedbackSection(),
                const SizedBox(height: 24),

                // Logout Button
                Consumer<AuthViewModel>(
                  builder: (context, authViewModel, _) {
                    return SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          // Show confirmation dialog
                          final bool? shouldLogout = await showDialog<bool>(
                            context: context,
                            builder: (BuildContext context) {
                              final dialogLanguageViewModel =
                                  context.read<LanguageViewModel>();
                              final dialogIsTagalog =
                                  dialogLanguageViewModel.isTagalog;
                              return AlertDialog(
                                title: Text(dialogIsTagalog
                                    ? 'Kumpirmasyon ng Pag-logout'
                                    : 'Logout Confirmation'),
                                content: Text(dialogIsTagalog
                                    ? 'Sigurado ka bang gusto mong mag-logout?'
                                    : 'Are you sure you want to logout?'),
                                actions: <Widget>[
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(context).pop(false),
                                    child: Text(dialogIsTagalog
                                        ? 'Kanselahin'
                                        : 'Cancel'),
                                  ),
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(context).pop(true),
                                    style: TextButton.styleFrom(
                                      foregroundColor: Colors.red,
                                    ),
                                    child: Text(dialogIsTagalog
                                        ? 'Mag-logout'
                                        : 'Logout'),
                                  ),
                                ],
                              );
                            },
                          );

                          if (shouldLogout == true && context.mounted) {
                            FirestoreService.clearDriverCache();
                            context.read<JeepneyViewModel>().resetState();
                            context.read<TripViewModel>().reset();
                            await authViewModel.logout();
                            if (context.mounted) {
                              AppRouter.goToLogin(context);
                            }
                          }
                        },
                        icon: const Icon(Icons.logout, color: Colors.red),
                        label: Text(
                          isTagalog ? 'Mag-logout' : 'Logout',
                          style: const TextStyle(color: Colors.red),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.red),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RatingsFeedbackSection extends StatelessWidget {
  const _RatingsFeedbackSection();

  @override
  Widget build(BuildContext context) {
    final jeepneyViewModel = context.watch<JeepneyViewModel>();
    final languageViewModel = context.watch<LanguageViewModel>();
    final isTagalog = languageViewModel.isTagalog;
    final driverId = jeepneyViewModel.driverId.trim();

    if (driverId.isEmpty) {
      return _RatingContainer(
        child: Text(
          isTagalog
              ? 'Maglo-load ang ratings kapag handa na ang profile.'
              : 'Ratings will load when your profile is ready.',
          style: TextStyle(color: Colors.grey.shade600),
        ),
      );
    }

    return _RatingContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.star_rounded, color: Color(0xFFF59E0B)),
              const SizedBox(width: 8),
              Text(
                isTagalog ? 'Mga Rating' : 'Ratings',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          StreamBuilder<DriverRatingSummary>(
            stream: FeedbackService.watchDriverRatingSummary(driverId),
            builder: (context, snapshot) {
              final summary = snapshot.data ?? DriverRatingSummary.empty();
              return Row(
                children: [
                  Text(
                    summary.ratingCount == 0
                        ? '0.0'
                        : summary.averageRating.toStringAsFixed(1),
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.primaryBlue,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RatingStars(rating: summary.averageRating.round()),
                      const SizedBox(height: 3),
                      Text(
                        summary.ratingCount == 1
                            ? '1 review'
                            : '${summary.ratingCount} reviews',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          StreamBuilder<List<DriverFeedback>>(
            stream: FeedbackService.watchRecentDriverFeedback(driverId),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Text(
                  isTagalog
                      ? 'Hindi ma-load ang ratings.'
                      : 'Could not load ratings.',
                  style: TextStyle(color: Colors.red.shade600),
                );
              }

              final feedback = snapshot.data ?? const <DriverFeedback>[];
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: CircularProgressIndicator(),
                  ),
                );
              }

              if (feedback.isEmpty) {
                return Text(
                  isTagalog ? 'Wala pang ratings.' : 'No ratings yet.',
                  style: TextStyle(color: Colors.grey.shade600),
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ...feedback.map((item) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: RatingCommentTile(feedback: item),
                    );
                  }),
                  const SizedBox(height: 14),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => DriverRatingsScreen(
                            driverId: driverId,
                            isTagalog: isTagalog,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.format_list_bulleted),
                    label: Text(isTagalog ? 'Tingnan lahat' : 'View All'),
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

class _RatingContainer extends StatelessWidget {
  final Widget child;

  const _RatingContainer({required this.child});

  @override
  Widget build(BuildContext context) {
    return DriverGlassSurface(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      child: child,
    );
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const _MenuItem({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return DriverGlassSurface(
      margin: const EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.zero,
      borderRadius: BorderRadius.circular(12),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.lightBlue,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: AppTheme.primaryBlue, size: 20),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Icon(Icons.arrow_forward_ios,
                    color: Colors.grey[400], size: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
