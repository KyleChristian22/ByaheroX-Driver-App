import 'package:equatable/equatable.dart';

/// RouteStop entity representing a stop on a jeepney route
class RouteStop extends Equatable {
  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final int sequence;

  const RouteStop({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.sequence,
  });

  /// Create a copy with modified fields
  RouteStop copyWith({
    String? id,
    String? name,
    double? latitude,
    double? longitude,
    int? sequence,
  }) {
    return RouteStop(
      id: id ?? this.id,
      name: name ?? this.name,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      sequence: sequence ?? this.sequence,
    );
  }

  @override
  List<Object?> get props => [id, name, latitude, longitude, sequence];
}
