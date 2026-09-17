import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_dimensions.dart';
import '../../core/router/app_router.dart';
import '../../l10n/app_localizations.dart';
import '../../presentation/viewmodels/auth_viewmodel.dart';
import '../../presentation/viewmodels/pickup_location_provider.dart';
import '../../presentation/widgets/common/app_background.dart';

/// Main shell with bottom navigation
class MainShell extends StatefulWidget {
  final Widget child;

  const MainShell({super.key, required this.child});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  DateTime? _lastBackPressedAt;

  Future<void> _confirmLogoutAndGoToLogin(AuthViewModel authViewModel) async {
    final l10n = AppLocalizations.of(context);
    final shouldLogout = await showDialog<bool>(
      context: context,
      barrierColor: AppColors.textPrimary.withValues(alpha: 0.38),
      builder: (dialogContext) => AlertDialog(
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
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.logout),
          ),
        ],
      ),
    );

    if (shouldLogout != true || !mounted) return;

    // Clear pickup location before logout
    if (authViewModel.isLoggedIn && !authViewModel.currentUser.isGuest) {
      final pickupProvider = context.read<PickupLocationProvider>();
      await pickupProvider.clearPickupLocation(
        authViewModel.currentUser.id,
        force: true,
      );
    }

    await authViewModel.logout();
    if (!mounted) return;

    context.go(AppRouter.login);
  }

  Future<void> _handleBackPress() async {
    if (!mounted) return;

    final l10n = AppLocalizations.of(context);
    final authViewModel = context.read<AuthViewModel>();
    final isGuest = authViewModel.isGuest;
    final location = GoRouterState.of(context).uri.toString();

    if (!isGuest) {
      if (location.startsWith(AppRouter.home) ||
          location.startsWith(AppRouter.profile)) {
        context.go(AppRouter.dashboard);
        return;
      }

      if (location.startsWith(AppRouter.dashboard)) {
        final now = DateTime.now();
        final isSecondPress =
            _lastBackPressedAt != null &&
            now.difference(_lastBackPressedAt!) <= const Duration(seconds: 2);

        if (!isSecondPress) {
          _lastBackPressedAt = now;
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                content: Text(l10n.guestModeSubtitle),
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 2),
              ),
            );
          return;
        }

        _lastBackPressedAt = null;
        await _confirmLogoutAndGoToLogin(authViewModel);
        return;
      }
    }

    // Fallback behavior: keep accidental exits from happening.
    final now = DateTime.now();
    final isSecondPress =
        _lastBackPressedAt != null &&
        now.difference(_lastBackPressedAt!) <= const Duration(seconds: 2);

    if (!isSecondPress) {
      _lastBackPressedAt = now;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(l10n.guestModeSubtitle),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      return;
    }

    context.go(isGuest ? AppRouter.welcome : AppRouter.dashboard);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final authViewModel = context.watch<AuthViewModel>();
    final isGuest = authViewModel.isGuest;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _handleBackPress();
      },
      child: Scaffold(
        body: widget.child,
        bottomNavigationBar: SafeArea(
          bottom: false,
          child: GlassSurface(
            padding: EdgeInsets.zero,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
            backgroundColor: AppColors.surface.withValues(alpha: 0.34),
            child: NavigationBar(
              selectedIndex: _calculateSelectedIndex(context),
              onDestinationSelected: (index) =>
                  _onItemTapped(index, context, isGuest),
              labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
              destinations: isGuest
                  ? [
                      NavigationDestination(
                        icon: Tooltip(
                          message: l10n.navMap,
                          child: const Icon(Icons.map_outlined),
                        ),
                        selectedIcon: const Icon(Icons.map),
                        label: l10n.navMap,
                      ),
                      NavigationDestination(
                        icon: Tooltip(
                          message: l10n.navProfile,
                          child: const Icon(Icons.person_outline),
                        ),
                        selectedIcon: const Icon(Icons.person),
                        label: l10n.navProfile,
                      ),
                    ]
                  : [
                      const NavigationDestination(
                        icon: Tooltip(
                          message: 'Dashboard',
                          child: Icon(Icons.dashboard_outlined),
                        ),
                        selectedIcon: Icon(Icons.dashboard),
                        label: 'Dashboard',
                      ),
                      NavigationDestination(
                        icon: Tooltip(
                          message: l10n.navMap,
                          child: const Icon(Icons.map_outlined),
                        ),
                        selectedIcon: const Icon(Icons.map),
                        label: l10n.navMap,
                      ),
                      NavigationDestination(
                        icon: Tooltip(
                          message: l10n.navProfile,
                          child: const Icon(Icons.person_outline),
                        ),
                        selectedIcon: const Icon(Icons.person),
                        label: l10n.navProfile,
                      ),
                    ],
            ),
          ),
        ),
      ),
    );
  }

  int _calculateSelectedIndex(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    final authViewModel = context.watch<AuthViewModel>();
    final isGuest = authViewModel.isGuest;

    if (isGuest) {
      if (location.startsWith('/home')) {
        return 0;
      }
      if (location.startsWith('/profile')) {
        return 1;
      }
      return 0;
    }

    if (location.startsWith('/dashboard')) {
      return 0;
    }
    if (location.startsWith('/home')) {
      return 1;
    }
    if (location.startsWith('/profile')) {
      return 2;
    }
    return 0;
  }

  void _onItemTapped(int index, BuildContext context, bool isGuest) {
    final currentLocation = GoRouterState.of(context).uri.toString();

    if (isGuest) {
      if (index == 0) {
        if (!currentLocation.startsWith('/home')) {
          context.go(AppRouter.home);
        }
      } else if (index == 1) {
        context.go(AppRouter.profile);
      }
      return;
    }

    switch (index) {
      case 0:
        context.go(AppRouter.dashboard);
        break;
      case 1:
        context.go(AppRouter.home);
        break;
      case 2:
        context.go(AppRouter.profile);
        break;
    }
  }
}
