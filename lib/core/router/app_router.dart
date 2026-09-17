import 'package:flutter/material.dart';
import '../../presentation/screens/auth/startup_auth_gate.dart';
import '../../presentation/screens/auth/login_screen.dart';
import '../../presentation/screens/auth/change_password_screen.dart';
import '../../presentation/screens/auth/email_verification_screen.dart';
import '../../presentation/screens/home/main_navigation_screen.dart';
import '../../presentation/screens/notifications/notifications_screen.dart';

/// App Router Configuration
class AppRouter {
  AppRouter._();

  /// Route names
  static const String authGate = '/';
  static const String login = '/login';
  static const String main = '/main';
  static const String notifications = '/notifications';
  static const String changePassword = '/change-password';
  static const String emailVerification = '/email-verification';

  /// Navigator keys
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  /// Route generator
  static Route<dynamic> generateRoute(RouteSettings settings) {
    switch (settings.name) {
      case authGate:
        return MaterialPageRoute(
          builder: (_) => const StartupAuthGate(),
          settings: settings,
        );
      case login:
        return MaterialPageRoute(
          builder: (_) => const LoginScreen(),
          settings: settings,
        );
      case main:
        return MaterialPageRoute(
          builder: (_) => const MainNavigationScreen(),
          settings: settings,
        );
      case changePassword:
        return MaterialPageRoute(
          builder: (_) => const ChangePasswordScreen(),
          settings: settings,
        );
      case emailVerification:
        return MaterialPageRoute(
          builder: (_) => const EmailVerificationScreen(),
          settings: settings,
        );
      case notifications:
        return MaterialPageRoute(
          builder: (_) => const NotificationsScreen(),
          settings: settings,
        );
      default:
        return MaterialPageRoute(
          builder: (_) => const LoginScreen(),
          settings: settings,
        );
    }
  }

  /// Navigate to login
  static void goToLogin(BuildContext context) {
    Navigator.of(context)
        .pushNamedAndRemoveUntil(login, (Route<dynamic> route) => false);
  }

  /// Navigate to main (after login)
  static void goToMain(BuildContext context) {
    Navigator.of(context)
        .pushNamedAndRemoveUntil(main, (Route<dynamic> route) => false);
  }

  /// Navigate to change password (for temporary/admin-created accounts)
  static void goToChangePassword(BuildContext context) {
    Navigator.of(context).pushNamedAndRemoveUntil(
        changePassword, (Route<dynamic> route) => false);
  }

  /// Navigate to email verification screen
  static void goToEmailVerification(BuildContext context) {
    Navigator.of(context).pushNamedAndRemoveUntil(
        emailVerification, (Route<dynamic> route) => false);
  }

  /// Navigate to notifications
  static void goToNotifications(BuildContext context) {
    Navigator.of(context).pushNamed(notifications);
  }
}
