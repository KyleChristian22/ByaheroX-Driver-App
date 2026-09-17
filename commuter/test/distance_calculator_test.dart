import 'package:flutter_test/flutter_test.dart';
import 'package:commuter_app/core/utils/distance_calculator.dart';

void main() {
  group('DistanceCalculator', () {
    test('should calculate distance between two points correctly', () {
      final distance = DistanceCalculator.calculateDistance(
        14.114451, // Lucban
        121.552106,
        14.266016, // Santa Cruz
        121.425670,
      );

      expect(distance, closeTo(21.7, 0.1));
    });

    test('should return 0 for same location', () {
      final distance = DistanceCalculator.calculateDistance(
        14.114451,
        121.552106,
        14.114451,
        121.552106,
      );

      expect(distance, equals(0));
    });

    test('should calculate estimated time correctly', () {
      final time1 = DistanceCalculator.calculateEstimatedTime(10, speedKmh: 60);
      expect(time1, equals(10));

      final time2 = DistanceCalculator.calculateEstimatedTime(5, speedKmh: 20);
      expect(time2, equals(15));

      final time3 = DistanceCalculator.calculateEstimatedTime(0, speedKmh: 20);
      expect(time3, equals(0));
    });
  });
}
