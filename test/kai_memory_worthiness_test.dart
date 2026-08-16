// Whether a model may widen a privacy scope, and everything that stops it.
//
// ── What this is guarding ────────────────────────────────────────────────────
//
// scopeForTurn used to end `if (route == fastChat) return sharedLife`, and
// fastChat is what the router returns when nothing matched. So "I could not
// classify this" meant "put it on Messenger". That is now inverted, and the
// classifier exists so the inversion does not simply make Kai forget the
// things worth keeping — "my sister is coming to stay" is exactly the turn a
// keyword router will never place and a friend should absolutely carry.
//
// Putting a model anywhere near a privacy boundary is only defensible because
// of the asymmetry these tests pin down: it can widen, never narrow; it can
// reach one scope, never any other; and every single way it can fail leaves
// the private answer standing. A turn that should have travelled and did not
// is a thinner Messenger. A turn that should not have travelled and did is not
// recoverable.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/services/core/kai_memory_scope.dart';
import 'package:homecoming_app/services/core/kai_memory_worthiness.dart';
import 'package:homecoming_app/services/core/kai_router_service.dart';
import 'package:homecoming_app/services/core/kai_surface_context.dart';

KaiMemoryWorthinessClassifier classifierReturning(
  List<Future<String?> Function(String, String)> providers, {
  double minimumConfidence = 0.7,
  Duration timeout = const Duration(seconds: 4),
}) =>
    KaiMemoryWorthinessClassifier(
      providers: providers,
      minimumConfidence: minimumConfidence,
      timeout: timeout,
    );

Future<String?> Function(String, String) says(String? raw) =>
    (_, __) async => raw;

void main() {
  group('reading a verdict is strict on purpose', () {
    test('a clean positive is understood', () {
      final v = parseMemoryWorthiness('{"personal": true, "confidence": 0.9}');
      expect(v.worthiness, KaiMemoryWorthiness.personal);
      expect(v.confidence, 0.9);
    });

    test('prose or a fence around the object is tolerated', () {
      // Small local models narrate. Refusing that would make the feature fail
      // for the exact class of model it was designed to run on.
      final v = parseMemoryWorthiness(
        'Sure! Here is the classification:\n'
        '```json\n{"personal": true, "confidence": 0.85}\n```\n'
        'Let me know if you need anything else.',
      );
      expect(v.worthiness, KaiMemoryWorthiness.personal);
      expect(v.confidence, 0.85);
    });

    test('a string "true" is not a boolean', () {
      // A model that cannot follow the schema is not one whose judgement
      // should widen a privacy scope.
      final v = parseMemoryWorthiness('{"personal": "true", "confidence": 1}');
      expect(v.worthiness, KaiMemoryWorthiness.unknown);
      expect(v.reasonCode, 'missing_verdict');
    });

    test('every malformed shape reads as unknown, never as yes', () {
      const bad = <String>[
        '',
        '   ',
        'yes',
        'personal: true',
        '{',
        '{"personal": true',
        '{"confidence": 0.9}',
        '{"personal": null, "confidence": 0.9}',
      ];
      for (final raw in bad) {
        expect(parseMemoryWorthiness(raw).worthiness,
            KaiMemoryWorthiness.unknown, reason: raw);
      }
      expect(parseMemoryWorthiness(null).worthiness, KaiMemoryWorthiness.unknown);
    });

    test('an object wrapped in an array still means what it says', () {
      // The extractor spans the first '{' to the last '}', which unwraps this.
      // Deliberately kept: the leniency is meaning-preserving, and the risk
      // being defended against is accepting a yes the model did NOT mean.
      //
      // Two verdicts in one response do not survive it — the span covers both
      // and stops being valid JSON, so "{...false...} actually {...true...}"
      // reads as unknown rather than picking one. That is the property that
      // makes the loose extraction safe, and it is why this is a separate,
      // named test rather than a quietly relaxed expectation.
      expect(
        parseMemoryWorthiness('[{"personal": true, "confidence": 0.9}]')
            .worthiness,
        KaiMemoryWorthiness.personal,
      );
      expect(
        parseMemoryWorthiness(
                '{"personal": false} but actually {"personal": true}')
            .worthiness,
        KaiMemoryWorthiness.unknown,
        reason: 'two verdicts is not one verdict',
      );
    });

    test('a confidence outside 0..1 is not a confidence', () {
      for (final raw in [
        '{"personal": true, "confidence": 1.4}',
        '{"personal": true, "confidence": -0.2}',
      ]) {
        expect(parseMemoryWorthiness(raw).reasonCode, 'bad_confidence');
      }
    });

    test('a missing confidence is zero, not assumed', () {
      final v = parseMemoryWorthiness('{"personal": true}');
      expect(v.worthiness, KaiMemoryWorthiness.personal);
      expect(v.confidence, 0);
    });
  });

  group('the classifier fails closed in every direction', () {
    test('no providers at all means the feature is simply off', () async {
      final v = await classifierReturning([]).classify(userText: 'anything');
      expect(v.worthiness, KaiMemoryWorthiness.unknown);
    });

    test('a provider that throws does not break the turn', () async {
      final v = await classifierReturning([
        (_, __) async => throw StateError('ollama is not running'),
      ]).classify(userText: 'my sister is visiting');
      expect(v.worthiness, KaiMemoryWorthiness.unknown);
    });

    test('a provider that hangs is abandoned, not waited for', () async {
      final v = await classifierReturning(
        [(_, __) => Completer<String?>().future],
        timeout: const Duration(milliseconds: 40),
      ).classify(userText: 'my sister is visiting');
      expect(v.worthiness, KaiMemoryWorthiness.unknown);
    });

    test('an unparseable first provider falls through to the next', () async {
      final v = await classifierReturning([
        says('I cannot help with that'),
        says('{"personal": true, "confidence": 0.9}'),
      ]).classify(userText: 'we went to the beach');
      expect(v.worthiness, KaiMemoryWorthiness.personal);
    });

    test('an empty exchange is never sent anywhere', () async {
      var called = false;
      final v = await classifierReturning([
        (_, __) async {
          called = true;
          return '{"personal": true, "confidence": 1}';
        },
      ]).classify(userText: '   ', kaiReply: '');
      expect(called, isFalse);
      expect(v.worthiness, KaiMemoryWorthiness.unknown);
    });
  });

  group('what the classifier is allowed to change', () {
    final marginal = scopeDecisionForTurn(
      context: KaiSurfaceContext.desktop,
      route: KaiRoute.fastChat,
      userText: 'my sister is coming to stay next week',
    );

    test('the margin is real — this turn is eligible', () {
      expect(marginal.marginal, isTrue);
      expect(marginal.scope, KaiMemoryScope.privateCore);
    });

    test('a confident yes promotes, and only to sharedLife', () async {
      final scope = await resolveMemoryScope(
        decision: marginal,
        classifier: classifierReturning(
            [says('{"personal": true, "confidence": 0.95}')]),
        userText: 'my sister is coming to stay next week',
      );
      expect(scope, KaiMemoryScope.sharedLife);
    });

    test('an unsure yes behaves exactly like an absent model', () async {
      final scope = await resolveMemoryScope(
        decision: marginal,
        classifier: classifierReturning(
          [says('{"personal": true, "confidence": 0.5}')],
          minimumConfidence: 0.7,
        ),
        userText: 'my sister is coming to stay next week',
      );
      expect(scope, KaiMemoryScope.privateCore);
    });

    test('a no keeps it private', () async {
      final scope = await resolveMemoryScope(
        decision: marginal,
        classifier: classifierReturning(
            [says('{"personal": false, "confidence": 0.99}')]),
        userText: 'rerun the deploy',
      );
      expect(scope, KaiMemoryScope.privateCore);
    });

    test('no classifier configured is the strict inversion', () async {
      final scope = await resolveMemoryScope(decision: marginal);
      expect(scope, KaiMemoryScope.privateCore);
    });

    test('a non-marginal turn never reaches the model at all', () async {
      var called = false;
      final technical = scopeDecisionForTurn(
        context: KaiSurfaceContext.desktop,
        route: KaiRoute.fastChat,
        userText: 'the firebase database rules are rejecting my write',
      );
      expect(technical.marginal, isFalse);

      final scope = await resolveMemoryScope(
        decision: technical,
        classifier: classifierReturning([
          (_, __) async {
            called = true;
            return '{"personal": true, "confidence": 1}';
          },
        ]),
        userText: 'the firebase database rules are rejecting my write',
      );
      expect(called, isFalse,
          reason: 'a decision made on evidence is not reopened by a model');
      expect(scope, KaiMemoryScope.privateCore);
    });

    test('an enthusiastic model cannot reach a scope it was not offered',
        () async {
      // The promotion target is fixed by the pure decision, not by the model.
      // Even a maximally confident yes only ever lands on sharedLife.
      final scope = await resolveMemoryScope(
        decision: marginal,
        classifier: classifierReturning(
            [says('{"personal": true, "confidence": 1.0}')]),
        userText: 'anything at all',
      );
      expect(scope, KaiMemoryScope.sharedLife);
      expect(scope, isNot(KaiMemoryScope.identity));
      expect(scope, isNot(KaiMemoryScope.relationship));
    });

    test('the audit line carries a reason and never the message', () async {
      final seen = <String>[];
      await resolveMemoryScope(
        decision: marginal,
        classifier: classifierReturning(
            [says('{"personal": true, "confidence": 0.9}')]),
        userText: 'my sister Layla is coming to stay next week',
        onDecision: (reasonCode, _) => seen.add(reasonCode),
      );
      expect(seen.single, 'promoted_sharedLife');
      expect(seen.single, isNot(contains('Layla')));
    });

    test('a held turn says why it was held', () async {
      final seen = <String>[];
      await resolveMemoryScope(
        decision: marginal,
        classifier: classifierReturning([says('nonsense')]),
        userText: 'something',
        onDecision: (reasonCode, _) => seen.add(reasonCode),
      );
      expect(seen.single, 'held_closed');
    });
  });
}
