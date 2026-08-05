import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/logic/memory_classifier.dart';
import 'package:homecoming_app/services/core/kai_memory_promotion_service.dart';

void main() {
  group('deterministic prefilter — narrows only', () {
    test('structural markers decide on their own', () {
      for (final summary in [
        'Sadeq said: why does this throw\nI said: ```dart\nfinal x = 1;\n```',
        'I said: the fix is in lib/services/ai/ai_service.dart',
        'I said: it blew up with StackTrace at the top of the queue',
        'Sadeq said: run git rebase main\nI said: done',
        'I said: Exception: token expired',
      ]) {
        expect(
          classifyLegacyMemory(summary).isTechnical,
          isTrue,
          reason: summary,
        );
      }
    });

    test('a memory ABOUT technical work stays personal', () {
      // The false positive that matters most. This is exactly the memory Kai
      // should carry to Messenger, and a topic-word classifier would bury it.
      for (final summary in [
        'Sadeq said: I am proud of what we built together',
        'Sadeq said: today was rough, the work beat me up',
        'Sadeq said: we stayed up until 4am and it finally worked',
        'Sadeq said: my sister came over and we made brunch',
        // Ordinary English that collides with tool names. These are the reason
        // command detection matches PAIRS rather than bare prefixes.
        'Sadeq said: we went to the pub after and it was good',
        'Sadeq said: my heart flutters when she does that',
        'Sadeq said: he threw a dart and missed completely',
      ]) {
        expect(
          classifyLegacyMemory(summary).isTechnical,
          isFalse,
          reason: summary,
        );
      }
    });

    test('one weak signal is not enough, two are', () {
      final one = classifyLegacyMemory('Sadeq said: the api felt slow today');
      expect(one.isTechnical, isFalse);
      expect(one.reason, contains('below the threshold'));

      final two = classifyLegacyMemory(
        'I said: the api endpoint is returning stale rows',
      );
      expect(two.isTechnical, isTrue);
      expect(two.signals.length, greaterThanOrEqualTo(2));
    });

    test('never returns a widening verdict', () {
      // The type system carries the guarantee: there is no "personal" verdict
      // to return. If someone adds one, this test is where they find out that
      // deterministic widening was a deliberate omission, not an oversight.
      expect(MemoryPrefilterVerdict.values, [
        MemoryPrefilterVerdict.technical,
        MemoryPrefilterVerdict.unclear,
      ]);
    });

    test('empty and unknown text abstain rather than guess', () {
      expect(classifyLegacyMemory('').isTechnical, isFalse);
      expect(classifyLegacyMemory('   ').isTechnical, isFalse);
      expect(classifyLegacyMemory('Sadeq said: hey').isTechnical, isFalse);
    });
  });

  group('triage pass — additive by construction', () {
    final rows = <String, dynamic>{
      'a': {'summary': 'I said: see lib/main.dart', 'scope': null},
      'b': {'summary': 'Sadeq said: I am proud of us', 'scope': null},
      'c': {
        'summary': 'Sadeq said: already classified',
        'scope': 'relationship',
      },
    };

    test('only legacy rows are considered', () async {
      final report = await KaiMemoryPromotionService.instance
          .triage('truekai', rowsForTest: rows);

      expect(report.totalRows, 3);
      expect(report.legacyRows, 2, reason: 'the scoped row is not revisited');
      expect(report.technical.single.shardId, 'a');
      expect(report.unclear.single.shardId, 'b');
    });

    test('dry run is the default and writes nothing', () async {
      final report = await KaiMemoryPromotionService.instance
          .triage('truekai', rowsForTest: rows);
      expect(report.proposalsWritten, 0);
    });

    test('proposals only ever narrow, and carry their provenance', () {
      const entry = MemoryTriageEntry(
        shardId: 'a',
        summary: 'I said: see lib/main.dart',
        verdict: MemoryPrefilterVerdict.technical,
        reason: 'file path with a code extension',
        signals: ['strong:filepath'],
      );
      final proposal = entry.toProposal(nowMs: 42);

      expect(proposal['proposedScope'], 'privateCore');
      expect(proposal['provenance'], 'promoted');
      expect(proposal['sourceShardId'], 'a');
      expect(proposal['status'], 'proposed');
    });

    test('the report names what it could not decide', () async {
      final report = await KaiMemoryPromotionService.instance
          .triage('truekai', rowsForTest: rows);
      final text = report.summarize();

      expect(text, contains('legacyUnscoped'));
      expect(text, contains('stay legacyUnscoped'));
      expect(text, contains('read these before applying'));
    });
  });
}
