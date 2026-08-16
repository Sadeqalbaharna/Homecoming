import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/services/core/kai_core_client.dart';
import 'package:homecoming_app/services/core/kai_core_server.dart';
import 'package:homecoming_app/services/core/kai_due_commitment_loop.dart';
import 'package:homecoming_app/services/core/kai_due_commitment_scheduler.dart';
import 'package:homecoming_app/services/core/kai_global_presence_service.dart';

void main() {
  test('eligible presence re-evaluates a no-body deferral immediately',
      () async {
    final directory =
        Directory.systemTemp.createTempSync('kai_due_wake_reviewer');
    var now = DateTime.utc(2026, 9, 1, 7);
    final server = KaiCoreServer(
      dataDirectory: directory,
      port: 0,
      clock: () => now,
    );
    await server.start();
    final client = KaiCoreClient(endpoint: server.endpoint!);
    addTearDown(() async {
      client.close();
      await server.stop();
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });

    final dueAt = DateTime.utc(2026, 9, 1, 6);
    now = DateTime.utc(2026, 8, 8, 12);
    await client.createCommitment(
      commitmentId: 'presence-wake-review',
      personaId: 'truekai',
      text: 'review the invoice',
      dueAt: dueAt,
      dueWallClock: '2026-09-01T09:00:00',
      dueWallOffsetMinutes: 180,
    );
    now = DateTime.utc(2026, 9, 1, 7);

    KaiGlobalPresenceSnapshot presence = KaiGlobalPresenceSnapshot(
      connected: true,
      coordinatorLeaseExpiresAt: DateTime.utc(2030),
      bodies: const [],
      observedAt: now,
    );
    final loop = KaiDueCommitmentLoop(
      interval: const Duration(minutes: 20),
      createScheduler: (isActive) => KaiDueCommitmentScheduler(
        client: client,
        presence: () => presence,
        now: () => now,
        noBodyRetry: const Duration(minutes: 5),
        isActive: isActive,
      ),
    );
    addTearDown(loop.stop);

    loop.start();
    await loop.drainNow();
    var record = (await client.commitments()).single;
    expect(record['status'], 'scheduled');
    expect(
      DateTime.parse(record['nextEvaluationAt'].toString()),
      dueAt,
      reason: 'Option C leaves the already-due Core instant unchanged',
    );
    expect(
      await client.commitments(dueOnly: true),
      hasLength(1),
      reason: 'the still-owed promise remains visible to timer/presence drains',
    );

    const bodyId = 'desktop-presence-wake-reviewer';
    presence = KaiGlobalPresenceSnapshot(
      connected: true,
      coordinatorLeaseExpiresAt: DateTime.utc(2030),
      bodies: [
        KaiGlobalBody(
          bodyId: bodyId,
          deviceId: 'desktop-reviewer',
          surface: 'desktop',
          leaseExpiresAt: DateTime.utc(2030),
          foreground: true,
          lastUserActivityAt: now,
        ),
      ],
      observedAt: now,
    );

    await loop.onPresence(presence);

    record = (await client.commitments()).single;
    expect(
      record['status'],
      'dispatched',
      reason: 'criterion 7 requires eligible presence to deliver the '
          'still-owed due commitment immediately',
    );
    expect(
      await client.pendingOutbound(toSurface: 'desktop', bodyId: bodyId),
      hasLength(1),
    );
  });
}
