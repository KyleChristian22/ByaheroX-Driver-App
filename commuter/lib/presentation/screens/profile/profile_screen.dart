import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/router/app_router.dart';
import '../../../l10n/app_localizations.dart';
import '../../viewmodels/auth_viewmodel.dart';
import '../../viewmodels/pickup_location_provider.dart';
import '../../widgets/common/app_background.dart';

/// Profile screen - displays user profile and settings
/// Fully responsive with SafeArea and LayoutBuilder
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Responsive calculations based on screen width
            final screenWidth = constraints.maxWidth;
            final isSmallScreen = screenWidth < 360;
            final isLargeScreen = screenWidth > 400;

            // Responsive sizing
            final avatarSize = isSmallScreen
                ? AppDimensions.avatarLg * 0.9
                : isLargeScreen
                ? AppDimensions.avatarLg * 1.2
                : AppDimensions.avatarLg;
            final headerPadding = isSmallScreen
                ? AppDimensions.md
                : isLargeScreen
                ? AppDimensions.lg
                : AppDimensions.md;
            final titleFontSize = isSmallScreen ? 18.0 : 22.0;
            final subtitleFontSize = isSmallScreen ? 12.0 : 14.0;

            return SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.symmetric(
                horizontal: isSmallScreen ? AppDimensions.sm : AppDimensions.md,
                vertical: AppDimensions.md,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Compact Profile Header
                  _buildProfileHeader(
                    context,
                    l10n: l10n,
                    avatarSize: avatarSize,
                    padding: headerPadding,
                    titleFontSize: titleFontSize,
                    subtitleFontSize: subtitleFontSize,
                  ),
                  const SizedBox(height: AppDimensions.md),

                  // Guest: prominent Login button
                  if (context.watch<AuthViewModel>().isGuest)
                    _buildGuestLoginButton(
                      context,
                      isSmallScreen: isSmallScreen,
                      l10n: l10n,
                    ),
                  // Quick Links
                  _buildQuickLinks(
                    context,
                    isSmallScreen: isSmallScreen,
                    l10n: l10n,
                  ),
                  if (!context.watch<AuthViewModel>().isGuest) ...[
                    const SizedBox(height: AppDimensions.md),
                    _buildDiscountNotice(context),
                  ],
                  const SizedBox(height: AppDimensions.md),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildProfileHeader(
    BuildContext context, {
    required AppLocalizations l10n,
    required double avatarSize,
    required double padding,
    required double titleFontSize,
    required double subtitleFontSize,
  }) {
    final authViewModel = context.watch<AuthViewModel>();
    final user = authViewModel.currentUser;

    return GlassSurface(
      padding: EdgeInsets.all(padding),
      backgroundColor: AppColors.surface.withValues(alpha: 0.32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Compact Avatar
          Container(
            width: avatarSize * 1.5,
            height: avatarSize * 1.5,
            decoration: BoxDecoration(
              color: AppColors.primaryBlueSurface.withValues(alpha: 0.72),
              shape: BoxShape.circle,
            ),
            child: Icon(
              user.isGuest ? Icons.person : Icons.person_pin,
              color: AppColors.primaryBlue,
              size: avatarSize,
            ),
          ),
          SizedBox(height: padding * 0.5),
          Text(
            user.isGuest ? l10n.guestMode : user.displayName,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.bold,
              fontSize: titleFontSize,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
          if (!user.isGuest) ...[
            const SizedBox(height: AppDimensions.xs),
            Text(
              user.email,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
                fontSize: subtitleFontSize,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildQuickLinks(
    BuildContext context, {
    required bool isSmallScreen,
    required AppLocalizations l10n,
  }) {
    final iconSize = isSmallScreen
        ? AppDimensions.iconSm
        : AppDimensions.iconMd;
    final fontSize = isSmallScreen ? 14.0 : 16.0;
    final subtitleFontSize = isSmallScreen ? 11.0 : 12.0;
    final tilePadding = isSmallScreen ? AppDimensions.sm : AppDimensions.md;
    final isGuest = context.watch<AuthViewModel>().isGuest;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.navProfile,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
            fontSize: fontSize,
          ),
        ),
        SizedBox(height: isSmallScreen ? AppDimensions.sm : AppDimensions.md),
        _QuickLinkTile(
          icon: Icons.account_balance_wallet_outlined,
          title: 'Wallet',
          subtitle: 'View balance & transaction history',
          iconSize: iconSize,
          fontSize: fontSize,
          subtitleFontSize: subtitleFontSize,
          padding: tilePadding,
          onTap: isGuest
              ? () => _showGuestAccessModal(context, featureName: 'Wallet')
              : () => context.go(AppRouter.wallet),
        ),
        SizedBox(height: isSmallScreen ? AppDimensions.xs : AppDimensions.sm),
        _QuickLinkTile(
          icon: Icons.payments_outlined,
          title: 'Pamasahe Guide',
          subtitle: 'Check fares by destination',
          iconSize: iconSize,
          fontSize: fontSize,
          subtitleFontSize: subtitleFontSize,
          padding: tilePadding,
          onTap: () => context.push(AppRouter.fares),
        ),
        SizedBox(height: isSmallScreen ? AppDimensions.xs : AppDimensions.sm),
        _QuickLinkTile(
          icon: Icons.route_outlined,
          title: 'Completed Trips',
          subtitle: 'View past rides and rate your trips',
          iconSize: iconSize,
          fontSize: fontSize,
          subtitleFontSize: subtitleFontSize,
          padding: tilePadding,
          onTap: isGuest
              ? () => _showGuestAccessModal(
                  context,
                  featureName: 'Completed Trips',
                )
              : () => context.go(AppRouter.completedTrips),
        ),
        SizedBox(height: isSmallScreen ? AppDimensions.xs : AppDimensions.sm),
        _QuickLinkTile(
          icon: Icons.badge_outlined,
          title: 'Fare Discount',
          subtitle: 'Apply, renew, or check discount status',
          iconSize: iconSize,
          fontSize: fontSize,
          subtitleFontSize: subtitleFontSize,
          padding: tilePadding,
          onTap: isGuest
              ? () =>
                    _showGuestAccessModal(context, featureName: 'Fare Discount')
              : () => context.go(AppRouter.discountApplication),
        ),
        SizedBox(height: isSmallScreen ? AppDimensions.xs : AppDimensions.sm),
        _QuickLinkTile(
          icon: Icons.info_outline,
          title: 'About',
          subtitle: l10n.appDescription,
          iconSize: iconSize,
          fontSize: fontSize,
          subtitleFontSize: subtitleFontSize,
          padding: tilePadding,
          onTap: () => _showAboutDialog(context),
        ),
        SizedBox(height: isSmallScreen ? AppDimensions.xs : AppDimensions.sm),
        // Show logout only for logged-in users (not guests)
        if (!isGuest)
          _QuickLinkTile(
            icon: Icons.logout,
            title: l10n.logout,
            isDestructive: true,
            iconSize: iconSize,
            fontSize: fontSize,
            subtitleFontSize: subtitleFontSize,
            padding: tilePadding,
            onTap: () async {
              final confirm = await showDialog<bool>(
                context: context,
                barrierColor: AppColors.textPrimary.withValues(alpha: 0.38),
                builder: (context) => AlertDialog(
                  backgroundColor: AppColors.surface.withValues(alpha: 0.92),
                  surfaceTintColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: AppDimensions.borderRadiusLg,
                    side: BorderSide(
                      color: AppColors.surface.withValues(alpha: 0.72),
                    ),
                  ),
                  title: Text(l10n.logout),
                  content: Text(l10n.guestModeSubtitle),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: Text(l10n.cancel),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.error,
                      ),
                      child: Text(l10n.logout),
                    ),
                  ],
                ),
              );

              if (confirm == true && context.mounted) {
                final authViewModel = context.read<AuthViewModel>();
                final pickupProvider = context.read<PickupLocationProvider>();

                // Clear pickup location before logout
                if (authViewModel.isLoggedIn &&
                    !authViewModel.currentUser.isGuest) {
                  await pickupProvider.clearPickupLocation(
                    authViewModel.currentUser.id,
                  );
                }

                await authViewModel.logout();
                if (context.mounted) {
                  context.go(AppRouter.welcome);
                }
              }
            },
          ),
      ],
    );
  }

  Widget _buildGuestLoginButton(
    BuildContext context, {
    required bool isSmallScreen,
    required AppLocalizations l10n,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () => _goToLoginFromGuest(context),
            icon: const Icon(Icons.login),
            label: Text(l10n.login),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              backgroundColor: AppColors.primaryBlue,
              foregroundColor: Colors.white,
              textStyle: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: AppDimensions.borderRadiusMd,
              ),
            ),
          ),
        ),
        const SizedBox(height: AppDimensions.md),
      ],
    );
  }

  Future<void> _goToLoginFromGuest(BuildContext context) async {
    final authViewModel = context.read<AuthViewModel>();

    if (authViewModel.isGuest) {
      await authViewModel.logout();
    }

    if (context.mounted) {
      context.go(AppRouter.login);
    }
  }

  Future<void> _goToRegisterFromGuest(BuildContext context) async {
    final authViewModel = context.read<AuthViewModel>();

    if (authViewModel.isGuest) {
      await authViewModel.logout();
    }

    if (context.mounted) {
      context.go(AppRouter.register);
    }
  }

  Future<void> _showGuestAccessModal(
    BuildContext context, {
    required String featureName,
  }) async {
    final l10n = AppLocalizations.of(context);

    await showDialog<void>(
      context: context,
      barrierColor: AppColors.textPrimary.withValues(alpha: 0.38),
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface.withValues(alpha: 0.92),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: AppDimensions.borderRadiusLg,
          side: BorderSide(color: AppColors.surface.withValues(alpha: 0.72)),
        ),
        title: const Text('Account required'),
        content: Text(
          'Log in or create an account first to access $featureName.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _goToRegisterFromGuest(context);
            },
            child: Text(l10n.createAccount),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _goToLoginFromGuest(context);
            },
            child: Text(l10n.login),
          ),
        ],
      ),
    );
  }

  Widget _buildDiscountNotice(BuildContext context) {
    final userId = context.watch<AuthViewModel>().currentUser.id;
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('commuters')
          .doc(userId)
          .snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data();
        final status =
            data?['discountStatus']?.toString().trim().toLowerCase() ?? 'none';
        final expiresAt = _toDateTime(data?['discountExpiresAt']);
        final now = DateTime.now();
        final isApproved =
            status == 'approved' && expiresAt != null && expiresAt.isAfter(now);
        final isExpiringSoon =
            isApproved && expiresAt.difference(now).inDays <= 30;
        final isExpired =
            status == 'approved' &&
            expiresAt != null &&
            !expiresAt.isAfter(now);

        Color color;
        IconData icon;
        String title;
        String body;
        if (isExpiringSoon) {
          color = AppColors.warning;
          icon = Icons.event_busy_outlined;
          title = 'Discount expiring soon';
          body =
              'Renew before ${_formatDate(expiresAt)} to keep RFID discount.';
        } else if (isApproved) {
          color = AppColors.success;
          icon = Icons.verified_outlined;
          title = 'Discount approved';
          body = 'RFID fares are discounted until ${_formatDate(expiresAt)}.';
        } else if (isExpired) {
          color = AppColors.error;
          icon = Icons.event_busy_outlined;
          title = 'Discount expired';
          body = 'RFID fares are regular until you upload new documents.';
        } else if (status == 'pending') {
          color = AppColors.warning;
          icon = Icons.hourglass_top_outlined;
          title = 'Application pending';
          body = 'RFID fares stay regular while treasurer review is pending.';
        } else {
          color = AppColors.primary;
          icon = Icons.badge_outlined;
          title = 'No active discount';
          body = 'Apply for Student, PWD, or Senior discounted RFID fares.';
        }

        return InkWell(
          onTap: () => context.go(AppRouter.discountApplication),
          borderRadius: AppDimensions.borderRadiusMd,
          child: GlassSurface(
            padding: const EdgeInsets.all(AppDimensions.md),
            backgroundColor: color.withValues(alpha: 0.1),
            borderColor: color.withValues(alpha: 0.25),
            child: Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        body,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: AppColors.textSecondary),
              ],
            ),
          ),
        );
      },
    );
  }

  DateTime? _toDateTime(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  String _formatDate(DateTime? value) {
    if (value == null) return 'the expiry date';
    const months = [
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
      'Dec',
    ];
    return '${months[value.month - 1]} ${value.day}, ${value.year}';
  }

  /// Show custom About dialog without View licenses button
  void _showAboutDialog(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      barrierColor: AppColors.textPrimary.withValues(alpha: 0.38),
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface.withValues(alpha: 0.92),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: AppDimensions.borderRadiusLg,
          side: BorderSide(color: AppColors.surface.withValues(alpha: 0.72)),
        ),
        title: Text(l10n.appName),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Version 1.0.0'),
            const SizedBox(height: AppDimensions.md),
            Text(l10n.appDescription),
            const SizedBox(height: AppDimensions.md),
            const Text('© 2026 ByaheroX'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.close),
          ),
        ],
      ),
    );
  }
}

/// Quick link tile widget - compact and reusable
class _QuickLinkTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool isDestructive;
  final double iconSize;
  final double fontSize;
  final double subtitleFontSize;
  final double padding;

  const _QuickLinkTile({
    required this.icon,
    required this.title,
    this.subtitle = '',
    required this.onTap,
    this.isDestructive = false,
    this.iconSize = AppDimensions.iconMd,
    this.fontSize = 16.0,
    this.subtitleFontSize = 12.0,
    this.padding = AppDimensions.md,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: AppDimensions.borderRadiusMd,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppDimensions.borderRadiusMd,
        child: GlassSurface(
          padding: EdgeInsets.all(padding),
          child: Row(
            children: [
              Container(
                padding: EdgeInsets.all(padding * 0.6),
                decoration: BoxDecoration(
                  color: isDestructive
                      ? AppColors.error.withValues(alpha: 0.1)
                      : AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: AppDimensions.borderRadiusSm,
                ),
                child: Icon(
                  icon,
                  color: isDestructive ? AppColors.error : AppColors.primary,
                  size: iconSize,
                ),
              ),
              SizedBox(width: padding),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: fontSize,
                        color: isDestructive
                            ? AppColors.error
                            : AppColors.textPrimary,
                      ),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                          fontSize: subtitleFontSize,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: AppColors.textSecondary,
                size: iconSize,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
