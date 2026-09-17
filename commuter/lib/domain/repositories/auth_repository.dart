import '../entities/user.dart';

/// Repository interface for authentication operations
abstract class AuthRepository {
  /// Get the current user
  User? getCurrentUser();

  /// Login with email and password
  Future<User> login(String email, String password);

  /// Register with commuter profile details, email, and password
  Future<User> register({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    required String phoneNumber,
    String middleName,
  });

  /// Send a Firebase email verification link to the current user
  Future<void> sendEmailVerification();

  /// Reload the current Firebase user and return true when email is verified
  Future<bool> reloadAndCheckEmailVerified();

  /// Replace the temporary password and clear the first-login gate
  Future<User> completeRequiredPasswordChange(String newPassword);

  /// Login as guest (anonymous Firebase authentication)
  Future<User> loginAsGuest();

  /// Logout
  Future<void> logout();

  /// Check if user is logged in
  bool isLoggedIn();

  /// Check if user is guest
  bool isGuest();

  /// Stream of auth state changes
  Stream<User?> watchAuthState();

  /// Update user profile
  Future<User> updateProfile(User user);

  /// Send password reset email
  Future<void> sendPasswordResetEmail(String email);
}
