import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../presentation/screens/splash/splash_screen.dart';
import '../../presentation/screens/welcome/welcome_screen.dart';
import '../../presentation/screens/login/login_screen.dart';
import '../../presentation/screens/login/forgot_password_screen.dart';
import '../../presentation/screens/login/change_password_screen.dart';
import '../../presentation/screens/register/email_verification_screen.dart';
import '../../presentation/screens/register/register_screen.dart';
import '../../presentation/screens/dashboard/dashboard_screen.dart';
import '../../presentation/screens/fares/fares_screen.dart';
import '../../presentation/screens/home/home_screen.dart';
import '../../presentation/screens/history/completed_trips_screen.dart';
import '../../presentation/screens/discount/discount_application_screen.dart';
import '../../presentation/screens/profile/profile_screen.dart';
import '../../presentation/screens/wallet/wallet_screen.dart';
import '../../presentation/screens/main_shell.dart';

/// App router configuration using GoRouter
class AppRouter {
  AppRouter._();

  /// Route names
  static const String splash = '/';
  static const String welcome = '/welcome';
  static const String login = '/login';
  static const String forgotPassword = '/forgot-password';
  static const String changePassword = '/change-password';
  static const String register = '/register';
  static const String verifyEmail = '/verify-email';
  static const String dashboard = '/dashboard';
  static const String home = '/home';
  static const String profile = '/profile';
  static const String wallet = '/wallet';
  static const String completedTrips = '/completed-trips';
  static const String discountApplication = '/discount-application';
  static const String fares = '/fares';

  /// Navigator key for the root navigator
  static final GlobalKey<NavigatorState> _rootNavigatorKey =
      GlobalKey<NavigatorState>();

  /// Navigator key for the shell navigator
  static final GlobalKey<NavigatorState> _shellNavigatorKey =
      GlobalKey<NavigatorState>();

  /// GoRouter instance
  static final GoRouter router = GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: splash,
    routes: [
      GoRoute(path: splash, builder: (context, state) => const SplashScreen()),
      GoRoute(
        path: welcome,
        builder: (context, state) => const WelcomeScreen(),
      ),
      GoRoute(path: login, builder: (context, state) => const LoginScreen()),
      GoRoute(
        path: forgotPassword,
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: changePassword,
        builder: (context, state) => const ChangePasswordScreen(),
      ),
      GoRoute(
        path: register,
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: verifyEmail,
        builder: (context, state) => const EmailVerificationScreen(),
      ),
      ShellRoute(
        navigatorKey: _shellNavigatorKey,
        builder: (context, state, child) => MainShell(child: child),
        routes: [
          GoRoute(
            path: dashboard,
            builder: (context, state) => const DashboardScreen(),
          ),
          GoRoute(path: home, builder: (context, state) => const HomeScreen()),
          GoRoute(
            path: profile,
            builder: (context, state) => const ProfileScreen(),
          ),
        ],
      ),
      GoRoute(path: wallet, builder: (context, state) => const WalletScreen()),
      GoRoute(
        path: completedTrips,
        builder: (context, state) => const CompletedTripsScreen(),
      ),
      GoRoute(
        path: discountApplication,
        builder: (context, state) => const DiscountApplicationScreen(),
      ),
      GoRoute(path: fares, builder: (context, state) => const FaresScreen()),
    ],

    redirect: (context, state) {
      final firebaseUser = FirebaseAuth.instance.currentUser;
      final isAuthenticated = firebaseUser != null && !firebaseUser.isAnonymous;
      final isGuest = firebaseUser != null && firebaseUser.isAnonymous;
      final location = state.uri.path;

      if (isAuthenticated) {
        if (location == AppRouter.welcome) {
          return AppRouter.dashboard;
        }
        return null;
      }

      if (isGuest) {
        // Guest users can access the guest shell and auth routes.
        // Keep protected account features unavailable until they sign in.
        const guestAllowedRoutes = <String>{
          AppRouter.welcome,
          AppRouter.login,
          AppRouter.forgotPassword,
          AppRouter.register,
          AppRouter.home,
          AppRouter.profile,
          AppRouter.fares,
        };
        if (guestAllowedRoutes.contains(location)) {
          return null;
        }
        return AppRouter.home;
      }

      // Completely unauthenticated user
      const protectedRoutes = <String>{
        AppRouter.dashboard,
        AppRouter.home,
        AppRouter.profile,
        AppRouter.wallet,
        AppRouter.completedTrips,
        AppRouter.discountApplication,
        AppRouter.fares,
      };

      if (protectedRoutes.contains(location)) {
        return AppRouter.welcome;
      }

      return null;
    },
  );

  /// Navigate to dashboard
  static void goToDashboard(BuildContext context) {
    context.go(dashboard);
  }

  /// Navigate to home
  static void goToHome(BuildContext context) {
    context.go(home);
  }

  /// Navigate to login
  static void goToLogin(BuildContext context) {
    context.go(login);
  }

  /// Navigate to forgot password
  static void goToForgotPassword(BuildContext context) {
    context.go(forgotPassword);
  }

  static void goToChangePassword(BuildContext context) {
    context.go(changePassword);
  }

  /// Navigate to register
  static void goToRegister(BuildContext context) {
    context.go(register);
  }

  /// Navigate to email verification
  static void goToVerifyEmail(BuildContext context) {
    context.go(verifyEmail);
  }

  /// Navigate to wallet
  static void goToWallet(BuildContext context) {
    context.go(wallet);
  }

  static void goToCompletedTrips(BuildContext context) {
    context.go(completedTrips);
  }

  static void goToDiscountApplication(BuildContext context) {
    context.go(discountApplication);
  }

  static void goToFares(BuildContext context) {
    context.push(fares);
  }

  /// Navigate to splash
  static void goToSplash(BuildContext context) {
    context.go(splash);
  }

  /// Navigate to welcome
  static void goToWelcome(BuildContext context) {
    context.go(welcome);
  }
}
