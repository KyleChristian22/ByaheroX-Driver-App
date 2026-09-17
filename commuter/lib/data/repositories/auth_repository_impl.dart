import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:commuter_app/data/services/app_session_service.dart';
import 'package:flutter/foundation.dart';
import '../../domain/entities/user.dart';
import '../../domain/repositories/auth_exception.dart';
import '../../domain/repositories/auth_repository.dart';

/// Implementation of AuthRepository using Firebase Authentication
class AuthRepositoryImpl implements AuthRepository {
  final firebase_auth.FirebaseAuth _firebaseAuth;
  final FirebaseFirestore _firestore;
  User? _currentUser;
  late final StreamSubscription<firebase_auth.User?> _firebaseAuthSubscription;
  final StreamController<User?> _authStateController =
      StreamController<User?>.broadcast();

  AuthRepositoryImpl({
    firebase_auth.FirebaseAuth? firebaseAuth,
    FirebaseFirestore? firestore,
  }) : _firebaseAuth = firebaseAuth ?? firebase_auth.FirebaseAuth.instance,
       _firestore = firestore ?? FirebaseFirestore.instance {
    // Listen to auth state changes
    _firebaseAuthSubscription = _firebaseAuth.authStateChanges().listen(
      _onAuthStateChanged,
    );
  }

  void _onAuthStateChanged(firebase_auth.User? firebaseUser) async {
    if (firebaseUser != null) {
      try {
        if (firebaseUser.isAnonymous) {
          await _createOrUpdateGuestDocument(firebaseUser);
          _currentUser = _guestUserFromFirebaseUser(firebaseUser);
          debugPrint(
            'AuthRepositoryImpl: Anonymous Firebase user active for Guest Mode. '
            'uid=${firebaseUser.uid}, isAnonymous=${firebaseUser.isAnonymous}',
          );
          _authStateController.add(_currentUser);
          return;
        }

        await _assertCommuterAccount(firebaseUser);
        _currentUser = await _fetchUserFromFirestore(firebaseUser.uid);
        if (_currentUser == null) {
          // Create new user in Firestore if doesn't exist
          _currentUser = User(
            id: firebaseUser.uid,
            email: firebaseUser.email ?? '',
            displayName:
                firebaseUser.displayName ??
                firebaseUser.email?.split('@').first ??
                'User',
            notificationPreferences: const NotificationPreferences(),
            isGuest: false,
          );
          await _saveUserToFirestore(_currentUser!);
        }
      } on AuthException catch (e) {
        if (e.isRoleAccessError) {
          debugPrint(
            'AuthRepositoryImpl: Role access denied (${e.code}). Signing out.',
          );
          await _firebaseAuth.signOut();
          _currentUser = User.guest();
        } else {
          debugPrint(
            'AuthRepositoryImpl: Non-critical auth error (${e.code}). '
            'Keeping user signed in with fallback.',
          );
          _currentUser = _fallbackUserFromFirebaseUser(firebaseUser);
        }
      } catch (e) {
        debugPrint(
          'AuthRepositoryImpl: Transient auth state validation error: $e. '
          'Keeping user signed in with fallback.',
        );
        _currentUser = _fallbackUserFromFirebaseUser(firebaseUser);
      }
    } else {
      _currentUser = User.guest();
    }
    _authStateController.add(_currentUser);
  }

  User _guestUserFromFirebaseUser(firebase_auth.User firebaseUser) {
    return User(
      id: firebaseUser.uid,
      email: '',
      displayName: 'Bisita',
      notificationPreferences: const NotificationPreferences(),
      isGuest: true,
    );
  }

  User _fallbackUserFromFirebaseUser(firebase_auth.User firebaseUser) {
    return User(
      id: firebaseUser.uid,
      email: firebaseUser.email ?? '',
      displayName:
          firebaseUser.displayName ??
          firebaseUser.email?.split('@').first ??
          'User',
      notificationPreferences: const NotificationPreferences(),
      isGuest: false,
    );
  }

  Future<void> _createOrUpdateGuestDocument(
    firebase_auth.User firebaseUser,
  ) async {
    final guestDocRef = _firestore
        .collection('commuter_guests')
        .doc(firebaseUser.uid);
    final guestData = {
      'uid': firebaseUser.uid,
      'role': 'guest',
      'isGuest': true,
      'isAnonymous': true,
      'status': 'active',
      'canViewLiveMap': true,
      'canViewJeepneys': true,
      'canUsePickupLocation': false,
      'canRate': false,
      'lastSeenAt': FieldValue.serverTimestamp(),
    };

    final guestDoc = await guestDocRef.get();
    if (guestDoc.exists) {
      await guestDocRef.update(guestData);
    } else {
      await guestDocRef.set({
        ...guestData,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
  }

  Future<void> _assertCommuterAccount(firebase_auth.User firebaseUser) async {
    try {
      if (await _hasDriverProfile(firebaseUser)) {
        throw const AuthException(AuthErrorCode.driverAccountNotAllowed);
      }

      final commuterDoc = await _firestore
          .collection('commuters')
          .doc(firebaseUser.uid)
          .get();
      if (commuterDoc.exists) {
        final data = commuterDoc.data() ?? <String, dynamic>{};
        if (_isBlockedCommuterRole(data['role'])) {
          throw const AuthException(AuthErrorCode.notCommuterAccount);
        }
        if (_isBlockedCommuterStatus(data['status'])) {
          throw const AuthException(AuthErrorCode.commuterAccountBlocked);
        }
      }
    } on FirebaseException catch (e) {
      throw AuthException(
        AuthErrorCode.accountRoleCheckFailed,
        message: e.code,
      );
    }
  }

  Future<bool> _hasDriverProfile(firebase_auth.User firebaseUser) async {
    final email = firebaseUser.email?.trim().toLowerCase();
    final queries = <Future<QuerySnapshot<Map<String, dynamic>>>>[
      _firestore
          .collection('driver')
          .where('uid', isEqualTo: firebaseUser.uid)
          .limit(1)
          .get(),
      _firestore
          .collection('driver')
          .where('firebaseUid', isEqualTo: firebaseUser.uid)
          .limit(1)
          .get(),
    ];

    if (email != null && email.isNotEmpty) {
      queries.add(
        _firestore
            .collection('driver')
            .where('email', isEqualTo: email)
            .limit(1)
            .get(),
      );
    }

    final snapshots = await Future.wait(queries);
    return snapshots.any((snapshot) => snapshot.docs.isNotEmpty);
  }

  bool _isBlockedCommuterRole(dynamic role) {
    final normalizedRole = role?.toString().trim().toLowerCase();
    return normalizedRole == 'driver' ||
        normalizedRole == 'admin' ||
        normalizedRole == 'super_admin';
  }

  bool _isBlockedCommuterStatus(dynamic status) {
    final normalizedStatus = status?.toString().trim().toLowerCase();
    return normalizedStatus == 'blocked' || normalizedStatus == 'suspended';
  }

  bool _isRoleAccessError(Object error) {
    return error is AuthException && error.isRoleAccessError;
  }

  Future<User?> _fetchUserFromFirestore(String uid) async {
    try {
      final doc = await _firestore.collection('commuters').doc(uid).get();
      if (doc.exists) {
        final data = doc.data()!;
        if (_isBlockedCommuterRole(data['role'])) {
          throw const AuthException(AuthErrorCode.notCommuterAccount);
        }
        if (_isBlockedCommuterStatus(data['status'])) {
          throw const AuthException(AuthErrorCode.commuterAccountBlocked);
        }
        return User(
          id: uid,
          email: data['email'] ?? '',
          displayName: data['displayName'] ?? data['name'] ?? 'User',
          firstName: data['firstName'] ?? '',
          lastName: data['lastName'] ?? '',
          middleName: data['middleName'] ?? '',
          phoneNumber: data['phoneNumber'] ?? '',
          notificationPreferences: NotificationPreferences(
            arrivalAlerts: data['arrivalAlerts'] ?? true,
            crowdLevelChanges: data['crowdLevelChanges'] ?? false,
            routeUpdates: data['routeUpdates'] ?? true,
            alertRadiusMinutes: data['alertRadiusMinutes'] ?? 10,
          ),
          isGuest: false,
          mustChangePassword: data['mustChangePassword'] == true,
        );
      }
    } catch (e) {
      if (_isRoleAccessError(e)) {
        rethrow;
      }
      // Return null if error, will create new user
    }
    return null;
  }

  Future<void> _saveUserToFirestore(User user) async {
    await _firestore.collection('commuters').doc(user.id).set({
      'email': user.email,
      'id': user.id,
      'displayName': user.displayName,
      'name': user.displayName,
      'firstName': user.firstName,
      'lastName': user.lastName,
      'middleName': user.middleName,
      'phoneNumber': user.phoneNumber,
      'role': 'commuter',
      'status': 'active',
      'arrivalAlerts': user.notificationPreferences.arrivalAlerts,
      'crowdLevelChanges': user.notificationPreferences.crowdLevelChanges,
      'routeUpdates': user.notificationPreferences.routeUpdates,
      'alertRadiusMinutes': user.notificationPreferences.alertRadiusMinutes,
      'mustChangePassword': false,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _markTemporaryPasswordLoginConsumed(String uid) async {
    await _firestore.collection('commuters').doc(uid).set({
      'temporaryPasswordLoginConsumed': true,
      'temporaryPasswordLoginConsumedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  @override
  User? getCurrentUser() {
    return _currentUser;
  }

  @override
  Future<User> login(String email, String password) async {
    try {
      debugPrint('AuthRepositoryImpl: Attempting login for email: $email');
      final credential = await _firebaseAuth
          .signInWithEmailAndPassword(email: email, password: password)
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              throw const AuthException(AuthErrorCode.timeout);
            },
          );

      if (credential.user == null) {
        throw const AuthException(AuthErrorCode.loginFailed);
      }
      debugPrint(
        'AuthRepositoryImpl: Login successful for uid: ${credential.user!.uid}',
      );

      await _assertEmailVerified(credential.user!);

      try {
        final verifiedUser = _firebaseAuth.currentUser ?? credential.user!;
        await _assertCommuterAccount(verifiedUser);

        final commuterProfile = await _firestore
            .collection('commuters')
            .doc(verifiedUser.uid)
            .get();
        final profileData = commuterProfile.data() ?? <String, dynamic>{};
        if (profileData['mustChangePassword'] == true &&
            profileData['temporaryPasswordLoginConsumed'] == true) {
          throw const AuthException(AuthErrorCode.passwordChangeRequiresReset);
        }

        // Fetch user from Firestore
        _currentUser = await _fetchUserFromFirestore(verifiedUser.uid);

        if (_currentUser == null) {
          // Create new user if doesn't exist
          _currentUser = User(
            id: verifiedUser.uid,
            email: email,
            displayName: verifiedUser.displayName ?? email.split('@').first,
            notificationPreferences: const NotificationPreferences(),
            isGuest: false,
          );
          await _saveUserToFirestore(_currentUser!);
        }
        if (_currentUser!.mustChangePassword) {
          await _markTemporaryPasswordLoginConsumed(verifiedUser.uid);
        }
      } catch (e) {
        if (e is AuthException &&
            e.code == AuthErrorCode.passwordChangeRequiresReset) {
          rethrow;
        }
        if (_firebaseAuth.currentUser != null) {
          await _firebaseAuth.signOut();
        }
        rethrow;
      }

      _authStateController.add(_currentUser);
      return _currentUser!;
    } on firebase_auth.FirebaseAuthException catch (e) {
      debugPrint(
        'AuthRepositoryImpl: Login failed - code: ${e.code}, message: ${e.message}',
      );
      throw _handleFirebaseAuthError(e);
    } on TimeoutException {
      throw const AuthException(AuthErrorCode.timeout);
    }
  }

  @override
  Future<User> register({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    required String phoneNumber,
    String middleName = '',
  }) async {
    try {
      final credential = await _firebaseAuth
          .createUserWithEmailAndPassword(email: email, password: password)
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              throw const AuthException(AuthErrorCode.timeout);
            },
          );

      final displayName = _buildDisplayName(
        firstName: firstName,
        middleName: middleName,
        lastName: lastName,
      );

      // Update display name
      await credential.user?.updateDisplayName(displayName);

      // Create user in Firestore
      final newUser = User(
        id: credential.user!.uid,
        email: email,
        displayName: displayName,
        firstName: firstName,
        lastName: lastName,
        middleName: middleName,
        phoneNumber: phoneNumber,
        notificationPreferences: const NotificationPreferences(),
        isGuest: false,
      );

      await _saveUserToFirestore(newUser);
      await sendEmailVerification();
      _currentUser = newUser;
      _authStateController.add(_currentUser);
      return _currentUser!;
    } on firebase_auth.FirebaseAuthException catch (e) {
      throw _handleFirebaseAuthError(e);
    } on TimeoutException {
      throw const AuthException(AuthErrorCode.timeout);
    }
  }

  String _buildDisplayName({
    required String firstName,
    required String lastName,
    required String middleName,
  }) {
    return [
      firstName.trim(),
      if (middleName.trim().isNotEmpty) middleName.trim(),
      lastName.trim(),
    ].join(' ');
  }

  Future<void> _assertEmailVerified(firebase_auth.User firebaseUser) async {
    await firebaseUser.reload();
    final refreshedUser = _firebaseAuth.currentUser ?? firebaseUser;
    if (refreshedUser.emailVerified) {
      return;
    }

    try {
      await refreshedUser.sendEmailVerification();
    } on firebase_auth.FirebaseAuthException {
      // Keep the login error focused on verification even if Firebase throttles resend.
    }
    throw const AuthException(AuthErrorCode.emailNotVerified);
  }

  @override
  Future<void> sendEmailVerification() async {
    try {
      final firebaseUser = _firebaseAuth.currentUser;
      if (firebaseUser == null) {
        throw const AuthException(AuthErrorCode.noUserToVerify);
      }

      await firebaseUser.reload();
      final refreshedUser = _firebaseAuth.currentUser;
      if (refreshedUser == null) {
        throw const AuthException(AuthErrorCode.noUserToVerify);
      }
      if (!refreshedUser.emailVerified) {
        await refreshedUser.sendEmailVerification();
      }
    } on firebase_auth.FirebaseAuthException catch (e) {
      throw _handleFirebaseAuthError(e);
    }
  }

  @override
  Future<bool> reloadAndCheckEmailVerified() async {
    try {
      final firebaseUser = _firebaseAuth.currentUser;
      if (firebaseUser == null) {
        throw const AuthException(AuthErrorCode.noUserToVerify);
      }

      await firebaseUser.reload();
      final refreshedUser = _firebaseAuth.currentUser;
      if (refreshedUser == null) {
        throw const AuthException(AuthErrorCode.noUserToVerify);
      }
      if (!refreshedUser.emailVerified) {
        return false;
      }

      await refreshedUser.getIdToken(true);
      await _assertCommuterAccount(refreshedUser);
      await _firestore.collection('commuters').doc(refreshedUser.uid).set({
        'emailVerified': true,
        'emailVerifiedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      _currentUser = await _fetchUserFromFirestore(refreshedUser.uid);
      if (_currentUser == null) {
        _currentUser = User(
          id: refreshedUser.uid,
          email: refreshedUser.email ?? '',
          displayName:
              refreshedUser.displayName ??
              refreshedUser.email?.split('@').first ??
              'User',
          notificationPreferences: const NotificationPreferences(),
          isGuest: false,
        );
        await _saveUserToFirestore(_currentUser!);
      }
      if (_currentUser!.mustChangePassword) {
        await _markTemporaryPasswordLoginConsumed(refreshedUser.uid);
      }

      _authStateController.add(_currentUser);
      return true;
    } on firebase_auth.FirebaseAuthException catch (e) {
      throw _handleFirebaseAuthError(e);
    }
  }

  AuthException _handleFirebaseAuthError(
    firebase_auth.FirebaseAuthException e,
  ) {
    switch (e.code) {
      case AuthErrorCode.emailAlreadyInUse:
      case AuthErrorCode.invalidEmail:
      case AuthErrorCode.weakPassword:
      case AuthErrorCode.wrongPassword:
      case AuthErrorCode.userNotFound:
      case AuthErrorCode.invalidCredential:
      case AuthErrorCode.invalidLoginCredentials:
      case AuthErrorCode.networkRequestFailed:
      case AuthErrorCode.tooManyRequests:
      case AuthErrorCode.userDisabled:
      case AuthErrorCode.timeout:
      case AuthErrorCode.operationNotAllowed:
      case AuthErrorCode.internalError:
        return AuthException(e.code, message: e.message);
      default:
        return AuthException(
          AuthErrorCode.authError,
          message: e.message ?? e.code,
        );
    }
  }

  @override
  Future<User> completeRequiredPasswordChange(String newPassword) async {
    try {
      final firebaseUser = _firebaseAuth.currentUser;
      if (firebaseUser == null || firebaseUser.isAnonymous) {
        throw const AuthException(AuthErrorCode.noUserToVerify);
      }

      await firebaseUser
          .updatePassword(newPassword)
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              throw const AuthException(AuthErrorCode.timeout);
            },
          );
      await _firestore.collection('commuters').doc(firebaseUser.uid).set({
        'mustChangePassword': false,
        'passwordChangedAt': FieldValue.serverTimestamp(),
        'temporaryPasswordClearedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      _currentUser =
          await _fetchUserFromFirestore(firebaseUser.uid) ??
          _currentUser?.copyWith(mustChangePassword: false) ??
          User(
            id: firebaseUser.uid,
            email: firebaseUser.email ?? '',
            displayName:
                firebaseUser.displayName ??
                firebaseUser.email?.split('@').first ??
                'User',
            notificationPreferences: const NotificationPreferences(),
            isGuest: false,
            mustChangePassword: false,
          );
      _currentUser = _currentUser!.copyWith(mustChangePassword: false);
      _authStateController.add(_currentUser);
      return _currentUser!;
    } on firebase_auth.FirebaseAuthException catch (e) {
      throw _handleFirebaseAuthError(e);
    } on TimeoutException {
      throw const AuthException(AuthErrorCode.timeout);
    }
  }

  @override
  Future<User> loginAsGuest() async {
    try {
      debugPrint('AuthRepositoryImpl: Guest Mode sign-in requested.');

      var firebaseUser = _firebaseAuth.currentUser;

      if (firebaseUser != null && !firebaseUser.isAnonymous) {
        debugPrint(
          'AuthRepositoryImpl: Signing out non-guest Firebase user before Guest Mode.',
        );
        await AppSessionService.stopCommuterSession();
        await _firebaseAuth.signOut();
        firebaseUser = null;
      }

      if (firebaseUser == null) {
        final credential = await _firebaseAuth.signInAnonymously().timeout(
          const Duration(seconds: 30),
          onTimeout: () {
            throw const AuthException(AuthErrorCode.timeout);
          },
        );
        firebaseUser = credential.user;
      }

      if (firebaseUser == null) {
        throw const AuthException(AuthErrorCode.loginFailed);
      }

      await _createOrUpdateGuestDocument(firebaseUser);

      _currentUser = _guestUserFromFirebaseUser(firebaseUser);
      debugPrint(
        'AuthRepositoryImpl: Guest Mode FirebaseAuth ready. '
        'uid=${firebaseUser.uid}, isAnonymous=${firebaseUser.isAnonymous}',
      );

      _authStateController.add(_currentUser);
      return _currentUser!;
    } on firebase_auth.FirebaseAuthException catch (e) {
      debugPrint(
        'AuthRepositoryImpl: Guest anonymous sign-in failed. '
        'code=${e.code}, message=${e.message}',
      );
      throw _handleFirebaseAuthError(e);
    } on TimeoutException {
      debugPrint('AuthRepositoryImpl: Guest anonymous sign-in timed out.');
      throw const AuthException(AuthErrorCode.timeout);
    }
  }

  @override
  Future<void> logout() async {
    await AppSessionService.stopCommuterSession();
    await _firebaseAuth.signOut();
    _currentUser = User.guest();
    _authStateController.add(_currentUser);
  }

  @override
  bool isLoggedIn() {
    return _currentUser != null && !_currentUser!.isGuest;
  }

  @override
  bool isGuest() {
    return _firebaseAuth.currentUser?.isAnonymous == true ||
        _currentUser == null ||
        _currentUser!.isGuest;
  }

  @override
  Stream<User?> watchAuthState() {
    return _authStateController.stream;
  }

  @override
  Future<User> updateProfile(User user) async {
    try {
      // Update in Firestore
      await _firestore.collection('commuters').doc(user.id).update({
        'displayName': user.displayName,
        'name': user.displayName,
        'firstName': user.firstName,
        'lastName': user.lastName,
        'middleName': user.middleName,
        'phoneNumber': user.phoneNumber,
        'arrivalAlerts': user.notificationPreferences.arrivalAlerts,
        'crowdLevelChanges': user.notificationPreferences.crowdLevelChanges,
        'routeUpdates': user.notificationPreferences.routeUpdates,
        'alertRadiusMinutes': user.notificationPreferences.alertRadiusMinutes,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      _currentUser = user;
      _authStateController.add(_currentUser);
      return _currentUser!;
    } catch (e) {
      throw Exception('Failed to update profile: $e');
    }
  }

  @override
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      final normalizedEmail = email.trim().toLowerCase();
      final currentFirebaseUser = _firebaseAuth.currentUser;
      await _firebaseAuth
          .sendPasswordResetEmail(email: normalizedEmail)
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              throw const AuthException(AuthErrorCode.timeout);
            },
          );
      if (currentFirebaseUser != null &&
          !currentFirebaseUser.isAnonymous &&
          currentFirebaseUser.email?.trim().toLowerCase() == normalizedEmail) {
        await _firestore
            .collection('commuters')
            .doc(currentFirebaseUser.uid)
            .set({
              'passwordResetRequestedAt': FieldValue.serverTimestamp(),
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
        await _firebaseAuth.signOut();
        _currentUser = User.guest();
        _authStateController.add(_currentUser);
      }
    } on firebase_auth.FirebaseAuthException catch (e) {
      throw _handleFirebaseAuthError(e);
    } on TimeoutException {
      throw const AuthException(AuthErrorCode.timeout);
    }
  }

  Future<void> dispose() async {
    await _firebaseAuthSubscription.cancel();
    _authStateController.close();
  }
}
