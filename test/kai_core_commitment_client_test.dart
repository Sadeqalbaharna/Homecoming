// Brief 014 — the real KaiCoreClient against a real KaiCoreServer over HTTP.
//
// No fakes and no hand-built payloads. The point of this file is that the
// coordinator and desktop will call these exact methods, so anything they can
// get wrong must be reachable here: canonical formatting, monotonic deferral,
// lifecycle refusal, and the mapping of every non-2xx onto KaiCoreException.
//
// Every server runs in its own system-temp directory. Nothing here reads or
// writes %LOCALAPPDATA%\Homecoming\KaiCore.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/services/core/kai_core_client.dart';
import 'package:homecoming_app/services/core/kai_core_server.dart';

final _createdAt = DateTime.utc(2026, 8, 8, 12);
final _dueAt = DateTime.utc(2026, 9, 1, 6);
final _afterDue = DateTime.utc(2026, 9, 1, 7);

const _wallClock = '2026-09-01T09:00:00';
const _bahrainOffset = 180;
const _desktopBody = 'desktop-body-1';
const _conversation = 'in_person';

class _Clock {
  DateTime now = _createdAt;
  DateTime call() => now;
}

Directory _tempCore(String name) {
  final directory = Directory.systemTemp.createTempSync('kai_client_$name');
  addTearDown(() {
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });
  return directory;
}

File _primaryIn(Directory directory) =>
    File('${directory.path}${Platform.pathSeparator}state.json');

class _Harness {
  _Harness(this.directory, this.clock, this.server, this.client);

  final Directory directory;
  final _Clock clock;
  final KaiCoreServer server;
  final KaiCoreClient client;
}

Future<_Harness> _harness(String name,
    {Directory? reuse, _Clock? clock}) async {
  final directory = reuse ?? _tempCore(name);
  final tick = clock ?? _Clock();
  final server =
      KaiCoreServer(dataDirectory: directory, port: 0, clock: tick.call);
  await server.start();
  final client = KaiCoreClient(endpoint: server.endpoint!);
  addTearDown(() async {
    client.close();
    await server.stop();
  });
  return _Harness(directory, tick, server, client);
}

Future<Map<String, dynamic>> _create(
  KaiCoreClient client, {
  String id = 'commit-client',
  String text = 'chase the invoice',
}) =>
    client.createCommitment(
      commitmentId: id,
      personaId: 'truekai',
      text: text,
      dueAt: _dueAt,
      dueWallClock: _wallClock,
      dueWallOffsetMinutes: _bahrainOffset,
    );

/// The raw ledger on disk, so durability is checked against bytes rather than
/// against whatever the server happens to be holding in memory.
Map<String, dynamic> _ledgerOnDisk(Directory directory) =>
    Map<String, dynamic>.from(
      (jsonDecode(_primaryIn(directory).readAsStringSync())
          as Map)['commitments'] as Map,
    );

void main() {
  group('creation and listing', () {
    test('creates one exact commitment and a retry does not duplicate it',
        () async {
      final h = await _harness('create');
      final created = await _create(h.client);
      expect(created['commitmentId'], 'commit-client');
      expect(created['text'], 'chase the invoice');
      expect(created['dueAt'], _dueAt.toIso8601String());
      expect(created['dueWallClock'], _wallClock);
      expect(created['dueWallOffsetMinutes'], _bahrainOffset);
      expect(created['status'], 'scheduled');
      expect(created['audience'], 'work');

      final retry = await _create(h.client);
      expect(retry['createdAt'], created['createdAt'],
          reason: 'a retry returns the stored record, not a fresh one');

      expect((await h.client.commitments()).length, 1);
    });

    test('due-only listing returns scheduled work whose instant has arrived',
        () async {
      final h = await _harness('due_only');
      await _create(h.client);

      expect(await h.client.commitments(dueOnly: true), isEmpty,
          reason: 'nothing is due before its evaluation instant');

      h.clock.now = _afterDue;
      final due = await h.client.commitments(dueOnly: true);
      expect(due.single['commitmentId'], 'commit-client');

      // Once dispatched it is the body's problem, not the scheduler's.
      await h.client.dispatchCommitment(
        'commit-client',
        outboundId: 'commit-client-outbound',
        targetBodyId: _desktopBody,
        conversationId: _conversation,
      );
      expect(await h.client.commitments(dueOnly: true), isEmpty);
      expect((await h.client.commitments()).length, 1,
          reason: 'the full listing still shows it');
    });
  });

  group('durable deferral', () {
    test('advances only nextEvaluationAt and survives restart', () async {
      final h = await _harness('defer_restart');
      final created = await _create(h.client);
      final later = _dueAt.add(const Duration(hours: 5));

      final deferred = await h.client
          .deferCommitment('commit-client', nextEvaluationAt: later);
      expect(deferred['nextEvaluationAt'], later.toIso8601String());

      // Everything that is the PROMISE is untouched.
      for (final field in [
        'commitmentId',
        'personaId',
        'text',
        'dueAt',
        'dueWallClock',
        'dueWallOffsetMinutes',
        'audience',
        'createdAt',
        'status',
        'outboundId',
        'targetBodyId',
        'dispatchedAt',
        'acknowledgedAt',
      ]) {
        expect(deferred[field], created[field], reason: field);
      }

      await h.server.stop();
      final reopened =
          await _harness('defer_restart', reuse: h.directory, clock: h.clock);
      final reloaded = (await reopened.client.commitments()).single;
      expect(reloaded['nextEvaluationAt'], later.toIso8601String(),
          reason: 'the deferral must survive byte-for-byte');
    });

    test('the exact stored value is idempotent, a later value advances once',
        () async {
      final h = await _harness('defer_idempotent');
      await _create(h.client);
      final later = _dueAt.add(const Duration(hours: 2));

      await h.client.deferCommitment('commit-client', nextEvaluationAt: later);
      final again = await h.client
          .deferCommitment('commit-client', nextEvaluationAt: later);
      expect(again['nextEvaluationAt'], later.toIso8601String());

      // Still valid after the instant has passed — repeating yourself must not
      // stop being allowed at the moment the work matters.
      h.clock.now = later.add(const Duration(minutes: 1));
      final afterArrival = await h.client
          .deferCommitment('commit-client', nextEvaluationAt: later);
      expect(afterArrival['nextEvaluationAt'], later.toIso8601String());

      final further = later.add(const Duration(hours: 3));
      final advanced = await h.client
          .deferCommitment('commit-client', nextEvaluationAt: further);
      expect(advanced['nextEvaluationAt'], further.toIso8601String());
      expect((await h.client.commitments()).single['nextEvaluationAt'],
          further.toIso8601String());
    });

    test('an earlier instant is refused as a regression', () async {
      final h = await _harness('defer_regression');
      await _create(h.client);
      final later = _dueAt.add(const Duration(hours: 4));
      await h.client.deferCommitment('commit-client', nextEvaluationAt: later);

      await expectLater(
        h.client.deferCommitment(
          'commit-client',
          nextEvaluationAt: _dueAt.add(const Duration(hours: 1)),
        ),
        throwsA(isA<KaiCoreException>()
            .having((e) => e.statusCode, 'statusCode', HttpStatus.conflict)
            .having((e) => e.message, 'message',
                'commitment_evaluation_regression')),
      );
      expect((await h.client.commitments()).single['nextEvaluationAt'],
          later.toIso8601String());
    });

    test('a non-future instant is refused and the record is unchanged',
        () async {
      final h = await _harness('defer_not_future');
      await _create(h.client);
      // Later than the stored instant, so it clears the regression gate, but
      // already in the past relative to Core's own receipt time.
      h.clock.now = _dueAt.add(const Duration(days: 2));
      await expectLater(
        h.client.deferCommitment(
          'commit-client',
          nextEvaluationAt: _dueAt.add(const Duration(hours: 6)),
        ),
        throwsA(isA<KaiCoreException>()
            .having((e) => e.statusCode, 'statusCode', HttpStatus.badRequest)
            .having((e) => e.message, 'message', 'next_evaluation_not_future')),
      );
      expect((await h.client.commitments()).single['nextEvaluationAt'],
          _dueAt.toIso8601String());
    });

    test('non-canonical and non-UTC spellings are refused at the wire',
        () async {
      // The client always emits canonical UTC, so these go over raw HTTP —
      // the coordinator is not the only thing that can reach loopback.
      final h = await _harness('defer_canonical');
      await _create(h.client);

      final rejected = <String>[
        '2026-09-01 08:00:00.000Z', // space separator
        '2026-09-01T08:00:00Z', // omitted fractional seconds
        '2026-09-01T11:00:00.000+03:00', // numeric offset
        '2026-09-01T08:00:00.000', // no zone at all
        'tomorrow morning', // not a date
      ];
      for (final value in rejected) {
        final response = await _rawPut(
          h.server.endpoint!,
          '/v1/commitments/commit-client/next-evaluation',
          {'nextEvaluationAt': value},
        );
        expect(response['status'], HttpStatus.badRequest, reason: value);
        expect(
            (response['body'] as Map)['error'], 'next_evaluation_not_canonical',
            reason: value);
      }

      final missing = await _rawPut(h.server.endpoint!,
          '/v1/commitments/commit-client/next-evaluation', const {});
      expect(missing['status'], HttpStatus.badRequest);

      expect((await h.client.commitments()).single['nextEvaluationAt'],
          _dueAt.toIso8601String(),
          reason: 'no rejected value may leave a trace');
    });

    test('dispatched and acknowledged commitments cannot be rescheduled',
        () async {
      final h = await _harness('defer_lifecycle');
      await _create(h.client);
      h.clock.now = _afterDue;
      await h.client.dispatchCommitment(
        'commit-client',
        outboundId: 'commit-client-outbound',
        targetBodyId: _desktopBody,
        conversationId: _conversation,
      );

      Future<void> expectNotScheduled() => expectLater(
            h.client.deferCommitment(
              'commit-client',
              nextEvaluationAt: _afterDue.add(const Duration(hours: 1)),
            ),
            throwsA(isA<KaiCoreException>()
                .having((e) => e.statusCode, 'statusCode', HttpStatus.conflict)
                .having(
                    (e) => e.message, 'message', 'commitment_not_scheduled')),
          );

      await expectNotScheduled();
      expect((await h.client.commitments()).single['status'], 'dispatched');

      await h.client.acknowledgeOutbound('commit-client-outbound',
          bodyId: _desktopBody, surface: 'desktop');
      await expectNotScheduled();
      expect((await h.client.commitments()).single['status'], 'acknowledged');
    });

    test('an absent commitment is 404, not a silent no-op', () async {
      final h = await _harness('defer_absent');
      await expectLater(
        h.client.deferCommitment('commit-nobody',
            nextEvaluationAt: _dueAt.add(const Duration(hours: 1))),
        throwsA(isA<KaiCoreException>()
            .having((e) => e.statusCode, 'statusCode', HttpStatus.notFound)
            .having((e) => e.message, 'message', 'commitment_not_found')),
      );
    });

    test('an unsupported ledger refuses deferral and stays byte-preserved',
        () async {
      final directory = _tempCore('defer_future_ledger');
      final state = {
        'version': 2,
        'startedAt': _createdAt.toIso8601String(),
        'presence': <String, dynamic>{},
        'handoffs': <String, dynamic>{},
        'outbound': <String, dynamic>{},
        'tasks': <String, dynamic>{},
        'commitmentLedgerVersion': 999,
        'commitments': {
          'from-the-future': {
            'commitmentId': 'from-the-future',
            'futureField': {'nested': true},
          },
        },
      };
      _primaryIn(directory).writeAsStringSync(jsonEncode(state), flush: true);

      final h = await _harness('defer_future_ledger', reuse: directory);
      await expectLater(
        h.client.deferCommitment('from-the-future',
            nextEvaluationAt: _dueAt.add(const Duration(hours: 1))),
        throwsA(isA<KaiCoreException>()
            .having((e) => e.statusCode, 'statusCode', HttpStatus.conflict)
            .having(
                (e) => e.message, 'message', 'commitment_ledger_unsupported')),
      );

      // An unrelated write must not rewrite what this build cannot read.
      await h.client.heartbeat(
        deviceId: 'device-1',
        surface: 'desktop',
        sessionId: 'session-1',
        foreground: true,
        audioAvailable: false,
      );
      await h.server.stop();

      final onDisk =
          jsonDecode(_primaryIn(directory).readAsStringSync()) as Map;
      expect(onDisk['commitmentLedgerVersion'], 999);
      expect(
          ((onDisk['commitments'] as Map)['from-the-future']
              as Map)['futureField'],
          {'nested': true});
    });

    test('a failed deferral write fails, retries fail, then recovery persists',
        () async {
      final h = await _harness('defer_write_failure');
      await _create(h.client);
      final later = _dueAt.add(const Duration(hours: 7));

      // A directory where the atomic temp file needs to go.
      final blocker = Directory('${_primaryIn(h.directory).path}.tmp')
        ..createSync();

      await expectLater(
        h.client.deferCommitment('commit-client', nextEvaluationAt: later),
        throwsA(isA<KaiCoreException>().having(
            (e) => e.statusCode, 'statusCode', HttpStatus.internalServerError)),
      );

      // Still broken: the identical retry must keep saying so.
      await expectLater(
        h.client.deferCommitment('commit-client', nextEvaluationAt: later),
        throwsA(isA<KaiCoreException>().having(
            (e) => e.statusCode, 'statusCode', HttpStatus.internalServerError)),
      );

      blocker.deleteSync();
      final repaired = await h.client
          .deferCommitment('commit-client', nextEvaluationAt: later);
      expect(repaired['nextEvaluationAt'], later.toIso8601String());

      await h.server.stop();
      expect(
        (_ledgerOnDisk(h.directory)['commit-client']
            as Map)['nextEvaluationAt'],
        later.toIso8601String(),
        reason: 'the repaired deferral must be on disk, not just in memory',
      );
    });
  });

  group('dispatch and acknowledgement through the client', () {
    test('one envelope for the exact body, surface, conversation and text',
        () async {
      final h = await _harness('dispatch');
      await _create(h.client);
      h.clock.now = _afterDue;

      final dispatched = await h.client.dispatchCommitment(
        'commit-client',
        outboundId: 'commit-client-outbound',
        targetBodyId: _desktopBody,
        conversationId: _conversation,
      );
      expect(dispatched['status'], 'dispatched');

      final inbox = await h.client
          .pendingOutbound(toSurface: 'desktop', bodyId: _desktopBody);
      expect(inbox.length, 1);
      expect(inbox.single['text'], 'chase the invoice');
      expect(inbox.single['conversationId'], _conversation);
      expect(inbox.single['commitmentId'], 'commit-client');

      // A retry mints nothing new.
      await h.client.dispatchCommitment(
        'commit-client',
        outboundId: 'commit-client-outbound',
        targetBodyId: _desktopBody,
        conversationId: _conversation,
      );
      expect(
        (await h.client
                .pendingOutbound(toSurface: 'desktop', bodyId: _desktopBody))
            .length,
        1,
      );
    });

    test(
        'the wrong body or surface cannot acknowledge; the right one closes '
        'both records', () async {
      final h = await _harness('ack');
      await _create(h.client);
      h.clock.now = _afterDue;
      await h.client.dispatchCommitment(
        'commit-client',
        outboundId: 'commit-client-outbound',
        targetBodyId: _desktopBody,
        conversationId: _conversation,
      );

      await expectLater(
        h.client.acknowledgeOutbound('commit-client-outbound',
            bodyId: 'some-other-body', surface: 'desktop'),
        throwsA(isA<KaiCoreException>()
            .having((e) => e.statusCode, 'statusCode', HttpStatus.conflict)),
      );
      await expectLater(
        h.client.acknowledgeOutbound('commit-client-outbound',
            bodyId: _desktopBody, surface: 'messenger'),
        throwsA(isA<KaiCoreException>()
            .having((e) => e.statusCode, 'statusCode', HttpStatus.conflict)),
      );
      expect((await h.client.commitments()).single['status'], 'dispatched',
          reason: 'the promise is still owed');

      final acked = await h.client.acknowledgeOutbound('commit-client-outbound',
          bodyId: _desktopBody, surface: 'desktop');
      expect(acked['status'], 'acknowledged');
      expect((await h.client.commitments()).single['status'], 'acknowledged');
      expect(
        await h.client
            .pendingOutbound(toSurface: 'desktop', bodyId: _desktopBody),
        isEmpty,
      );

      await h.server.stop();
      expect((_ledgerOnDisk(h.directory)['commit-client'] as Map)['status'],
          'acknowledged');
    });
  });

  group('failures are never reported as success', () {
    test('a rejected creation throws with the exact Core status and code',
        () async {
      final h = await _harness('bad_create');
      await expectLater(
        h.client.createCommitment(
          commitmentId: 'commit-bad-provenance',
          personaId: 'truekai',
          text: 'chase the invoice',
          dueAt: _dueAt,
          // 10:00 Bahrain is not 06:00Z; provenance must be true or absent.
          dueWallClock: '2026-09-01T10:00:00',
          dueWallOffsetMinutes: _bahrainOffset,
        ),
        throwsA(isA<KaiCoreException>()
            .having((e) => e.statusCode, 'statusCode', HttpStatus.badRequest)
            .having(
                (e) => e.message, 'message', 'commitment_provenance_mismatch')),
      );
      expect(await h.client.commitments(), isEmpty);
    });

    test('dispatch before the evaluation instant throws conflict', () async {
      final h = await _harness('early_dispatch');
      await _create(h.client);
      await expectLater(
        h.client.dispatchCommitment(
          'commit-client',
          outboundId: 'commit-client-outbound',
          targetBodyId: _desktopBody,
          conversationId: _conversation,
        ),
        throwsA(isA<KaiCoreException>()
            .having((e) => e.statusCode, 'statusCode', HttpStatus.conflict)
            .having((e) => e.message, 'message', 'commitment_not_yet_due')),
      );
      expect(
        await h.client
            .pendingOutbound(toSurface: 'desktop', bodyId: _desktopBody),
        isEmpty,
      );
    });

    test('a transport failure is an exception, never an empty success',
        () async {
      // Nothing is listening on this port.
      final dead = KaiCoreClient(
        endpoint: Uri.parse('http://127.0.0.1:1'),
        timeout: const Duration(milliseconds: 300),
      );
      addTearDown(dead.close);

      await expectLater(dead.commitments(), throwsA(isA<Object>()));
      expect(await dead.isHealthy(), isFalse,
          reason: 'only the explicit health probe may soften a failure');
    });
  });
}

Future<Map<String, dynamic>> _rawPut(
  Uri endpoint,
  String path,
  Map<String, Object?> body,
) async {
  final client = HttpClient();
  try {
    final request = await client.putUrl(endpoint.resolve(path));
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(body));
    final response = await request.close();
    final text = await utf8.decoder.bind(response).join();
    return {
      'status': response.statusCode,
      'body': text.isEmpty ? <String, dynamic>{} : jsonDecode(text),
    };
  } finally {
    client.close(force: true);
  }
}
