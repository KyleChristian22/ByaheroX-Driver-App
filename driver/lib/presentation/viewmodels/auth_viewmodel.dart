import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../../services/analytics_tracking_service.dart';
import '../../services/firestore_service.dart';

class AuthResult {
  final bool success;
  final String? error;
  final AuthErrorType errorType;

  AuthResult({
    required this.success,
    this.error,
    this.errorType = AuthErrorType.none,
  });

  factory AuthResult.success() => AuthResult(success: true);

  factory AuthResult.failure(String message, AuthErrorType type) => AuthResult(
        success: false,
        error: message,
        errorType: type,
      );
}

enum AuthErrorType {
  none,
  invalidEmail,
  userNotFound,
  wrongPassword,
  userDisabled,
  networkError,
  tooManyRequests,
  emailNotVerified,
  passwordChangeRequiresReset,
  unknown,
}

class EmailValidationResult {
  final bool isValid;
  final String? error;

  EmailValidationResult({required this.isValid, this.error});

  factory EmailValidationResult.valid() => EmailValidationResult(isValid: true);

  factory EmailValidationResult.invalid(String error) =>
      EmailValidationResult(isValid: false, error: error);
}

class PasswordValidationResult {
  final bool isValid;
  final String? error;

  PasswordValidationResult({required this.isValid, this.error});

  factory PasswordValidationResult.valid() =>
      PasswordValidationResult(isValid: true);

  factory PasswordValidationResult.invalid(String error) =>
      PasswordValidationResult(isValid: false, error: error);
}

class AuthViewModel extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  User? _currentUser;
  bool _isLoading = false;
  String? _error;
  AuthErrorType _errorType = AuthErrorType.none;
  bool _requiresPasswordChange = false;
  bool _requiresEmailVerification = false;

  int _loginAttempts = 0;
  DateTime? _lockoutEndTime;
  Timer? _lockoutTimer;
  DateTime? _lastVerificationEmailSentAt;
  static const int _maxAttempts = 5;
  static const Duration _lockoutDuration = Duration(minutes: 2);
  static const Duration _verificationEmailCooldown = Duration(minutes: 5);

  User? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  String? get error => _error;
  AuthErrorType get errorType => _errorType;
  bool get isAuthenticated => _currentUser != null;
  bool get isLockedOut => _remainingLockoutDuration != null;
  bool get requiresPasswordChange => _requiresPasswordChange;
  bool get requiresEmailVerification => _requiresEmailVerification;
  String get verificationEmail => _currentUser?.email ?? '';

  String? get lockoutRemainingTime {
    final remaining = _remainingLockoutDuration;
    if (remaining == null) return null;
    return _formatLockoutDuration(remaining);
  }

  AuthViewModel() {
    _initAuthStateListener();
  }

  @override
  void dispose() {
    _lockoutTimer?.cancel();
    super.dispose();
  }

  static final RegExp _emailRegex = RegExp(
    r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
  );

  EmailValidationResult validateEmail(String? email) {
    if (email == null || email.trim().isEmpty) {
      return EmailValidationResult.invalid('Email is required');
    }
    final trimmed = email.trim();
    if (!_emailRegex.hasMatch(trimmed)) {
      return EmailValidationResult.invalid(
          'Please enter a valid email address');
    }
    if (trimmed.length > 254) {
      return EmailValidationResult.invalid('Email address is too long');
    }
    return EmailValidationResult.valid();
  }

  PasswordValidationResult validatePassword(String? password) {
    if (password == null || password.isEmpty) {
      return PasswordValidationResult.invalid('Password is required');
    }
    if (password != password.trim()) {
      return PasswordValidationResult.invalid(
        'Password cannot start or end with spaces',
      );
    }
    if (password.length < 8) {
      return PasswordValidationResult.invalid(
          'Password must be at least 8 characters');
    }
    if (password.length > 128) {
      return PasswordValidationResult.invalid('Password is too long');
    }
    final hasLetter = RegExp(r'[a-zA-Z]').hasMatch(password);
    final hasNumber = RegExp(r'[0-9]').hasMatch(password);
    if (!hasLetter || !hasNumber) {
      return PasswordValidationResult.invalid(
        'Password must contain both letters and numbers',
      );
    }
    return PasswordValidationResult.valid();
  }

  PasswordValidationResult validateRequiredNewPassword(String? password) {
    if (password == null || password.isEmpty) {
      return PasswordValidationResult.invalid('Password is required');
    }
    if (password != password.trim()) {
      return PasswordValidationResult.invalid(
        'Password cannot start or end with spaces',
      );
    }
    if (password.length < 8) {
      return PasswordValidationResult.invalid(
        'Password must be at least 8 characters',
      );
    }
    if (password.length > 128) {
      return PasswordValidationResult.invalid('Password is too long');
    }
    if (!RegExp(r'[A-Z]').hasMatch(password) ||
        !RegExp(r'[a-z]').hasMatch(password) ||
        !RegExp(r'[^A-Za-z0-9]').hasMatch(password)) {
      return PasswordValidationResult.invalid(
        'Password must include uppercase, lowercase, and special character',
      );
    }
    return PasswordValidationResult.valid();
  }

  void _initAuthStateListener() {
    _auth.authStateChanges().listen((User? user) {
      if (user == null) {
        FirestoreService.clearDriverCache();
      }
      _currentUser = user;
      debugPrint('Auth state changed - User: ${user?.uid ?? 'null'}');
      notifyListeners();
    });
    _currentUser = _auth.currentUser;
    debugPrint('Current user initialized: ${_currentUser?.uid ?? 'null'}');
    notifyListeners();
  }

  Future<AuthResult> login(String email, String password) async {
    _clearExpiredLockoutIfNeeded();
    FirestoreService.clearDriverCache();
    _requiresPasswordChange = false;
    _requiresEmailVerification = false;

    if (isLockedOut) {
      final remaining = lockoutRemainingTime;
      _error = 'Too many failed login attempts. Try again in $remaining.';
      _errorType = AuthErrorType.tooManyRequests;
      notifyListeners();
      return AuthResult.failure(_error!, _errorType);
    }

    final emailValidation = validateEmail(email);
    if (!emailValidation.isValid) {
      _error = emailValidation.error;
      _errorType = AuthErrorType.invalidEmail;
      notifyListeners();
      return AuthResult.failure(_error!, _errorType);
    }

    final passwordValidation = validatePassword(password);
    if (!passwordValidation.isValid) {
      _error = passwordValidation.error;
      _errorType = AuthErrorType.unknown;
      notifyListeners();
      return AuthResult.failure(_error!, _errorType);
    }

    _isLoading = true;
    _error = null;
    _errorType = AuthErrorType.none;
    notifyListeners();

    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email.trim().toLowerCase(),
        password: password,
      );

      _currentUser = credential.user;
      await _currentUser?.reload();
      _currentUser = _auth.currentUser;

      if (_currentUser == null) {
        _error = 'Login failed. Please try again.';
        _errorType = AuthErrorType.unknown;
        _isLoading = false;
        notifyListeners();
        return AuthResult.failure(_error!, _errorType);
      }

      _resetLoginFailureState();

      if (!_currentUser!.emailVerified) {
        final verificationEmailSent =
            await _sendVerificationEmailIfPossible(_currentUser!);
        final loginEmail = _currentUser!.email ?? email.trim().toLowerCase();
        _error = verificationEmailSent
            ? 'Please verify your email address before logging in. We sent a verification link to $loginEmail.'
            : 'Please verify your email address before logging in. Check the verification email sent to $loginEmail.';
        _errorType = AuthErrorType.emailNotVerified;
        _requiresEmailVerification = true;
        _isLoading = false;
        notifyListeners();
        return AuthResult.failure(_error!, _errorType);
      }

      final driverProfileResult =
          await FirestoreService.getCurrentDriverProfileResult();
      if (!driverProfileResult.success) {
        await logout();
        _error = driverProfileResult.message;
        _errorType = _getFirestoreErrorType(driverProfileResult.errorCode);
        _isLoading = false;
        notifyListeners();
        return AuthResult.failure(_error!, _errorType);
      }

      final driverProfile = driverProfileResult.data;
      if (driverProfile == null) {
        await logout();
        _error = driverProfileResult.message;
        _errorType = AuthErrorType.unknown;
        _isLoading = false;
        notifyListeners();
        return AuthResult.failure(_error!, _errorType);
      }

      if (driverProfile.role != 'driver') {
        await logout();
        _error = 'This account is not authorized as a driver.';
        _errorType = AuthErrorType.userDisabled;
        _isLoading = false;
        notifyListeners();
        return AuthResult.failure(_error!, _errorType);
      }

      if (!driverProfile.isActive) {
        await logout();
        _error =
            'This driver account is not active. Please contact the administrator.';
        _errorType = AuthErrorType.userDisabled;
        _isLoading = false;
        notifyListeners();
        return AuthResult.failure(_error!, _errorType);
      }

      await FirestoreService.markCurrentDriverEmailVerified();

      if (driverProfile.mustSetPassword) {
        final metadataUpdated = await FirestoreService
            .markCurrentDriverTemporaryPasswordLoginConsumed();
        if (!metadataUpdated) {
          debugPrint(
            'Driver temporary password metadata update failed; keeping password-change gate active.',
          );
        }
        _requiresPasswordChange = true;
        _isLoading = false;
        notifyListeners();
        return AuthResult.success();
      }

      final metadataUpdated =
          await FirestoreService.updateCurrentDriverLastLogin();

      if (!metadataUpdated) {
        debugPrint(
          'Driver login metadata update failed; allowing authenticated driver to continue.',
        );
      }

      // Store FCM token after successful login
      await _storeFCMToken();

      _requiresPasswordChange = false;
      _requiresEmailVerification = false;
      _resetLoginFailureState();
      _isLoading = false;
      notifyListeners();
      return AuthResult.success();
    } on FirebaseAuthException catch (e) {
      _applyLoginFailure(e.code);
      _isLoading = false;
      notifyListeners();
      return AuthResult.failure(_error!, _errorType);
    } on PlatformException catch (e) {
      _applyLoginFailure(e.code);
      _isLoading = false;
      notifyListeners();
      return AuthResult.failure(_error!, _errorType);
    } on FirebaseException catch (e) {
      _error = FirestoreService.userFriendlyMessageForError(e);
      _errorType = _getFirestoreErrorType(e.code);
      _isLoading = false;
      notifyListeners();
      return AuthResult.failure(_error!, _errorType);
    } catch (e) {
      _error = 'An unexpected error occurred. Please try again.';
      _errorType = AuthErrorType.unknown;
      _isLoading = false;
      notifyListeners();
      return AuthResult.failure(_error!, _errorType);
    }
  }

  Future<AuthResult> validateSavedSession() async {
    _requiresPasswordChange = false;
    _requiresEmailVerification = false;
    _isLoading = true;
    _error = null;
    _errorType = AuthErrorType.none;
    notifyListeners();

    try {
      final restoredUser = await _getRestoredCurrentUser();
      _currentUser = restoredUser;

      if (restoredUser == null) {
        _isLoading = false;
        notifyListeners();
        return AuthResult.failure(
          'No saved session found. Please log in.',
          AuthErrorType.unknown,
        );
      }

      await restoredUser.reload();
      _currentUser = _auth.currentUser;

      if (_currentUser == null) {
        _isLoading = false;
        notifyListeners();
        return AuthResult.failure(
          'No saved session found. Please log in.',
          AuthErrorType.unknown,
        );
      }

      if (!_currentUser!.emailVerified) {
        _requiresEmailVerification = true;
        _error = 'Please verify your email address before continuing.';
        _errorType = AuthErrorType.emailNotVerified;
        _isLoading = false;
        notifyListeners();
        return AuthResult.failure(_error!, _errorType);
      }

      final driverProfileResult =
          await FirestoreService.getCurrentDriverProfileResult();
      final driverProfile = driverProfileResult.data;

      if (!driverProfileResult.success || driverProfile == null) {
        _error = driverProfileResult.message;
        _errorType = _getFirestoreErrorType(driverProfileResult.errorCode);

        if (_errorType != AuthErrorType.networkError) {
          await logout();
        }

        _isLoading = false;
        notifyListeners();
        return AuthResult.failure(_error!, _errorType);
      }

      if (driverProfile.role != 'driver') {
        _error = 'This account is not authorized as a driver.';
        _errorType = AuthErrorType.userDisabled;
        await logout();
        _isLoading = false;
        notifyListeners();
        return AuthResult.failure(_error!, _errorType);
      }

      if (!driverProfile.isActive) {
        _error =
            'This driver account is not active. Please contact the administrator.';
        _errorType = AuthErrorType.userDisabled;
        await logout();
        _isLoading = false;
        notifyListeners();
        return AuthResult.failure(_error!, _errorType);
      }

      await FirestoreService.markCurrentDriverEmailVerified();

      if (driverProfile.mustSetPassword) {
        await FirestoreService
            .markCurrentDriverTemporaryPasswordLoginConsumed();
        _requiresPasswordChange = true;
      } else {
        await FirestoreService.updateCurrentDriverLastLogin();
        await _storeFCMToken();
        _requiresPasswordChange = false;
      }

      _requiresEmailVerification = false;
      _resetLoginFailureState();
      _isLoading = false;
      notifyListeners();
      return AuthResult.success();
    } on FirebaseAuthException catch (e) {
      _error = _getErrorMessage(e.code);
      _errorType = _getErrorType(e.code);

      if (_errorType == AuthErrorType.userDisabled ||
          e.code == 'invalid-user-token' ||
          e.code == 'user-token-expired') {
        await logout();
      }

      _isLoading = false;
      notifyListeners();
      return AuthResult.failure(_error!, _errorType);
    } on PlatformException catch (e) {
      _error = _getErrorMessage(e.code);
      _errorType = _getErrorType(e.code);
      _isLoading = false;
      notifyListeners();
      return AuthResult.failure(_error!, _errorType);
    } on FirebaseException catch (e) {
      _error = FirestoreService.userFriendlyMessageForError(e);
      _errorType = _getFirestoreErrorType(e.code);
      _isLoading = false;
      notifyListeners();
      return AuthResult.failure(_error!, _errorType);
    } catch (e) {
      _error = 'Could not restore your session. Please try again.';
      _errorType = AuthErrorType.unknown;
      _isLoading = false;
      notifyListeners();
      return AuthResult.failure(_error!, _errorType);
    }
  }

  /// Send password reset email
  Future<bool> sendPasswordResetEmail(String email) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
      _requiresPasswordChange = false;
      _requiresEmailVerification = false;
      _isLoading = false;
      notifyListeners();
      return true;
    } on FirebaseAuthException catch (e) {
      _error = _getResetErrorMessage(e.code);
      _isLoading = false;
      notifyListeners();
      return false;
    } on PlatformException catch (e) {
      _error = _getResetErrorMessage(e.code);
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _error = 'An error occurred. Please try again.';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> _sendVerificationEmailIfPossible(User user) async {
    if (!_canSendVerificationEmail()) {
      debugPrint('Skipped verification resend because cooldown is active.');
      return false;
    }

    try {
      await user.sendEmailVerification();
      _lastVerificationEmailSentAt = DateTime.now();
      return true;
    } on FirebaseAuthException catch (e) {
      debugPrint('Could not resend driver verification email: ${e.code}');
      if (e.code == 'too-many-requests') {
        _lastVerificationEmailSentAt = DateTime.now();
      }
      return false;
    } on PlatformException catch (e) {
      debugPrint('Could not resend driver verification email: ${e.code}');
      if (e.code == 'too-many-requests') {
        _lastVerificationEmailSentAt = DateTime.now();
      }
      return false;
    } catch (e) {
      debugPrint('Could not resend driver verification email: $e');
      return false;
    }
  }

  Future<User?> _getRestoredCurrentUser() async {
    final existingUser = _auth.currentUser;
    if (existingUser != null) return existingUser;

    try {
      return await _auth.authStateChanges().first.timeout(
            const Duration(seconds: 2),
            onTimeout: () => _auth.currentUser,
          );
    } catch (_) {
      return _auth.currentUser;
    }
  }

  Future<bool> resendEmailVerification() async {
    _error = null;
    _isLoading = true;
    notifyListeners();

    try {
      final user = _auth.currentUser;
      if (user == null) {
        _error = 'No account to send verification. Please log in again.';
        _errorType = AuthErrorType.unknown;
        _isLoading = false;
        notifyListeners();
        return false;
      }

      await user.reload();
      final refreshedUser = _auth.currentUser;
      if (refreshedUser == null) {
        _error = 'No account to send verification. Please log in again.';
        _errorType = AuthErrorType.unknown;
        _isLoading = false;
        notifyListeners();
        return false;
      }

      if (refreshedUser.emailVerified) {
        _error = 'Email is already verified.';
        _errorType = AuthErrorType.none;
        _isLoading = false;
        notifyListeners();
        return false;
      }

      final sent = await _sendVerificationEmailIfPossible(refreshedUser);
      _isLoading = false;
      notifyListeners();
      return sent;
    } on FirebaseAuthException catch (e) {
      _error = _getResetErrorMessage(e.code);
      _isLoading = false;
      notifyListeners();
      return false;
    } on PlatformException catch (e) {
      _error = _getResetErrorMessage(e.code);
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _error = 'An unexpected error occurred. Please try again.';
      _errorType = AuthErrorType.unknown;
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<AuthResult> checkEmailVerification() async {
    _isLoading = true;
    _error = null;
    _errorType = AuthErrorType.none;
    notifyListeners();

    try {
      final user = _auth.currentUser;
      if (user == null) {
        _error = 'No account to verify. Please log in again.';
        _errorType = AuthErrorType.unknown;
        _isLoading = false;
        notifyListeners();
        return AuthResult.failure(_error!, _errorType);
      }

      await user.reload();
      _currentUser = _auth.currentUser;
      if (_currentUser == null || !_currentUser!.emailVerified) {
        _error =
            'Email is not verified yet. Please open the verification link first.';
        _errorType = AuthErrorType.emailNotVerified;
        _requiresEmailVerification = true;
        _isLoading = false;
        notifyListeners();
        return AuthResult.failure(_error!, _errorType);
      }

      final driverProfileResult =
          await FirestoreService.getCurrentDriverProfileResult();
      if (!driverProfileResult.success || driverProfileResult.data == null) {
        _error = driverProfileResult.message;
        _errorType = _getFirestoreErrorType(driverProfileResult.errorCode);
        _isLoading = false;
        notifyListeners();
        return AuthResult.failure(_error!, _errorType);
      }

      final driverProfile = driverProfileResult.data!;
      if (driverProfile.role != 'driver') {
        _error = 'This account is not authorized as a driver.';
        _errorType = AuthErrorType.userDisabled;
        _isLoading = false;
        notifyListeners();
        return AuthResult.failure(_error!, _errorType);
      }
      if (!driverProfile.isActive) {
        _error =
            'This driver account is not active. Please contact the administrator.';
        _errorType = AuthErrorType.userDisabled;
        _isLoading = false;
        notifyListeners();
        return AuthResult.failure(_error!, _errorType);
      }

      await FirestoreService.markCurrentDriverEmailVerified();

      if (driverProfile.mustSetPassword) {
        await FirestoreService
            .markCurrentDriverTemporaryPasswordLoginConsumed();
        _requiresPasswordChange = true;
      } else {
        await FirestoreService.updateCurrentDriverLastLogin();
        await _storeFCMToken();
        _requiresPasswordChange = false;
      }

      _requiresEmailVerification = false;
      _isLoading = false;
      notifyListeners();
      return AuthResult.success();
    } on FirebaseAuthException catch (e) {
      _applyLoginFailure(e.code);
      _isLoading = false;
      notifyListeners();
      return AuthResult.failure(_error!, _errorType);
    } on FirebaseException catch (e) {
      _error = FirestoreService.userFriendlyMessageForError(e);
      _errorType = _getFirestoreErrorType(e.code);
      _isLoading = false;
      notifyListeners();
      return AuthResult.failure(_error!, _errorType);
    } catch (e) {
      _error = 'Verification check failed. Please try again.';
      _errorType = AuthErrorType.unknown;
      _isLoading = false;
      notifyListeners();
      return AuthResult.failure(_error!, _errorType);
    }
  }

  Future<AuthResult> completeRequiredPasswordChange(String newPassword) async {
    final validation = validateRequiredNewPassword(newPassword);
    if (!validation.isValid) {
      _error = validation.error;
      _errorType = AuthErrorType.unknown;
      notifyListeners();
      return AuthResult.failure(_error!, _errorType);
    }

    _isLoading = true;
    _error = null;
    _errorType = AuthErrorType.none;
    notifyListeners();

    try {
      final user = _auth.currentUser;
      if (user == null) {
        _error = 'No signed-in driver was found. Please log in again.';
        _errorType = AuthErrorType.unknown;
        _isLoading = false;
        notifyListeners();
        return AuthResult.failure(_error!, _errorType);
      }

      await user.reload();
      final refreshedUser = _auth.currentUser;
      if (refreshedUser == null || !refreshedUser.emailVerified) {
        await _sendVerificationEmailIfPossible(refreshedUser ?? user);
        _error =
            'Please verify your email address before changing your password. A verification link has been sent to your email.';
        _errorType = AuthErrorType.emailNotVerified;
        _requiresEmailVerification = true;
        _isLoading = false;
        notifyListeners();
        return AuthResult.failure(_error!, _errorType);
      }

      await user.updatePassword(newPassword);
      await FirestoreService.markCurrentDriverPasswordSetupComplete();
      await FirestoreService.markCurrentDriverEmailVerified();
      await _storeFCMToken();

      _requiresPasswordChange = false;
      _requiresEmailVerification = false;
      _isLoading = false;
      notifyListeners();
      return AuthResult.success();
    } on FirebaseAuthException catch (e) {
      _applyLoginFailure(e.code);
      _isLoading = false;
      notifyListeners();
      return AuthResult.failure(_error!, _errorType);
    } on PlatformException catch (e) {
      _applyLoginFailure(e.code);
      _isLoading = false;
      notifyListeners();
      return AuthResult.failure(_error!, _errorType);
    } catch (e) {
      _error = 'Could not update password. Please try again.';
      _errorType = AuthErrorType.unknown;
      _isLoading = false;
      notifyListeners();
      return AuthResult.failure(_error!, _errorType);
    }
  }

  /// Logout
  Future<void> logout() async {
    await AnalyticsTrackingService.stopDriverSession();
    await _auth.signOut();
    FirestoreService.clearDriverCache();
    _currentUser = null;
    _requiresPasswordChange = false;
    _requiresEmailVerification = false;
    notifyListeners();
  }

  bool _canSendVerificationEmail() {
    if (_lastVerificationEmailSentAt == null) {
      return true;
    }

    final elapsed = DateTime.now().difference(_lastVerificationEmailSentAt!);
    return elapsed >= _verificationEmailCooldown;
  }

  void _applyLoginFailure(String code) {
    if (code == 'too-many-requests') {
      _startLockout(
        'Too many requests. Please wait ${_lockoutDuration.inMinutes} minutes before trying again.',
      );
      return;
    }

    if (_isCredentialFailureCode(code)) {
      _loginAttempts++;

      if (_loginAttempts >= _maxAttempts) {
        _startLockout(
          'Too many failed login attempts. Try again in ${_formatLockoutDuration(_lockoutDuration)}.',
        );
        return;
      }

      final attemptsRemaining = _maxAttempts - _loginAttempts;
      final attemptLabel = attemptsRemaining == 1 ? 'attempt' : 'attempts';
      _error =
          '${_getErrorMessage(code)} $attemptsRemaining $attemptLabel remaining before a temporary lockout.';
      _errorType = _getErrorType(code);
      return;
    }

    _error = _getErrorMessage(code);
    _errorType = _getErrorType(code);
  }

  Duration? get _remainingLockoutDuration {
    if (_lockoutEndTime == null) return null;
    final remaining = _lockoutEndTime!.difference(DateTime.now());
    if (remaining <= Duration.zero) return null;
    return remaining;
  }

  bool _clearExpiredLockoutIfNeeded() {
    if (_lockoutEndTime == null || isLockedOut) {
      return false;
    }

    _lockoutEndTime = null;
    _loginAttempts = 0;
    _lockoutTimer?.cancel();
    _lockoutTimer = null;
    if (_errorType == AuthErrorType.tooManyRequests) {
      _error = null;
      _errorType = AuthErrorType.none;
    }
    return true;
  }

  void _startLockout(String message) {
    _lockoutEndTime = DateTime.now().add(_lockoutDuration);
    _loginAttempts = _maxAttempts;
    _error = message;
    _errorType = AuthErrorType.tooManyRequests;

    _lockoutTimer?.cancel();
    _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_clearExpiredLockoutIfNeeded()) {
        notifyListeners();
        return;
      }

      notifyListeners();
    });
  }

  void _resetLoginFailureState() {
    _loginAttempts = 0;
    _lockoutEndTime = null;
    _lockoutTimer?.cancel();
    _lockoutTimer = null;
  }

  bool _isCredentialFailureCode(String code) {
    switch (code) {
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
      case 'invalid-login-credentials':
        return true;
      default:
        return false;
    }
  }

  String _formatLockoutDuration(Duration duration) {
    final totalSeconds = duration.inSeconds;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;

    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  AuthErrorType _getErrorType(String code) {
    switch (code) {
      case 'user-not-found':
        return AuthErrorType.userNotFound;
      case 'wrong-password':
      case 'invalid-credential':
      case 'invalid-login-credentials':
        return AuthErrorType.wrongPassword;
      case 'invalid-email':
        return AuthErrorType.invalidEmail;
      case 'user-disabled':
        return AuthErrorType.userDisabled;
      case 'too-many-requests':
        return AuthErrorType.tooManyRequests;
      case 'network-request-failed':
      case 'network-error':
        return AuthErrorType.networkError;
      default:
        return AuthErrorType.unknown;
    }
  }

  AuthErrorType _getFirestoreErrorType(String? code) {
    switch (code) {
      case FirestoreErrorCode.unavailable:
        return AuthErrorType.networkError;
      default:
        return AuthErrorType.unknown;
    }
  }

  String _getResetErrorMessage(String code) {
    switch (code) {
      case 'user-not-found':
        return 'No user found with this email.';
      case 'invalid-email':
        return 'Invalid email address.';
      case 'too-many-requests':
        return 'Too many requests. Please wait a few minutes before trying again.';
      default:
        return 'Failed to send reset email. Please try again.';
    }
  }

  /// Store FCM token in Firestore after login
  Future<void> _storeFCMToken() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await FirestoreService.updateCurrentDriverFcmToken(token);
        debugPrint('FCM token stored for current driver');
      }
    } catch (e) {
      debugPrint('Error storing FCM token: $e');
    }
  }

  /// Clear error
  void clearError() {
    _error = null;
    notifyListeners();
  }

  String _getErrorMessage(String code) {
    switch (code) {
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
      case 'invalid-login-credentials':
        return 'Incorrect email or password.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'user-disabled':
        return 'This driver account has been disabled. Please contact the administrator.';
      case 'too-many-requests':
        return 'Too many requests. Please wait a few minutes before trying again.';
      case 'network-request-failed':
      case 'network-error':
        return 'Network error. Please check your internet connection and try again.';
      default:
        return 'Login failed. Please try again.';
    }
  }
}
