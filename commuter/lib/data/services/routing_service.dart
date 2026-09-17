import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../domain/entities/route.dart';
import '../../domain/entities/route_stop.dart';

class RoutingService {
  static const String _osrmBaseUrl = 'https://router.project-osrm.org';

  Future<List<RouteCoordinate>> getRoadSnappedCoordinates(
    double startLat,
    double startLng,
    double endLat,
    double endLng,
  ) async {
    final url = Uri.parse(
      '$_osrmBaseUrl/route/v1/driving/$startLng,$startLat;$endLng,$endLat'
      '?overview=full&geometries=geojson',
    );

    try {
      final response = await http.get(url).timeout(
        const Duration(seconds: 10),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['routes'] != null && 
            data['routes'] is List && 
            data['routes'].isNotEmpty) {
          
          final geometry = data['routes'][0]['geometry'];
          final coordinates = geometry['coordinates'] as List;
          
          return coordinates.map((coord) {
            return RouteCoordinate(
              latitude: coord[1],
              longitude: coord[0],
            );
          }).toList();
        }
      }
    } catch (e) {
    }
    
    return [];
  }

  Future<double?> calculateDistance(
    double startLat,
    double startLng,
    double endLat,
    double endLng,
  ) async {
    final url = Uri.parse(
      '$_osrmBaseUrl/route/v1/driving/$startLng,$startLat;$endLng,$endLat'
      '?overview=false',
    );

    try {
      final response = await http.get(url).timeout(
        const Duration(seconds: 10),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['routes'] != null && 
            data['routes'] is List && 
            data['routes'].isNotEmpty) {
          
          final route = data['routes'][0];
          return (route['distance'] as num).toDouble();
        }
      }
    } catch (e) {
    }
    
    return null;
  }

  Future<int?> calculateETA(
    double startLat,
    double startLng,
    double endLat,
    double endLng,
  ) async {
    final url = Uri.parse(
      '$_osrmBaseUrl/route/v1/driving/$startLng,$startLat;$endLng,$endLat'
      '?overview=false',
    );

    try {
      final response = await http.get(url).timeout(
        const Duration(seconds: 10),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['routes'] != null && 
            data['routes'] is List && 
            data['routes'].isNotEmpty) {
          
          final route = data['routes'][0];
          return (route['duration'] as num).toInt();
        }
      }
    } catch (e) {
    }
    
    return null;
  }

  Future<RouteInfo?> getRouteInfo(
    double startLat,
    double startLng,
    double endLat,
    double endLng,
  ) async {
    final url = Uri.parse(
      '$_osrmBaseUrl/route/v1/driving/$startLng,$startLat;$endLng,$endLat'
      '?overview=full&geometries=geojson',
    );

    try {
      final response = await http.get(url).timeout(
        const Duration(seconds: 10),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['routes'] != null && 
            data['routes'] is List && 
            data['routes'].isNotEmpty) {
          
          final route = data['routes'][0];
          final geometry = route['geometry'];
          
          final distance = (route['distance'] as num).toDouble();
          final duration = (route['duration'] as num).toInt();
          final coordinates = (geometry['coordinates'] as List).map((coord) {
            return RouteCoordinate(
              latitude: coord[1],
              longitude: coord[0],
            );
          }).toList();
          
          return RouteInfo(
            coordinates: coordinates,
            distance: distance,
            duration: duration,
          );
        }
      }
    } catch (e) {
    }
    
    return null;
  }

  Future<List<RouteCoordinate>> getRouteThroughWaypoints(
    List<RouteStop> stops,
  ) async {
    if (stops.isEmpty) return [];
    if (stops.length == 1) {
      return [
        RouteCoordinate(
          latitude: stops.first.latitude,
          longitude: stops.first.longitude,
        ),
      ];
    }

    final List<RouteCoordinate> allCoordinates = [];
    
    for (int i = 0; i < stops.length - 1; i++) {
      final start = stops[i];
      final end = stops[i + 1];
      
      final routeCoords = await getRoadSnappedCoordinates(
        start.latitude,
        start.longitude,
        end.latitude,
        end.longitude,
      );
      
      if (routeCoords.isNotEmpty) {
        if (i > 0 && allCoordinates.isNotEmpty) {
          allCoordinates.addAll(routeCoords.take(routeCoords.length - 1));
        } else {
          allCoordinates.addAll(routeCoords);
        }
      } else {
        allCoordinates.add(RouteCoordinate(
          latitude: start.latitude,
          longitude: start.longitude,
        ));
      }
    }
    
    if (stops.isNotEmpty) {
      allCoordinates.add(RouteCoordinate(
        latitude: stops.last.latitude,
        longitude: stops.last.longitude,
      ));
    }
    
    return allCoordinates;
  }

  Future<Route> getRouteWithRoadSnappedPolyline(Route route) async {
    if (route.stops.isEmpty) {
      return route;
    }

    final snappedCoords = await getRouteThroughWaypoints(route.stops);

    if (snappedCoords.isNotEmpty) {
      return route.copyWith(polylineCoordinates: snappedCoords);
    }

    return route;
  }
}

class RouteInfo {
  final List<RouteCoordinate> coordinates;
  final double? distance;
  final int? duration;

  const RouteInfo({
    required this.coordinates,
    required this.distance,
    required this.duration,
  });

  double? get distanceInKm => distance != null ? distance! / 1000 : null;

  int? get durationInMinutes => duration != null ? (duration! / 60).round() : null;

  Duration? get eta => duration != null ? Duration(seconds: duration!) : null;
}
