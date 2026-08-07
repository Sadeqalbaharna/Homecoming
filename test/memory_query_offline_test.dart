import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/services/ai/memory_service.dart';

Future<List<double>?> fakeEmbedding(String text) async {
  final lower = text.toLowerCase();
  if (lower.contains('fitness') || lower.contains('lionheart')) {
    return [1.0, 0.0, 0.0];
  }
  if (lower.contains('tavern') || lower.contains('brunch')) {
    return [0.0, 1.0, 0.0];
  }
  if (lower.contains('homecoming') || lower.contains('memory')) {
    return [0.0, 0.0, 1.0];
  }
  return [0.0, 0.0, 0.0];
}

Future<List<Map<String, dynamic>>> fakeShards(String personaId) async => [
      {
        'id': 'lionheart',
        'summary': 'Project Lionheart is Sadeq’s fitness and strength arc.',
        'vector': [1.0, 0.0, 0.0],
        'timestamp': '2026-07-15T10:00:00.000Z',
        'shardId': 'lionheart-shard',
        'shardRef': 'mem/lionheart-shard',
      },
      {
        'id': 'tavern',
        'summary':
            'The Tavern is Sadeq’s fantasy-themed brunch venue in Bahrain.',
        'embedding': [0.0, 1.0, 0.0],
        'timestamp': '2026-07-15T11:00:00.000Z',
        'shardId': 'tavern-shard',
        'shardRef': 'mem/tavern-shard',
      },
      {
        'id': 'homecoming',
        'summary':
            'Homecoming is the Flutter app where Kai is becoming smarter.',
        'vector': [0.0, 0.0, 1.0],
        'timestamp': '2026-07-15T12:00:00.000Z',
        'shardId': 'homecoming-shard',
        'shardRef': 'mem/homecoming-shard',
      },
    ];

void main() {
  group('MemoryService offline query seam', () {
    test('ranks deterministic fake shards without OpenAI or Firebase',
        () async {
      final result = await MemoryService.queryMemory(
        personaId: 'truekai',
        query: 'How is Project Lionheart fitness going?',
        embeddingProvider: fakeEmbedding,
        shardLoader: fakeShards,
        sideEffects: MemoryQuerySideEffects.disabled,
      );

      expect(result, isNotNull);
      expect(result!.results, isNotEmpty);
      expect(result.results.first.id, 'lionheart');
      expect(result.results.first.similarity, greaterThan(0.99));
    });

    test('accepts both vector and embedding fields', () async {
      final tavern = await MemoryService.queryMemory(
        personaId: 'truekai',
        query: 'What do we remember about Tavern brunch?',
        embeddingProvider: fakeEmbedding,
        shardLoader: fakeShards,
        sideEffects: MemoryQuerySideEffects.disabled,
      );
      final homecoming = await MemoryService.queryMemory(
        personaId: 'truekai',
        query: 'What do we remember about Homecoming memory?',
        embeddingProvider: fakeEmbedding,
        shardLoader: fakeShards,
        sideEffects: MemoryQuerySideEffects.disabled,
      );

      expect(tavern!.results.first.id, 'tavern');
      expect(homecoming!.results.first.id, 'homecoming');
    });

    test('empty fake shard list returns an empty result instead of null',
        () async {
      final result = await MemoryService.queryMemory(
        personaId: 'truekai',
        query: 'anything',
        embeddingProvider: (_) async => [1.0, 0.0, 0.0],
        shardLoader: (_) async => const [],
        sideEffects: MemoryQuerySideEffects.disabled,
      );

      expect(result, isNotNull);
      expect(result!.results, isEmpty);
    });

    test('explicit immediate-continuity questions promote the latest memory',
        () async {
      final now = DateTime.now().toUtc();
      final result = await MemoryService.queryMemory(
        personaId: 'truekai',
        query: 'What was I telling you about just before I came in here?',
        embeddingProvider: (_) async => [0.0, 0.0, 1.0],
        shardLoader: (_) async => [
          {
            'id': 'older-semantic-match',
            'summary': 'An older discussion about Homecoming memory.',
            'vector': [0.0, 0.0, 1.0],
            'timestamp':
                now.subtract(const Duration(hours: 2)).toIso8601String(),
            'shardId': 'older',
          },
          {
            'id': 'latest-messenger-moment',
            'summary': 'Sadeq named a purple notebook Moth Hotel.',
            'vector': [1.0, 0.0, 0.0],
            'timestamp':
                now.subtract(const Duration(minutes: 2)).toIso8601String(),
            'shardId': 'latest',
          },
        ],
        sideEffects: MemoryQuerySideEffects.disabled,
      );

      expect(result!.results.first.id, 'latest-messenger-moment');
    });

    test('ordinary semantic questions are not overridden by recency', () async {
      final now = DateTime.now().toUtc();
      final result = await MemoryService.queryMemory(
        personaId: 'truekai',
        query: 'What do you remember about Homecoming memory?',
        embeddingProvider: (_) async => [0.0, 0.0, 1.0],
        shardLoader: (_) async => [
          ...await fakeShards('truekai'),
          {
            'id': 'recent-unrelated',
            'summary': 'A purple notebook called Moth Hotel.',
            'vector': [1.0, 0.0, 0.0],
            'timestamp':
                now.subtract(const Duration(minutes: 1)).toIso8601String(),
            'shardId': 'recent',
          },
        ],
        sideEffects: MemoryQuerySideEffects.disabled,
      );

      expect(result!.results.first.id, 'homecoming');
    });
  });
}
