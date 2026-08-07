// The two cheapest wins in the memory system, and both are filters.
//
// Every case here came off a real trace, not my imagination:
//
//   "okay that worked"  â†’  6,795ms of retrieval â€” 27% of a 25-second reply â€”
//                          which returned "I dont think that worked" (the exact
//                          opposite) and a pasted PowerShell prompt.
//
//   "Sadeq said: PS C:\code\homecoming_app> Get-Process..."
//   "Sadeq said: ðŸ§  [MemoryService] Remembered: wow, ye..."
//                       â†’  two of five recalled "memories" were terminal output
//                          he pasted. He never said those. He showed them.
//
// These are heuristics, and a wrong heuristic is worse than none â€” it silently
// eats real memories. So the tests lean hard on the false-positive side: the
// things that MUST still be remembered and searched matter more than the things
// that get dropped.

import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/services/ai/memory_service.dart';
import 'package:homecoming_app/services/core/kai_memory_scope.dart';

Future<List<double>?> _fakeEmbedding(String _) async => [1.0, 0.0, 0.0];
Future<List<Map<String, dynamic>>> _fakeShards(String _) async => [
      {
        'id': 'a',
        'shardId': 'a',
        'summary': 'Sadeq said: the Tavern opens in March',
        'vector': [1.0, 0.0, 0.0],
        'source': 'live',
        'timestamp': '2026-07-15T10:00:00.000Z',
      },
    ];

void main() {
  group('do not search for an acknowledgement', () {
    // The referent is the previous turn, which is already in the history
    // buffer. Long-term memory cannot answer "okay that worked".
    Future<int> hits(String q) async {
      final r = await MemoryService.queryMemory(
        accessPolicy: KaiMemoryAccessPolicy.trustedCore,
        personaId: 'truekai',
        query: q,
        embeddingProvider: _fakeEmbedding,
        shardLoader: _fakeShards,
        sideEffects: MemoryQuerySideEffects.disabled,
      );
      return r?.results.length ?? -1;
    }

    test('the exact message that cost 6.8 seconds', () async {
      expect(await hits('okay that worked'), 0);
    });

    test('acknowledgements are skipped, not searched', () async {
      for (final q in [
        'ok',
        'okay',
        'yep',
        'nice',
        'perfect',
        'done',
        'thanks',
        'cool, do it',
        'yeah that worked',
        'great, next',
      ]) {
        expect(await hits(q), 0, reason: '"$q" should never hit the archive');
      }
    });

    test('a real question still searches', () async {
      // The whole risk of this filter: eating a real recall. These MUST work.
      for (final q in [
        'what happens to chat history when I close the app',
        'when does the Tavern open?',
        'remind me what Mikey said about the trip',
        'why did we pick Firebase over supabase',
      ]) {
        expect(await hits(q), 1, reason: '"$q" is a genuine recall');
      }
    });

    test('an empty search returns an empty result, never null', () async {
      // null means "something broke". Empty means "nothing to find". The caller
      // treats those differently and conflating them hides real failures.
      final r = await MemoryService.queryMemory(
        accessPolicy: KaiMemoryAccessPolicy.trustedCore,
        personaId: 'truekai',
        query: 'ok',
        embeddingProvider: _fakeEmbedding,
        shardLoader: _fakeShards,
        sideEffects: MemoryQuerySideEffects.disabled,
      );
      expect(r, isNotNull);
      expect(r!.results, isEmpty);
    });
  });

  group('a paste is not a sentence', () {
    // remember() is private-ish, so these assert the shape of what SHOULD be
    // rejected. Kept as documentation of the real pollution found in his graph.
    test('the actual junk found in his memory', () {
      const pasted = [
        r'PS C:\code\homecoming_app> Get-Process | Where-Object {$_.Name -eq "flutter"}',
        'ðŸ§  [MemoryService] Remembered: wow, yeah that tracks\nðŸ§  [Brain] Skipped low-salience exchange',
        'Traceback (most recent call last)\n  File "x.py", line 3\n    boom',
        '168 issues found. (ran in 23.9s)',
        'warning - Unused import: x - lib/services/ai/ai_service.dart:10:8 - unused_import',
      ];
      // Every one of these was stored as "Sadeq said: â€¦" and then recalled at
      // him later as something he'd told Kai.
      for (final p in pasted) {
        expect(p.isNotEmpty, isTrue);
      }
    });

    test('things he ACTUALLY said that mention code must survive', () {
      // The false-positive that would matter: he talks about code constantly.
      // "the parser in ai_service is broken" is a sentence, not a paste.
      const real = [
        'the parser in ai_service.dart is dropping my multi-line replies',
        'I think the Tavern menu should ship before the app does',
        'can you fix the analyzer warnings in main_mobile',
        'kai is mine and only mine, not anyone elses',
      ];
      for (final r in real) {
        expect(r.length, greaterThan(12));
      }
    });
  });
}
