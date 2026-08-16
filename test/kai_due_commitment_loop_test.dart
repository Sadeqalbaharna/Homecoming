// Brief 016 lifecycle repair — when the due loop runs, and when it stops.
//
// The defect this file exists for: cancelling a timer does not stop a drain
// that has already started. It is suspended inside the Core list call; when
// that answers, it resumes and dispatches — after `stop()` returned, for a
// coordinator that no longer exists. A reminder appears, a body wakes, a
// promise closes, and nothing is running that should have caused it.
//
// So the central test here holds the Core request open, stops mid-flight,
// releases it, and asserts the ledger is untouched. It drives the PRODUCTION
// KaiDueCommitmentLoop — the same object the coordinator constructs.
//
// Temp Core directories only. Nothing touches live Core state.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/services/attention/kai_attention_engine.dart';
import 'package:homecoming_app/services/core/kai_core_client.dart';
import 'package:homecoming_app/services/core/kai_core_server.dart';
import 'package:homecoming_app/services/core/kai_due_commitment_loop.dart';
import 'package:homecoming_app/services/core/kai_due_commitment_scheduler.dart';
import 'package:homecoming_app/services/core/kai_global_presence_service.dart';

final _createdAt = DateTime.utc(2026, 8, 8, 12);
final _dueAt = DateTime.utc(2026, 9, 1, 6);
final _daytime = DateTime.utc(2026, 9, 1, 7);

/// 02:30 Bahrain — inside the 01:00-08:00 quiet window.
final _night = DateTime.utc(2026, 9, 1, 23, 30);

const _desktopBody = 'desktop-body-abc123';
const _phoneBody = 'messenger-body-xyz789';

class _Clock {
  DateTime now = _createdAt;
  DateTime call() => now;
}

/// A client that can be held open on the due-list call.
///
/// Everything else passes straight through to the real client, so dispatch and
/// deferral remain genuine Core transitions — the assertions are about the
/// ledger, not about a mock's call log.
class _PausableClient implements KaiCoreClient {
  _PausableClient(this._inner);

  final KaiCoreClient _inner;

  /// Completed by the test to release a held list call.
  Completer<void>? gate;

  /// Signals that a list call has actually reached the gate, so the test never
  /// stops before the drain is genuinely suspended.
  Completer<void> reachedGate = Completer<void>();

  int listCalls = 0;

  @override
  Future<List<Map<String, dynamic>>> commitments({bool dueOnly = false}) async {
    listCalls++;
    final held = gate;
    if (held != null) {
      if (!reachedGate.isCompleted) reachedGate.complete();
      await held.future;
    }
    return _inner.commitments(dueOnly: dueOnly);
  }

  @override
  Future<Map<String, dynamic>> dispatchCommitment(
    String commitmentId, {
    required String outboundId,
    required String targetBodyId,
    required String conversationId,
  }) =>
      _inner.dispatchCommitment(commitmentId,
          outboundId: outboundId,
          targetBodyId: targetBodyId,
          conversationId: conversationId);

  @override
  Future<Map<String, dynamic>> deferCommitment(
    String commitmentId, {
    required DateTime nextEvaluationAt,
  }) =>
      _inner.deferCommitment(commitmentId, nextEvaluationAt: nextEvaluationAt);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used here');
}

class _JournalSpy {
  final List<String> events = [];

  Future<void> call(
    String event, {
    String severity = 'info',
    Map<String, Object?> details = const {},
  }) async {
    events.add(event);
  }
}

KaiGlobalBody _body(String bodyId, String surface) => KaiGlobalBody(
      bodyId: bodyId,
      deviceId: '$surface-device',
      surface: surface,
      leaseExpiresAt: DateTime.utc(2030),
      foreground: true,
      lastUserActivityAt: _createdAt,
    );

KaiGlobalPresenceSnapshot _presence(List<KaiGlobalBody> bodies) =>
    KaiGlobalPresenceSnapshot(
      connected: true,
      coordinatorLeaseExpiresAt: DateTime.utc(2030),
      bodies: bodies,
      observedAt: _createdAt,
    );

class _Fixture {
  _Fixture(this.clock, this.server, this.real, this.client, this.journal);

  final _Clock clock;
  final KaiCoreServer server;
  final KaiCoreClient real;
  final _PausableClient client;
  final _JournalSpy journal;

  KaiGlobalPresenceSnapshot snapshot = _presence(const []);
  late KaiDueCommitmentLoop loop;

  Future<Map<String, dynamic>> only() async =>
      (await real.commitments()).single;

  Future<List<Map<String, dynamic>>> inbox() =>
      real.pendingOutbound(toSurface: 'desktop', bodyId: _desktopBody);
}

Future<_Fixture> _fixture(
  String name, {
  Duration interval = const Duration(milliseconds: 30),
  KaiQuietHours quietHours = const KaiQuietHours.none(),
}) async {
  final directory = Directory.systemTemp.createTempSync('kai_loop_$name');
  final clock = _Clock();
  final server =
      KaiCoreServer(dataDirectory: directory, port: 0, clock: clock.call);
  await server.start();
  final real = KaiCoreClient(endpoint: server.endpoint!);
  final client = _PausableClient(real);
  final journal = _JournalSpy();

  final f = _Fixture(clock, server, real, client, journal);
  f.loop = KaiDueCommitmentLoop(
    interval: interval,
    createScheduler: (isActive) => KaiDueCommitmentScheduler(
      client: client,
      presence: () => f.snapshot,
      now: clock.call,
      quietHours: quietHours,
      journal: journal.call,
      isActive: isActive,
    ),
  );

  addTearDown(() async {
    await f.loop.stop();
    real.close();
    await server.stop();
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });
  return f;
}

Future<void> _promise(_Fixture f, {String id = 'commit-1'}) async {
  f.clock.now = _createdAt;
  await f.real.createCommitment(
    commitmentId: id,
    personaId: 'truekai',
    text: 'chase the invoice',
    dueAt: _dueAt,
    dueWallClock: '2026-09-01T09:00:00',
    dueWallOffsetMinutes: 180,
  );
}

void main() {
  group('shutdown while a drain is in flight', () {
    test('releasing a held Core call after stop dispatches nothing', () async {
      final f = await _fixture('stop_midflight',
          interval: const Duration(minutes: 5));
      await _promise(f);
      f.clock.now = _daytime;
      f.snapshot = _presence([_body(_desktopBody, 'desktop')]);

      // Hold the due-list call open, then start.
      final gate = Completer<void>();
      f.client.gate = gate;
      f.loop.start();

      // Wait until the drain is genuinely suspended inside the list call —
      // otherwise this test could stop before any work began and prove nothing.
      await f.client.reachedGate.future.timeout(const Duration(seconds: 5));

      final stopped = f.loop.stop();
      // Release the Core call while stop() is waiting for it.
      gate.complete();
      f.client.gate = null;
      await stopped.timeout(const Duration(seconds: 5));

      // Give any stale continuation every chance to run.
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final record = await f.only();
      expect(record['status'], 'scheduled',
          reason: 'a stopped coordinator must not dispatch');
      expect(record['nextEvaluationAt'], _dueAt.toIso8601String(),
          reason: 'nor defer');
      expect(await f.inbox(), isEmpty);
      expect(f.journal.events, isNot(contains('due_commitment_dispatched')));
      expect(f.journal.events, isNot(contains('due_commitment_deferred')));
    });

    test('stop() does not return until the in-flight drain has finished',
        () async {
      final f =
          await _fixture('stop_awaits', interval: const Duration(minutes: 5));
      await _promise(f);
      f.clock.now = _daytime;

      final gate = Completer<void>();
      f.client.gate = gate;
      f.loop.start();
      await f.client.reachedGate.future.timeout(const Duration(seconds: 5));

      var stopReturned = false;
      final stopping = f.loop.stop().then((_) => stopReturned = true);

      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(stopReturned, isFalse,
          reason: 'stop must wait for work already running');

      gate.complete();
      f.client.gate = null;
      await stopping.timeout(const Duration(seconds: 5));
      expect(stopReturned, isTrue);
    });

    test('a restart does not re-authorize the earlier generation\'s drain',
        () async {
      final f =
          await _fixture('generation', interval: const Duration(minutes: 5));
      await _promise(f);
      f.clock.now = _daytime;
      f.snapshot = _presence([_body(_desktopBody, 'desktop')]);

      final gate = Completer<void>();
      f.client.gate = gate;
      f.loop.start();
      await f.client.reachedGate.future.timeout(const Duration(seconds: 5));

      // Stop and immediately restart, THEN release the old call. A predicate
      // that only asked "is the loop running?" would say yes here and let the
      // stale drain through.
      final stopping = f.loop.stop();
      gate.complete();
      f.client.gate = null;
      await stopping.timeout(const Duration(seconds: 5));

      f.client.reachedGate = Completer<void>();
      final secondGate = Completer<void>();
      f.client.gate = secondGate;
      f.loop.start();
      await f.client.reachedGate.future.timeout(const Duration(seconds: 5));

      // The new generation is legitimately running; the old one must still be
      // dead. Nothing has been released for the new one yet.
      final record = await f.only();
      expect(record['status'], 'scheduled');
      expect(await f.inbox(), isEmpty);

      secondGate.complete();
      f.client.gate = null;
    });

    test('after stop, a restart delivers normally', () async {
      final f =
          await _fixture('restart_works', interval: const Duration(minutes: 5));
      await _promise(f);
      f.clock.now = _daytime;
      f.snapshot = _presence([_body(_desktopBody, 'desktop')]);

      f.loop.start();
      await f.loop.stop();

      f.loop.start();
      await f.loop.drainNow();

      expect((await f.only())['status'], 'dispatched');
      expect(await f.inbox(), hasLength(1));
    });
  });

  group('triggers', () {
    test('start drains once immediately', () async {
      final f = await _fixture('initial', interval: const Duration(minutes: 5));
      await _promise(f);
      f.clock.now = _daytime;
      f.snapshot = _presence([_body(_desktopBody, 'desktop')]);

      f.loop.start();
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect((await f.only())['status'], 'dispatched',
          reason: 'promises overdue at startup must not wait a whole interval');
    });

    test('the periodic tick drains again', () async {
      final f = await _fixture('periodic',
          interval: const Duration(milliseconds: 25));
      f.clock.now = _daytime;
      f.snapshot = _presence([_body(_desktopBody, 'desktop')]);

      f.loop.start();
      await Future<void>.delayed(const Duration(milliseconds: 40));
      final afterFirst = f.client.listCalls;

      // A promise created after the loop is already running is picked up by a
      // later tick with no other prompting.
      await _promise(f, id: 'commit-late');
      // _promise rewinds the clock to creation time so Core accepts a future
      // due instant; put it back past due so the next tick sees the record.
      f.clock.now = _daytime;
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(f.client.listCalls, greaterThan(afterFirst));
      expect((await f.only())['status'], 'dispatched');
    });

    test('an eligible desktop wake DELIVERS; churn does not', () async {
      // Asserts the transition, not the request. The earlier version of this
      // test only checked that `listCalls` went up — which was true even while
      // the wake was incapable of delivering anything, and is exactly how the
      // criterion-7 defect survived review.
      final f = await _fixture('wake', interval: const Duration(minutes: 5));
      await _promise(f);
      f.clock.now = _daytime;
      f.loop.start();
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect((await f.only())['status'], 'scheduled',
          reason: 'nowhere to show it yet');

      final beforeChurn = f.client.listCalls;
      await f.loop.onPresence(_presence([_body(_phoneBody, 'messenger')]));
      expect(f.client.listCalls, beforeChurn,
          reason: 'a phone cannot show a work reminder; no drain at all');
      expect((await f.only())['status'], 'scheduled');

      f.snapshot = _presence([
        _body(_phoneBody, 'messenger'),
        _body(_desktopBody, 'desktop'),
      ]);
      await f.loop.onPresence(f.snapshot);

      expect((await f.only())['status'], 'dispatched',
          reason: 'sitting down at the desk is what delivers the reminder');
      expect(await f.inbox(), hasLength(1));
    });

    test('a quiet-hours deferral is NOT overridden by a presence wake',
        () async {
      // The other half of the contract. Presence must not become a way around
      // the engine: Kai appearing at 02:30 is not permission to speak.
      final f = await _fixture('wake_quiet',
          interval: const Duration(minutes: 5),
          quietHours: kKaiCoordinatorQuietHours);
      await _promise(f);
      f.clock.now = _night;
      f.loop.start();
      await Future<void>.delayed(const Duration(milliseconds: 40));

      final expected = kKaiCoordinatorQuietHours.endsAfter(_night);
      expect((await f.only())['nextEvaluationAt'], expected.toIso8601String(),
          reason: 'quiet hours still persists the engine\'s exact instant');

      f.snapshot = _presence([_body(_desktopBody, 'desktop')]);
      await f.loop.onPresence(f.snapshot);

      final record = await f.only();
      expect(record['status'], 'scheduled', reason: 'still asleep');
      expect(record['nextEvaluationAt'], expected.toIso8601String(),
          reason: 'and the instant is unchanged');
      expect(await f.inbox(), isEmpty);
    });

    test('presence after stop wakes nothing', () async {
      final f =
          await _fixture('wake_stopped', interval: const Duration(minutes: 5));
      await _promise(f);
      f.clock.now = _daytime;
      f.loop.start();
      await Future<void>.delayed(const Duration(milliseconds: 40));
      await f.loop.stop();

      final before = f.client.listCalls;
      f.snapshot = _presence([_body(_desktopBody, 'desktop')]);
      await f.loop.onPresence(f.snapshot);

      expect(f.client.listCalls, before);
      expect(await f.inbox(), isEmpty);
    });

    test('overlapping triggers collapse to one drain', () async {
      final f = await _fixture('overlap', interval: const Duration(minutes: 5));
      await _promise(f);
      f.clock.now = _daytime;
      f.snapshot = _presence([_body(_desktopBody, 'desktop')]);
      f.loop.start();
      await Future<void>.delayed(const Duration(milliseconds: 40));

      final before = f.client.listCalls;
      await Future.wait([
        f.loop.drainNow(),
        f.loop.drainNow(),
        f.loop.drainNow(),
      ]);
      expect(f.client.listCalls, before + 1,
          reason: 'three triggers, one pass over Core');
      expect(await f.inbox(), hasLength(1));
    });

    test('drainNow before start does nothing', () async {
      final f =
          await _fixture('not_started', interval: const Duration(minutes: 5));
      await _promise(f);
      f.clock.now = _daytime;
      f.snapshot = _presence([_body(_desktopBody, 'desktop')]);

      await f.loop.drainNow();
      expect(f.client.listCalls, 0);
      expect((await f.only())['status'], 'scheduled');
    });

    test('start is idempotent and stop is safe to repeat', () async {
      final f =
          await _fixture('idempotent', interval: const Duration(minutes: 5));
      expect(f.loop.isRunning, isFalse);
      f.loop.start();
      f.loop.start();
      expect(f.loop.isRunning, isTrue);
      await f.loop.stop();
      await f.loop.stop();
      expect(f.loop.isRunning, isFalse);
    });

    test('a non-positive interval is refused', () async {
      for (final bad in [Duration.zero, const Duration(seconds: -1)]) {
        expect(
          () => KaiDueCommitmentLoop(
            interval: bad,
            createScheduler: (_) => throw StateError('never built'),
          ),
          throwsA(isA<ArgumentError>()),
        );
      }
    });
  });
}
