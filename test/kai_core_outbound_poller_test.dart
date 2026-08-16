// Brief 015 — the exact-body outbound poller, against a real Core over HTTP.
//
// Real server, real client, real loopback. A mock would let the poller's own
// filtering assumptions define the test, and the thing most worth proving here
// is that one desktop cannot see or close another desktop's reminder.
//
// Temp directories only; nothing touches the live Core state.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/services/core/kai_core_client.dart';
import 'package:homecoming_app/services/core/kai_core_server.dart';

final _createdAt = DateTime.utc(2026, 8, 8, 12);
final _dueAt = DateTime.utc(2026, 9, 1, 6);
final _afterDue = DateTime.utc(2026, 9, 1, 7);

const _wallClock = '2026-09-01T09:00:00';
const _thisBody = 'desktop-body-mine';
const _otherBody = 'desktop-body-theirs';

class _Clock {
  DateTime now = _createdAt;
  DateTime call() => now;
}

class _Fixture {
  _Fixture(this.clock, this.server, this.client);

  final _Clock clock;
  final KaiCoreServer server;
  final KaiCoreClient client;
}

Future<_Fixture> _fixture(String name) async {
  final directory = Directory.systemTemp.createTempSync('kai_poller_$name');
  final clock = _Clock();
  final server =
      KaiCoreServer(dataDirectory: directory, port: 0, clock: clock.call);
  await server.start();
  final client = KaiCoreClient(endpoint: server.endpoint!);
  addTearDown(() async {
    client.close();
    await server.stop();
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });
  return _Fixture(clock, server, client);
}

/// Schedule and dispatch one commitment to [bodyId], leaving it pending.
///
/// The clock has to move between the two calls: Core refuses a commitment
/// created in the past, and equally refuses a dispatch before its evaluation
/// instant. Both gates are real, so the fixture honours both.
Future<void> _owe(
  _Fixture f, {
  required String id,
  required String bodyId,
  String text = 'chase the invoice',
}) async {
  f.clock.now = _createdAt;
  await f.client.createCommitment(
    commitmentId: id,
    personaId: 'truekai',
    text: text,
    dueAt: _dueAt,
    dueWallClock: _wallClock,
    dueWallOffsetMinutes: 180,
  );
  f.clock.now = _afterDue;
  await f.client.dispatchCommitment(
    id,
    outboundId: '$id-outbound',
    targetBodyId: bodyId,
    conversationId: 'in_person',
  );
}

KaiCoreOutboundInbox _inbox(
  KaiCoreClient client,
  KaiCoreOutboundReceiver onOutbound, {
  String bodyId = _thisBody,
  String surface = 'desktop',
}) {
  final inbox = KaiCoreOutboundInbox(
    client: client,
    surface: surface,
    bodyId: bodyId,
    onOutbound: onOutbound,
    interval: const Duration(milliseconds: 20),
  );
  addTearDown(inbox.stop);
  return inbox;
}

void main() {
  test('an accepted record is acknowledged and stops being pending', () async {
    final f = await _fixture('accept');
    await _owe(f, id: 'commit-a', bodyId: _thisBody);

    final seen = <String>[];
    final inbox = _inbox(f.client, (record) async {
      seen.add(record['outboundId'].toString());
      return true;
    });

    await inbox.poll();
    expect(seen, ['commit-a-outbound']);
    expect(
      await f.client.pendingOutbound(toSurface: 'desktop', bodyId: _thisBody),
      isEmpty,
    );

    // A second drain has nothing left to do.
    await inbox.poll();
    expect(seen.length, 1);
  });

  test('a rejected record stays pending and is offered again', () async {
    final f = await _fixture('reject');
    await _owe(f, id: 'commit-b', bodyId: _thisBody);

    var attempts = 0;
    final inbox = _inbox(f.client, (_) async {
      attempts++;
      return attempts > 2; // fail twice, then accept
    });

    await inbox.poll();
    expect(
      await f.client.pendingOutbound(toSurface: 'desktop', bodyId: _thisBody),
      hasLength(1),
      reason: 'a refused reminder is still owed',
    );

    await inbox.poll();
    await inbox.poll();
    expect(attempts, 3);
    expect(
      await f.client.pendingOutbound(toSurface: 'desktop', bodyId: _thisBody),
      isEmpty,
    );
  });

  test(
      'a throwing callback leaves the record pending and does not kill the '
      'poller', () async {
    final f = await _fixture('throw');
    await _owe(f, id: 'commit-c', bodyId: _thisBody);

    var calls = 0;
    final inbox = _inbox(f.client, (_) async {
      calls++;
      if (calls == 1) throw StateError('transcript unavailable');
      return true;
    });

    await inbox.poll();
    expect(
      await f.client.pendingOutbound(toSurface: 'desktop', bodyId: _thisBody),
      hasLength(1),
    );

    await inbox.poll();
    expect(calls, 2);
    expect(
      await f.client.pendingOutbound(toSurface: 'desktop', bodyId: _thisBody),
      isEmpty,
    );
  });

  test('another body\'s reminder never reaches this callback', () async {
    final f = await _fixture('wrong_body');
    await _owe(f, id: 'commit-theirs', bodyId: _otherBody);

    final seen = <String>[];
    await _inbox(f.client, (record) async {
      seen.add(record['outboundId'].toString());
      return true;
    }).poll();

    expect(seen, isEmpty, reason: 'a promise is owed to one exact machine');
    expect(
      await f.client.pendingOutbound(toSurface: 'desktop', bodyId: _otherBody),
      hasLength(1),
      reason: 'and it is still owed to the body that should show it',
    );
  });

  test('this desktop cannot acknowledge another body\'s reminder', () async {
    final f = await _fixture('wrong_body_ack');
    await _owe(f, id: 'commit-theirs', bodyId: _otherBody);

    await expectLater(
      f.client.acknowledgeOutbound('commit-theirs-outbound',
          bodyId: _thisBody, surface: 'desktop'),
      throwsA(isA<KaiCoreException>()
          .having((e) => e.statusCode, 'statusCode', HttpStatus.conflict)),
    );
  });

  test('a record for another surface never reaches this callback', () async {
    final f = await _fixture('wrong_surface');
    // Core refuses non-desktop commitment dispatch, so this is an ordinary
    // outbound aimed at the same body id on a different surface.
    await f.client.createOutbound(
      outboundId: 'messenger-note',
      kind: 'proactive_friend',
      fromSurface: 'central',
      toSurface: 'messenger',
      targetBodyId: _thisBody,
      conversationId: 'messenger',
      text: 'a friend-lane message',
      expiresAt: _createdAt.add(const Duration(hours: 1)),
    );

    final seen = <String>[];
    await _inbox(f.client, (record) async {
      seen.add(record['outboundId'].toString());
      return true;
    }).poll();

    expect(seen, isEmpty);
  });

  test('overlapping drains collapse into one; no record is handled twice',
      () async {
    final f = await _fixture('overlap');
    await _owe(f, id: 'commit-d', bodyId: _thisBody);

    final release = Completer<void>();
    var entered = 0;
    final inbox = _inbox(f.client, (_) async {
      entered++;
      await release.future; // hold the drain open
      return true;
    });

    final first = inbox.poll();
    // Fire more drains while the first is still inside the callback.
    final overlapping = [inbox.poll(), inbox.poll(), inbox.poll()];
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(entered, 1, reason: 'one promise must not be rendered three times');

    release.complete();
    await Future.wait([first, ...overlapping]);
    expect(entered, 1);
    expect(
      await f.client.pendingOutbound(toSurface: 'desktop', bodyId: _thisBody),
      isEmpty,
    );
  });

  test('an unreachable Core is contained, and recovery resumes delivery',
      () async {
    final f = await _fixture('unreachable');
    await _owe(f, id: 'commit-e', bodyId: _thisBody);

    final dead = KaiCoreClient(
      endpoint: Uri.parse('http://127.0.0.1:1'),
      timeout: const Duration(milliseconds: 200),
    );
    addTearDown(dead.close);

    var seen = 0;
    // Must not throw out of poll().
    await _inbox(dead, (_) async {
      seen++;
      return true;
    }).poll();
    expect(seen, 0);

    await _inbox(f.client, (_) async {
      seen++;
      return true;
    }).poll();
    expect(seen, 1);
  });

  test('start is idempotent and stop halts the timer', () async {
    final f = await _fixture('lifecycle');
    final inbox = _inbox(f.client, (_) async => true);
    expect(inbox.isRunning, isFalse);
    inbox.start();
    inbox.start();
    expect(inbox.isRunning, isTrue);
    inbox.stop();
    expect(inbox.isRunning, isFalse);
  });

  test('the timer delivers without a manual poll', () async {
    final f = await _fixture('timer');
    await _owe(f, id: 'commit-f', bodyId: _thisBody);

    final delivered = Completer<String>();
    _inbox(f.client, (record) async {
      if (!delivered.isCompleted) {
        delivered.complete(record['outboundId'].toString());
      }
      return true;
    }).start();

    expect(await delivered.future.timeout(const Duration(seconds: 5)),
        'commit-f-outbound');
  });
}
