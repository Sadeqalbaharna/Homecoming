import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/services/core/kai_core_client.dart';
import 'package:homecoming_app/services/core/kai_core_server.dart';

void main() {
  late Directory data;
  late KaiCoreServer server;
  late KaiCoreClient client;
  var now = DateTime.utc(2026, 8, 7, 12);

  setUp(() async {
    data = await Directory.systemTemp.createTemp('kai-core-test-');
    server = KaiCoreServer(
      dataDirectory: data,
      port: 0,
      staleAfter: const Duration(seconds: 60),
      clock: () => now,
    );
    final endpoint = await server.start();
    client = KaiCoreClient(endpoint: endpoint);
  });

  tearDown(() async {
    client.close();
    await server.stop();
    if (await data.exists()) await data.delete(recursive: true);
  });

  test('health and presence work without any model or app process', () async {
    expect(await client.isHealthy(), isTrue);

    final heartbeat = await client.heartbeat(
      deviceId: 'desktop-one',
      surface: 'desktop',
      sessionId: 'session-one',
      foreground: true,
      audioAvailable: false,
      status: 'thinking',
    );
    expect(heartbeat['online'], isTrue);
    expect(heartbeat['status'], 'thinking');
    expect(heartbeat['leaseExpiresAt'], '2026-08-07T12:01:00.000Z');

    expect((await client.activeDevices()).single['deviceId'], 'desktop-one');
    expect((await client.activeDevices()).single['status'], 'thinking');
    now = now.add(const Duration(seconds: 61));
    expect(await client.activeDevices(), isEmpty);
  });

  test('handoffs are idempotent, destination-scoped, and acknowledged',
      () async {
    final expires = now.add(const Duration(minutes: 5));
    final first = await client.createHandoff(
      handoffId: 'handoff-one',
      fromSurface: 'desktop',
      toSurface: 'vr',
      conversationId: 'in_person',
      summary: 'Continue in the Shack.',
      expiresAt: expires,
    );
    final retry = await client.createHandoff(
      handoffId: 'handoff-one',
      fromSurface: 'desktop',
      toSurface: 'vr',
      conversationId: 'in_person',
      summary: 'Continue in the Shack.',
      expiresAt: expires,
    );

    expect(first['handoffId'], 'handoff-one');
    expect(retry['handoffId'], 'handoff-one');
    expect(await client.pendingHandoffs('messenger'), isEmpty);
    expect((await client.pendingHandoffs('vr')).single['status'], 'pending');

    final acknowledged = await client.acknowledgeHandoff('handoff-one');
    expect(acknowledged['status'], 'acknowledged');
    expect(await client.pendingHandoffs('vr'), isEmpty);
  });

  test('outbound attention is body-targeted, durable, and acknowledged',
      () async {
    final created = await client.createOutbound(
      outboundId: 'outbound-one',
      kind: 'proactive_friend',
      fromSurface: 'central',
      toSurface: 'vr',
      targetBodyId: 'quest-shack',
      conversationId: 'vr_shack',
      text: 'I found something you might like.',
      gesture: 'wave',
      expiresAt: now.add(const Duration(minutes: 5)),
    );
    expect(created['status'], 'pending');
    expect(
      await client.pendingOutbound(
        toSurface: 'vr',
        bodyId: 'different-quest',
      ),
      isEmpty,
    );
    final pending = await client.pendingOutbound(
      toSurface: 'vr',
      bodyId: 'quest-shack',
    );
    expect(pending.single['text'], 'I found something you might like.');

    final acknowledged = await client.acknowledgeOutbound(
      'outbound-one',
      bodyId: 'quest-shack',
      surface: 'vr',
    );
    expect(acknowledged['status'], 'acknowledged');
    expect(
      await client.pendingOutbound(
        toSurface: 'vr',
        bodyId: 'quest-shack',
      ),
      isEmpty,
    );
  });

  test('wrong body cannot acknowledge targeted outbound attention', () async {
    await client.createOutbound(
      outboundId: 'private-outbound',
      kind: 'direct_reply',
      fromSurface: 'central',
      toSurface: 'ar',
      targetBodyId: 'glasses-one',
      text: 'For this body only.',
      expiresAt: now.add(const Duration(minutes: 5)),
    );
    await expectLater(
      client.acknowledgeOutbound(
        'private-outbound',
        bodyId: 'glasses-two',
        surface: 'ar',
      ),
      throwsA(isA<KaiCoreException>()),
    );
  });

  test('coordination state survives a core restart', () async {
    await client.heartbeat(
      deviceId: 'desktop-one',
      surface: 'desktop',
      sessionId: 'session-one',
      foreground: true,
      audioAvailable: false,
    );
    await client.createHandoff(
      handoffId: 'durable-handoff',
      fromSurface: 'desktop',
      toSurface: 'messenger',
      conversationId: 'in_person',
      summary: 'Pick up the same thread.',
      expiresAt: now.add(const Duration(minutes: 5)),
    );
    await client.enqueueTask(
      taskId: 'durable-task',
      lane: 'work',
      kind: 'desktop_job',
      sourceSurface: 'messenger',
      payload: const {'instruction': 'Keep working.'},
    );
    await client.createOutbound(
      outboundId: 'durable-outbound',
      kind: 'proactive_friend',
      fromSurface: 'central',
      toSurface: 'vr',
      targetBodyId: 'quest-durable',
      text: 'This should still be waiting after Core restarts.',
      expiresAt: now.add(const Duration(minutes: 5)),
    );

    client.close();
    await server.stop();
    server = KaiCoreServer(
      dataDirectory: data,
      port: 0,
      staleAfter: const Duration(seconds: 60),
      clock: () => now,
    );
    client = KaiCoreClient(endpoint: await server.start());

    expect((await client.activeDevices()).single['deviceId'], 'desktop-one');
    expect(
      (await client.pendingHandoffs('messenger')).single['handoffId'],
      'durable-handoff',
    );
    expect((await client.tasks()).single['taskId'], 'durable-task');
    expect(
      (await client.pendingOutbound(
        toSurface: 'vr',
        bodyId: 'quest-durable',
      ))
          .single['outboundId'],
      'durable-outbound',
    );
  });

  test('conversation lane allows parallel threads but preserves turn order',
      () async {
    await client.enqueueTask(
      taskId: 'conversation-a-1',
      lane: 'conversation',
      kind: 'reply',
      sourceSurface: 'messenger',
      conversationId: 'thread-a',
    );
    now = now.add(const Duration(seconds: 1));
    await client.enqueueTask(
      taskId: 'conversation-a-2',
      lane: 'conversation',
      kind: 'reply',
      sourceSurface: 'desktop',
      conversationId: 'thread-a',
    );
    now = now.add(const Duration(seconds: 1));
    await client.enqueueTask(
      taskId: 'conversation-b-1',
      lane: 'conversation',
      kind: 'reply',
      sourceSurface: 'vr',
      conversationId: 'thread-b',
    );
    now = now.add(const Duration(seconds: 1));
    await client.enqueueTask(
      taskId: 'conversation-c-1',
      lane: 'conversation',
      kind: 'reply',
      sourceSurface: 'ar',
      conversationId: 'thread-c',
    );

    final first = await client.claimNextTask(
      lane: 'conversation',
      workerId: 'conversation-worker-1',
    );
    final parallel = await client.claimNextTask(
      lane: 'conversation',
      workerId: 'conversation-worker-2',
    );
    final blocked = await client.claimNextTask(
      lane: 'conversation',
      workerId: 'conversation-worker-3',
    );

    expect(first!['taskId'], 'conversation-a-1');
    expect(parallel!['taskId'], 'conversation-b-1');
    expect(blocked, isNull,
        reason: 'the conversation pool deliberately stops at two lanes');

    await client.completeTask(
      'conversation-a-1',
      workerId: 'conversation-worker-1',
    );
    expect(
      (await client.claimNextTask(
        lane: 'conversation',
        workerId: 'conversation-worker-3',
      ))!['taskId'],
      'conversation-a-2',
    );
    await client.completeTask(
      'conversation-b-1',
      workerId: 'conversation-worker-2',
    );
    expect(
      (await client.claimNextTask(
        lane: 'conversation',
        workerId: 'conversation-worker-4',
      ))!['taskId'],
      'conversation-c-1',
    );
  });

  test('work lane is bounded to two simultaneous jobs', () async {
    for (var index = 0; index < 3; index++) {
      await client.enqueueTask(
        taskId: 'work-$index',
        lane: 'work',
        kind: 'desktop_job',
        sourceSurface: 'messenger',
        priority: index == 2 ? 'urgent' : 'normal',
      );
    }

    final claims = await Future.wait([
      client.claimNextTask(lane: 'work', workerId: 'worker-a'),
      client.claimNextTask(lane: 'work', workerId: 'worker-b'),
    ]);
    expect(claims.whereType<Map>().length, 2);
    expect(claims.map((task) => task!['taskId']).toSet().length, 2);
    expect(
      await client.claimNextTask(lane: 'work', workerId: 'worker-c'),
      isNull,
    );
  });

  test('an abandoned queued admission can be cancelled without lane leakage',
      () async {
    await client.enqueueTask(
      taskId: 'waiting-turn',
      lane: 'conversation',
      kind: 'reply',
      sourceSurface: 'vr',
      conversationId: 'vr_shack',
    );
    final cancelled = await client.cancelTask(
      'waiting-turn',
      workerId: 'embodiment-vr',
    );
    expect(cancelled['status'], 'cancelled');
    expect(
      await client.claimNextTask(
        lane: 'conversation',
        workerId: 'another-worker',
      ),
      isNull,
    );
  });

  test('memory writes are single-file and abandoned leases are recovered',
      () async {
    await client.enqueueTask(
      taskId: 'memory-1',
      lane: 'memory',
      kind: 'promote_memory',
      sourceSurface: 'desktop',
    );
    await client.enqueueTask(
      taskId: 'memory-2',
      lane: 'memory',
      kind: 'promote_memory',
      sourceSurface: 'messenger',
    );

    final first = await client.claimNextTask(
      lane: 'memory',
      workerId: 'memory-worker-a',
      lease: const Duration(seconds: 15),
    );
    expect(first!['taskId'], 'memory-1');
    expect(
      await client.claimNextTask(
        lane: 'memory',
        workerId: 'memory-worker-b',
      ),
      isNull,
    );

    now = now.add(const Duration(seconds: 16));
    final recovered = await client.claimNextTask(
      lane: 'memory',
      workerId: 'memory-worker-b',
    );
    expect(recovered!['taskId'], 'memory-1');
    expect(recovered['attempt'], 2);
    expect(recovered['lastLeaseOwner'], 'memory-worker-a');
  });

  test('destination inbox acknowledges only after accepted delivery', () async {
    await client.createHandoff(
      handoffId: 'deliver-me',
      fromSurface: 'vr',
      toSurface: 'desktop',
      conversationId: 'vr_shack',
      summary: 'We left off beside the crooked window.',
      expiresAt: now.add(const Duration(minutes: 5)),
    );
    final delivered = Completer<Map<String, dynamic>>();
    final inbox = KaiCoreHandoffInbox(
      client: client,
      surface: 'desktop',
      interval: const Duration(milliseconds: 20),
      onHandoff: (handoff) async {
        if (!delivered.isCompleted) delivered.complete(handoff);
        return true;
      },
    );
    addTearDown(inbox.stop);
    inbox.start();

    final handoff = await delivered.future.timeout(const Duration(seconds: 1));
    expect(handoff['handoffId'], 'deliver-me');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(await client.pendingHandoffs('desktop'), isEmpty);
  });

  test('rejected delivery stays pending for the next process', () async {
    await client.createHandoff(
      handoffId: 'keep-me',
      fromSurface: 'messenger',
      toSurface: 'desktop',
      conversationId: 'messenger',
      summary: 'Do not lose this transition.',
      expiresAt: now.add(const Duration(minutes: 5)),
    );
    final inbox = KaiCoreHandoffInbox(
      client: client,
      surface: 'desktop',
      onHandoff: (_) async => false,
    );

    await inbox.poll();

    expect(
      (await client.pendingHandoffs('desktop')).single['handoffId'],
      'keep-me',
    );
  });
}
