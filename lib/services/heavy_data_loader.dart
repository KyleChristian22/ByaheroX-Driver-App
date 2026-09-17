import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'firestore_service.dart';

class DriverDataResult {
  final String? driverName;
  final String? driverId;
  final String? jeepneyId;
  final String? plateNumber;
  final String? routeName;
  final int? capacity;
  final String? scheduleTime;
  final String? error;

  DriverDataResult({
    this.driverName,
    this.driverId,
    this.jeepneyId,
    this.plateNumber,
    this.routeName,
    this.capacity,
    this.scheduleTime,
    this.error,
  });
}

class HeavyDataLoader {
  static Future<DriverDataResult> loadDriverDataInBackground(
      String firebaseUid) async {
    try {
      final db = FirebaseFirestore.instance;
      final auth = FirebaseAuth.instance;

      debugPrint('[HeavyDataLoader] Starting with firebaseUid: $firebaseUid');

      if (firebaseUid.isEmpty) {
        return DriverDataResult(error: 'No user UID provided');
      }

      // Get current driver's email to find the correct document ID in 'driver' collection
      final currentEmail = auth.currentUser?.email?.toLowerCase();
      debugPrint('[HeavyDataLoader] Current email: $currentEmail');
      DocumentSnapshot driverDoc;

      if (currentEmail != null) {
        // Query by email to get the document ID (Admin uses custom IDs like 'DRV001')
        final driverDocs = await db
            .collection('driver')
            .where('email', isEqualTo: currentEmail)
            .limit(1)
            .get();

        debugPrint(
            '[HeavyDataLoader] Query by email, found: ${driverDocs.docs.length} docs');

        if (driverDocs.docs.isEmpty) {
          debugPrint(
              '[HeavyDataLoader] No driver found by email, trying uid field');
          // Fallback: try querying by uid field
          final uidQuery = await db
              .collection('driver')
              .where('uid', isEqualTo: firebaseUid)
              .limit(1)
              .get();

          debugPrint(
              '[HeavyDataLoader] Query by uid, found: ${uidQuery.docs.length} docs');

          if (uidQuery.docs.isEmpty) {
            return DriverDataResult(error: 'Driver profile not found');
          }
          driverDoc = uidQuery.docs.first;
        } else {
          driverDoc = driverDocs.docs.first;
          debugPrint('[HeavyDataLoader] Found driver doc ID: ${driverDoc.id}');
        }
      } else {
        // Fallback: try direct document access with firebaseUid
        driverDoc = await db.collection('driver').doc(firebaseUid).get();
        if (!driverDoc.exists) {
          return DriverDataResult(error: 'Driver profile not found');
        }
      }

      final driverData = driverDoc.data() as Map<String, dynamic>;
      debugPrint('[HeavyDataLoader] Driver data: $driverData');
      final driverName = driverData['name'] ?? 'Driver';
      final storedDriverId = driverData['id']?.toString().trim() ?? '';
      final driverIdValue =
          driverDoc.id.trim().isNotEmpty ? driverDoc.id : storedDriverId;
      debugPrint('[HeavyDataLoader] driverDocId: $driverIdValue');

      // FIRST: Check today's daily assignment from trip_schedule_driver_assignments
      final todayAssignment =
          await FirestoreService.getTodayDriverAssignment(driverDoc.id).timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          debugPrint('[HeavyDataLoader] getTodayDriverAssignment timed out');
          return null;
        },
      );

      String? jeepneyId;
      String? plateNumber;
      String? scheduleTime;

      if (todayAssignment != null) {
        jeepneyId = todayAssignment['jeepneyId']?.toString();
        plateNumber = todayAssignment['plateNumber']?.toString();
        scheduleTime = todayAssignment['scheduleTime']?.toString();
        debugPrint(
          '[HeavyDataLoader] Using daily assignment: '
          'jeepneyId=$jeepneyId, plateNumber=$plateNumber, '
          'scheduleTime=$scheduleTime',
        );
      }

      // SECOND: Fall back to persistent assignedJeepneyId on driver doc
      if (jeepneyId == null || jeepneyId.isEmpty) {
        String? assignedJeepneyId;
        final rawId = driverData['assignedJeepneyId'];
        if (rawId != null) {
          assignedJeepneyId = rawId.toString().trim();
          if (assignedJeepneyId.isEmpty ||
              assignedJeepneyId.toLowerCase() == 'null') {
            assignedJeepneyId = null;
          }
        }
        if (assignedJeepneyId == null || assignedJeepneyId.isEmpty) {
          final rawId2 = driverData['assignedJeepId'];
          if (rawId2 != null) {
            assignedJeepneyId = rawId2.toString().trim();
            if (assignedJeepneyId.isEmpty ||
                assignedJeepneyId.toLowerCase() == 'null') {
              assignedJeepneyId = null;
            }
          }
        }
        debugPrint(
          '[HeavyDataLoader] No daily assignment, '
          'checking persistent assignedJeepneyId: $assignedJeepneyId',
        );

        if (assignedJeepneyId != null && assignedJeepneyId.isNotEmpty) {
          jeepneyId = assignedJeepneyId;
        }
      }

      // Try to fetch scheduleTime from trip_schedules if not already set
      if (jeepneyId != null &&
          jeepneyId.isNotEmpty &&
          (scheduleTime == null || scheduleTime.isEmpty)) {
        try {
          final tripSchedule =
              await FirestoreService.getTodayTripSchedule(jeepneyId);
          if (tripSchedule != null) {
            scheduleTime = tripSchedule['scheduleTime']?.toString();
            debugPrint(
              '[HeavyDataLoader] Got scheduleTime from trip_schedules: $scheduleTime',
            );
          }
        } catch (e) {
          debugPrint('[HeavyDataLoader] Error fetching trip schedule: $e');
        }
      }

      if (jeepneyId == null || jeepneyId.isEmpty) {
        debugPrint('[HeavyDataLoader] No jeepney assigned');
        return DriverDataResult(
          driverName: driverName,
          driverId: driverIdValue,
          scheduleTime: scheduleTime,
        );
      }

      final jeepneyDoc = await db.collection('jeeps').doc(jeepneyId).get();
      if (!jeepneyDoc.exists) {
        return DriverDataResult(
          driverName: driverName,
          driverId: driverIdValue,
          jeepneyId: jeepneyId,
          plateNumber: plateNumber,
          scheduleTime: scheduleTime,
        );
      }

      final jeepneyData = jeepneyDoc.data()!;
      final capacity =
          jeepneyData['capacity'] ?? jeepneyData['seatingCapacity'] ?? 0;
      final routeId = jeepneyData['routeId'] ?? '';
      String? routeName;

      if (routeId.isNotEmpty) {
        final routeDoc = await db.collection('routes').doc(routeId).get();
        if (routeDoc.exists) {
          final routeData = routeDoc.data() as Map<String, dynamic>;
          final start = routeData['startTerminal'] ?? '';
          final end = routeData['endTerminal'] ?? '';
          routeName = '$start → $end';
        }
      }

      // Use plateNumber from daily assignment if available, otherwise from jeepney doc
      plateNumber ??= jeepneyData['plateNumber'] ?? 'N/A';

      return DriverDataResult(
        driverName: driverName,
        driverId: driverIdValue,
        jeepneyId: jeepneyId,
        plateNumber: plateNumber,
        routeName: routeName,
        capacity:
            capacity is int ? capacity : int.tryParse(capacity.toString()) ?? 0,
        scheduleTime: scheduleTime,
      );
    } catch (e) {
      debugPrint('[HeavyDataLoader] Error: $e');
      return DriverDataResult(
        error: FirestoreService.userFriendlyMessageForError(e),
      );
    }
  }
}
