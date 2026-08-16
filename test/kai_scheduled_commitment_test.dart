import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/services/core/kai_core_server.dart';
import 'package:homecoming_app/services/core/kai_scheduled_commitment.dart';

/// Unique temporary Core directory per test. The user's real
/// %LOCALAPPDATA%\Homecoming\KaiCore is never read or written.
Directory _tempCore(String name) {
  final dir = Directory.systemTemp.createTempSync('kai_commit_$name');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  return dir;
}

/// A future Bahrain instant used throughout: 2026-09-01 09:00 +03:00.
final _dueUtc = DateTime.utc(2026, 9, 1, 6);
final _beforeDue = DateTime.utc(2026, 8, 8, 12);

Future<KaiCoreServer> _server(
  Directory dir, {
  required DateTime Function() clock,
}) async {
  final server = KaiCoreServer(dataDirectory: dir, port: 0, clock: clock);
  await server.start();
  addTearDown(server.stop);
  return server;
}

Future<Map<String, dynamic>> _post(
  Uri endpoint,
  String path,
  Map<String, Object?> body,
) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(endpoint.resolve(path));
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

Future<Map<String, dynamic>> _get(Uri endpoint, String path) async {
  final client = HttpClient();
  try {
    final response =
        await (await client.getUrl(endpoint.resolve(path))).close();
    final text = await utf8.decoder.bind(response).join();
    return {
      'status': response.statusCode,
      'body': text.isEmpty ? <String, dynamic>{} : jsonDecode(text),
    };
  } finally {
    client.close(force: true);
  }
}

Map<String, Object?> _commitment({
  String id = 'c-1',
  String text = 'chase the invoice',
  DateTime? dueAt,
}) =>
    {
      'commitmentId': id,
      'personaId': 'truekai',
      'text': text,
      'dueAt': (dueAt ?? _dueUtc).toIso8601String(),
      'dueWallClock': '2026-09-01T09:00:00',
      'dueWallOffsetMinutes': 180,
    };

void main() {
  group('Bahrain wall-clock conversion', () {
    test('wall time converts once to UTC and never reads the host zone', () {
      final due = KaiScheduledCommitment.bahrainWallToUtc(
        year: 2026,
        month: 9,
        day: 1,
        hour: 9,
        minute: 0,
      );

      expect(due.isUtc, isTrue);
      expect(due, DateTime.utc(2026, 9, 1, 6),
          reason: '09:00 Bahrain is 06:00 UTC, always — UTC+03:00, no DST');
    });

    test('a wall time that wraps the date converts correctly', () {
      // 01:30 Bahrain is 22:30 UTC on the PREVIOUS day.
      final due = KaiScheduledCommitment.bahrainWallToUtc(
        year: 2026,
        month: 9,
        day: 1,
        hour: 1,
        minute: 30,
      );
      expect(due, DateTime.utc(2026, 8, 31, 22, 30));
    });

    test('invalid calendar values are rejected, not normalised', () {
      for (final invalid in [
        [2026, 13, 1, 9, 0],
        [2026, 2, 30, 9, 0],
        [2026, 9, 1, 24, 0],
        [2026, 9, 1, 9, 60],
        [2026, 0, 1, 9, 0],
      ]) {
        expect(
          () => KaiScheduledCommitment.bahrainWallToUtc(
            year: invalid[0],
            month: invalid[1],
            day: invalid[2],
            hour: invalid[3],
            minute: invalid[4],
          ),
          throwsA(isA<FormatException>()),
          reason: invalid.toString(),
        );
      }
    });
  });

  group('deterministic commitment id', () {
    test('the same intent yields the same id across a retry', () {
      final first = KaiScheduledCommitment.deterministicId(
        personaId: 'truekai',
        text: '  Chase   the invoice  ',
        dueAtUtc: _dueUtc,
      );
      final retry = KaiScheduledCommitment.deterministicId(
        personaId: 'truekai',
        text: 'Chase the invoice',
        dueAtUtc: _dueUtc,
      );

      expect(first, retry,
          reason: 'normalised text — a retry must reach the same record');
      expect(first, startsWith('commit-'));
      expect(first.length, greaterThan(16));
    });

    test('different text or time yields a different id', () {
      final base = KaiScheduledCommitment.deterministicId(
        personaId: 'truekai',
        text: 'a',
        dueAtUtc: _dueUtc,
      );
      expect(
        KaiScheduledCommitment.deterministicId(
            personaId: 'truekai', text: 'b', dueAtUtc: _dueUtc),
        isNot(base),
      );
      expect(
        KaiScheduledCommitment.deterministicId(
            personaId: 'truekai',
            text: 'a',
            dueAtUtc: _dueUtc.add(const Duration(minutes: 1))),
        isNot(base),
      );
    });

    test('the id is Firebase-path safe', () {
      final id = KaiScheduledCommitment.deterministicId(
        personaId: 'truekai',
        text: 'has / . \$ # [ ] forbidden characters',
        dueAtUtc: _dueUtc,
      );
      for (final forbidden in ['/', '.', r'$', '#', '[', ']']) {
        expect(id, isNot(contains(forbidden)));
      }
    });

    test('the deterministic transcript key is also path safe', () {
      final key = KaiScheduledCommitment.transcriptKey('commit-abc123');
      for (final forbidden in ['/', '.', r'$', '#', '[', ']']) {
        expect(key, isNot(contains(forbidden)));
      }
    });
  });

  group('Core ledger', () {
    test('a valid future commitment is created with exact text and UTC',
        () async {
      final dir = _tempCore('create');
      final server = await _server(dir, clock: () => _beforeDue);

      final created =
          await _post(server.endpoint!, '/v1/commitments', _commitment());
      expect(created['status'], HttpStatus.created);

      final record = created['body'] as Map<String, dynamic>;
      expect(record['text'], 'chase the invoice');
      expect(record['dueAt'], _dueUtc.toIso8601String());
      expect(record['dueWallClock'], '2026-09-01T09:00:00');
      expect(record['dueWallOffsetMinutes'], 180);
      expect(record['status'], 'scheduled');
      expect(record['audience'], 'work');
      expect(record['outboundId'], isNull);
    });

    test('invalid input fails closed without creating a record', () async {
      final dir = _tempCore('invalid');
      final server = await _server(dir, clock: () => _beforeDue);

      final cases = <Map<String, Object?>>[
        // Past instant.
        _commitment(dueAt: _beforeDue.subtract(const Duration(hours: 1))),
        // Empty text.
        {..._commitment(), 'text': '   '},
        // Oversized text.
        {..._commitment(), 'text': 'x' * 2001},
        // Missing id.
        {..._commitment()}..remove('commitmentId'),
        // Unparseable due instant.
        {..._commitment(), 'dueAt': 'not-a-date'},
      ];

      for (final invalid in cases) {
        final result =
            await _post(server.endpoint!, '/v1/commitments', invalid);
        expect(result['status'], HttpStatus.badRequest, reason: '$invalid');
      }

      final listed = await _get(server.endpoint!, '/v1/commitments');
      expect((listed['body'] as Map)['commitments'], isEmpty,
          reason: 'nothing partial was written');
    });

    test('same id + same intent is idempotent; different intent conflicts',
        () async {
      final dir = _tempCore('idempotent');
      final server = await _server(dir, clock: () => _beforeDue);

      await _post(server.endpoint!, '/v1/commitments', _commitment());
      final again =
          await _post(server.endpoint!, '/v1/commitments', _commitment());
      expect(again['status'], HttpStatus.ok);
      expect((again['body'] as Map)['status'], 'scheduled');

      final conflict = await _post(
        server.endpoint!,
        '/v1/commitments',
        _commitment(text: 'a different promise'),
      );
      expect(conflict['status'], HttpStatus.conflict);
      expect((conflict['body'] as Map)['error'], 'commitment_id_conflict');

      final listed = await _get(server.endpoint!, '/v1/commitments');
      expect(((listed['body'] as Map)['commitments'] as List).length, 1);
    });

    test('nothing is due before the due instant', () async {
      final dir = _tempCore('not_due');
      final server = await _server(dir, clock: () => _beforeDue);
      await _post(server.endpoint!, '/v1/commitments', _commitment());

      final due = await _get(server.endpoint!, '/v1/commitments?due=true');
      expect((due['body'] as Map)['commitments'], isEmpty);
    });

    test('it becomes due once the clock passes the instant', () async {
      final dir = _tempCore('due');
      var now = _beforeDue;
      final server = await _server(dir, clock: () => now);
      await _post(server.endpoint!, '/v1/commitments', _commitment());

      now = _dueUtc.add(const Duration(minutes: 1));
      final due = await _get(server.endpoint!, '/v1/commitments?due=true');
      expect(((due['body'] as Map)['commitments'] as List).length, 1);
    });
  });

  group('restart', () {
    test('a pre-due commitment restores with identical fields', () async {
      final dir = _tempCore('restart');
      final first = await _server(dir, clock: () => _beforeDue);
      final created =
          await _post(first.endpoint!, '/v1/commitments', _commitment());
      final before = created['body'] as Map<String, dynamic>;
      await first.stop();

      final second = await _server(dir, clock: () => _beforeDue);
      final listed = await _get(second.endpoint!, '/v1/commitments');
      final after =
          ((listed['body'] as Map)['commitments'] as List).single as Map;

      expect(after['commitmentId'], before['commitmentId']);
      expect(after['text'], before['text']);
      expect(after['dueAt'], before['dueAt']);
      expect(after['createdAt'], before['createdAt']);
      expect(after['status'], 'scheduled');
    });

    test('a pre-Brief-012 state migrates additively', () async {
      final dir = _tempCore('migrate');
      // A Core file written before the ledger existed, with real records.
      File('${dir.path}${Platform.pathSeparator}state.json').writeAsStringSync(
        jsonEncode({
          'version': 2,
          'startedAt': _beforeDue.toIso8601String(),
          'presence': {
            'device-1': {'deviceId': 'device-1', 'surface': 'desktop'}
          },
          'handoffs': {
            'h-1': {'handoffId': 'h-1', 'status': 'pending'}
          },
          'outbound': {
            'o-1': {'outboundId': 'o-1', 'status': 'pending'}
          },
          'tasks': {
            't-1': {'taskId': 't-1', 'status': 'queued'}
          },
        }),
      );

      final server = await _server(dir, clock: () => _beforeDue);
      final listed = await _get(server.endpoint!, '/v1/commitments');
      expect(listed['status'], HttpStatus.ok);
      expect((listed['body'] as Map)['commitments'], isEmpty,
          reason: 'migrated to an empty version-1 ledger');

      // Force a durable write, then assert every pre-existing record survived
      // on disk. Asserting the state file directly is stricter than any
      // endpoint: it proves migration was additive rather than reconstructive.
      await _post(server.endpoint!, '/v1/commitments', _commitment());
      await server.stop();

      final onDisk = jsonDecode(
        File('${dir.path}${Platform.pathSeparator}state.json')
            .readAsStringSync(),
      ) as Map<String, dynamic>;

      expect(onDisk['commitmentLedgerVersion'], 1);
      expect((onDisk['presence'] as Map)['device-1'], isNotNull);
      expect((onDisk['handoffs'] as Map)['h-1'], isNotNull);
      expect((onDisk['outbound'] as Map)['o-1'], isNotNull);
      expect((onDisk['tasks'] as Map)['t-1'], isNotNull);
      expect(onDisk['version'], 2, reason: 'Core version is not disturbed');
    });

    test('an unsupported future ledger is retained and refused, not emptied',
        () async {
      final dir = _tempCore('future_ledger');
      final stateFile = File('${dir.path}${Platform.pathSeparator}state.json');
      final original = jsonEncode({
        'version': 2,
        'startedAt': _beforeDue.toIso8601String(),
        'presence': <String, dynamic>{},
        'handoffs': <String, dynamic>{},
        'outbound': <String, dynamic>{},
        'tasks': <String, dynamic>{},
        'commitmentLedgerVersion': 999,
        'commitments': {
          'future-1': {'commitmentId': 'future-1', 'text': 'still owed'}
        },
      });
      stateFile.writeAsStringSync(original);

      final server = await _server(dir, clock: () => _beforeDue);

      // Refused rather than interpreted.
      final listed = await _get(server.endpoint!, '/v1/commitments');
      expect(listed['status'], HttpStatus.conflict);
      expect((listed['body'] as Map)['error'], 'commitment_ledger_unsupported');

      final created =
          await _post(server.endpoint!, '/v1/commitments', _commitment());
      expect(created['status'], HttpStatus.conflict);

      // And the unreadable ledger is still on disk, unchanged.
      final onDisk = jsonDecode(stateFile.readAsStringSync()) as Map;
      expect(onDisk['commitmentLedgerVersion'], 999);
      expect((onDisk['commitments'] as Map)['future-1'], isNotNull);
    });
  });
}
