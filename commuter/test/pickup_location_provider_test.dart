import 'package:commuter_app/presentation/viewmodels/pickup_location_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PickupLocationProvider onboarding transitions', () {
    late PickupLocationProvider provider;

    setUp(() {
      provider = PickupLocationProvider();
    });

    tearDown(() {
      provider.dispose();
    });

    group('pendingOnboardNotification', () {
      test('is false by default', () {
        expect(provider.pendingOnboardNotification, false);
      });

      test('is false after consume is called', () {
        provider.consumeOnboardNotification();
        expect(provider.pendingOnboardNotification, false);
      });
    });

    group('detectOnboardTransition', () {
      test(
        'does not fire on first observation even if already onboard (null previous state)',
        () {
          provider.detectOnboardTransition('onboard', true);
          expect(provider.pendingOnboardNotification, false);
        },
      );

      test('fires when transitioning from not-onboard to onboard via status', () {
        provider.detectOnboardTransition('waiting', false);
        expect(provider.pendingOnboardNotification, false);

        provider.detectOnboardTransition('onboard', false);
        expect(provider.pendingOnboardNotification, true);
      });

      test('fires when transitioning from not-onboard to onboard via onBoard flag', () {
        provider.detectOnboardTransition('waiting', false);
        expect(provider.pendingOnboardNotification, false);

        provider.detectOnboardTransition('waiting', true);
        expect(provider.pendingOnboardNotification, true);
      });

      test('does not fire when already onboard and state stays onboard', () {
        provider.detectOnboardTransition('onboard', true);
        expect(provider.pendingOnboardNotification, false);

        provider.detectOnboardTransition('onboard', true);
        expect(provider.pendingOnboardNotification, false);
      });

      test('resets pending flag after consume and allows re-fire on next transition', () {
        // waiting → onboard
        provider.detectOnboardTransition('waiting', false);
        provider.detectOnboardTransition('onboard', false);
        expect(provider.pendingOnboardNotification, true);

        provider.consumeOnboardNotification();
        expect(provider.pendingOnboardNotification, false);

        // onboard → offboard (no fire)
        provider.detectOnboardTransition('offboard', false);
        expect(provider.pendingOnboardNotification, false);

        // offboard → waiting (no fire)
        provider.detectOnboardTransition('waiting', false);
        expect(provider.pendingOnboardNotification, false);

        // waiting → onboard again (fire)
        provider.detectOnboardTransition('onboard', false);
        expect(provider.pendingOnboardNotification, true);
      });

      test('does not fire when transitioning from onboard back to not-onboard', () {
        provider.detectOnboardTransition('waiting', false);
        provider.detectOnboardTransition('onboard', true);
        expect(provider.pendingOnboardNotification, true);

        provider.consumeOnboardNotification();

        provider.detectOnboardTransition('offboard', false);
        expect(provider.pendingOnboardNotification, false);
      });

      test('handles status normalization (on_board, boarded)', () {
        // Test 'on_board' is recognized as onboard
        provider.detectOnboardTransition('waiting', false);
        provider.detectOnboardTransition('on_board', false);
        expect(provider.pendingOnboardNotification, true);

        provider.consumeOnboardNotification();

        // Transition back to not-onboard, then to 'boarded'
        provider.detectOnboardTransition('offboard', false);
        provider.detectOnboardTransition('boarded', false);
        expect(provider.pendingOnboardNotification, true);
      });
    });
  });
}
