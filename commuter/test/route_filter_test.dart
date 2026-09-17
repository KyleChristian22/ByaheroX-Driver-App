import 'package:commuter_app/domain/models/route_filter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RouteFilter validation', () {
    test('warns when no route is selected', () {
      final message = RouteFilter.validationMessage(
        routeId: null,
        originTerminal: null,
        destinationTerminal: null,
      );

      expect(message, 'Please select a route first.');
    });

    test('warns when origin terminal is missing', () {
      final message = RouteFilter.validationMessage(
        routeId: RouteDirections.routeLucbanToStaCruz,
        originTerminal: '',
        destinationTerminal: 'sta_cruz',
      );

      expect(message, 'Please select your origin terminal.');
    });

    test('warns when destination terminal is missing', () {
      final message = RouteFilter.validationMessage(
        routeId: RouteDirections.routeLucbanToStaCruz,
        originTerminal: 'lucban',
        destinationTerminal: '',
      );

      expect(message, 'Please select your destination terminal.');
    });

    test('warns when route id is empty for selected terminals', () {
      final message = RouteFilter.validationMessage(
        routeId: '',
        originTerminal: 'lucban',
        destinationTerminal: 'lucban',
      );

      expect(message, 'Please select a route first.');
    });

    test('accepts a complete route selection', () {
      final message = RouteFilter.validationMessage(
        routeId: RouteDirections.routeLucbanToStaCruz,
        originTerminal: 'lucban',
        destinationTerminal: 'sta_cruz',
      );

      expect(message, isNull);
    });
  });
}
