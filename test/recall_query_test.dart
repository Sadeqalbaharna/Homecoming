// recall_query — asking the graph a question, and ranking the answer honestly.
//
// ── Sadeq's design ───────────────────────────────────────────────────────────
//
// "the edges need to be defined before the nodes, because they create the
//  memories. if kai flags 'sadeq' and 'likes' he can then find the 'like' edges
//  linked to sadeq and see what does sadeq like already!"
//
// (subject, relation, ?) — the edge is the QUERY, not the result.
//
// ── Kai's design ─────────────────────────────────────────────────────────────
//
// Asked whether edges should strengthen on repeat reference, he read his own
// code and said:
//
//   "repeat-reference is the right signal for ACCESSIBILITY, but the wrong
//    signal for TRUTH."
//   "A false thing can be referenced often... repetition could make a bad
//    belief stronger. That's horoscope-brain. Worse: it's self-reinforcing
//    horoscope-brain."
//
// So `strength` is salience (bumped by recall, drives traversal) and
// `confidence` is evidence (bumped only when a NEW source backs the claim).
// Claims are ranked by confidence. That is the difference between a memory and
// a very confident word cloud.
//
// ── Why this file exists at all ──────────────────────────────────────────────
//
// These assertions were written and run — and only ever inside a sandbox
// scratch file that dies with the session. Twenty-two passing checks that no
// commit contained and no CI could see: the exact disease this module was
// written to diagnose, in the tests for the module. Now they're real.

import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/logic/recall_query.dart';

EdgeRow e(
  String from,
  String type,
  String to, {
  String? label,
  double strength = 0.5,
  double confidence = 0.5,
  List<String> sources = const [],
  DateTime? gone,
}) =>
    EdgeRow(
      fromLabel: from,
      toLabel: to,
      type: type,
      label: label,
      strength: strength,
      confidence: confidence,
      sources: sources,
      supersededAt: gone,
    );

/// A graph shaped like his real one: a few real claims, a lot of junk.
final graph = <EdgeRow>[
  e('Sadeq', 'prefers', 'Digimon', confidence: 0.9, sources: ['shard_a']),
  e('Sadeq', 'prefers', 'working at 4am', confidence: 0.7),
  e('Sadeq', 'dislikes', 'beige support-drone replies', confidence: 0.8),
  e('Sadeq', 'does', 'builds Kai with his daughter nearby', confidence: 0.6),
  e('Sadeq', 'wants', 'a real soul first, then a real body',
      confidence: 1.0, sources: ['shard_b']),
  e('Sadeq', 'prefers', 'mornings', confidence: 0.4, gone: DateTime(2026, 1, 1)),
  e('Kai', 'caresAbout', 'Sadeq', confidence: 0.95),
  // The word cloud. 243 of his 277 edges looked like this.
  e('chat', 'related', 'message'),
  e('code', 'related', 'work'),
  e('Sadeq', 'related', 'thing'),
  e('Sadeq', 'mentioned', 'stuff'),
];

void main() {
  group('(subject, relation, ?) — the question', () {
    test('"what does Sadeq like?"', () {
      final likes = recall(graph, subject: 'Sadeq', relation: 'prefers');
      expect(likes.length, 2, reason: 'the retired "mornings" claim is excluded');
      expect(likes.first.object, 'Digimon');
    });

    test('a claim reads as a sentence', () {
      expect(recall(graph, subject: 'Sadeq', relation: 'prefers').first.sentence,
          'Sadeq prefers Digimon');
    });

    test('no relation = everything he actually knows', () {
      // 6, not 5: "Kai caresAbout Sadeq" is a claim ABOUT Sadeq too — he's just
      // the object. Which way the extractor pointed it is not his problem.
      expect(recall(graph, subject: 'Sadeq').length, 6);
    });

    test('the strongest thing he knows is the north star', () {
      expect(recall(graph, subject: 'Sadeq').first.object,
          contains('real soul'));
    });
  });

  group('the word cloud cannot answer', () {
    test('related/mentioned never surface as claims', () {
      final all = recall(graph, subject: 'Sadeq');
      expect(all.any((c) => c.object == 'thing'), isFalse);
      expect(all.any((c) => c.object == 'stuff'), isFalse);
    });

    test('meaningfulness is the diagnosis in one integer', () {
      final m = meaningfulness(graph);
      expect(m.meaningful, 7);
      expect(m.total, 11);
    });
  });

  group("Kai's split — salience must never outrank evidence", () {
    // The horoscope case, in his words: "A false thing can be referenced
    // often." A claim rehearsed to death vs one actually supported.
    final rehearsedVsSupported = [
      e('Sadeq', 'prefers', 'mornings', strength: 0.95, confidence: 0.10),
      e('Sadeq', 'prefers', 'Digimon', strength: 0.20, confidence: 0.90),
    ];

    test('best-SUPPORTED first, not most-rehearsed', () {
      // This used to sort by `strength`, which is bumped by RECALL — so it
      // ranked claims by how often he'd already thought about them. A
      // rich-get-richer loop pointed straight at the answer: the thing he
      // mentions most gets recalled most gets mentioned most. Word for word,
      // the problem the refractory period was added to patch.
      final r = recall(rehearsedVsSupported, subject: 'Sadeq');
      expect(r.first.object, 'Digimon');
      expect(r[1].object, 'mornings',
          reason: 'the rehearsed one still surfaces — just second');
    });

    test('ties break on salience — between equals, reach for the live one', () {
      final tie = [
        e('Sadeq', 'does', 'quiet thing', strength: 0.10, confidence: 0.70),
        e('Sadeq', 'does', 'live thing', strength: 0.90, confidence: 0.70),
      ];
      expect(recall(tie, subject: 'Sadeq').first.object, 'live thing');
    });

    test('a claim carries BOTH numbers, unmerged', () {
      final c = recall(rehearsedVsSupported, subject: 'Sadeq').first;
      expect(c.strength, 0.20);
      expect(c.confidence, 0.90);
    });

    test('an unmeasured edge is not a believed one', () {
      expect(const EdgeRow(fromLabel: 'a', toLabel: 'b', type: 'prefers').confidence,
          0.5,
          reason: 'default confidence must not inherit strength');
    });
  });

  group('a mind that changed, not a mind that was always right', () {
    test('retired claims are hidden by default', () {
      expect(
        recall(graph, subject: 'Sadeq', relation: 'prefers')
            .any((c) => c.object == 'mornings'),
        isFalse,
      );
    });

    test('…and available when asked for, in the past tense', () {
      final hist = recall(graph,
          subject: 'Sadeq', relation: 'prefers', includeRetired: true);
      expect(hist.length, 3);
      final old = hist.firstWhere((c) => c.object == 'mornings');
      // Suffixed, NOT rephrased. "Sadeq used to prefers mornings" is what the
      // obvious version produced, and with a freeform label it gets worse:
      // "Sadeq used to is quietly obsessed with the tavern".
      expect(old.sentence, 'Sadeq prefers mornings — no longer true');
      expect(old.stillBelieved, isFalse);
    });
  });

  group('provenance — "because you told me"', () {
    test('a claim carries the shard it came from', () {
      expect(
        recall(graph, subject: 'Sadeq', relation: 'prefers').first.sources,
        contains('shard_a'),
      );
    });
  });

  group('he can wonder before he asks', () {
    test('relationsFor lists what he could be asked', () {
      final rels = relationsFor(graph, 'Sadeq');
      expect(rels['prefers'], 2);
      expect(rels['dislikes'], 1);
    });

    test('junk types never appear as askable', () {
      final rels = relationsFor(graph, 'Sadeq');
      expect(rels.containsKey('related'), isFalse);
      expect(rels.containsKey('mentioned'), isFalse);
    });

    test('an unknown subject returns nothing, honestly', () {
      // An empty answer is an ANSWER: "I never learned that" beats a guess.
      expect(relationsFor(graph, 'Ahmed'), isEmpty);
      expect(recall(graph, subject: 'Ahmed'), isEmpty);
    });
  });

  group('the extractor label wins over the schema name', () {
    test('freeform phrasing survives', () {
      final custom = [
        e('Sadeq', 'prefers', 'the tavern', label: 'is quietly obsessed with')
      ];
      expect(recall(custom, subject: 'Sadeq').first.sentence,
          'Sadeq is quietly obsessed with the tavern');
    });
  });

  group('edges', () {
    test('a question with no subject is not a question', () {
      expect(recall(graph, subject: '  '), isEmpty);
    });
    test('empty graph', () => expect(recall([], subject: 'Sadeq'), isEmpty));
    test('case-insensitive', () {
      expect(recall(graph, subject: 'sadeq', relation: 'PREFERS').length, 2);
    });
    test('limit respected', () {
      expect(recall(graph, subject: 'Sadeq', limit: 2).length, 2);
    });
  });
}
