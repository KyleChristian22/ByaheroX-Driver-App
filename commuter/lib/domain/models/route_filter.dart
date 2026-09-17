import 'package:equatable/equatable.dart';

/// Model for route-based filtering on commuter map
class RouteFilter extends Equatable {
  final String routeId;
  final String originTerminal;
  final String destinationTerminal;

  const RouteFilter({
    required this.routeId,
    required this.originTerminal,
    required this.destinationTerminal,
  });

  RouteFilter copyWith({
    String? routeId,
    String? originTerminal,
    String? destinationTerminal,
  }) {
    return RouteFilter(
      routeId: routeId ?? this.routeId,
      originTerminal: originTerminal ?? this.originTerminal,
      destinationTerminal: destinationTerminal ?? this.destinationTerminal,
    );
  }

  bool get isValid =>
      routeId.trim().isNotEmpty &&
      originTerminal.trim().isNotEmpty &&
      destinationTerminal.trim().isNotEmpty;

  bool get hasSelection =>
      originTerminal.trim().isNotEmpty || destinationTerminal.trim().isNotEmpty;

  static String? validationMessage({
    required String? routeId,
    required String? originTerminal,
    required String? destinationTerminal,
  }) {
    final origin = originTerminal?.trim() ?? '';
    final destination = destinationTerminal?.trim() ?? '';
    final route = routeId?.trim() ?? '';

    if (origin.isEmpty && destination.isEmpty && route.isEmpty) {
      return 'Please select a route first.';
    }
    if (origin.isEmpty) {
      return 'Please select your origin terminal.';
    }
    if (destination.isEmpty) {
      return 'Please select your destination terminal.';
    }
    if (route.isEmpty) {
      return 'Please select a route first.';
    }
    return null;
  }

  @override
  List<Object?> get props => [routeId, originTerminal, destinationTerminal];
}

/// Route directions with predefined route IDs
class RouteDirections {
  // Match the actual route IDs used in Driver app (uppercase)
  static const String routeLucbanToStaCruz = 'ROUTE001';
  static const String routeStaCruzToLucban = 'ROUTE002';

  static String getRouteIdForDirection(String origin, String destination) {
    if (origin == 'lucban' && destination == 'sta_cruz') {
      return routeLucbanToStaCruz;
    } else if (origin == 'sta_cruz' && destination == 'lucban') {
      return routeStaCruzToLucban;
    }
    return '';
  }

  static String getDestinationForRoute(String routeId, String origin) {
    if (routeId == routeLucbanToStaCruz) {
      return 'sta_cruz';
    } else if (routeId == routeStaCruzToLucban) {
      return 'lucban';
    }
    return origin == 'lucban' ? 'sta_cruz' : 'lucban';
  }
}

/// Terminal information for route selection
class Terminal extends Equatable {
  final String id;
  final String name;
  final String shortName;

  const Terminal({
    required this.id,
    required this.name,
    required this.shortName,
  });

  @override
  List<Object?> get props => [id, name, shortName];
}

/// Predefined terminals for the route
class Terminals {
  static const List<Terminal> mainRoute = [
    Terminal(id: 'lucban', name: 'Lucban Terminal', shortName: 'Lucban'),
    Terminal(
      id: 'sta_cruz',
      name: 'Sta. Cruz Terminal',
      shortName: 'Sta. Cruz',
    ),
  ];

  static const List<Terminal> lucbanToStaCruz = [
    Terminal(id: 'lucban', name: 'Lucban Terminal', shortName: 'Lucban'),
    Terminal(
      id: 'sta_cruz',
      name: 'Sta. Cruz Terminal',
      shortName: 'Sta. Cruz',
    ),
  ];

  static const List<Terminal> staCruzToLucban = [
    Terminal(
      id: 'sta_cruz',
      name: 'Sta. Cruz Terminal',
      shortName: 'Sta. Cruz',
    ),
    Terminal(id: 'lucban', name: 'Lucban Terminal', shortName: 'Lucban'),
  ];
}
