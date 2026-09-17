import '../entities/jeepney.dart';

/// Repository interface for jeepney data operations
abstract class JeepneyRepository {
  /// Get all active jeepneys for a specific route
  Future<List<Jeepney>> getJeepneys(String routeId);

  /// Get all active jeepneys across all routes
  Future<List<Jeepney>> getAllActiveJeepneys();

  /// Stream of all active jeepneys across all routes
  Stream<List<Jeepney>> watchAllActiveJeepneys();

  /// Get a single jeepney by ID
  Future<Jeepney?> getJeepneyById(String jeepneyId);

  /// Get jeepneys near a specific location
  Future<List<Jeepney>> getJeepneysNearLocation(
    double latitude,
    double longitude,
    double radiusKm,
  );

  /// Stream of real-time jeepney updates
  Stream<List<Jeepney>> watchJeepneys(String routeId);

  /// Refresh jeepney data
  Future<void> refreshJeepneys(String routeId);
}
