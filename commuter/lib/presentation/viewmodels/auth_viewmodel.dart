import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter/foundation.dart';
import '../../domain/entities/user.dart';
import '../../domain/repositories/auth_exception.dart';
import '../../data/repositories/auth_repository_impl.dart';
import '../../core/constants/app_strings.dart';

/// Validation result class
class ValidationResult {
  final bool isValid;
  final String? errorMessage;

  const ValidationResult({required this.isValid, this.errorMessage});

  static const ValidationResult valid = ValidationResult(isValid: true);
}

/// Input validator for auth forms
class AuthValidator {
  AuthValidator._();

  static final _emailRegex = RegExp(
    r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
  );
  static final _phoneRegex = RegExp(r'^[0-9]{11}$');
  static final _nameValidCharsRegex = RegExp(r"^[a-zA-Z\s'-]+$");
  static final _multipleSpacesRegex = RegExp(r'\s{2,}');
  static final _repeatedLettersRegex = RegExp(r'([a-zA-Z])\1{2,}');
  static final _repeatedDigitsRegex = RegExp(r'(\d)\1{3,}');

  static ValidationResult validateEmail(String? email) {
    if (email == null || email.trim().isEmpty) {
      return const ValidationResult(
        isValid: false,
        errorMessage: AppStrings.emailRequired,
      );
    }
    final trimmedEmail = email.trim();
    // Check for spaces in email
    if (trimmedEmail.contains(' ')) {
      return const ValidationResult(
        isValid: false,
        errorMessage: AppStrings.emailNoSpaces,
      );
    }
    // Check max length (RFC 5321)
    if (trimmedEmail.length > 254) {
      return const ValidationResult(
        isValid: false,
        errorMessage: AppStrings.emailMaxLength,
      );
    }
    if (!_emailRegex.hasMatch(trimmedEmail)) {
      return const ValidationResult(
        isValid: false,
        errorMessage: AppStrings.emailInvalid,
      );
    }
    return ValidationResult.valid;
  }

  static ValidationResult validatePassword(String? password) {
    if (password == null || password.isEmpty) {
      return const ValidationResult(
        isValid: false,
        errorMessage: AppStrings.passwordRequired,
      );
    }
    // Check for leading/trailing spaces
    if (password != password.trim()) {
      return const ValidationResult(
        isValid: false,
        errorMessage: AppStrings.passwordNoLeadingTrailingSpaces,
      );
    }
    if (password.length < 8) {
      return const ValidationResult(
        isValid: false,
        errorMessage: AppStrings.passwordMinLength,
      );
    }
    if (password.length > 128) {
      return const ValidationResult(
        isValid: false,
        errorMessage: AppStrings.passwordMaxLength,
      );
    }
    // Check for both letters and numbers
    final hasLetter = RegExp(r'[a-zA-Z]').hasMatch(password);
    final hasNumber = RegExp(r'[0-9]').hasMatch(password);
    if (!hasLetter || !hasNumber) {
      return const ValidationResult(
        isValid: false,
        errorMessage: AppStrings.passwordNeedsLetterAndNumber,
      );
    }
    return ValidationResult.valid;
  }

  static ValidationResult validateRequiredNewPassword(String? password) {
    if (password == null || password.isEmpty) {
      return const ValidationResult(
        isValid: false,
        errorMessage: AppStrings.passwordRequired,
      );
    }
    if (password != password.trim()) {
      return const ValidationResult(
        isValid: false,
        errorMessage: AppStrings.passwordNoLeadingTrailingSpaces,
      );
    }
    if (password.length < 8) {
      return const ValidationResult(
        isValid: false,
        errorMessage: AppStrings.passwordMinLength,
      );
    }
    if (password.length > 128) {
      return const ValidationResult(
        isValid: false,
        errorMessage: AppStrings.passwordMaxLength,
      );
    }
    if (!RegExp(r'[A-Z]').hasMatch(password) ||
        !RegExp(r'[a-z]').hasMatch(password) ||
        !RegExp(r'[^A-Za-z0-9]').hasMatch(password)) {
      return const ValidationResult(
        isValid: false,
        errorMessage: AppStrings.passwordNeedsUpperLowerSpecial,
      );
    }
    return ValidationResult.valid;
  }

  static ValidationResult validateDisplayName(String? displayName) {
    if (displayName == null || displayName.trim().isEmpty) {
      return const ValidationResult(
        isValid: false,
        errorMessage: AppStrings.displayNameRequired,
      );
    }
    if (displayName.trim().length < 2) {
      return const ValidationResult(
        isValid: false,
        errorMessage: AppStrings.displayNameMinLength,
      );
    }
    if (displayName.trim().length > 50) {
      return const ValidationResult(
        isValid: false,
        errorMessage: AppStrings.displayNameMaxLength,
      );
    }
    return ValidationResult.valid;
  }

  static ValidationResult validateFirstName(String? firstName) {
    final value = firstName?.trim() ?? '';
    if (value.isEmpty) {
      return const ValidationResult(
        isValid: false,
        errorMessage: AppStrings.firstNameRequired,
      );
    }
    return _validateName(value, AppStrings.firstNameRequired);
  }

  static ValidationResult validateLastName(String? lastName) {
    final value = lastName?.trim() ?? '';
    if (value.isEmpty) {
      return const ValidationResult(
        isValid: false,
        errorMessage: AppStrings.lastNameRequired,
      );
    }
    return _validateName(value, AppStrings.lastNameRequired);
  }

  static ValidationResult validateMiddleName(String? middleName) {
    final value = middleName?.trim() ?? '';
    // Middle name is optional, only validate if provided
    if (value.isEmpty) {
      return ValidationResult.valid;
    }
    return _validateName(value, null);
  }

  /// Common name validation helper
  static ValidationResult _validateName(String value, String? requiredMessage) {
    // Min length: 3 characters
    if (value.length < 3) {
      return const ValidationResult(
        isValid: false,
        errorMessage: AppStrings.nameMinLength,
      );
    }
    // Max length: 50 characters
    if (value.length > 50) {
      return const ValidationResult(
        isValid: false,
        errorMessage: AppStrings.nameMaxLength,
      );
    }
    // Letters, spaces, hyphens, apostrophes only
    if (!_nameValidCharsRegex.hasMatch(value)) {
      return const ValidationResult(
        isValid: false,
        errorMessage: AppStrings.nameInvalidChars,
      );
    }
    // No multiple spaces in a row
    if (_multipleSpacesRegex.hasMatch(value)) {
      return const ValidationResult(
        isValid: false,
        errorMessage: AppStrings.nameMultipleSpaces,
      );
    }
    // No 3+ identical letters in a row
    if (_repeatedLettersRegex.hasMatch(value)) {
      return const ValidationResult(
        isValid: false,
        errorMessage: AppStrings.nameRepeatedLetters,
      );
    }
    return ValidationResult.valid;
  }

  static ValidationResult validatePhoneNumber(String? phoneNumber) {
    final normalizedPhoneNumber = normalizePhoneNumber(phoneNumber ?? '');
    if (normalizedPhoneNumber.isEmpty) {
      return const ValidationResult(
        isValid: false,
        errorMessage: AppStrings.phoneNumberRequired,
      );
    }
    if (!_phoneRegex.hasMatch(normalizedPhoneNumber)) {
      return const ValidationResult(
        isValid: false,
        errorMessage: AppStrings.phoneNumberInvalid,
      );
    }
    // Must start with '09' (Philippine mobile format)
    if (!normalizedPhoneNumber.startsWith('09')) {
      return const ValidationResult(
        isValid: false,
        errorMessage: AppStrings.phoneNumberPrefix,
      );
    }
    // No 4+ identical digits in a row
    if (_repeatedDigitsRegex.hasMatch(normalizedPhoneNumber)) {
      return const ValidationResult(
        isValid: false,
        errorMessage: AppStrings.phoneNumberRepeatedDigits,
      );
    }
    return ValidationResult.valid;
  }

  static String normalizePhoneNumber(String phoneNumber) {
    return phoneNumber.trim().replaceAll(RegExp(r'[\s\-()]'), '');
  }

  static ValidationResult validateConfirmPassword(
    String? password,
    String? confirmPassword,
  ) {
    if (confirmPassword == null || confirmPassword.isEmpty) {
      return const ValidationResult(
        isValid: false,
        errorMessage: AppStrings.confirmPasswordRequired,
      );
    }
    if (password != confirmPassword) {
      return const ValidationResult(
        isValid: false,
        errorMessage: AppStrings.confirmPasswordMismatch,
      );
    }
    return ValidationResult.valid;
  }
}

/// ViewModel for authentication state management
class AuthViewModel extends ChangeNotifier {
  final AuthRepositoryImpl _authRepository;
  final bool _ownsAuthRepository;
  late final StreamSubscription<User?> _authStateSubscription;

  User _currentUser = User.guest();
  bool _isLoading = false;
  String? _error;
  bool _hasResolvedInitialAuthState = false;
  bool _requiresEmailVerification = false;
  bool _requiresPasswordReset = false;
  String? _pendingVerificationEmail;

  AuthViewModel({AuthRepositoryImpl? authRepository})
    : _authRepository = authRepository ?? AuthRepositoryImpl(),
      _ownsAuthRepository = authRepository == null {
    _authStateSubscription = _authRepository.watchAuthState().listen((user) {
      _currentUser = user ?? User.guest();
      _isLoading = false;
      _hasResolvedInitialAuthState = true;
      notifyListeners();
    });
    final cachedUser = _authRepository.getCurrentUser();
    if (cachedUser != null) {
      _currentUser = cachedUser;
      _hasResolvedInitialAuthState = true;
    }
  }

  /// Get current user
  User get currentUser => _currentUser;

  /// Check if user is logged in (not guest)
  bool get isLoggedIn => !_currentUser.isGuest;

  /// Check if user is guest
  bool get isGuest =>
      _currentUser.isGuest ||
      firebase_auth.FirebaseAuth.instance.currentUser?.isAnonymous == true;

  /// Check if loading
  bool get isLoading => _isLoading;

  /// True once Firebase/auth repository has emitted the initial account state.
  bool get hasResolvedInitialAuthState => _hasResolvedInitialAuthState;

  /// Get error message
  String? get error => _error;

  /// True when Firebase requires the current user to verify their email
  bool get requiresEmailVerification => _requiresEmailVerification;

  /// True when an abandoned temporary-password login must continue through reset
  bool get requiresPasswordReset => _requiresPasswordReset;

  /// True when the commuter must replace the temporary admin-issued password
  bool get requiresPasswordChange => _currentUser.mustChangePassword;

  /// Email address currently waiting for Firebase verification
  String get verificationEmail {
    if (_currentUser.email.isNotEmpty) {
      return _currentUser.email;
    }
    return _pendingVerificationEmail ?? '';
  }

  /// Check if the current user can perform a given action.
  /// Guests are restricted from write operations that require authentication.
  bool canPerformAction(String action) {
    if (!isGuest) return true;

    switch (action) {
      case 'book':
      case 'notify_driver':
      case 'drop_off':
      case 'cancel_booking':
        return false;
      case 'view_map':
      case 'view_jeepneys':
        return true;
      default:
        return false;
    }
  }

  /// Login with email and password
  Future<bool> login(String email, String password) async {
    _error = null;
    _requiresEmailVerification = false;
    _requiresPasswordReset = false;

    final emailValidation = AuthValidator.validateEmail(email);
    if (!emailValidation.isValid) {
      _error = AppStrings.errorLoginFailed;
      notifyListeners();
      return false;
    }

    final passwordValidation = AuthValidator.validatePassword(password);
    if (!passwordValidation.isValid) {
      _error = AppStrings.errorLoginFailed;
      notifyListeners();
      return false;
    }

    _isLoading = true;
    notifyListeners();

    try {
      _currentUser = await _authRepository.login(email.trim(), password);
      _requiresEmailVerification = false;
      _isLoading = false;
      notifyListeners();
      return true;
    } on Exception catch (e) {
      _error = _parseAuthError(e);
      _requiresEmailVerification = _isEmailNotVerifiedError(e);
      _requiresPasswordReset =
          e is AuthException &&
          e.code == AuthErrorCode.passwordChangeRequiresReset;
      if (_requiresEmailVerification) {
        _pendingVerificationEmail = email.trim();
      }
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _error = AppStrings.errorUnknown;
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Parse authentication error to user-friendly message
  String _parseAuthError(Exception e) {
    if (e is! AuthException) {
      return AppStrings.errorLoginFailed;
    }

    if (e.isRoleAccessError || e.code == AuthErrorCode.loginFailed) {
      return AppStrings.errorLoginFailed;
    }

    return _messageForAuthCode(e.code, fallback: AppStrings.errorLoginFailed);
  }

  bool _isEmailNotVerifiedError(Exception e) {
    return e is AuthException && e.code == AuthErrorCode.emailNotVerified;
  }

  String _messageForAuthCode(String code, {required String fallback}) {
    switch (code) {
      case AuthErrorCode.emailAlreadyInUse:
        return AppStrings.errorEmailInUse;
      case AuthErrorCode.invalidEmail:
        return AppStrings.errorInvalidEmail;
      case AuthErrorCode.weakPassword:
        return AppStrings.errorWeakPassword;
      case AuthErrorCode.wrongPassword:
        return AppStrings.errorWrongPassword;
      case AuthErrorCode.userNotFound:
        return AppStrings.errorUserNotFound;
      case AuthErrorCode.invalidCredential:
      case AuthErrorCode.invalidLoginCredentials:
        return AppStrings.errorInvalidCredential;
      case AuthErrorCode.networkRequestFailed:
        return AppStrings.errorNetworkError;
      case AuthErrorCode.tooManyRequests:
        return AppStrings.errorTooManyRequests;
      case AuthErrorCode.userDisabled:
        return AppStrings.errorUserDisabled;
      case AuthErrorCode.timeout:
        return AppStrings.errorLoginTimeout;
      case AuthErrorCode.emailNotVerified:
        return AppStrings.errorEmailNotVerified;
      case AuthErrorCode.noUserToVerify:
        return AppStrings.noUserToVerify;
      case AuthErrorCode.passwordChangeRequiresReset:
        return AppStrings.errorPasswordChangeRequiresReset;
      default:
        return fallback;
    }
  }

  /// Login as guest
  Future<bool> loginAsGuest() async {
    debugPrint('AuthViewModel: Continue as Guest requested.');

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _currentUser = await _authRepository.loginAsGuest();
      debugPrint(
        'AuthViewModel: Guest Mode active. localUserId=${_currentUser.id}',
      );
      _requiresEmailVerification = false;
      _requiresPasswordReset = false;
      _pendingVerificationEmail = null;
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('AuthViewModel: Guest Mode sign-in failed: $e');
      _error = AppStrings.errorGeneric;
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Logout
  Future<void> logout() async {
    _isLoading = true;
    notifyListeners();

    await _authRepository.logout();
    _currentUser = User.guest();
    _requiresEmailVerification = false;
    _requiresPasswordReset = false;
    _pendingVerificationEmail = null;
    _isLoading = false;
    notifyListeners();
  }

  /// Register a new commuter account with profile details, email, and password
  Future<bool> register({
    required String email,
    required String password,
    required String repeatPassword,
    required String firstName,
    required String lastName,
    required String phoneNumber,
    String middleName = '',
  }) async {
    _error = null;

    final firstNameValidation = AuthValidator.validateFirstName(firstName);
    if (!firstNameValidation.isValid) {
      _error = firstNameValidation.errorMessage;
      notifyListeners();
      return false;
    }

    final lastNameValidation = AuthValidator.validateLastName(lastName);
    if (!lastNameValidation.isValid) {
      _error = lastNameValidation.errorMessage;
      notifyListeners();
      return false;
    }

    final middleNameValidation = AuthValidator.validateMiddleName(middleName);
    if (!middleNameValidation.isValid) {
      _error = middleNameValidation.errorMessage;
      notifyListeners();
      return false;
    }

    final phoneNumberValidation = AuthValidator.validatePhoneNumber(
      phoneNumber,
    );
    if (!phoneNumberValidation.isValid) {
      _error = phoneNumberValidation.errorMessage;
      notifyListeners();
      return false;
    }

    final emailValidation = AuthValidator.validateEmail(email);
    if (!emailValidation.isValid) {
      _error = emailValidation.errorMessage;
      notifyListeners();
      return false;
    }

    final passwordValidation = AuthValidator.validatePassword(password);
    if (!passwordValidation.isValid) {
      _error = passwordValidation.errorMessage;
      notifyListeners();
      return false;
    }

    final repeatPasswordValidation = AuthValidator.validateConfirmPassword(
      password,
      repeatPassword,
    );
    if (!repeatPasswordValidation.isValid) {
      _error = repeatPasswordValidation.errorMessage;
      notifyListeners();
      return false;
    }

    _isLoading = true;
    notifyListeners();

    try {
      _currentUser = await _authRepository.register(
        email: email.trim(),
        password: password,
        firstName: firstName.trim(),
        lastName: lastName.trim(),
        middleName: middleName.trim(),
        phoneNumber: AuthValidator.normalizePhoneNumber(phoneNumber),
      );
      _requiresEmailVerification = true;
      _pendingVerificationEmail = email.trim();
      _isLoading = false;
      notifyListeners();
      return true;
    } on Exception catch (e) {
      _error = _parseRegistrationError(e);
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _error = AppStrings.errorUnknown;
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Parse registration error to user-friendly message
  String _parseRegistrationError(Exception e) {
    if (e is AuthException) {
      return _messageForAuthCode(
        e.code,
        fallback: AppStrings.errorRegistrationFailed,
      );
    }

    return AppStrings.errorRegistrationFailed;
  }

  /// Resend the verification email to the current Firebase user
  Future<bool> resendEmailVerification() async {
    _error = null;
    _isLoading = true;
    notifyListeners();

    try {
      await _authRepository.sendEmailVerification();
      _isLoading = false;
      notifyListeners();
      return true;
    } on Exception catch (e) {
      _error = _parseVerificationError(e);
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (_) {
      _error = AppStrings.verificationCheckFailed;
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Check Firebase for the latest email verification state
  Future<bool> checkEmailVerification() async {
    _error = null;
    _isLoading = true;
    notifyListeners();

    try {
      final verified = await _authRepository.reloadAndCheckEmailVerified();
      if (verified) {
        _currentUser = _authRepository.getCurrentUser() ?? _currentUser;
        _requiresEmailVerification = false;
        _pendingVerificationEmail = null;
      } else {
        _error = AppStrings.emailNotVerified;
        _requiresEmailVerification = true;
      }
      _isLoading = false;
      notifyListeners();
      return verified;
    } on Exception catch (e) {
      _error = _parseVerificationError(e);
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (_) {
      _error = AppStrings.verificationCheckFailed;
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> completeRequiredPasswordChange({
    required String newPassword,
    required String repeatPassword,
  }) async {
    _error = null;

    final passwordValidation = AuthValidator.validateRequiredNewPassword(
      newPassword,
    );
    if (!passwordValidation.isValid) {
      _error = passwordValidation.errorMessage;
      notifyListeners();
      return false;
    }

    final repeatPasswordValidation = AuthValidator.validateConfirmPassword(
      newPassword,
      repeatPassword,
    );
    if (!repeatPasswordValidation.isValid) {
      _error = repeatPasswordValidation.errorMessage;
      notifyListeners();
      return false;
    }

    _isLoading = true;
    notifyListeners();

    try {
      _currentUser = await _authRepository.completeRequiredPasswordChange(
        newPassword,
      );
      _requiresEmailVerification = false;
      _pendingVerificationEmail = null;
      _isLoading = false;
      notifyListeners();
      return true;
    } on Exception catch (e) {
      _error = _messageForAuthCode(
        e is AuthException ? e.code : AuthErrorCode.authError,
        fallback: AppStrings.errorGeneric,
      );
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (_) {
      _error = AppStrings.errorGeneric;
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  String _parseVerificationError(Exception e) {
    if (e is AuthException) {
      if (e.code == AuthErrorCode.noUserToVerify) {
        return AppStrings.noUserToVerify;
      }
      if (e.code == AuthErrorCode.emailNotVerified) {
        return AppStrings.emailNotVerified;
      }
      if (e.isRoleAccessError) {
        return AppStrings.errorLoginFailed;
      }
      return _messageForAuthCode(
        e.code,
        fallback: AppStrings.verificationCheckFailed,
      );
    }

    return AppStrings.verificationCheckFailed;
  }

  /// Clear error
  void clearError() {
    _error = null;
    notifyListeners();
  }

  /// Send password reset email
  Future<bool> sendPasswordResetEmail(String email) async {
    _error = null;

    final emailValidation = AuthValidator.validateEmail(email);
    if (!emailValidation.isValid) {
      _error = emailValidation.errorMessage;
      notifyListeners();
      return false;
    }

    _isLoading = true;
    notifyListeners();

    try {
      await _authRepository.sendPasswordResetEmail(email.trim());
      _currentUser = _authRepository.getCurrentUser() ?? _currentUser;
      _requiresEmailVerification = false;
      _requiresPasswordReset = false;
      _isLoading = false;
      notifyListeners();
      return true;
    } on Exception catch (e) {
      _error = _parsePasswordResetError(e);
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _error = AppStrings.errorGeneric;
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Parse password reset error to user-friendly message
  String _parsePasswordResetError(Exception e) {
    if (e is AuthException) {
      return _messageForAuthCode(e.code, fallback: AppStrings.errorGeneric);
    }

    return AppStrings.errorGeneric;
  }

  @override
  void dispose() {
    unawaited(_authStateSubscription.cancel());
    if (_ownsAuthRepository) {
      unawaited(_authRepository.dispose());
    }
    super.dispose();
  }
}
