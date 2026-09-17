import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/router/app_router.dart';
import '../../../l10n/app_localizations.dart';
import '../../viewmodels/auth_viewmodel.dart';
import '../../viewmodels/jeepney_viewmodel.dart';
import '../../widgets/common/app_background.dart';

/// Dashboard screen - landing page for logged in commuters
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Timer? _dashboardLoadingTimeoutTimer;
  Timer? _minimumDashboardLoadingTimer;
  bool _hasCompletedInitialDashboardLoad = false;
  bool _dashboardLoadingTimedOut = false;
  bool _hasMetMinimumDashboardLoadingTime = false;
  bool _hasQueuedNotLoggedInRedirect = false;

  @override
  void initState() {
    super.initState();
    _startInitialDashboardLoadingTimeout();
    _startMinimumDashboardLoadingTimer();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<JeepneyViewModel>().initialize();
    });
  }

  @override
  void dispose() {
    _dashboardLoadingTimeoutTimer?.cancel();
    _minimumDashboardLoadingTimer?.cancel();
    super.dispose();
  }

  void _startInitialDashboardLoadingTimeout() {
    _dashboardLoadingTimeoutTimer?.cancel();
    _dashboardLoadingTimeoutTimer = Timer(const Duration(seconds: 8), () {
      if (!mounted || _hasCompletedInitialDashboardLoad) return;

      setState(() {
        _dashboardLoadingTimedOut = true;
      });
    });
  }

  void _startMinimumDashboardLoadingTimer() {
    _minimumDashboardLoadingTimer?.cancel();
    _minimumDashboardLoadingTimer = Timer(
      const Duration(milliseconds: 1800),
      () {
        if (!mounted) return;

        setState(() {
          _hasMetMinimumDashboardLoadingTime = true;
        });
      },
    );
  }

  bool _isInitialDashboardLoadReady(
    AuthViewModel authViewModel,
    JeepneyViewModel jeepneyViewModel,
  ) {
    final hasAccountCheckCompleted =
        authViewModel.hasResolvedInitialAuthState && !authViewModel.isLoading;
    final hasLiveDataFirstPass =
        jeepneyViewModel.isInitialized && !jeepneyViewModel.isLoading;

    return _hasMetMinimumDashboardLoadingTime &&
        hasAccountCheckCompleted &&
        hasLiveDataFirstPass;
  }

  void _completeInitialDashboardLoadIfReady(
    AuthViewModel authViewModel,
    JeepneyViewModel jeepneyViewModel,
  ) {
    if (_hasCompletedInitialDashboardLoad || _dashboardLoadingTimedOut) return;
    if (!_isInitialDashboardLoadReady(authViewModel, jeepneyViewModel)) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _hasCompletedInitialDashboardLoad) return;
      setState(() {
        _hasCompletedInitialDashboardLoad = true;
      });
      _dashboardLoadingTimeoutTimer?.cancel();
    });
  }

  void _redirectIfAccountIsNotLoggedIn(AuthViewModel authViewModel) {
    if (_hasQueuedNotLoggedInRedirect ||
        !authViewModel.hasResolvedInitialAuthState ||
        authViewModel.isLoggedIn) {
      return;
    }

    _hasQueuedNotLoggedInRedirect = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.go(AppRouter.welcome);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final authViewModel = context.watch<AuthViewModel>();
    final jeepneyViewModel = context.watch<JeepneyViewModel>();
    _redirectIfAccountIsNotLoggedIn(authViewModel);
    _completeInitialDashboardLoadIfReady(authViewModel, jeepneyViewModel);
    final showInitialDashboardLoading =
        !_hasCompletedInitialDashboardLoad && !_dashboardLoadingTimedOut;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: showInitialDashboardLoading
          ? _buildInitialDashboardLoadingScreen(
              context,
              authViewModel,
              jeepneyViewModel,
            )
          : _buildDashboardContent(context, l10n),
    );
  }

  Widget _buildDashboardContent(BuildContext context, AppLocalizations l10n) {
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxHeight < 820;
          final pagePadding = isCompact ? 12.0 : AppDimensions.md;
          final availableHeight = constraints.maxHeight - (pagePadding * 2);
          final headerGap = (availableHeight * 0.025).clamp(10.0, 22.0);
          final sectionGap = (availableHeight * 0.02).clamp(8.0, 18.0);
          final actionCardHeight = (availableHeight * 0.24).clamp(142.0, 190.0);
          final liveStatsHeight = (availableHeight * 0.18).clamp(118.0, 152.0);

          return Padding(
            padding: EdgeInsets.all(pagePadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(context, l10n, compact: isCompact),
                SizedBox(height: headerGap),
                Expanded(
                  child: Column(
                    children: [
                      const Spacer(),
                      _buildQuickActions(
                        context,
                        l10n,
                        compact: isCompact,
                        cardHeight: actionCardHeight,
                      ),
                      SizedBox(height: sectionGap),
                      _buildLiveJeepneysSection(
                        context,
                        l10n,
                        compact: isCompact,
                        statsHeight: liveStatsHeight,
                      ),
                      const Spacer(),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildInitialDashboardLoadingScreen(
    BuildContext context,
    AuthViewModel authViewModel,
    JeepneyViewModel jeepneyViewModel,
  ) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final hasAccountCheckCompleted =
        authViewModel.hasResolvedInitialAuthState && !authViewModel.isLoading;
    final hasLiveDataFirstPass =
        jeepneyViewModel.isInitialized && !jeepneyViewModel.isLoading;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppDimensions.lg),
        child: Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0.96, end: 1),
            duration: reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 520),
            curve: Curves.easeOutCubic,
            builder: (context, scale, child) {
              return Transform.scale(scale: scale, child: child);
            },
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 340),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: AppColors.primaryBlueSurface.withValues(
                        alpha: 0.72,
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: SizedBox(
                        width: 42,
                        height: 42,
                        child: CircularProgressIndicator(
                          strokeWidth: 4,
                          color: AppColors.primaryBlue,
                          backgroundColor: AppColors.surface.withValues(
                            alpha: 0.72,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppDimensions.lg),
                  Text(
                    'Loading dashboard',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: AppDimensions.xs),
                  Text(
                    'Checking your account and live jeepney stats...',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppDimensions.xl),
                  _buildDashboardLoadingStep(
                    context,
                    label: 'Checking account',
                    isComplete: hasAccountCheckCompleted,
                  ),
                  const SizedBox(height: AppDimensions.sm),
                  _buildDashboardLoadingStep(
                    context,
                    label: 'Live jeepney data',
                    isComplete: hasLiveDataFirstPass,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDashboardLoadingStep(
    BuildContext context, {
    required String label,
    required bool isComplete,
  }) {
    final color = isComplete ? AppColors.success : AppColors.primaryBlue;

    return Row(
      children: [
        SizedBox(
          width: 18,
          height: 18,
          child: isComplete
              ? Icon(Icons.check_circle, size: 18, color: color)
              : CircularProgressIndicator(strokeWidth: 2, color: color),
        ),
        const SizedBox(width: AppDimensions.sm),
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(
    BuildContext context,
    AppLocalizations l10n, {
    required bool compact,
  }) {
    final authViewModel = context.watch<AuthViewModel>();
    final user = authViewModel.currentUser;
    final greeting = _getGreeting(context);
    final avatarSize = compact ? 54.0 : 62.0;

    return GlassSurface(
      padding: EdgeInsets.all(compact ? 18 : AppDimensions.lg),
      backgroundColor: AppColors.surface.withValues(alpha: 0.32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Avatar and Name
              Expanded(
                child: Row(
                  children: [
                    Container(
                      width: avatarSize,
                      height: avatarSize,
                      decoration: BoxDecoration(
                        color: AppColors.primaryBlueSurface.withValues(
                          alpha: 0.72,
                        ),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        user.isGuest ? Icons.person : Icons.person_pin,
                        color: AppColors.primaryBlue,
                        size: compact ? 30 : 34,
                      ),
                    ),
                    SizedBox(
                      width: compact ? AppDimensions.sm : AppDimensions.md,
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            greeting,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: AppColors.textSecondary),
                          ),
                          const SizedBox(height: AppDimensions.xs),
                          Text(
                            user.isGuest ? l10n.guestMode : user.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // Logout is only available in Profile page
            ],
          ),
          const SizedBox(height: AppDimensions.md),

          // Status Card
          Container(
            padding: EdgeInsets.all(compact ? 16 : AppDimensions.md),
            decoration: BoxDecoration(
              color: AppColors.surface.withValues(alpha: 0.28),
              borderRadius: AppDimensions.borderRadiusMd,
              border: Border.all(
                color: AppColors.surface.withValues(alpha: 0.42),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(compact ? 11 : AppDimensions.sm),
                  decoration: BoxDecoration(
                    color: AppColors.success,
                    borderRadius: AppDimensions.borderRadiusSm,
                  ),
                  child: Icon(
                    Icons.directions_car,
                    color: AppColors.textOnPrimary,
                    size: compact ? 28 : AppDimensions.iconMd,
                  ),
                ),
                SizedBox(width: compact ? AppDimensions.sm : AppDimensions.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ByaheroX',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        l10n.appDescription,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                          fontSize: compact ? 14 : null,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions(
    BuildContext context,
    AppLocalizations l10n, {
    required bool compact,
    required double cardHeight,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.quickActions,
          style:
              (compact
                      ? Theme.of(context).textTheme.titleSmall
                      : Theme.of(context).textTheme.titleMedium)
                  ?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
        ),
        const SizedBox(height: AppDimensions.sm),
        Row(
          children: [
            Expanded(
              child: _QuickActionCard(
                icon: Icons.map,
                label: l10n.viewOnMap,
                color: AppColors.primary,
                compact: compact,
                height: cardHeight,
                onTap: () => context.go(AppRouter.home),
              ),
            ),
            SizedBox(width: compact ? AppDimensions.sm : AppDimensions.md),
            Expanded(
              child: _QuickActionCard(
                icon: Icons.payments_outlined,
                label: 'Pamasahe',
                color: AppColors.secondary,
                compact: compact,
                height: cardHeight,
                onTap: () => context.push(AppRouter.fares),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLiveJeepneysSection(
    BuildContext context,
    AppLocalizations l10n, {
    required bool compact,
    required double statsHeight,
  }) {
    return Consumer<JeepneyViewModel>(
      builder: (context, jeepneyViewModel, _) {
        final onTripJeepneys = jeepneyViewModel.activeDriverLocations
            .where((jeepney) => jeepney.isActive)
            .toList();
        final jeepneysOnTrip = onTripJeepneys
            .map((jeepney) => jeepney.id)
            .toSet()
            .length;
        final passengersOnBoard = onTripJeepneys.fold<int>(
          0,
          (total, jeepney) => total + jeepney.passengerCount,
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    l10n.liveJeepneys,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton.icon(
                      onPressed: jeepneyViewModel.isRefreshing
                          ? null
                          : () => jeepneyViewModel.refresh(),
                      icon: jeepneyViewModel.isRefreshing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh),
                      label: const Text('Refresh'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        minimumSize: Size(48, compact ? 34 : 42),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        padding: EdgeInsets.symmetric(
                          horizontal: compact
                              ? AppDimensions.xs
                              : AppDimensions.sm,
                        ),
                      ),
                    ),
                    SizedBox(width: compact ? 2 : AppDimensions.xs),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppDimensions.sm,
                        vertical: AppDimensions.xs,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.successLight,
                        borderRadius: AppDimensions.borderRadiusFull,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: AppColors.success,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: AppDimensions.xs),
                          Text(
                            l10n.live,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: AppColors.secondaryDark,
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            SizedBox(height: compact ? AppDimensions.xs : AppDimensions.sm),
            GlassSurface(
              height: statsHeight,
              padding: EdgeInsets.all(compact ? 10 : AppDimensions.md),
              child: Row(
                children: [
                  // Jeepneys on trip
                  Expanded(
                    child: _StatCard(
                      icon: Icons.directions_car,
                      value: '$jeepneysOnTrip',
                      label: 'Jeepneys On Trip',
                      color: AppColors.primary,
                      compact: compact,
                      height: statsHeight,
                    ),
                  ),
                  Container(
                    width: 1,
                    height: (statsHeight * 0.48).clamp(54.0, 72.0),
                    color: AppColors.divider,
                  ),
                  // Passengers on board
                  Expanded(
                    child: _StatCard(
                      icon: Icons.groups,
                      value: '$passengersOnBoard',
                      label: 'Passengers On Board',
                      color: AppColors.secondary,
                      compact: compact,
                      height: statsHeight,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  String _getGreeting(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final hour = DateTime.now().hour;
    if (hour < 12) {
      return l10n.goodMorning;
    } else if (hour < 17) {
      return l10n.goodAfternoon;
    } else {
      return l10n.goodEvening;
    }
  }
}

/// Quick action card widget
class _QuickActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool compact;
  final double height;

  const _QuickActionCard({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    required this.compact,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    final iconSize = (height * 0.26).clamp(34.0, 48.0);
    final iconPadding = (height * 0.1).clamp(12.0, 18.0);
    final labelSize = (height * 0.12).clamp(16.0, 20.0);

    return Material(
      color: Colors.transparent,
      borderRadius: AppDimensions.borderRadiusMd,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppDimensions.borderRadiusMd,
        child: GlassSurface(
          height: height,
          padding: EdgeInsets.all(compact ? 12 : AppDimensions.md),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: EdgeInsets.all(iconPadding),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: AppDimensions.borderRadiusMd,
                ),
                child: Icon(icon, color: color, size: iconSize),
              ),
              SizedBox(height: compact ? AppDimensions.sm : AppDimensions.md),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontSize: labelSize,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Stat card widget for dashboard
class _StatCard extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;
  final bool compact;
  final double height;

  const _StatCard({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
    required this.compact,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : height;
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 160.0;
        final safeHeight = availableHeight <= 0 ? height : availableHeight;
        final iconSize = (safeHeight * 0.28)
            .clamp(24.0, compact ? 32.0 : 42.0)
            .toDouble();
        final valueSize = (safeHeight * 0.25)
            .clamp(22.0, compact ? 28.0 : 32.0)
            .toDouble();
        final labelSize = (safeHeight * 0.12)
            .clamp(11.0, compact ? 13.0 : 16.0)
            .toDouble();
        final gap = (safeHeight * 0.04)
            .clamp(2.0, compact ? 5.0 : 8.0)
            .toDouble();

        return Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: SizedBox(
              width: availableWidth,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: color, size: iconSize),
                  SizedBox(height: gap),
                  Text(
                    value,
                    maxLines: 1,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontSize: valueSize,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                      fontSize: labelSize,
                      height: 1.05,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
