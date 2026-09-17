/// Auth error codes used by the commuter authentication flow.
///
/// Firebase-backed errors intentionally keep Firebase's exact code strings so
/// UI mapping can be done without parsing raw exception text.
class AuthErrorCode {
  AuthErrorCode._();

  static const String emailAlreadyInUse = 'email-already-in-use';
  static const String invalidEmail = 'invalid-email';
  static const String weakPassword = 'weak-password';
  static const String wrongPassword = 'wrong-password';
  static const String userNotFound = 'user-not-found';
  static const String invalidCredential = 'invalid-credential';
  static const String invalidLoginCredentials = 'invalid-login-credentials';
  static const String networkRequestFailed = 'network-request-failed';
  static const String tooManyRequests = 'too-many-requests';
  static const String userDisabled = 'user-disabled';
  static const String operationNotAllowed = 'operation-not-allowed';
  static const String internalError = 'internal-error';

  static const String timeout = 'timeout';
  static const String authError = 'auth-error';
  static const String loginFailed = 'login-failed';
  static const String emailNotVerified = 'email-not-verified';
  static const String noUserToVerify = 'no-user-to-verify';
  static const String passwordChangeRequiresReset =
      'password-change-requires-reset';
  static const String driverAccountNotAllowed = 'driver-account-not-allowed';
  static const String notCommuterAccount = 'not-commuter-account';
  static const String accountRoleCheckFailed = 'account-role-check-failed';
  static const String commuterAccountBlocked = 'commuter-account-blocked';

  static const Set<String> roleAccessErrors = {
    driverAccountNotAllowed,
    notCommuterAccount,
    accountRoleCheckFailed,
    commuterAccountBlocked,
  };
}

/// Typed auth exception used between the repository and ViewModel.
class AuthException implements Exception {
  const AuthException(this.code, {this.message});

  final String code;
  final String? message;

  bool get isRoleAccessError => AuthErrorCode.roleAccessErrors.contains(code);

  @override
  String toString() {
    if (message == null || message!.isEmpty) {
      return 'AuthException(code: $code)';
    }
    return 'AuthException(code: $code, message: $message)';
  }
}
