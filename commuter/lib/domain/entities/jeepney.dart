import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

/// Crowd level enum representing jeepney passenger density.
///
/// NOTE:
/// The enum value is still named `maliwag` to avoid breaking existing code.
/// But display/string values are corrected to "maluwag".
enum CrowdLevel {
  maliwag, // Green - Empty/seats available
  sakto, // Yellow - Moderate crowd
  puno, // Red - Full/crowded
}

/// Jeepney entity representing a jeepney on the route.
///
/// For live tracking, this entity is usually created from:
///
/// Firestore:
/// locations/{jeepneyId}
///
/// Expected live location fields:
/// - jeepneyId
/// - plateNumber
/// - routeId
/// - lat
/// - lng
/// - speedMps
/// - crowdStatus
/// - isOnTrip
/// - isOnline
/// - originTerminal
/// - destinationTerminal
/// - timestamp / updatedAt
class Jeepney extends Equatable {
  final String id;
  final String plateNumber;
  final String routeId;
  final double latitude;
  final double longitude;

  /// Speed should be stored in km/h for UI display.
  ///
  /// If data comes from Firestore `speedMps`, it is converted to km/h.
  final double speed;

  final CrowdLevel crowdLevel;
  final int estimatedArrivalMinutes;
  final DateTime lastUpdated;

  /// For commuter app visibility:
  /// true means the jeepney is currently on trip and should be visible.
  final bool isActive;

  final String? originTerminal;
  final String? destinationTerminal;
  final String? driverName;
  final int passengerCount;
  final int maxCapacity;
  final String? scheduleTime;
  final DateTime? scheduledAt;

  const Jeepney({
    required this.id,
    required this.plateNumber,
    required this.routeId,
    required this.latitude,
    required this.longitude,
    required this.speed,
    required this.crowdLevel,
    required this.estimatedArrivalMinutes,
    required this.lastUpdated,
    required this.isActive,
    this.originTerminal,
    this.destinationTerminal,
    this.driverName,
    this.passengerCount = 0,
    this.maxCapacity = 0,
    this.scheduleTime,
    this.scheduledAt,
  });

  /// Create a copy with modified fields.
  Jeepney copyWith({
    String? id,
    String? plateNumber,
    String? routeId,
    double? latitude,
    double? longitude,
    double? speed,
    CrowdLevel? crowdLevel,
    int? estimatedArrivalMinutes,
    DateTime? lastUpdated,
    bool? isActive,
    String? originTerminal,
    String? destinationTerminal,
    String? driverName,
    int? passengerCount,
    int? maxCapacity,
    String? scheduleTime,
    DateTime? scheduledAt,
  }) {
    return Jeepney(
      id: id ?? this.id,
      plateNumber: plateNumber ?? this.plateNumber,
      routeId: routeId ?? this.routeId,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      speed: speed ?? this.speed,
      crowdLevel: crowdLevel ?? this.crowdLevel,
      estimatedArrivalMinutes:
          estimatedArrivalMinutes ?? this.estimatedArrivalMinutes,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      isActive: isActive ?? this.isActive,
      originTerminal: originTerminal ?? this.originTerminal,
      destinationTerminal: destinationTerminal ?? this.destinationTerminal,
      driverName: driverName ?? this.driverName,
      passengerCount: passengerCount ?? this.passengerCount,
      maxCapacity: maxCapacity ?? this.maxCapacity,
      scheduleTime: scheduleTime ?? this.scheduleTime,
      scheduledAt: scheduledAt ?? this.scheduledAt,
    );
  }

  /// Returns true if the jeepney has usable map coordinates.
  bool get hasValidLocation {
    return latitude.isFinite &&
        longitude.isFinite &&
        latitude >= -90 &&
        latitude <= 90 &&
        longitude >= -180 &&
        longitude <= 180 &&
        !(latitude == 0 && longitude == 0);
  }

  /// Get crowd level as Firestore/string value.
  String get crowdLevelString {
    switch (crowdLevel) {
      case CrowdLevel.maliwag:
        return 'maluwag';
      case CrowdLevel.sakto:
        return 'sakto';
      case CrowdLevel.puno:
        return 'puno';
    }
  }

  /// Get crowd level display name.
  String get crowdLevelDisplayName {
    switch (crowdLevel) {
      case CrowdLevel.maliwag:
        return 'Maluwag';
      case CrowdLevel.sakto:
        return 'Sakto';
      case CrowdLevel.puno:
        return 'Puno';
    }
  }

  /// Check if jeepney is arriving soon.
  bool get isArrivingSoon => estimatedArrivalMinutes <= 5;

  /// Get abbreviated plate number for marker display.
  String get abbreviatedPlateNumber {
    final value = plateNumber.trim();

    if (value.isEmpty) {
      return id.length <= 4 ? id : id.substring(0, 4);
    }

    if (value.length <= 4) {
      return value;
    }

    return value.substring(0, 4);
  }

  /// Create Jeepney from location data.
  ///
  /// This is for real-time tracking from Driver app.
  ///
  /// Compatible with your Firestore screenshot:
  ///
  /// locations/JEEP001
  /// {
  ///   crowdStatus: "sakto",
  ///   destinationTerminal: "Sta.Cruz Terminal",
  ///   driverDocId: "DRV001",
  ///   driverEmail: "...",
  ///   driverUid: "...",
  ///   heading: "...",
  ///   isOnTrip: true,
  ///   isOnline: true,
  ///   jeepneyId: "JEEP001",
  ///   lat: 14.273055999999993,
  ///   lng: 121.40314499999998,
  ///   originTerminal: "Lucban Terminal",
  ///   routeId: "ROUTE001",
  ///   speedMps: 3,
  ///   timestamp: Timestamp,
  ///   updatedAt: Timestamp
  /// }
  factory Jeepney.fromLocation(DocumentSnapshot doc) {
    final data = _documentData(doc);

    final jeepneyId = _readString(data, [
      'jeepneyId',
      'jeepneyDocId',
      'vehicleId',
      'vehicleDocId',
    ], defaultValue: doc.id);

    final plateNumber = _readString(data, [
      'plateNumber',
      'plate_number',
      'plateNo',
      'plate_no',
      'plate',
      'vehiclePlateNumber',
      'vehiclePlateNo',
      'vehiclePlate',
      'jeepneyPlateNumber',
      'jeepneyPlateNo',
      'bodyNumber',
    ]);

    final latitude = _readDouble(data, [
      'lat',
      'latitude',
      '_latitude',
    ], defaultValue: 0.0);

    final longitude = _readDouble(data, [
      'lng',
      'longitude',
      'lon',
      'long',
      '_longitude',
    ], defaultValue: 0.0);

    final speedKmh = _readSpeedKmh(data);

    final passengerCount = _readInt(data, [
      'passengerCount',
      'currentPassengerCount',
      'currentPassengers',
      'passengers',
    ], defaultValue: 0);
    final maxCapacity = _readInt(data, [
      'maxCapacity',
      'capacity',
      'seatingCapacity',
      'maxPassengers',
    ], defaultValue: 0);
    final crowdStatus = _readString(data, [
      'crowdStatus',
      'crowdLevel',
      'crowdingLevel',
      'capacityStatus',
    ], defaultValue: '');

    final isOnTrip = _readBool(data, [
      'isOnTrip',
      'onTrip',
      'isActive',
      'active',
    ], defaultValue: false);

    final isOnline = _readBool(data, [
      'isOnline',
      'online',
    ], defaultValue: true);
    final scheduledAt = _readNullableDateTime(data, [
      'scheduledAt',
      'departureAt',
    ]);
    final scheduledVisible = _isScheduledVisible(data, scheduledAt);

    final hasValidCoordinates =
        latitude.isFinite &&
        longitude.isFinite &&
        latitude >= -90 &&
        latitude <= 90 &&
        longitude >= -180 &&
        longitude <= 180 &&
        !(latitude == 0 && longitude == 0);
    final hasAssignedDriver = _hasAssignedDriver(data);

    return Jeepney(
      id: jeepneyId,
      plateNumber: plateNumber,
      routeId: _readString(data, ['routeId', 'routeDocId']),
      latitude: latitude,
      longitude: longitude,
      speed: speedKmh,
      crowdLevel: passengerCount > 0
          ? _crowdLevelFromPassengerCount(passengerCount, maxCapacity)
          : _crowdLevelFromStatus(crowdStatus),
      estimatedArrivalMinutes: _readInt(data, [
        'estimatedArrivalMinutes',
        'etaMinutes',
        'eta',
      ], defaultValue: 0),
      lastUpdated: _readDateTime(data, [
        'locationUpdatedAt',
        'updatedAt',
        'timestamp',
        'lastUpdated',
        'lastLocationUpdate',
      ], defaultValue: DateTime.now()),
      isActive:
          ((isOnTrip && isOnline) || scheduledVisible) &&
          hasValidCoordinates &&
          hasAssignedDriver,
      originTerminal: _readNullableString(data, [
        'originTerminal',
        'origin',
        'from',
      ]),
      destinationTerminal: _readNullableString(data, [
        'destinationTerminal',
        'destination',
        'to',
      ]),
      driverName: _readDriverName(data),
      passengerCount: passengerCount,
      maxCapacity: maxCapacity,
      scheduleTime: _readNullableString(data, [
        'scheduleTime',
        'departureTime',
        'tripTime',
      ]),
      scheduledAt: scheduledAt,
    );
  }

  /// Create Jeepney from Map data.
  ///
  /// Useful if you want to reuse the mapper outside Firestore DocumentSnapshot.
  factory Jeepney.fromMap(Map<String, dynamic> data, {String? documentId}) {
    final fakeDocumentId = documentId ?? '';

    final jeepneyId = _readString(data, [
      'jeepneyId',
      'jeepneyDocId',
      'vehicleId',
      'vehicleDocId',
    ], defaultValue: fakeDocumentId);

    final plateNumber = _readString(data, [
      'plateNumber',
      'plate_number',
      'plateNo',
      'plate_no',
      'plate',
      'vehiclePlateNumber',
      'vehiclePlateNo',
      'vehiclePlate',
      'jeepneyPlateNumber',
      'jeepneyPlateNo',
      'bodyNumber',
    ]);

    final latitude = _readDouble(data, [
      'lat',
      'latitude',
      '_latitude',
    ], defaultValue: 0.0);

    final longitude = _readDouble(data, [
      'lng',
      'longitude',
      'lon',
      'long',
      '_longitude',
    ], defaultValue: 0.0);

    final isOnTrip = _readBool(data, [
      'isOnTrip',
      'onTrip',
      'isActive',
      'active',
    ], defaultValue: false);

    final isOnline = _readBool(data, [
      'isOnline',
      'online',
    ], defaultValue: true);
    final scheduledAt = _readNullableDateTime(data, [
      'scheduledAt',
      'departureAt',
    ]);
    final scheduledVisible = _isScheduledVisible(data, scheduledAt);

    final hasValidCoordinates =
        latitude.isFinite &&
        longitude.isFinite &&
        latitude >= -90 &&
        latitude <= 90 &&
        longitude >= -180 &&
        longitude <= 180 &&
        !(latitude == 0 && longitude == 0);
    final hasAssignedDriver = _hasAssignedDriver(data);

    return Jeepney(
      id: jeepneyId,
      plateNumber: plateNumber,
      routeId: _readString(data, ['routeId', 'routeDocId']),
      latitude: latitude,
      longitude: longitude,
      speed: _readSpeedKmh(data),
      crowdLevel: _crowdLevelFromPassengerCount(
        _readInt(data, [
          'passengerCount',
          'currentPassengerCount',
          'currentPassengers',
          'passengers',
        ], defaultValue: 0),
        _readInt(data, [
          'maxCapacity',
          'capacity',
          'seatingCapacity',
          'maxPassengers',
        ], defaultValue: 0),
      ),
      estimatedArrivalMinutes: _readInt(data, [
        'estimatedArrivalMinutes',
        'etaMinutes',
        'eta',
      ], defaultValue: 0),
      lastUpdated: _readDateTime(data, [
        'locationUpdatedAt',
        'updatedAt',
        'timestamp',
        'lastUpdated',
        'lastLocationUpdate',
      ], defaultValue: DateTime.now()),
      isActive:
          ((isOnTrip && isOnline) || scheduledVisible) &&
          hasValidCoordinates &&
          hasAssignedDriver,
      originTerminal: _readNullableString(data, [
        'originTerminal',
        'origin',
        'from',
      ]),
      destinationTerminal: _readNullableString(data, [
        'destinationTerminal',
        'destination',
        'to',
      ]),
      driverName: _readDriverName(data),
      passengerCount: _readInt(data, [
        'passengerCount',
        'currentPassengerCount',
        'currentPassengers',
        'passengers',
      ], defaultValue: 0),
      maxCapacity: _readInt(data, [
        'maxCapacity',
        'capacity',
        'seatingCapacity',
        'maxPassengers',
      ], defaultValue: 0),
      scheduleTime: _readNullableString(data, [
        'scheduleTime',
        'departureTime',
        'tripTime',
      ]),
      scheduledAt: scheduledAt,
    );
  }

  /// Convert Jeepney to Map.
  ///
  /// Useful for debugging or saving static jeepney info.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'jeepneyId': id,
      'plateNumber': plateNumber,
      'routeId': routeId,
      'lat': latitude,
      'lng': longitude,
      'speedKmh': speed,
      'crowdStatus': crowdLevelString,
      'estimatedArrivalMinutes': estimatedArrivalMinutes,
      'lastUpdated': Timestamp.fromDate(lastUpdated),
      'isActive': isActive,
      'isOnTrip': isActive,
      'originTerminal': originTerminal,
      'destinationTerminal': destinationTerminal,
      'driverName': driverName,
      'passengerCount': passengerCount,
      'maxCapacity': maxCapacity,
      'scheduleTime': scheduleTime,
      'scheduledAt': scheduledAt == null
          ? null
          : Timestamp.fromDate(scheduledAt!),
    };
  }

  /// Determine crowd level from status string set by driver.
  static CrowdLevel _crowdLevelFromStatus(String status) {
    final normalized = status.trim().toLowerCase();

    switch (normalized) {
      case 'maluwag':
      case 'maliwag':
      case 'available':
      case 'light':
      case 'low':
      case 'empty':
        return CrowdLevel.maliwag;

      case 'sakto':
      case 'moderate':
      case 'medium':
      case 'normal':
        return CrowdLevel.sakto;

      case 'puno':
      case 'full':
      case 'high':
      case 'crowded':
        return CrowdLevel.puno;

      default:
        return CrowdLevel.sakto;
    }
  }

  static Map<String, dynamic> _documentData(DocumentSnapshot doc) {
    final rawData = doc.data();

    if (rawData is Map<String, dynamic>) {
      return rawData;
    }

    if (rawData is Map) {
      return rawData.map((key, value) => MapEntry(key.toString(), value));
    }

    return <String, dynamic>{};
  }

  static String _readString(
    Map<String, dynamic> data,
    List<String> keys, {
    String defaultValue = '',
  }) {
    for (final key in keys) {
      final value = data[key];

      if (value == null) {
        continue;
      }

      final text = value.toString().trim();

      if (text.isNotEmpty) {
        return text;
      }
    }

    return defaultValue;
  }

  static String? _readDriverName(Map<String, dynamic> data) {
    final name = _readNullableString(data, [
      'driverName',
      'driverFullName',
      'assignedDriverName',
      'driverDisplayName',
    ]);
    if (name != null) return name;

    final email = _readNullableString(data, ['driverEmail', 'email']);
    if (email != null) {
      final atIndex = email.indexOf('@');
      if (atIndex > 0) {
        final derived = email.substring(0, atIndex);
        return derived[0].toUpperCase() + derived.substring(1);
      }
      return email;
    }

    return null;
  }

  static bool _hasAssignedDriver(Map<String, dynamic> data) {
    return _readString(data, [
      'driverId',
      'assignedDriver',
      'assignedDriverId',
      'driverDocId',
      'driverUid',
      'uid',
    ]).isNotEmpty;
  }

  static String? _readNullableString(
    Map<String, dynamic> data,
    List<String> keys,
  ) {
    final value = _readString(data, keys);

    if (value.trim().isEmpty) {
      return null;
    }

    return value;
  }

  static int _readInt(
    Map<String, dynamic> data,
    List<String> keys, {
    required int defaultValue,
  }) {
    for (final key in keys) {
      final value = data[key];

      if (value == null) {
        continue;
      }

      if (value is int) {
        return value;
      }

      if (value is num) {
        return value.toInt();
      }

      if (value is String) {
        final parsed = int.tryParse(value.trim());

        if (parsed != null) {
          return parsed;
        }
      }
    }

    return defaultValue;
  }

  static bool _readBool(
    Map<String, dynamic> data,
    List<String> keys, {
    required bool defaultValue,
  }) {
    for (final key in keys) {
      final value = data[key];

      if (value == null) {
        continue;
      }

      if (value is bool) {
        return value;
      }

      if (value is num) {
        return value != 0;
      }

      if (value is String) {
        final normalized = value.trim().toLowerCase();

        if (normalized == 'true' ||
            normalized == '1' ||
            normalized == 'yes' ||
            normalized == 'active' ||
            normalized == 'online' ||
            normalized == 'ontrip' ||
            normalized == 'on trip' ||
            normalized == 'on_trip') {
          return true;
        }

        if (normalized == 'false' ||
            normalized == '0' ||
            normalized == 'no' ||
            normalized == 'inactive' ||
            normalized == 'offline' ||
            normalized == 'not active') {
          return false;
        }
      }
    }

    return defaultValue;
  }

  static double _readDouble(
    Map<String, dynamic> data,
    List<String> keys, {
    required double defaultValue,
  }) {
    final value = _readNullableDouble(data, keys);

    if (value == null) {
      return defaultValue;
    }

    return value;
  }

  static double? _readNullableDouble(
    Map<String, dynamic> data,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = data[key];

      final parsed = _toDouble(value);

      if (parsed != null) {
        return parsed;
      }
    }

    return null;
  }

  static double? _toDouble(dynamic value) {
    if (value == null) {
      return null;
    }

    if (value is num) {
      return value.toDouble();
    }

    if (value is String) {
      return double.tryParse(value.trim());
    }

    return null;
  }

  static DateTime _readDateTime(
    Map<String, dynamic> data,
    List<String> keys, {
    required DateTime defaultValue,
  }) {
    for (final key in keys) {
      final value = data[key];

      if (value == null) {
        continue;
      }

      if (value is Timestamp) {
        return value.toDate();
      }

      if (value is DateTime) {
        return value;
      }

      if (value is String) {
        final parsed = DateTime.tryParse(value.trim());

        if (parsed != null) {
          return parsed;
        }
      }

      if (value is int) {
        try {
          // If value looks like seconds timestamp.
          if (value < 1000000000000) {
            return DateTime.fromMillisecondsSinceEpoch(value * 1000);
          }

          // If value looks like milliseconds timestamp.
          return DateTime.fromMillisecondsSinceEpoch(value);
        } catch (_) {
          continue;
        }
      }
    }

    return defaultValue;
  }

  static DateTime? _readNullableDateTime(
    Map<String, dynamic> data,
    List<String> keys,
  ) {
    final fallback = DateTime.fromMillisecondsSinceEpoch(0);
    final value = _readDateTime(data, keys, defaultValue: fallback);
    return value == fallback ? null : value;
  }

  static bool _isScheduledVisible(
    Map<String, dynamic> data,
    DateTime? scheduledAt,
  ) {
    if (_isEndedTripLocation(data, scheduledAt: scheduledAt)) {
      return false;
    }

    final hasScheduleVisibility = _readBool(data, [
      'scheduledVisible',
      'visibleFromSchedule',
    ], defaultValue: false);

    if (!hasScheduleVisibility || scheduledAt == null) {
      return false;
    }

    final now = DateTime.now();
    return !now.isBefore(scheduledAt) &&
        now.difference(scheduledAt) <= const Duration(hours: 3);
  }

  static CrowdLevel _crowdLevelFromPassengerCount(
    int passengerCount,
    int maxCapacity,
  ) {
    final safeCount = passengerCount < 0 ? 0 : passengerCount;
    if (maxCapacity > 0 && safeCount >= maxCapacity) {
      return CrowdLevel.puno;
    }
    if (safeCount >= 18) return CrowdLevel.puno;
    if (safeCount >= 9) return CrowdLevel.sakto;
    return CrowdLevel.maliwag;
  }

  static bool _isEndedTripLocation(
    Map<String, dynamic> data, {
    DateTime? scheduledAt,
  }) {
    final status = _readString(data, [
      'status',
      'tripStatus',
    ]).trim().toLowerCase();

    final endedAt = _readNullableDateTime(data, ['tripEndedAt', 'endedAt']);
    if (status == 'completed' || status == 'done' || status == 'finished') {
      if (endedAt != null &&
          scheduledAt != null &&
          scheduledAt.isAfter(endedAt)) {
        return false;
      }
      return true;
    }
    if (endedAt == null) return false;
    if (scheduledAt != null && scheduledAt.isAfter(endedAt)) return false;
    return true;
  }

  static double _readSpeedKmh(Map<String, dynamic> data) {
    final speedKmh = _readNullableDouble(data, [
      'speedKmh',
      'speedKmH',
      'speedKilometersPerHour',
    ]);

    if (speedKmh != null) {
      return speedKmh;
    }

    final genericSpeed = _readNullableDouble(data, ['speed']);

    if (genericSpeed != null) {
      return genericSpeed;
    }

    final speedMps = _readNullableDouble(data, [
      'speedMps',
      'speedMetersPerSecond',
    ]);

    if (speedMps != null) {
      return speedMps * 3.6;
    }

    return 0.0;
  }

  @override
  List<Object?> get props => [
    id,
    plateNumber,
    routeId,
    latitude,
    longitude,
    speed,
    crowdLevel,
    estimatedArrivalMinutes,
    lastUpdated,
    isActive,
    originTerminal,
    destinationTerminal,
    driverName,
    passengerCount,
    maxCapacity,
    scheduleTime,
    scheduledAt,
  ];
}
