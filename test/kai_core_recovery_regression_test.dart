// Brief 013 regressions for Kai Core's degraded-startup path.
//
// Every test here runs against a throwaway directory under the system temp
// root. Nothing in this file may read, write, rename or delete anything under
// %LOCALAPPDATA%\Homecoming\KaiCore — Sadeq's real Core state is not a fixture.
//
// Two properties are pinned:
//
//   1. A degraded load never destroys evidence. The bytes that could not be
//      parsed are moved sideways under a collision-safe name, the last
//      READABLE copy is left in place until the new primary lands, and a
//      second incident does not overwrite the first one's evidence.
//   2. The commitment expiry exemption is narrow. A promise survives the
//      24-hour sweep; an ordinary outbound still expires exactly as before.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/services/core/kai_core_server.dart';

final _now = DateTime.utc(2026, 8, 8, 12);
final _dueAt = DateTime.utc(2026, 9, 1, 6);
final _afterDue = DateTime.utc(2026, 9, 1, 7);

class _Clock {
  DateTime now = _now;
  DateTime call() => now;
}

Directory _tempCore(String name) {
  final directory = Directory.systemTemp.createTempSync('kai_core_reg_$name');
  addTearDown(() {
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });
  return directory;
}

/// Corrupt state bytes, constructed at runtime and labelled per incident.
///
/// Deliberately NOT a string literal in this file. It carries 0x00 and 0xFF,
/// which are not valid UTF-8 text — pasting them into a .dart source makes the
/// source itself a binary file, which is the exact defect this fixture exists
/// to test around. The label lets one test distinguish two incidents.
List<int> _corruptFixture(String label) => <int>[
      0x7b, 0x20, // "{ " — plausible enough to look like a torn write
      0x00, 0xff, 0xfe, 0x01,
      ...utf8.encode(label),
      0x00,
    ];

File _primaryIn(Directory directory) =>
    File('${directory.path}${Platform.pathSeparator}state.json');

Future<KaiCoreServer> _server(Directory directory, _Clock clock) async {
  final server =
      KaiCoreServer(dataDirectory: directory, port: 0, clock: clock.call);
  await server.start();
  addTearDown(server.stop);
  return server;
}

Future<Map<String, dynamic>> _send(
  Uri endpoint,
  String method,
  String path, [
  Map<String, Object?>? body,
]) async {
  final client = HttpClient();
  try {
    final uri = endpoint.resolve(path);
    final request =
        method == 'GET' ? await client.getUrl(uri) : await client.postUrl(uri);
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

/// A full readable state carrying one record in EVERY collection, so recovery
/// is not accidentally verified on commitments alone.
String _readableState() => jsonEncode({
      'version': 2,
      'startedAt': _now.toIso8601String(),
      'presence': {
        'device-a': {
          'deviceId': 'device-a',
          'surface': 'desktop',
          'sessionId': 'session-a',
          'online': true,
          'foreground': true,
          'audioAvailable': false,
          'worldId': null,
          'gogglesOn': false,
          'lastInteractionAt': null,
          'lastHeartbeatAt': _now.toIso8601String(),
          'leaseExpiresAt':
              _now.add(const Duration(days: 400)).toIso8601String(),
        },
      },
      'handoffs': {
        'handoff-a': {
          'handoffId': 'handoff-a',
          'purpose': 'thread_continuation',
          'fromSurface': 'desktop',
          'toSurface': 'mobile',
          'conversationId': 'in_person',
          'summary': 'carried across',
          'createdAt': _now.toIso8601String(),
          'expiresAt': _now.add(const Duration(days: 400)).toIso8601String(),
          'status': 'pending',
          'acknowledgedAt': null,
        },
      },
      'outbound': <String, dynamic>{},
      'tasks': {
        'task-a': {
          'taskId': 'task-a',
          'status': 'queued',
          'createdAt': _now.toIso8601String(),
        },
      },
      'commitmentLedgerVersion': 1,
      'commitments': {
        'commit-survivor': {
          'commitmentId': 'commit-survivor',
          'personaId': 'truekai',
          'text': 'survive the crash window',
          'dueAt': _dueAt.toIso8601String(),
          'dueWallClock': '2026-09-01T09:00:00',
          'dueWallOffsetMinutes': 180,
          'audience': 'work',
          'createdAt': _now.toIso8601String(),
          'status': 'scheduled',
          'nextEvaluationAt': _dueAt.toIso8601String(),
          'outboundId': null,
          'targetBodyId': null,
          'dispatchedAt': null,
          'acknowledgedAt': null,
        },
      },
    });

Future<void> _schedule(Uri endpoint, String id) async {
  final result = await _send(endpoint, 'POST', '/v1/commitments', {
    'commitmentId': id,
    'personaId': 'truekai',
    'text': 'chase the invoice',
    'dueAt': _dueAt.toIso8601String(),
    'dueWallClock': '2026-09-01T09:00:00',
    'dueWallOffsetMinutes': 180,
  });
  expect(result['status'], HttpStatus.created);
}

void main() {
  test('/health advertises the scheduled-commitment capability', () async {
    final server = await _server(_tempCore('health'), _Clock());
    final health = await _send(server.endpoint!, 'GET', '/health');
    expect((health['body'] as Map)['capabilities'],
        contains('scheduled_commitments'));
  });

  group('degraded startup keeps evidence', () {
    test('backup-only startup restores every collection, not just commitments',
        () async {
      final directory = _tempCore('backup_only_all');
      final backup = File('${_primaryIn(directory).path}.bak')
        ..writeAsStringSync(_readableState(), flush: true);

      final server = await _server(directory, _Clock());
      final presence = await _send(server.endpoint!, 'GET', '/v1/presence');
      expect(
        ((presence['body'] as Map)['devices'] as List)
            .map((item) => (item as Map)['deviceId']),
        contains('device-a'),
      );
      final handoffs =
          await _send(server.endpoint!, 'GET', '/v1/handoffs?toSurface=mobile');
      expect(((handoffs['body'] as Map)['handoffs'] as List), isNotEmpty);
      final tasks = await _send(server.endpoint!, 'GET', '/v1/tasks');
      expect(((tasks['body'] as Map)['tasks'] as List), isNotEmpty);

      await _schedule(server.endpoint!, 'commit-new');
      await server.stop();

      // The readable backup was never the thing deleted to make room.
      expect(backup.existsSync(), isTrue);
      expect(jsonDecode(backup.readAsStringSync()), isA<Map>());
      final primary = jsonDecode(_primaryIn(directory).readAsStringSync())
          as Map<String, dynamic>;
      expect((primary['commitments'] as Map).keys,
          containsAll(['commit-survivor', 'commit-new']));
      expect((primary['presence'] as Map).keys, contains('device-a'));
      expect((primary['tasks'] as Map).keys, contains('task-a'));
    });

    test('corrupt primary is quarantined byte-for-byte, backup untouched',
        () async {
      final directory = _tempCore('quarantine');
      // Built at runtime, never typed into this source. Real corruption is a
      // truncated write or a torn sector, so the fixture includes bytes that
      // are not valid UTF-8 (0x00, 0xFF) - and embedding those in a .dart file
      // makes the file itself binary to editors, diffs and tooling.
      final corruptBytes = _corruptFixture('primary');
      final primary = _primaryIn(directory)
        ..writeAsBytesSync(corruptBytes, flush: true);
      final backup = File('${primary.path}.bak')
        ..writeAsStringSync(_readableState(), flush: true);

      final server = await _server(directory, _Clock());
      await _schedule(server.endpoint!, 'commit-new');
      await server.stop();

      final quarantined = File('${primary.path}.corrupt');
      expect(quarantined.existsSync(), isTrue,
          reason: 'unparseable bytes are evidence, not rubbish');
      expect(quarantined.readAsBytesSync(), corruptBytes,
          reason: 'quarantine copies exactly; it does not sanitise');
      expect(jsonDecode(primary.readAsStringSync()), isA<Map>());
      expect(jsonDecode(backup.readAsStringSync()), isA<Map>(),
          reason: 'the readable backup must survive the first save');
    });

    test('a second incident does not overwrite the first quarantine', () async {
      final directory = _tempCore('quarantine_twice');
      final firstBytes = _corruptFixture('first incident');
      final secondBytes = _corruptFixture('second incident');
      final primary = _primaryIn(directory)
        ..writeAsBytesSync(firstBytes, flush: true);
      File('${primary.path}.bak')
          .writeAsStringSync(_readableState(), flush: true);

      final first = await _server(directory, _Clock());
      await _schedule(first.endpoint!, 'commit-one');
      await first.stop();

      // Corrupt it again. Same directory, same names — the collision case.
      primary.writeAsBytesSync(secondBytes, flush: true);
      final second = await _server(directory, _Clock());
      await _schedule(second.endpoint!, 'commit-two');
      await second.stop();

      expect(File('${primary.path}.corrupt').readAsBytesSync(), firstBytes);
      expect(File('${primary.path}.corrupt.1').readAsBytesSync(), secondBytes,
          reason: 'a later incident takes the next free index');
    });

    test('a retry that still cannot persist still reports failure', () async {
      // The other half of the durability rule. Making a retry repair the disk
      // is only safe if a retry that CANNOT repair it keeps saying so — an
      // idempotent 200 handed back while the disk is still broken is exactly
      // the silent loss the repair exists to prevent, just moved one attempt
      // later.
      final directory = _tempCore('retry_still_failing');
      final server = await _server(directory, _Clock());
      final blocker = Directory('${_primaryIn(directory).path}.tmp')
        ..createSync();

      final first = await _send(server.endpoint!, 'POST', '/v1/commitments', {
        'commitmentId': 'commit-stubborn',
        'personaId': 'truekai',
        'text': 'chase the invoice',
        'dueAt': _dueAt.toIso8601String(),
        'dueWallClock': '2026-09-01T09:00:00',
        'dueWallOffsetMinutes': 180,
      });
      expect(first['status'], HttpStatus.internalServerError);

      // Blocker still in place: the identical retry must NOT claim success.
      final stillBroken =
          await _send(server.endpoint!, 'POST', '/v1/commitments', {
        'commitmentId': 'commit-stubborn',
        'personaId': 'truekai',
        'text': 'chase the invoice',
        'dueAt': _dueAt.toIso8601String(),
        'dueWallClock': '2026-09-01T09:00:00',
        'dueWallOffsetMinutes': 180,
      });
      expect(stillBroken['status'], HttpStatus.internalServerError,
          reason: 'the promise is still not on disk; saying 200 would lie');

      blocker.deleteSync();
      final recovered =
          await _send(server.endpoint!, 'POST', '/v1/commitments', {
        'commitmentId': 'commit-stubborn',
        'personaId': 'truekai',
        'text': 'chase the invoice',
        'dueAt': _dueAt.toIso8601String(),
        'dueWallClock': '2026-09-01T09:00:00',
        'dueWallOffsetMinutes': 180,
      });
      expect(recovered['status'], HttpStatus.ok);
      await server.stop();

      // Exactly one record — repair re-persists, it does not re-create.
      final commitments = (jsonDecode(_primaryIn(directory).readAsStringSync())
          as Map)['commitments'] as Map;
      expect(commitments.keys, ['commit-stubborn']);
      expect((commitments['commit-stubborn'] as Map)['status'], 'scheduled');
    });

    test('a healthy load rotates normally and mints no quarantine', () async {
      final directory = _tempCore('healthy');
      final clock = _Clock();
      final first = await _server(directory, clock);
      await _schedule(first.endpoint!, 'commit-one');
      await first.stop();

      final second = await _server(directory, clock);
      await _schedule(second.endpoint!, 'commit-two');
      await second.stop();

      final primary = _primaryIn(directory);
      expect(File('${primary.path}.corrupt').existsSync(), isFalse);
      expect(File('${primary.path}.bak').existsSync(), isTrue);
      expect(
        ((jsonDecode(primary.readAsStringSync()) as Map)['commitments'] as Map)
            .keys,
        containsAll(['commit-one', 'commit-two']),
      );
    });
  });

  group('the expiry exemption is narrow', () {
    test('an ordinary outbound still expires on the 24-hour sweep', () async {
      final directory = _tempCore('ordinary_expiry');
      final clock = _Clock();
      final server = await _server(directory, clock);

      final created = await _send(server.endpoint!, 'POST', '/v1/outbound', {
        'outboundId': 'ordinary-1',
        'kind': 'proactive_friend',
        'fromSurface': 'central',
        'toSurface': 'desktop',
        'targetBodyId': 'desktop-body-1',
        'conversationId': 'in_person',
        'correlationId': 'ordinary',
        'text': 'thought you might want to see this',
        'expiresAt': _now.add(const Duration(hours: 2)).toIso8601String(),
      });
      expect(created['status'], HttpStatus.created);

      const inboxPath = '/v1/outbound?toSurface=desktop&bodyId=desktop-body-1';
      final before = await _send(server.endpoint!, 'GET', inboxPath);
      expect(((before['body'] as Map)['outbound'] as List).length, 1);

      clock.now = _now.add(const Duration(hours: 3));
      final after = await _send(server.endpoint!, 'GET', inboxPath);
      expect((after['body'] as Map)['outbound'], isEmpty,
          reason: 'a moment that has passed is no longer worth saying');
    });

    test('a commitment outbound outlives an ordinary one in the same sweep',
        () async {
      final directory = _tempCore('mixed_sweep');
      final clock = _Clock();
      final server = await _server(directory, clock);
      await _schedule(server.endpoint!, 'commit-mixed');
      await _send(server.endpoint!, 'POST', '/v1/outbound', {
        'outboundId': 'ordinary-2',
        'kind': 'proactive_friend',
        'fromSurface': 'central',
        'toSurface': 'desktop',
        'targetBodyId': 'desktop-body-1',
        'conversationId': 'in_person',
        'correlationId': 'ordinary',
        'text': 'a passing thought',
        'expiresAt': _now.add(const Duration(hours: 2)).toIso8601String(),
      });

      clock.now = _afterDue;
      final dispatched = await _send(
        server.endpoint!,
        'POST',
        '/v1/commitments/commit-mixed/dispatch',
        {
          'outboundId': 'commit-mixed-outbound',
          'targetBodyId': 'desktop-body-1',
          'toSurface': 'desktop',
          'conversationId': 'in_person',
        },
      );
      expect(dispatched['status'], HttpStatus.ok);

      clock.now = _afterDue.add(const Duration(days: 3));
      final inbox = await _send(server.endpoint!, 'GET',
          '/v1/outbound?toSurface=desktop&bodyId=desktop-body-1');
      final records = (inbox['body'] as Map)['outbound'] as List;
      expect(records.map((item) => (item as Map)['outboundId']),
          ['commit-mixed-outbound'],
          reason: 'the promise is still owed; the passing thought is not');
    });
  });
}
