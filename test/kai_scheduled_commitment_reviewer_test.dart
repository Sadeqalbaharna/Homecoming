import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/services/core/kai_core_server.dart';

final _createdAt = DateTime.utc(2026, 8, 8, 12);
final _dueAt = DateTime.utc(2026, 9, 1, 6);
final _afterDue = DateTime.utc(2026, 9, 1, 7);

class _Clock {
  DateTime now = _createdAt;
  DateTime call() => now;
}

Directory _tempCore(String name) {
  final directory =
      Directory.systemTemp.createTempSync('kai_commit_review_$name');
  addTearDown(() {
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });
  return directory;
}

Future<KaiCoreServer> _server(Directory directory, _Clock clock) async {
  final server = KaiCoreServer(
    dataDirectory: directory,
    port: 0,
    clock: clock.call,
  );
  await server.start();
  addTearDown(server.stop);
  return server;
}

Future<Map<String, dynamic>> _request(
  Uri endpoint,
  String method,
  String path, {
  Map<String, Object?>? body,
}) async {
  final client = HttpClient();
  try {
    final uri = endpoint.resolve(path);
    final request = switch (method) {
      'GET' => await client.getUrl(uri),
      'POST' => await client.postUrl(uri),
      _ => throw ArgumentError.value(method, 'method'),
    };
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
    }
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

Map<String, Object?> _commitment({
  String id = 'commit-review',
  String personaId = 'truekai',
  String text = 'chase the invoice',
  String wallClock = '2026-09-01T09:00:00',
  int offsetMinutes = 180,
}) =>
    {
      'commitmentId': id,
      'personaId': personaId,
      'text': text,
      'dueAt': _dueAt.toIso8601String(),
      'dueWallClock': wallClock,
      'dueWallOffsetMinutes': offsetMinutes,
    };

Map<String, dynamic> _stateWithCommitment({
  int ledgerVersion = 1,
}) =>
    {
      'version': 2,
      'startedAt': _createdAt.toIso8601String(),
      'presence': <String, dynamic>{},
      'handoffs': <String, dynamic>{},
      'outbound': <String, dynamic>{},
      'tasks': <String, dynamic>{},
      'commitmentLedgerVersion': ledgerVersion,
      'commitments': {
        'commit-from-backup': {
          'commitmentId': 'commit-from-backup',
          'personaId': 'truekai',
          'text': 'survive the crash window',
          'dueAt': _dueAt.toIso8601String(),
          'dueWallClock': '2026-09-01T09:00:00',
          'dueWallOffsetMinutes': 180,
          'audience': 'work',
          'createdAt': _createdAt.toIso8601String(),
          'status': 'scheduled',
          'nextEvaluationAt': _dueAt.toIso8601String(),
          'outboundId': null,
          'targetBodyId': null,
          'dispatchedAt': null,
          'acknowledgedAt': null,
        },
      },
    };

Future<void> _schedule(Uri endpoint, {Map<String, Object?>? body}) async {
  final result = await _request(
    endpoint,
    'POST',
    '/v1/commitments',
    body: body ?? _commitment(),
  );
  expect(result['status'], anyOf(HttpStatus.created, HttpStatus.ok));
}

Future<Map<String, dynamic>> _dispatch(
  Uri endpoint, {
  String outboundId = 'commit-review-outbound',
  String bodyId = 'desktop-body-review',
  String surface = 'desktop',
}) =>
    _request(
      endpoint,
      'POST',
      '/v1/commitments/commit-review/dispatch',
      body: {
        'outboundId': outboundId,
        'targetBodyId': bodyId,
        'toSurface': surface,
        'conversationId': 'in_person',
      },
    );

void main() {
  group('last-readable Core state survives recovery', () {
    test('backup-only startup restores commitments and preserves the backup',
        () async {
      final directory = _tempCore('backup_only');
      final backup =
          File('${directory.path}${Platform.pathSeparator}state.json.bak');
      backup.writeAsStringSync(jsonEncode(_stateWithCommitment()), flush: true);

      final clock = _Clock();
      final server = await _server(directory, clock);
      final listed = await _request(server.endpoint!, 'GET', '/v1/commitments');
      final records = (listed['body'] as Map)['commitments'] as List;
      expect(records.map((item) => (item as Map)['commitmentId']),
          contains('commit-from-backup'));

      await _schedule(server.endpoint!, body: _commitment(id: 'commit-new'));
      await server.stop();

      final primary =
          File('${directory.path}${Platform.pathSeparator}state.json');
      expect(primary.existsSync(), isTrue);
      expect(backup.existsSync(), isTrue,
          reason:
              'the last readable copy must survive until a new primary lands');
      expect(jsonDecode(backup.readAsStringSync()), isA<Map>());
      expect(
        ((jsonDecode(primary.readAsStringSync()) as Map)['commitments'] as Map)
            .keys,
        containsAll(['commit-from-backup', 'commit-new']),
      );
    });

    test('corrupt primary plus readable backup keeps readable evidence',
        () async {
      final directory = _tempCore('corrupt_primary');
      final primary =
          File('${directory.path}${Platform.pathSeparator}state.json')
            ..writeAsStringSync('{ definitely broken', flush: true);
      final backup = File('${primary.path}.bak')
        ..writeAsStringSync(jsonEncode(_stateWithCommitment()), flush: true);

      final clock = _Clock();
      final server = await _server(directory, clock);
      await _schedule(server.endpoint!, body: _commitment(id: 'commit-new'));
      await server.stop();

      expect(jsonDecode(primary.readAsStringSync()), isA<Map>());
      expect(backup.existsSync(), isTrue);
      expect(jsonDecode(backup.readAsStringSync()), isA<Map>(),
          reason:
              'normal rotation must not replace the readable backup with corrupt bytes');
    });
  });

  group('dispatch admission is fail-closed', () {
    test('Core refuses dispatch before nextEvaluationAt', () async {
      final directory = _tempCore('early_dispatch');
      final clock = _Clock();
      final server = await _server(directory, clock);
      await _schedule(server.endpoint!);

      final dispatched = await _dispatch(server.endpoint!);
      expect(dispatched['status'], HttpStatus.conflict);

      final inbox = await _request(
        server.endpoint!,
        'GET',
        '/v1/outbound?toSurface=desktop&bodyId=desktop-body-review',
      );
      expect((inbox['body'] as Map)['outbound'], isEmpty);
    });

    test('a dispatched commitment is not returned as due work', () async {
      final directory = _tempCore('dispatched_due');
      final clock = _Clock();
      final server = await _server(directory, clock);
      await _schedule(server.endpoint!);
      clock.now = _afterDue;
      expect((await _dispatch(server.endpoint!))['status'], HttpStatus.ok);

      final due = await _request(
        server.endpoint!,
        'GET',
        '/v1/commitments?due=true',
      );
      expect((due['body'] as Map)['commitments'], isEmpty,
          reason:
              'dispatched waits for acknowledgement; it is not scheduler work');
    });

    test('an existing unrelated outbound ID cannot be captured', () async {
      final directory = _tempCore('outbound_collision');
      final clock = _Clock();
      final server = await _server(directory, clock);
      await _schedule(server.endpoint!);

      final collision = await _request(
        server.endpoint!,
        'POST',
        '/v1/outbound',
        body: {
          'outboundId': 'commit-review-outbound',
          'kind': 'proactive_friend',
          'fromSurface': 'central',
          'toSurface': 'desktop',
          'targetBodyId': 'some-other-body',
          'conversationId': 'in_person',
          'correlationId': 'unrelated',
          'text': 'unrelated message',
          'expiresAt':
              _createdAt.add(const Duration(hours: 1)).toIso8601String(),
        },
      );
      expect(collision['status'], HttpStatus.created);

      clock.now = _afterDue;
      final dispatched = await _dispatch(server.endpoint!);
      expect(dispatched['status'], HttpStatus.conflict);

      final listed = await _request(server.endpoint!, 'GET', '/v1/commitments');
      expect(((listed['body'] as Map)['commitments'] as List).single['status'],
          'scheduled');
    });

    test('the v1 work-reminder endpoint refuses a non-desktop surface',
        () async {
      final directory = _tempCore('wrong_dispatch_surface');
      final clock = _Clock();
      final server = await _server(directory, clock);
      await _schedule(server.endpoint!);
      clock.now = _afterDue;

      final dispatched =
          await _dispatch(server.endpoint!, surface: 'messenger');
      expect(dispatched['status'], HttpStatus.conflict);
    });
  });

  test('an unacknowledged commitment outbound does not expire after 24 hours',
      () async {
    final directory = _tempCore('durable_outbound');
    final clock = _Clock();
    final server = await _server(directory, clock);
    await _schedule(server.endpoint!);
    clock.now = _afterDue;
    expect((await _dispatch(server.endpoint!))['status'], HttpStatus.ok);

    clock.now = _afterDue.add(const Duration(days: 2));
    final inbox = await _request(
      server.endpoint!,
      'GET',
      '/v1/outbound?toSurface=desktop&bodyId=desktop-body-review',
    );
    expect(((inbox['body'] as Map)['outbound'] as List).length, 1,
        reason: 'a promise remains owed until its exact body acknowledges it');
  });

  group('commitment intent and provenance are immutable', () {
    test('same ID with a different persona or wall provenance conflicts',
        () async {
      for (final variant in [
        _commitment(personaId: 'somebody-else'),
        _commitment(wallClock: '2026-09-01T10:00:00'),
        _commitment(offsetMinutes: 0),
      ]) {
        final directory = _tempCore('intent_conflict');
        final clock = _Clock();
        final server = await _server(directory, clock);
        await _schedule(server.endpoint!);
        final retry = await _request(
          server.endpoint!,
          'POST',
          '/v1/commitments',
          body: variant,
        );
        expect(retry['status'], HttpStatus.conflict, reason: '$variant');
        await server.stop();
      }
    });

    test('invalid Bahrain offset or wall/UTC mismatch is rejected', () async {
      for (final invalid in [
        _commitment(offsetMinutes: 0),
        _commitment(wallClock: '2026-09-01T10:00:00'),
      ]) {
        final directory = _tempCore('bad_provenance');
        final clock = _Clock();
        final server = await _server(directory, clock);
        final created = await _request(
          server.endpoint!,
          'POST',
          '/v1/commitments',
          body: invalid,
        );
        expect(created['status'], HttpStatus.badRequest, reason: '$invalid');
        await server.stop();
      }
    });
  });

  test('scheduled commitment source contains no literal NUL bytes', () {
    final bytes = File('lib/services/core/kai_scheduled_commitment.dart')
        .readAsBytesSync();
    expect(bytes, isNot(contains(0)),
        reason:
            'source must remain text; use an escaped or length-prefixed delimiter');
  });
}
