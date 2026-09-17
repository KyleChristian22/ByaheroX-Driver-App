import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/entities/route.dart';
import '../../domain/entities/route_stop.dart';
import '../../domain/repositories/route_repository.dart';
import '../services/routing_service.dart';

/// Implementation of RouteRepository using Firebase Firestore
class RouteRepositoryImpl implements RouteRepository {
  final FirebaseFirestore _firestore;
  final RoutingService _routingService;

  // Cache for routes
  List<Route>? _cachedRoutes;
  DateTime? _routesCacheTime;
  static const _routesCacheDuration = Duration(minutes: 5);

  RouteRepositoryImpl({
    FirebaseFirestore? firestore,
    RoutingService? routingService,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _routingService = routingService ?? RoutingService();

  @override
  Future<List<Route>> getRoutes() async {
    // Check cache first
    if (_cachedRoutes != null &&
        _routesCacheTime != null &&
        DateTime.now().difference(_routesCacheTime!) < _routesCacheDuration) {
      return _cachedRoutes!;
    }

    try {
      final snapshot = await _firestore.collection('routes').get();

      _cachedRoutes = snapshot.docs
          .where((doc) => _isActiveRouteData(doc.data()))
          .map((doc) => _routeFromFirestore(doc))
          .toList();
      _routesCacheTime = DateTime.now();
      // Enhance routes with road-snapped coordinates
      _cachedRoutes = await _enhanceRoutesWithRoadSnappedPolyline(
        _cachedRoutes!,
      );
      return _cachedRoutes!;
    } catch (e) {
      // Return empty list on error - Firestore is not available
      return [];
    }
  }

  @override
  Future<Route?> getRouteById(String routeId) async {
    try {
      final doc = await _firestore.collection('routes').doc(routeId).get();
      if (doc.exists) {
        return _routeFromFirestore(doc);
      }
    } catch (e) {
      // Return null on error
    }
    return null;
  }

  @override
  Future<Route?> getMainRoute() async {
    try {
      final snapshot = await _firestore.collection('routes').get();

      final activeDocs = snapshot.docs
          .where((doc) => _isActiveRouteData(doc.data()))
          .toList();

      if (activeDocs.isNotEmpty) {
        final route = _routeFromFirestore(activeDocs.first);
        // Enhance with road-snapped coordinates from Geoapify
        final enhancedRoutes = await _enhanceRoutesWithRoadSnappedPolyline([
          route,
        ]);
        return enhancedRoutes.first;
      }
    } catch (e) {
      // Return null on error
    }
    return null;
  }

  /// Enhance routes with road-snapped polyline coordinates
  /// This fetches actual road-aligned coordinates from Geoapify API
  Future<List<Route>> _enhanceRoutesWithRoadSnappedPolyline(
    List<Route> routes,
  ) async {
    final enhancedRoutes = <Route>[];

    for (final route in routes) {
      if (route.stops.isNotEmpty) {
        // Get road-snapped coordinates
        final snappedCoords = await _routingService.getRouteThroughWaypoints(
          route.stops,
        );

        if (snappedCoords.isNotEmpty) {
          enhancedRoutes.add(
            route.copyWith(polylineCoordinates: snappedCoords),
          );
        } else {
          // Keep original coordinates if snapping fails
          enhancedRoutes.add(route);
        }
      } else {
        enhancedRoutes.add(route);
      }
    }

    return enhancedRoutes;
  }

  @override
  Future<List<Route>> searchRoutes(String query) async {
    final routes = await getRoutes();
    final lowercaseQuery = query.toLowerCase();
    return routes
        .where(
          (r) =>
              r.name.toLowerCase().contains(lowercaseQuery) ||
              r.description.toLowerCase().contains(lowercaseQuery),
        )
        .toList();
  }

  @override
  Future<List<Route>> getFavoriteRoutes(List<String> routeIds) async {
    final routes = await getRoutes();
    return routes.where((r) => routeIds.contains(r.id)).toList();
  }

  @override
  Future<void> addToFavorites(String routeId) async {
    // Handled by AuthRepository
  }

  @override
  Future<void> removeFromFavorites(String routeId) async {
    // Handled by AuthRepository
  }

  // Firestore document conversion
  Route _routeFromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    // Admin stores `stops` as an int count, while older commuter route data
    // used a list of stop objects. Accept both so fare-only routes still load.
    final rawStops = data['stops'];
    final stops = rawStops is List
        ? rawStops.map((s) {
            final stopMap = s as Map<String, dynamic>;
            return RouteStop(
              id: stopMap['id'] ?? '',
              name: stopMap['name'] ?? '',
              latitude: _doubleValue(stopMap['latitude']),
              longitude: _doubleValue(stopMap['longitude']),
              sequence: _intValue(stopMap['sequence']),
            );
          }).toList()
        : <RouteStop>[];

    // Parse polyline coordinates
    final polylineList =
        data['polylineCoordinates'] as List<dynamic>? ??
        data['coordinates'] as List<dynamic>? ??
        [];
    final polylineCoordinates = polylineList.map((c) {
      final coordMap = c as Map<String, dynamic>;
      return RouteCoordinate(
        latitude: _doubleValue(coordMap['latitude'] ?? coordMap['lat']),
        longitude: _doubleValue(coordMap['longitude'] ?? coordMap['lng']),
      );
    }).toList();

    final fareEntriesList = data['fareEntries'] as List<dynamic>? ?? [];
    final fareEntries = fareEntriesList.map((entry) {
      final entryMap = entry as Map<String, dynamic>;
      return RouteFareEntry(
        from: entryMap['from']?.toString() ?? '',
        to: entryMap['to']?.toString() ?? '',
        regular: _doubleValue(entryMap['regular']),
        studentSenior: _doubleValue(entryMap['studentSenior']),
      );
    }).toList();

    return Route(
      id: doc.id,
      name: data['name'] ?? '',
      description: data['description'] ?? '',
      fare: _doubleValue(data['fare']),
      fareEntries: fareEntries,
      stops: stops,
      polylineCoordinates: polylineCoordinates,
      isActive: _isActiveRouteData(data),
    );
  }

  bool _isActiveRouteData(Map<String, dynamic> data) {
    final isActive = data['isActive'];
    if (isActive is bool) return isActive;

    final status = data['status']?.toString().trim().toLowerCase();
    if (status == null || status.isEmpty) return true;
    return status == 'active';
  }

  double _doubleValue(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  int _intValue(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
