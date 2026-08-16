import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/services/attention/kai_attention_engine.dart';
import 'package:homecoming_app/services/attention/kai_proactive_attention_queue.dart';
import 'package:homecoming_app/services/attention/kai_proactive_attention_store.dart';
import 'package:homecoming_app/services/core/kai_body_event.dart';
import 'package:homecoming_app/services/core/kai_proactive_service.dart';

/// Every test gets its own directory and cleans only that exact path. The real
/// %LOCALAPPDATA%\Homecoming\KaiCore is never touched.
Directory _tempDir(String name) {
  final dir = Directory.systemTemp.createTempSync('kai_attn_$name');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  return dir;
}

KaiBodyRouteCandidate _body(String id, {DateTime? active}) =>
    KaiBodyRouteCandidate(
      bodyId: id,
      surface: 'desktop',
      foreground: true,
      lastUserActivityAt: active ?? DateTime.utc(2026, 8, 8, 14),
    );

/// Midday Bahrain — outside the 01:00-08:00 quiet window.
final _noon = DateTime.utc(2026, 8, 8, 11);

void main() {
  group('snapshot round-trip', () {
    test('every field needed to resume survives serialization', () {
      final queue = KaiProactiveAttentionQueue();
      final pending = queue.enqueue(
        const KaiNudge('(proactive) the crooked window',
            wantsHands: true,
            kind: KaiNudgeKind.noticed,
            topicId: 'crooked-window'),
        receivedAt: _noon,
        occurredAt: _noon.subtract(const Duration(minutes: 5)),
      );
      pending.notBefore = _noon.add(const Duration(minutes: 45));
      queue.complete('other-event', now: _noon);

      final restored = KaiProactiveAttentionQueue()
        ..restore(jsonDecode(jsonEncode(queue.snapshot())) as Map);

      final item = restored.pending.single;
      expect(item.event.eventId, pending.event.eventId);
      expect(item.event.correlationId, pending.event.correlationId);
      expect(item.event.receivedAt, pending.event.receivedAt);
      expect(item.event.occurredAt, pending.event.occurredAt);
      expect(item.event.expiresAt, pending.event.expiresAt);
      expect(item.notBefore, pending.notBefore);
      expect(item.nudge.seed, '(proactive) the crooked window');
      expect(item.nudge.wantsHands, isTrue);
      expect(item.nudge.kind, KaiNudgeKind.noticed);
      expect(item.nudge.topicId, 'crooked-window');
    });

    test('a restored event keeps its original receipt time and expiry', () {
      // Restart must not reorder the stream or refresh relevance.
      final queue = KaiProactiveAttentionQueue();
      final original = queue.enqueue(const KaiNudge('a'), receivedAt: _noon);

      final restored = KaiProactiveAttentionQueue()..restore(queue.snapshot());
      expect(
          restored.pending.single.event.receivedAt, original.event.receivedAt);
      expect(restored.pending.single.event.expiresAt, original.event.expiresAt);
    });

    test('malformed individual records are skipped, not fatal', () {
      final restored = KaiProactiveAttentionQueue()
        ..restore({
          'version': 1,
          'pending': [
            {'garbage': true},
            'not even a map',
            {
              'eventId': 'good',
              'correlationId': 'good',
              'receivedAt': _noon.toIso8601String(),
              'occurredAt': _noon.toIso8601String(),
              'seed': 'kept',
            },
          ],
          'processedEventIds': ['x', 42],
        });

      expect(restored.pending.single.event.eventId, 'good');
      expect(restored.processedEventIds, contains('x'));
    });

    test('an unsupported schema version restores nothing rather than guessing',
        () {
      final restored = KaiProactiveAttentionQueue()
        ..restore({
          'version': 999,
          'pending': [
            {'eventId': 'x', 'correlationId': 'x', 'seed': 's'}
          ]
        });
      expect(restored.pending, isEmpty);
    });
  });

  group('budget and idempotency across restart', () {
    test('an exhausted Bahrain day survives; restart grants no fresh nudges',
        () {
      final queue = KaiProactiveAttentionQueue();
      for (var i = 0; i < 2; i++) {
        queue.enqueue(const KaiNudge('n'), receivedAt: _noon, eventId: 'e$i');
        queue.complete('e$i', now: _noon);
      }
      expect(queue.deliveriesUsed, 2);

      final restored = KaiProactiveAttentionQueue()..restore(queue.snapshot());
      expect(restored.deliveriesUsed, 2);

      restored.enqueue(const KaiNudge('seventh'),
          receivedAt: _noon, eventId: 'seventh');
      final dispatch = restored.evaluate(
        now: _noon.add(const Duration(minutes: 1)),
        candidates: [_body('desktop')],
      );

      expect(dispatch!.decision.outcome, KaiAttentionOutcome.deferUntil);
      expect(dispatch.decision.bodyId, isNull);
    });

    test('a completed event replayed after restart is a duplicate', () {
      final queue = KaiProactiveAttentionQueue();
      queue.enqueue(const KaiNudge('n'), receivedAt: _noon, eventId: 'done-1');
      queue.complete('done-1', now: _noon);

      final restored = KaiProactiveAttentionQueue()..restore(queue.snapshot());
      restored.enqueue(const KaiNudge('n'),
          receivedAt: _noon, eventId: 'done-1');

      final dispatch = restored.evaluate(
        now: _noon.add(const Duration(minutes: 1)),
        candidates: [_body('desktop')],
      );
      expect(dispatch!.decision.outcome, KaiAttentionOutcome.discardDuplicate);
      expect(dispatch.decision.bodyId, isNull);
    });

    test('a paraphrased topic remains closed after restart', () {
      final queue = KaiProactiveAttentionQueue();
      const first = KaiNudge(
        'the Kai headers may target the wrong region',
        kind: KaiNudgeKind.noticed,
        topicId: 'header-observation-42',
      );
      final delivered = queue.enqueue(first, receivedAt: _noon);
      queue.complete(delivered.event.eventId, now: _noon);

      final restored = KaiProactiveAttentionQueue()..restore(queue.snapshot());
      restored.enqueue(
        const KaiNudge(
          'the two Kai labels are wearing the same hat',
          kind: KaiNudgeKind.noticed,
          topicId: 'header-observation-42',
        ),
        receivedAt: _noon.add(const Duration(hours: 4)),
      );

      final dispatch = restored.evaluate(
        now: _noon.add(const Duration(hours: 4)),
        candidates: [_body('desktop')],
      );
      expect(dispatch!.decision.outcome, KaiAttentionOutcome.discardDuplicate);
      expect(restored.pending, isEmpty);
    });

    test('a retry instant survives restart and cannot run early', () {
      final queue = KaiProactiveAttentionQueue();
      queue.enqueue(const KaiNudge('n'), receivedAt: _noon, eventId: 'flaky');
      queue.fail('flaky', now: _noon);
      final retryAt = queue.pending.single.notBefore!;

      final restored = KaiProactiveAttentionQueue()..restore(queue.snapshot());
      expect(restored.pending.single.notBefore, retryAt);

      expect(
        restored.evaluate(
          now: retryAt.subtract(const Duration(seconds: 1)),
          candidates: [_body('desktop')],
        ),
        isNull,
        reason: 'the retry instant is not yet due',
      );
      expect(
        restored.evaluate(now: retryAt, candidates: [_body('desktop')]),
        isNotNull,
      );
    });

    test('an event that expired while down is explicitly expired, not lost',
        () {
      final queue = KaiProactiveAttentionQueue();
      queue.enqueue(const KaiNudge('n'), receivedAt: _noon, eventId: 'stale');

      final restored = KaiProactiveAttentionQueue()..restore(queue.snapshot());
      final dispatch = restored.evaluate(
        now: _noon.add(const Duration(hours: 3)),
        candidates: [_body('desktop')],
      );

      expect(dispatch!.decision.outcome, KaiAttentionOutcome.discardExpired);
      expect(dispatch.decision.bodyId, isNull);
      expect(restored.pending, isEmpty);
    });
  });

  group('atomic store', () {
    test('save then load returns the same snapshot', () async {
      final dir = _tempDir('roundtrip');
      final store = KaiProactiveAttentionStore(directory: dir);

      final queue = KaiProactiveAttentionQueue();
      queue.enqueue(const KaiNudge('remember this'),
          receivedAt: _noon, eventId: 'e1');
      await store.save(queue.snapshot());

      final loaded = await KaiProactiveAttentionStore(directory: dir).load();
      final restored = KaiProactiveAttentionQueue()..restore(loaded!);
      expect(restored.pending.single.event.eventId, 'e1');
    });

    test('absent state loads as null, not as an error', () async {
      final store = KaiProactiveAttentionStore(directory: _tempDir('absent'));
      expect(await store.load(), isNull);
    });

    test('overlapping saves produce valid JSON of the later snapshot',
        () async {
      final dir = _tempDir('overlap');
      final store = KaiProactiveAttentionStore(directory: dir);

      final first = KaiProactiveAttentionQueue()
        ..enqueue(const KaiNudge('first'), receivedAt: _noon, eventId: 'first');
      final second = KaiProactiveAttentionQueue()
        ..enqueue(const KaiNudge('second'),
            receivedAt: _noon, eventId: 'second');

      // Fire both without awaiting the first — the write tail must serialize.
      final a = store.save(first.snapshot());
      final b = store.save(second.snapshot());
      await Future.wait([a, b]);

      final raw =
          await File('${dir.path}${Platform.pathSeparator}attention.json')
              .readAsString();
      final decoded = jsonDecode(raw); // throws if truncated
      expect(decoded, isA<Map>());

      final restored = KaiProactiveAttentionQueue()
        ..restore(decoded as Map<String, dynamic>);
      expect(restored.pending.single.event.eventId, 'second');
    });

    test('a corrupt primary falls back to the last valid backup', () async {
      final dir = _tempDir('corrupt');
      final store = KaiProactiveAttentionStore(directory: dir);

      final good = KaiProactiveAttentionQueue()
        ..enqueue(const KaiNudge('good'), receivedAt: _noon, eventId: 'good');
      await store.save(good.snapshot());
      // A second save rotates the first file into .bak.
      final newer = KaiProactiveAttentionQueue()
        ..enqueue(const KaiNudge('newer'), receivedAt: _noon, eventId: 'newer');
      await store.save(newer.snapshot());

      File('${dir.path}${Platform.pathSeparator}attention.json')
          .writeAsStringSync('{ this is not json');

      final loaded = await KaiProactiveAttentionStore(directory: dir).load();
      expect(loaded, isNotNull);
      final restored = KaiProactiveAttentionQueue()..restore(loaded!);
      expect(restored.pending.single.event.eventId, 'good',
          reason: 'the last readable backup');
    });

    test('both corrupt starts empty and PRESERVES the corrupt evidence',
        () async {
      final dir = _tempDir('both_corrupt');
      final store = KaiProactiveAttentionStore(directory: dir);
      await store.save(KaiProactiveAttentionQueue().snapshot());
      await store.save(KaiProactiveAttentionQueue().snapshot());

      final primary =
          File('${dir.path}${Platform.pathSeparator}attention.json');
      final backup =
          File('${dir.path}${Platform.pathSeparator}attention.json.bak');
      primary.writeAsStringSync('{ broken');
      backup.writeAsStringSync('{ also broken');

      final fresh = KaiProactiveAttentionStore(directory: dir);
      expect(await fresh.load(), isNull, reason: 'honest empty, not a guess');
      expect(fresh.lastLoadDegraded, isTrue);

      // Startup must not destroy the evidence before it reports it.
      expect(primary.readAsStringSync(), '{ broken');
      expect(backup.readAsStringSync(), '{ also broken');
    });

    test('the state file carries no reply, transcript, or credential',
        () async {
      final dir = _tempDir('privacy');
      final store = KaiProactiveAttentionStore(directory: dir);
      final queue = KaiProactiveAttentionQueue()
        ..enqueue(const KaiNudge('(proactive) bring up the loft'),
            receivedAt: _noon, eventId: 'e1');
      await store.save(queue.snapshot());

      final raw =
          await File('${dir.path}${Platform.pathSeparator}attention.json')
              .readAsString();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;

      // The seed is REQUIRED to resume, and the brief permits it explicitly.
      expect(raw, contains('bring up the loft'));
      // Nothing else about the conversation may be here.
      for (final forbidden in [
        'reply',
        'transcript',
        'apiKey',
        'authorization',
        'bearer',
        'sk-',
        'memory',
        'tool',
      ]) {
        expect(raw.toLowerCase(), isNot(contains(forbidden.toLowerCase())),
            reason: '"$forbidden" must never reach the attention state file');
      }
      expect(decoded.keys.toSet(), {
        'version',
        'pending',
        'processedEventIds',
        'deliveriesUsed',
        'budgetDay',
        'sequence',
      });
    });
  });

  group('Brief 009 — failure integrity', () {
    test('a failed save completes ITS future with an error', () async {
      // save() used to swallow into .catchError, so the future completed
      // successfully and the coordinator's persistence-failure journal seam was
      // unreachable. A write that cannot happen must be visible to its caller.
      final root = _tempDir('save_fail');
      final blocked = Directory('${root.path}${Platform.pathSeparator}blocked');
      // A FILE where the state directory must be — create() cannot succeed.
      File(blocked.path).writeAsStringSync('not a directory');

      final store = KaiProactiveAttentionStore(directory: blocked);
      await expectLater(
        store.save(KaiProactiveAttentionQueue().snapshot()),
        throwsA(anything),
      );
    });

    test('the serialization tail survives a failure and a later save works',
        () async {
      final root = _tempDir('tail_survives');
      final target = Directory('${root.path}${Platform.pathSeparator}state');
      final blocker = File(target.path)..writeAsStringSync('blocking file');

      final store = KaiProactiveAttentionStore(directory: target);
      await expectLater(
        store.save(KaiProactiveAttentionQueue().snapshot()),
        throwsA(anything),
      );

      // Clear the obstruction. The tail must not be poisoned by the failure.
      blocker.deleteSync();
      final queue = KaiProactiveAttentionQueue()
        ..enqueue(const KaiNudge('after recovery'),
            receivedAt: _noon, eventId: 'later');
      await store.save(queue.snapshot());

      final loaded = await KaiProactiveAttentionStore(directory: target).load();
      expect(loaded, isNotNull);
      final restored = KaiProactiveAttentionQueue()..restore(loaded!);
      expect(restored.pending.single.event.eventId, 'later');
    });

    test('the first save after backup recovery keeps the good backup',
        () async {
      // The rotation used to run unconditionally: delete .bak, rename the
      // CORRUPT primary into .bak, write the new primary. That destroyed the
      // one readable copy in the act of recovering from it.
      final dir = _tempDir('preserve_backup');
      final store = KaiProactiveAttentionStore(directory: dir);

      final good = KaiProactiveAttentionQueue()
        ..enqueue(const KaiNudge('good'), receivedAt: _noon, eventId: 'good');
      await store.save(good.snapshot());
      await store.save(good.snapshot()); // rotates 'good' into .bak

      final primary =
          File('${dir.path}${Platform.pathSeparator}attention.json');
      primary.writeAsStringSync('{ corrupt primary');

      final reader = KaiProactiveAttentionStore(directory: dir);
      final recovered = await reader.load();
      expect(recovered, isNotNull);
      expect(reader.lastLoadStatus, KaiAttentionLoadStatus.recoveredFromBackup);

      final fresh = KaiProactiveAttentionQueue()
        ..enqueue(const KaiNudge('fresh'), receivedAt: _noon, eventId: 'fresh');
      await reader.save(fresh.snapshot());

      // New primary is readable…
      final after = await KaiProactiveAttentionStore(directory: dir).load();
      expect(
          (KaiProactiveAttentionQueue()..restore(after!))
              .pending
              .single
              .event
              .eventId,
          'fresh');

      // …the previously readable backup is STILL readable…
      final backup =
          File('${dir.path}${Platform.pathSeparator}attention.json.bak');
      expect(
        (jsonDecode(backup.readAsStringSync()) as Map)['version'],
        1,
        reason: 'the recovered backup must not be replaced by corrupt bytes',
      );

      // …and the corrupt bytes are retained separately for diagnosis.
      final quarantined =
          File('${dir.path}${Platform.pathSeparator}attention.json.corrupt');
      expect(quarantined.existsSync(), isTrue);
      expect(quarantined.readAsStringSync(), '{ corrupt primary');
    });

    test('both corrupt: the first save deletes neither evidence blob',
        () async {
      final dir = _tempDir('preserve_both');
      final store = KaiProactiveAttentionStore(directory: dir);
      await store.save(KaiProactiveAttentionQueue().snapshot());
      await store.save(KaiProactiveAttentionQueue().snapshot());

      File('${dir.path}${Platform.pathSeparator}attention.json')
          .writeAsStringSync('{ broken primary');
      File('${dir.path}${Platform.pathSeparator}attention.json.bak')
          .writeAsStringSync('{ broken backup');

      final reader = KaiProactiveAttentionStore(directory: dir);
      expect(await reader.load(), isNull);
      expect(reader.lastLoadStatus, KaiAttentionLoadStatus.corrupt);

      await reader.save(KaiProactiveAttentionQueue().snapshot());

      expect(
        File('${dir.path}${Platform.pathSeparator}attention.json.corrupt')
            .readAsStringSync(),
        '{ broken primary',
      );
      expect(
        File('${dir.path}${Platform.pathSeparator}attention.json.bak.corrupt')
            .readAsStringSync(),
        '{ broken backup',
      );
    });

    test('an unsupported version is reported, not called a successful load',
        () async {
      final dir = _tempDir('unsupported');
      File('${dir.path}${Platform.pathSeparator}attention.json')
          .writeAsStringSync(jsonEncode({'version': 999, 'pending': []}));

      final store = KaiProactiveAttentionStore(directory: dir);
      final loaded = await store.load();

      expect(loaded, isNull, reason: 'no state, rather than an empty v1 queue');
      expect(store.lastLoadStatus, KaiAttentionLoadStatus.unsupportedVersion);
      expect(store.lastLoadDegraded, isTrue);
    });

    test('load status distinguishes all five outcomes', () async {
      final dir = _tempDir('statuses');
      final store = KaiProactiveAttentionStore(directory: dir);

      expect(await store.load(), isNull);
      expect(store.lastLoadStatus, KaiAttentionLoadStatus.absent);

      await store.save(KaiProactiveAttentionQueue().snapshot());
      await store.load();
      expect(store.lastLoadStatus, KaiAttentionLoadStatus.loaded);
    });
  });

  group('Brief 009 — budget reset with no dispatch', () {
    test('a day rollover is a mutation even when nothing is due', () {
      final queue = KaiProactiveAttentionQueue();
      queue.enqueue(const KaiNudge('n'), receivedAt: _noon, eventId: 'blocked');
      queue.complete('blocked', now: _noon);
      expect(queue.deliveriesUsed, 1);

      // Something pending, but blocked far into the future.
      final pending =
          queue.enqueue(const KaiNudge('n2'), receivedAt: _noon, eventId: 'p2');
      pending.notBefore = _noon.add(const Duration(days: 5));

      final before = queue.revision;
      final dispatch = queue.evaluate(
        now: _noon.add(const Duration(days: 1)),
        candidates: const [],
      );

      expect(dispatch, isNull, reason: 'nothing is due');
      expect(queue.deliveriesUsed, 0, reason: 'the Bahrain day rolled over');
      expect(queue.revision, greaterThan(before),
          reason: 'the reset is a state change the coordinator must persist');
    });

    test('an idle evaluation with no change does not bump the revision', () {
      final queue = KaiProactiveAttentionQueue();
      final pending =
          queue.enqueue(const KaiNudge('n'), receivedAt: _noon, eventId: 'p');
      pending.notBefore = _noon.add(const Duration(hours: 6));
      // Establish the budget day so the first evaluate is not itself a reset.
      queue.evaluate(now: _noon, candidates: const []);

      final before = queue.revision;
      for (var i = 0; i < 5; i++) {
        expect(
          queue.evaluate(
              now: _noon.add(Duration(minutes: i)), candidates: const []),
          isNull,
        );
      }
      expect(queue.revision, before,
          reason: 'an idle timer loop must not request a disk write');
    });
  });

  group('model-free restart harness', () {
    test('a bodyless event survives a full store/queue replacement', () async {
      final dir = _tempDir('harness');

      // ── First process ────────────────────────────────────────────────────
      var store = KaiProactiveAttentionStore(directory: dir);
      var queue = KaiProactiveAttentionQueue();
      final original = queue.enqueue(
        const KaiNudge('(proactive) the thing you noticed'),
        receivedAt: _noon,
      );

      final bodyless = queue.evaluate(now: _noon, candidates: const []);
      expect(bodyless!.decision.outcome, KaiAttentionOutcome.storeForLater);
      expect(bodyless.decision.bodyId, isNull);
      expect(
        queue.pending.single.notBefore,
        _noon.add(const Duration(minutes: 1)),
      );
      await store.save(queue.snapshot());

      // ── Process dies ─────────────────────────────────────────────────────
      queue = KaiProactiveAttentionQueue();
      store = KaiProactiveAttentionStore(directory: dir);

      // ── Second process ───────────────────────────────────────────────────
      final loaded = await store.load();
      expect(loaded, isNotNull);
      queue.restore(loaded!);

      final dispatch = queue.evaluate(
        now: _noon.add(const Duration(minutes: 1)),
        candidates: [_body('desktop-2')],
      );

      expect(dispatch!.decision.outcome, KaiAttentionOutcome.deliverNow);
      expect(dispatch.decision.bodyId, 'desktop-2');
      expect(dispatch.decision.eventId, original.event.eventId);
      expect(dispatch.decision.correlationId, original.event.correlationId);
      expect(dispatch.pending.nudge.seed, '(proactive) the thing you noticed');
    });
  });
}
