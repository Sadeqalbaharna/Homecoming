import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/services/core/kai_graceful_shutdown_service.dart';

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('kai_graceful_shutdown_');
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('publishes a per-run capability on a loopback-only random port',
      () async {
    final service = KaiGracefulShutdownService(
      directory: temp,
      processId: 4100,
      executablePath: r'C:\accepted\Kai.exe',
      random: Random(7),
      onDrain: () async {},
      onNativeExit: () async {},
      hardenCapabilityFile: (_) async {},
      audit: _noAudit,
    );

    await service.start();
    final endpoint = service.endpoint!;
    final control = jsonDecode(await service.controlFile.readAsString())
        as Map<String, dynamic>;

    expect(endpoint.host, '127.0.0.1');
    expect(endpoint.port, greaterThan(0));
    expect(control['port'], endpoint.port);
    expect(control['pid'], 4100);
    expect(control['runId'], hasLength(48));
    expect(control['capability'], hasLength(64));
    expect(control['executablePath'], r'C:\accepted\Kai.exe');

    await service.stopWithoutExit();
    expect(await service.controlFile.exists(), isFalse);
  });

  test('wrong capability, run, and pid fail closed without draining', () async {
    var drains = 0;
    final audits = <Map<String, Object?>>[];
    final service = KaiGracefulShutdownService(
      directory: temp,
      processId: 4200,
      executablePath: r'C:\accepted\Kai.exe',
      random: Random(8),
      onDrain: () async => drains++,
      onNativeExit: () async {},
      hardenCapabilityFile: (_) async {},
      audit: (event, {severity = 'info', details = const {}}) async {
        audits.add({'event': event, 'severity': severity, ...details});
      },
    );
    await service.start();
    final control = jsonDecode(await service.controlFile.readAsString())
        as Map<String, dynamic>;

    expect(
      (await _post(service.endpoint!, 'wrong', control['runId'], 4200))
          .statusCode,
      HttpStatus.forbidden,
    );
    expect(
      (await _post(
        service.endpoint!,
        control['capability'],
        'wrong-run',
        4200,
      ))
          .statusCode,
      HttpStatus.forbidden,
    );
    expect(
      (await _post(
        service.endpoint!,
        control['capability'],
        control['runId'],
        9999,
      ))
          .statusCode,
      HttpStatus.forbidden,
    );

    expect(drains, 0);
    expect(service.state, KaiGracefulShutdownState.idle);
    expect(
        audits.where(
            (item) => item['event'] == 'graceful_shutdown_request_refused'),
        hasLength(3));
    expect(jsonEncode(audits), isNot(contains(control['capability'])));
    await service.stopWithoutExit();
  });

  test('accepted duplicates share one drain and exit after durable flush',
      () async {
    final releaseDrain = Completer<void>();
    final nativeExit = Completer<void>();
    var drains = 0;
    var exits = 0;
    final events = <String>[];
    final service = KaiGracefulShutdownService(
      directory: temp,
      processId: 4300,
      executablePath: r'C:\accepted\Kai.exe',
      random: Random(9),
      onDrain: () async {
        drains++;
        await releaseDrain.future;
      },
      onNativeExit: () async {
        exits++;
        nativeExit.complete();
      },
      hardenCapabilityFile: (_) async {},
      audit: (event, {severity = 'info', details = const {}}) async {
        events.add(event);
      },
    );
    await service.start();
    final control = jsonDecode(await service.controlFile.readAsString())
        as Map<String, dynamic>;

    final first = await _post(
      service.endpoint!,
      control['capability'],
      control['runId'],
      4300,
    );
    final second = await _post(
      service.endpoint!,
      control['capability'],
      control['runId'],
      4300,
    );
    expect(first.statusCode, HttpStatus.accepted);
    expect(second.statusCode, HttpStatus.accepted);
    expect(drains, 1);
    expect(exits, 0);
    expect(
        events.where((event) => event == 'graceful_shutdown_request_accepted'),
        hasLength(1));

    releaseDrain.complete();
    await nativeExit.future.timeout(const Duration(seconds: 2));
    expect(exits, 1);
    expect(service.state, KaiGracefulShutdownState.exiting);
    expect(await service.controlFile.exists(), isFalse);
    expect(
        events,
        containsAllInOrder([
          'graceful_shutdown_request_accepted',
          'graceful_shutdown_teardown_started',
          'graceful_shutdown_durable_flush_completed',
        ]));
  });

  test('ACL failure leaves no capability file or reusable service', () async {
    final service = KaiGracefulShutdownService(
      directory: temp,
      processId: 4400,
      executablePath: r'C:\accepted\Kai.exe',
      random: Random(10),
      onDrain: () async {},
      onNativeExit: () async {},
      hardenCapabilityFile: (_) async => throw StateError('acl failed'),
      audit: _noAudit,
    );

    await expectLater(service.start(), throwsStateError);
    expect(await service.controlFile.exists(), isFalse);
    expect(await File('${service.controlFile.path}.tmp').exists(), isFalse);
    await expectLater(service.start(), throwsStateError);
  });

  test('default Windows hardening removes inherited broad grants', () async {
    if (!Platform.isWindows) return;
    final service = KaiGracefulShutdownService(
      directory: temp,
      processId: 4500,
      executablePath: r'C:\accepted\Kai.exe',
      random: Random(11),
      onDrain: () async {},
      onNativeExit: () async {},
      audit: _noAudit,
    );

    await service.start();
    final result = await Process.run(
      r'C:\Windows\System32\icacls.exe',
      [service.controlFile.path],
    );
    expect(
      result.exitCode,
      0,
      reason: 'stdout=${result.stdout} stderr=${result.stderr}',
    );
    final acl = result.stdout.toString();
    expect(acl, contains(':(F)'));
    expect(acl, isNot(contains('(I)')));
    expect(acl, isNot(contains('Everyone:')));
    expect(acl, isNot(contains('BUILTIN\\Users:')));
    expect(acl, isNot(contains('Authenticated Users:')));
    await service.stopWithoutExit();
  });
}

Future<void> _noAudit(
  String event, {
  String severity = 'info',
  Map<String, Object?> details = const {},
}) async {}

Future<_Response> _post(
  Uri endpoint,
  String capability,
  String runId,
  int pid,
) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(endpoint.resolve('/v1/shutdown'));
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $capability');
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode({'runId': runId, 'pid': pid}));
    final response = await request.close();
    final body = await utf8.decoder.bind(response).join();
    return _Response(response.statusCode, body);
  } finally {
    client.close(force: true);
  }
}

class _Response {
  const _Response(this.statusCode, this.body);

  final int statusCode;
  final String body;
}
