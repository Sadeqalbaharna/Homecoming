library;

import 'dart:async';
import 'dart:io';

import '../ai/ai_service.dart';
import '../attention/kai_attention_engine.dart';
import '../attention/kai_proactive_attention_queue.dart';
import '../attention/kai_proactive_attention_store.dart';
import '../embodiment/kai_embodiment_gateway_service.dart';
import 'kai_conversation_request_service.dart';
import 'kai_body_event.dart';
import 'conversation_store_service.dart';
import 'kai_core_client.dart';
import 'kai_due_commitment_loop.dart';
import 'kai_due_commitment_scheduler.dart';
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

/// Proactive speech is generated from the admitted nudge only.
///
/// Loading the ordinary room transcript here creates an assistant-only echo
/// chamber: each generic check-in sees Kai's previous proactive reply and
/// paraphrases its stale subject again. The nudge already carries the approved
/// topic and the live personality/mood prompt still supplies Kai's voice.
const int kKaiProactiveContextTurns = 0;

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
  final KaiProactiveAttentionQueue _proactiveAttention =
      KaiProactiveAttentionQueue();
  final KaiProactiveAttentionStore _attentionStore =
      KaiProactiveAttentionStore();
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
  Timer? _attentionTimer;
  bool _bodyMirrorBusy = false;
  bool _coreRecoveryBusy = false;
  Future<void>? _gracefulStopFuture;

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

    // HYDRATE FIRST. Before the nudge subscription exists and before the timer
    // can drain, or a restart would evaluate an empty queue, hand Kai six fresh
    // nudges, and re-deliver something he already said.
    await _hydrateProactiveAttention();

    // Proactive friend messages move with the coordinator. Tool-bearing nudges
    // remain parked for an attended desktop session.
    KaiProactiveService.instance.start(kKaiCentralPersona);
    _watchCrossProcessActivity();
    _proactiveSub = KaiProactiveService.instance.nudges.listen(
      (nudge) => unawaited(_enqueueProactiveNudge(nudge)),
    );
    _attentionTimer ??= Timer.periodic(
      const Duration(seconds: 20),
      (_) => unawaited(_drainProactiveAttention()),
    );

    // Due reminders get their OWN loop, not a share of the proactive timer.
    // They carry no model call and their lateness is the whole failure mode,
    // so they must not inherit conversation work's pacing or its busy flag.
    // The loop owns its initial drain, so there is nothing to kick here.
    _dueLoop.start();

    await _journal.record('coordinator_ready');
  }

  /// The due-commitment loop: Core → attention decision → dispatch or defer.
  ///
  /// Lifecycle and policy are separate objects on purpose. The loop decides
  /// WHEN — initial drain, periodic tick, presence wake, shutdown — and the
  /// scheduler it builds decides WHAT. Both are the real production objects
  /// the tests drive; neither is reimplemented in a harness.
  late final KaiDueCommitmentLoop _dueLoop = KaiDueCommitmentLoop(
    createScheduler: (isActive) => KaiDueCommitmentScheduler(
      client: _core,
      presence: () => _globalPresence,
      now: DateTime.now,
      quietHours: kKaiCoordinatorQuietHours,
      journal: (event, {severity = 'info', details = const {}}) =>
          _journal.record(event,
              component: 'due_commitments',
              severity: severity,
              details: details),
      // Authorization comes from the loop, so a drain suspended across a
      // shutdown cannot resume and write to Core.
      isActive: isActive,
    ),
  );

  /// Stop timers and subscriptions so nothing fires after shutdown.
  ///
  /// The coordinator previously had no teardown at all: every timer and stream
  /// outlived it. That is survivable in a process that only ever exits, but it
  /// means a test — or a restart inside one process — leaves callbacks running
  /// that can still reach Core and mutate a promise.
  Future<void> stop() async {
    _started = false;
    // Awaited, not just cancelled: this is the one subsystem that can still
    // mutate a durable promise after its trigger is gone.
    await _dueLoop.stop();
    _attentionTimer?.cancel();
    _attentionTimer = null;
    _bodyMirrorTimer?.cancel();
    _bodyMirrorTimer = null;
    _bootstrapRetryTimer?.cancel();
    _bootstrapRetryTimer = null;
    _heartbeat?.stop();
    _heartbeat = null;
    await _presenceSub?.cancel();
    _presenceSub = null;
    await _requestSub?.cancel();
    _requestSub = null;
    await _proactiveSub?.cancel();
    _proactiveSub = null;
    for (final sub in _activitySubs) {
      await sub.cancel();
    }
    _activitySubs.clear();
    KaiProactiveService.instance.stop();
    await _journal.record('coordinator_stopped');
  }

  /// Drain every coordinator-owned writer before the native runner exits.
  ///
  /// This is deliberately separate from ordinary widget/process disposal. The
  /// authenticated local shutdown seam is the only production caller, and the
  /// cached future makes simultaneous accepted requests idempotent.
  Future<void> gracefulStop() => _gracefulStopFuture ??= _performGracefulStop();

  Future<void> _performGracefulStop() async {
    await stop();
    await KaiEmbodimentGatewayService.vr.stop();
    await KaiEmbodimentGatewayService.ar.stop();
    final embeddedCore = _embeddedCore;
    _embeddedCore = null;
    if (embeddedCore != null) await embeddedCore.stop();
    await _journal.flush();
  }

  Future<void> auditShutdownEvent(
    String event, {
    String severity = 'info',
    Map<String, Object?> details = const {},
  }) =>
      _journal.record(
        event,
        component: 'graceful_shutdown',
        severity: severity,
        details: details,
      );

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
        // This is the only process allowed to mutate Kai's central lease.
        // Visible desktop/mobile/VR/AR bodies publish their own leases only.
        managesCoordinatorLease: true,
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
    if (_proactiveAttention.pending.isNotEmpty) {
      unawaited(_drainProactiveAttention());
    }
    // A desktop that just came back is the reason a waiting reminder can
    // finally be shown, so it wakes the drain rather than costing up to a
    // whole timer interval. Presence churn that adds no eligible body — a
    // phone reconnecting, a lease renewing — returns false and creates
    // nothing.
    unawaited(_dueLoop.onPresence(snapshot));
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

  Future<void> _enqueueProactiveNudge(KaiNudge nudge) async {
    if (nudge.wantsHands) {
      await _journal.record(
        'proactive_work_parked',
        details: {'kind': nudge.kind.name},
      );
      return;
    }

    final receivedAt = DateTime.now().toUtc();
    final pending = _proactiveAttention.enqueue(
      nudge,
      receivedAt: receivedAt,
    );
    await _persistProactiveAttention();
    await _journal.record(
      'attention_event_received',
      requestId: pending.event.eventId,
      details: {
        'kind': pending.event.kind.name,
        'nudgeKind': nudge.kind.name,
        'receivedAt': receivedAt,
      },
    );
    await _drainProactiveAttention();
  }

  List<KaiBodyRouteCandidate> _attentionCandidates() =>
      _globalPresence.bodies.map((body) {
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
              DateTime.fromMillisecondsSinceEpoch(
                observedActivity,
                isUtc: true,
              ),
          foreground: body.foreground,
          allowsFriendConversation: const {
            'messenger',
            'desktop',
            'vr',
            'ar',
          }.contains(body.surface),
        );
      }).toList(growable: false);

  /// Load durable attention state, or start honestly empty.
  ///
  /// Never throws. A coordinator that will not start because one JSON file is
  /// unreadable is worse than a coordinator that starts having forgotten what
  /// it was waiting to say — so a degraded load is journalled, not fatal.
  Future<void> _hydrateProactiveAttention() async {
    try {
      final snapshot = await _attentionStore.load();
      if (snapshot != null) {
        _proactiveAttention.restore(snapshot);
        await _journal.record(
          _attentionStore.lastLoadUsedBackup
              ? 'attention_state_recovered_from_backup'
              : 'attention_state_loaded',
          severity: _attentionStore.lastLoadUsedBackup ? 'warning' : 'info',
          // Counts only. The seed lives in the state file because resumption
          // needs it; it must never reach the operations journal.
          details: {
            'pending': _proactiveAttention.pending.length,
            'deliveriesUsed': _proactiveAttention.deliveriesUsed,
          },
        );
        return;
      }

      // Each remaining outcome gets its own record. Brief 008 mapped an
      // unsupported version onto `attention_state_loaded`, so a build reading
      // state it could not understand reported a successful start.
      switch (_attentionStore.lastLoadStatus) {
        case KaiAttentionLoadStatus.unsupportedVersion:
          await _journal.record(
            'attention_state_unsupported_version',
            severity: 'warning',
            details: const {'startedEmpty': true, 'evidenceRetained': true},
          );
          break;
        case KaiAttentionLoadStatus.corrupt:
          await _journal.record(
            'attention_state_unreadable',
            severity: 'warning',
            details: const {'startedEmpty': true, 'evidenceRetained': true},
          );
          break;
        case KaiAttentionLoadStatus.absent:
          // A first run is not an incident.
          break;
        case KaiAttentionLoadStatus.loaded:
        case KaiAttentionLoadStatus.recoveredFromBackup:
          break;
      }
    } catch (error) {
      await _journal.record(
        'attention_state_load_failed',
        severity: 'warning',
        details: {'error': error.toString()},
      );
    }
  }

  /// Persist after any queue mutation. An extra write after a read-only
  /// evaluation is harmless; a missed mutation is not, so this is called on
  /// every path rather than only where state provably changed.
  Future<void> _persistProactiveAttention() async {
    try {
      await _attentionStore.save(_proactiveAttention.snapshot());
    } catch (error) {
      await _journal.record(
        'attention_state_persist_failed',
        severity: 'warning',
        details: {'error': error.toString()},
      );
    }
  }

  Future<void> _drainProactiveAttention() async {
    // Unlike the old path, contention does not discard the event. It is already
    // queued and the bounded timer will evaluate it again.
    if (_busy || _proactiveBusy) return;
    final revisionBefore = _proactiveAttention.revision;
    final dispatch = _proactiveAttention.evaluate(
      now: DateTime.now().toUtc(),
      candidates: _attentionCandidates(),
    );
    // A null dispatch is NOT a no-op. evaluate() resets the Bahrain budget day
    // before it checks whether anything is due, so a midnight rollover with
    // everything blocked mutates state and then returns early. Brief 008
    // returned here without writing, and a restart after midnight restored
    // yesterday's exhausted budget.
    //
    // Keyed on the revision so an idle 20-second timer still writes nothing.
    if (_proactiveAttention.revision != revisionBefore) {
      await _persistProactiveAttention();
    }
    if (dispatch == null) return;

    final decision = dispatch.decision;
    await _journal.record(
      'attention_decision',
      requestId: decision.eventId,
      details: decision.toJson(),
    );
    switch (decision.outcome) {
      case KaiAttentionOutcome.deliverNow:
        break;
      case KaiAttentionOutcome.deferUntil:
      case KaiAttentionOutcome.storeForLater:
      case KaiAttentionOutcome.discardDuplicate:
      case KaiAttentionOutcome.discardExpired:
        return;
    }

    _proactiveBusy = true;
    final started = DateTime.now().toUtc();
    try {
      final body = _globalPresence.bodies.firstWhere(
        (candidate) => candidate.bodyId == decision.bodyId,
      );
      final nudge = dispatch.pending.nudge;
      final embodied = body.surface == 'vr' || body.surface == 'ar';
      final targetSurface = switch (body.surface) {
        'messenger' => 'messenger',
        'desktop' => 'in_person',
        'vr' => 'vr_shack',
        _ => 'ar',
      };
      final context = switch (body.surface) {
        'messenger' => KaiSurfaceContext.messenger,
        'desktop' =>
          KaiSurfaceContext.desktop.copyWith(goggles: KaiGoggles.off),
        'vr' => KaiSurfaceContext.vr(
            worldId: 'vr_shack',
            deviceId: body.deviceId,
            sessionId: body.sessionId,
          ),
        _ => KaiSurfaceContext.ar.copyWith(
            deviceId: body.deviceId,
            sessionId: body.sessionId,
          ),
      };
      final response = await _ai
          .sendMessage(
            text: nudge.seed,
            personaId: kKaiCentralPersona,
            model: kKaiCentralModel,
            ctxTurns: kKaiProactiveContextTurns,
            conversationSurfaceId: targetSurface,
            surfaceContext: context,
            replyCeiling: 90,
            useMemory: false,
            useWebSearch: false,
            saveUserMessage: false,
            // No proactive reply is persisted inside AIService. The final
            // delivery boundary below re-checks quiet hours first, then commits
            // the body/transcript in that order.
            saveAssistantReply: false,
            source: 'proactive',
          )
          .timeout(const Duration(seconds: 45));
      final deliveryAt = DateTime.now().toUtc();
      if (_proactiveAttention.deferForQuietHours(
        dispatch.pending.event.eventId,
        now: deliveryAt,
      )) {
        await _persistProactiveAttention();
        await _journal.record(
          'proactive_delivery_deferred_quiet_hours',
          requestId: dispatch.pending.event.eventId,
          surface: body.surface,
          details: {
            'eventId': dispatch.pending.event.eventId,
            'notBefore': _proactiveAttention.pending
                .firstWhere((item) =>
                    item.event.eventId == dispatch.pending.event.eventId)
                .notBefore,
          },
        );
        return;
      }
      final delivered = response.reply.trim().isNotEmpty &&
          response.reply.trim() != '(no reply)';
      if (delivered && embodied) {
        final outboundId = dispatch.pending.event.eventId;
        await _core.createOutbound(
          outboundId: outboundId,
          kind: 'proactive_friend',
          fromSurface: 'central',
          toSurface: body.surface,
          targetBodyId: body.bodyId,
          conversationId: targetSurface,
          correlationId: dispatch.pending.event.correlationId,
          text: response.reply.trim(),
          expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 10)),
        );
      }
      if (delivered) {
        await ConversationStoreService().saveTurn(
          personaId: kKaiCentralPersona,
          surfaceId: targetSurface,
          aiReply: response.reply.trim(),
          personalityDeltas: const {},
        );
      }
      _proactiveAttention.complete(
        dispatch.pending.event.eventId,
        now: DateTime.now().toUtc(),
      );
      // Persisted BEFORE the journal entry: the processed-ID ledger and the
      // budget count are what stop a redelivery after a crash, so they should
      // reach disk before anything else about this delivery does.
      await _persistProactiveAttention();
      await _journal.record(
        delivered ? 'proactive_delivered' : 'proactive_empty',
        severity: delivered ? 'info' : 'warning',
        surface: body.surface,
        duration: DateTime.now().toUtc().difference(started),
        details: {
          'kind': nudge.kind.name,
          'bodyId': body.bodyId,
          'route': decision.reasonCode,
          'eventId': dispatch.pending.event.eventId,
        },
      );
    } catch (error) {
      _proactiveAttention.fail(
        dispatch.pending.event.eventId,
        now: DateTime.now().toUtc(),
      );
      await _persistProactiveAttention();
      await _journal.record(
        'proactive_failed',
        severity: 'warning',
        surface: 'central',
        requestId: dispatch.pending.event.eventId,
        details: {
          'kind': dispatch.pending.nudge.kind.name,
          'error': error,
          'retryInMs': _proactiveAttention.failureRetryDelay.inMilliseconds,
        },
      );
    } finally {
      _proactiveBusy = false;
      if (_proactiveAttention.pending.isNotEmpty) {
        unawaited(_drainProactiveAttention());
      }
    }
  }
}
