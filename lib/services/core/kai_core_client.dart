import 'dart:async';
import 'dart:convert';
import 'dart:io';

class KaiCoreClient {
  KaiCoreClient({
    Uri? endpoint,
    HttpClient? httpClient,
    this.timeout = const Duration(seconds: 2),
  })  : endpoint = endpoint ?? Uri.parse('http://127.0.0.1:8790'),
        _http = httpClient ?? HttpClient();

  final Uri endpoint;
  final Duration timeout;
  final HttpClient _http;

  Future<bool> isHealthy() async {
    try {
      final result = await _request('GET', '/health');
      return result.statusCode == HttpStatus.ok && result.body['ok'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> heartbeat({
    required String deviceId,
    required String surface,
    required String sessionId,
    required bool foreground,
    required bool audioAvailable,
    String? worldId,
    bool gogglesOn = false,
    DateTime? lastInteractionAt,
  }) async {
    final result = await _request(
      'PUT',
      '/v1/presence/${Uri.encodeComponent(deviceId)}',
      body: {
        'surface': surface,
        'sessionId': sessionId,
        'foreground': foreground,
        'audioAvailable': audioAvailable,
        if (worldId != null) 'worldId': worldId,
        'gogglesOn': gogglesOn,
        if (lastInteractionAt != null)
          'lastInteractionAt': lastInteractionAt.toUtc().toIso8601String(),
      },
    );
    _requireSuccess(result);
    return result.body;
  }

  Future<List<Map<String, dynamic>>> activeDevices() async {
    final result = await _request('GET', '/v1/presence');
    _requireSuccess(result);
    return (result.body['devices'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> createHandoff({
    required String handoffId,
    required String fromSurface,
    required String toSurface,
    required String conversationId,
    required String summary,
    required DateTime expiresAt,
  }) async {
    final result = await _request('POST', '/v1/handoffs', body: {
      'handoffId': handoffId,
      'purpose': 'thread_continuation',
      'fromSurface': fromSurface,
      'toSurface': toSurface,
      'conversationId': conversationId,
      'summary': summary,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'expiresAt': expiresAt.toUtc().toIso8601String(),
    });
    _requireSuccess(result);
    return result.body;
  }

  Future<List<Map<String, dynamic>>> pendingHandoffs(String toSurface) async {
    final query = Uri(queryParameters: {'toSurface': toSurface}).query;
    final result = await _request('GET', '/v1/handoffs?$query');
    _requireSuccess(result);
    return (result.body['handoffs'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> acknowledgeHandoff(String handoffId) async {
    final result = await _request(
      'POST',
      '/v1/handoffs/${Uri.encodeComponent(handoffId)}/ack',
      body: const {},
    );
    _requireSuccess(result);
    return result.body;
  }

  Future<Map<String, dynamic>> enqueueTask({
    required String taskId,
    required String lane,
    required String kind,
    required String sourceSurface,
    String? conversationId,
    String priority = 'normal',
    Map<String, dynamic> payload = const {},
  }) async {
    final result = await _request('POST', '/v1/tasks', body: {
      'taskId': taskId,
      'lane': lane,
      'kind': kind,
      'sourceSurface': sourceSurface,
      if (conversationId != null) 'conversationId': conversationId,
      'priority': priority,
      'payload': payload,
    });
    _requireSuccess(result);
    return result.body;
  }

  Future<Map<String, dynamic>?> claimNextTask({
    required String lane,
    required String workerId,
    Duration lease = const Duration(minutes: 2),
  }) async {
    final result = await _request('POST', '/v1/tasks/claim', body: {
      'lane': lane,
      'workerId': workerId,
      'leaseSeconds': lease.inSeconds,
    });
    _requireSuccess(result);
    final task = result.body['task'];
    return task is Map ? Map<String, dynamic>.from(task) : null;
  }

  Future<Map<String, dynamic>> claimTask(
    String taskId, {
    required String workerId,
    Duration lease = const Duration(minutes: 2),
  }) async {
    final result = await _request(
      'POST',
      '/v1/tasks/${Uri.encodeComponent(taskId)}/claim',
      body: {
        'workerId': workerId,
        'leaseSeconds': lease.inSeconds,
      },
    );
    _requireSuccess(result);
    return result.body;
  }

  Future<Map<String, dynamic>> renewTaskLease(
    String taskId, {
    required String workerId,
    Duration lease = const Duration(minutes: 2),
  }) async {
    final result = await _request(
      'POST',
      '/v1/tasks/${Uri.encodeComponent(taskId)}/lease',
      body: {
        'workerId': workerId,
        'leaseSeconds': lease.inSeconds,
      },
    );
    _requireSuccess(result);
    return result.body;
  }

  Future<Map<String, dynamic>> completeTask(
    String taskId, {
    required String workerId,
    Map<String, dynamic> result = const {},
  }) async {
    final response = await _request(
      'POST',
      '/v1/tasks/${Uri.encodeComponent(taskId)}/complete',
      body: {'workerId': workerId, 'result': result},
    );
    _requireSuccess(response);
    return response.body;
  }

  Future<Map<String, dynamic>> failTask(
    String taskId, {
    required String workerId,
    required String error,
    bool retry = false,
  }) async {
    final response = await _request(
      'POST',
      '/v1/tasks/${Uri.encodeComponent(taskId)}/fail',
      body: {
        'workerId': workerId,
        'error': error,
        'retry': retry,
      },
    );
    _requireSuccess(response);
    return response.body;
  }

  Future<Map<String, dynamic>> cancelTask(
    String taskId, {
    required String workerId,
  }) async {
    final response = await _request(
      'POST',
      '/v1/tasks/${Uri.encodeComponent(taskId)}/cancel',
      body: {'workerId': workerId},
    );
    _requireSuccess(response);
    return response.body;
  }

  Future<List<Map<String, dynamic>>> tasks({
    String? lane,
    String? status,
  }) async {
    final query = Uri(
      queryParameters: {
        if (lane != null) 'lane': lane,
        if (status != null) 'status': status,
      },
    ).query;
    final result =
        await _request('GET', '/v1/tasks${query.isEmpty ? '' : '?$query'}');
    _requireSuccess(result);
    return (result.body['tasks'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }

  void close() => _http.close(force: true);

  Future<_KaiCoreResult> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final uri = endpoint.resolve(path);
    final request = await _http.openUrl(method, uri).timeout(timeout);
    request.headers.contentType = ContentType.json;
    if (body != null) request.write(jsonEncode(body));
    final response = await request.close().timeout(timeout);
    final text = await utf8.decoder.bind(response).join().timeout(timeout);
    final decoded = text.isEmpty ? <String, dynamic>{} : jsonDecode(text);
    return _KaiCoreResult(
      response.statusCode,
      decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : <String, dynamic>{'value': decoded},
    );
  }

  static void _requireSuccess(_KaiCoreResult result) {
    if (result.statusCode >= 200 && result.statusCode < 300) return;
    throw KaiCoreException(
      result.statusCode,
      result.body['error']?.toString() ?? 'kai_core_request_failed',
    );
  }
}

class KaiCoreException implements Exception {
  const KaiCoreException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  @override
  String toString() => 'KaiCoreException($statusCode): $message';
}

class _KaiCoreResult {
  const _KaiCoreResult(this.statusCode, this.body);

  final int statusCode;
  final Map<String, dynamic> body;
}

/// Optional desktop integration. Missing sidecar means "use current behavior",
/// never "Homecoming cannot start".
class KaiCoreSidecarManager {
  KaiCoreSidecarManager({KaiCoreClient? client})
      : client = client ?? KaiCoreClient();

  final KaiCoreClient client;

  Future<bool> ensureAvailable() async {
    if (await client.isHealthy()) return true;
    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) {
      return false;
    }

    for (final candidate in _executableCandidates()) {
      if (!await File(candidate).exists()) continue;
      try {
        await Process.start(
          candidate,
          const [],
          mode: ProcessStartMode.detached,
        );
      } catch (_) {
        continue;
      }
      for (var attempt = 0; attempt < 10; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        if (await client.isHealthy()) return true;
      }
    }
    return false;
  }

  Iterable<String> _executableCandidates() sync* {
    final configured = Platform.environment['KAI_CORE_EXECUTABLE'];
    if (configured != null && configured.trim().isNotEmpty) {
      yield configured.trim();
    }
    final name = Platform.isWindows ? 'KaiCore.exe' : 'kai-core';
    yield '${File(Platform.resolvedExecutable).parent.path}${Platform.pathSeparator}$name';
    yield '${Directory.current.path}${Platform.pathSeparator}build${Platform.pathSeparator}kai-core${Platform.pathSeparator}$name';
  }
}

class KaiCorePresenceHeartbeat {
  KaiCorePresenceHeartbeat({
    required this.client,
    required this.deviceId,
    required this.surface,
    required this.sessionId,
    this.interval = const Duration(seconds: 30),
    this.onStatus,
  });

  final KaiCoreClient client;
  final String deviceId;
  final String surface;
  final String sessionId;
  final Duration interval;
  final void Function(KaiCoreHeartbeatStatus status)? onStatus;
  Timer? _timer;
  bool _foreground = true;
  DateTime? _lastSuccessAt;
  int _consecutiveFailures = 0;

  void start() {
    if (_timer != null) return;
    _report(KaiCoreHeartbeatPhase.connecting);
    unawaited(beat());
    _timer = Timer.periodic(interval, (_) => unawaited(beat()));
  }

  void setForeground(bool value) {
    _foreground = value;
    unawaited(beat());
  }

  Future<void> beat() async {
    try {
      await client.heartbeat(
        deviceId: deviceId,
        surface: surface,
        sessionId: sessionId,
        foreground: _foreground,
        audioAvailable: false,
      );
      _lastSuccessAt = DateTime.now().toUtc();
      _consecutiveFailures = 0;
      _report(KaiCoreHeartbeatPhase.healthy);
    } catch (_) {
      _consecutiveFailures++;
      final staleAfter = interval * 3;
      final lastSuccess = _lastSuccessAt;
      final isStale = lastSuccess == null ||
          DateTime.now().toUtc().difference(lastSuccess) >= staleAfter;
      _report(isStale
          ? KaiCoreHeartbeatPhase.offline
          : KaiCoreHeartbeatPhase.reconnecting);
      // The sidecar is optional during migration. Current Homecoming behavior
      // remains the fallback until the core has earned authority.
    }
  }

  void _report(KaiCoreHeartbeatPhase phase) {
    onStatus?.call(KaiCoreHeartbeatStatus(
      phase: phase,
      lastSuccessAt: _lastSuccessAt,
      consecutiveFailures: _consecutiveFailures,
    ));
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}

enum KaiCoreHeartbeatPhase { connecting, healthy, reconnecting, offline }

class KaiCoreHeartbeatStatus {
  const KaiCoreHeartbeatStatus({
    required this.phase,
    this.lastSuccessAt,
    this.consecutiveFailures = 0,
  });

  final KaiCoreHeartbeatPhase phase;
  final DateTime? lastSuccessAt;
  final int consecutiveFailures;
}

typedef KaiCoreHandoffReceiver = Future<bool> Function(
  Map<String, dynamic> handoff,
);

/// Polling inbox for one destination body.
///
/// A handoff is acknowledged only after [onHandoff] accepts it. If the app is
/// closing, rendering fails, or the callback rejects it, the durable record
/// stays pending for the next process rather than disappearing mid-transition.
class KaiCoreHandoffInbox {
  KaiCoreHandoffInbox({
    required this.client,
    required this.surface,
    required this.onHandoff,
    this.interval = const Duration(seconds: 3),
  });

  final KaiCoreClient client;
  final String surface;
  final KaiCoreHandoffReceiver onHandoff;
  final Duration interval;

  Timer? _timer;
  bool _polling = false;
  final Set<String> _processing = {};

  void start() {
    if (_timer != null) return;
    unawaited(poll());
    _timer = Timer.periodic(interval, (_) => unawaited(poll()));
  }

  Future<void> poll() async {
    if (_polling) return;
    _polling = true;
    try {
      final pending = await client.pendingHandoffs(surface);
      for (final handoff in pending) {
        final id = handoff['handoffId']?.toString() ?? '';
        if (id.isEmpty || !_processing.add(id)) continue;
        try {
          final accepted = await onHandoff(handoff);
          if (accepted) await client.acknowledgeHandoff(id);
        } finally {
          _processing.remove(id);
        }
      }
    } catch (_) {
      // Optional during migration. Pending records remain durable in the core.
    } finally {
      _polling = false;
    }
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}
