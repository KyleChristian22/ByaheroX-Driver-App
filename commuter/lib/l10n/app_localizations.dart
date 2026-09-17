import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_fil.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('fil'),
  ];

  /// App name
  ///
  /// In en, this message translates to:
  /// **'ByaheroX'**
  String get appName;

  /// App tagline/slogan
  ///
  /// In en, this message translates to:
  /// **'Know where your jeepney is.'**
  String get appTagline;

  /// App description
  ///
  /// In en, this message translates to:
  /// **'Real-time jeepney tracking for Lucban–Luisiana–Sta. Cruz route'**
  String get appDescription;

  /// No description provided for @mainRoute.
  ///
  /// In en, this message translates to:
  /// **'Lucban - Luisiana - Sta. Cruz'**
  String get mainRoute;

  /// No description provided for @routeLucbanLuisiana.
  ///
  /// In en, this message translates to:
  /// **'Lucban - Luisiana'**
  String get routeLucbanLuisiana;

  /// No description provided for @routeLuisianaStaCruz.
  ///
  /// In en, this message translates to:
  /// **'Luisiana - Sta. Cruz'**
  String get routeLuisianaStaCruz;

  /// No description provided for @showAll.
  ///
  /// In en, this message translates to:
  /// **'Show All'**
  String get showAll;

  /// No description provided for @crowdNotCrowded.
  ///
  /// In en, this message translates to:
  /// **'Not Crowded'**
  String get crowdNotCrowded;

  /// No description provided for @crowdModerate.
  ///
  /// In en, this message translates to:
  /// **'Moderate'**
  String get crowdModerate;

  /// No description provided for @crowdFull.
  ///
  /// In en, this message translates to:
  /// **'Full'**
  String get crowdFull;

  /// No description provided for @crowdNotCrowdedDesc.
  ///
  /// In en, this message translates to:
  /// **'Seats available'**
  String get crowdNotCrowdedDesc;

  /// No description provided for @crowdModerateDesc.
  ///
  /// In en, this message translates to:
  /// **'Some passengers'**
  String get crowdModerateDesc;

  /// No description provided for @crowdFullDesc.
  ///
  /// In en, this message translates to:
  /// **'Full capacity'**
  String get crowdFullDesc;

  /// No description provided for @navMap.
  ///
  /// In en, this message translates to:
  /// **'Map'**
  String get navMap;

  /// No description provided for @navFavorites.
  ///
  /// In en, this message translates to:
  /// **'Favorites'**
  String get navFavorites;

  /// No description provided for @navProfile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get navProfile;

  /// No description provided for @login.
  ///
  /// In en, this message translates to:
  /// **'Login'**
  String get login;

  /// No description provided for @logout.
  ///
  /// In en, this message translates to:
  /// **'Logout'**
  String get logout;

  /// No description provided for @createAccount.
  ///
  /// In en, this message translates to:
  /// **'Create Account'**
  String get createAccount;

  /// No description provided for @continueAsGuest.
  ///
  /// In en, this message translates to:
  /// **'Continue as Guest'**
  String get continueAsGuest;

  /// No description provided for @signUp.
  ///
  /// In en, this message translates to:
  /// **'Sign Up'**
  String get signUp;

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @getNotifications.
  ///
  /// In en, this message translates to:
  /// **'Get Notifications'**
  String get getNotifications;

  /// No description provided for @viewOnMap.
  ///
  /// In en, this message translates to:
  /// **'View on Map'**
  String get viewOnMap;

  /// No description provided for @sendResetLink.
  ///
  /// In en, this message translates to:
  /// **'Send Reset Link'**
  String get sendResetLink;

  /// No description provided for @backToLogin.
  ///
  /// In en, this message translates to:
  /// **'Back to Login'**
  String get backToLogin;

  /// No description provided for @email.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get email;

  /// No description provided for @emailAddress.
  ///
  /// In en, this message translates to:
  /// **'Email Address'**
  String get emailAddress;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @confirmPassword.
  ///
  /// In en, this message translates to:
  /// **'Repeat Password'**
  String get confirmPassword;

  /// No description provided for @confirmPasswordHint.
  ///
  /// In en, this message translates to:
  /// **'Re-enter your password'**
  String get confirmPasswordHint;

  /// No description provided for @forgotPassword.
  ///
  /// In en, this message translates to:
  /// **'Forgot password?'**
  String get forgotPassword;

  /// No description provided for @displayName.
  ///
  /// In en, this message translates to:
  /// **'Display Name'**
  String get displayName;

  /// No description provided for @firstName.
  ///
  /// In en, this message translates to:
  /// **'First name'**
  String get firstName;

  /// No description provided for @lastName.
  ///
  /// In en, this message translates to:
  /// **'Last name'**
  String get lastName;

  /// No description provided for @middleName.
  ///
  /// In en, this message translates to:
  /// **'Middle name (Optional)'**
  String get middleName;

  /// No description provided for @phoneNumber.
  ///
  /// In en, this message translates to:
  /// **'Phone number'**
  String get phoneNumber;

  /// No description provided for @emailHint.
  ///
  /// In en, this message translates to:
  /// **'example@email.com'**
  String get emailHint;

  /// No description provided for @passwordHint.
  ///
  /// In en, this message translates to:
  /// **'••••••••'**
  String get passwordHint;

  /// No description provided for @displayNameHint.
  ///
  /// In en, this message translates to:
  /// **'Juan dela Cruz'**
  String get displayNameHint;

  /// No description provided for @firstNameHint.
  ///
  /// In en, this message translates to:
  /// **'Juan'**
  String get firstNameHint;

  /// No description provided for @lastNameHint.
  ///
  /// In en, this message translates to:
  /// **'Dela Cruz'**
  String get lastNameHint;

  /// No description provided for @middleNameHint.
  ///
  /// In en, this message translates to:
  /// **'Santos'**
  String get middleNameHint;

  /// No description provided for @phoneNumberHint.
  ///
  /// In en, this message translates to:
  /// **'09171234567'**
  String get phoneNumberHint;

  /// No description provided for @emailRequired.
  ///
  /// In en, this message translates to:
  /// **'Email is required'**
  String get emailRequired;

  /// No description provided for @emailInvalid.
  ///
  /// In en, this message translates to:
  /// **'Invalid email format'**
  String get emailInvalid;

  /// No description provided for @emailNoSpaces.
  ///
  /// In en, this message translates to:
  /// **'Email cannot contain spaces'**
  String get emailNoSpaces;

  /// No description provided for @emailMaxLength.
  ///
  /// In en, this message translates to:
  /// **'Email must be 254 characters or less'**
  String get emailMaxLength;

  /// No description provided for @passwordRequired.
  ///
  /// In en, this message translates to:
  /// **'Password is required'**
  String get passwordRequired;

  /// No description provided for @passwordMinLength.
  ///
  /// In en, this message translates to:
  /// **'Password must have at least 8 characters'**
  String get passwordMinLength;

  /// No description provided for @passwordMaxLength.
  ///
  /// In en, this message translates to:
  /// **'Password must be 128 characters or less'**
  String get passwordMaxLength;

  /// No description provided for @passwordNoLeadingTrailingSpaces.
  ///
  /// In en, this message translates to:
  /// **'Password cannot start or end with spaces'**
  String get passwordNoLeadingTrailingSpaces;

  /// No description provided for @passwordNeedsLetterAndNumber.
  ///
  /// In en, this message translates to:
  /// **'Password must contain both letters and numbers'**
  String get passwordNeedsLetterAndNumber;

  /// No description provided for @confirmPasswordRequired.
  ///
  /// In en, this message translates to:
  /// **'Please confirm your password'**
  String get confirmPasswordRequired;

  /// No description provided for @confirmPasswordMismatch.
  ///
  /// In en, this message translates to:
  /// **'Passwords do not match'**
  String get confirmPasswordMismatch;

  /// No description provided for @displayNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Display name is required'**
  String get displayNameRequired;

  /// No description provided for @displayNameMinLength.
  ///
  /// In en, this message translates to:
  /// **'Display name must have at least 2 characters'**
  String get displayNameMinLength;

  /// No description provided for @displayNameMaxLength.
  ///
  /// In en, this message translates to:
  /// **'Display name must have 50 characters or less'**
  String get displayNameMaxLength;

  /// No description provided for @firstNameRequired.
  ///
  /// In en, this message translates to:
  /// **'First name is required'**
  String get firstNameRequired;

  /// No description provided for @lastNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Last name is required'**
  String get lastNameRequired;

  /// No description provided for @nameMinLength.
  ///
  /// In en, this message translates to:
  /// **'Name must have at least 3 characters'**
  String get nameMinLength;

  /// No description provided for @nameMaxLength.
  ///
  /// In en, this message translates to:
  /// **'Name must have 50 characters or less'**
  String get nameMaxLength;

  /// No description provided for @nameInvalidChars.
  ///
  /// In en, this message translates to:
  /// **'Only letters, spaces, hyphens, and apostrophes allowed'**
  String get nameInvalidChars;

  /// No description provided for @nameMultipleSpaces.
  ///
  /// In en, this message translates to:
  /// **'Cannot have multiple spaces in a row'**
  String get nameMultipleSpaces;

  /// No description provided for @nameRepeatedLetters.
  ///
  /// In en, this message translates to:
  /// **'Cannot have 3 identical letters in a row'**
  String get nameRepeatedLetters;

  /// No description provided for @middleNameMaxLength.
  ///
  /// In en, this message translates to:
  /// **'Middle name must be 50 characters or less'**
  String get middleNameMaxLength;

  /// No description provided for @phoneNumberRequired.
  ///
  /// In en, this message translates to:
  /// **'Phone number is required'**
  String get phoneNumberRequired;

  /// No description provided for @phoneNumberInvalid.
  ///
  /// In en, this message translates to:
  /// **'Phone number must be 11 digits'**
  String get phoneNumberInvalid;

  /// No description provided for @phoneNumberPrefix.
  ///
  /// In en, this message translates to:
  /// **'Phone number must start with 09'**
  String get phoneNumberPrefix;

  /// No description provided for @phoneNumberRepeatedDigits.
  ///
  /// In en, this message translates to:
  /// **'Too many repeated digits in a row'**
  String get phoneNumberRepeatedDigits;

  /// No description provided for @errorInvalidEmail.
  ///
  /// In en, this message translates to:
  /// **'Invalid email format'**
  String get errorInvalidEmail;

  /// No description provided for @errorWrongPassword.
  ///
  /// In en, this message translates to:
  /// **'Incorrect password'**
  String get errorWrongPassword;

  /// No description provided for @errorUserNotFound.
  ///
  /// In en, this message translates to:
  /// **'No user found with this email'**
  String get errorUserNotFound;

  /// No description provided for @errorEmailInUse.
  ///
  /// In en, this message translates to:
  /// **'This email is already in use'**
  String get errorEmailInUse;

  /// No description provided for @errorWeakPassword.
  ///
  /// In en, this message translates to:
  /// **'Weak password. Please choose a stronger password'**
  String get errorWeakPassword;

  /// No description provided for @errorNetworkError.
  ///
  /// In en, this message translates to:
  /// **'Network error. Please check your connection'**
  String get errorNetworkError;

  /// No description provided for @errorUnknown.
  ///
  /// In en, this message translates to:
  /// **'An unknown error occurred. Please try again'**
  String get errorUnknown;

  /// No description provided for @errorLoginFailed.
  ///
  /// In en, this message translates to:
  /// **'Invalid email or password'**
  String get errorLoginFailed;

  /// No description provided for @errorInvalidCredential.
  ///
  /// In en, this message translates to:
  /// **'Invalid email or password'**
  String get errorInvalidCredential;

  /// No description provided for @errorUserDisabled.
  ///
  /// In en, this message translates to:
  /// **'This account has been disabled. Please contact support.'**
  String get errorUserDisabled;

  /// No description provided for @errorEmailNotVerified.
  ///
  /// In en, this message translates to:
  /// **'Please verify your email before logging in'**
  String get errorEmailNotVerified;

  /// No description provided for @errorRegistrationFailed.
  ///
  /// In en, this message translates to:
  /// **'Registration failed'**
  String get errorRegistrationFailed;

  /// No description provided for @errorTooManyRequests.
  ///
  /// In en, this message translates to:
  /// **'Too many attempts. Please try again later'**
  String get errorTooManyRequests;

  /// No description provided for @errorLoginTimeout.
  ///
  /// In en, this message translates to:
  /// **'Login timeout. Please try again'**
  String get errorLoginTimeout;

  /// No description provided for @welcomeTitle.
  ///
  /// In en, this message translates to:
  /// **'Welcome to ByaheroX!'**
  String get welcomeTitle;

  /// No description provided for @welcomeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Choose an option to get started'**
  String get welcomeSubtitle;

  /// No description provided for @loginTitle.
  ///
  /// In en, this message translates to:
  /// **'Welcome!'**
  String get loginTitle;

  /// No description provided for @loginSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Login for a better experience'**
  String get loginSubtitle;

  /// No description provided for @forgotPasswordTitle.
  ///
  /// In en, this message translates to:
  /// **'Forgot Password'**
  String get forgotPasswordTitle;

  /// No description provided for @forgotPasswordSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Enter your email to receive a password reset link'**
  String get forgotPasswordSubtitle;

  /// No description provided for @resetPasswordSuccess.
  ///
  /// In en, this message translates to:
  /// **'We have sent a password reset link to your email. Please check your inbox.'**
  String get resetPasswordSuccess;

  /// No description provided for @registerTitle.
  ///
  /// In en, this message translates to:
  /// **'Create Account'**
  String get registerTitle;

  /// No description provided for @registerSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Sign up for a better experience'**
  String get registerSubtitle;

  /// No description provided for @registrationSuccessful.
  ///
  /// In en, this message translates to:
  /// **'Registration successful! Please verify your email.'**
  String get registrationSuccessful;

  /// No description provided for @verifyEmailTitle.
  ///
  /// In en, this message translates to:
  /// **'Verify your email'**
  String get verifyEmailTitle;

  /// No description provided for @verifyEmailSubtitle.
  ///
  /// In en, this message translates to:
  /// **'An email verification was sent to your email.'**
  String get verifyEmailSubtitle;

  /// No description provided for @verifyEmailInstructions.
  ///
  /// In en, this message translates to:
  /// **'Open your inbox, tap the verification link, then return here to continue.'**
  String get verifyEmailInstructions;

  /// No description provided for @homeTitle.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get homeTitle;

  /// No description provided for @favoritesTitle.
  ///
  /// In en, this message translates to:
  /// **'Favorites'**
  String get favoritesTitle;

  /// No description provided for @jeepneyDetailsTitle.
  ///
  /// In en, this message translates to:
  /// **'Jeepney Details'**
  String get jeepneyDetailsTitle;

  /// No description provided for @noJeepneys.
  ///
  /// In en, this message translates to:
  /// **'No jeepneys on route'**
  String get noJeepneys;

  /// No description provided for @noFavorites.
  ///
  /// In en, this message translates to:
  /// **'No favorites yet'**
  String get noFavorites;

  /// No description provided for @noFavoritesDesc.
  ///
  /// In en, this message translates to:
  /// **'Save routes to access them easily'**
  String get noFavoritesDesc;

  /// No description provided for @loading.
  ///
  /// In en, this message translates to:
  /// **'Loading...'**
  String get loading;

  /// No description provided for @updating.
  ///
  /// In en, this message translates to:
  /// **'Updating...'**
  String get updating;

  /// No description provided for @errorGeneric.
  ///
  /// In en, this message translates to:
  /// **'An error occurred'**
  String get errorGeneric;

  /// No description provided for @errorNetwork.
  ///
  /// In en, this message translates to:
  /// **'No internet connection'**
  String get errorNetwork;

  /// No description provided for @errorLocation.
  ///
  /// In en, this message translates to:
  /// **'Cannot find location'**
  String get errorLocation;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Try Again'**
  String get retry;

  /// No description provided for @accountCreatedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Account created successfully!'**
  String get accountCreatedSuccess;

  /// No description provided for @verificationEmailSent.
  ///
  /// In en, this message translates to:
  /// **'Email verification sent. Please check your inbox or spam folder.'**
  String get verificationEmailSent;

  /// No description provided for @emailVerifiedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Email verified. Welcome to ByaheroX!'**
  String get emailVerifiedSuccess;

  /// No description provided for @emailNotVerified.
  ///
  /// In en, this message translates to:
  /// **'Email not verified yet. Please click the verification link first.'**
  String get emailNotVerified;

  /// No description provided for @verificationCheckFailed.
  ///
  /// In en, this message translates to:
  /// **'Cannot check verification status now. Please try again.'**
  String get verificationCheckFailed;

  /// No description provided for @noUserToVerify.
  ///
  /// In en, this message translates to:
  /// **'No account to verify. Please login again.'**
  String get noUserToVerify;

  /// No description provided for @checkVerification.
  ///
  /// In en, this message translates to:
  /// **'I have verified'**
  String get checkVerification;

  /// No description provided for @resendVerificationEmail.
  ///
  /// In en, this message translates to:
  /// **'Resend email'**
  String get resendVerificationEmail;

  /// No description provided for @live.
  ///
  /// In en, this message translates to:
  /// **'LIVE'**
  String get live;

  /// No description provided for @lastUpdated.
  ///
  /// In en, this message translates to:
  /// **'Last updated'**
  String get lastUpdated;

  /// No description provided for @secondsAgo.
  ///
  /// In en, this message translates to:
  /// **'seconds ago'**
  String get secondsAgo;

  /// No description provided for @plateNumber.
  ///
  /// In en, this message translates to:
  /// **'Plate Number'**
  String get plateNumber;

  /// No description provided for @route.
  ///
  /// In en, this message translates to:
  /// **'Route'**
  String get route;

  /// No description provided for @eta.
  ///
  /// In en, this message translates to:
  /// **'Estimated Time of Arrival (ETA)'**
  String get eta;

  /// No description provided for @speed.
  ///
  /// In en, this message translates to:
  /// **'Speed'**
  String get speed;

  /// No description provided for @kmh.
  ///
  /// In en, this message translates to:
  /// **'km/h'**
  String get kmh;

  /// No description provided for @minutes.
  ///
  /// In en, this message translates to:
  /// **'minutes'**
  String get minutes;

  /// No description provided for @arriving.
  ///
  /// In en, this message translates to:
  /// **'Arriving'**
  String get arriving;

  /// No description provided for @arrived.
  ///
  /// In en, this message translates to:
  /// **'Arrived'**
  String get arrived;

  /// No description provided for @savedRoutes.
  ///
  /// In en, this message translates to:
  /// **'Saved Routes'**
  String get savedRoutes;

  /// No description provided for @notifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notifications;

  /// No description provided for @enableNotifications.
  ///
  /// In en, this message translates to:
  /// **'Alert when a jeepney is nearby'**
  String get enableNotifications;

  /// No description provided for @guestMode.
  ///
  /// In en, this message translates to:
  /// **'Browsing as Guest'**
  String get guestMode;

  /// No description provided for @guestModeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Login for full features'**
  String get guestModeSubtitle;

  /// No description provided for @now.
  ///
  /// In en, this message translates to:
  /// **'Now'**
  String get now;

  /// No description provided for @arrivingNow.
  ///
  /// In en, this message translates to:
  /// **'Arriving now'**
  String get arrivingNow;

  /// No description provided for @arrivingSoon.
  ///
  /// In en, this message translates to:
  /// **'Arriving soon'**
  String get arrivingSoon;

  /// No description provided for @proceedToPickup.
  ///
  /// In en, this message translates to:
  /// **'Please proceed to your pickup area.'**
  String get proceedToPickup;

  /// No description provided for @away.
  ///
  /// In en, this message translates to:
  /// **'away'**
  String get away;

  /// No description provided for @selectLocation.
  ///
  /// In en, this message translates to:
  /// **'Select Location'**
  String get selectLocation;

  /// No description provided for @pinPickupLocation.
  ///
  /// In en, this message translates to:
  /// **'Pin Pickup Location'**
  String get pinPickupLocation;

  /// No description provided for @showMyLocation.
  ///
  /// In en, this message translates to:
  /// **'Show My Location'**
  String get showMyLocation;

  /// No description provided for @showWaitingLocation.
  ///
  /// In en, this message translates to:
  /// **'Show Waiting Location'**
  String get showWaitingLocation;

  /// No description provided for @loginToPinLocation.
  ///
  /// In en, this message translates to:
  /// **'Login to pin pickup location'**
  String get loginToPinLocation;

  /// No description provided for @useCurrentGpsLocation.
  ///
  /// In en, this message translates to:
  /// **'Use Current GPS Location'**
  String get useCurrentGpsLocation;

  /// No description provided for @chooseOnMap.
  ///
  /// In en, this message translates to:
  /// **'Choose on Map'**
  String get chooseOnMap;

  /// No description provided for @pickupLocationPinned.
  ///
  /// In en, this message translates to:
  /// **'Pickup location pinned!'**
  String get pickupLocationPinned;

  /// No description provided for @waitingAtLocation.
  ///
  /// In en, this message translates to:
  /// **'Waiting at location'**
  String get waitingAtLocation;

  /// No description provided for @tapToSetLocation.
  ///
  /// In en, this message translates to:
  /// **'Tap to set location'**
  String get tapToSetLocation;

  /// No description provided for @shareLocation.
  ///
  /// In en, this message translates to:
  /// **'Share Location'**
  String get shareLocation;

  /// No description provided for @unshareMyLocation.
  ///
  /// In en, this message translates to:
  /// **'Unshare my Location'**
  String get unshareMyLocation;

  /// No description provided for @stopSharingLocation.
  ///
  /// In en, this message translates to:
  /// **'Stop Sharing'**
  String get stopSharingLocation;

  /// No description provided for @locationSharingStopped.
  ///
  /// In en, this message translates to:
  /// **'Your location is no longer visible to the driver.'**
  String get locationSharingStopped;

  /// No description provided for @locationSharingStopFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to stop location sharing. Please try again.'**
  String get locationSharingStopFailed;

  /// No description provided for @cannotShareNoDriverOnTrip.
  ///
  /// In en, this message translates to:
  /// **'No driver currently on trip. Location cannot be shared at this time.'**
  String get cannotShareNoDriverOnTrip;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @languageTagalog.
  ///
  /// In en, this message translates to:
  /// **'Tagalog'**
  String get languageTagalog;

  /// No description provided for @quickActions.
  ///
  /// In en, this message translates to:
  /// **'Quick Actions'**
  String get quickActions;

  /// No description provided for @liveJeepneys.
  ///
  /// In en, this message translates to:
  /// **'Live Jeepneys'**
  String get liveJeepneys;

  /// No description provided for @activeDrivers.
  ///
  /// In en, this message translates to:
  /// **'Active Drivers'**
  String get activeDrivers;

  /// No description provided for @totalJeepneys.
  ///
  /// In en, this message translates to:
  /// **'Total Jeepneys'**
  String get totalJeepneys;

  /// No description provided for @goodMorning.
  ///
  /// In en, this message translates to:
  /// **'Good morning!'**
  String get goodMorning;

  /// No description provided for @goodAfternoon.
  ///
  /// In en, this message translates to:
  /// **'Good afternoon!'**
  String get goodAfternoon;

  /// No description provided for @goodEvening.
  ///
  /// In en, this message translates to:
  /// **'Good evening!'**
  String get goodEvening;

  /// No description provided for @alreadyHaveAccount.
  ///
  /// In en, this message translates to:
  /// **'Already have an account?'**
  String get alreadyHaveAccount;

  /// No description provided for @noAccount.
  ///
  /// In en, this message translates to:
  /// **'Don\'t have an account?'**
  String get noAccount;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'fil'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'fil':
      return AppLocalizationsFil();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
