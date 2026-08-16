import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'kai_scheduled_commitment.dart';

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

  /// When THIS process began serving.
  ///
  /// Distinct from `state['startedAt']`, which is written once with `??=` and
  /// therefore records the first time Core ever ran on this machine — it
  /// survives every restart and rebuild. Reading it as a process clock is what
  /// made the Brief 018 preflight declare a freshly built runtime "stale": the
  /// capability list was current, the date was from the original install.
  ///
  /// An evidence-governed project cannot afford an instrument that reports a
  /// value nobody means. Both are published; neither is guessed from the other.
  DateTime? _processStartedAt;

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
    _processStartedAt = _clock().toUtc();
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
          // First run on this machine. Durable across restarts by design.
          'startedAt': _state['startedAt'],
          // This process. The only field that answers "is the running build
          // the one I just made?"
          'processStartedAt': _processStartedAt?.toIso8601String(),
          'capabilities': [
            'presence',
            'handoffs',
            'runtime_tasks',
            'outbound_inbox',
            'scheduled_commitments',
          ],
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

      if (segments.length == 2 &&
          segments[0] == 'v1' &&
          segments[1] == 'outbound') {
        if (request.method == 'GET') return _listOutbound(request);
        if (request.method == 'POST') return await _createOutbound(request);
      }

      if (segments.length == 4 &&
          segments[0] == 'v1' &&
          segments[1] == 'outbound' &&
          segments[3] == 'ack' &&
          request.method == 'POST') {
        return await _ackOutbound(request, segments[2]);
      }

      if (segments.length == 2 &&
          segments[0] == 'v1' &&
          segments[1] == 'commitments') {
        if (request.method == 'GET') return _listCommitments(request);
        if (request.method == 'POST') return await _createCommitment(request);
      }

      if (segments.length == 4 &&
          segments[0] == 'v1' &&
          segments[1] == 'commitments' &&
          segments[3] == 'dispatch' &&
          request.method == 'POST') {
        return await _dispatchCommitment(request, segments[2]);
      }

      if (segments.length == 4 &&
          segments[0] == 'v1' &&
          segments[1] == 'commitments' &&
          segments[3] == 'next-evaluation' &&
          request.method == 'PUT') {
        return await _deferCommitment(request, segments[2]);
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
    final status = _optionalString(body['status']) ?? 'idle';
    const bodyStatuses = {
      'idle',
      'listening',
      'thinking',
      'speaking',
      'working',
    };
    if (!bodyStatuses.contains(status)) {
      throw const FormatException('invalid_presence_status');
    }
    final record = <String, dynamic>{
      'deviceId': deviceId,
      'surface': surface,
      'sessionId': _requiredString(body, 'sessionId'),
      'online': true,
      'foreground': body['foreground'] == true,
      'audioAvailable': body['audioAvailable'] == true,
      'worldId': _optionalString(body['worldId']),
      'gogglesOn': body['gogglesOn'] == true,
      'status': status,
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
    if (changed) unawaited(_persistBestEffort());
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

  Future<void> _createOutbound(HttpRequest request) async {
    final body = await _body(request);
    final id = _requiredString(body, 'outboundId');
    final kind = _requiredString(body, 'kind');
    if (!{'proactive_friend', 'completed_work', 'direct_reply'}
        .contains(kind)) {
      throw const FormatException('invalid_outbound_kind');
    }
    final text = _requiredString(body, 'text');
    if (text.length > 4000) throw const FormatException('outbound_too_large');
    final now = _clock().toUtc();
    final expiresAt =
        DateTime.tryParse(_requiredString(body, 'expiresAt'))?.toUtc();
    if (expiresAt == null ||
        !expiresAt.isAfter(now) ||
        expiresAt.isAfter(now.add(const Duration(hours: 24)))) {
      throw const FormatException('outbound_expiry_invalid');
    }
    final candidate = <String, dynamic>{
      'outboundId': id,
      'kind': kind,
      'fromSurface': _requiredString(body, 'fromSurface'),
      'toSurface': _requiredString(body, 'toSurface'),
      // Every envelope belongs to one exact body. Surface-only delivery would
      // let two headsets race and both present the same supposedly singular
      // moment before either acknowledgement reaches Core.
      'targetBodyId': _requiredString(body, 'targetBodyId'),
      'conversationId': _optionalString(body['conversationId']),
      'correlationId': _optionalString(body['correlationId']),
      'text': text,
      'gesture': _optionalString(body['gesture']) ?? 'none',
      'createdAt': now.toIso8601String(),
      'expiresAt': expiresAt.toIso8601String(),
      'status': 'pending',
      'acknowledgedAt': null,
      'acknowledgedBy': null,
    };
    final existing = _outbound[id];
    if (existing != null) {
      final prior = Map<String, dynamic>.from(existing as Map);
      final sameIntent = prior['kind'] == kind &&
          prior['toSurface'] == candidate['toSurface'] &&
          prior['targetBodyId'] == candidate['targetBodyId'] &&
          prior['text'] == text;
      if (!sameIntent) {
        return _json(request.response, HttpStatus.conflict, {
          'error': 'outbound_id_conflict',
        });
      }
      return _json(request.response, HttpStatus.ok, prior);
    }
    _outbound[id] = candidate;
    await _persist();
    _json(request.response, HttpStatus.created, candidate);
  }

  void _listOutbound(HttpRequest request) {
    final toSurface = request.uri.queryParameters['toSurface']?.trim();
    final bodyId = request.uri.queryParameters['bodyId']?.trim();
    if (toSurface == null || toSurface.isEmpty) {
      throw const FormatException('toSurface_required');
    }
    if (bodyId == null || bodyId.isEmpty) {
      throw const FormatException('bodyId_required');
    }
    final now = _clock().toUtc();
    var changed = false;
    final records = <Map<String, dynamic>>[];
    for (final entry in _outbound.entries) {
      final item = Map<String, dynamic>.from(entry.value as Map);
      final expiry = DateTime.tryParse(item['expiresAt']?.toString() ?? '');
      // A commitment envelope is EXEMPT from relevance expiry. Ordinary
      // outbound is a moment that stops being worth saying; a promise is owed
      // until its exact body acknowledges it, and letting the 24-hour sweep
      // mark it expired would strand it â€” still `dispatched` in the ledger,
      // invisible in the inbox, delivered to nobody, and never retried.
      final isCommitment =
          (item['commitmentId']?.toString().trim() ?? '').isNotEmpty;
      if (!isCommitment &&
          item['status'] == 'pending' &&
          (expiry == null || !expiry.isAfter(now))) {
        item['status'] = 'expired';
        _outbound[entry.key] = item;
        changed = true;
      }
      final target = item['targetBodyId']?.toString().trim() ?? '';
      if (item['status'] == 'pending' &&
          item['toSurface'] == toSurface &&
          target == bodyId) {
        records.add(item);
      }
    }
    if (changed) unawaited(_persistBestEffort());
    records.sort((a, b) =>
        a['createdAt'].toString().compareTo(b['createdAt'].toString()));
    _json(request.response, HttpStatus.ok, {'outbound': records});
  }

  Future<void> _ackOutbound(HttpRequest request, String rawId) async {
    final body = await _body(request);
    final bodyId = _requiredString(body, 'bodyId');
    final surface = _requiredString(body, 'surface');
    final id = Uri.decodeComponent(rawId);
    final existing = _outbound[id];
    if (existing == null) {
      return _json(request.response, HttpStatus.notFound, {
        'error': 'outbound_not_found',
      });
    }
    final item = Map<String, dynamic>.from(existing as Map);
    final target = item['targetBodyId']?.toString().trim() ?? '';
    if (item['toSurface'] != surface ||
        (target.isNotEmpty && target != bodyId)) {
      return _json(request.response, HttpStatus.conflict, {
        'error': 'outbound_recipient_mismatch',
      });
    }
    if (item['status'] == 'pending') {
      item
        ..['status'] = 'acknowledged'
        ..['acknowledgedAt'] = _clock().toUtc().toIso8601String()
        ..['acknowledgedBy'] = bodyId;
      _outbound[id] = item;
      // Same durable write. The recipient checks above already ran, so a wrong
      // body or wrong surface cannot reach this line â€” which means it cannot
      // close the linked promise either.
      _linkAcknowledgedCommitment(item);
      await _persist();
    } else {
      // Already acknowledged in memory. If that closure never reached disk, the
      // retry is what makes it durable — otherwise a restart reopens a promise
      // the body was told twice it had closed.
      await _ensureDurable();
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
    if (changed) unawaited(_persistBestEffort());
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

  // â”€â”€ Scheduled commitments â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  //
  // Lifecycle: scheduled -> dispatched -> acknowledged.
  //
  // There is deliberately no terminal `failed`, `expired`, or `delivered`. A
  // promise that could not be delivered is still owed â€” the only thing that
  // ends it is the target body confirming it landed. Abandonment would need an
  // explicit product decision, not a quiet timeout.

  Future<void> _createCommitment(HttpRequest request) async {
    if (_commitmentLedgerUnsupported) {
      return _json(request.response, HttpStatus.conflict, {
        'error': 'commitment_ledger_unsupported',
      });
    }
    final body = await _body(request);
    final id = _requiredString(body, 'commitmentId');
    final text = _verbatimText(body, 'text');
    if (text.length > 2000) throw const FormatException('commitment_too_large');

    final dueAt = DateTime.tryParse(_requiredString(body, 'dueAt'))?.toUtc();
    if (dueAt == null) throw const FormatException('commitment_due_invalid');
    final now = _clock().toUtc();
    if (!dueAt.isAfter(now)) {
      throw const FormatException('commitment_due_in_past');
    }

    final wallClock = _requiredString(body, 'dueWallClock');
    final offsetMinutes = body['dueWallOffsetMinutes'];

    final candidate = <String, dynamic>{
      'commitmentId': id,
      'personaId': _requiredString(body, 'personaId'),
      'text': text,
      // Stored in UTC; the Bahrain wall clock that produced it is kept beside
      // it as provenance so a later reader can see what was actually asked for
      // rather than re-deriving it from a host timezone.
      'dueAt': dueAt.toIso8601String(),
      'dueWallClock': wallClock,
      'dueWallOffsetMinutes': offsetMinutes,
      'audience': 'work',
      'createdAt': now.toIso8601String(),
      'status': 'scheduled',
      // Durable retry/defer instant. The engine's decision is persisted here so
      // a restart does not re-evaluate something it already deferred.
      'nextEvaluationAt': dueAt.toIso8601String(),
      'outboundId': null,
      'targetBodyId': null,
      'dispatchedAt': null,
      'acknowledgedAt': null,
    };

    final existing = _commitments[id];
    if (existing != null) {
      final prior = Map<String, dynamic>.from(existing as Map);
      // The WHOLE intent, not just text and time. A retry that changed persona,
      // wall provenance, offset or audience is a different promise wearing an
      // existing id, and returning the old record would quietly honour neither.
      const intentFields = [
        'personaId',
        'text',
        'dueAt',
        'dueWallClock',
        'dueWallOffsetMinutes',
        'audience',
      ];
      final sameIntent =
          intentFields.every((field) => prior[field] == candidate[field]);
      if (!sameIntent) {
        return _json(request.response, HttpStatus.conflict, {
          'error': 'commitment_id_conflict',
        });
      }
      await _ensureDurable();
      return _json(request.response, HttpStatus.ok, prior);
    }

    // Provenance is only worth storing if it is TRUE. Validated at admission,
    // because a wall-clock string that does not actually produce this UTC
    // instant is worse than an absent one â€” it looks authoritative to every
    // later reader while being wrong.
    //
    // Deliberately AFTER the identity check. The same malformed body means two
    // different things depending on what Core already holds: against an
    // existing id it is a second, conflicting promise (409, and the stored one
    // is untouched); against a free id it is simply bad input (400). Validating
    // first would collapse both into 400 and let a caller silently believe a
    // rejected re-promise had merely been mistyped.
    if (offsetMinutes is! int) {
      throw const FormatException('commitment_offset_required');
    }
    if (!KaiScheduledCommitment.wallClockMatchesUtc(
      wallClock: wallClock,
      offsetMinutes: offsetMinutes,
      dueAtUtc: dueAt,
    )) {
      throw const FormatException('commitment_provenance_mismatch');
    }

    _commitments[id] = candidate;
    await _persist();
    _json(request.response, HttpStatus.created, candidate);
  }

  void _listCommitments(HttpRequest request) {
    if (_commitmentLedgerUnsupported) {
      return _json(request.response, HttpStatus.conflict, {
        'error': 'commitment_ledger_unsupported',
      });
    }
    final dueOnly = request.uri.queryParameters['due'] == 'true';
    final now = _clock().toUtc();
    final records = <Map<String, dynamic>>[];
    for (final value in _commitments.values) {
      final item = Map<String, dynamic>.from(value as Map);
      if (dueOnly) {
        // ONLY `scheduled` is scheduler work. A dispatched promise is already
        // sitting in a body's inbox waiting to be acknowledged; returning it as
        // due would have the coordinator try to dispatch it a second time.
        if (item['status'] != 'scheduled') continue;
        final next =
            DateTime.tryParse(item['nextEvaluationAt']?.toString() ?? '');
        // Nothing is due before its own persisted evaluation instant â€” that is
        // what makes a quiet-hours deferral survive a restart.
        if (next == null || next.isAfter(now)) continue;
      }
      records.add(item);
    }
    // Core receipt time orders the ledger.
    records.sort((a, b) =>
        a['createdAt'].toString().compareTo(b['createdAt'].toString()));
    _json(request.response, HttpStatus.ok, {'commitments': records});
  }

  /// Atomically link one commitment to one outbound for one exact body.
  ///
  /// Both records move in a single durable write, so a crash cannot leave a
  /// commitment marked dispatched with no envelope, or an envelope with nothing
  /// owed behind it.
  ///
  /// Idempotent: a retry that names the same outbound returns the existing
  /// record rather than minting a second envelope.
  /// Move one scheduled commitment's next evaluation later. Nothing else.
  ///
  /// This is the coordinator's only way to say "not yet" durably. Deferral must
  /// be the narrowest possible operation: it cannot touch the id, persona,
  /// text, due instant, wall provenance, audience, creation time or lifecycle,
  /// because none of those are the scheduler's to change — they are the promise
  /// itself, and the promise is Sadeq's.
  ///
  /// It also cannot pull a commitment EARLIER. A deferral that moved the
  /// instant backwards would let any caller reachable on loopback make a
  /// quiet-hours-deferred reminder eligible immediately, which is the due-time
  /// gate defeated through the side door rather than the front.
  Future<void> _deferCommitment(HttpRequest request, String rawId) async {
    if (_commitmentLedgerUnsupported) {
      return _json(request.response, HttpStatus.conflict, {
        'error': 'commitment_ledger_unsupported',
      });
    }
    final id = Uri.decodeComponent(rawId);
    final existing = _commitments[id];
    if (existing == null) {
      return _json(request.response, HttpStatus.notFound, {
        'error': 'commitment_not_found',
      });
    }

    final body = await _body(request);
    final raw = _requiredString(body, 'nextEvaluationAt');

    // Canonical means EXACTLY what Dart's `toUtc().toIso8601String()` emits.
    // Verified by round-trip rather than by regex, so the definition cannot
    // drift from the one producer everyone actually uses. This rejects a space
    // separator, omitted fractional seconds, and any numeric offset — including
    // `+00:00`, which denotes the same instant but is a second spelling of it,
    // and two spellings mean byte comparison stops working for idempotency.
    final parsed = DateTime.tryParse(raw);
    if (parsed == null || parsed.toUtc().toIso8601String() != raw) {
      throw const FormatException('next_evaluation_not_canonical');
    }
    final requested = parsed.toUtc();

    final item = Map<String, dynamic>.from(existing as Map);
    if (item['status'] != 'scheduled') {
      // A dispatched promise is already out for delivery and an acknowledged
      // one is closed. Rescheduling either would silently reopen work whose
      // outcome is settled.
      return _json(request.response, HttpStatus.conflict, {
        'error': 'commitment_not_scheduled',
      });
    }

    final storedRaw = item['nextEvaluationAt']?.toString() ?? '';
    final stored = DateTime.tryParse(storedRaw)?.toUtc();

    // Idempotency BEFORE the future check, deliberately. A retry of the exact
    // value already stored is the caller repeating itself, and repeating
    // yourself must stay valid even if the instant has since arrived — the
    // alternative is that a slow or retried defer becomes un-retryable at
    // precisely the moment the work matters. This also repairs a prior failed
    // write, per the Brief 013 retry contract.
    if (stored != null && requested == stored) {
      await _ensureDurable();
      return _json(request.response, HttpStatus.ok, item);
    }

    if (stored != null && requested.isBefore(stored)) {
      return _json(request.response, HttpStatus.conflict, {
        'error': 'commitment_evaluation_regression',
      });
    }

    // Core receipt time is authoritative; a caller-supplied `now` is not
    // consulted anywhere on this path.
    if (!requested.isAfter(_clock().toUtc())) {
      throw const FormatException('next_evaluation_not_future');
    }

    item['nextEvaluationAt'] = requested.toIso8601String();
    _commitments[id] = item;
    await _persist();
    _json(request.response, HttpStatus.ok, item);
  }

  /// Is [recorded] the identical delivery a retry is asking for?
  ///
  /// One definition, used by both the collision check and the idempotent
  /// redispatch path, so the two can never drift into disagreeing about what
  /// "the same envelope" means.
  static bool _sameCommitmentEnvelope(
    Map<String, dynamic> recorded, {
    required String commitmentId,
    required String targetBodyId,
    required String toSurface,
    required String? conversationId,
    required Object? text,
  }) =>
      recorded['commitmentId'] == commitmentId &&
      recorded['kind'] == 'completed_work' &&
      recorded['targetBodyId'] == targetBodyId &&
      recorded['toSurface'] == toSurface &&
      recorded['conversationId'] == conversationId &&
      recorded['text'] == text;

  Future<void> _dispatchCommitment(HttpRequest request, String rawId) async {
    if (_commitmentLedgerUnsupported) {
      return _json(request.response, HttpStatus.conflict, {
        'error': 'commitment_ledger_unsupported',
      });
    }
    final id = Uri.decodeComponent(rawId);
    final existing = _commitments[id];
    if (existing == null) {
      return _json(request.response, HttpStatus.notFound, {
        'error': 'commitment_not_found',
      });
    }
    final item = Map<String, dynamic>.from(existing as Map);
    if (item['status'] == 'acknowledged') {
      return _json(request.response, HttpStatus.conflict, {
        'error': 'commitment_already_acknowledged',
      });
    }

    final body = await _body(request);
    final outboundId = _requiredString(body, 'outboundId');
    final targetBodyId = _requiredString(body, 'targetBodyId');
    final toSurface = _requiredString(body, 'toSurface');
    final conversationId = _optionalString(body['conversationId']);

    // v1 work reminders go to the desktop workbench and nowhere else. Messenger
    // is friend-only, and AR/VR have no accepted presentation for this content
    // yet â€” so an unexpected surface is refused rather than attempted.
    if (toSurface != 'desktop') {
      return _json(request.response, HttpStatus.conflict, {
        'error': 'commitment_surface_not_permitted',
      });
    }

    final now = _clock().toUtc();

    // Due-time is a TRUSTED transition, not a caller hint. Without this, any
    // caller able to reach the endpoint could make a promise land early â€”
    // including one deferred by quiet hours moments earlier.
    final nextEvaluationAt =
        DateTime.tryParse(item['nextEvaluationAt']?.toString() ?? '');
    if (item['status'] == 'scheduled' &&
        (nextEvaluationAt == null || nextEvaluationAt.isAfter(now))) {
      return _json(request.response, HttpStatus.conflict, {
        'error': 'commitment_not_yet_due',
      });
    }

    if (item['status'] == 'dispatched') {
      // Idempotency means "this is the SAME delivery, said again" â€” and the
      // commitment record only remembers which outbound and which body. The
      // envelope remembers where it was going to be said. A retry that keeps
      // the outbound id but changes the conversation is a different delivery
      // wearing the first one's name: accepting it would return 200 while the
      // reminder stayed in the original thread, so the caller believes it
      // moved and nothing did.
      final recorded = _outbound[outboundId];
      final sameEnvelope = item['outboundId'] == outboundId &&
          item['targetBodyId'] == targetBodyId &&
          recorded != null &&
          _sameCommitmentEnvelope(
            Map<String, dynamic>.from(recorded as Map),
            commitmentId: id,
            targetBodyId: targetBodyId,
            toSurface: toSurface,
            conversationId: conversationId,
            text: item['text'],
          );
      if (!sameEnvelope) {
        return _json(request.response, HttpStatus.conflict, {
          'error': 'commitment_already_dispatched',
        });
      }
      await _ensureDurable();
      return _json(request.response, HttpStatus.ok, item);
    }
    final expiresAt = now.add(const Duration(hours: 24));
    final envelope = <String, dynamic>{
      'outboundId': outboundId,
      'kind': 'completed_work',
      'fromSurface': 'core',
      'toSurface': toSurface,
      'targetBodyId': targetBodyId,
      'conversationId': conversationId,
      'correlationId': id,
      // The EXACT stored text. No model call sits between due detection and
      // presentation, so what was promised is what is shown.
      'text': item['text'],
      'gesture': 'none',
      'createdAt': now.toIso8601String(),
      'expiresAt': expiresAt.toIso8601String(),
      'status': 'pending',
      'acknowledgedAt': null,
      'acknowledgedBy': null,
      'commitmentId': id,
    };

    // Check the envelope slot BEFORE mutating anything. Brief 012 silently
    // skipped the write when the id was taken and marked the commitment
    // dispatched regardless â€” so an unrelated outbound already occupying that
    // id would have the promise pointing at somebody else's message, and the
    // reminder would never be delivered while looking as though it had been.
    final priorEnvelope = _outbound[outboundId];
    if (priorEnvelope != null) {
      final sameEnvelope = _sameCommitmentEnvelope(
        Map<String, dynamic>.from(priorEnvelope as Map),
        commitmentId: id,
        targetBodyId: targetBodyId,
        toSurface: toSurface,
        conversationId: conversationId,
        text: item['text'],
      );
      if (!sameEnvelope) {
        return _json(request.response, HttpStatus.conflict, {
          'error': 'outbound_id_conflict',
        });
      }
    } else {
      _outbound[outboundId] = envelope;
    }

    item
      ..['status'] = 'dispatched'
      ..['outboundId'] = outboundId
      ..['targetBodyId'] = targetBodyId
      ..['dispatchedAt'] = now.toIso8601String();
    _commitments[id] = item;

    // One write for both. Non-atomic would allow "dispatched, no envelope".
    await _persist();
    _json(request.response, HttpStatus.ok, item);
  }

  /// Move a commitment to acknowledged in the SAME write that acknowledges its
  /// outbound. Called from [_ackOutbound] rather than exposed separately, so a
  /// body cannot mark a promise complete without having accepted the envelope.
  void _linkAcknowledgedCommitment(Map<String, dynamic> outboundItem) {
    final commitmentId = outboundItem['commitmentId']?.toString() ?? '';
    if (commitmentId.isEmpty) return;
    final existing = _commitments[commitmentId];
    if (existing is! Map) return;
    final item = Map<String, dynamic>.from(existing);
    if (item['status'] == 'acknowledged') return;
    item
      ..['status'] = 'acknowledged'
      ..['acknowledgedAt'] = outboundItem['acknowledgedAt']
      ..['nextEvaluationAt'] = null;
    _commitments[commitmentId] = item;
  }

  Map<String, dynamic> get _presence =>
      _state['presence'] as Map<String, dynamic>;
  Map<String, dynamic> get _handoffs =>
      _state['handoffs'] as Map<String, dynamic>;
  Map<String, dynamic> get _outbound =>
      _state['outbound'] as Map<String, dynamic>;
  Map<String, dynamic> get _tasks => _state['tasks'] as Map<String, dynamic>;
  Map<String, dynamic> get _commitments =>
      _state['commitments'] as Map<String, dynamic>;

  /// The only commitment-ledger schema this build understands.
  ///
  /// Versioned separately from Core's own `version` so the ledger can evolve
  /// without forcing a migration of presence, handoffs, outbound or tasks â€”
  /// and so an older build meeting a newer ledger can say so precisely.
  static const commitmentLedgerVersion = 1;

  /// True when the stored ledger is a version this build cannot interpret.
  ///
  /// Retained, never rewritten and never read as empty: silently treating a
  /// future ledger as "no commitments" would drop promises that are still owed
  /// and leave no trace of having done it.
  bool get _commitmentLedgerUnsupported =>
      _state['commitmentLedgerVersion'] != commitmentLedgerVersion;

  Future<Map<String, dynamic>> _body(HttpRequest request) async {
    final text = await utf8.decoder.bind(request).join();
    final decoded = jsonDecode(text);
    if (decoded is! Map) throw const FormatException('json_object_required');
    return Map<String, dynamic>.from(decoded);
  }

  /// Load Core state, preferring the primary and falling back to the backup.
  ///
  /// â”€â”€ The crash window this closes â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  ///
  /// `_persist()` rotates: delete `.bak`, rename primary to `.bak`, rename temp
  /// to primary. A crash between the second and third step leaves NO primary
  /// and one perfectly readable backup â€” the normal, expected result of dying
  /// mid-save.
  ///
  /// The old first line was `if (!await _stateFile.exists()) return
  /// _emptyState()`. An absent primary was read as a first run, so Core started
  /// blank while its whole state sat in `.bak`, and the next save then deleted
  /// that backup. Every commitment, handoff and task gone, with no error.
  ///
  /// Absence of the primary is not emptiness. It is a question the backup can
  /// answer.
  Future<Map<String, dynamic>> _readState() async {
    final primary = await _readStateFile(_stateFile);
    if (primary != null) {
      _primaryWasUnreadable = false;
      // A healthy primary does not excuse ignoring a corrupt backup. Normal
      // rotation deletes `.bak` to make room, so bytes that failed to parse
      // would be destroyed by the very next save â€” the one moment they were
      // still evidence of whatever went wrong. Check even on the happy path.
      _backupWasUnreadable = await _isUnreadable(_backupStateFile);
      return _hydrate(primary);
    }

    // Reached when the primary is absent OR unparseable. Both mean the same
    // thing here: ask the backup.
    _primaryWasUnreadable = await _stateFile.exists();

    final backup = await _readStateFile(_backupStateFile);
    if (backup != null) {
      _recoveredFromBackup = true;
      return _hydrate(backup);
    }

    // Genuinely nothing usable. If bytes are present but unreadable they are
    // retained as evidence and quarantined on the first successful save.
    _backupWasUnreadable = await _backupStateFile.exists();
    // Through _hydrate so a genuine first run stamps `startedAt` from the
    // injected clock, like every other path. _emptyState is a static shape and
    // cannot reach _clock(); routing it here keeps _hydrate the single writer
    // of that field instead of two writers disagreeing about which clock is
    // authoritative.
    return _hydrate(_emptyState());
  }

  /// Present on disk, but not parseable as a Core state map.
  ///
  /// Distinct from absence: absence is a normal first run, unreadable bytes are
  /// an incident.
  static Future<bool> _isUnreadable(File file) async =>
      await file.exists() && await _readStateFile(file) == null;

  static Future<Map<String, dynamic>?> _readStateFile(File file) async {
    try {
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return null;
      return Map<String, dynamic>.from(decoded);
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> _hydrate(Map<String, dynamic> state) {
    state['presence'] = _map(state['presence']);
    state['handoffs'] = _map(state['handoffs']);
    state['outbound'] = _map(state['outbound']);
    state['tasks'] = _map(state['tasks']);
    _migrateCommitmentLedger(state);
    state['startedAt'] ??= _clock().toUtc().toIso8601String();
    state['version'] = 2;
    return state;
  }

  File get _backupStateFile => File('${_stateFile.path}.bak');

  // Recovery obligations, set by [_readState] and consumed by the FIRST
  // successful [_persist]. Cleared only on success, so a save that failed
  // arrives again carrying the same duties.
  bool _primaryWasUnreadable = false;
  bool _backupWasUnreadable = false;
  bool _recoveredFromBackup = false;

  /// Bring a pre-Brief-012 state up to an empty version-1 ledger.
  ///
  /// Additive only. Presence, handoffs, outbound and tasks are not touched, so
  /// an existing Core file keeps every record it had.
  ///
  /// A ledger version this build does not understand is LEFT EXACTLY AS FOUND
  /// and flagged. Rewriting it to empty would silently discard promises that
  /// are still owed; rewriting it to v1 would half-interpret a schema we cannot
  /// read. Neither is recoverable, so the ledger is simply refused instead.
  static void _migrateCommitmentLedger(Map<String, dynamic> state) {
    final declared = state['commitmentLedgerVersion'];
    if (declared == null) {
      state['commitmentLedgerVersion'] = commitmentLedgerVersion;
      state['commitments'] = _map(state['commitments']);
      return;
    }
    if (declared != commitmentLedgerVersion) {
      // Retained verbatim. `_commitmentLedgerUnsupported` makes every
      // commitment endpoint refuse rather than operate on it.
      state['commitments'] = state['commitments'] is Map
          ? Map<String, dynamic>.from(state['commitments'] as Map)
          : <String, dynamic>{};
      return;
    }
    state['commitments'] = _map(state['commitments']);
  }

  /// Serialize this snapshot, and report THIS caller's outcome to THIS caller.
  ///
  /// The returned future is not the tail. Chaining callers onto `_writeTail`
  /// itself made one transient failure permanent: the rejected tail was the
  /// input to every later `.then`, so once a single write failed â€” a locked
  /// file, a full disk, an antivirus scanner holding `.tmp` for a moment â€”
  /// every subsequent save short-circuited to the same old error and Core
  /// silently stopped persisting for the rest of the process lifetime. The
  /// fault would have cleared seconds later; the poisoned chain would not.
  ///
  /// So the tail carries ORDERING and never fails, while each caller gets its
  /// own completer carrying SUCCESS OR FAILURE. A failed save is still fully
  /// visible to the request that caused it (and becomes a 500), the recovery
  /// obligations it did not discharge are still owed, and the next save runs.
  Future<void> _persist() {
    // Encoded synchronously, before chaining: the snapshot must be the state as
    // it was when this caller asked, not as it becomes while queued.
    final snapshot = jsonEncode(_state);
    final sequence = ++_snapshotSequence;
    final result = Completer<void>();
    _writeTail = _writeTail.then((_) async {
      try {
        await _writeSnapshot(snapshot);
        if (sequence > _flushedSequence) _flushedSequence = sequence;
        result.complete();
      } catch (error, stack) {
        result.completeError(error, stack);
      }
    });
    return result.future;
  }

  // Which snapshot was last asked for, and which last reached disk. The tail is
  // sequential, so a gap between them means some applied transition is memory-
  // only. Counters rather than a flag: with a flag, an earlier in-flight save
  // completing would clear the obligation created by a later mutation.
  int _snapshotSequence = 0;
  int _flushedSequence = 0;

  /// Make the transition this response is about to report actually durable.
  ///
  /// Called on the IDEMPOTENT paths — the ones that return 200 for work already
  /// applied. Without it, a failed save opened a silent hole: the caller got
  /// 500 and retried the identical operation, the retry recognised the
  /// transition already in memory and returned 200 without touching the disk,
  /// and a restart then lost the creation, reverted the dispatch, or reopened
  /// an acknowledged promise. The caller had done everything right and was told
  /// twice that the promise was kept.
  ///
  /// Re-persists the CURRENT state, so nothing is recreated or duplicated: the
  /// ids, timestamps, exact text and envelope are whatever the first attempt
  /// already applied. If the disk is still broken this throws again and the
  /// retry fails again, which is the honest answer.
  Future<void> _ensureDurable() async {
    if (_flushedSequence < _snapshotSequence) await _persist();
  }

  /// [_persist] for the housekeeping sweeps that no request is waiting on.
  ///
  /// Lazy expiry marking is a side effect of a read, not the read's purpose. If
  /// its save fails there is nothing to tell the caller — the response is
  /// already correct — and the state is recomputed on the next read anyway. The
  /// error is swallowed here rather than left to become an unhandled async
  /// error that tears down the isolate over a bookkeeping write.
  Future<void> _persistBestEffort() => _persist().catchError((Object error) {
        stderr.writeln('[KaiCore] deferred save failed: $error');
      });

  Future<void> _writeSnapshot(String snapshot) async {
    final temp = File('${_stateFile.path}.tmp');
    final backup = _backupStateFile;
    await temp.writeAsString(snapshot, flush: true);

    // A corrupt backup is moved aside whether or not the primary was readable.
    // On the healthy path the rotation below would otherwise DELETE it.
    if (_backupWasUnreadable && await backup.exists()) {
      await backup.rename(await _quarantinePath(backup));
      _backupWasUnreadable = false;
    }

    if (_primaryWasUnreadable || _recoveredFromBackup) {
      // â”€â”€ First save after a degraded load â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
      //
      // The backup is the last readable copy, so it is not rotated over and not
      // deleted. Corrupt primary bytes move sideways into quarantine.
      if (_primaryWasUnreadable && await _stateFile.exists()) {
        await _stateFile.rename(await _quarantinePath(_stateFile));
      }

      // Install LAST. Until this lands the backup is still the only copy, so a
      // failure above leaves it exactly where it was.
      await temp.rename(_stateFile.path);

      _primaryWasUnreadable = false;
      _recoveredFromBackup = false;
      return;
    }

    // Normal rotation.
    if (await backup.exists()) await backup.delete();
    if (await _stateFile.exists()) await _stateFile.rename(backup.path);
    await temp.rename(_stateFile.path);
  }

  /// A free quarantine path, never colliding with earlier evidence.
  ///
  /// `state.json.corrupt`, then `.corrupt.1`, `.corrupt.2`, â€¦ Lowest free
  /// index, so it is deterministic rather than timestamped. Renaming onto an
  /// existing path throws on Windows, so a collision would make every later
  /// save fail permanently â€” a diagnostic file becoming an outage. Overwriting
  /// would destroy the first incident's evidence instead.
  ///
  /// Unbounded on purpose. Any cap has to end in overwriting somebody's
  /// evidence or refusing to save, and a machine that has produced a thousand
  /// corrupt states is exactly the one whose thousand-and-first still matters.
  static Future<String> _quarantinePath(File file) async {
    final base = '${file.path}.corrupt';
    if (!await File(base).exists()) return base;
    for (var i = 1;; i++) {
      final candidate = '$base.$i';
      if (!await File(candidate).exists()) return candidate;
    }
  }

  // No `startedAt` here on purpose. _hydrate owns that field and stamps it from
  // the injected clock; a second writer using the real wall clock made the
  // install date untestable and disagreed with every other path.
  static Map<String, dynamic> _emptyState() => {
        'version': 2,
        'presence': <String, dynamic>{},
        'handoffs': <String, dynamic>{},
        'outbound': <String, dynamic>{},
        'tasks': <String, dynamic>{},
        'commitmentLedgerVersion': commitmentLedgerVersion,
        'commitments': <String, dynamic>{},
      };

  static Map<String, dynamic> _map(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

  static String _requiredString(Map<String, dynamic> body, String key) {
    final value = body[key]?.toString().trim() ?? '';
    if (value.isEmpty) throw FormatException('${key}_required');
    return value;
  }

  /// A required string stored EXACTLY as sent.
  ///
  /// [_requiredString] trims, which is right for identifiers, personas and
  /// provenance — canonical values where surrounding space is noise and two
  /// spellings of one id would be a bug. It is wrong for a promise.
  ///
  /// A reminder's text is quoted back to Sadeq weeks later, and it is the one
  /// field nothing in this system is allowed to rewrite. Trimming it was a
  /// silent edit: small, invisible, and a direct contradiction of the
  /// byte-for-byte guarantee the whole vertical slice is built on. So `trim()`
  /// is used here ONLY to decide whether anything was said at all — the value
  /// that gets stored is the original, whitespace, line breaks, unicode and
  /// all. The length limit deliberately measures that original too, or a
  /// caller could smuggle 2000 characters past the check and store more.
  ///
  /// Deliberately separate rather than a flag on [_requiredString]: every
  /// other Core field keeps its accepted canonicalization, and the exception
  /// is visible at the one call site that needs it.
  static String _verbatimText(Map<String, dynamic> body, String key) {
    final raw = body[key];
    if (raw is! String) throw FormatException('${key}_required');
    if (raw.trim().isEmpty) throw FormatException('${key}_required');
    return raw;
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
