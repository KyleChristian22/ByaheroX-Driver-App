// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'ByaheroX Driver';

  @override
  String get driverLogin => 'Driver Login';

  @override
  String get email => 'Email';

  @override
  String get enterYourEmail => 'Enter your email';

  @override
  String get emailIsRequired => 'Email is required';

  @override
  String get enterValidEmail => 'Please enter a valid email address';

  @override
  String get password => 'Password';

  @override
  String get enterYourPassword => 'Enter your password';

  @override
  String get passwordIsRequired => 'Password is required';

  @override
  String get passwordMinLength => 'Password must be at least 6 characters';

  @override
  String get login => 'Login';

  @override
  String get forgotPassword => 'Forgot Password?';

  @override
  String get resetPassword => 'Reset Password';

  @override
  String get resetPasswordDescription =>
      'Enter your email address and we will send you a link to reset your password.';

  @override
  String get cancel => 'Cancel';

  @override
  String get sendResetLink => 'Send Reset Link';

  @override
  String get passwordResetSent => 'Password reset link sent! Check your email.';

  @override
  String get failedToSendReset => 'Failed to send reset email';

  @override
  String tryAgainIn(String seconds) {
    return 'Try again in $seconds';
  }

  @override
  String get switchLanguage => 'Switch Language';

  @override
  String get english => 'English';

  @override
  String get tagalog => 'Tagalog';
}
