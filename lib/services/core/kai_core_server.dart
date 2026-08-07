import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Lightweight, model-free coordination core for Kai's bodies.
///
/// This process deliberately owns no prompts, provider credentials, chat
/// generation, or tools. Its first responsibility is durable coordination:
/// presence leases and handoffs that survive any individual UI process.
class KaiCoreServer {
  KaiCoreServer({
    required this.dataDirectory,
    this.port = 8790,
    this.staleAfter = const Duration(seconds: 90),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Directory dataDirectory;
  final int port;
  final Duration staleAfter;
  final DateTime Function() _clock;

  HttpServer? _server;
  late final File _stateFile =
      File('${dataDirectory.path}${Platform.pathSeparator}state.json');
  Map<String, dynamic> _state = _emptyState();
  Future<void> _writeTail = Future<void>.value();

  Uri? get endpoint =>
      _server == null ? null : Uri.parse('http://127.0.0.1:${_server!.port}');

  Future<Uri> start() async {
    if (_server != null) return endpoint!;
    await dataDirectory.create(recursive: true);
    _state = await _readState();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    _server = server;
    server.listen(
      _handle,
      onError: (Object error, StackTrace stack) {
        stderr.writeln('[KaiCore] server error: $error');
      },
      cancelOnError: false,
    );
    return endpoint!;
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    await _writeTail;
    if (server != null) await server.close(force: true);
  }

  Future<void> _handle(HttpRequest request) async {
    try {
      final segments = request.uri.pathSegments;
      if (request.method == 'GET' && request.uri.path == '/health') {
        return _json(request.response, HttpStatus.ok, {
          'ok': true,
          'service': 'kai-core',
          'version': 2,
          'startedAt': _state['startedAt'],
          'capabilities': ['presence', 'handoffs', 'runtime_tasks'],
        });
      }

      if (segments.length == 2 &&
          segments[0] == 'v1' &&
          segments[1] == 'tasks') {
        if (request.method == 'GET') return _listTasks(request);
        if (request.method == 'POST') return await _createTask(request);
      }

      if (segments.length == 3 &&
          segments[0] == 'v1' &&
          segments[1] == 'tasks' &&
          segments[2] == 'claim' &&
          request.method == 'POST') {
        return await _claimNextTask(request);
      }

      if (segments.length == 4 &&
          segments[0] == 'v1' &&
          segments[1] == 'tasks' &&
          request.method == 'POST') {
        final taskId = Uri.decodeComponent(segments[2]);
        return switch (segments[3]) {
          'claim' => await _claimTask(request, taskId),
          'lease' => await _renewTaskLease(request, taskId),
          'complete' => await _completeTask(request, taskId),
          'fail' => await _failTask(request, taskId),
          'cancel' => await _cancelTask(request, taskId),
          _ => _json(
              request.response,
              HttpStatus.notFound,
              {'error': 'not_found'},
            ),
        };
      }

      if (segments.length == 2 &&
          segments[0] == 'v1' &&
          segments[1] == 'presence') {
        if (request.method == 'GET') return _listPresence(request);
      }

      if (segments.length == 3 &&
          segments[0] == 'v1' &&
          segments[1] == 'presence' &&
          request.method == 'PUT') {
        return await _upsertPresence(request, segments[2]);
      }

      if (segments.length == 2 &&
          segments[0] == 'v1' &&
          segments[1] == 'handoffs') {
        if (request.method == 'GET') return _listHandoffs(request);
        if (request.method == 'POST') return await _createHandoff(request);
      }

      if (segments.length == 4 &&
          segments[0] == 'v1' &&
          segments[1] == 'handoffs' &&
          segments[3] == 'ack' &&
          request.method == 'POST') {
        return await _ackHandoff(request, segments[2]);
      }

      _json(request.response, HttpStatus.notFound, {'error': 'not_found'});
    } on FormatException catch (error) {
      _json(request.response, HttpStatus.badRequest, {'error': error.message});
    } catch (error, stack) {
      stderr.writeln('[KaiCore] request failed: $error\n$stack');
      _json(request.response, HttpStatus.internalServerError, {
        'error': 'kai_core_request_failed',
      });
    }
  }

  Future<void> _upsertPresence(HttpRequest request, String rawDeviceId) async {
    final deviceId = Uri.decodeComponent(rawDeviceId).trim();
    if (deviceId.isEmpty) throw const FormatException('device_id_required');
    final body = await _body(request);
    final surface = _requiredString(body, 'surface');
    const surfaces = {'desktop', 'mobile', 'messenger', 'ar', 'vr'};
    if (!surfaces.contains(surface)) {
      throw const FormatException('invalid_surface');
    }

    final now = _clock().toUtc();
    final record = <String, dynamic>{
      'deviceId': deviceId,
      'surface': surface,
      'sessionId': _requiredString(body, 'sessionId'),
      'online': true,
      'foreground': body['foreground'] == true,
      'audioAvailable': body['audioAvailable'] == true,
      'worldId': _optionalString(body['worldId']),
      'gogglesOn': body['gogglesOn'] == true,
      'lastInteractionAt': _optionalString(body['lastInteractionAt']),
      'lastHeartbeatAt': now.toIso8601String(),
      'leaseExpiresAt': now.add(staleAfter).toIso8601String(),
    };
    _presence[deviceId] = record;
    await _persist();
    _json(request.response, HttpStatus.ok, record);
  }

  void _listPresence(HttpRequest request) {
    final now = _clock().toUtc();
    final includeStale = request.uri.queryParameters['includeStale'] == 'true';
    final records = _presence.values
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .map((item) {
          final expiry =
              DateTime.tryParse(item['leaseExpiresAt']?.toString() ?? '');
          item['online'] = expiry != null && expiry.isAfter(now);
          return item;
        })
        .where((item) => includeStale || item['online'] == true)
        .toList()
      ..sort((a, b) => (b['lastHeartbeatAt'] ?? '')
          .toString()
          .compareTo((a['lastHeartbeatAt'] ?? '').toString()));
    _json(request.response, HttpStatus.ok, {'devices': records});
  }

  Future<void> _createHandoff(HttpRequest request) async {
    final body = await _body(request);
    final id = _requiredString(body, 'handoffId');
    final from = _requiredString(body, 'fromSurface');
    final to = _requiredString(body, 'toSurface');
    if (from == to) throw const FormatException('handoff_requires_destination');
    final now = _clock().toUtc();
    final expiresAt =
        DateTime.tryParse(_requiredString(body, 'expiresAt'))?.toUtc();
    if (expiresAt == null || !expiresAt.isAfter(now)) {
      throw const FormatException('handoff_expiry_invalid');
    }

    final candidate = <String, dynamic>{
      'handoffId': id,
      // Compatibility endpoint name; this carries a thread summary between
      // simultaneously active bodies. It does not transfer Kai's presence.
      'purpose': 'thread_continuation',
      'fromSurface': from,
      'toSurface': to,
      'conversationId': _requiredString(body, 'conversationId'),
      'summary': _requiredString(body, 'summary'),
      'createdAt': _optionalString(body['createdAt']) ?? now.toIso8601String(),
      'expiresAt': expiresAt.toIso8601String(),
      'status': 'pending',
      'acknowledgedAt': null,
    };

    final existing = _handoffs[id];
    if (existing != null) {
      final prior = Map<String, dynamic>.from(existing as Map);
      final sameIntent = prior['fromSurface'] == from &&
          prior['toSurface'] == to &&
          prior['conversationId'] == candidate['conversationId'] &&
          prior['summary'] == candidate['summary'];
      if (!sameIntent) {
        return _json(request.response, HttpStatus.conflict, {
          'error': 'handoff_id_conflict',
        });
      }
      return _json(request.response, HttpStatus.ok, prior);
    }

    _handoffs[id] = candidate;
    await _persist();
    _json(request.response, HttpStatus.created, candidate);
  }

  void _listHandoffs(HttpRequest request) {
    final to = request.uri.queryParameters['toSurface'];
    final now = _clock().toUtc();
    var changed = false;
    final records = <Map<String, dynamic>>[];
    for (final entry in _handoffs.entries) {
      final item = Map<String, dynamic>.from(entry.value as Map);
      final expiry = DateTime.tryParse(item['expiresAt']?.toString() ?? '');
      if (item['status'] == 'pending' &&
          expiry != null &&
          !expiry.isAfter(now)) {
        item['status'] = 'expired';
        _handoffs[entry.key] = item;
        changed = true;
      }
      if (item['status'] == 'pending' &&
          (to == null || item['toSurface'] == to)) {
        records.add(item);
      }
    }
    if (changed) unawaited(_persist());
    records.sort((a, b) => (a['createdAt'] ?? '')
        .toString()
        .compareTo((b['createdAt'] ?? '').toString()));
    _json(request.response, HttpStatus.ok, {'handoffs': records});
  }

  Future<void> _ackHandoff(HttpRequest request, String rawId) async {
    final id = Uri.decodeComponent(rawId);
    final existing = _handoffs[id];
    if (existing == null) {
      return _json(request.response, HttpStatus.notFound, {
        'error': 'handoff_not_found',
      });
    }
    final item = Map<String, dynamic>.from(existing as Map);
    if (item['status'] == 'pending') {
      item['status'] = 'acknowledged';
      item['acknowledgedAt'] = _clock().toUtc().toIso8601String();
      _handoffs[id] = item;
      await _persist();
    }
    _json(request.response, HttpStatus.ok, item);
  }

  Future<void> _createTask(HttpRequest request) async {
    final body = await _body(request);
    final id = _requiredString(body, 'taskId');
    final lane = _requiredLane(body);
    final conversationId = _optionalString(body['conversationId']);
    if (lane == 'conversation' && conversationId == null) {
      throw const FormatException('conversation_id_required');
    }
    final priority = _priority(body['priority']);
    final payload = body['payload'];
    if (payload != null && payload is! Map) {
      throw const FormatException('payload_object_required');
    }
    final now = _clock().toUtc().toIso8601String();
    final candidate = <String, dynamic>{
      'taskId': id,
      'lane': lane,
      'kind': _requiredString(body, 'kind'),
      'sourceSurface': _requiredString(body, 'sourceSurface'),
      'conversationId': conversationId,
      'priority': priority,
      'payload': payload is Map ? Map<String, dynamic>.from(payload) : {},
      'status': 'queued',
      'attempt': 0,
      'createdAt': now,
      'updatedAt': now,
    };

    final existing = _tasks[id];
    if (existing != null) {
      final prior = Map<String, dynamic>.from(existing as Map);
      final sameIntent = prior['lane'] == lane &&
          prior['kind'] == candidate['kind'] &&
          prior['sourceSurface'] == candidate['sourceSurface'] &&
          prior['conversationId'] == conversationId &&
          jsonEncode(prior['payload']) == jsonEncode(candidate['payload']);
      if (!sameIntent) {
        return _json(request.response, HttpStatus.conflict, {
          'error': 'task_id_conflict',
        });
      }
      return _json(request.response, HttpStatus.ok, prior);
    }

    _tasks[id] = candidate;
    await _persist();
    _json(request.response, HttpStatus.created, candidate);
  }

  Future<void> _claimNextTask(HttpRequest request) async {
    final body = await _body(request);
    final lane = _requiredLane(body);
    final workerId = _requiredString(body, 'workerId');
    final lease = _leaseDuration(body['leaseSeconds']);
    final now = _clock().toUtc();
    final changed = _requeueExpiredTasks(now);

    final candidates = _tasks.values
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .where((item) => item['lane'] == lane && item['status'] == 'queued')
        .where((item) => _canRun(item, now))
        .toList()
      ..sort(_compareTasks);
    if (candidates.isEmpty) {
      if (changed) await _persist();
      return _json(request.response, HttpStatus.ok, {'task': null});
    }
    final task = _claim(candidates.first, workerId, lease, now);
    await _persist();
    _json(request.response, HttpStatus.ok, {'task': task});
  }

  Future<void> _claimTask(HttpRequest request, String taskId) async {
    final body = await _body(request);
    final workerId = _requiredString(body, 'workerId');
    final lease = _leaseDuration(body['leaseSeconds']);
    final now = _clock().toUtc();
    final changed = _requeueExpiredTasks(now);
    final raw = _tasks[taskId];
    if (raw == null) {
      if (changed) await _persist();
      return _json(request.response, HttpStatus.notFound, {
        'error': 'task_not_found',
      });
    }
    final item = Map<String, dynamic>.from(raw as Map);
    if (item['status'] != 'queued' || !_canRun(item, now)) {
      if (changed) await _persist();
      return _json(request.response, HttpStatus.conflict, {
        'error': 'task_not_claimable',
      });
    }
    final task = _claim(item, workerId, lease, now);
    await _persist();
    _json(request.response, HttpStatus.ok, task);
  }

  Future<void> _renewTaskLease(HttpRequest request, String taskId) async {
    final body = await _body(request);
    final workerId = _requiredString(body, 'workerId');
    final lease = _leaseDuration(body['leaseSeconds']);
    final raw = _tasks[taskId];
    if (raw == null) {
      return _json(request.response, HttpStatus.notFound, {
        'error': 'task_not_found',
      });
    }
    final item = Map<String, dynamic>.from(raw as Map);
    if (item['status'] != 'running' || item['claimedBy'] != workerId) {
      return _json(request.response, HttpStatus.conflict, {
        'error': 'task_lease_owner_mismatch',
      });
    }
    final now = _clock().toUtc();
    item['updatedAt'] = now.toIso8601String();
    item['leaseExpiresAt'] = now.add(lease).toIso8601String();
    _tasks[taskId] = item;
    await _persist();
    _json(request.response, HttpStatus.ok, item);
  }

  Future<void> _completeTask(HttpRequest request, String taskId) async {
    final body = await _body(request);
    final item = _ownedRunningTask(
      request,
      taskId,
      _requiredString(body, 'workerId'),
    );
    if (item == null) return;
    final result = body['result'];
    if (result != null && result is! Map) {
      throw const FormatException('result_object_required');
    }
    final now = _clock().toUtc().toIso8601String();
    item
      ..['status'] = 'done'
      ..['result'] = result is Map ? Map<String, dynamic>.from(result) : {}
      ..['updatedAt'] = now
      ..['completedAt'] = now
      ..remove('leaseExpiresAt');
    _tasks[taskId] = item;
    await _persist();
    _json(request.response, HttpStatus.ok, item);
  }

  Future<void> _failTask(HttpRequest request, String taskId) async {
    final body = await _body(request);
    final item = _ownedRunningTask(
      request,
      taskId,
      _requiredString(body, 'workerId'),
    );
    if (item == null) return;
    final now = _clock().toUtc().toIso8601String();
    final retry = body['retry'] == true;
    item
      ..['status'] = retry ? 'queued' : 'failed'
      ..['error'] = _requiredString(body, 'error')
      ..['updatedAt'] = now
      ..remove('claimedBy')
      ..remove('leaseExpiresAt');
    if (!retry) item['completedAt'] = now;
    _tasks[taskId] = item;
    await _persist();
    _json(request.response, HttpStatus.ok, item);
  }

  Future<void> _cancelTask(HttpRequest request, String taskId) async {
    final body = await _body(request);
    final workerId = _requiredString(body, 'workerId');
    final raw = _tasks[taskId];
    if (raw == null) {
      return _json(
        request.response,
        HttpStatus.notFound,
        {'error': 'task_not_found'},
      );
    }
    final item = Map<String, dynamic>.from(raw as Map);
    final status = item['status']?.toString();
    final owner = item['claimedBy']?.toString();
    if (status == 'running' && owner != workerId) {
      return _json(request.response, HttpStatus.conflict, {
        'error': 'task_owner_mismatch',
      });
    }
    if (status != 'queued' && status != 'running') {
      return _json(request.response, HttpStatus.ok, item);
    }
    item
      ..['status'] = 'cancelled'
      ..['updatedAt'] = _clock().toUtc().toIso8601String()
      ..['cancelledBy'] = workerId
      ..remove('claimedBy')
      ..remove('leaseExpiresAt');
    _tasks[taskId] = item;
    await _persist();
    _json(request.response, HttpStatus.ok, item);
  }

  void _listTasks(HttpRequest request) {
    final now = _clock().toUtc();
    final changed = _requeueExpiredTasks(now);
    final lane = request.uri.queryParameters['lane'];
    final status = request.uri.queryParameters['status'];
    final records = _tasks.values
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .where((item) => lane == null || item['lane'] == lane)
        .where((item) => status == null || item['status'] == status)
        .toList()
      ..sort(_compareTasks);
    if (changed) unawaited(_persist());
    _json(request.response, HttpStatus.ok, {'tasks': records});
  }

  Map<String, dynamic> _claim(
    Map<String, dynamic> item,
    String workerId,
    Duration lease,
    DateTime now,
  ) {
    final id = item['taskId'].toString();
    item
      ..['status'] = 'running'
      ..['claimedBy'] = workerId
      ..['attempt'] = ((item['attempt'] as num?)?.toInt() ?? 0) + 1
      ..['startedAt'] ??= now.toIso8601String()
      ..['updatedAt'] = now.toIso8601String()
      ..['leaseExpiresAt'] = now.add(lease).toIso8601String();
    _tasks[id] = item;
    return item;
  }

  bool _canRun(Map<String, dynamic> candidate, DateTime now) {
    final lane = candidate['lane']?.toString();
    final running = _tasks.values
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .where((item) => item['lane'] == lane && item['status'] == 'running')
        .where((item) {
      final expiry =
          DateTime.tryParse(item['leaseExpiresAt']?.toString() ?? '');
      return expiry != null && expiry.isAfter(now);
    }).toList();
    // Two human-facing conversations is the deliberate ceiling: enough for
    // simultaneous bodies without multiplying interleaving and model cost.
    // Background work has its own pool and does not consume these slots.
    const capacities = {'conversation': 2, 'work': 2, 'memory': 1};
    if (running.length >= (capacities[lane] ?? 1)) return false;
    if (lane == 'conversation') {
      final conversationId = candidate['conversationId'];
      return !running.any((item) => item['conversationId'] == conversationId);
    }
    return true;
  }

  bool _requeueExpiredTasks(DateTime now) {
    var changed = false;
    for (final entry in _tasks.entries.toList()) {
      final item = Map<String, dynamic>.from(entry.value as Map);
      if (item['status'] != 'running') continue;
      final expiry =
          DateTime.tryParse(item['leaseExpiresAt']?.toString() ?? '');
      if (expiry != null && expiry.isAfter(now)) continue;
      item
        ..['status'] = 'queued'
        ..['updatedAt'] = now.toIso8601String()
        ..['lastLeaseOwner'] = item['claimedBy']
        ..remove('claimedBy')
        ..remove('leaseExpiresAt');
      _tasks[entry.key] = item;
      changed = true;
    }
    return changed;
  }

  Map<String, dynamic>? _ownedRunningTask(
    HttpRequest request,
    String taskId,
    String workerId,
  ) {
    final raw = _tasks[taskId];
    if (raw == null) {
      _json(request.response, HttpStatus.notFound, {'error': 'task_not_found'});
      return null;
    }
    final item = Map<String, dynamic>.from(raw as Map);
    if (item['status'] != 'running' || item['claimedBy'] != workerId) {
      _json(request.response, HttpStatus.conflict, {
        'error': 'task_owner_mismatch',
      });
      return null;
    }
    return item;
  }

  static int _compareTasks(Map<String, dynamic> a, Map<String, dynamic> b) {
    final priority = _priorityRank(b['priority']?.toString())
        .compareTo(_priorityRank(a['priority']?.toString()));
    if (priority != 0) return priority;
    return (a['createdAt'] ?? '')
        .toString()
        .compareTo((b['createdAt'] ?? '').toString());
  }

  static int _priorityRank(String? value) => switch (value) {
        'urgent' => 3,
        'high' => 2,
        'normal' => 1,
        'low' => 0,
        _ => 1,
      };

  static String _priority(Object? value) {
    final priority = value?.toString().trim().toLowerCase() ?? 'normal';
    if (!{'urgent', 'high', 'normal', 'low'}.contains(priority)) {
      throw const FormatException('invalid_priority');
    }
    return priority;
  }

  static String _requiredLane(Map<String, dynamic> body) {
    final lane = _requiredString(body, 'lane').toLowerCase();
    if (!{'conversation', 'work', 'memory'}.contains(lane)) {
      throw const FormatException('invalid_lane');
    }
    return lane;
  }

  static Duration _leaseDuration(Object? value) {
    final seconds = value is num ? value.toInt() : 120;
    if (seconds < 15 || seconds > 900) {
      throw const FormatException('invalid_lease_seconds');
    }
    return Duration(seconds: seconds);
  }

  Map<String, dynamic> get _presence =>
      _state['presence'] as Map<String, dynamic>;
  Map<String, dynamic> get _handoffs =>
      _state['handoffs'] as Map<String, dynamic>;
  Map<String, dynamic> get _tasks => _state['tasks'] as Map<String, dynamic>;

  Future<Map<String, dynamic>> _body(HttpRequest request) async {
    final text = await utf8.decoder.bind(request).join();
    final decoded = jsonDecode(text);
    if (decoded is! Map) throw const FormatException('json_object_required');
    return Map<String, dynamic>.from(decoded);
  }

  Future<Map<String, dynamic>> _readState() async {
    if (!await _stateFile.exists()) return _emptyState();
    try {
      final decoded = jsonDecode(await _stateFile.readAsString());
      if (decoded is! Map) return _emptyState();
      final state = Map<String, dynamic>.from(decoded);
      state['presence'] = _map(state['presence']);
      state['handoffs'] = _map(state['handoffs']);
      state['tasks'] = _map(state['tasks']);
      state['startedAt'] ??= _clock().toUtc().toIso8601String();
      state['version'] = 2;
      return state;
    } catch (_) {
      final backup = File('${_stateFile.path}.bak');
      if (!await backup.exists()) return _emptyState();
      final decoded = jsonDecode(await backup.readAsString());
      final state = Map<String, dynamic>.from(decoded as Map);
      state['presence'] = _map(state['presence']);
      state['handoffs'] = _map(state['handoffs']);
      state['tasks'] = _map(state['tasks']);
      return state;
    }
  }

  Future<void> _persist() {
    final snapshot = jsonEncode(_state);
    _writeTail = _writeTail.then((_) async {
      final temp = File('${_stateFile.path}.tmp');
      final backup = File('${_stateFile.path}.bak');
      await temp.writeAsString(snapshot, flush: true);
      if (await backup.exists()) await backup.delete();
      if (await _stateFile.exists()) await _stateFile.rename(backup.path);
      await temp.rename(_stateFile.path);
    });
    return _writeTail;
  }

  static Map<String, dynamic> _emptyState() => {
        'version': 2,
        'startedAt': DateTime.now().toUtc().toIso8601String(),
        'presence': <String, dynamic>{},
        'handoffs': <String, dynamic>{},
        'tasks': <String, dynamic>{},
      };

  static Map<String, dynamic> _map(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

  static String _requiredString(Map<String, dynamic> body, String key) {
    final value = body[key]?.toString().trim() ?? '';
    if (value.isEmpty) throw FormatException('${key}_required');
    return value;
  }

  static String? _optionalString(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  static void _json(HttpResponse response, int status, Object value) {
    response.statusCode = status;
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(value));
    response.close();
  }
}
