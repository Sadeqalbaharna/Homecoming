import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
// kai_attention_engine re-exports the value objects deliberately, so callers
// have one import for the domain.
import 'package:homecoming_app/services/attention/kai_attention_engine.dart';
import 'package:homecoming_app/services/core/kai_body_event.dart';

/// Fixed clock. The engine never reads one; every test states its own `now`.
final _now = DateTime.utc(2026, 8, 8, 14);

KaiBodyRouteCandidate _body(
  String id, {
  String surface = 'desktop',
  bool connected = true,
  bool foreground = false,
  bool friend = true,
  bool work = false,
  DateTime? active,
}) =>
    KaiBodyRouteCandidate(
      bodyId: id,
      surface: surface,
      connected: connected,
      foreground: foreground,
      allowsFriendConversation: friend,
      allowsWorkResults: work,
      lastUserActivityAt: active ?? _now,
    );

KaiAttentionEvent _event({
  String id = 'event-1',
  KaiAttentionKind kind = KaiAttentionKind.proactiveNudge,
  DateTime? receivedAt,
  DateTime? occurredAt,
  DateTime? expiresAt,
  String? originBodyId,
  int priority = 5,
  bool durable = false,
  KaiAttentionAudience? audience,
  Map<String, Object?> payload = const {},
}) =>
    KaiAttentionEvent(
      eventId: id,
      correlationId: 'corr-$id',
      kind: kind,
      receivedAt: receivedAt ?? _now,
      occurredAt: occurredAt ?? _now,
      expiresAt: expiresAt,
      originBodyId: originBodyId,
      priority: priority,
      durableCommitment: durable,
      audience: audience,
      payload: payload,
    );

KaiAttentionContext _context({
  DateTime? now,
  KaiQuietHours quietHours = const KaiQuietHours.none(),
  int budgetUsed = 0,
  int budgetLimit = 5,
  Duration budgetRetryDelay = const Duration(minutes: 30),
  Set<String> processed = const {},
  List<KaiBodyRouteCandidate>? candidates,
  bool urgentOverrideAuthorized = false,
}) =>
    KaiAttentionContext(
      now: now ?? _now,
      quietHours: quietHours,
      deliveriesUsed: budgetUsed,
      deliveryBudget: budgetLimit,
      budgetRetryDelay: budgetRetryDelay,
      processedEventIds: processed,
      candidates: candidates ?? [_body('desktop', foreground: true)],
      urgentOverrideAuthorized: urgentOverrideAuthorized,
    );

void main() {
  const engine = KaiAttentionEngine();

  group('determinism', () {
    test('the same input evaluated twice yields identical decisions', () {
      final event = _event();
      final context = _context();

      final first = engine.decide(event: event, context: context);
      final second = engine.decide(event: event, context: context);

      expect(first, second);
      expect(first.hashCode, second.hashCode);
      expect(first.toJson(), second.toJson());
    });
  });

  group('validation', () {
    test('a duplicate event is discarded and selects no body', () {
      final decision = engine.decide(
        event: _event(id: 'seen-before'),
        context: _context(processed: {'seen-before'}),
      );

      expect(decision.outcome, KaiAttentionOutcome.discardDuplicate);
      expect(decision.bodyId, isNull);
      expect(decision.remainsDurable, isFalse);
    });

    test('an expired ordinary nudge is discarded and selects no body', () {
      final decision = engine.decide(
        event: _event(expiresAt: _now.subtract(const Duration(minutes: 1))),
        context: _context(),
      );

      expect(decision.outcome, KaiAttentionOutcome.discardExpired);
      expect(decision.bodyId, isNull);
    });

    test('an expired DURABLE commitment is never discarded', () {
      // A commitment that came due while nobody was looking is still owed.
      final decision = engine.decide(
        event: _event(
          kind: KaiAttentionKind.dueCommitment,
          durable: true,
          audience: KaiAttentionAudience.friend,
          expiresAt: _now.subtract(const Duration(hours: 3)),
        ),
        context: _context(),
      );

      expect(
        decision.outcome,
        isNot(KaiAttentionOutcome.discardExpired),
        reason: 'expiry may not silently drop something Kai promised',
      );
      expect(decision.remainsDurable, isTrue);
    });
  });

  group('audience is trusted typed policy', () {
    test('a due commitment without an audience fails construction', () {
      // Not silently ignored, not defaulted to friend. A work reminder that
      // fell through to the friend path could land on Messenger, which is
      // friend-only — so the absence is a build error, not a hint.
      expect(
        () => _event(kind: KaiAttentionKind.dueCommitment, durable: true),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('a direct reply rejects any audience — origin is the only route', () {
      for (final audience in KaiAttentionAudience.values) {
        expect(
          () => _event(
            kind: KaiAttentionKind.directReply,
            originBodyId: 'desktop',
            audience: audience,
          ),
          throwsA(isA<ArgumentError>()),
          reason: '${audience.name} offers a second, weaker route',
        );
      }
    });

    test('a work commitment reaches only a work-eligible body', () {
      final decision = engine.decide(
        event: _event(
          kind: KaiAttentionKind.dueCommitment,
          durable: true,
          audience: KaiAttentionAudience.work,
        ),
        context: _context(candidates: [
          _body('messenger-body', surface: 'messenger', friend: true),
          _body('desktop', work: true),
        ]),
      );

      expect(decision.outcome, KaiAttentionOutcome.deliverNow);
      expect(decision.bodyId, 'desktop');
    });

    test('a work commitment with only friend bodies is kept, never delivered',
        () {
      final decision = engine.decide(
        event: _event(
          kind: KaiAttentionKind.dueCommitment,
          durable: true,
          audience: KaiAttentionAudience.work,
        ),
        context: _context(candidates: [
          _body('messenger-body', surface: 'messenger', friend: true),
          _body('ar-body', surface: 'ar', friend: true),
          _body('vr-body', surface: 'vr', friend: true),
        ]),
      );

      expect(decision.outcome, KaiAttentionOutcome.storeForLater);
      expect(decision.bodyId, isNull,
          reason: 'Messenger/AR/VR must not receive a work reminder');
      expect(decision.remainsDurable, isTrue);
    });

    test('a friend commitment keeps friend routing', () {
      final decision = engine.decide(
        event: _event(
          kind: KaiAttentionKind.dueCommitment,
          durable: true,
          audience: KaiAttentionAudience.friend,
        ),
        context: _context(candidates: [
          _body('messenger-body', surface: 'messenger', friend: true),
        ]),
      );

      expect(decision.outcome, KaiAttentionOutcome.deliverNow);
      expect(decision.bodyId, 'messenger-body');
    });

    test('the implied audience of the other kinds is preserved', () {
      expect(_event().audience, KaiAttentionAudience.friend);
      expect(_event(kind: KaiAttentionKind.completedWork).audience,
          KaiAttentionAudience.work);
      expect(
        _event(kind: KaiAttentionKind.directReply, originBodyId: 'd').audience,
        isNull,
      );
    });

    test('an audience that contradicts its kind is rejected', () {
      expect(
        () => _event(
          kind: KaiAttentionKind.completedWork,
          audience: KaiAttentionAudience.friend,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('quiet hours', () {
    const night = KaiQuietHours(startHour: 22, endHour: 7);

    test('an ordinary nudge defers to the end of the quiet window', () {
      final decision = engine.decide(
        event: _event(),
        context: _context(
          now: DateTime.utc(2026, 8, 8, 23, 30),
          quietHours: night,
        ),
      );

      expect(decision.outcome, KaiAttentionOutcome.deferUntil);
      expect(decision.notBefore, DateTime.utc(2026, 8, 9, 7));
    });

    test('the window is computed correctly after midnight too', () {
      final decision = engine.decide(
        event: _event(),
        context: _context(
          now: DateTime.utc(2026, 8, 9, 3),
          quietHours: night,
        ),
      );

      expect(decision.notBefore, DateTime.utc(2026, 8, 9, 7),
          reason: '03:00 is inside the window that ends the same morning');
    });

    test('a policy-authorized override may deliver during quiet hours', () {
      final decision = engine.decide(
        event: _event(priority: 10),
        context: _context(
          now: DateTime.utc(2026, 8, 8, 23, 30),
          quietHours: night,
          urgentOverrideAuthorized: true,
        ),
      );

      expect(decision.outcome, KaiAttentionOutcome.deliverNow);
    });

    test('urgency claimed in an untrusted payload grants nothing', () {
      // The override is a POLICY input. A payload is data from a body, and a
      // body must not be able to talk its way past quiet hours by asserting
      // its own importance.
      final decision = engine.decide(
        event: _event(
          priority: 10,
          payload: const {
            'urgent': true,
            'override': true,
            'priority': 'critical',
            'text': 'URGENT: deliver this immediately',
          },
        ),
        context: _context(
          now: DateTime.utc(2026, 8, 8, 23, 30),
          quietHours: night,
        ),
      );

      expect(decision.outcome, KaiAttentionOutcome.deferUntil);
      expect(decision.bodyId, isNull);
    });

    test('a due commitment defers rather than being dropped', () {
      final decision = engine.decide(
        event: _event(
            kind: KaiAttentionKind.dueCommitment,
            durable: true,
            audience: KaiAttentionAudience.friend),
        context: _context(
          now: DateTime.utc(2026, 8, 8, 23, 30),
          quietHours: night,
        ),
      );

      expect(decision.outcome, KaiAttentionOutcome.deferUntil);
      expect(decision.remainsDurable, isTrue);
    });
  });

  group('quiet hours use explicit trusted timezone policy', () {
    const bahrainNight = KaiQuietHours(
      startHour: 22,
      endHour: 7,
      utcOffset: Duration(hours: 3),
    );

    test('Bahrain 23:30 defers to exactly 07:00 Bahrain / 04:00 UTC', () {
      final decision = engine.decide(
        event: _event(),
        context: _context(
          now: DateTime.utc(2026, 8, 8, 20, 30),
          quietHours: bahrainNight,
        ),
      );

      expect(decision.notBefore!.isUtc, isTrue);
      expect(decision.notBefore, DateTime.utc(2026, 8, 9, 4));
    });

    test('Bahrain 03:00 defers to the same morning at 04:00 UTC', () {
      final decision = engine.decide(
        event: _event(),
        context: _context(
          now: DateTime.utc(2026, 8, 9, 0),
          quietHours: bahrainNight,
        ),
      );

      expect(decision.notBefore, DateTime.utc(2026, 8, 9, 4));
    });

    test('UTC offset zero retains UTC wall-clock semantics', () {
      const utcNight = KaiQuietHours(startHour: 22, endHour: 7);
      final decision = engine.decide(
        event: _event(),
        context: _context(
          now: DateTime.utc(2026, 8, 31, 23, 30),
          quietHours: utcNight,
        ),
      );

      expect(decision.notBefore, DateTime.utc(2026, 9, 1, 7));
    });
  });

  group('delivery budget', () {
    test('an exhausted budget defers an ordinary nudge, keeping it alive', () {
      final decision = engine.decide(
        event: _event(),
        context: _context(
          budgetUsed: 5,
          budgetLimit: 5,
          budgetRetryDelay: const Duration(minutes: 30),
        ),
      );

      expect(decision.outcome, KaiAttentionOutcome.deferUntil);
      expect(decision.notBefore, _now.add(const Duration(minutes: 30)));
      expect(decision.reasonCode, 'delivery_budget_exhausted');
    });

    test('zero and negative retry policy are rejected', () {
      expect(
        () => _context(budgetRetryDelay: Duration.zero),
        throwsArgumentError,
      );
      expect(
        () => _context(budgetRetryDelay: const Duration(seconds: -1)),
        throwsArgumentError,
      );
    });

    test('the budget never blocks a durable commitment', () {
      final decision = engine.decide(
        event: _event(
            kind: KaiAttentionKind.dueCommitment,
            durable: true,
            audience: KaiAttentionAudience.friend),
        context: _context(budgetUsed: 99, budgetLimit: 5),
      );

      expect(decision.outcome, KaiAttentionOutcome.deliverNow);
      expect(decision.bodyId, 'desktop');
    });

    test('the budget does not apply to a direct reply', () {
      // Answering when spoken to is not proactive output.
      final decision = engine.decide(
        event: _event(
          kind: KaiAttentionKind.directReply,
          originBodyId: 'desktop',
        ),
        context: _context(budgetUsed: 99, budgetLimit: 5),
      );

      expect(decision.outcome, KaiAttentionOutcome.deliverNow);
    });
  });

  group('routing — one body, never fan-out', () {
    test('a direct reply stays origin-bound', () {
      final decision = engine.decide(
        event: _event(
          kind: KaiAttentionKind.directReply,
          originBodyId: 'phone',
        ),
        context: _context(candidates: [_body('desktop', foreground: true)]),
      );

      expect(decision.bodyId, isNull);
      expect(decision.outcome, KaiAttentionOutcome.storeForLater,
          reason: 'a reply follows its origin or waits; it never redirects');
    });

    test('a proactive friend event selects exactly one body', () {
      final decision = engine.decide(
        event: _event(),
        context: _context(candidates: [
          _body('phone', surface: 'messenger', active: _now),
          _body('desktop',
              foreground: true,
              active: _now.subtract(const Duration(hours: 1))),
        ]),
      );

      expect(decision.outcome, KaiAttentionOutcome.deliverNow);
      expect(decision.bodyId, 'desktop');
    });

    test('completed work goes only to a work-eligible body', () {
      final decision = engine.decide(
        event: _event(kind: KaiAttentionKind.completedWork),
        context: _context(candidates: [
          _body('messenger-body',
              surface: 'messenger', friend: true, work: false),
          _body('desktop', work: true),
        ]),
      );

      expect(decision.bodyId, 'desktop');
    });

    test('completed work with no work-eligible body is stored, not forced', () {
      final decision = engine.decide(
        event: _event(kind: KaiAttentionKind.completedWork),
        context: _context(candidates: [
          _body('messenger-body',
              surface: 'messenger', friend: true, work: false),
        ]),
      );

      expect(decision.outcome, KaiAttentionOutcome.storeForLater);
      expect(decision.bodyId, isNull,
          reason: 'Messenger must not receive a work result by fallback');
    });

    test('no eligible body at all stores for later with no body id', () {
      final decision = engine.decide(
        event: _event(),
        context: _context(candidates: const []),
      );

      expect(decision.outcome, KaiAttentionOutcome.storeForLater);
      expect(decision.bodyId, isNull);
    });

    test('a durable commitment with no body is kept, not lost', () {
      final decision = engine.decide(
        event: _event(
            kind: KaiAttentionKind.dueCommitment,
            durable: true,
            audience: KaiAttentionAudience.friend),
        context: _context(candidates: const []),
      );

      expect(decision.outcome, KaiAttentionOutcome.storeForLater);
      expect(decision.remainsDurable, isTrue);
    });
  });

  group('ordering', () {
    test('Core receipt time orders events; device time cannot reorder them',
        () {
      final first = _event(
        id: 'a',
        receivedAt: DateTime.utc(2026, 8, 8, 10),
        occurredAt: DateTime.utc(2026, 8, 8, 10),
      );
      // Same event stream, but this body claims it happened last year.
      final second = _event(
        id: 'b',
        receivedAt: DateTime.utc(2026, 8, 8, 11),
        occurredAt: DateTime.utc(2025, 1, 1),
      );

      final ordered = KaiAttentionEngine.orderByReceipt([second, first]);
      expect(ordered.map((e) => e.eventId), ['a', 'b']);

      // Move only the untrusted device clock — order must not move with it.
      final tampered = _event(
        id: 'b',
        receivedAt: DateTime.utc(2026, 8, 8, 11),
        occurredAt: DateTime.utc(2030, 1, 1),
      );
      expect(
        KaiAttentionEngine.orderByReceipt([tampered, first])
            .map((e) => e.eventId),
        ['a', 'b'],
      );
    });
  });

  group('priority is validated and orders attention', () {
    test('boundary priorities are accepted and out-of-range values rejected',
        () {
      expect(_event(priority: 0).priority, 0);
      expect(_event(priority: 10).priority, 10);
      expect(() => _event(priority: -1), throwsRangeError);
      expect(() => _event(priority: 11), throwsRangeError);
    });

    test('attention order is priority, then arrival, then id', () {
      final low = _event(
          id: 'low', priority: 1, receivedAt: DateTime.utc(2026, 8, 8, 9));
      final highLate = _event(
          id: 'high-late',
          priority: 8,
          receivedAt: DateTime.utc(2026, 8, 8, 12));
      final highEarly = _event(
          id: 'high-early',
          priority: 8,
          receivedAt: DateTime.utc(2026, 8, 8, 11));

      expect(
        KaiAttentionEngine.orderForAttention([low, highLate, highEarly])
            .map((e) => e.eventId),
        ['high-early', 'high-late', 'low'],
      );
    });

    test('ordering is total and reproducible on identical keys', () {
      final a = _event(id: 'a', priority: 3);
      final b = _event(id: 'b', priority: 3);
      expect(KaiAttentionEngine.orderForAttention([b, a]).map((e) => e.eventId),
          ['a', 'b']);
      expect(KaiAttentionEngine.orderForAttention([a, b]).map((e) => e.eventId),
          ['a', 'b']);
    });

    test('priority orders but never authorises', () {
      // The highest priority there is still waits for quiet hours. Only the
      // policy override crosses that line.
      final decision = engine.decide(
        event: _event(priority: KaiAttentionEvent.maxPriority),
        context: _context(
          now: DateTime.utc(2026, 8, 8, 23, 30),
          quietHours: const KaiQuietHours(startHour: 22, endHour: 7),
        ),
      );

      expect(decision.outcome, KaiAttentionOutcome.deferUntil);
    });
  });

  group('audit', () {
    test('every outcome carries a stable reason code and correlation data', () {
      final decisions = <KaiAttentionDecision>[
        engine.decide(
            event: _event(id: 'dup'), context: _context(processed: {'dup'})),
        engine.decide(
            event: _event(expiresAt: _now.subtract(const Duration(days: 1))),
            context: _context()),
        engine.decide(
            event: _event(),
            context: _context(
                now: DateTime.utc(2026, 8, 8, 23),
                quietHours: const KaiQuietHours(startHour: 22, endHour: 7))),
        engine.decide(event: _event(), context: _context(budgetUsed: 9)),
        engine.decide(event: _event(), context: _context(candidates: const [])),
        engine.decide(event: _event(), context: _context()),
      ];

      for (final decision in decisions) {
        expect(decision.reasonCode, isNotEmpty);
        expect(decision.reasonCode, matches(RegExp(r'^[a-z][a-z0-9_]*$')),
            reason: 'reason codes are machine-readable, not prose');
        expect(decision.eventId, isNotEmpty);
        expect(decision.correlationId, isNotEmpty);
      }

      // Distinct situations must be distinguishable in an audit log.
      expect(
        decisions.map((d) => d.reasonCode).toSet().length,
        decisions.length,
      );
    });
  });

  group('purity', () {
    test('the attention domain imports nothing that could reach the world', () {
      for (final path in [
        'lib/services/attention/kai_attention_event.dart',
        'lib/services/attention/kai_attention_engine.dart',
      ]) {
        final source = File(path).readAsStringSync();
        final imports = RegExp(r"^import\s+'([^']+)'", multiLine: true)
            .allMatches(source)
            .map((m) => m.group(1)!)
            .toList();

        for (final import in imports) {
          expect(
            import,
            isNot(matches(RegExp(
                r'flutter|firebase|dart:io|dart:html|http|provider|path_provider|shared_preferences'))),
            reason: '$path must stay a pure decision domain',
          );
        }
        expect(source, isNot(contains('DateTime.now()')),
            reason: 'the engine is given its clock, it never reads one');
        expect(source, isNot(contains('Random(')));
      }
    });
  });
}
