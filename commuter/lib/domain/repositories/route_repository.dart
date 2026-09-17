import '../entities/route.dart';

/// Repository interface for route data operations
abstract class RouteRepository {
  /// Get all available routes
  Future<List<Route>> getRoutes();

  /// Get a single route by ID
  Future<Route?> getRouteById(String routeId);

  /// Get the main route (Lucban - Luisiana - Sta. Cruz)
  Future<Route?> getMainRoute();

  /// Search routes by name
  Future<List<Route>> searchRoutes(String query);

  /// Get favorite routes for a user
  Future<List<Route>> getFavoriteRoutes(List<String> routeIds);

  /// Add a route to favorites
  Future<void> addToFavorites(String routeId);

  /// Remove a route from favorites
  Future<void> removeFromFavorites(String routeId);
}
