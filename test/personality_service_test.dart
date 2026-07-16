import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/services/ai/personality_service.dart';

void main() {
  group('PersonalityService pure evaluations', () {
    final service = PersonalityService();

    test('personality deltas are damped and clamped instead of jumping wildly', () {
      expect(service.applyPersonalityDelta(500, 100), 515);
      expect(service.applyPersonalityDelta(995, 100), 998);
      expect(service.applyPersonalityDelta(5, -100), 2);
      expect(service.applyPersonalityDelta(500, 0), 500);
    });

    test('mood deltas respect context intensity and clamp to the mood scale', () {
      expect(service.applyMoodDelta(50, 10, 'normal'), 60);
      expect(service.applyMoodDelta(50, 10, 'high'), 70);
      expect(service.applyMoodDelta(50, 10, 'radical'), 90);
      expect(service.applyMoodDelta(50, 10, 'unknown'), 60);
      expect(service.applyMoodDelta(95, 20, 'high'), 100);
      expect(service.applyMoodDelta(5, -20, 'high'), 0);
      expect(service.applyMoodDelta(50, 0, 'high'), 50);
    });

    test('MBTI calculation is deterministic from thresholded trait values', () {
      expect(
        service.calculateMBTI({
          'extraversion': 100,
          'intuition': 700,
          'feeling': 800,
          'perceiving': 650,
        }),
        'INFP',
      );

      expect(
        service.calculateMBTI({
          'extraversion': 800,
          'intuition': 100,
          'feeling': 100,
          'perceiving': 200,
        }),
        'ESTJ',
      );
    });
  });
}
