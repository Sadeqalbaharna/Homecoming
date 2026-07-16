import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/services/core/memory_consolidation_service.dart';

void main() {
  group('MemoryConsolidationService prompt formatting', () {
    test('formats episodic memory into prompt context without live services', () {
      final formatted = MemoryConsolidationService().formatForPromptForTesting({
        'running_narrative': 'Sadeq is building Homecoming and improving Kai.',
        'emotional_patterns': 'Warm, playful focus with occasional tech stress.',
        'recurring_themes': ['Homecoming', 'Digimon', 'fitness'],
        'key_moments': [
          'Router became real',
          'Layer 5 tests started',
          'Copying full chatbox text was fixed',
          'Memory tests became offline',
          'Dashboard progress was corrected',
          'This sixth moment should be capped out',
        ],
        'commitments_and_plans': [
          'Check TVs on WiFi',
          '✓ Fixed selectable chat bubbles',
          'Finish offline memory evals',
        ],
        'relationship_depth_note': 'Kai and Sadeq work as chaotic honest partners.',
      });

      expect(formatted, contains('EPISODIC MEMORY'));
      expect(formatted, contains('Sadeq is building Homecoming'));
      expect(formatted, contains('Emotional pattern: Warm, playful focus'));
      expect(formatted, contains('Homecoming'));
      expect(formatted, contains('Router became real'));
      expect(formatted, contains('Dashboard progress was corrected'));
      expect(formatted, isNot(contains('This sixth moment should be capped out')));
      expect(formatted, contains('Open commitments: Check TVs on WiFi'));
      expect(formatted, contains('Finish offline memory evals'));
      expect(formatted, isNot(contains('Fixed selectable chat bubbles')));
      expect(formatted, contains('Relationship: Kai and Sadeq'));
    });

    test('omits empty sections instead of injecting noise', () {
      final formatted = MemoryConsolidationService().formatForPromptForTesting({
        'running_narrative': 'Only the useful narrative remains.',
        'recurring_themes': const [],
        'key_moments': const [],
        'commitments_and_plans': const [],
      });

      expect(formatted, contains('Only the useful narrative remains.'));
      expect(formatted, isNot(contains('Recurring themes:')));
      expect(formatted, isNot(contains('Key moments:')));
      expect(formatted, isNot(contains('Open commitments:')));
    });
  });
}
