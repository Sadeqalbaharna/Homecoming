// The router's shrug is not a finding.
//
// ── What was happening ──────────────────────────────────────────────────────
//
// `route` starts as fastChat and only moves if a rule fires. So a turn nothing
// recognised came out as fastChat — indistinguishable, downstream, from "I am
// confident this is small talk."
//
// They are not the same claim, and the difference is expensive. fastChat drops
// ten of the fifteen live context blocks and cuts the self-context budget from
// 450 tokens to 120. So the questions the keyword list does not happen to
// cover got the THINNEST possible Kai, precisely because they were hardest to
// classify. "why did that break" matches nothing at all.
//
// ── The asymmetry worth keeping in mind ─────────────────────────────────────
//
// The memory write classifier was fixed the same day in the OPPOSITE
// direction. For privacy, an unclassified turn must fail CLOSED — absence of
// evidence is not evidence of intimacy. For capability, an unclassified turn
// must fail OPEN — absence of evidence is not evidence of triviality.
//
// Same shrug. Opposite safe defaults. Because the cost of being wrong points
// the other way: a trivial turn carrying full context costs a few cached
// tokens, while a hard turn stripped of context is an answer that quietly
// misses and nobody can see why.

import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/services/core/kai_context_manifest.dart';
import 'package:homecoming_app/services/core/kai_router_service.dart';

const _router = KaiRouterService();

KaiRouteDecision decide(String message, {bool hasActiveJob = false}) =>
    _router.decide(message, hasActiveJob: hasActiveJob);

void main() {
  group('the shrug is named', () {
    test('the question that started this is unmatched', () {
      final d = decide('why did that break');
      expect(d.route, KaiRoute.fastChat,
          reason: 'still the fallback shape — that part was never wrong');
      expect(d.unmatched, isTrue,
          reason: 'but nothing actually recognised it');
      expect(d.confidentlyTrivial, isFalse);
    });

    test('a genuinely small turn is matched, not shrugged', () {
      final d = decide('ok thanks');
      expect(d.route, KaiRoute.fastChat);
      expect(d.unmatched, isFalse,
          reason: 'length is real positive evidence, unlike silence');
      expect(d.confidentlyTrivial, isTrue);
    });

    test('short is not the same as trivial', () {
      // The first version of this fix used length alone, and "why did that
      // break" is nineteen characters — under the twenty-four-char threshold.
      // So the rule confidently declared the motivating example to be small
      // talk, and the fix silently did nothing for the one case it was written
      // for. A question is a request for thought at any length.
      // The invariant is about triviality, not about matching: "is it fixed"
      // legitimately routes to coding, because "fixed" is a debugging signal.
      // That is a recognised turn and gets the coding manifest. What none of
      // these may be is confidently small talk.
      for (final asked in const [
        'why did that break',
        'what broke',
        'is it fixed',
        'did it work?',
        'how come',
      ]) {
        expect(decide(asked).confidentlyTrivial, isFalse, reason: asked);
      }
      // Of those, the ones no rule recognises must fall open rather than thin.
      for (final unrecognised in const [
        'why did that break',
        'what broke',
        'how come',
      ]) {
        expect(decide(unrecognised).unmatched, isTrue, reason: unrecognised);
      }
      for (final small in const ['ok thanks', 'go on', 'nice', 'sure']) {
        expect(decide(small).confidentlyTrivial, isTrue, reason: small);
      }
    });

    test('a recognised route is never a shrug', () {
      for (final message in const [
        'can you refactor lib/services/core/kai_db.dart',
        'send a text to Layla',
        'i feel awful today and I cannot sleep',
      ]) {
        expect(decide(message).unmatched, isFalse, reason: message);
      }
    });

    test('a long unrecognised turn stays unmatched', () {
      // Length is what separates "ok" from a real question the list misses.
      final d = decide(
        'the thing we were looking at yesterday never settled properly and '
        'I keep coming back to it without getting anywhere',
      );
      expect(d.route, KaiRoute.fastChat);
      expect(d.unmatched, isTrue);
    });
  });

  group('an unmatched turn gets the full Kai', () {
    test('it keeps every context block', () {
      final shrug = KaiContextManifest.forDecision(decide('why did that break'));
      final full = KaiContextManifest.forRoute(null);
      expect(shrug.skippedIndices, isEmpty);
      expect(shrug.skippedIndices, full.skippedIndices);
    });

    test('a confidently trivial turn still trims', () {
      final small = KaiContextManifest.forDecision(decide('ok thanks'));
      expect(small.skippedIndices, isNotEmpty,
          reason: 'the saving is real when the router actually knows');
      expect(small.skippedIndices, KaiContextManifest.forRoute(KaiRoute.fastChat).skippedIndices);
    });

    test('the two turns get materially different context', () {
      final hard = KaiContextManifest.forDecision(decide('why did that break'));
      final small = KaiContextManifest.forDecision(decide('ok thanks'));
      expect(hard.included.length, greaterThan(small.included.length + 5),
          reason: 'ten blocks is the whole point of the fix');
    });

    test('a null decision is still the generous default', () {
      expect(KaiContextManifest.forDecision(null).skippedIndices, isEmpty);
    });
  });

  group('the flag defaults to a deliberate choice', () {
    test('a hand-built decision is not treated as a shrug', () {
      // Every existing caller and test constructs a decision on purpose.
      // Defaulting unmatched to false keeps that meaning.
      const d = KaiRouteDecision(
        route: KaiRoute.fastChat,
        confidence: 0.9,
        reasons: ['hand-built'],
      );
      expect(d.unmatched, isFalse);
      expect(d.confidentlyTrivial, isTrue);
      expect(KaiContextManifest.forDecision(d).skippedIndices, isNotEmpty);
    });
  });
}
