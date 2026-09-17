// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Tagalog (`tl`).
class AppLocalizationsTl extends AppLocalizations {
  AppLocalizationsTl([String locale = 'tl']) : super(locale);

  @override
  String get appName => 'ByaheroX Driver';

  @override
  String get driverLogin => 'Pag-login ng Driver';

  @override
  String get email => 'Email';

  @override
  String get enterYourEmail => 'Ilagay ang iyong email';

  @override
  String get emailIsRequired => 'Kailangan ang email';

  @override
  String get enterValidEmail => 'Mangyaring maglagay ng wastong email address';

  @override
  String get password => 'Password';

  @override
  String get enterYourPassword => 'Ilagay ang iyong password';

  @override
  String get passwordIsRequired => 'Kailangan ang password';

  @override
  String get passwordMinLength =>
      'Ang password ay dapat may hindi bababa sa 6 na character';

  @override
  String get login => 'Mag-login';

  @override
  String get forgotPassword => 'Nakalimutan ang Password?';

  @override
  String get resetPassword => 'I-reset ang Password';

  @override
  String get resetPasswordDescription =>
      'Ilagay ang iyong email address at padadalhan ka namin ng link para i-reset ang iyong password.';

  @override
  String get cancel => 'Kanselahin';

  @override
  String get sendResetLink => 'Ipadala ang Reset Link';

  @override
  String get passwordResetSent =>
      'Naipadala ang password reset link! Suriin ang iyong email.';

  @override
  String get failedToSendReset => 'Nabigong magpadala ng reset email';

  @override
  String tryAgainIn(String seconds) {
    return 'Subukan muli sa $seconds';
  }

  @override
  String get switchLanguage => 'Palitan ang Wika';

  @override
  String get english => 'English';

  @override
  String get tagalog => 'Tagalog';
}
