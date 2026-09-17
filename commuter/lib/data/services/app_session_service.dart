import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class AppSessionService {
  static const String _appSessionsCollection = 'app_sessions';
  static const Duration _staleSessionThreshold = Duration(minutes: 5);

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  static Future<void> startOrResumeCommuterSession() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      final commuterId = await _resolveCommuterId();
      if (commuterId == null || commuterId.isEmpty) return;

      final sessionRef = _firestore
          .collection(_appSessionsCollection)
          .doc('commuter_$commuterId');
      final sessionSnapshot = await sessionRef.get();
      final sessionData = sessionSnapshot.data();
      final lastSeenAt = _toDateTime(sessionData?['lastSeenAt']);
      final shouldRestart =
          !sessionSnapshot.exists ||
          sessionData?['isActive'] != true ||
          lastSeenAt == null ||
          DateTime.now().difference(lastSeenAt) > _staleSessionThreshold;

      final payload = <String, dynamic>{
        'role': 'commuter',
        'userId': commuterId,
        'authUid': user.uid,
        'email': user.email ?? '',
        'displayName': user.displayName?.trim().isNotEmpty == true
            ? user.displayName
            : '',
        'isActive': true,
        'lastSeenAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (shouldRestart) {
        payload['startedAt'] = FieldValue.serverTimestamp();
        payload['endedAt'] = FieldValue.delete();
      }

      await sessionRef.set(payload, SetOptions(merge: true));
    } catch (error) {
      debugPrint('Failed to start commuter app session: $error');
    }
  }

  static Future<void> heartbeatCommuterSession() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      final commuterId = await _resolveCommuterId();
      if (commuterId == null || commuterId.isEmpty) return;

      await _firestore
          .collection(_appSessionsCollection)
          .doc('commuter_$commuterId')
          .set({
            'role': 'commuter',
            'userId': commuterId,
            'authUid': user.uid,
            'email': user.email ?? '',
            'isActive': true,
            'lastSeenAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
    } catch (error) {
      debugPrint('Failed to refresh commuter app session: $error');
    }
  }

  static Future<void> stopCommuterSession() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      final commuterId = await _resolveCommuterId();
      if (commuterId == null || commuterId.isEmpty) return;

      await _firestore
          .collection(_appSessionsCollection)
          .doc('commuter_$commuterId')
          .set({
            'role': 'commuter',
            'userId': commuterId,
            'authUid': user.uid,
            'email': user.email ?? '',
            'isActive': false,
            'lastSeenAt': FieldValue.serverTimestamp(),
            'endedAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
    } catch (error) {
      debugPrint('Failed to stop commuter app session: $error');
    }
  }

  static Future<String?> _resolveCommuterId() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return null;

      final directSnapshot = await _firestore
          .collection('commuters')
          .doc(user.uid)
          .get();
      if (directSnapshot.exists) {
        return directSnapshot.id;
      }

      final uidQuery = await _firestore
          .collection('commuters')
          .where('uid', isEqualTo: user.uid)
          .limit(1)
          .get();
      if (uidQuery.docs.isNotEmpty) {
        return uidQuery.docs.first.id;
      }

      final email = user.email?.trim().toLowerCase();
      if (email != null && email.isNotEmpty) {
        final emailQuery = await _firestore
            .collection('commuters')
            .where('email', isEqualTo: email)
            .limit(1)
            .get();
        if (emailQuery.docs.isNotEmpty) {
          return emailQuery.docs.first.id;
        }
      }

      return user.uid;
    } catch (error) {
      debugPrint('Failed to resolve commuter id for analytics: $error');
      return null;
    }
  }

  static DateTime? _toDateTime(Object? value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);

    if (value is Map) {
      final seconds = value['seconds'] ?? value['_seconds'];
      final nanoseconds = value['nanoseconds'] ?? value['_nanoseconds'] ?? 0;
      if (seconds is num) {
        return DateTime.fromMillisecondsSinceEpoch(
          seconds.toInt() * 1000 + ((nanoseconds as num) / 1000000).floor(),
        );
      }
    }

    return null;
  }
}
