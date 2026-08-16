import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';

enum KaiGracefulShutdownState { idle, accepted, draining, flushed, exiting }

typedef KaiShutdownAudit = Future<void> Function(
  String event, {
  String severity,
  Map<String, Object?> details,
});

/// Authenticated, loopback-only control seam for a normal coordinator exit.
///
/// The per-run capability lives only in the current user's local application
/// data. It is never compiled, accepted on the command line, returned by a
/// health endpoint, or written to the operations journal.
class KaiGracefulShutdownService {
  KaiGracefulShutdownService({
    required this.onDrain,
    required this.audit,
    Directory? directory,
    Future<void> Function()? onNativeExit,
    Future<void> Function(File file)? hardenCapabilityFile,
    int? processId,
    String? executablePath,
    Random? random,
  })  : directory = directory ?? defaultDirectory(),
        _onNativeExit = onNativeExit ?? _defaultNativeExit,
        _hardenCapabilityFile =
            hardenCapabilityFile ?? _defaultHardenCapabilityFile,
        _processId = processId ?? pid,
        _executablePath = executablePath ?? Platform.resolvedExecutable,
        _random = random ?? Random.secure();

  static const _channel = MethodChannel('kai.homecoming/lifecycle');
  static const _controlFileName = 'shutdown-control.json';

  final Future<void> Function() onDrain;
  final KaiShutdownAudit audit;
  final Directory directory;
  final Future<void> Function() _onNativeExit;
  final Future<void> Function(File file) _hardenCapabilityFile;
  final int _processId;
  final String _executablePath;
  final Random _random;

  HttpServer? _server;
  String? _capability;
  String? _runId;
  Future<void>? _shutdownFuture;
  KaiGracefulShutdownState _state = KaiGracefulShutdownState.idle;

  KaiGracefulShutdownState get state => _state;
  Uri? get endpoint =>
      _server == null ? null : Uri.parse('http://127.0.0.1:${_server!.port}');
  File get controlFile => File(
        '${directory.path}${Platform.pathSeparator}$_controlFileName',
      );

  static Directory defaultDirectory() {
    final local = Platform.environment['LOCALAPPDATA'];
    final root =
        local == null || local.trim().isEmpty ? Directory.current.path : local;
    return Directory(
      '$root${Platform.pathSeparator}Homecoming${Platform.pathSeparator}'
      'KaiCore',
    );
  }

  Future<void> start() async {
    if (_server != null) return;
    if (_state != KaiGracefulShutdownState.idle) {
      throw StateError('A completed shutdown service cannot be restarted.');
    }
    await directory.create(recursive: true);
    _capability = _randomHex(32);
    _runId = _randomHex(24);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    try {
      await _writeControlFile(server.port);
    } catch (_) {
      _server = null;
      await server.close(force: true);
      await _deleteControlFile();
      _clearSecrets();
      rethrow;
    }
    server.listen(
      _handle,
      onError: (Object error, StackTrace stack) {
        unawaited(audit(
          'graceful_shutdown_listener_error',
          severity: 'warning',
          details: {'error': error},
        ));
      },
      cancelOnError: false,
    );
    await audit(
      'graceful_shutdown_listener_started',
      details: {'port': server.port, 'pid': _processId},
    );
  }

  Future<void> stopWithoutExit() async {
    final server = _server;
    _server = null;
    if (server != null) await server.close(force: true);
    await _deleteControlFile();
    _clearSecrets();
  }

  Future<void> _writeControlFile(int port) async {
    final file = controlFile;
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
      jsonEncode({
        'version': 1,
        'pid': _processId,
        'runId': _runId,
        'port': port,
        'executablePath': _executablePath,
        'capability': _capability,
      }),
      flush: true,
    );
    await _hardenCapabilityFile(temporary);
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
    await _hardenCapabilityFile(file);
  }

  Future<void> _handle(HttpRequest request) async {
    request.response.headers.contentType = ContentType.json;
    request.response.headers.set('Cache-Control', 'no-store');
    if (request.method != 'POST' || request.uri.path != '/v1/shutdown') {
      request.response.statusCode = HttpStatus.notFound;
      request.response.write(jsonEncode({'error': 'not_found'}));
      await request.response.close();
      return;
    }

    Map<String, dynamic> body;
    try {
      final decoded = jsonDecode(await utf8.decoder.bind(request).join());
      body = decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : <String, dynamic>{};
    } catch (_) {
      await _refuse(request, 'malformed_request', HttpStatus.badRequest);
      return;
    }
    final authorization =
        request.headers.value(HttpHeaders.authorizationHeader);
    final suppliedCapability = authorization?.startsWith('Bearer ') == true
        ? authorization!.substring('Bearer '.length)
        : '';
    final reason = _refusalReason(
      suppliedCapability: suppliedCapability,
      suppliedRunId: body['runId']?.toString() ?? '',
      suppliedPid: (body['pid'] as num?)?.toInt(),
    );
    if (reason != null) {
      await _refuse(request, reason, HttpStatus.forbidden);
      return;
    }

    if (_state == KaiGracefulShutdownState.idle) {
      _state = KaiGracefulShutdownState.accepted;
      await audit(
        'graceful_shutdown_request_accepted',
        details: {'pid': _processId, 'runId': _runId},
      );
    }
    request.response.statusCode = HttpStatus.accepted;
    request.response.write(jsonEncode({
      'accepted': true,
      'pid': _processId,
      'runId': _runId,
      'state': _state.name,
    }));
    await request.response.close();
    _shutdownFuture ??= _performShutdown();
  }

  String? _refusalReason({
    required String suppliedCapability,
    required String suppliedRunId,
    required int? suppliedPid,
  }) {
    if (_state == KaiGracefulShutdownState.exiting) return 'already_exiting';
    if (suppliedCapability.isEmpty || suppliedCapability != _capability) {
      return 'invalid_capability';
    }
    if (suppliedRunId.isEmpty || suppliedRunId != _runId) {
      return 'wrong_run';
    }
    if (suppliedPid == null || suppliedPid != _processId) return 'wrong_pid';
    return null;
  }

  Future<void> _refuse(
    HttpRequest request,
    String reason,
    int status,
  ) async {
    await audit(
      'graceful_shutdown_request_refused',
      severity: 'warning',
      details: {'reason': reason, 'pid': _processId},
    );
    request.response.statusCode = status;
    request.response.write(jsonEncode({'error': reason}));
    await request.response.close();
  }

  Future<void> _performShutdown() async {
    _state = KaiGracefulShutdownState.draining;
    await audit('graceful_shutdown_teardown_started',
        details: {'pid': _processId});
    try {
      await onDrain();
      _state = KaiGracefulShutdownState.flushed;
      await audit('graceful_shutdown_durable_flush_completed',
          details: {'pid': _processId});
      final server = _server;
      _server = null;
      if (server != null) await server.close(force: true);
      await _deleteControlFile();
      _clearSecrets();
      _state = KaiGracefulShutdownState.exiting;
      await _onNativeExit();
    } catch (error) {
      await audit(
        'graceful_shutdown_teardown_failed',
        severity: 'error',
        details: {'error': error, 'pid': _processId},
      );
      rethrow;
    }
  }

  Future<void> _deleteControlFile() async {
    final file = controlFile;
    if (await file.exists()) await file.delete();
    final temporary = File('${file.path}.tmp');
    if (await temporary.exists()) await temporary.delete();
  }

  void _clearSecrets() {
    _capability = null;
    _runId = null;
  }

  String _randomHex(int bytes) {
    final values = List<int>.generate(bytes, (_) => _random.nextInt(256));
    return values
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  static Future<void> _defaultNativeExit() =>
      _channel.invokeMethod<void>('quitCoordinator');

  static Future<void> _defaultHardenCapabilityFile(File file) async {
    if (!Platform.isWindows) return;
    final escaped = file.path.replaceAll("'", "''");
    final script = """
\$path = '$escaped'
\$sid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
\$icacls = Join-Path \$env:SystemRoot 'System32\\icacls.exe'
& \$icacls \$path '/inheritance:r' '/grant:r' "*\${sid}:(F)" | Out-Null
if (\$LASTEXITCODE -ne 0) { exit \$LASTEXITCODE }
""";
    final result = await Process.run(
      'powershell.exe',
      ['-NoProfile', '-NonInteractive', '-Command', script],
      runInShell: false,
    );
    if (result.exitCode != 0) {
      throw FileSystemException(
        'Could not restrict the shutdown capability to the current user.',
        file.path,
      );
    }
  }
}
