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
      Directory.systemTemp.createTempSync('kai_commit_followup_$name');
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
  addTearDown(() async {
    try {
      await server.stop();
    } catch (_) {
      // A test deliberately poisons the pre-repair write tail. The behavioral
      // assertion reports that failure; teardown must still release the port.
    }
  });
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
      'PUT' => await client.putUrl(uri),
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

Map<String, Object?> _commitment(
  String id, {
  String wallClock = '2026-09-01T09:00:00',
  DateTime? dueAt,
}) =>
    {
      'commitmentId': id,
      'personaId': 'truekai',
      'text': 'chase the invoice',
      'dueAt': (dueAt ?? _dueAt).toIso8601String(),
      'dueWallClock': wallClock,
      'dueWallOffsetMinutes': 180,
    };

Map<String, dynamic> _state({
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
        'commit-survivor': {
          'commitmentId': 'commit-survivor',
          'personaId': 'truekai',
          'text': 'survive every retry',
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

File _primary(Directory directory) =>
    File('${directory.path}${Platform.pathSeparator}state.json');

Future<void> _schedule(Uri endpoint, String id) async {
  final created = await _request(
    endpoint,
    'POST',
    '/v1/commitments',
    body: _commitment(id),
  );
  expect(created['status'], HttpStatus.created);
}

void main() {
  test('all Brief 013 Dart sources remain ordinary text without NUL bytes', () {
    for (final path in [
      'lib/services/core/kai_core_server.dart',
      'lib/services/core/kai_scheduled_commitment.dart',
      'test/kai_core_recovery_regression_test.dart',
    ]) {
      expect(File(path).readAsBytesSync(), isNot(contains(0)), reason: path);
    }
  });

  test('idempotent redispatch includes conversation identity', () async {
    final directory = _tempCore('conversation_identity');
    final clock = _Clock();
    final server = await _server(directory, clock);
    await _schedule(server.endpoint!, 'commit-conversation');
    clock.now = _afterDue;

    final first = await _request(
      server.endpoint!,
      'POST',
      '/v1/commitments/commit-conversation/dispatch',
      body: {
        'outboundId': 'commit-conversation-outbound',
        'targetBodyId': 'desktop-body-1',
        'toSurface': 'desktop',
        'conversationId': 'in_person',
      },
    );
    expect(first['status'], HttpStatus.ok);

    final changed = await _request(
      server.endpoint!,
      'POST',
      '/v1/commitments/commit-conversation/dispatch',
      body: {
        'outboundId': 'commit-conversation-outbound',
        'targetBodyId': 'desktop-body-1',
        'toSurface': 'desktop',
        'conversationId': 'some_other_conversation',
      },
    );
    expect(changed['status'], HttpStatus.conflict,
        reason: 'changed conversation is not the same envelope');
  });

  test('a corrupt backup is quarantined even when the primary is readable',
      () async {
    final directory = _tempCore('corrupt_backup');
    final primary = _primary(directory)
      ..writeAsStringSync(jsonEncode(_state()), flush: true);
    final backup = File('${primary.path}.bak');
    final corruptBytes = <int>[0, 255, 1, 2, 3, 125];
    backup.writeAsBytesSync(corruptBytes, flush: true);

    final server = await _server(directory, _Clock());
    await _schedule(server.endpoint!, 'commit-new');
    await server.stop();

    final quarantine = File('${backup.path}.corrupt');
    expect(quarantine.existsSync(), isTrue);
    expect(quarantine.readAsBytesSync(), corruptBytes,
        reason: 'unreadable backup bytes are diagnostic evidence');
    expect(jsonDecode(backup.readAsStringSync()), isA<Map>(),
        reason: 'normal rotation may install the old readable primary here');
  });

  test('quarantine remains collision-safe beyond suffix 999', () async {
    final directory = _tempCore('quarantine_unbounded');
    final primary = _primary(directory);
    final corruptBytes = utf8.encode('incident one thousand');
    primary.writeAsBytesSync(corruptBytes, flush: true);
    File('${primary.path}.bak')
        .writeAsStringSync(jsonEncode(_state()), flush: true);

    File('${primary.path}.corrupt').writeAsStringSync('existing base');
    for (var i = 1; i <= 999; i++) {
      File('${primary.path}.corrupt.$i').writeAsStringSync('existing $i');
    }

    final server = await _server(directory, _Clock());
    final created = await _request(
      server.endpoint!,
      'POST',
      '/v1/commitments',
      body: _commitment('commit-new'),
    );
    expect(created['status'], HttpStatus.created);
    expect(File('${primary.path}.corrupt.1000').readAsBytesSync(), corruptBytes);
    expect(File('${primary.path}.corrupt.999').readAsStringSync(),
        'existing 999');
  });

  test('non-canonical or normalised Bahrain wall clocks are rejected',
      () async {
    final invalid = <MapEntry<String, DateTime>>[
      MapEntry('2026-09-01 09:00:00', _dueAt),
      MapEntry('2026-09-01T09:00', _dueAt),
      MapEntry('2026-09-01T09:00:00.000', _dueAt),
      MapEntry('2026-02-30T09:00:00', DateTime.utc(2026, 3, 2, 6)),
    ];

    for (var i = 0; i < invalid.length; i++) {
      final directory = _tempCore('canonical_wall_$i');
      final server = await _server(directory, _Clock());
      final created = await _request(
        server.endpoint!,
        'POST',
        '/v1/commitments',
        body: _commitment(
          'commit-wall-$i',
          wallClock: invalid[i].key,
          dueAt: invalid[i].value,
        ),
      );
      expect(created['status'], HttpStatus.badRequest,
          reason: invalid[i].key);
      await server.stop();
    }
  });

  test('unsupported future ledger survives an unrelated Core write',
      () async {
    final directory = _tempCore('future_ledger_write');
    final state = _state(ledgerVersion: 999);
    (state['commitments'] as Map)['future-only'] = {
      'commitmentId': 'future-only',
      'futureField': {'nested': true},
    };
    _primary(directory).writeAsStringSync(jsonEncode(state), flush: true);

    final server = await _server(directory, _Clock());
    final heartbeat = await _request(
      server.endpoint!,
      'PUT',
      '/v1/presence/device-future',
      body: {
        'surface': 'desktop',
        'sessionId': 'future-session',
        'foreground': true,
        'audioAvailable': false,
      },
    );
    expect(heartbeat['status'], HttpStatus.ok);
    await server.stop();

    final onDisk = jsonDecode(_primary(directory).readAsStringSync()) as Map;
    expect(onDisk['commitmentLedgerVersion'], 999);
    expect(((onDisk['commitments'] as Map)['future-only'] as Map)['futureField'],
        {'nested': true});
  });

  test('a transient failed recovery save does not poison later writes',
      () async {
    final directory = _tempCore('write_tail_retry');
    final primary = _primary(directory);
    final backup = File('${primary.path}.bak')
      ..writeAsStringSync(jsonEncode(_state()), flush: true);
    final tempBlocker = Directory('${primary.path}.tmp')..createSync();

    final server = await _server(directory, _Clock());
    final first = await _request(
      server.endpoint!,
      'POST',
      '/v1/commitments',
      body: _commitment('commit-first'),
    );
    expect(first['status'], HttpStatus.internalServerError);
    expect(backup.existsSync(), isTrue);
    expect(jsonDecode(backup.readAsStringSync()), isA<Map>());

    tempBlocker.deleteSync();
    final second = await _request(
      server.endpoint!,
      'POST',
      '/v1/commitments',
      body: _commitment('commit-second'),
    );
    expect(second['status'], HttpStatus.created,
        reason: 'one failed write must not permanently poison the save chain');
    await server.stop();

    final commitments =
        (jsonDecode(primary.readAsStringSync()) as Map)['commitments'] as Map;
    expect(commitments.keys,
        containsAll(['commit-survivor', 'commit-first', 'commit-second']));
  });

  group('an identical retry repairs a failed durable transition', () {
    test('commitment creation retry makes the promise durable', () async {
      final directory = _tempCore('retry_create_durable');
      final server = await _server(directory, _Clock());
      final tempBlocker = Directory('${_primary(directory).path}.tmp')
        ..createSync();

      final first = await _request(
        server.endpoint!,
        'POST',
        '/v1/commitments',
        body: _commitment('commit-retry-create'),
      );
      expect(first['status'], HttpStatus.internalServerError);

      tempBlocker.deleteSync();
      final retry = await _request(
        server.endpoint!,
        'POST',
        '/v1/commitments',
        body: _commitment('commit-retry-create'),
      );
      expect(retry['status'], HttpStatus.ok);
      await server.stop();

      final persisted = jsonDecode(_primary(directory).readAsStringSync()) as Map;
      expect((persisted['commitments'] as Map).keys,
          contains('commit-retry-create'));
    });

    test('commitment dispatch retry makes envelope and transition durable',
        () async {
      final directory = _tempCore('retry_dispatch_durable');
      final clock = _Clock();
      final server = await _server(directory, clock);
      await _schedule(server.endpoint!, 'commit-retry-dispatch');
      clock.now = _afterDue;
      final body = <String, Object?>{
        'outboundId': 'commit-retry-dispatch-outbound',
        'targetBodyId': 'desktop-body-1',
        'toSurface': 'desktop',
        'conversationId': 'in_person',
      };
      final tempBlocker = Directory('${_primary(directory).path}.tmp')
        ..createSync();

      final first = await _request(
        server.endpoint!,
        'POST',
        '/v1/commitments/commit-retry-dispatch/dispatch',
        body: body,
      );
      expect(first['status'], HttpStatus.internalServerError);

      tempBlocker.deleteSync();
      final retry = await _request(
        server.endpoint!,
        'POST',
        '/v1/commitments/commit-retry-dispatch/dispatch',
        body: body,
      );
      expect(retry['status'], HttpStatus.ok);
      await server.stop();

      final persisted = jsonDecode(_primary(directory).readAsStringSync()) as Map;
      expect(
          ((persisted['commitments'] as Map)['commit-retry-dispatch']
              as Map)['status'],
          'dispatched');
      expect((persisted['outbound'] as Map).keys,
          contains('commit-retry-dispatch-outbound'));
    });

    test('outbound acknowledgement retry durably closes the promise',
        () async {
      final directory = _tempCore('retry_ack_durable');
      final clock = _Clock();
      final server = await _server(directory, clock);
      await _schedule(server.endpoint!, 'commit-retry-ack');
      clock.now = _afterDue;
      final dispatched = await _request(
        server.endpoint!,
        'POST',
        '/v1/commitments/commit-retry-ack/dispatch',
        body: {
          'outboundId': 'commit-retry-ack-outbound',
          'targetBodyId': 'desktop-body-1',
          'toSurface': 'desktop',
          'conversationId': 'in_person',
        },
      );
      expect(dispatched['status'], HttpStatus.ok);
      final ackBody = <String, Object?>{
        'bodyId': 'desktop-body-1',
        'surface': 'desktop',
      };
      final tempBlocker = Directory('${_primary(directory).path}.tmp')
        ..createSync();

      final first = await _request(
        server.endpoint!,
        'POST',
        '/v1/outbound/commit-retry-ack-outbound/ack',
        body: ackBody,
      );
      expect(first['status'], HttpStatus.internalServerError);

      tempBlocker.deleteSync();
      final retry = await _request(
        server.endpoint!,
        'POST',
        '/v1/outbound/commit-retry-ack-outbound/ack',
        body: ackBody,
      );
      expect(retry['status'], HttpStatus.ok);
      await server.stop();

      final persisted = jsonDecode(_primary(directory).readAsStringSync()) as Map;
      expect(
          ((persisted['commitments'] as Map)['commit-retry-ack'] as Map)
              ['status'],
          'acknowledged');
      expect(
          ((persisted['outbound'] as Map)['commit-retry-ack-outbound'] as Map)
              ['status'],
          'acknowledged');
    });
  });
}
