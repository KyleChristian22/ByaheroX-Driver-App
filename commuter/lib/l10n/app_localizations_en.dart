// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'ByaheroX';

  @override
  String get appTagline => 'Know where your jeepney is.';

  @override
  String get appDescription =>
      'Real-time jeepney tracking for Lucban–Luisiana–Sta. Cruz route';

  @override
  String get mainRoute => 'Lucban - Luisiana - Sta. Cruz';

  @override
  String get routeLucbanLuisiana => 'Lucban - Luisiana';

  @override
  String get routeLuisianaStaCruz => 'Luisiana - Sta. Cruz';

  @override
  String get showAll => 'Show All';

  @override
  String get crowdNotCrowded => 'Not Crowded';

  @override
  String get crowdModerate => 'Moderate';

  @override
  String get crowdFull => 'Full';

  @override
  String get crowdNotCrowdedDesc => 'Seats available';

  @override
  String get crowdModerateDesc => 'Some passengers';

  @override
  String get crowdFullDesc => 'Full capacity';

  @override
  String get navMap => 'Map';

  @override
  String get navFavorites => 'Favorites';

  @override
  String get navProfile => 'Profile';

  @override
  String get login => 'Login';

  @override
  String get logout => 'Logout';

  @override
  String get createAccount => 'Create Account';

  @override
  String get continueAsGuest => 'Continue as Guest';

  @override
  String get signUp => 'Sign Up';

  @override
  String get refresh => 'Refresh';

  @override
  String get save => 'Save';

  @override
  String get cancel => 'Cancel';

  @override
  String get delete => 'Delete';

  @override
  String get edit => 'Edit';

  @override
  String get done => 'Done';

  @override
  String get close => 'Close';

  @override
  String get back => 'Back';

  @override
  String get getNotifications => 'Get Notifications';

  @override
  String get viewOnMap => 'View on Map';

  @override
  String get sendResetLink => 'Send Reset Link';

  @override
  String get backToLogin => 'Back to Login';

  @override
  String get email => 'Email';

  @override
  String get emailAddress => 'Email Address';

  @override
  String get password => 'Password';

  @override
  String get confirmPassword => 'Repeat Password';

  @override
  String get confirmPasswordHint => 'Re-enter your password';

  @override
  String get forgotPassword => 'Forgot password?';

  @override
  String get displayName => 'Display Name';

  @override
  String get firstName => 'First name';

  @override
  String get lastName => 'Last name';

  @override
  String get middleName => 'Middle name (Optional)';

  @override
  String get phoneNumber => 'Phone number';

  @override
  String get emailHint => 'example@email.com';

  @override
  String get passwordHint => '••••••••';

  @override
  String get displayNameHint => 'Juan dela Cruz';

  @override
  String get firstNameHint => 'Juan';

  @override
  String get lastNameHint => 'Dela Cruz';

  @override
  String get middleNameHint => 'Santos';

  @override
  String get phoneNumberHint => '09171234567';

  @override
  String get emailRequired => 'Email is required';

  @override
  String get emailInvalid => 'Invalid email format';

  @override
  String get emailNoSpaces => 'Email cannot contain spaces';

  @override
  String get emailMaxLength => 'Email must be 254 characters or less';

  @override
  String get passwordRequired => 'Password is required';

  @override
  String get passwordMinLength => 'Password must have at least 8 characters';

  @override
  String get passwordMaxLength => 'Password must be 128 characters or less';

  @override
  String get passwordNoLeadingTrailingSpaces =>
      'Password cannot start or end with spaces';

  @override
  String get passwordNeedsLetterAndNumber =>
      'Password must contain both letters and numbers';

  @override
  String get confirmPasswordRequired => 'Please confirm your password';

  @override
  String get confirmPasswordMismatch => 'Passwords do not match';

  @override
  String get displayNameRequired => 'Display name is required';

  @override
  String get displayNameMinLength =>
      'Display name must have at least 2 characters';

  @override
  String get displayNameMaxLength =>
      'Display name must have 50 characters or less';

  @override
  String get firstNameRequired => 'First name is required';

  @override
  String get lastNameRequired => 'Last name is required';

  @override
  String get nameMinLength => 'Name must have at least 3 characters';

  @override
  String get nameMaxLength => 'Name must have 50 characters or less';

  @override
  String get nameInvalidChars =>
      'Only letters, spaces, hyphens, and apostrophes allowed';

  @override
  String get nameMultipleSpaces => 'Cannot have multiple spaces in a row';

  @override
  String get nameRepeatedLetters => 'Cannot have 3 identical letters in a row';

  @override
  String get middleNameMaxLength => 'Middle name must be 50 characters or less';

  @override
  String get phoneNumberRequired => 'Phone number is required';

  @override
  String get phoneNumberInvalid => 'Phone number must be 11 digits';

  @override
  String get phoneNumberPrefix => 'Phone number must start with 09';

  @override
  String get phoneNumberRepeatedDigits => 'Too many repeated digits in a row';

  @override
  String get errorInvalidEmail => 'Invalid email format';

  @override
  String get errorWrongPassword => 'Incorrect password';

  @override
  String get errorUserNotFound => 'No user found with this email';

  @override
  String get errorEmailInUse => 'This email is already in use';

  @override
  String get errorWeakPassword =>
      'Weak password. Please choose a stronger password';

  @override
  String get errorNetworkError => 'Network error. Please check your connection';

  @override
  String get errorUnknown => 'An unknown error occurred. Please try again';

  @override
  String get errorLoginFailed => 'Invalid email or password';

  @override
  String get errorInvalidCredential => 'Invalid email or password';

  @override
  String get errorUserDisabled =>
      'This account has been disabled. Please contact support.';

  @override
  String get errorEmailNotVerified =>
      'Please verify your email before logging in';

  @override
  String get errorRegistrationFailed => 'Registration failed';

  @override
  String get errorTooManyRequests =>
      'Too many attempts. Please try again later';

  @override
  String get errorLoginTimeout => 'Login timeout. Please try again';

  @override
  String get welcomeTitle => 'Welcome to ByaheroX!';

  @override
  String get welcomeSubtitle => 'Choose an option to get started';

  @override
  String get loginTitle => 'Welcome!';

  @override
  String get loginSubtitle => 'Login for a better experience';

  @override
  String get forgotPasswordTitle => 'Forgot Password';

  @override
  String get forgotPasswordSubtitle =>
      'Enter your email to receive a password reset link';

  @override
  String get resetPasswordSuccess =>
      'We have sent a password reset link to your email. Please check your inbox.';

  @override
  String get registerTitle => 'Create Account';

  @override
  String get registerSubtitle => 'Sign up for a better experience';

  @override
  String get registrationSuccessful =>
      'Registration successful! Please verify your email.';

  @override
  String get verifyEmailTitle => 'Verify your email';

  @override
  String get verifyEmailSubtitle =>
      'An email verification was sent to your email.';

  @override
  String get verifyEmailInstructions =>
      'Open your inbox, tap the verification link, then return here to continue.';

  @override
  String get homeTitle => 'Home';

  @override
  String get favoritesTitle => 'Favorites';

  @override
  String get jeepneyDetailsTitle => 'Jeepney Details';

  @override
  String get noJeepneys => 'No jeepneys on route';

  @override
  String get noFavorites => 'No favorites yet';

  @override
  String get noFavoritesDesc => 'Save routes to access them easily';

  @override
  String get loading => 'Loading...';

  @override
  String get updating => 'Updating...';

  @override
  String get errorGeneric => 'An error occurred';

  @override
  String get errorNetwork => 'No internet connection';

  @override
  String get errorLocation => 'Cannot find location';

  @override
  String get retry => 'Try Again';

  @override
  String get accountCreatedSuccess => 'Account created successfully!';

  @override
  String get verificationEmailSent =>
      'Email verification sent. Please check your inbox or spam folder.';

  @override
  String get emailVerifiedSuccess => 'Email verified. Welcome to ByaheroX!';

  @override
  String get emailNotVerified =>
      'Email not verified yet. Please click the verification link first.';

  @override
  String get verificationCheckFailed =>
      'Cannot check verification status now. Please try again.';

  @override
  String get noUserToVerify => 'No account to verify. Please login again.';

  @override
  String get checkVerification => 'I have verified';

  @override
  String get resendVerificationEmail => 'Resend email';

  @override
  String get live => 'LIVE';

  @override
  String get lastUpdated => 'Last updated';

  @override
  String get secondsAgo => 'seconds ago';

  @override
  String get plateNumber => 'Plate Number';

  @override
  String get route => 'Route';

  @override
  String get eta => 'Estimated Time of Arrival (ETA)';

  @override
  String get speed => 'Speed';

  @override
  String get kmh => 'km/h';

  @override
  String get minutes => 'minutes';

  @override
  String get arriving => 'Arriving';

  @override
  String get arrived => 'Arrived';

  @override
  String get savedRoutes => 'Saved Routes';

  @override
  String get notifications => 'Notifications';

  @override
  String get enableNotifications => 'Alert when a jeepney is nearby';

  @override
  String get guestMode => 'Browsing as Guest';

  @override
  String get guestModeSubtitle => 'Login for full features';

  @override
  String get now => 'Now';

  @override
  String get arrivingNow => 'Arriving now';

  @override
  String get arrivingSoon => 'Arriving soon';

  @override
  String get proceedToPickup => 'Please proceed to your pickup area.';

  @override
  String get away => 'away';

  @override
  String get selectLocation => 'Select Location';

  @override
  String get pinPickupLocation => 'Pin Pickup Location';

  @override
  String get showMyLocation => 'Show My Location';

  @override
  String get showWaitingLocation => 'Show Waiting Location';

  @override
  String get loginToPinLocation => 'Login to pin pickup location';

  @override
  String get useCurrentGpsLocation => 'Use Current GPS Location';

  @override
  String get chooseOnMap => 'Choose on Map';

  @override
  String get pickupLocationPinned => 'Pickup location pinned!';

  @override
  String get waitingAtLocation => 'Waiting at location';

  @override
  String get tapToSetLocation => 'Tap to set location';

  @override
  String get shareLocation => 'Share Location';

  @override
  String get unshareMyLocation => 'Unshare my Location';

  @override
  String get stopSharingLocation => 'Stop Sharing';

  @override
  String get locationSharingStopped =>
      'Your location is no longer visible to the driver.';

  @override
  String get locationSharingStopFailed =>
      'Failed to stop location sharing. Please try again.';

  @override
  String get cannotShareNoDriverOnTrip =>
      'No driver currently on trip. Location cannot be shared at this time.';

  @override
  String get language => 'Language';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageTagalog => 'Tagalog';

  @override
  String get quickActions => 'Quick Actions';

  @override
  String get liveJeepneys => 'Live Jeepneys';

  @override
  String get activeDrivers => 'Active Drivers';

  @override
  String get totalJeepneys => 'Total Jeepneys';

  @override
  String get goodMorning => 'Good morning!';

  @override
  String get goodAfternoon => 'Good afternoon!';

  @override
  String get goodEvening => 'Good evening!';

  @override
  String get alreadyHaveAccount => 'Already have an account?';

  @override
  String get noAccount => 'Don\'t have an account?';
}
