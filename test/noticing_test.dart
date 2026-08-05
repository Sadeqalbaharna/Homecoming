// noticing — finding what Kai should say first, in his own graph.
//
// The point of this file is the ANTI-horoscope guarantee: every observation
// names the exact edges it came from, and a graph with nothing genuinely odd in
// it produces SILENCE, not manufactured insight. A "noticer" that always finds
// something is a horoscope; these tests exist to keep it honest.

import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/logic/noticing.dart';
import 'package:homecoming_app/logic/recall_query.dart';

EdgeRow e(String from, String type, String to,
        {double confidence = 0.7, DateTime? gone}) =>
    EdgeRow(
      fromLabel: from,
      toLabel: to,
      type: type,
      confidence: confidence,
      supersededAt: gone,
    );

void main() {
  group('contradiction — the sharpest thing he can notice', () {
    test('likes AND dislikes the same thing', () {
      final g = [
        e('Sadeq', 'prefers', 'the Tavern', confidence: 0.9),
        e('Sadeq', 'dislikes', 'the Tavern', confidence: 0.8),
      ];
      final n = noticings(g);
      expect(n.first.kind, NoticeKind.contradiction);
      // The receipt: it must name both edges it was built from.
      expect(n.first.evidence, hasLength(2));
      expect(n.first.evidence.any((s) => s.contains('prefers')), isTrue);
      expect(n.first.evidence.any((s) => s.contains('dislikes')), isTrue);
    });

    test('preferring TWO DIFFERENT things is NOT a contradiction', () {
      // The false-positive that had to be designed out: you can prefer many
      // things. Only opposed relations on the SAME object clash.
      final g = [
        e('Sadeq', 'prefers', 'Digimon'),
        e('Sadeq', 'prefers', 'working at 4am'),
      ];
      expect(
        noticings(g).any((o) => o.kind == NoticeKind.contradiction),
        isFalse,
      );
    });
  });

  group('reconsidered — a change only he witnessed', () {
    test('a retired claim with a live replacement', () {
      final g = [
        e('Sadeq', 'prefers', 'mornings',
            confidence: 0.5, gone: DateTime(2026, 1, 1)),
        e('Sadeq', 'prefers', 'working at 4am', confidence: 0.8),
      ];
      final recon = noticings(g).where((o) => o.kind == NoticeKind.reconsidered);
      expect(recon, isNotEmpty);
      expect(recon.first.text, contains('used to'));
      expect(recon.first.evidence.any((s) => s.contains('(was)')), isTrue);
      expect(recon.first.evidence.any((s) => s.contains('(now)')), isTrue);
    });

    test('a retired claim with NO replacement is not resurfaced as a change', () {
      final g = [
        e('Sadeq', 'prefers', 'mornings',
            confidence: 0.5, gone: DateTime(2026, 1, 1)),
      ];
      expect(
        noticings(g).any((o) => o.kind == NoticeKind.reconsidered),
        isFalse,
      );
    });
  });

  group('gap — the honest edge of what he knows', () {
    test('a strong preference with no reason on record', () {
      final g = [
        e('Sadeq', 'prefers', 'Walker Scobell', confidence: 0.9),
      ];
      final gap = noticings(g).where((o) => o.kind == NoticeKind.gap);
      expect(gap, isNotEmpty);
      expect(gap.first.text.toLowerCase(), contains("don't"));
    });

    test('no gap when the WHY is on record', () {
      final g = [
        e('Sadeq', 'prefers', 'Walker Scobell', confidence: 0.9),
        e('Sadeq', 'believes', 'Walker Scobell', confidence: 0.8),
      ];
      expect(noticings(g).any((o) => o.kind == NoticeKind.gap), isFalse);
    });

    test('no gap about a thing he is only half-sure of', () {
      // Wondering out loud about a shaky guess is worse than silence.
      final g = [e('Sadeq', 'prefers', 'a thing', confidence: 0.4)];
      expect(noticings(g).any((o) => o.kind == NoticeKind.gap), isFalse);
    });
  });

  group('the whole point: silence when there is nothing to notice', () {
    test('a clean, consistent graph produces NO observations', () {
      // Every claim distinct, supported, none opposed, each with a reason.
      final g = [
        e('Sadeq', 'prefers', 'Digimon', confidence: 0.9),
        e('Sadeq', 'believes', 'Digimon', confidence: 0.8),
        e('Kai', 'caresAbout', 'Sadeq', confidence: 0.95),
      ];
      expect(noticings(g), isEmpty,
          reason: 'a noticer that always finds something is a horoscope');
    });

    test('junk edges never become observations', () {
      final g = [
        e('chat', 'related', 'message'),
        e('Sadeq', 'mentioned', 'stuff'),
      ];
      expect(noticings(g), isEmpty);
    });

    test('empty graph', () => expect(noticings(const []), isEmpty));
  });

  group('ranking — hardest evidence first', () {
    test('a contradiction outranks a gap', () {
      final g = [
        e('Sadeq', 'prefers', 'the Tavern', confidence: 0.9),
        e('Sadeq', 'dislikes', 'the Tavern', confidence: 0.9),
        e('Sadeq', 'wants', 'a soul first', confidence: 0.9), // a lone gap
      ];
      expect(noticings(g).first.kind, NoticeKind.contradiction);
    });

    test('every observation carries its evidence — no exceptions', () {
      final g = [
        e('Sadeq', 'prefers', 'the Tavern', confidence: 0.9),
        e('Sadeq', 'dislikes', 'the Tavern', confidence: 0.9),
        e('Sadeq', 'wants', 'a soul first', confidence: 0.9),
      ];
      for (final o in noticings(g)) {
        expect(o.evidence, isNotEmpty,
            reason: 'an observation that cannot name its source is a horoscope');
      }
    });
  });
}
