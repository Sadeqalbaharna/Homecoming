// Brief 016 — the coordinator's due-commitment loop.
//
// Real KaiCoreServer over loopback, real KaiCoreClient, real KaiAttentionEngine,
// real routing. Only the clock and the presence snapshot are injected, because
// those are the two things a test must control and the two things production
// reads from outside itself anyway.
//
// The scheduler under test is the PRODUCTION object the coordinator constructs
// — not a copy of its algorithm. Brief 015 taught that lesson the expensive
// way: a harness that re-implements the logic can only prove the copy agrees
// with the copy.
//
// Temp Core directories only. Nothing reads or writes the live Core state.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/services/attention/kai_attention_engine.dart';
import 'package:homecoming_app/services/core/kai_body_event.dart';
import 'package:homecoming_app/services/core/kai_core_client.dart';
import 'package:homecoming_app/services/core/kai_core_server.dart';
import 'package:homecoming_app/services/core/kai_due_commitment_scheduler.dart';
import 'package:homecoming_app/services/core/kai_global_presence_service.dart';

final _createdAt = DateTime.utc(2026, 8, 8, 12);
final _dueAt = DateTime.utc(2026, 9, 1, 6);

/// 09:00 Bahrain on the due date — comfortably outside quiet hours.
final _daytime = DateTime.utc(2026, 9, 1, 7);

/// 02:30 Bahrain — inside the 01:00–08:00 window.
final _night = DateTime.utc(2026, 9, 1, 23, 30);

const _desktopBody = 'desktop-body-abc123';
const _phoneBody = 'messenger-body-xyz789';
const _reminderText = 'chase the invoice';

class _Clock {
  DateTime now = _createdAt;
  DateTime call() => now;
}

class _JournalSpy {
  final List<Map<String, Object?>> entries = [];

  Future<void> call(
    String event, {
    String severity = 'info',
    Map<String, Object?> details = const {},
  }) async {
    entries.add({'event': event, 'severity': severity, ...details});
  }

  List<String> get events =>
      entries.map((e) => e['event'].toString()).toList(growable: false);

  int countOf(String event) => events.where((e) => e == event).length;
}

KaiGlobalBody _body(
  String bodyId,
  String surface, {
  bool foreground = true,
  DateTime? lastActivity,
}) =>
    KaiGlobalBody(
      bodyId: bodyId,
      deviceId: '$surface-device',
      surface: surface,
      leaseExpiresAt: DateTime.utc(2030),
      foreground: foreground,
      lastUserActivityAt: lastActivity ?? _createdAt,
    );

KaiGlobalPresenceSnapshot _presence(
  List<KaiGlobalBody> bodies, {
  bool connected = true,
}) =>
    KaiGlobalPresenceSnapshot(
      connected: connected,
      coordinatorLeaseExpiresAt: DateTime.utc(2030),
      bodies: bodies,
      observedAt: _createdAt,
    );

class _Fixture {
  _Fixture(this.clock, this.server, this.client, this.journal);

  final _Clock clock;
  final KaiCoreServer server;
  final KaiCoreClient client;
  final _JournalSpy journal;

  KaiGlobalPresenceSnapshot snapshot = _presence(const []);
  late KaiDueCommitmentScheduler scheduler;

  Future<List<Map<String, dynamic>>> commitments() => client.commitments();

  Future<Map<String, dynamic>> only() async => (await commitments()).single;

  Future<List<Map<String, dynamic>>> inbox(String bodyId) =>
      client.pendingOutbound(toSurface: 'desktop', bodyId: bodyId);
}

Future<_Fixture> _fixture(
  String name, {
  KaiQuietHours quietHours = const KaiQuietHours.none(),
  Duration noBodyRetry = const Duration(minutes: 5),
}) async {
  final directory = Directory.systemTemp.createTempSync('kai_due_$name');
  final clock = _Clock();
  final server =
      KaiCoreServer(dataDirectory: directory, port: 0, clock: clock.call);
  await server.start();
  final client = KaiCoreClient(endpoint: server.endpoint!);
  final journal = _JournalSpy();
  addTearDown(() async {
    client.close();
    await server.stop();
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });

  final f = _Fixture(clock, server, client, journal);
  f.scheduler = KaiDueCommitmentScheduler(
    client: client,
    presence: () => f.snapshot,
    now: clock.call,
    quietHours: quietHours,
    noBodyRetry: noBodyRetry,
    journal: journal.call,
  );
  return f;
}

/// Create one scheduled commitment. Does NOT advance the clock past due.
Future<void> _promise(
  _Fixture f, {
  String id = 'commit-1',
  String text = _reminderText,
}) async {
  f.clock.now = _createdAt;
  await f.client.createCommitment(
    commitmentId: id,
    personaId: 'truekai',
    text: text,
    dueAt: _dueAt,
    dueWallClock: '2026-09-01T09:00:00',
    dueWallOffsetMinutes: 180,
  );
}

void main() {
  group('event construction', () {
    test('a due record becomes a durable expiry-free work commitment', () {
      final event = KaiDueCommitmentScheduler.buildEvent({
        'commitmentId': 'commit-1',
        'nextEvaluationAt': _dueAt.toIso8601String(),
        'dueAt': _dueAt.toIso8601String(),
      });

      expect(event.kind, KaiAttentionKind.dueCommitment);
      expect(event.audience, KaiAttentionAudience.work,
          reason: 'explicit and trusted, never inferred from the words');
      expect(event.correlationId, 'commit-1');
      expect(event.eventId, 'due:commit-1');
      expect(event.isDurable, isTrue);
      expect(event.expiresAt, isNull,
          reason: 'a promise does not stop being owed because it is old');
      expect(event.outboundKind, KaiOutboundKind.completedWork);
    });

    test('identity derives from the commitment ID alone', () {
      // Same promise, different evaluation instant after a deferral: the event
      // identity must not move, or a retry becomes a different event.
      final first = KaiDueCommitmentScheduler.buildEvent({
        'commitmentId': 'commit-1',
        'nextEvaluationAt': _dueAt.toIso8601String(),
        'dueAt': _dueAt.toIso8601String(),
      });
      final afterDeferral = KaiDueCommitmentScheduler.buildEvent({
        'commitmentId': 'commit-1',
        'nextEvaluationAt':
            _dueAt.add(const Duration(hours: 9)).toIso8601String(),
        'dueAt': _dueAt.toIso8601String(),
      });
      expect(afterDeferral.eventId, first.eventId);
      expect(afterDeferral.correlationId, first.correlationId);
    });

    test('ordering uses Core instants, not the local clock', () {
      final event = KaiDueCommitmentScheduler.buildEvent({
        'commitmentId': 'commit-1',
        'nextEvaluationAt': _dueAt.toIso8601String(),
        'dueAt': _createdAt.toIso8601String(),
      });
      expect(event.receivedAt, _dueAt);
      expect(event.occurredAt, _createdAt);
    });

    test('a retry delay of zero or less is refused at construction', () async {
      final f = await _fixture('bad_retry');
      for (final bad in [Duration.zero, const Duration(seconds: -1)]) {
        expect(
          () => KaiDueCommitmentScheduler(
            client: f.client,
            presence: () => f.snapshot,
            now: f.clock.call,
            noBodyRetry: bad,
          ),
          throwsA(isA<ArgumentError>()),
          reason: 'retries are policy, not accidents',
        );
      }
    });
  });

  group('nothing happens before its time', () {
    test('a commitment that is not due produces no decision at all', () async {
      final f = await _fixture('not_due');
      await _promise(f);
      f.snapshot = _presence([_body(_desktopBody, 'desktop')]);

      await f.scheduler.drain();

      expect((await f.only())['status'], 'scheduled');
      expect((await f.only())['nextEvaluationAt'], _dueAt.toIso8601String(),
          reason: 'not touched');
      expect(await f.inbox(_desktopBody), isEmpty);
      expect(f.journal.entries, isEmpty);
    });
  });

  group('the engine decides the route', () {
    test('an eligible desktop body receives exactly one dispatch', () async {
      final f = await _fixture('dispatch');
      await _promise(f);
      f.clock.now = _daytime;
      f.snapshot = _presence([
        _body(_phoneBody, 'messenger'),
        _body(_desktopBody, 'desktop'),
      ]);

      await f.scheduler.drain();

      final record = await f.only();
      expect(record['status'], 'dispatched');
      expect(record['targetBodyId'], _desktopBody,
          reason: 'the exact global presence id, unchanged');

      final envelopes = await f.inbox(_desktopBody);
      expect(envelopes, hasLength(1));
      expect(envelopes.single['text'], _reminderText,
          reason: 'Core owns the text; the coordinator never regenerates it');
      expect(envelopes.single['conversationId'], 'in_person');
      expect(f.journal.events, contains('due_commitment_dispatched'));
    });

    test('quiet hours defer to the engine\'s exact instant, with no outbound',
        () async {
      final f = await _fixture('quiet', quietHours: kKaiCoordinatorQuietHours);
      await _promise(f);
      f.clock.now = _night;
      f.snapshot = _presence([_body(_desktopBody, 'desktop')]);

      // What the engine itself would say, computed independently.
      final expected = kKaiCoordinatorQuietHours.endsAfter(_night);

      await f.scheduler.drain();

      final record = await f.only();
      expect(record['status'], 'scheduled', reason: 'still owed');
      expect(record['nextEvaluationAt'], expected.toIso8601String(),
          reason: 'Core receives the engine\'s exact UTC notBefore');
      expect(await f.inbox(_desktopBody), isEmpty);

      // And it is not reconsidered before Core says so.
      await f.scheduler.drain();
      expect(await f.client.commitments(dueOnly: true), isEmpty);
    });

    test('no work-eligible body leaves the promise owed and still due',
        () async {
      // Option C. The no-body path deliberately writes NOTHING to Core.
      //
      // Persisting a retry would push `nextEvaluationAt` into the future, and
      // Core then refuses dispatch until it elapses while also refusing to
      // move it back — so the promise would be undeliverable for the whole
      // retry window, including the moment a desktop finally appears.
      final f =
          await _fixture('no_body', noBodyRetry: const Duration(minutes: 7));
      await _promise(f);
      f.clock.now = _daytime;
      f.snapshot = _presence(const []);

      await f.scheduler.drain();

      final record = await f.only();
      expect(record['status'], 'scheduled');
      expect(record['nextEvaluationAt'], _dueAt.toIso8601String(),
          reason: 'the evaluation instant is left exactly where it was');
      expect(await f.client.commitments(dueOnly: true), hasLength(1),
          reason: 'still listed as due, because it genuinely is owed');
      expect(await f.inbox(_desktopBody), isEmpty);
      expect(f.journal.events, contains('due_commitment_awaiting_body'));
    });

    test('a desktop arriving later delivers it with no extra Core round trip',
        () async {
      // The user-visible half of criterion 7: after the no-body pass, an
      // eligible desktop appearing is enough on its own.
      final f = await _fixture('no_body_then_desktop');
      await _promise(f);
      f.clock.now = _daytime;
      f.snapshot = _presence(const []);
      await f.scheduler.drain();
      expect((await f.only())['status'], 'scheduled');

      f.snapshot = _presence([_body(_desktopBody, 'desktop')]);
      await f.scheduler.drain();

      final record = await f.only();
      expect(record['status'], 'dispatched');
      expect(record['targetBodyId'], _desktopBody);
      expect(await f.inbox(_desktopBody), hasLength(1));
    });

    test('messenger, AR and VR presence cannot receive a work reminder',
        () async {
      for (final surface in ['messenger', 'ar', 'vr', 'mobile']) {
        final f = await _fixture('surface_$surface');
        await _promise(f);
        f.clock.now = _daytime;
        f.snapshot = _presence([_body('$surface-body', surface)]);

        await f.scheduler.drain();

        expect((await f.only())['status'], 'scheduled', reason: surface);
        expect(
            await f.client.pendingOutbound(
              toSurface: surface,
              bodyId: '$surface-body',
            ),
            isEmpty,
            reason: surface);
        await f.server.stop();
      }
    });

    test('a disconnected snapshot offers no candidates', () async {
      final f = await _fixture('disconnected');
      await _promise(f);
      f.clock.now = _daytime;
      f.snapshot =
          _presence([_body(_desktopBody, 'desktop')], connected: false);

      await f.scheduler.drain();
      expect((await f.only())['status'], 'scheduled');
      expect(await f.inbox(_desktopBody), isEmpty);
    });

    test('a malformed body is skipped rather than routed to', () async {
      final f = await _fixture('malformed_body');
      await _promise(f);
      f.clock.now = _daytime;
      f.snapshot = _presence([
        _body('   ', 'desktop'),
        _body(_desktopBody, 'desktop'),
      ]);

      await f.scheduler.drain();
      expect((await f.only())['targetBodyId'], _desktopBody);
    });
  });

  group('presence wake', () {
    test('a newly eligible desktop wakes the drain; churn does not', () async {
      final f = await _fixture('wake');
      final empty = _presence(const []);
      f.scheduler.shouldWakeFor(empty);

      expect(
          f.scheduler
              .shouldWakeFor(_presence([_body(_phoneBody, 'messenger')])),
          isFalse,
          reason: 'a phone cannot show a work reminder');

      expect(
          f.scheduler.shouldWakeFor(_presence([
            _body(_phoneBody, 'messenger'),
            _body(_desktopBody, 'desktop'),
          ])),
          isTrue,
          reason: 'the desktop is the reason a waiting reminder can be shown');

      expect(
          f.scheduler.shouldWakeFor(_presence([
            _body(_phoneBody, 'messenger'),
            _body(_desktopBody, 'desktop', foreground: false),
          ])),
          isFalse,
          reason: 'the same body again is not a new opportunity');
    });
  });

  group('one drain at a time', () {
    test('overlapping drains collapse into one pass', () async {
      final f = await _fixture('overlap');
      await _promise(f);
      f.clock.now = _daytime;
      f.snapshot = _presence([_body(_desktopBody, 'desktop')]);

      await Future.wait([
        f.scheduler.drain(),
        f.scheduler.drain(),
        f.scheduler.drain(),
      ]);

      expect(await f.inbox(_desktopBody), hasLength(1),
          reason: 'one promise, one envelope');
      expect(f.journal.countOf('due_commitment_dispatched'), 1);
    });

    test('a repeated drain after dispatch mints no second outbound', () async {
      final f = await _fixture('repeat');
      await _promise(f);
      f.clock.now = _daytime;
      f.snapshot = _presence([_body(_desktopBody, 'desktop')]);

      await f.scheduler.drain();
      await f.scheduler.drain();
      await f.scheduler.drain();

      expect(await f.inbox(_desktopBody), hasLength(1));
    });

    test('a fresh scheduler over the same Core is still idempotent', () async {
      // Stands in for a coordinator restart: no local memory at all, relying
      // entirely on Core's atomic dispatch.
      final f = await _fixture('restart');
      await _promise(f);
      f.clock.now = _daytime;
      f.snapshot = _presence([_body(_desktopBody, 'desktop')]);
      await f.scheduler.drain();

      final reborn = KaiDueCommitmentScheduler(
        client: f.client,
        presence: () => f.snapshot,
        now: f.clock.call,
        journal: f.journal.call,
      );
      await reborn.drain();

      expect(await f.inbox(_desktopBody), hasLength(1));
      expect((await f.only())['status'], 'dispatched');
    });
  });

  group('failures leave the promise owed', () {
    test('an unreachable Core changes nothing and is journalled', () async {
      final f = await _fixture('core_down');
      await _promise(f);
      f.clock.now = _daytime;
      f.snapshot = _presence([_body(_desktopBody, 'desktop')]);

      final dead = KaiCoreClient(
        endpoint: Uri.parse('http://127.0.0.1:1'),
        timeout: const Duration(milliseconds: 200),
      );
      addTearDown(dead.close);
      final offline = KaiDueCommitmentScheduler(
        client: dead,
        presence: () => f.snapshot,
        now: f.clock.call,
        journal: f.journal.call,
      );

      await offline.drain();
      expect(f.journal.events, contains('due_commitment_list_failed'));
      expect((await f.only())['status'], 'scheduled');

      // The healthy scheduler then delivers it.
      await f.scheduler.drain();
      expect(await f.inbox(_desktopBody), hasLength(1));
    });

    test('a dispatch refused by Core leaves it scheduled and retryable',
        () async {
      final f = await _fixture('dispatch_refused');
      await _promise(f);
      f.clock.now = _daytime;
      f.snapshot = _presence([_body(_desktopBody, 'desktop')]);

      // Occupy the deterministic envelope id with an unrelated outbound, so
      // Core refuses the dispatch as a collision.
      await f.client.createOutbound(
        outboundId: KaiDueCommitmentScheduler.outboundIdFor('commit-1'),
        kind: 'proactive_friend',
        fromSurface: 'central',
        toSurface: 'desktop',
        targetBodyId: 'somebody-else',
        conversationId: 'in_person',
        text: 'unrelated',
        expiresAt: _daytime.add(const Duration(hours: 1)),
      );

      await f.scheduler.drain();

      expect((await f.only())['status'], 'scheduled',
          reason: 'refused delivery is still an owed promise');
      expect(f.journal.events, contains('due_commitment_dispatch_refused'));
    });
  });

  group('journal discipline', () {
    test('an unchanged outcome is not written once per tick', () async {
      // The genuine repeat-per-tick case. A deferral removes the record from
      // the due list, so those ticks are no-ops and would prove nothing. A
      // REFUSED dispatch leaves it scheduled and still due, so every tick
      // re-decides it identically — which is exactly the shape that would
      // otherwise bury the log.
      final f = await _fixture('journal_repeat');
      await _promise(f);
      f.clock.now = _daytime;
      f.snapshot = _presence([_body(_desktopBody, 'desktop')]);
      await f.client.createOutbound(
        outboundId: KaiDueCommitmentScheduler.outboundIdFor('commit-1'),
        kind: 'proactive_friend',
        fromSurface: 'central',
        toSurface: 'desktop',
        targetBodyId: 'somebody-else',
        conversationId: 'in_person',
        text: 'unrelated',
        expiresAt: _daytime.add(const Duration(hours: 1)),
      );

      for (var tick = 0; tick < 6; tick++) {
        await f.scheduler.drain();
        // Still due every time — the promise is genuinely being re-decided.
        expect(await f.client.commitments(dueOnly: true), hasLength(1));
      }

      expect(f.journal.countOf('due_commitment_dispatch_refused'), 1,
          reason: 'six identical refusals are one fact, not six');
    });

    test('suppression is per commitment, not global', () async {
      final f = await _fixture('journal_scope');
      await _promise(f, id: 'commit-1');
      await _promise(f, id: 'commit-2');
      f.clock.now = _daytime;
      f.snapshot = _presence(const []);

      await f.scheduler.drain();
      expect(f.journal.countOf('due_commitment_awaiting_body'), 2,
          reason: 'two promises waiting is two facts');
    });

    test('waiting for a body is logged once, not once per tick', () async {
      final f = await _fixture('journal_awaiting');
      await _promise(f);
      f.clock.now = _daytime;
      f.snapshot = _presence(const []);

      // The no-body case now recurs on every tick by design, which makes
      // suppression load-bearing rather than incidental.
      for (var tick = 0; tick < 6; tick++) {
        await f.scheduler.drain();
      }
      expect(f.journal.countOf('due_commitment_awaiting_body'), 1);
    });

    test('a meaningful change is still recorded', () async {
      final f = await _fixture('journal_change');
      await _promise(f);
      f.clock.now = _daytime;
      f.snapshot = _presence(const []);
      await f.scheduler.drain();
      expect(f.journal.countOf('due_commitment_awaiting_body'), 1);

      // A real transition — the desktop arrives and it is delivered — must
      // still appear, however many identical waiting entries were suppressed.
      f.snapshot = _presence([_body(_desktopBody, 'desktop')]);
      await f.scheduler.drain();
      expect(f.journal.countOf('due_commitment_dispatched'), 1);
    });

    test('no journal entry ever carries the reminder text', () async {
      final f = await _fixture('journal_text');
      await _promise(f, text: 'RING THE ACCOUNTANT ABOUT THE VAT RETURN');
      f.clock.now = _daytime;
      f.snapshot = _presence([_body(_desktopBody, 'desktop')]);
      await f.scheduler.drain();
      f.snapshot = _presence(const []);
      f.clock.now = _daytime.add(const Duration(hours: 2));
      await f.scheduler.drain();

      expect(f.journal.entries, isNotEmpty);
      final dumped = f.journal.entries.toString();
      expect(dumped, isNot(contains('ACCOUNTANT')));
      expect(dumped, isNot(contains('VAT')));
    });
  });

  group('several promises at once', () {
    test('each is decided on its own merits', () async {
      final f = await _fixture('many');
      await _promise(f, id: 'commit-1', text: 'first');
      await _promise(f, id: 'commit-2', text: 'second');
      f.clock.now = _daytime;
      f.snapshot = _presence([_body(_desktopBody, 'desktop')]);

      await f.scheduler.drain();

      final envelopes = await f.inbox(_desktopBody);
      expect(envelopes, hasLength(2));
      expect(envelopes.map((e) => e['text']).toSet(), {'first', 'second'});
      expect(
        envelopes.map((e) => e['outboundId']).toSet(),
        {
          KaiDueCommitmentScheduler.outboundIdFor('commit-1'),
          KaiDueCommitmentScheduler.outboundIdFor('commit-2'),
        },
      );
    });
  });
}
