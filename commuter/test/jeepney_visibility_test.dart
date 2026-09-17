import 'package:commuter_app/domain/entities/jeepney.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Jeepney live visibility', () {
    Map<String, dynamic> liveLocation({String? driverId}) {
      return {
        'jeepneyId': 'JEEP001',
        'routeId': 'ROUTE001',
        'lat': 14.2730,
        'lng': 121.4031,
        'isOnTrip': true,
        'isOnline': true,
        if (driverId != null) 'driverId': driverId,
      };
    }

    test('keeps on-trip jeepney active when driver is assigned', () {
      final jeepney = Jeepney.fromMap(liveLocation(driverId: 'DRV001'));

      expect(jeepney.isActive, isTrue);
    });

    test('hides on-trip jeepney when driver is missing', () {
      final jeepney = Jeepney.fromMap(liveLocation());

      expect(jeepney.isActive, isFalse);
    });
  });
}
