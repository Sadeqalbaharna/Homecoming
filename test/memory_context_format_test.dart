import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/services/ai/memory_service.dart';

void main() {
  group('MemoryQueryResult context formatting', () {
    test('empty result set injects no memory block', () {
      final result = MemoryQueryResult(results: const [], query: 'anything');

      expect(result.toContextString(), isEmpty);
    });

    test('relevant memories format into the system prompt context block', () {
      final result = MemoryQueryResult(
        query: 'Layer 5 evaluations',
        results: const [
          MemoryResult(
            id: 'm1',
            summary: 'Sadeq asked Kai to test tools, personality, memory, and failure handling.',
            similarity: 0.873,
            timestamp: '2026-07-15T15:00:00.000',
            shardId: 'shard-1',
            shardRef: 'conversation/shard-1',
          ),
          MemoryResult(
            id: 'm2',
            summary: 'Kai should not mark unverified work as done.',
            similarity: 0.421,
            timestamp: '2026-07-15T15:05:00.000',
            shardId: 'shard-2',
            shardRef: 'conversation/shard-2',
          ),
        ],
      );

      final context = result.toContextString();

      expect(context, contains('=== Relevant Memories ==='));
      expect(context, contains('[87% match]'));
      expect(context, contains('[42% match]'));
      expect(context, contains('test tools, personality, memory, and failure handling'));
      expect(context, contains('not mark unverified work as done'));
    });
  });
}
