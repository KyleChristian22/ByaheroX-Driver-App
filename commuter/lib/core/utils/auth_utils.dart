import 'package:firebase_auth/firebase_auth.dart';

/// Helper utilities for checking Firebase Auth custom claims.
///
/// Used to verify driver/admin permissions enforced by Firestore Security Rules.
class AuthUtils {
  AuthUtils._();

  /// Force-refresh the ID token and return true if the user has the `driver` claim.
  static Future<bool> isDriver() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    final result = await user.getIdTokenResult(true);
    return result.claims?['driver'] == true;
  }

  /// Force-refresh the ID token and return true if the user has the `admin` claim.
  static Future<bool> isAdmin() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    final result = await user.getIdTokenResult(true);
    return result.claims?['admin'] == true;
  }

  /// Force-refresh the ID token and return all custom claims.
  static Future<Map<String, dynamic>> getUserClaims() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return {};

    final result = await user.getIdTokenResult(true);
    return Map<String, dynamic>.from(result.claims ?? {});
  }
}
