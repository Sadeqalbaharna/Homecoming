import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/services/core/kai_core_server.dart';

Directory _tempCore(String name) {
  final dir = Directory.systemTemp.createTempSync('kai_inbox_$name');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  return dir;
}

final _dueUtc = DateTime.utc(2026, 9, 1, 6);
final _afterDue = DateTime.utc(2026, 9, 1, 7);
final _beforeDue = DateTime.utc(2026, 8, 8, 12);

/// A mutable clock. A commitment must be CREATED before its due instant —
/// Core rejects a past one — so every test schedules at [_beforeDue] and then
/// advances time rather than starting after due.
class _Clock {
  DateTime now = _beforeDue;
  DateTime call() => now;
}

Future<KaiCoreServer> _server(Directory dir, _Clock clock) async {
  final server = KaiCoreServer(dataDirectory: dir, port: 0, clock: clock.call);
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
    final request = method == 'GET'
        ? await client.getUrl(endpoint.resolve(path))
        : await client.postUrl(endpoint.resolve(path));
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

const _commitmentId = 'commit-abc';
const _outboundId = 'commit-abc-outbound';
const _desktopBody = 'desktop-body-1';

Future<void> _schedule(Uri endpoint) =>
    _send(endpoint, 'POST', '/v1/commitments', {
      'commitmentId': _commitmentId,
      'personaId': 'truekai',
      'text': 'chase the invoice',
      'dueAt': _dueUtc.toIso8601String(),
      'dueWallClock': '2026-09-01T09:00:00',
      'dueWallOffsetMinutes': 180,
    });

Future<Map<String, dynamic>> _dispatch(
  Uri endpoint, {
  String outboundId = _outboundId,
  String bodyId = _desktopBody,
}) =>
    _send(endpoint, 'POST', '/v1/commitments/$_commitmentId/dispatch', {
      'outboundId': outboundId,
      'targetBodyId': bodyId,
      'toSurface': 'desktop',
      'conversationId': 'in_person',
    });

void main() {
  group('atomic dispatch', () {
    test('one dispatch links exactly one outbound to one exact body', () async {
      final dir = _tempCore('dispatch');
      final clock = _Clock();
      final server = await _server(dir, clock);
      await _schedule(server.endpoint!);
      clock.now = _afterDue;

      final result = await _dispatch(server.endpoint!);
      expect(result['status'], HttpStatus.ok);
      final record = result['body'] as Map<String, dynamic>;
      expect(record['status'], 'dispatched');
      expect(record['outboundId'], _outboundId);
      expect(record['targetBodyId'], _desktopBody);

      // The envelope carries the EXACT stored text — no model sat between.
      final inbox = await _send(server.endpoint!, 'GET',
          '/v1/outbound?toSurface=desktop&bodyId=$_desktopBody');
      final envelopes = (inbox['body'] as Map)['outbound'] as List;
      expect(envelopes.length, 1);
      expect((envelopes.single as Map)['text'], 'chase the invoice');
      expect((envelopes.single as Map)['commitmentId'], _commitmentId);
    });

    test('a retry mints no second outbound', () async {
      final dir = _tempCore('retry');
      final clock = _Clock();
      final server = await _server(dir, clock);
      await _schedule(server.endpoint!);
      clock.now = _afterDue;

      await _dispatch(server.endpoint!);
      final again = await _dispatch(server.endpoint!);
      expect(again['status'], HttpStatus.ok);

      final inbox = await _send(server.endpoint!, 'GET',
          '/v1/outbound?toSurface=desktop&bodyId=$_desktopBody');
      expect(((inbox['body'] as Map)['outbound'] as List).length, 1,
          reason: 'a coordinator retry must not promise twice');
    });

    test('a different envelope for an already-dispatched promise conflicts',
        () async {
      final dir = _tempCore('conflict');
      final clock = _Clock();
      final server = await _server(dir, clock);
      await _schedule(server.endpoint!);
      clock.now = _afterDue;
      await _dispatch(server.endpoint!);

      final other =
          await _dispatch(server.endpoint!, outboundId: 'a-different-envelope');
      expect(other['status'], HttpStatus.conflict);
    });

    test('dispatch survives restart without producing a second outbound',
        () async {
      final dir = _tempCore('restart_dispatch');
      final clock = _Clock();
      final first = await _server(dir, clock);
      await _schedule(first.endpoint!);
      clock.now = _afterDue;
      await _dispatch(first.endpoint!);
      await first.stop();

      final second = await _server(dir, clock);
      final listed = await _send(second.endpoint!, 'GET', '/v1/commitments');
      final record =
          ((listed['body'] as Map)['commitments'] as List).single as Map;
      expect(record['status'], 'dispatched');
      expect(record['outboundId'], _outboundId);

      await _dispatch(second.endpoint!);
      final inbox = await _send(second.endpoint!, 'GET',
          '/v1/outbound?toSurface=desktop&bodyId=$_desktopBody');
      expect(((inbox['body'] as Map)['outbound'] as List).length, 1);
    });
  });

  group('target-scoped acknowledgement', () {
    test('the wrong body cannot acknowledge', () async {
      final dir = _tempCore('wrong_body');
      final clock = _Clock();
      final server = await _server(dir, clock);
      await _schedule(server.endpoint!);
      clock.now = _afterDue;
      await _dispatch(server.endpoint!);

      final wrong = await _send(
        server.endpoint!,
        'POST',
        '/v1/outbound/$_outboundId/ack',
        {'bodyId': 'some-other-body', 'surface': 'desktop'},
      );
      expect(wrong['status'], HttpStatus.conflict);

      final listed = await _send(server.endpoint!, 'GET', '/v1/commitments');
      final record =
          ((listed['body'] as Map)['commitments'] as List).single as Map;
      expect(record['status'], 'dispatched',
          reason: 'the promise is still owed');
    });

    test('the wrong surface cannot acknowledge', () async {
      final dir = _tempCore('wrong_surface');
      final clock = _Clock();
      final server = await _server(dir, clock);
      await _schedule(server.endpoint!);
      clock.now = _afterDue;
      await _dispatch(server.endpoint!);

      final wrong = await _send(
        server.endpoint!,
        'POST',
        '/v1/outbound/$_outboundId/ack',
        {'bodyId': _desktopBody, 'surface': 'messenger'},
      );
      expect(wrong['status'], HttpStatus.conflict);
    });

    test('the target body closes both records in one write', () async {
      final dir = _tempCore('ack');
      final clock = _Clock();
      final server = await _server(dir, clock);
      await _schedule(server.endpoint!);
      clock.now = _afterDue;
      await _dispatch(server.endpoint!);

      final ack = await _send(
        server.endpoint!,
        'POST',
        '/v1/outbound/$_outboundId/ack',
        {'bodyId': _desktopBody, 'surface': 'desktop'},
      );
      expect(ack['status'], HttpStatus.ok);
      expect((ack['body'] as Map)['status'], 'acknowledged');

      final listed = await _send(server.endpoint!, 'GET', '/v1/commitments');
      final record =
          ((listed['body'] as Map)['commitments'] as List).single as Map;
      expect(record['status'], 'acknowledged');
      expect(record['acknowledgedAt'], isNotNull);
    });

    test('after acknowledgement nothing is due and the inbox is empty',
        () async {
      final dir = _tempCore('terminal');
      final clock = _Clock();
      final server = await _server(dir, clock);
      await _schedule(server.endpoint!);
      clock.now = _afterDue;
      await _dispatch(server.endpoint!);
      await _send(server.endpoint!, 'POST', '/v1/outbound/$_outboundId/ack',
          {'bodyId': _desktopBody, 'surface': 'desktop'});

      final due =
          await _send(server.endpoint!, 'GET', '/v1/commitments?due=true');
      expect((due['body'] as Map)['commitments'], isEmpty);

      final inbox = await _send(server.endpoint!, 'GET',
          '/v1/outbound?toSurface=desktop&bodyId=$_desktopBody');
      expect((inbox['body'] as Map)['outbound'], isEmpty);
    });

    test('an acknowledged promise cannot be re-dispatched', () async {
      final dir = _tempCore('no_redispatch');
      final clock = _Clock();
      final server = await _server(dir, clock);
      await _schedule(server.endpoint!);
      clock.now = _afterDue;
      await _dispatch(server.endpoint!);
      await _send(server.endpoint!, 'POST', '/v1/outbound/$_outboundId/ack',
          {'bodyId': _desktopBody, 'surface': 'desktop'});

      final again = await _dispatch(server.endpoint!);
      expect(again['status'], HttpStatus.conflict);
      expect(
          (again['body'] as Map)['error'], 'commitment_already_acknowledged');
    });

    test('terminal state survives restart', () async {
      final dir = _tempCore('terminal_restart');
      final clock = _Clock();
      final first = await _server(dir, clock);
      await _schedule(first.endpoint!);
      clock.now = _afterDue;
      await _dispatch(first.endpoint!);
      await _send(first.endpoint!, 'POST', '/v1/outbound/$_outboundId/ack',
          {'bodyId': _desktopBody, 'surface': 'desktop'});
      await first.stop();

      final second = await _server(dir, clock);
      final due =
          await _send(second.endpoint!, 'GET', '/v1/commitments?due=true');
      expect((due['body'] as Map)['commitments'], isEmpty,
          reason: 'another evaluation produces no work');
    });
  });

  group('nothing before its time', () {
    test('a scheduled commitment produces no outbound before due', () async {
      final dir = _tempCore('not_yet');
      final clock = _Clock();
      final server = await _server(dir, clock);
      await _schedule(server.endpoint!);
      // Deliberately NOT advanced — this test is about the pre-due window.

      final due =
          await _send(server.endpoint!, 'GET', '/v1/commitments?due=true');
      expect((due['body'] as Map)['commitments'], isEmpty);

      final inbox = await _send(server.endpoint!, 'GET',
          '/v1/outbound?toSurface=desktop&bodyId=$_desktopBody');
      expect((inbox['body'] as Map)['outbound'], isEmpty);
    });
  });
}
