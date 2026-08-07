library;

import 'dart:async';
import 'dart:io';

import '../ai/ai_service.dart';
import '../embodiment/kai_embodiment_gateway_service.dart';
import 'kai_conversation_request_service.dart';
import 'kai_body_event.dart';
import 'kai_core_client.dart';
import 'kai_core_server.dart';
import 'kai_db.dart';
import 'kai_global_presence_service.dart';
import 'kai_operations_journal.dart';
import 'kai_proactive_service.dart';
import 'kai_surface_context.dart';
import 'kai_taskbar_heartbeat.dart';

const String kKaiCentralPersona = 'truekai';
const String kKaiCentralModel = 'gpt-5.5';
const String kKaiHeadlessWorkerId = 'central-headless';

bool isTransientConversationFailure(Object error) {
  if (error is TimeoutException || error is SocketException) return true;
  final text = error.toString().toLowerCase();
  return text.contains('timeout') ||
      text.contains('connection') ||
      text.contains('socket') ||
      text.contains('network') ||
      text.contains('temporarily') ||
      text.contains('http 408') ||
      text.contains('http 429') ||
      text.contains('http 500') ||
      text.contains('http 502') ||
      text.contains('http 503') ||
      text.contains('http 504');
}

Duration kaiRetryDelay(int attemptCount) {
  final seconds = switch (attemptCount) {
    <= 0 => 1,
    1 => 2,
    _ => 5,
  };
  return Duration(seconds: seconds);
}

int latestUserActivityMillis(Object? value) {
  if (value is! Map) return 0;
  var latest = 0;
  for (final raw in value.values) {
    if (raw is! Map) continue;
    final user = raw['userMessage']?.toString().trim() ?? '';
    final timestamp = (raw['timestamp'] as num?)?.toInt() ?? 0;
    if (user.isNotEmpty && timestamp > latest) latest = timestamp;
  }
  return latest;
}

/// Central Kai's non-visual runtime.
///
/// This runs in a hidden Flutter engine because Firebase/Auth/secure-storage
/// plugins still need an engine, but it mounts no desktop UI. Closing the room
/// cannot stop Messenger, presence, VR/AR gateways or bounded check-ins.
class KaiHeadlessCoordinator {
  KaiHeadlessCoordinator._();
  static final KaiHeadlessCoordinator instance = KaiHeadlessCoordinator._();

  final AIService _ai = AIService();
  final KaiConversationRequestService _requests =
      KaiConversationRequestService.instance;
  final KaiCoreClient _core = KaiCoreClient();
  final KaiOperationsJournal _journal = KaiOperationsJournal();
  KaiCoreServer? _embeddedCore;

  StreamSubscription<List<KaiConversationRequest>>? _requestSub;
  StreamSubscription<KaiGlobalPresenceSnapshot>? _presenceSub;
  StreamSubscription<KaiNudge>? _proactiveSub;
  final List<StreamSubscription<KaiEvent>> _activitySubs = [];
  final Map<String, int> _lastUserActivityBySurface = {};
  KaiCorePresenceHeartbeat? _heartbeat;
  List<KaiConversationRequest> _queue = const [];
  bool _busy = false;
  bool _proactiveBusy = false;
  bool _started = false;
  KaiCoreHeartbeatPhase? _lastHeartbeatPhase;
  KaiGlobalPresenceSnapshot _globalPresence =
      const KaiGlobalPresenceSnapshot.connecting();
  Timer? _bootstrapRetryTimer;
  Timer? _bodyMirrorTimer;
  bool _bodyMirrorBusy = false;
  bool _coreRecoveryBusy = false;

  Future<void> start({bool recovered = false}) async {
    if (_started) return;
    _started = true;
    await _journal.record(
      recovered ? 'coordinator_recovered' : 'coordinator_started',
      details: {'pid': pid, 'workerId': kKaiHeadlessWorkerId},
    );

    final presence = KaiGlobalPresenceService.instance;
    _presenceSub = presence.snapshots.listen(_applyPresence, onError: (error) {
      unawaited(_journal.record(
        'presence_stream_error',
        severity: 'warning',
        details: {'error': error},
      ));
    });
    await _bootstrapPresenceAndCore();

    await _startEmbodimentGateways();
    _startBodyMirror();

    _requestSub = _requests.watchOpenRequests(kKaiCentralPersona).listen(
      (requests) {
        _queue = requests;
        unawaited(_drain());
      },
      onError: (error) {
        unawaited(_journal.record(
          'request_stream_unavailable',
          severity: 'warning',
          details: {'error': error},
        ));
      },
    );

    // Proactive friend messages move with the coordinator. Tool-bearing nudges
    // remain parked for an attended desktop session.
    KaiProactiveService.instance.start(kKaiCentralPersona);
    _watchCrossProcessActivity();
    _proactiveSub = KaiProactiveService.instance.nudges.listen(
      (nudge) => unawaited(_deliverProactiveNudge(nudge)),
    );

    await _journal.record('coordinator_ready');
  }

  void _startBodyMirror() {
    unawaited(_mirrorEmbodiedBodies());
    _bodyMirrorTimer ??= Timer.periodic(
      const Duration(seconds: 20),
      (_) => unawaited(_mirrorEmbodiedBodies()),
    );
  }

  Future<void> _mirrorEmbodiedBodies() async {
    if (_bodyMirrorBusy) return;
    _bodyMirrorBusy = true;
    try {
      final active = await _core.activeDevices();
      await KaiGlobalPresenceService.instance.mirrorCoreBodies(active);
    } catch (error) {
      await _journal.record(
        'body_mirror_unavailable',
        severity: 'warning',
        details: {'error': error},
      );
    } finally {
      _bodyMirrorBusy = false;
    }
  }

  void _watchCrossProcessActivity() {
    for (final surface in const ['in_person', 'messenger']) {
      final sub = KaiDb.instance
          .ref('conversations/$kKaiCentralPersona/$surface')
          .limitToLast(3)
          .onValue
          .listen((event) {
        final latest = latestUserActivityMillis(event.snapshot.value);
        final previous = _lastUserActivityBySurface[surface];
        _lastUserActivityBySurface[surface] = latest;
        if (previous != null && latest > previous) {
          KaiProactiveService.instance.noteActivity();
          unawaited(_journal.record(
            'user_activity_observed',
            surface: surface,
          ));
        }
      }, onError: (error) {
        unawaited(_journal.record(
          'activity_stream_unavailable',
          severity: 'warning',
          surface: surface,
          details: {'error': error},
        ));
      });
      _activitySubs.add(sub);
    }
  }

  Future<void> _bootstrapPresenceAndCore() async {
    try {
      final presence = KaiGlobalPresenceService.instance;
      await presence.startBody(
        surface: 'desktop',
        canBootstrapOwner: true,
        // The coordinator is Kai's heart, not a visible desktop body. Publishing
        // it here made the constellation claim the room was open when it wasn't.
        publishBodyLease: false,
        foreground: false,
        status: 'coordinating',
      );
      final coreAvailable = await _ensureCoreAvailable();
      if (!coreAvailable) throw StateError('KaiCore sidecar unavailable');
      _heartbeat ??= KaiCorePresenceHeartbeat(
        client: _core,
        deviceId: 'coordinator-${Platform.localHostname}',
        // Core surfaces describe embodiments, not process roles. The distinct
        // device/session IDs carry the headless coordinator identity.
        surface: 'desktop',
        sessionId: 'headless-$pid-${DateTime.now().microsecondsSinceEpoch}',
        onStatus: _applyHeartbeat,
      )..start();
      _bootstrapRetryTimer?.cancel();
      _bootstrapRetryTimer = null;
    } catch (error) {
      await _journal.record(
        'coordinator_bootstrap_deferred',
        severity: 'warning',
        details: {'error': error},
      );
      _bootstrapRetryTimer ??= Timer(const Duration(seconds: 5), () {
        _bootstrapRetryTimer = null;
        unawaited(_bootstrapPresenceAndCore());
      });
    }
  }

  Future<bool> _ensureCoreAvailable() async {
    if (await _core.isHealthy()) return true;
    if (_embeddedCore != null) return false;

    final local = Platform.environment['LOCALAPPDATA'];
    final root =
        local == null || local.trim().isEmpty ? Directory.current.path : local;
    final server = KaiCoreServer(
      dataDirectory: Directory(
        '$root${Platform.pathSeparator}Homecoming${Platform.pathSeparator}'
        'KaiCore',
      ),
      port: 8790,
    );
    try {
      await server.start();
      _embeddedCore = server;
      await _journal.record(
        'embedded_core_started',
        details: {'port': 8790, 'version': 2},
      );
      return await _core.isHealthy();
    } catch (error) {
      // Another process may have won the port race. Accept it only if it really
      // answers the Core health contract.
      if (await _core.isHealthy()) return true;
      await _journal.record(
        'embedded_core_start_failed',
        severity: 'error',
        details: {'error': error},
      );
      return false;
    }
  }

  Future<void> _startEmbodimentGateways() async {
    for (final channel in <(KaiEmbodimentGatewayService, KaiSurface, int)>[
      (
        KaiEmbodimentGatewayService.vr,
        KaiSurface.vr,
        KaiEmbodimentGatewayService.defaultPort,
      ),
      (
        KaiEmbodimentGatewayService.ar,
        KaiSurface.ar,
        KaiEmbodimentGatewayService.defaultArPort,
      ),
    ]) {
      try {
        await channel.$1.start(
          ai: _ai,
          model: kKaiCentralModel,
          channelSurface: channel.$2,
          port: channel.$3,
          allowUnauthenticatedLoopback: true,
        );
        await _journal.record(
          'embodiment_gateway_started',
          surface: channel.$2.name,
          details: {'port': channel.$3},
        );
      } catch (error) {
        await _journal.record(
          'embodiment_gateway_failed',
          severity: 'warning',
          surface: channel.$2.name,
          details: {'error': error, 'port': channel.$3},
        );
      }
    }
  }

  void _applyHeartbeat(KaiCoreHeartbeatStatus status) {
    unawaited(KaiGlobalPresenceService.instance.setCoordinatorAwake(
      status.phase == KaiCoreHeartbeatPhase.healthy,
    ));
    if (_lastHeartbeatPhase == status.phase) return;
    _lastHeartbeatPhase = status.phase;
    unawaited(_journal.record(
      'core_heartbeat_${status.phase.name}',
      severity: status.phase == KaiCoreHeartbeatPhase.offline
          ? 'error'
          : status.phase == KaiCoreHeartbeatPhase.reconnecting
              ? 'warning'
              : 'info',
      details: {'failures': status.consecutiveFailures},
    ));
    if (status.phase == KaiCoreHeartbeatPhase.reconnecting ||
        status.phase == KaiCoreHeartbeatPhase.offline) {
      unawaited(_recoverCore());
    }
  }

  Future<void> _recoverCore() async {
    if (_coreRecoveryBusy) return;
    _coreRecoveryBusy = true;
    try {
      await _journal.record('core_recovery_started', severity: 'warning');
      final recovered = await _ensureCoreAvailable();
      if (!recovered) throw StateError('KaiCore could not be restarted');
      await _heartbeat?.beat();
      await _journal.record('core_recovery_completed');
    } catch (error) {
      await _journal.record(
        'core_recovery_failed',
        severity: 'error',
        details: {'error': error},
      );
    } finally {
      _coreRecoveryBusy = false;
    }
  }

  void _applyPresence(KaiGlobalPresenceSnapshot snapshot) {
    _globalPresence = snapshot;
    final phase = !snapshot.connected
        ? KaiCoreHeartbeatPhase.reconnecting
        : snapshot.isAwake
            ? KaiCoreHeartbeatPhase.healthy
            : KaiCoreHeartbeatPhase.offline;
    unawaited(KaiTaskbarHeartbeat.setStatus(KaiCoreHeartbeatStatus(
      phase: phase,
      lastSuccessAt: snapshot.observedAt,
    )));
  }

  Future<void> _drain() async {
    if (_busy || _queue.isEmpty) return;
    _busy = true;
    try {
      while (_queue.isNotEmpty) {
        final request = _queue.first;
        _queue = _queue
            .where((item) => item.id != request.id)
            .toList(growable: false);
        await _process(request);
      }
    } finally {
      _busy = false;
      if (_queue.isNotEmpty) unawaited(_drain());
    }
  }

  Future<void> _process(KaiConversationRequest request) async {
    final started = DateTime.now().toUtc();
    final canonical =
        KaiConversationRequestService.canonicalConversationIdForSurface(
      request.sourceSurface,
    );
    if (canonical == null || !request.hasCanonicalRoute) {
      await _requests.failRequest(
        kKaiCentralPersona,
        request.id,
        error: 'Rejected non-canonical route',
      );
      await _journal.record(
        'request_rejected',
        severity: 'warning',
        requestId: request.id,
        surface: request.sourceSurface,
      );
      return;
    }

    if (!await _core.isHealthy()) {
      await _journal.record(
        'request_deferred_core_unavailable',
        severity: 'warning',
        requestId: request.id,
        surface: request.sourceSurface,
      );
      await Future<void>.delayed(const Duration(seconds: 2));
      _requeueLocally(request);
      return;
    }

    final nextAttempt = request.attemptCount + 1;
    final runtimeTaskId = 'conversation-request-${request.id}-run-'
        '${DateTime.now().microsecondsSinceEpoch}';
    KaiConversationRequest? claimed;
    try {
      await _core.enqueueTask(
        taskId: runtimeTaskId,
        lane: 'conversation',
        kind: 'conversation_turn',
        sourceSurface: request.sourceSurface,
        conversationId: canonical,
        payload: {
          'requestId': request.id,
          'replyCeiling': request.replyCeiling,
        },
      );
      await _core.claimTask(
        runtimeTaskId,
        workerId: kKaiHeadlessWorkerId,
        lease: const Duration(minutes: 2),
      );
      claimed = await _requests.claimRequest(
        kKaiCentralPersona,
        request.id,
        workerId: kKaiHeadlessWorkerId,
        runtimeTaskId: runtimeTaskId,
        lease: const Duration(minutes: 2),
      );
      if (claimed == null) {
        await _failRuntime(runtimeTaskId, 'Request no longer claimable');
        return;
      }
      KaiProactiveService.instance.noteActivity();
      await _journal.record(
        'request_claimed',
        requestId: request.id,
        surface: request.sourceSurface,
        details: {'attempt': claimed.attemptCount, 'model': claimed.model},
      );

      final modelStarted = DateTime.now().toUtc();
      await _journal.record(
        'model_started',
        requestId: request.id,
        surface: request.sourceSurface,
      );
      final response = await _ai
          .sendMessage(
            text: claimed.text,
            personaId: kKaiCentralPersona,
            model: claimed.model.isEmpty ? kKaiCentralModel : claimed.model,
            conversationSurfaceId: canonical,
            surfaceContext: KaiSurfaceContext.messenger,
            replyCeiling: claimed.replyCeiling,
            onProgress: (_) {
              unawaited(_renew(runtimeTaskId, request.id));
            },
          )
          .timeout(const Duration(seconds: 60));
      final reply = response.reply.trim();
      if (reply.isEmpty || reply == '(no reply)') {
        throw StateError('Central Kai returned an empty reply');
      }
      await _journal.record(
        'model_completed',
        requestId: request.id,
        surface: request.sourceSurface,
        duration: DateTime.now().toUtc().difference(modelStarted),
      );
      await _core.completeTask(
        runtimeTaskId,
        workerId: kKaiHeadlessWorkerId,
        result: {'replyCharacters': reply.length},
      );
      await _requests.completeRequest(
        kKaiCentralPersona,
        request.id,
        reply: reply,
      );
      await _journal.record(
        'request_completed',
        requestId: request.id,
        surface: request.sourceSurface,
        duration: DateTime.now().toUtc().difference(started),
        details: {
          'attempt': claimed.attemptCount,
          'replyCharacters': reply.length,
        },
      );
    } catch (error) {
      final attempt = claimed?.attemptCount ?? nextAttempt;
      final retry = isTransientConversationFailure(error) && attempt < 3;
      await _failRuntime(runtimeTaskId, error.toString());
      if (retry) {
        await _requests.requeueRequest(
          kKaiCentralPersona,
          request.id,
          error: error.toString(),
        );
        await _journal.record(
          'request_retry_scheduled',
          severity: 'warning',
          requestId: request.id,
          surface: request.sourceSurface,
          details: {'attempt': attempt, 'error': error},
        );
        await Future<void>.delayed(kaiRetryDelay(attempt));
      } else {
        await _requests.failRequest(
          kKaiCentralPersona,
          request.id,
          error: error.toString(),
        );
        await _journal.record(
          'request_failed',
          severity: 'error',
          requestId: request.id,
          surface: request.sourceSurface,
          duration: DateTime.now().toUtc().difference(started),
          details: {'attempt': attempt, 'error': error},
        );
      }
    }
  }

  void _requeueLocally(KaiConversationRequest request) {
    if (_queue.any((item) => item.id == request.id)) return;
    _queue = [..._queue, request]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    unawaited(_drain());
  }

  Future<void> _renew(String runtimeTaskId, String requestId) async {
    try {
      await Future.wait([
        _core.renewTaskLease(
          runtimeTaskId,
          workerId: kKaiHeadlessWorkerId,
          lease: const Duration(minutes: 2),
        ),
        _requests.renewClaim(
          kKaiCentralPersona,
          requestId,
          workerId: kKaiHeadlessWorkerId,
          lease: const Duration(minutes: 2),
        ),
      ]);
    } catch (_) {}
  }

  Future<void> _failRuntime(
    String taskId,
    String error,
  ) async {
    try {
      await _core.failTask(
        taskId,
        workerId: kKaiHeadlessWorkerId,
        error: error,
        // Firebase owns the retry and creates a fresh runtime task. Requeueing
        // this task too would leave an orphan competing in Core's lane.
        retry: false,
      );
    } catch (_) {}
  }

  Future<void> _deliverProactiveNudge(KaiNudge nudge) async {
    if (_busy || _proactiveBusy) return;
    if (nudge.wantsHands) {
      await _journal.record(
        'proactive_work_parked',
        details: {'kind': nudge.kind.name},
      );
      return;
    }
    _proactiveBusy = true;
    final started = DateTime.now().toUtc();
    try {
      final candidates = _globalPresence.bodies.map((body) {
        final conversationSurface = body.surface == 'messenger'
            ? 'messenger'
            : body.surface == 'desktop'
                ? 'in_person'
                : body.surface;
        final observedActivity =
            _lastUserActivityBySurface[conversationSurface] ?? 0;
        return KaiBodyRouteCandidate(
          bodyId: body.bodyId,
          surface: body.surface,
          lastUserActivityAt: body.lastUserActivityAt ??
              DateTime.fromMillisecondsSinceEpoch(observedActivity,
                  isUtc: true),
          foreground: body.foreground,
          // Until Unity has an outbound inbox, only visible chat bodies may be
          // selected. This prevents a proactive line from being "delivered" to
          // a headset that has no receiver and silently disappearing.
          allowsFriendConversation:
              body.surface == 'messenger' || body.surface == 'desktop',
        );
      });
      final route = routeKaiOutput(
        kind: KaiOutboundKind.proactiveFriend,
        candidates: candidates,
      );
      if (route.storeForLater) {
        await _journal.record(
          'proactive_parked_no_body',
          details: {'kind': nudge.kind.name, 'reason': route.reason},
        );
        return;
      }
      final body = _globalPresence.bodies.firstWhere(
        (candidate) => candidate.bodyId == route.bodyId,
      );
      final targetSurface =
          body.surface == 'messenger' ? 'messenger' : 'in_person';
      final context = body.surface == 'messenger'
          ? KaiSurfaceContext.messenger
          : KaiSurfaceContext.desktop.copyWith(goggles: KaiGoggles.off);
      final response = await _ai
          .sendMessage(
            text: nudge.seed,
            personaId: kKaiCentralPersona,
            model: kKaiCentralModel,
            conversationSurfaceId: targetSurface,
            surfaceContext: context,
            replyCeiling: 90,
            useMemory: false,
            useWebSearch: false,
            saveUserMessage: false,
            saveAssistantReply: true,
            source: 'proactive',
          )
          .timeout(const Duration(seconds: 45));
      final delivered = response.reply.trim().isNotEmpty &&
          response.reply.trim() != '(no reply)';
      await _journal.record(
        delivered ? 'proactive_delivered' : 'proactive_empty',
        severity: delivered ? 'info' : 'warning',
        surface: body.surface,
        duration: DateTime.now().toUtc().difference(started),
        details: {
          'kind': nudge.kind.name,
          'bodyId': body.bodyId,
          'route': route.reason,
        },
      );
    } catch (error) {
      await _journal.record(
        'proactive_failed',
        severity: 'warning',
        surface: 'central',
        details: {'kind': nudge.kind.name, 'error': error},
      );
    } finally {
      _proactiveBusy = false;
    }
  }
}
