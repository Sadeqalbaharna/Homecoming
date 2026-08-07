import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/services/core/kai_state_service.dart';

void main() {
  group('mood survives two bodies talking at once', () {
    test('clamping bounds a value that increments drifted out of range', () {
      // Server-side increments cannot clamp. A long run in one direction drifts
      // the stored value past its range, and if reads did not bound it, several
      // turns of the opposite sign would do nothing visible — his mood would
      // sit pinned while the numbers quietly came back down.
      final drifted = KaiStateService.clampState(
        {'valence': 137, 'energy': -12, 'warmth': 50},
        min: 0,
        max: 100,
      );

      expect(drifted.values['valence'], 100);
      expect(drifted.values['energy'], 0);
      expect(drifted.values['warmth'], 50);
      expect(drifted.healed, isTrue,
          reason: 'an out-of-range read must trigger the corrective write');
    });

    test('an in-range read is left alone and writes nothing back', () {
      final fine = KaiStateService.clampState(
        {'valence': 0, 'energy': 100, 'warmth': 50},
        min: 0,
        max: 100,
      );

      expect(fine.values, {'valence': 0, 'energy': 100, 'warmth': 50});
      expect(fine.healed, isFalse,
          reason: 'the boundaries themselves are valid, not drift');
    });

    test('personality uses its own wider range', () {
      final personality = KaiStateService.clampState(
        {'extraversion': 1400, 'feeling': 900},
        min: 0,
        max: 1000,
      );

      expect(personality.values['extraversion'], 1000);
      expect(personality.values['feeling'], 900,
          reason: '900 is in range for personality, out of range for mood');
    });
  });
}
