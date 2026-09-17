/// App strings for ByaheroX
/// All text content used throughout the application
class AppStrings {
  AppStrings._();

  // App Info
  static const String appName = 'ByaheroX';
  static const String appTagline = 'Know where your jeepney is.';
  static const String appDescription =
      'Real-time jeepney tracking for Lucban–Luisiana–Sta. Cruz route';

  // Routes
  static const String mainRoute = 'Lucban - Luisiana - Sta. Cruz';
  static const String routeLucbanLuisiana = 'Lucban - Luisiana';
  static const String routeLuisianaStaCruz = 'Luisiana - Sta. Cruz';
  static const String showAll = 'Show All';

  // Crowd Levels
  static const String crowdMaliwag = 'Not Crowded';
  static const String crowdSakto = 'Moderate';
  static const String crowdPuno = 'Full';

  // Crowd Level Descriptions
  static const String crowdMaliwagDesc = 'Seats available';
  static const String crowdSaktoDesc = 'Some passengers';
  static const String crowdPunoDesc = 'Full capacity';

  // Navigation
  static const String navMap = 'Map';
  static const String navFavorites = ' Favorites';
  static const String navProfile = 'Profile';

  // Actions
  static const String login = 'Login';
  static const String logout = 'Logout';
  static const String createAccount = 'Create Account';
  static const String continueAsGuest = 'Continue as Guest';
  static const String signUp = 'Sign Up';
  static const String refresh = 'Refresh';
  static const String save = 'Save';
  static const String cancel = 'Cancel';
  static const String delete = 'Delete';
  static const String edit = 'Edit';
  static const String done = 'Done';
  static const String close = 'Close';
  static const String back = 'Back';
  static const String getNotifications = 'Get Notifications';
  static const String viewOnMap = 'View on Map';
  static const String sendResetLink = 'Send Reset Link';
  static const String backToLogin = 'Back to Login';

  // Form Labels
  static const String email = 'Email';
  static const String emailAddress = 'Email Address';
  static const String password = 'Password';
  static const String confirmPassword = 'Repeat Password';
  static const String forgotPassword = 'Forgot password?';
  static const String displayName = 'Display Name';
  static const String firstName = 'First name';
  static const String lastName = 'Last name';
  static const String middleName = 'Middle name (Optional)';
  static const String phoneNumber = 'Phone number';

  // Form Hints
  static const String emailHint = 'example@email.com';
  static const String passwordHint = '••••••••';
  static const String displayNameHint = 'Juan dela Cruz';
  static const String firstNameHint = 'Juan';
  static const String lastNameHint = 'Dela Cruz';
  static const String middleNameHint = 'Santos';
  static const String phoneNumberHint = '09171234567';

  // Validation Messages
  static const String emailRequired = 'Email is required';
  static const String emailInvalid = 'Invalid email format';
  static const String passwordRequired = 'Password is required';
  static const String passwordMinLength =
      'Password must have at least 8 characters';
  static const String confirmPasswordRequired = 'Please confirm your password';
  static const String confirmPasswordMismatch = 'Passwords do not match';
  static const String displayNameRequired = 'Display name is required';
  static const String displayNameMinLength =
      'Display name must have at least 2 characters';
  static const String displayNameMaxLength =
      'Display name must have 50 characters or less';
  static const String firstNameRequired = 'First name is required';
  static const String firstNameMinLength =
      'First name must have at least 3 characters';
  static const String firstNameMaxLength =
      'First name must have 50 characters or less';
  static const String lastNameRequired = 'Last name is required';
  static const String lastNameMinLength =
      'Last name must have at least 3 characters';
  static const String lastNameMaxLength =
      'Last name must have 50 characters or less';
  static const String middleNameMaxLength =
      'Middle name must be 50 characters or less';
  static const String phoneNumberRequired = 'Phone number is required';
  static const String phoneNumberInvalid = 'Phone number must be 11 digits';
  static const String phoneNumberPrefix = 'Phone number must start with 09';
  static const String phoneNumberRepeatedDigits =
      'Too many repeated digits in a row';

  // Name Validation Messages
  static const String nameMinLength = 'Name must have at least 3 characters';
  static const String nameMaxLength = 'Name must have 50 characters or less';
  static const String nameInvalidChars =
      'Only letters, spaces, hyphens, and apostrophes allowed';
  static const String nameMultipleSpaces =
      'Cannot have multiple spaces in a row';
  static const String nameRepeatedLetters =
      'Cannot have 3 identical letters in a row';

  // Email Validation Messages
  static const String emailMaxLength = 'Email must be 254 characters or less';
  static const String emailNoSpaces = 'Email cannot contain spaces';

  // Password Validation Messages
  static const String passwordMaxLength =
      'Password must be 128 characters or less';
  static const String passwordNoLeadingTrailingSpaces =
      'Password cannot start or end with spaces';
  static const String passwordNeedsLetterAndNumber =
      'Password must contain both letters and numbers';
  static const String passwordNeedsUpperLowerSpecial =
      'Password must include uppercase, lowercase, and a special character';

  // Auth Error Messages
  static const String errorInvalidEmail = 'Invalid email format';
  static const String errorWrongPassword = 'Incorrect password';
  static const String errorUserNotFound = 'No user found with this email';
  static const String errorEmailInUse = 'This email is already in use';
  static const String errorWeakPassword =
      'Weak password. Please choose a stronger password';
  static const String errorNetworkError =
      'Network error. Please check your connection';
  static const String errorUnknown =
      'An unknown error occurred. Please try again';
  static const String errorLoginFailed = 'Invalid email or password';
  static const String errorInvalidCredential = 'Invalid email or password';
  static const String errorUserDisabled =
      'This account has been disabled. Please contact support.';
  static const String errorEmailNotVerified =
      'Please verify your email before logging in';
  static const String errorRegistrationFailed = 'Registration failed';
  static const String errorTooManyRequests =
      'Too many attempts. Please try again later';
  static const String errorLoginTimeout = 'Login timeout. Please try again';
  static const String errorPasswordChangeRequiresReset =
      'This temporary login was not completed. Please use Forgot password to set a new password.';

  // Screen Titles
  static const String splashTitle = '';
  static const String welcomeTitle = 'Welcome to ByaheroX!';
  static const String welcomeSubtitle = 'Choose an option to get started';
  static const String loginTitle = 'Welcome!';
  static const String loginSubtitle = 'Login for a better experience';
  static const String forgotPasswordTitle = 'Forgot Password';
  static const String forgotPasswordSubtitle =
      'Enter your email to receive a password reset link';
  static const String resetPasswordSuccess =
      'We have sent a password reset link to your email. Please check your inbox.';
  static const String registerTitle = 'Create Account';
  static const String registerSubtitle = 'Sign up for a better experience';
  static const String verifyEmailTitle = 'Verify your email';
  static const String verifyEmailSubtitle =
      'An email verification was sent to your email.';
  static const String verifyEmailInstructions =
      'Open your inbox, tap the verification link, then return here to continue.';
  static const String changePasswordTitle = 'Create a new password';
  static const String changePasswordSubtitle =
      'Replace your temporary password before using the commuter dashboard.';
  static const String newPassword = 'New password';
  static const String repeatNewPassword = 'Repeat new password';
  static const String updatePassword = 'Update password';
  static const String passwordUpdatedSuccess =
      'Password updated. Welcome to ByaheroX!';
  static const String homeTitle = 'Jeepneys';
  static const String favoritesTitle = 'Favorites';
  static const String jeepneyDetailsTitle = 'Jeepney Details';

  // Empty States
  static const String noJeepneys = 'No jeepneys on route';
  static const String noFavorites = 'No favorites yet';
  static const String noFavoritesDesc = 'Save routes to access them easily';

  // Loading States
  static const String loading = 'Loading...';
  static const String updating = 'Updating...';

  // Error States
  static const String errorGeneric = 'An error occurred';
  static const String errorNetwork = 'No internet connection';
  static const String errorLocation = 'Cannot find location';
  static const String retry = 'Try Again';

  // Success Messages
  static const String accountCreatedSuccess = 'Account created successfully!';
  static const String verificationEmailSent =
      'Email verification sent. Please check your inbox or spam folder.';
  static const String emailVerifiedSuccess =
      'Email verified. Welcome to ByaheroX!';
  static const String emailNotVerified =
      'Email not verified yet. Please click the verification link first.';
  static const String verificationCheckFailed =
      'Cannot check verification status now. Please try again.';
  static const String noUserToVerify =
      'No account to verify. Please login again.';
  static const String checkVerification = 'I have verified';
  static const String resendVerificationEmail = 'Resend email';

  // Live Indicator
  static const String live = 'LIVE';
  static const String lastUpdated = 'Last updated';
  static const String secondsAgo = 'seconds ago';

  // Jeepney Info
  static const String plateNumber = 'Plate Number';
  static const String route = 'Route';
  static const String eta = 'Estimated Time of Arrival (ETA)';
  static const String speed = 'Speed';
  static const String kmh = 'km/h';
  static const String minutes = 'minutes';
  static const String arriving = 'Arriving';
  static const String arrived = 'Arrived';

  // Favorites
  static const String savedRoutes = 'Saved Routes';
  static const String notifications = 'Notifications';
  static const String enableNotifications = 'Alert when a jeepney is nearby';

  // Guest Mode
  static const String guestMode = 'Browsing as Guest';
  static const String guestModeSubtitle = 'Login for full features';

  // Time
  static const String now = 'Now';
  static const String arrivingNow = 'Arriving now';
  static const String arrivingSoon = 'Arriving soon';
  static const String proceedToPickup = 'Please proceed to your pickup area.';
  static const String away = 'away';

  // Pickup Location
  static const String selectLocation = 'Select Location';
  static const String pinPickupLocation = 'Pin Pickup Location';
  static const String showMyLocation = 'Show My Location';
  static const String showWaitingLocation = 'Show Waiting Location';
  static const String loginToPinLocation = 'Login to pin pickup location';
  static const String useCurrentGpsLocation = 'Use Current GPS Location';
  static const String chooseOnMap = 'Choose on Map';
  static const String pickupLocationPinned = 'Pickup location pinned!';
  static const String waitingAtLocation = 'Waiting at location';
  static const String tapToSetLocation = 'Tap to set location';

  /// Pickup / location sharing
  static const String shareLocation = 'Share Location';
  static const String unshareMyLocation = 'Unshare my Location';
  static const String stopSharingLocation = 'Stop Sharing';
  static const String locationSharingStopped =
      'Your location is no longer visible to the driver.';
  static const String locationSharingStopFailed =
      'Failed to stop location sharing. Please try again.';
  static const String cannotShareNoDriverOnTrip =
      'No driver currently on trip. Location cannot be shared at this time.';
}
