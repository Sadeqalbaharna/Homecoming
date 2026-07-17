import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/services/ai/memory_service.dart';

import 'memory_golden_data.dart';
import 'memory_golden_test_runner.dart';

Future<List<double>?> _embedding(String text) async {
  final lower = text.toLowerCase();
  if (lower.contains('vibe') ||
      lower.contains('preference') ||
      lower.contains('cozy') ||
      lower.contains('prefer')) {
    return [0.0, 1.0];
  }
  if (lower.contains('project') || lower.contains('homecoming')) {
    return [1.0, 0.0];
  }
  return [0.1, 0.1];
}

Future<List<Map<String, dynamic>>> _shards(String personaId) async => [
      {
        'id': 'project-homecoming',
        'summary': 'Homecoming is Sadeq’s Flutter conversational AI companion project.',
        'vector': [1.0, 0.0],
        'timestamp': '2026-07-15T12:00:00.000Z',
        'shardId': 'project-homecoming-shard',
        'shardRef': 'mem/project-homecoming-shard',
      },
      {
        'id': 'cozy-preference',
        'summary': 'Sadeq prefers a cozy, playful, direct atmosphere.',
        'embedding': [0.0, 1.0],
        'timestamp': '2026-07-15T12:05:00.000Z',
        'shardId': 'cozy-preference-shard',
        'shardRef': 'mem/cozy-preference-shard',
      },
    ];

void main() {
  group('Memory golden runner offline seam', () {
    test('can execute injected golden checks without live services', () async {
      final results = <MemoryTestResult>[];
      for (final golden in [
        MemoryTest(
          query: 'What project is Sadeq building?',
          expectedKeywords: const ['homecoming', 'flutter', 'ai'],
          minSimilarity: 0.9,
          description: 'recalls Homecoming project memory',
        ),
        MemoryTest(
          query: 'What kind of vibe does Sadeq prefer?',
          expectedKeywords: const ['cozy', 'playful', 'direct'],
          minSimilarity: 0.9,
          description: 'recalls style preference memory',
        ),
      ]) {
        final response = await MemoryService.queryMemory(
          personaId: 'truekai',
          query: golden.query,
          embeddingProvider: _embedding,
          shardLoader: _shards,
          sideEffects: MemoryQuerySideEffects.disabled,
        );
        final top = response!.results.first;
        final summary = top.summary.toLowerCase();
        final foundKeywords = golden.expectedKeywords
            .where((keyword) => summary.contains(keyword.toLowerCase()))
            .toList();
        final passed = top.similarity >= golden.minSimilarity &&
            foundKeywords.isNotEmpty;
        results.add(MemoryTestResult(
          test: golden,
          passed: passed,
          actualSimilarity: top.similarity,
          foundKeywords: foundKeywords,
          errorMessage: passed ? null : 'Offline fake memory did not match',
        ));
      }

      expect(results, hasLength(2));
      expect(results.every((result) => result.passed), isTrue);
    });

    test('runGoldenTests accepts offline providers', () async {
      final results = await runGoldenTests(
        personaId: 'truekai',
        version: 'offline',
        embeddingProvider: _embedding,
        shardLoader: _shards,
        sideEffects: MemoryQuerySideEffects.disabled,
      );

      expect(results, isNotEmpty);
      expect(
        results.any((result) => result.errorMessage?.contains('MissingPlugin') == true),
        isFalse,
      );
    });
  });
}
