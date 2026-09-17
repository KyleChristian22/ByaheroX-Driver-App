import 'package:equatable/equatable.dart';
import 'route_stop.dart';

/// Route entity representing a jeepney route
class Route extends Equatable {
  final String id;
  final String name;
  final String description;
  final double fare;
  final List<RouteFareEntry> fareEntries;
  final List<RouteStop> stops;
  final List<RouteCoordinate> polylineCoordinates;
  final bool isActive;

  const Route({
    required this.id,
    required this.name,
    required this.description,
    this.fare = 0,
    this.fareEntries = const [],
    required this.stops,
    required this.polylineCoordinates,
    required this.isActive,
  });

  /// Create a copy with modified fields
  Route copyWith({
    String? id,
    String? name,
    String? description,
    double? fare,
    List<RouteFareEntry>? fareEntries,
    List<RouteStop>? stops,
    List<RouteCoordinate>? polylineCoordinates,
    bool? isActive,
  }) {
    return Route(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      fare: fare ?? this.fare,
      fareEntries: fareEntries ?? this.fareEntries,
      stops: stops ?? this.stops,
      polylineCoordinates:
          polylineCoordinates ?? this.polylineCoordinates,
      isActive: isActive ?? this.isActive,
    );
  }

  /// Get number of stops
  int get stopCount => stops.length;

  /// Get start point coordinates
  RouteCoordinate? get startPoint {
    if (polylineCoordinates.isEmpty) return null;
    return polylineCoordinates.first;
  }

  /// Get end point coordinates
  RouteCoordinate? get endPoint {
    if (polylineCoordinates.isEmpty) return null;
    return polylineCoordinates.last;
  }

  @override
  List<Object?> get props => [
        id,
        name,
        description,
        fare,
        fareEntries,
        stops,
        polylineCoordinates,
        isActive,
      ];
}

/// Fare data for a route segment.
class RouteFareEntry extends Equatable {
  final String from;
  final String to;
  final double regular;
  final double studentSenior;

  const RouteFareEntry({
    required this.from,
    required this.to,
    required this.regular,
    required this.studentSenior,
  });

  bool matchesDirection(String origin, String destination) {
    final normalizedFrom = _normalizeTerminal(from);
    final normalizedTo = _normalizeTerminal(to);
    final normalizedOrigin = _normalizeTerminal(origin);
    final normalizedDestination = _normalizeTerminal(destination);

    return normalizedFrom == normalizedOrigin &&
        normalizedTo == normalizedDestination;
  }

  @override
  List<Object?> get props => [from, to, regular, studentSenior];
}

/// Simple coordinate class for route polyline
class RouteCoordinate extends Equatable {
  final double latitude;
  final double longitude;

  const RouteCoordinate({
    required this.latitude,
    required this.longitude,
  });

  @override
  List<Object?> get props => [latitude, longitude];
}

String _normalizeTerminal(String value) {
  return value
      .trim()
      .toLowerCase()
      .replaceAll('.', '')
      .replaceAll('-', ' ')
      .replaceAll('_', ' ')
      .replaceAll(RegExp(r'\s+'), ' ');
}
