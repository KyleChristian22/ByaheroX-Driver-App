import 'package:equatable/equatable.dart';

/// User entity representing an authenticated user
class User extends Equatable {
  final String id;
  final String email;
  final String displayName;
  final String firstName;
  final String lastName;
  final String middleName;
  final String phoneNumber;
  final NotificationPreferences notificationPreferences;
  final bool isGuest;
  final bool mustChangePassword;

  const User({
    required this.id,
    required this.email,
    required this.displayName,
    this.firstName = '',
    this.lastName = '',
    this.middleName = '',
    this.phoneNumber = '',
    required this.notificationPreferences,
    required this.isGuest,
    this.mustChangePassword = false,
  });

  factory User.guest() {
    return const User(
      id: 'guest',
      email: '',
      displayName: 'Bisita',
      notificationPreferences: NotificationPreferences(),
      isGuest: true,
      mustChangePassword: false,
    );
  }

  User copyWith({
    String? id,
    String? email,
    String? displayName,
    String? firstName,
    String? lastName,
    String? middleName,
    String? phoneNumber,
    NotificationPreferences? notificationPreferences,
    bool? isGuest,
    bool? mustChangePassword,
  }) {
    return User(
      id: id ?? this.id,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      middleName: middleName ?? this.middleName,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      notificationPreferences:
          notificationPreferences ?? this.notificationPreferences,
      isGuest: isGuest ?? this.isGuest,
      mustChangePassword: mustChangePassword ?? this.mustChangePassword,
    );
  }

  @override
  List<Object?> get props => [
    id,
    email,
    displayName,
    firstName,
    lastName,
    middleName,
    phoneNumber,
    notificationPreferences,
    isGuest,
    mustChangePassword,
  ];
}

/// Notification preferences for a user
class NotificationPreferences extends Equatable {
  final bool arrivalAlerts;
  final bool crowdLevelChanges;
  final bool routeUpdates;
  final int alertRadiusMinutes;

  const NotificationPreferences({
    this.arrivalAlerts = true,
    this.crowdLevelChanges = false,
    this.routeUpdates = true,
    this.alertRadiusMinutes = 10,
  });

  /// Create a copy with modified fields
  NotificationPreferences copyWith({
    bool? arrivalAlerts,
    bool? crowdLevelChanges,
    bool? routeUpdates,
    int? alertRadiusMinutes,
  }) {
    return NotificationPreferences(
      arrivalAlerts: arrivalAlerts ?? this.arrivalAlerts,
      crowdLevelChanges: crowdLevelChanges ?? this.crowdLevelChanges,
      routeUpdates: routeUpdates ?? this.routeUpdates,
      alertRadiusMinutes: alertRadiusMinutes ?? this.alertRadiusMinutes,
    );
  }

  @override
  List<Object?> get props => [
    arrivalAlerts,
    crowdLevelChanges,
    routeUpdates,
    alertRadiusMinutes,
  ];
}
