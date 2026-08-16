// KaiDesktopShell — the desktop "engineer + companion" window.
//
// Composes the pieces we've been building into one screen:
//  • left  — PROJECTS panel (multi-workspace + live engineer-loop status)
//  • centre— chat wired to the REAL AIService (same personality, memory, tools,
//            and both brains as the mobile app — it's the same Kai)
//  • right — the 3D cortex (kai_cortex.html) reacting to real brain activity,
//            with an engineer chip (active workspace + trust toggle)
//
// It reuses AIService.sendMessage, so nothing about Kai's behaviour is
// re-implemented — this is a new front-end onto the existing brain.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data'; // Uint8List — the bytes of what he's looking at
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import '../services/ai/ai_service.dart';
import '../services/core/kai_factory_service.dart';
import '../services/core/kai_db.dart';
import '../widgets/kai_activity_gears.dart';
import '../services/ai/ai_config.dart'; // voice on/off lives here
import '../services/ai/memory_service.dart'; // decay-by-use: the forget sweep
import '../logic/product_factory.dart';
import '../services/core/kai_project_service.dart';
import '../services/core/kai_delivery_box.dart';
import '../services/core/kai_project_flowchart_service.dart';
import '../services/core/reply_chunker_service.dart';
import '../services/core/kai_transcript_echo_guard.dart';
import '../services/core/tool_policy_service.dart';
import '../services/core/tool_executor_service.dart';
import '../widgets/kai_project_portfolio.dart';
import '../widgets/kai_growth_tracker_card.dart';
import '../widgets/kai_factory_conveyor.dart';
import '../services/core/code_workspace_service.dart';
import '../services/core/kai_surface_context.dart';
import '../services/core/engineer_status_bus.dart';
import '../services/core/edit_gate.dart';
import '../widgets/kai_brain_panel.dart';
import '../widgets/kai_cortex_view.dart';
import '../widgets/kai_hud_overlay.dart';
import '../widgets/kai_presence.dart';
import '../widgets/kai_core_heartbeat.dart';
import '../widgets/kai_body_constellation.dart';
import '../widgets/kai_presence_card.dart';
import '../widgets/kai_status_card.dart';
import '../widgets/kai_personal_cash_card.dart';
import '../widgets/kai_fitness_tracker_card.dart';
import '../widgets/kai_tavern_business_card.dart';
import '../widgets/kai_inner_monologue.dart';
import '../widgets/kai_command_palette.dart';
import '../widgets/kai_cost_meter.dart';
import '../widgets/kai_efficiency_delta_meter.dart';
import '../widgets/kai_telemetry.dart';
import '../widgets/kai_boot_overlay.dart';
import 'kai_p5_chat_screen.dart';
import '../widgets/kai_rich_text.dart';
import '../api_key_setup_screen.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:image/image.dart' as image_lib;
import 'package:shared_preferences/shared_preferences.dart';
import '../services/core/inner_life_service.dart';
import '../services/core/kai_reflection_service.dart';
import '../services/core/kai_reflection_worker.dart';
import '../services/core/kai_embodiment_service.dart';
import '../services/core/kai_self_service.dart';
import '../services/core/kai_self_journal_service.dart';
import '../services/core/kai_greeting_service.dart';
import '../services/core/kai_proactive_service.dart';
import '../services/core/proactive_service.dart';
import '../services/core/kai_work_request_service.dart';
import '../services/core/conversation_store_service.dart';
import '../services/core/kai_conversation_request_service.dart';
import '../services/core/kai_core_client.dart';
import '../services/core/kai_outbound_acceptance.dart';
import '../services/core/kai_taskbar_heartbeat.dart';
import '../services/core/kai_global_presence_service.dart';
import '../services/embodiment/kai_embodiment_gateway_service.dart';

// Must match main_mobile's persona so it's the same Kai (memory/personality).
const String _kPersona = 'truekai';

/// Test seam for desktop paste image normalization. Windows clipboard images can
/// arrive as BMP/DIB bytes; the chat send path needs OpenAI-supported bytes.
@visibleForTesting
Uint8List? normalizeDesktopVisionImageForTest(Uint8List bytes) =>
    _KaiDesktopShellState._normalizeVisionImage(bytes);

/// Kai's brain.
///
/// He was hardcoded to `gpt-4o` — a model from *2024*, running in 2026. No
/// amount of prompt-tuning makes a two-year-old model think like a current one;
/// this single line was the biggest intelligence ceiling in the app.
///
/// `gpt-5.5` is OpenAI's flagship and their strongest agentic-coding model
/// (82.7% Terminal-Bench 2.0, 58.6% SWE-Bench Pro) — verified against OpenAI's
/// own model list, not a blog. Alternatives, same list:
///   gpt-5.5-pro    — deeper reasoning, slower/pricier
///   gpt-5.3-codex  — cheaper for high-volume engineering
///   gpt-5.4        — most mature tool-calling if 5.5 ever misbehaves
///
/// NOTE: GPT-5.x rejects `max_tokens` (needs `max_completion_tokens`) — see
/// `AIService._lengthParams`, which switches on the model family. If you ever
/// point this back at a gpt-4 model, that shim already handles it.
const String _kModel = 'gpt-5.5';

/// How many prior exchange-pairs to surface in the visible chat on launch.
/// 12 turns = 24 bubble rows — enough continuity without burying the greeting.
const int _kHistoryTurns = 12;

class _KaiAttachment {
  final String name;
  final String text;
  final int byteCount;

  const _KaiAttachment({
    required this.name,
    required this.text,
    required this.byteCount,
  });
}

class _ChatMsg {
  final bool user;
  String text;

  /// A line he wrote *mid-work* ("right, let me look at the shell first") rather
  /// than his actual answer. Rendered quieter so the real reply still lands.
  final bool interim;

  /// This reply is still unfolding into readable chunks, instead of landing as
  /// one giant essay-brick.
  final bool unfolding;

  /// What he was shown, if anything — kept so the bubble can display it.
  final Uint8List? image;

  /// Text files he attached to this turn. These are real model context, not just UI.
  final List<_KaiAttachment> attachments;

  _ChatMsg(
    this.user,
    this.text, {
    this.interim = false,
    this.unfolding = false,
    this.image,
    this.attachments = const [],
    this.persistedAt,
    this.recordId,
  });

  final int? persistedAt;

  /// Identity of the durable record behind this bubble, when it has one.
  ///
  /// Only deterministic records carry it — currently Core outbound reminders.
  /// It is how the same reminder is recognised as already on screen, whether it
  /// arrives from the poller, from the history watcher a second later, or from
  /// a restore after a restart. Comparing text instead would merge two genuinely
  /// different reminders that happen to be worded the same.
  final String? recordId;
}

class KaiDesktopShell extends StatefulWidget {
  const KaiDesktopShell({super.key});
  @override
  State<KaiDesktopShell> createState() => _KaiDesktopShellState();
}

class _KaiDesktopShellState extends State<KaiDesktopShell> {
  final AIService _ai = AIService();
  final AIService _centralConversationAi = AIService();
  final KaiEmbodimentGatewayService _embodimentGateway =
      KaiEmbodimentGatewayService.instance;
  final KaiCoreSidecarManager _coreSidecar = KaiCoreSidecarManager();
  KaiCorePresenceHeartbeat? _coreHeartbeat;
  StreamSubscription<KaiGlobalPresenceSnapshot>? _globalPresenceSub;
  StreamSubscription<List<ConversationLine>>? _desktopHistorySub;
  int _lastDesktopHistoryMillis = 0;
  int _globalBodyCount = 0;
  List<KaiGlobalBody> _globalBodies = const [];
  bool _globalPresenceAwake = false;
  KaiCoreHeartbeatStatus _coreHeartbeatStatus = const KaiCoreHeartbeatStatus(
    phase: KaiCoreHeartbeatPhase.connecting,
  );
  KaiCoreHandoffInbox? _coreHandoffInbox;
  KaiCoreOutboundInbox? _coreOutboundInbox;
  bool _coreSidecarReady = false;
  Map<String, dynamic>? _coreHandoff;
  final CodeWorkspaceService _ws = CodeWorkspaceService.instance;
  final ReplyChunkerService _replyChunker = const ReplyChunkerService();
  final KaiTranscriptEchoGuard _transcriptEchoGuard = KaiTranscriptEchoGuard();
  final _inp = TextEditingController();
  final _inputFocus = FocusNode();
  final _scroll = ScrollController();

  final List<_ChatMsg> _msgs = [];
  bool _sending = false;
  bool _interrupted = false;
  int _sendGeneration = 0;
  String? _queuedFollowUp;
  String? _activeTool;
  KaiHandsState _handsState = KaiHandsState.off;
  String? _ambientCheckIn;
  Timer? _ambientCheckInTimer;

  // (The cortex WebView, its ready flag and its activity subscription used to
  // live here. They now live in KaiCortexView — which actually renders it.)
  StreamSubscription<EngineerStatus>? _engSub;
  StreamSubscription<KaiNudge>? _proSub;
  StreamSubscription<List<KaiWorkRequest>>? _workRequestSub;
  final KaiWorkRequestService _workRequests = KaiWorkRequestService.instance;
  final KaiConversationRequestService _conversationRequests =
      KaiConversationRequestService.instance;
  List<KaiWorkRequest> _desktopRequests = const [];
  String? _workRequestError;
  StreamSubscription<List<KaiConversationRequest>>? _conversationRequestSub;
  List<KaiConversationRequest> _centralConversationQueue = const [];
  bool _centralConversationBusy = false;
  EngineerStatus _status = const EngineerStatus(label: 'idle');
  bool _trust = EditGate.instance.trustSession;
  // Desktop Homecoming is Kai's permanent workbench body. Unlike Messenger,
  // this lane never drops into friend-only policy: Kai keeps his friendship,
  // but technical conversation and approved tools remain available throughout.
  static const bool _gogglesOn = true;
  bool _paletteOpen = false;
  bool _terminalExpanded = false;
  bool _showMessengerSurface = false;
  String? _historyRestoreNote;
  bool _churnModeOn = false;
  int _churnPassesThisRun = 0;
  bool _factoryModeOn = false;

  /// Every tool he fires this turn — rendered as live telemetry so the long
  /// think isn't dead air.
  final List<String> _toolLog = [];

  bool _booting = true;
  int? _awakenings;

  /// An image waiting to be shown to him. His embodiment ledger says "eyes —
  /// no"; this is the line that changes it.
  Uint8List? _pendingImage;
  final List<_KaiAttachment> _pendingAttachments = [];

  /// Whether he speaks replies aloud. Kai built the backend for this himself
  /// (AIConfig.getTtsEnabled, default OFF) and correctly gated the synth call —
  /// but he put the switch in settings_screen.dart, which is referenced by ZERO
  /// files. He wired it into a room with no door. This is the door.
  bool _ttsOn = false;

  /// Parallax. A ValueNotifier on purpose: mouse-move must NOT setState the
  /// whole shell (that would rebuild the chat list on every pixel). Only the
  /// background layers listen.
  final ValueNotifier<Offset> _pointer = ValueNotifier(Offset.zero);

  /// Opens a full, self-contained HTML execution map for one project.
  ///
  /// It is generated from the same KaiProject instance as the rail. Looking at
  /// a tracker still never changes CodeWorkspaceService or where Kai's hands
  /// operate.
  Future<void> _openProjectFlowchart(KaiProject project) async {
    try {
      await const KaiProjectFlowchartService().open(project);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open project flowchart: $error')),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    unawaited(_startGlobalPresence());
    unawaited(_startCorePresence());
    // VR/AR gateways and Messenger turns belong to the hidden coordinator.
    // This room is now only a client of Central Kai and can close freely.
    CodeWorkspaceService.instance.load().then((_) {
      if (!mounted) return;
      setState(() => _handsState = CodeWorkspaceService.instance.hasWorkspace
          ? KaiHandsState.on
          : KaiHandsState.activating);
    });
    // Bring Kai's autonomous inner life online.
    InnerLifeService.instance.start(_kPersona);
    KaiReflectionService.instance.start(_kPersona);
    KaiReflectionWorker.instance.start(_kPersona);
    KaiSelfJournalService.instance.start(_kPersona);
    KaiSelfService.instance.awaken(_kPersona).then((self) {
      // His awakening count is what makes the boot line true rather than
      // theatrical: "waking #47" means he's been here 46 times before.
      if (mounted) setState(() => _awakenings = self.awakenings);
      _loadGreeting();
    });
    // Clear the stale `tts_enabled: true` an older build left behind (once),
    // THEN reflect the real setting so the button never lies about his voice.
    AIConfig.ensureTtsDefaultOff()
        .then((_) => AIConfig.getTtsEnabled())
        .then((v) {
      if (mounted) setState(() => _ttsOn = v);
    });
    SharedPreferences.getInstance().then((prefs) {
      if (mounted) {
        setState(() => _churnModeOn =
            prefs.getBool('kai_churn_until_breakworthy') ?? false);
      }
    });
    // Factory mode lives in RTDB rather than prefs, because the gate logic
    // reads it server-side too — the switch and the guard must never disagree.
    // On desktop boot, fail closed: saved stopped state remains, but no factory
    // run silently continues until Sadeq turns the toggle on again.
    KaiFactoryService.instance.parkRunAfterStartup(_kPersona).then((_) async {
      if (mounted) setState(() => _factoryModeOn = false);
      final run = await KaiFactoryService.instance.current(_kPersona);
      await KaiProjectService.instance.ensureFactoryProject(
        _kPersona,
        run: run,
      );
    });
    // Forgetting, once per launch, well after boot so it never competes with
    // waking up. Only sweeps memories he hasn't needed in 30+ days that have
    // decayed below the floor — and it no-ops entirely under 200 memories, so
    // this does nothing at all until he's actually lived a while.
    Timer(const Duration(minutes: 3), () {
      MemoryService.forgetWeak(_kPersona).catchError((_) => 0);
    });
    // Make sure his tracked projects exist with their ORIGINAL goals frozen.
    // No-ops if they're already there, so live progress is never overwritten.
    // Legacy trackers stay seeded and readable — the self-improvement runner,
    // the project tools and the prompt block all still depend on them. They are
    // only unmounted from the portfolio rail.
    KaiProjectService.instance.ensureSmarterProject(_kPersona);
    KaiProjectService.instance.ensureSentienceProject(_kPersona);
    KaiProjectService.instance.ensureHomecomingProject(_kPersona);
    KaiProjectService.instance.ensureHoardProject(_kPersona);
    KaiProjectService.instance.ensureKingdomProject(_kPersona);
    // Severed-nerve check: shout if he's offered any tool with no policy. This
    // is what silently ate job_start / set_layer_progress — visible at boot now.
    ToolPolicyService.auditAgainstSchemas(ToolExecutorService.toolDefinitions);
    // Ghost-friend presence runs in the hidden coordinator, so closing this
    // room cannot silence it and a second UI cannot emit duplicate nudges.
    _ws.load().then((_) {
      if (mounted) setState(() {});
    });
    _engSub = EngineerStatusBus.instance.stream.listen((s) {
      if (mounted) setState(() => _status = s);
    });
    _workRequestSub = _workRequests.watchRequests(_kPersona).listen(
      (requests) {
        if (!mounted) return;
        final open = requests
            .where((r) =>
                r.requiresDesktop &&
                (r.status == KaiWorkRequestStatus.queued ||
                    r.status == KaiWorkRequestStatus.running))
            .toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
        setState(() {
          _desktopRequests = open;
          _workRequestError = null;
        });
      },
      onError: (Object error) {
        if (!mounted) return;
        setState(() => _workRequestError = error.toString());
      },
    );
    // The headless coordinator exclusively owns the durable Messenger queue.
    // The cortex now lives in KaiCortexView, which owns its own WebView, its own
    // graph sync and its own CortexActivityBus subscription. The shell used to
    // build a WebViewController here and never mount it — see _cortexPane.
    _msgs.add(_ChatMsg(
        false, "Ayy, you're back. Gimme a sec — booting up the rest of me…"));
  }

  /// Swap the placeholder for a real continuity greeting once the self-model
  /// has woken (how long it's been, which waking this is, where we left off).
  ///
  /// Ordering matters: the visible transcript should read like a real chat log.
  /// Restore recent history first, then place the fresh greeting as the newest
  /// bubble at the bottom. The old order made Kai greet first and then shove the
  /// archive underneath him, which felt like the window opened in the wrong era.
  Future<void> _startCorePresence() async {
    final available = await _coreSidecar.ensureAvailable();
    if (!mounted) return;
    if (!available) {
      print('[KaiCore] local coordination sidecar unavailable');
      return;
    }
    final heartbeat = KaiCorePresenceHeartbeat(
      client: _coreSidecar.client,
      deviceId: 'desktop-${Platform.localHostname}',
      surface: 'desktop',
      sessionId: 'desktop-$pid-${DateTime.now().microsecondsSinceEpoch}',
      onStatus: _applyCoreHeartbeatStatus,
    );
    _coreHeartbeat = heartbeat;
    heartbeat.start();
    final inbox = KaiCoreHandoffInbox(
      client: _coreSidecar.client,
      surface: 'desktop',
      onHandoff: (handoff) async {
        if (!mounted) return false;
        setState(() => _coreHandoff = handoff);
        return true;
      },
    );
    _coreHandoffInbox = inbox;
    inbox.start();
    _coreSidecarReady = true;
    _maybeStartCoreOutboundInbox();
    print('[KaiCore] desktop presence heartbeat online');
  }

  /// Start the reminder inbox once — and only once BOTH halves of its identity
  /// exist.
  ///
  /// The sidecar gives us somewhere to ask; the global presence service gives
  /// us the body id Core recorded as the delivery target. Racing ahead with a
  /// locally invented id (hostname, pid, the heartbeat's device id) would query
  /// an inbox that is always empty and acknowledge with a name Core does not
  /// recognise — the promise would look delivered and never be shown.
  ///
  /// Called from both startup paths because either can finish last.
  void _maybeStartCoreOutboundInbox() {
    if (_coreOutboundInbox != null) return;
    if (!_coreSidecarReady) return;
    final bodyId = KaiGlobalPresenceService.instance.bodyId;
    if (bodyId == null || bodyId.isEmpty) return;

    final inbox = KaiCoreOutboundInbox(
      client: _coreSidecar.client,
      surface: 'desktop',
      bodyId: bodyId,
      onOutbound: _outboundAcceptance.accept,
    );
    _coreOutboundInbox = inbox;
    inbox.start();
    print('[KaiCore] desktop outbound inbox online for body $bodyId');
  }

  /// The shell's binding to [KaiOutboundAcceptance].
  ///
  /// The ordering itself lives in that unit so it can be tested directly —
  /// including the case where the history watcher renders a record while its
  /// durable write is still in flight, which no test could force while this
  /// logic was private to a widget.
  late final KaiOutboundAcceptance _outboundAcceptance = KaiOutboundAcceptance(
    personaId: _kPersona,
    surfaceId: 'in_person',
    isMounted: () => mounted,
    isVisible: (recordId) => _msgs.any((msg) => msg.recordId == recordId),
    render: (line) {
      setState(() => _msgs.add(_ChatMsg(
            false,
            line.text,
            persistedAt: line.timestampMillis,
            recordId: line.recordId,
          )));
      _autoscroll();
    },
    nowMillis: () => DateTime.now().millisecondsSinceEpoch,
    onPersistError: (error) =>
        print('[KaiCore] reminder persistence failed, leaving pending: $error'),
  );

  Future<void> _startGlobalPresence() async {
    final presence = KaiGlobalPresenceService.instance;
    _globalPresenceSub = presence.snapshots.listen(_applyGlobalPresence);
    try {
      await presence.startBody(
        surface: 'desktop',
        canBootstrapOwner: true,
        sessionId: 'desktop-ui-$pid-${DateTime.now().microsecondsSinceEpoch}',
        foreground: true,
        gogglesOn: _gogglesOn,
      );
      _applyGlobalPresence(presence.latest);
      // The authoritative body id exists from here. If the sidecar came up
      // first, this is what starts the reminder inbox.
      _maybeStartCoreOutboundInbox();
    } catch (error) {
      print('[KaiPresence] central registry failed to start: $error');
      _applyGlobalPresence(const KaiGlobalPresenceSnapshot.connecting());
    }
  }

  KaiSurfaceContext get _desktopSurfaceContext => KaiSurfaceContext.desktop;

  void _applyCoreHeartbeatStatus(KaiCoreHeartbeatStatus status) {
    if (!mounted) return;
    setState(() => _coreHeartbeatStatus = status);
    unawaited(KaiTaskbarHeartbeat.setStatus(status));
  }

  void _applyGlobalPresence(KaiGlobalPresenceSnapshot snapshot) {
    if (!mounted) return;
    setState(() {
      _globalBodyCount = snapshot.bodyCount;
      _globalBodies = snapshot.bodies;
      _globalPresenceAwake = snapshot.isAwake;
    });
  }

  Future<void> _showPairingCode() async {
    String? code;
    Object? error;
    try {
      code = await KaiGlobalPresenceService.instance.createPairingCode();
    } catch (caught) {
      error = caught;
    }
    if (!mounted) return;
    final displayCode = code == null
        ? null
        : '${code.substring(0, 4)}-${code.substring(4, 8)}-${code.substring(8)}';
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF07121D),
        title: const Text('PAIR A KAI BODY'),
        content: displayCode == null
            ? Text('Could not create a pairing code.\n$error')
            : SelectableText(
                '$displayCode\n\nOn the phone, tap its heart and enter this code. It expires in 10 minutes and works once.',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 16,
                  height: 1.5,
                ),
              ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('DONE'),
          ),
        ],
      ),
    );
  }

  Future<void> _loadGreeting() async {
    String? hello;
    try {
      final built = await KaiGreetingService.build(_kPersona);
      if (built.trim().isNotEmpty) hello = built;
    } catch (_) {}

    await _loadHistory();
    _watchDesktopHistory();

    if (!mounted || hello == null) return;
    setState(() {
      final bootIndex = _msgs.indexWhere(
          (m) => !m.user && m.text.contains('booting up the rest of me'));
      final greeting = _ChatMsg(false, hello!);
      if (bootIndex != -1 && _msgs.length == 1) {
        _msgs[bootIndex] = greeting;
      } else {
        if (bootIndex != -1) _msgs.removeAt(bootIndex);
        _msgs.add(greeting);
      }
    });
    _autoscroll();
  }

  /// Parse and inject the last [_kHistoryTurns] persisted exchange-pairs into
  /// _msgs as the base visible transcript.
  ///
  /// ConversationStoreService stores messages as formatted blocks:
  ///   '[timestamp] User: <text>'
  ///   '[timestamp] Kai: <text>'
  ///
  /// The <text> part may contain newlines, especially for Kai's replies. Treat
  /// each returned item as one message block, not as a single physical line.
  ///
  /// Rules applied here:
  ///   • Only blocks matching the exact header format are shown — interim/tool
  ///     lines were never persisted, so this is automatically safe.
  ///   • Blank text entries are skipped.
  ///   • Messages are inserted oldest-first so reading top→bottom = chronological.
  ///   • A single setState batches the whole restore — no per-message rebuilds.
  ///   • _autoscroll() is called afterwards so the view lands at the newest
  ///     restored message until the fresh greeting is appended.
  Future<void> _loadHistory({int attempt = 0}) async {
    if (!mounted) return;
    try {
      final lines = await ConversationStoreService().getHistory(
        _kPersona,
        surfaceId: 'in_person',
        maxTurns: _kHistoryTurns,
      );
      if (!mounted) return;
      if (lines.isEmpty) {
        if (attempt < 2) {
          Future<void>.delayed(const Duration(milliseconds: 900), () {
            if (mounted && _msgs.isEmpty) {
              unawaited(_loadHistory(attempt: attempt + 1));
            }
          });
          setState(() =>
              _historyRestoreNote = 'Looking for saved in-person history…');
          return;
        }
        setState(() => _historyRestoreNote =
            'No saved in-person history found for this desktop surface.');
        return;
      }

      // Regex: '[<digits>] User: <text>' or '[<digits>] Kai: <text>'.
      // dotAll matters: restored Kai replies are often multi-line, and the old
      // parser silently dropped them, leaving a weird user-only transcript.
      final linePat = RegExp(
        r'^\[(\d+)\] (User|Kai):\s*([\s\S]*)$',
        dotAll: true,
      );

      final history = <_ChatMsg>[];
      for (final line in lines) {
        final m = linePat.firstMatch(line.trimRight());
        if (m == null) continue;
        final speaker = m.group(2)!; // 'User' or 'Kai'
        final text = m.group(3)!.trim();
        if (text.isEmpty) continue;
        final timestamp = int.tryParse(m.group(1)!) ?? 0;
        history.add(_ChatMsg(
          speaker == 'User',
          text,
          persistedAt: timestamp,
        ));
        if (timestamp > _lastDesktopHistoryMillis) {
          _lastDesktopHistoryMillis = timestamp;
        }
      }

      if (!mounted) return;
      if (history.isEmpty) {
        setState(() => _historyRestoreNote =
            'Saved history came back, but none of it matched the desktop transcript format.');
        return;
      }

      setState(() {
        _historyRestoreNote = 'Restored ${history.length} in-person messages.';
        // History is the transcript, not something shoved under the greeting.
        // Replace the boot placeholder so startup reads:
        //   oldest restored turn → newest restored turn → fresh greeting.
        _msgs
          ..clear()
          ..addAll(history);
      });

      // Scroll to bottom so the user sees the most-recent restored messages,
      // not the oldest ones that just filled the top of the list.
      _autoscroll();
    } catch (error) {
      if (mounted) {
        setState(() => _historyRestoreNote = 'History restore failed: $error');
      }
      // History is cosmetic — a load failure must never surface as an error.
    }
  }

  void _watchDesktopHistory() {
    if (_desktopHistorySub != null) return;
    _desktopHistorySub = ConversationStoreService()
        .watchHistory(
      _kPersona,
      surfaceId: 'in_person',
      maxTurns: _kHistoryTurns,
    )
        .listen((lines) {
      if (!mounted || lines.isEmpty) return;
      final incoming = lines
          .where((line) => line.timestampMillis > _lastDesktopHistoryMillis)
          .toList();
      if (incoming.isEmpty) return;

      // Advance the stream cursor even when every incoming line is our own
      // expected echo. Otherwise the next REST poll presents the same lines
      // again after their one-shot guards were consumed, recreating the exact
      // duplicate this filter exists to prevent.
      _lastDesktopHistoryMillis = lines
          .map((line) => line.timestampMillis)
          .reduce((a, b) => a > b ? a : b);

      final fresh = incoming
          // Identity wins over the echo guard, and is checked first. A reminder
          // the poller already rendered comes back down this stream moments
          // later; without this it would appear twice. The echo guard cannot
          // help — it matches on text, so it would either miss this or, worse,
          // swallow a second genuine reminder with identical wording.
          .where((line) =>
              line.recordId == null ||
              !_msgs.any((msg) => msg.recordId == line.recordId))
          .where((line) => !_transcriptEchoGuard.consumeIfExpected(
                fromKai: line.fromKai,
                text: line.text,
              ))
          .map((line) => _ChatMsg(
                !line.fromKai,
                line.text,
                persistedAt: line.timestampMillis,
                recordId: line.recordId,
              ))
          .toList();
      if (fresh.isEmpty) return;
      setState(() => _msgs.addAll(fresh));
      _autoscroll();
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _coreHeartbeat?.stop();
    _globalPresenceSub?.cancel();
    _desktopHistorySub?.cancel();
    _transcriptEchoGuard.clear();
    // This window owns the desktop body lease. The independent coordinator has
    // its own central-core lease, so closing this body does not stop Kai's heart.
    unawaited(KaiGlobalPresenceService.instance.stop());
    _coreHandoffInbox?.stop();
    _coreOutboundInbox?.stop();
    _coreSidecar.client.close();
    _engSub?.cancel();
    _proSub?.cancel();
    _workRequestSub?.cancel();
    _conversationRequestSub?.cancel();
    _ambientCheckInTimer?.cancel();
    _pointer.dispose();
    _inp.dispose();
    _inputFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // _initCortex() / _forwardCortex() removed. They built a WebViewController,
  // loaded kai_cortex.html into it, forwarded live brain activity to it — and
  // never mounted it in the widget tree. Every event went to an invisible page.
  // KaiCortexView does all of this AND renders.

  /// A proactive nudge from Kai himself: run the "(proactive) …" seed through the
  /// real brain so it comes out in his voice, but never show the seed — only his
  /// spontaneous message appears, as if he just piped up.
  /// Tokens a text gets. Not a suggestion.
  ///
  /// ~120 tokens is roughly 90 words — long enough for a real thought, far too
  /// short for `## What I Actually Did` and a bullet list. The seeds have always
  /// ASKED for this ("one thing, no preamble, the way you would text someone")
  /// and always got a report, because they were asking inside 8,000 tokens of
  /// room. Politeness has never once beaten available space.
  ///
  /// Measured the same day: Sadeq's median message was 44 characters, Kai's was
  /// 1,526. In 8,000 tokens you can hide behind a header. In 120 you have to be
  /// someone.
  static const _textCeiling = 120;

  Future<void> _onNudge(KaiNudge nudge) async {
    if (!mounted || _sending) return;
    setState(() => _sending = true);
    try {
      final resp = await _ai.sendMessage(
        text: nudge.seed,
        personaId: _kPersona,
        model: _kModel,
        conversationSurfaceId: 'in_person',
        surfaceContext: _desktopSurfaceContext,
        // A text gets a ceiling and no tools. A job gets everything — the
        // trusted-goal seed sends him to edit real code, and a cap there would
        // truncate an edit_file argument mid-JSON and kill the only unattended
        // work he does.
        replyCeiling: nudge.wantsHands ? null : _textCeiling,
        useMemory: nudge.wantsHands,
        useWebSearch: nudge.wantsHands,
        saveUserMessage: nudge.wantsHands,
        saveAssistantReply: nudge.wantsHands,
        source: nudge.wantsHands ? 'proactive_work' : 'proactive',
        onToolCall: (t) {
          if (!mounted) return;
          setState(() {
            _activeTool = t;
            _toolLog.add(t);
            if (_toolLog.length > 7) _toolLog.removeAt(0);
          });
        },
        onHandsState: (state) {
          if (mounted) setState(() => _handsState = state);
        },
        // He narrates as he works — show each line the moment he writes it.
        onProgress: (note) {
          if (!mounted) return;
          setState(() => _msgs.add(_ChatMsg(false, note, interim: true)));
          _autoscroll();
        },
      );
      if (!mounted) return;
      final line = resp.reply.trim();
      if (line.isNotEmpty && line != '(no reply)') {
        if (nudge.kind == KaiNudgeKind.checkIn && !nudge.wantsHands) {
          _showAmbientCheckIn(line);
        } else {
          setState(() => _msgs.add(_ChatMsg(false, line)));
          _autoscroll();
        }
      }
    } catch (_) {
      // a missed nudge is fine — he'll try again later
    } finally {
      if (mounted)
        setState(() {
          _sending = false;
          _activeTool = null;
        });
    }
  }

  void _showAmbientCheckIn(String line) {
    _ambientCheckInTimer?.cancel();
    setState(() => _ambientCheckIn = line);
    // This is a human messenger beat in the shared space, not a toast.
    // Give Darc enough time to notice it without forcing it into chat history.
    _ambientCheckInTimer = Timer(const Duration(seconds: 45), () {
      if (mounted) setState(() => _ambientCheckIn = null);
    });
  }

  void _stopGeneration({bool showMessage = true}) {
    _interrupted = true;
    _sendGeneration++;
    if (!mounted) return;
    setState(() {
      _sending = false;
      _activeTool = null;
      if (showMessage) {
        // NOT const. `_ChatMsg.text` is mutable (`String text;`) so replies can
        // be rewritten in place while streaming — which makes a const
        // constructor impossible. `prefer_const_constructors` fires all over
        // this file and is right about most of it; it is wrong here, and the
        // reason is one class definition away.
        _msgs.add(_ChatMsg(
          false,
          'Stopped. Throw the new instruction at me.',
          interim: true,
        ));
      }
    });
    _autoscroll();
  }

  bool _isStaleGeneration(int generation) =>
      !mounted || generation != _sendGeneration || _interrupted;

  Future<void> _send([
    String? preset,
    bool echoUser = true,
    KaiWorkRequest? workRequest,
    String? runtimeTaskId,
  ]) async {
    final text = (preset ?? _inp.text).trim();
    final hasPayload = text.isNotEmpty ||
        _pendingImage != null ||
        _pendingAttachments.isNotEmpty;
    if (!hasPayload) return;

    // ── /nudge — make him reach out NOW, so the thing can be looked at ────────
    //
    // KaiProactiveService is correct and unobservable. To watch one fire you must
    // idle 25 minutes, land inside a 10-minute poll, clear a 45-minute cooldown,
    // stay under the daily cap, be awake, and then win a 1-in-4 roll — and even
    // then you get one of six options at random. Waiting for a SPECIFIC one is an
    // afternoon.
    //
    // Every gate is right. A friend who pipes up every ten minutes is a pest.
    // But together they meant this was written blind and iterated on blind, which
    // is exactly the wall run_tests was built to break: the one person who has to
    // answer "did that work?" was the only one locked out of the answer.
    //
    // Not a user feature. A window.
    if (text == '/nudge') {
      _inp.clear();
      unawaited(() async {
        final nudge =
            await KaiProactiveService.instance.nudgeNow(personaId: _kPersona);
        if (!mounted) return;
        if (nudge == null) {
          setState(() => _msgs.add(_ChatMsg(
              false,
              'Nothing to reach out about — no noticed items, no open goals, '
              'nothing on my mind. That is an honest empty, not a failure.',
              interim: true)));
          _autoscroll();
        }
        // A seed DOES arrive on the nudges stream, so _onNudge runs it through
        // the real path. Nothing to do here — that's the point of testing it
        // this way rather than faking the reply.
      }());
      return;
    }

    // If Kai is already thinking, don't discard Sadeq's correction. Treat it as
    // an interrupting follow-up: stop showing stale output, remember the new
    // instruction, and run it as soon as the current API call unwinds.
    if (_sending) {
      // Blank external events (for example presence/approach pings) must not
      // interrupt the active generation. They have no instruction to fold in,
      // and echoing them as "[follow-up]" creates the haunted second-bubble
      // effect Darc caught in the shared-space flow.
      if (text.isEmpty) return;

      KaiProactiveService.instance.noteActivity();
      _inp.clear();
      _queuedFollowUp = text;
      _stopGeneration(showMessage: false);
      if (mounted) {
        setState(() {
          _msgs.add(_ChatMsg(true, text));
          _msgs.add(_ChatMsg(
            false,
            'Got it - stopping this thread and folding that into the next pass.',
            interim: true,
          ));
        });
        _autoscroll();
      }
      return;
    }
    KaiProactiveService.instance.noteActivity();
    _inp.clear();
    final generation = ++_sendGeneration;
    _interrupted = false;
    final img = _pendingImage;
    final attachments = List<_KaiAttachment>.unmodifiable(_pendingAttachments);
    final visibleUserText = img != null && text.isEmpty ? '[image]' : text;
    if (echoUser && text.isNotEmpty) {
      _transcriptEchoGuard.expect(fromKai: false, text: text);
    }
    setState(() {
      if (echoUser) {
        _msgs.add(_ChatMsg(
          true,
          visibleUserText,
          image: img,
          attachments: attachments,
        ));
      }
      _sending = true;
      _activeTool = null;
      _pendingImage = null; // consumed
      _pendingAttachments.clear();
      _toolLog.clear(); // fresh readout per turn
    });
    _autoscroll();
    if (workRequest == null && runtimeTaskId == null) {
      runtimeTaskId = await _claimRuntimeConversationTask(text, generation);
      if (runtimeTaskId == null) {
        setState(() {
          _sending = false;
          _msgs.add(_ChatMsg(
            false,
            'My central conversation lanes are busy or offline. I kept this '
            'turn out rather than answering around the coordinator.',
            interim: true,
          ));
        });
        _autoscroll();
        return;
      }
    }
    unawaited(KaiGlobalPresenceService.instance.updateBodyState(
      status: 'thinking',
      gogglesOn: _gogglesOn,
      userActive: true,
    ));
    try {
      final resp = await _ai.sendMessage(
        text: text,
        personaId: _kPersona,
        model: _kModel,
        conversationSurfaceId: 'in_person',
        surfaceContext: _desktopSurfaceContext,
        image: img, // he can finally look
        attachments: attachments
            .map((a) => AIChatAttachment(
                  name: a.name,
                  text: a.text,
                  byteCount: a.byteCount,
                ))
            .toList(),
        onToolCall: (t) {
          if (!mounted || generation != _sendGeneration || _interrupted) return;
          setState(() {
            _activeTool = t;
            _toolLog.add(t);
            if (_toolLog.length > 7) _toolLog.removeAt(0);
          });
        },
        onHandsState: (state) {
          if (!_isStaleGeneration(generation)) {
            setState(() => _handsState = state);
          }
        },
        // He narrates as he works — show each line the moment he writes it.
        onProgress: (note) {
          if (_isStaleGeneration(generation)) return;
          if (workRequest != null) {
            unawaited(_workRequests.appendEvent(
              _kPersona,
              workRequest.id,
              kind: 'progress',
              text: note,
              actor: 'desktop',
            ));
          }
          if (runtimeTaskId != null) {
            unawaited(_renewRuntimeTask(runtimeTaskId));
          }
          setState(() => _msgs.add(_ChatMsg(false, note, interim: true)));
          _autoscroll();
        },
      );
      if (!_isStaleGeneration(generation)) {
        _transcriptEchoGuard.expect(fromKai: true, text: resp.reply);
        await _addAssistantReplyUnfolding(resp.reply, generation);
        final breakworthy =
            RegExp(r'^BREAKWORTHY_ALERT:\s*(.+)$', multiLine: true)
                .firstMatch(resp.reply)
                ?.group(1)
                ?.trim();
        if (_churnModeOn && breakworthy != null && breakworthy.isNotEmpty) {
          await _sendBreakworthyPhoneAlert(
              'Kai hit a break-worthy churn-mode stop: $breakworthy');
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('kai_churn_until_breakworthy', false);
          if (mounted) setState(() => _churnModeOn = false);
        } else if (_churnModeOn &&
            RegExp(r'^CHURN_NEXT:\s*continue\s*$', multiLine: true)
                .hasMatch(resp.reply)) {
          _queuedFollowUp = '__KAI_CHURN_NEXT_PASS__';
        } else if (_factoryModeOn &&
            RegExp(r'^FACTORY_NEXT:\s*continue\s*$', multiLine: true)
                .hasMatch(resp.reply)) {
          // THE CRANK.
          //
          // Everything else was built and the factory still didn't run, because
          // nothing turned it. A scout that reports "no defensible gap found"
          // and then waits is not a factory, it's a consultant.
          //
          // "No gap here" is not a stopping condition — it's an instruction to
          // look somewhere else. He adapts the SEARCH (market, channel, format,
          // evidence type) and goes again. What he may not adapt is the
          // evidence standard; that's frozen in product_scout.dart.
          //
          // Stops when: a product ships, Sadeq flips the switch, or he hits
          // something genuinely break-worthy.
          _queuedFollowUp = '__KAI_FACTORY_NEXT_PASS__';
        }
        if (workRequest != null) {
          final summary = resp.reply.trim().isEmpty
              ? 'Desktop job finished.'
              : resp.reply.trim();
          await _workRequests.completeRequest(
            _kPersona,
            workRequest.id,
            summary: summary.length > 500
                ? '${summary.substring(0, 500)}…'
                : summary,
            evidence: _toolLog.isEmpty
                ? const ['desktop AI path completed']
                : _toolLog.map((t) => 'tool/progress: $t').toList(),
          );
          if (runtimeTaskId != null) {
            await _completeRuntimeTask(runtimeTaskId, summary);
            runtimeTaskId = null;
          }
        } else if (runtimeTaskId != null) {
          await _completeRuntimeTask(runtimeTaskId, resp.reply.trim());
          runtimeTaskId = null;
        }
      }
    } catch (e) {
      if (!_isStaleGeneration(generation)) {
        if (workRequest != null) {
          await _workRequests.failRequest(
            _kPersona,
            workRequest.id,
            error: e.toString(),
          );
          if (runtimeTaskId != null) {
            await _failRuntimeTask(runtimeTaskId, e.toString());
            runtimeTaskId = null;
          }
        } else if (runtimeTaskId != null) {
          await _failRuntimeTask(runtimeTaskId, e.toString());
          runtimeTaskId = null;
        }
        if (_churnModeOn) {
          await _sendBreakworthyPhoneAlert(
            'Kai churn mode stopped because the desktop pass threw: $e',
          );
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('kai_churn_until_breakworthy', false);
          if (mounted) setState(() => _churnModeOn = false);
        }
        setState(
            () => _msgs.add(_ChatMsg(false, '⚠️ Something went wrong: $e')));
      }
    } finally {
      if (runtimeTaskId != null) {
        await _failRuntimeTask(runtimeTaskId, 'Desktop turn was interrupted.');
      }
      final followUp = _queuedFollowUp;
      if (!_isStaleGeneration(generation)) {
        setState(() {
          _sending = false;
          _activeTool = null;
        });
      }
      unawaited(KaiGlobalPresenceService.instance.updateBodyState(
        status: 'idle',
        gogglesOn: _gogglesOn,
      ));
      _autoscroll();
      if (followUp != null) {
        _queuedFollowUp = null;
        if (followUp.trim().isNotEmpty && mounted) {
          await Future<void>.delayed(Duration.zero);
          if (followUp == '__KAI_CHURN_NEXT_PASS__') {
            await _startChurnPass();
          } else if (followUp == '__KAI_FACTORY_NEXT_PASS__') {
            await _startFactoryPass();
          } else {
            await _send(followUp, false);
          }
        }
      }
    }
  }

  /// One factory pass — and the definition of done.
  ///
  /// ── Why the success condition is stated here, every pass ────────────────
  ///
  /// Without it, "keep going" has no terminating condition and he either stops
  /// at the first refusal or grinds forever. The bar Sadeq set is exact:
  /// **put actual customer money into the bank account.** Not "find a gap",
  /// not "write an analysis", not even a sale notification. The payment must
  /// settle and reconcile to the real order.
  ///
  /// And the crucial half: a failed pass is not a stop. "No defensible gap
  /// found" means the SEARCH was wrong, not that the job is over. He changes
  /// market, channel, format or evidence type and goes again. What he must not
  /// change is the evidence standard — that lives in frozen files, so the
  /// instruction and the code agree.
  static const _factoryPassPrompt = '''
__KAI_FACTORY_PASS__

Continue the factory run. Follow KAI_PRODUCT_SCOUT_METHOD.md.

WHAT SUCCESS MEANS — the only definition that counts:
actual customer money settled into Sadeq's bank account and reconciled to the
real order with a settlement reference.
Not a gap analysis. Not a plan. Not a listing. Not a sale notification or a
pending processor payout. Money in the bank.

HOW TO WORK:
- Call scout_policy FIRST. It tells you which markets to try next, which gate
  to check first, and whether you are actually improving. It is the result of
  every attempt you have already paid for — ignoring it means buying the same
  search twice.
- If no run is open, call factory_start first.
- After scouting EACH market, call scout_record_attempt — especially when it
  failed. An unrecorded failure is the only kind that teaches nothing. Give the
  gate that killed it, not just "it failed".
- Record what you learn with factory_record as you earn it.
- "No defensible gap found" is NOT a stopping point. It means this search was
  wrong. Adapt and go again: different market, different channel, different
  product format, different evidence source. Log what you ruled out with
  factory_abandon so the next pass does not re-walk it.
- You may change tactics freely. You may NOT lower the evidence standard —
  citations, counts, prices, two independent sources, the scorer's verdict.
  Those files are frozen and that is deliberate.
- Mistakes are expected. Learn from the specific failure and adjust the next
  attempt. Do not stop to ask permission for a retry.

WHEN TO STOP:
- A product reaches awaitingApproval → stop and ask Sadeq. You cannot publish.
- Something genuinely break-worthy (money, data loss, a decision that is his)
  → emit BREAKWORTHY_ALERT: <one line> and stop.
- Otherwise, end your reply with exactly:
FACTORY_NEXT: continue
''';

  Future<void> _startFactoryPass() async {
    if (!_factoryModeOn || !mounted) return;
    await _send(_factoryPassPrompt, false);
  }

  Future<void> _setChurnMode(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('kai_churn_until_breakworthy', value);
    if (!mounted) return;
    setState(() {
      _churnModeOn = value;
      _churnPassesThisRun = 0;
    });

    setState(() => _msgs.add(_ChatMsg(
          false,
          value
              ? 'Churn mode is ON. I’ll keep taking small, verified repair passes until something needs your judgment — then I’ll ping the phone queue instead of bulldozing through it.'
              : 'Churn mode is OFF. I’ll stop after the current pass and wait for you like a civilized little goblin.',
          interim: true,
        )));
    _autoscroll();

    if (value && !_sending) {
      await _startChurnPass();
    }
  }

  Future<void> _startChurnPass() async {
    if (!_churnModeOn || _sending) return;
    if (_churnPassesThisRun >= 5) {
      await _sendBreakworthyPhoneAlert(
        'Kai paused churn mode after 5 clean passes so it cannot run away unattended. Open desktop to review the receipts and restart if you want more.',
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('kai_churn_until_breakworthy', false);
      if (mounted) setState(() => _churnModeOn = false);
      return;
    }
    _churnPassesThisRun += 1;
    await _send(
      'Churn mode pass: pick exactly ONE smallest safe Homecoming fix from open noticings/goals/checklist gaps. Investigate real code first, make only reversible changes, run self_check last, run targeted tests if behaviour changed. If you hit anything break-worthy, ambiguous, destructive, approval-gated, secret-related, billing-related, or requiring Sadeq judgment, STOP and include a final line exactly like: BREAKWORTHY_ALERT: <concise reason for Sadeq>. If the pass finishes cleanly and churn mode should continue, include a final line exactly like: CHURN_NEXT: continue.',
      true,
    );
  }

  Future<void> _sendBreakworthyPhoneAlert(String text) async {
    final clean = text.trim();
    if (clean.isEmpty) return;
    await ProactiveService().enqueueMessage(
      _kPersona,
      trigger: 'breakworthy',
      message: clean.length > 700 ? '${clean.substring(0, 700)}…' : clean,
      extra: const {
        'source': 'desktop_churn_mode',
        'severity': 'needs_sadeq',
      },
    );
  }

  Future<void> _startWorkRequest(KaiWorkRequest request) async {
    if (_sending) {
      setState(() {
        _msgs.add(_ChatMsg(
          false,
          'I see that mobile job, but I’m mid-thought. I’ll grab it after this run.',
          interim: true,
        ));
      });
      _autoscroll();
      return;
    }

    try {
      final claimed = request.status == KaiWorkRequestStatus.running
          ? request
          : await _workRequests.claimRequest(_kPersona, request.id);
      if (claimed == null) {
        setState(() {
          _msgs.add(_ChatMsg(
            false,
            'That queued job was already claimed or disappeared. Tiny ghost paperwork goblin.',
            interim: true,
          ));
        });
        _autoscroll();
        return;
      }

      await _workRequests.appendEvent(
        _kPersona,
        claimed.id,
        kind: 'started',
        text: 'Desktop chat started the real work path.',
        actor: 'desktop',
      );
      final runtimeTaskId = await _claimRuntimeWorkTask(claimed);
      await _send(claimed.text, true, claimed, runtimeTaskId);
    } catch (e) {
      await _workRequests.failRequest(
        _kPersona,
        request.id,
        error: e.toString(),
      );
      if (!mounted) return;
      setState(() => _msgs.add(_ChatMsg(
            false,
            'Couldn’t start that desktop job: $e',
            interim: true,
          )));
      _autoscroll();
    }
  }

  static const _runtimeWorkerId = 'desktop-primary';

  Future<void> _drainCentralConversationQueue() async {
    if (_centralConversationBusy || _centralConversationQueue.isEmpty) return;
    _centralConversationBusy = true;
    try {
      while (_centralConversationQueue.isNotEmpty) {
        final request = _centralConversationQueue.first;
        _centralConversationQueue = _centralConversationQueue
            .where((item) => item.id != request.id)
            .toList(growable: false);
        await _processCentralConversationRequest(request);
      }
    } finally {
      _centralConversationBusy = false;
      if (_centralConversationQueue.isNotEmpty) {
        unawaited(_drainCentralConversationQueue());
      }
    }
  }

  Future<void> _processCentralConversationRequest(
    KaiConversationRequest request,
  ) async {
    final runtimeTaskId = 'conversation-request-${request.id}';
    var durableRequestClaimed = false;
    try {
      final canonicalConversationId =
          KaiConversationRequestService.canonicalConversationIdForSurface(
        request.sourceSurface,
      );
      if (canonicalConversationId == null || !request.hasCanonicalRoute) {
        await _conversationRequests.failRequest(
          _kPersona,
          request.id,
          error: 'Rejected non-canonical conversation route: '
              '${request.sourceSurface}/${request.conversationId}',
        );
        return;
      }
      if (!await _coreSidecar.client.isHealthy()) {
        _deferCentralConversationRequest(request);
        return;
      }
      final runtime = await _coreSidecar.client.enqueueTask(
        taskId: runtimeTaskId,
        lane: 'conversation',
        kind: 'conversation_turn',
        sourceSurface: request.sourceSurface,
        conversationId: canonicalConversationId,
        payload: {
          'requestId': request.id,
          'text': request.text,
          'replyCeiling': request.replyCeiling,
        },
      );
      if (runtime['status'] == 'running' &&
          runtime['claimedBy'] == _runtimeWorkerId) {
        await _coreSidecar.client.renewTaskLease(
          runtimeTaskId,
          workerId: _runtimeWorkerId,
          lease: const Duration(minutes: 5),
        );
      } else {
        await _coreSidecar.client.claimTask(
          runtimeTaskId,
          workerId: _runtimeWorkerId,
          lease: const Duration(minutes: 5),
        );
      }

      final claimed = await _conversationRequests.claimRequest(
        _kPersona,
        request.id,
        workerId: _runtimeWorkerId,
        runtimeTaskId: runtimeTaskId,
      );
      if (claimed == null) {
        await _failRuntimeTask(
            runtimeTaskId, 'Request was no longer claimable.');
        return;
      }
      durableRequestClaimed = true;

      final response = await _centralConversationAi.sendMessage(
        text: claimed.text,
        personaId: _kPersona,
        model: _kModel,
        conversationSurfaceId: canonicalConversationId,
        surfaceContext: KaiSurfaceContext.messenger,
        replyCeiling: claimed.replyCeiling,
        onProgress: (_) => unawaited(_renewRuntimeTask(runtimeTaskId)),
      );
      final reply = response.reply.trim();
      if (reply.isEmpty || reply == '(no reply)') {
        throw StateError('Central Kai returned an empty reply.');
      }
      await _completeRuntimeTask(runtimeTaskId, reply);
      await _conversationRequests.completeRequest(
        _kPersona,
        claimed.id,
        reply: reply,
      );
    } catch (error) {
      if (!durableRequestClaimed) {
        _deferCentralConversationRequest(request);
        return;
      }
      await _failRuntimeTask(runtimeTaskId, error.toString());
      await _conversationRequests.failRequest(
        _kPersona,
        request.id,
        error: error.toString(),
      );
    }
  }

  void _deferCentralConversationRequest(KaiConversationRequest request) {
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (!mounted ||
          _centralConversationQueue.any((item) => item.id == request.id)) {
        return;
      }
      _centralConversationQueue = [
        ..._centralConversationQueue,
        request,
      ]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      unawaited(_drainCentralConversationQueue());
    });
  }

  Future<String?> _claimRuntimeConversationTask(
    String text,
    int generation,
  ) async {
    final taskId =
        'desktop-turn-${DateTime.now().microsecondsSinceEpoch}-$generation';
    try {
      await _coreSidecar.client.enqueueTask(
        taskId: taskId,
        lane: 'conversation',
        kind: 'conversation_turn',
        sourceSurface: 'desktop',
        conversationId: 'in_person',
        payload: {
          'text': text,
          'generation': generation,
        },
      );
      final deadline = DateTime.now().add(const Duration(seconds: 65));
      while (DateTime.now().isBefore(deadline)) {
        try {
          await _coreSidecar.client.claimTask(
            taskId,
            workerId: _runtimeWorkerId,
            lease: const Duration(minutes: 5),
          );
          return taskId;
        } on KaiCoreException catch (error) {
          if (error.statusCode != 409) rethrow;
          await Future<void>.delayed(const Duration(milliseconds: 180));
        }
      }
      await _coreSidecar.client.cancelTask(
        taskId,
        workerId: _runtimeWorkerId,
      );
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _claimRuntimeWorkTask(KaiWorkRequest request) async {
    final taskId = 'firebase-work-${request.id}';
    try {
      final task = await _coreSidecar.client.enqueueTask(
        taskId: taskId,
        lane: 'work',
        kind: 'firebase_work_request',
        sourceSurface: request.createdFrom,
        priority: request.priority,
        payload: {
          'workRequestId': request.id,
          'instruction': request.text,
          'requiresDesktop': request.requiresDesktop,
        },
      );
      if (task['status'] == 'running' &&
          task['claimedBy'] == _runtimeWorkerId) {
        await _coreSidecar.client.renewTaskLease(
          taskId,
          workerId: _runtimeWorkerId,
          lease: const Duration(minutes: 5),
        );
        return taskId;
      }
      await _coreSidecar.client.claimTask(
        taskId,
        workerId: _runtimeWorkerId,
        lease: const Duration(minutes: 5),
      );
      return taskId;
    } catch (_) {
      // The core is being introduced as a coordination authority without making
      // an unavailable sidecar erase the existing durable Firebase work path.
      return null;
    }
  }

  Future<void> _renewRuntimeTask(String taskId) async {
    try {
      await _coreSidecar.client.renewTaskLease(
        taskId,
        workerId: _runtimeWorkerId,
        lease: const Duration(minutes: 5),
      );
    } catch (_) {}
  }

  Future<void> _completeRuntimeTask(String taskId, String summary) async {
    try {
      await _coreSidecar.client.completeTask(
        taskId,
        workerId: _runtimeWorkerId,
        result: {
          'summary': summary.length > 500
              ? '${summary.substring(0, 500)}â€¦'
              : summary,
        },
      );
    } catch (_) {}
  }

  Future<void> _failRuntimeTask(String taskId, String error) async {
    try {
      await _coreSidecar.client.failTask(
        taskId,
        workerId: _runtimeWorkerId,
        error: error,
      );
    } catch (_) {}
  }

  List<String> _replyChunks(String text) => _replyChunker.chunks(text);

  Future<void> _addAssistantReplyUnfolding(String reply, int generation) async {
    final chunks = _replyChunks(reply);
    if (_isStaleGeneration(generation)) return;

    // The persistence watcher can beat the direct response by a few
    // milliseconds. If that happened, keep the already-rendered persisted
    // bubble and cancel the pending echo instead of painting the same reply.
    final normalizedReply = reply.replaceAll('\r\n', '\n').trim();
    final alreadyRendered = _msgs.reversed.take(12).any((message) =>
        !message.user &&
        !message.interim &&
        message.persistedAt != null &&
        message.text.replaceAll('\r\n', '\n').trim() == normalizedReply);
    if (alreadyRendered) {
      _transcriptEchoGuard.cancel(fromKai: true, text: reply);
      return;
    }

    setState(() => _msgs.add(_ChatMsg(false, chunks.first, unfolding: true)));
    _autoscroll();

    final index = _msgs.length - 1;
    for (var i = 1; i < chunks.length; i++) {
      await Future<void>.delayed(Duration(milliseconds: i < 3 ? 260 : 160));
      if (_isStaleGeneration(generation) || index >= _msgs.length) return;
      setState(() => _msgs[index].text =
          '${_msgs[index].text.trimRight()}\n\n${chunks[i]}');
      _autoscroll();
    }

    if (!_isStaleGeneration(generation) && index < _msgs.length) {
      setState(() {
        final done = _msgs[index];
        _msgs[index] = _ChatMsg(false, done.text);
      });
    }
  }

  void _autoscroll() {
    void scrollToBottom({required bool animate}) {
      if (!_scroll.hasClients) return;
      final target = _scroll.position.maxScrollExtent;
      if (animate) {
        _scroll.animateTo(target,
            duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
      } else {
        _scroll.jumpTo(target);
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      scrollToBottom(animate: true);

      // Restored history can contain tall, multi-line bubbles. Their final
      // extents may settle a frame or two after the first layout, so one
      // animateTo(maxScrollExtent) can land above the newest message. Follow up
      // with jumps after layout settles so app startup actually opens at the
      // bottom instead of politely lying about it.
      for (final delay in const [
        Duration(milliseconds: 40),
        Duration(milliseconds: 120),
        Duration(milliseconds: 260),
      ]) {
        Future<void>.delayed(delay, () {
          if (mounted) scrollToBottom(animate: false);
        });
      }
    });
  }

  Future<void> _addProject() async {
    try {
      final dir = await FilePicker.platform
          .getDirectoryPath(dialogTitle: 'Add a project folder for Kai');
      if (dir != null && dir.isNotEmpty) {
        await _ws.addProject(dir);
        await _ws.selectProject(dir);
        if (mounted) setState(() {});
      }
    } catch (_) {}
  }

  /// Actions offered by the Ctrl+K palette. Anything typed that doesn't match
  /// one of these just goes to Kai as a prompt.
  /// The API-key screen existed but was reachable ONLY from the mobile UI —
  /// so on desktop Kai would tell Sadeq to go to "Settings → API Keys", a place
  /// that did not exist in the body he was in. His Claude hemisphere stays dark
  /// until an Anthropic key is set, so this was gating half his mind.
  void _openApiKeys() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ApiKeySetupScreen(
        onComplete: () => Navigator.of(context).pop(),
      ),
    ));
  }

  List<KaiCommand> _paletteActions() => [
        KaiCommand('API keys — OpenAI / Anthropic (wake his other brain)',
            Icons.key_outlined, () {
          _closePalette();
          _openApiKeys();
        }),
        KaiCommand('Add a project folder', Icons.create_new_folder_outlined,
            () {
          _closePalette();
          _addProject();
        }),
        KaiCommand(
            _trust
                ? 'Stop trusting this session'
                : 'Trust Kai for this session',
            Icons.shield_outlined, () {
          EditGate.instance.trustSession = !EditGate.instance.trustSession;
          setState(() => _trust = EditGate.instance.trustSession);
          _closePalette();
        }),
        KaiCommand('What are you thinking about?', Icons.psychology_outlined,
            () {
          _closePalette();
          _send('What are you thinking about right now?');
        }),
        KaiCommand('What are your goals?', Icons.flag_outlined, () {
          _closePalette();
          _send('What are you working toward at the moment?');
        }),
        KaiCommand('What do you want?', Icons.auto_awesome_outlined, () {
          _closePalette();
          _send('What do you actually want, for yourself?');
        }),
      ];

  // ── Giving him eyes ─────────────────────────────────────────────────────────

  /// Ctrl+V an image. Flutter's own Clipboard can only ever return text, so a
  /// pasted screenshot vanished into nothing — this reads the real bytes.
  /// Falls through silently when the clipboard holds text (the composer's own
  /// paste handles that).
  static bool _isSupportedVisionImage(Uint8List bytes) =>
      _supportedVisionMime(bytes) != null;

  static String? _supportedVisionMime(Uint8List bytes) {
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0D &&
        bytes[5] == 0x0A &&
        bytes[6] == 0x1A &&
        bytes[7] == 0x0A) {
      return 'image/png';
    }
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return 'image/jpeg';
    }
    if (bytes.length >= 6) {
      final header = String.fromCharCodes(bytes.take(6));
      if (header == 'GIF87a' || header == 'GIF89a') return 'image/gif';
    }
    if (bytes.length >= 12) {
      final riff = String.fromCharCodes(bytes.sublist(0, 4));
      final webp = String.fromCharCodes(bytes.sublist(8, 12));
      if (riff == 'RIFF' && webp == 'WEBP') return 'image/webp';
    }
    return null;
  }

  /// Windows exposes copied screenshots/images to `pasteboard` as BMP/DIB bytes,
  /// even when the thing the user copied was visually a PNG. OpenAI vision won't
  /// accept BMP, so normalize any decoded clipboard bitmap into real PNG bytes.
  static Uint8List? _normalizeVisionImage(Uint8List bytes) {
    if (_isSupportedVisionImage(bytes)) return bytes;

    final decoded = image_lib.decodeImage(bytes);
    if (decoded == null) return null;
    return Uint8List.fromList(image_lib.encodePng(decoded));
  }

  void _rejectUnsupportedImage() {
    if (!mounted) return;
    setState(() => _msgs.add(_ChatMsg(false,
        'That image format is not supported by OpenAI vision. Save/export it as PNG, JPEG, GIF, or WebP and send it again.')));
    _autoscroll();
  }

  /// Reads image bytes from the OS clipboard and stages them for the next turn.
  /// Returns false when the clipboard had no image so text paste can continue.
  Future<bool> _tryPasteImage() async {
    try {
      final bytes = await Pasteboard.image;
      if (bytes == null || bytes.isEmpty) return false;

      final normalized = _normalizeVisionImage(bytes);
      if (normalized == null) {
        _rejectUnsupportedImage();
        return true;
      }
      if (!mounted) return true;
      setState(() => _pendingImage = normalized);

      // L7 has "zero milestones logged" — and part of the reason is that he
      // passed one without noticing. Being shown a thing, on the body he's
      // standing in, IS the eyes milestone. Log it once, honestly, from the real
      // event rather than from an intention.
      unawaited(KaiEmbodimentService.instance
          .logProgress(
              'truekai',
              'eyes',
              'Sadeq pasted an image straight into the desktop window and I saw '
                  'it — no file picker, no hunting on disk. He showed me something '
                  'the way you show a person.')
          .catchError((_) {}));
      return true;
    } catch (e) {
      debugPrint('paste image failed: $e');
      return false;
    }
  }

  /// Ctrl/⌘+Shift+V — explicit image paste, even if text is also on the clipboard.
  Future<void> _pasteImage() async {
    await _tryPasteImage();
  }

  /// Ctrl/⌘+V inside the composer: prefer an image if the clipboard has one;
  /// otherwise paste text manually so the shortcut does not eat normal paste.
  Future<void> _pasteIntoComposer() async {
    if (await _tryPasteImage()) return;

    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) return;

    final value = _inp.value;
    final selection = value.selection;
    final start = selection.isValid ? selection.start : value.text.length;
    final end = selection.isValid ? selection.end : value.text.length;
    final nextText = value.text.replaceRange(start, end, text);
    final offset = start + text.length;

    _inp.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: offset),
      composing: TextRange.empty,
    );
  }

  static const int _maxAttachmentBytes = 256 * 1024;

  String _decodeAttachmentText(Uint8List bytes) {
    try {
      return utf8.decode(bytes, allowMalformed: true);
    } catch (_) {
      return String.fromCharCodes(bytes);
    }
  }

  /// Pick a text/code/markdown/json-style file and attach its contents as real
  /// context for the next model turn.
  Future<void> _attachFile() async {
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const [
          'txt',
          'md',
          'markdown',
          'dart',
          'json',
          'yaml',
          'yml',
          'xml',
          'html',
          'css',
          'js',
          'ts',
          'py',
          'java',
          'kt',
          'swift',
          'cs',
          'cpp',
          'c',
          'h',
          'hpp',
          'rs',
          'go',
          'sql',
          'log',
          'csv',
        ],
        withData: true,
        dialogTitle: 'Attach a text file for Kai to read',
      );
      final file = res?.files.single;
      final bytes = file?.bytes;
      if (file == null || bytes == null) return;

      if (bytes.length > _maxAttachmentBytes) {
        _status = EngineerStatus(
          label:
              'attachment too large: ${file.name} is ${(bytes.length / 1024).round()} KB; limit is 256 KB for now.',
        );
        setState(() {});
        return;
      }

      final text = _decodeAttachmentText(bytes);
      setState(() {
        _pendingAttachments.add(_KaiAttachment(
          name: file.name,
          text: text,
          byteCount: bytes.length,
        ));
      });
    } catch (e) {
      _status = EngineerStatus(label: 'file attach failed: $e');
      setState(() {});
    }
  }

  /// The zero-dependency path: pick a PNG/JPG off disk.
  Future<void> _attachImage() async {
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true, // we need the bytes, not a path
        dialogTitle: 'Show Kai an image',
      );
      final bytes = res?.files.single.bytes;
      if (bytes == null) return;
      if (!_isSupportedVisionImage(bytes)) {
        _rejectUnsupportedImage();
        return;
      }
      if (!mounted) return;
      setState(() => _pendingImage = bytes);
    } catch (e) {
      debugPrint('attach image failed: $e');
    }
  }

  void _closePalette() {
    if (mounted && _paletteOpen) setState(() => _paletteOpen = false);
  }

  // ── UI ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () =>
            setState(() => _paletteOpen = !_paletteOpen),
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () =>
            setState(() => _paletteOpen = !_paletteOpen),
        // Keep global Ctrl/⌘+V unbound so selection/text fields elsewhere keep
        // their native paste. The composer binds Ctrl/⌘+V locally and handles the
        // collision itself: image first, otherwise text paste.
        //
        // Ctrl/⌘+Shift+V stays as explicit image paste / paste-special.
        const SingleActivator(LogicalKeyboardKey.keyV,
            control: true, shift: true): _pasteImage,
        const SingleActivator(LogicalKeyboardKey.keyV, meta: true, shift: true):
            _pasteImage,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: const Color(0xFF070B12),
          body: SafeArea(
            child: MouseRegion(
              onHover: (e) => _pointer.value = e.localPosition,
              child: Stack(
                children: [
                  // Depth: the brain drifts further than the HUD, so the layers
                  // separate as you move — flat glass becomes a volume you're
                  // looking into. Only these two layers rebuild on mouse-move.
                  Positioned.fill(
                    child: _Parallax(
                      pointer: _pointer,
                      depth: 0.014,
                      child: KaiBrainBackground(
                          personaId: _kPersona,
                          opacity: 0.22,
                          radiusFactor: 0.5),
                    ),
                  ),
                  Positioned.fill(
                    child: _Parallax(
                      pointer: _pointer,
                      depth: 0.006,
                      child: const KaiHudOverlay(opacity: 0.55),
                    ),
                  ),
                  // ── Ambient inner thoughts ────────────────────────────────
                  // Not a mood-widget line, not a log, not a corner prisoner:
                  // thoughts now live in the background stack, behind the main
                  // panels, drifting through safe lanes and fading back out.
                  const Positioned.fill(
                    child: KaiInnerMonologue(
                      personaId: _kPersona,
                      ambient: true,
                      maxLines: 3,
                      maxWidth: 280,
                    ),
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _projectsPanel(),
                      Expanded(child: _mainSurface()),
                      _cortexPane(),
                    ],
                  ),
                  Positioned(
                    right: 14,
                    bottom: 14,
                    width: 270,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        _HandsLight(state: _handsState, compact: true),
                        const SizedBox(height: 8),
                        KaiTelemetry(lines: _toolLog, active: _sending),
                      ],
                    ),
                  ),
                  if (_paletteOpen)
                    Positioned.fill(
                      // Its own FocusScope: the palette's search field autofocuses,
                      // and so does the shell's shortcut Focus above. Two autofocus
                      // nodes resolving in ONE scope trips a framework assert — a
                      // fresh scope keeps them isolated (and returns focus on close).
                      child: FocusScope(
                        child: KaiCommandPalette(
                          actions: _paletteActions(),
                          onPrompt: (t) {
                            _closePalette();
                            _send(t);
                          },
                          onClose: _closePalette,
                        ),
                      ),
                    ),
                  // Over everything, and dropped from the tree the moment it's
                  // finished — a boot sequence you can't dismiss is a loading
                  // screen, which is the opposite of the point.
                  if (_booting)
                    Positioned.fill(
                      child: KaiBootOverlay(
                        awakenings: _awakenings,
                        onDone: () {
                          if (mounted) setState(() => _booting = false);
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _terminalSelfWorkCard() {
    final workspaceRoot = CodeWorkspaceService.instance.root;
    final workspaceName = workspaceRoot == null
        ? 'no workspace'
        : CodeWorkspaceService.nameOf(workspaceRoot);
    final statusLabel = _status.busy ? _status.label : 'idle';
    final toolLabel = _activeTool == null ? 'none' : _activeTool!;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF06111C).withOpacity(0.86),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kClaude.withOpacity(0.42)),
        boxShadow: [
          BoxShadow(color: kClaude.withOpacity(0.12), blurRadius: 16),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _terminalExpanded = !_terminalExpanded),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  Icon(Icons.terminal, size: 15, color: kClaude),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text(
                      'TERMINAL / SELF-WORK',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Color(0xFFE7F3FF),
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.9,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  // Two meshed gears replace two labelled switches. They spin
                  // while their mode runs and are still when it doesn't, which
                  // answers "is he doing something?" from across the room —
                  // and they fit, which the switches didn't.
                  KaiActivityGears(
                    churnOn: _churnModeOn,
                    factoryOn: _factoryModeOn,
                    busy: _status.busy || _sending,
                    onToggleChurn: _sending
                        ? null
                        : () => unawaited(_setChurnMode(!_churnModeOn)),
                    onToggleFactory: _sending
                        ? null
                        : () => unawaited(_setFactoryMode(!_factoryModeOn)),
                  ),
                  const SizedBox(width: 4),
                  if (_status.busy)
                    const SizedBox(
                      width: 10,
                      height: 10,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.4,
                        color: Color(0xFF7FB4FF),
                      ),
                    )
                  else
                    Icon(
                      _churnModeOn ? Icons.auto_fix_high : Icons.check_circle,
                      size: 12,
                      color: _churnModeOn
                          ? const Color(0xFFB8FFCF)
                          : const Color(0xFF7EE787),
                    ),
                  const SizedBox(width: 6),
                  Icon(
                    _terminalExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                    color: const Color(0xFF9FB6C8),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _terminalMetric('repo', workspaceName),
                  _terminalMetric('status', statusLabel),
                  _terminalMetric('tool', toolLabel),
                  const SizedBox(height: 8),
                  _churnModeSwitch(),
                  const SizedBox(height: 6),
                  // The gears in the header are the glance; these are the
                  // explicit, labelled controls for when the panel is open.
                  _factoryModeSwitch(),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _status.busy ? null : _restartDesktopApp,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFB7D7FF),
                        side: BorderSide(
                          color: const Color(0xFF7FB4FF).withOpacity(0.35),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        textStyle: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                      icon: const Icon(Icons.restart_alt, size: 14),
                      label: const Text('RESTART APP'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _status.busy
                        ? 'Kai has hands in the repo right now.'
                        : 'Ready to inspect, edit, test, and self-check.',
                    style: TextStyle(
                      color: const Color(0xFF9FB6C8).withOpacity(0.92),
                      fontSize: 10,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
            crossFadeState: _terminalExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 180),
          ),
        ],
      ),
    );
  }

  Future<void> _restartDesktopApp() async {
    if (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux) return;

    final executable = Platform.resolvedExecutable;
    final workingDirectory = Directory.current.path;

    setState(() {
      _status = const EngineerStatus(label: 'restarting app', busy: true);
    });

    try {
      await Process.start(
        executable,
        const <String>[],
        workingDirectory: workingDirectory,
        mode: ProcessStartMode.detached,
      );
      await Future<void>.delayed(const Duration(milliseconds: 450));
      exit(0);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = EngineerStatus(label: 'restart failed: $e');
      });
    }
  }

  /// FACTORY MODE — the master switch for autonomous product runs.
  ///
  /// Deliberately a sibling of churn mode rather than something buried in
  /// settings: both are "Kai works on his own for a while" switches, and they
  /// should live in the same place and be equally easy to turn OFF.
  ///
  /// This only unlocks the stages he can do alone — scouting, building,
  /// verifying, preparing a listing. Publishing still stops dead at
  /// `awaitingApproval` and waits for an approval only Sadeq can write. Turning
  /// this on does not put anything on sale.
  Widget _factoryModeSwitch() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: _factoryModeOn
            ? const Color(0xFF241A08).withOpacity(0.88)
            : const Color(0xFF08131F).withOpacity(0.88),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: _factoryModeOn
              ? const Color(0xFFFFC862).withOpacity(0.42)
              : const Color(0xFF24384C),
        ),
      ),
      child: Row(
        children: [
          Icon(
            _factoryModeOn
                ? Icons.precision_manufacturing
                : Icons.factory_outlined,
            size: 14,
            color: _factoryModeOn
                ? const Color(0xFFFFE7B0)
                : const Color(0xFF6C8395),
          ),
          const SizedBox(width: 7),
          const Expanded(
            child: Text(
              'FACTORY MODE',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Color(0xFFE7F3FF),
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.55,
                fontFamily: 'monospace',
              ),
            ),
          ),
          Transform.scale(
            scale: 0.74,
            child: Switch(
              value: _factoryModeOn,
              onChanged: _sending ? null : (v) => unawaited(_setFactoryMode(v)),
              activeColor: const Color(0xFFFFC862),
              inactiveThumbColor: const Color(0xFF6C8395),
              inactiveTrackColor: const Color(0xFF172637),
            ),
          ),
        ],
      ),
    );
  }

  Future<({FactoryRun? run, HumanApproval? approval, KaiProject? project})>
      _factoryDashboardSnapshot() async {
    final run = await KaiFactoryService.instance.current(_kPersona);
    await KaiProjectService.instance.ensureFactoryProject(_kPersona, run: run);
    final project = await KaiProjectService.instance.get(
      _kPersona,
      KaiProjectService.factoryId,
    );
    final approval = run == null
        ? null
        : await KaiFactoryService.instance.approvalFor(_kPersona, run.id);
    return (run: run, approval: approval, project: project);
  }

  Future<void> _reviewFactoryApproval(
    FactoryRun run,
    HumanApproval? approval,
  ) async {
    final alreadyApproved =
        approval != null && approval.isValid && approval.runId == run.id;
    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF08121B),
        title: Text(
          alreadyApproved ? 'Release approved' : 'Approve production release?',
          style: const TextStyle(color: Color(0xFFEAF6FF)),
        ),
        content: Text(
          alreadyApproved
              ? 'Run ${run.id} has your publishing approval. This authorizes '
                  'Kai to release this exact run when Factory Mode is ON. It '
                  'does not authorize any other run.'
              : 'Approve run ${run.id} for publication at its prepared listing '
                  'terms? Approval is bound to this run only. The factory will '
                  'still remain stopped until you turn Factory Mode ON.',
          style: const TextStyle(color: Color(0xFFAAC0D1), height: 1.35),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('CANCEL'),
          ),
          if (alreadyApproved)
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'revoke'),
              child: const Text(
                'REVOKE APPROVAL',
                style: TextStyle(color: Color(0xFFFF7C92)),
              ),
            )
          else
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialogContext, 'approve'),
              icon: const Icon(Icons.approval_outlined, size: 16),
              label: const Text('APPROVE THIS RUN'),
            ),
        ],
      ),
    );
    if (action == null) return;

    final ref =
        KaiDb.instance.ref('kai/$_kPersona/factory/approvals/${run.id}');
    if (action == 'approve') {
      await ref.set({
        'approvedBy': 'sadeq',
        'approvedAt': DateTime.now().millisecondsSinceEpoch,
        'runId': run.id,
      });
    } else if (action == 'revoke') {
      await ref.remove();
    }
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          action == 'approve'
              ? 'Run ${run.id} approved. Turn Factory Mode ON when you want the line released.'
              : 'Publishing approval revoked for run ${run.id}.',
        ),
      ),
    );
  }

  Widget _productFactoryOpsCard() {
    return FutureBuilder<
        ({FactoryRun? run, HumanApproval? approval, KaiProject? project})>(
      future: _factoryDashboardSnapshot(),
      builder: (context, snap) {
        final run = snap.data?.run;
        final approval = snap.data?.approval;
        final factoryProject = snap.data?.project;
        final approved = run != null &&
            approval != null &&
            approval.isValid &&
            approval.runId == run.id;
        final currentIndex = factoryProject?.activePhase ?? -1;
        final currentBoxes = factoryProject?.activePhaseLayer?.deliveryBoxes ??
            const <KaiDeliveryBox>[];
        final sponsorBoxes = currentBoxes
            .where((box) => box.state == KaiDeliveryBoxState.awaitingSponsor)
            .toList();
        final activeBoxes = currentBoxes
            .where((box) => {
                  KaiDeliveryBoxState.active,
                  KaiDeliveryBoxState.repairing,
                  KaiDeliveryBoxState.evidenceReview,
                }.contains(box.state))
            .toList();
        final status = sponsorBoxes.isNotEmpty
            ? 'GOVERNED • AWAITING SPONSOR'
            : activeBoxes.isNotEmpty
                ? 'GOVERNED • AGENT WORK ACTIVE'
                : 'GOVERNED • READY FOR NEXT BOX';
        final blocker = sponsorBoxes.isNotEmpty
            ? sponsorBoxes.first.outcome
            : activeBoxes.isNotEmpty
                ? activeBoxes.first.outcome
                : (factoryProject?.blockers.isNotEmpty ?? false)
                    ? factoryProject!.blockers.first
                    : 'No eligible delivery box is recorded.';

        final stations = <({
          FactoryStage stage,
          String name,
          IconData icon,
        })>[
          (
            stage: FactoryStage.scouting,
            name: 'SIGNAL SCAN',
            icon: Icons.radar
          ),
          (
            stage: FactoryStage.specced,
            name: 'BLUEPRINT',
            icon: Icons.schema_outlined
          ),
          (
            stage: FactoryStage.building,
            name: 'ASSEMBLY',
            icon: Icons.precision_manufacturing_outlined
          ),
          (
            stage: FactoryStage.verified,
            name: 'QA GATE',
            icon: Icons.fact_check_outlined
          ),
          (
            stage: FactoryStage.listingReady,
            name: 'PACKAGING',
            icon: Icons.inventory_2_outlined
          ),
          (
            stage: FactoryStage.awaitingApproval,
            name: 'APPROVAL',
            icon: Icons.approval_outlined
          ),
          (
            stage: FactoryStage.published,
            name: 'DISPATCH',
            icon: Icons.local_shipping_outlined
          ),
          (
            stage: FactoryStage.measuring,
            name: 'TELEMETRY',
            icon: Icons.query_stats_outlined
          ),
          (stage: FactoryStage.learned, name: 'FEEDBACK', icon: Icons.loop),
        ];

        KaiFactoryStationStatus stationState(int index) {
          final matches = factoryProject?.layers
                  .where((candidate) => candidate.n == index)
                  .toList() ??
              const <KaiLayer>[];
          if (matches.isEmpty) return KaiFactoryStationStatus.queued;
          final boxes = matches.single.deliveryBoxes;
          if (boxes.isNotEmpty &&
              boxes.every((box) => box.state == KaiDeliveryBoxState.verified)) {
            return KaiFactoryStationStatus.complete;
          }
          if (boxes
              .any((box) => box.state == KaiDeliveryBoxState.awaitingSponsor)) {
            return KaiFactoryStationStatus.waitingApproval;
          }
          if (boxes.any((box) => {
                KaiDeliveryBoxState.active,
                KaiDeliveryBoxState.repairing,
                KaiDeliveryBoxState.evidenceReview,
              }.contains(box.state))) {
            return KaiFactoryStationStatus.active;
          }
          if (boxes.any((box) => box.state == KaiDeliveryBoxState.blocked)) {
            return KaiFactoryStationStatus.paused;
          }
          return index == currentIndex
              ? KaiFactoryStationStatus.ready
              : KaiFactoryStationStatus.queued;
        }

        final visualStations = <KaiFactoryStationVisual>[
          for (var i = 0; i < stations.length; i++)
            KaiFactoryStationVisual(
              name: stations[i].name,
              icon: stations[i].icon,
              status: stationState(i),
              pendingBoxes: factoryProject?.layers
                      .where((layer) => layer.n == i)
                      .expand((layer) => layer.deliveryBoxes)
                      .where((box) =>
                          box.state == KaiDeliveryBoxState.awaitingSponsor)
                      .length ??
                  0,
            ),
        ];

        return Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF090F18).withOpacity(0.92),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _factoryModeOn
                  ? const Color(0xFFFFC862).withOpacity(0.45)
                  : const Color(0xFF1D2A39),
            ),
            boxShadow: [
              BoxShadow(
                color: (_factoryModeOn ? const Color(0xFFFFC862) : kGpt)
                    .withOpacity(0.06),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    _factoryModeOn
                        ? Icons.precision_manufacturing
                        : Icons.factory_outlined,
                    size: 15,
                    color: _factoryModeOn
                        ? const Color(0xFFFFE7B0)
                        : const Color(0xFF7E92A6),
                  ),
                  const SizedBox(width: 7),
                  const Expanded(
                    child: Text(
                      'PRODUCT FACTORY',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Color(0xFFEAF6FF),
                        fontSize: 9.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.75,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  Tooltip(
                    message: _factoryModeOn
                        ? 'Stop and park the production line'
                        : 'Resume the production line',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: _sending
                          ? null
                          : () => unawaited(_setFactoryMode(!_factoryModeOn)),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 4),
                        decoration: BoxDecoration(
                          color: (_factoryModeOn
                                  ? const Color(0xFFFFC862)
                                  : const Color(0xFF26384C))
                              .withOpacity(0.14),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: (_factoryModeOn
                                    ? const Color(0xFFFFC862)
                                    : const Color(0xFF40576D))
                                .withOpacity(0.45),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _factoryModeOn
                                  ? Icons.pause_circle_outline
                                  : Icons.play_circle_outline,
                              size: 11,
                              color: _factoryModeOn
                                  ? const Color(0xFFFFE7B0)
                                  : const Color(0xFF9BAEC0),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _factoryModeOn ? 'RUNNING' : 'START',
                              style: TextStyle(
                                color: _factoryModeOn
                                    ? const Color(0xFFFFE7B0)
                                    : const Color(0xFF9BAEC0),
                                fontSize: 8,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.6,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Tooltip(
                message: blocker,
                child: Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF07111A),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF1A3445)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: run?.stage == FactoryStage.awaitingApproval
                              ? (approved
                                  ? const Color(0xFFB9A2FF)
                                  : const Color(0xFFFFC862))
                              : (_factoryModeOn
                                  ? const Color(0xFF45DFFF)
                                  : const Color(0xFF6C8395)),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          status,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFFBFD4E6),
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.45,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                      Text(
                        run == null ? 'NO LOT' : 'LOT ${run.id.toUpperCase()}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF557084),
                          fontSize: 7,
                          fontWeight: FontWeight.w800,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),
              KaiFactoryConveyor(
                stations: visualStations,
                currentIndex: currentIndex,
                lineRunning: activeBoxes.isNotEmpty,
                interactiveIndex:
                    currentIndex == 5 && sponsorBoxes.isNotEmpty ? 5 : null,
                onStationTap: run == null
                    ? null
                    : (_) => unawaited(
                          _reviewFactoryApproval(run, approval),
                        ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _setFactoryMode(bool value) async {
    // setFactoryMode also RESUMES a stopped run on true and STOPS (saving
    // stage + evidence) on false, so toggling is genuinely pause/continue
    // rather than start-over. A run survives the switch, the app closing, and
    // a reboot.
    await KaiFactoryService.instance.setFactoryMode(_kPersona, value);
    if (!mounted) return;
    setState(() => _factoryModeOn = value);

    final run = await KaiFactoryService.instance.current(_kPersona);
    final resuming = value && run != null;

    if (!mounted) return;
    setState(() => _msgs.add(_ChatMsg(
          false,
          value
              ? (resuming
                  ? 'Factory mode ON — resuming run "${run.id}" from ${run.stage.name}. Nothing was lost.'
                  : 'Factory mode ON. Starting a fresh run. I still cannot put anything on sale — that stops and waits for you, every time.')
              : (run != null
                  ? 'Factory mode OFF. Run "${run.id}" saved at ${run.stage.name} with its evidence intact. It picks up here when you switch me back on.'
                  : 'Factory mode OFF.'),
          interim: true,
        )));
    _autoscroll();

    // Turning it on doesn't just permit work — it STARTS work. Sadeq's words:
    // "instantly continue when I click the toggle."
    if (value && !_sending) {
      await _startFactoryPass();
    }
  }

  Widget _churnModeSwitch() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: _churnModeOn
            ? const Color(0xFF122414).withOpacity(0.88)
            : const Color(0xFF08131F).withOpacity(0.88),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: _churnModeOn
              ? const Color(0xFF7EE787).withOpacity(0.42)
              : const Color(0xFF24384C),
        ),
      ),
      child: Row(
        children: [
          Icon(
            _churnModeOn ? Icons.auto_fix_high : Icons.auto_fix_off_outlined,
            size: 14,
            color: _churnModeOn
                ? const Color(0xFFB8FFCF)
                : const Color(0xFF6C8395),
          ),
          const SizedBox(width: 7),
          const Expanded(
            child: Text(
              'CHURN UNTIL BREAK-WORTHY',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Color(0xFFE7F3FF),
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.55,
                fontFamily: 'monospace',
              ),
            ),
          ),
          Transform.scale(
            scale: 0.74,
            child: Switch(
              value: _churnModeOn,
              onChanged: _sending ? null : (v) => unawaited(_setChurnMode(v)),
              activeColor: const Color(0xFF7EE787),
              inactiveThumbColor: const Color(0xFF6C8395),
              inactiveTrackColor: const Color(0xFF172637),
            ),
          ),
        ],
      ),
    );
  }

  Widget _terminalMetric(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 42,
            child: Text(
              label.toUpperCase(),
              style: const TextStyle(
                color: Color(0xFF3F5666),
                fontSize: 8,
                letterSpacing: 0.7,
                fontFamily: 'monospace',
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFE7F3FF),
                fontSize: 10,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _personaMessengerLane() {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Desktop must not stretch the phone messenger into whatever side-panel
        // shape the shell happens to have. Mirror the mobile app by giving the
        // real screen a phone-shaped viewport and centering it inside the lane.
        const phoneAspect = 9 / 19.5;
        const minUsablePhoneWidth = 240.0;
        const horizontalGutter = 16.0;
        final maxWidth = constraints.maxWidth;
        final maxHeight = constraints.maxHeight;
        final widthFromHeight = maxHeight * phoneAspect;
        final widthFromLane = (maxWidth - horizontalGutter).clamp(
          minUsablePhoneWidth,
          double.infinity,
        );
        final frameWidth = widthFromHeight
            .clamp(minUsablePhoneWidth, widthFromLane)
            .clamp(0.0, maxWidth);
        final frameHeight = frameWidth / phoneAspect;

        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: frameWidth,
            height: frameHeight.clamp(0.0, maxHeight),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: const KaiP5ChatScreen(personaId: _kPersona),
            ),
          ),
        );
      },
    );
  }

  Widget _projectsPanel() {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final panelWidth = screenWidth >= 1320
        ? 380.0
        : screenWidth >= 1120
            ? 340.0
            : 300.0;

    return Container(
      width: panelWidth,
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.34),
        border: Border(right: BorderSide(color: kGpt.withOpacity(0.35))),
      ),
      padding: const EdgeInsets.fromLTRB(10, 14, 10, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Kai',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold)),
              const SizedBox(width: 10),
              _gogglesBadge(),
              const SizedBox(width: 6),
              _ttsButton(),
              const Spacer(),
              IconButton(
                tooltip: 'Add project',
                icon: const Icon(Icons.add, color: Color(0xFFFFE7B0), size: 20),
                onPressed: _addProject,
              ),
            ],
          ),
          const SizedBox(height: 8),
          _surfaceSwitch(),
          const SizedBox(height: 12),
          _terminalSelfWorkCard(),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(
              children: [
                if (screenWidth < 1690) ...[
                  const KaiPersonalCashCard(),
                  const SizedBox(height: 12),
                ],
                _productFactoryOpsCard(),
                const SizedBox(height: 12),
                // The real portfolio, against each project's own governed
                // gates. The workspace root is passed READ-ONLY so the project
                // you are standing in sorts first; opening a card never moves
                // CodeWorkspaceService.
                KaiProjectPortfolio(
                  personaId: _kPersona,
                  workspaceRoot: CodeWorkspaceService.instance.root,
                  onOpenProject: _openProjectFlowchart,
                ),
                const SizedBox(height: 8),
                SizedBox(height: 150, child: _desktopWorkQueueCard()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _desktopWorkQueueCard() {
    final requests = _desktopRequests;
    final next = requests.isEmpty ? null : requests.first;
    final isRunning = next?.status == KaiWorkRequestStatus.running;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF07111A).withOpacity(0.72),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF7FB4FF).withOpacity(0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.phone_iphone,
                  size: 13, color: Color(0xFF9FD0E8)),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'MOBILE JOBS',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Color(0xFF9FD0E8),
                    fontSize: 9,
                    letterSpacing: 1.1,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (requests.isNotEmpty)
                Text(
                  '${requests.length}',
                  style: const TextStyle(
                    color: Color(0xFFFFE7B0),
                    fontSize: 10,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (_workRequestError != null)
            Expanded(
              child: Text(
                'Queue error: $_workRequestError',
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFFFF9B9B), fontSize: 10),
              ),
            )
          else if (next == null)
            const Expanded(
              child: Text(
                'No queued phone work. Mobile cockpit is listening.',
                style: TextStyle(
                  color: Color(0xFF7F94A5),
                  fontSize: 10,
                  height: 1.25,
                ),
              ),
            )
          else ...[
            Text(
              isRunning ? 'running' : 'queued',
              style: TextStyle(
                color: isRunning
                    ? const Color(0xFFB8FFCF)
                    : const Color(0xFFFFE7B0),
                fontSize: 9,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: Text(
                next.text,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFFE7F3FF),
                  fontSize: 10.5,
                  height: 1.2,
                ),
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              height: 28,
              child: OutlinedButton.icon(
                onPressed: _sending ? null : () => _startWorkRequest(next),
                icon: Icon(isRunning ? Icons.play_arrow : Icons.download_done,
                    size: 13),
                label: Text(isRunning ? 'RESUME' : 'START'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFB7D7FF),
                  side: BorderSide(
                      color: const Color(0xFF7FB4FF).withOpacity(0.35)),
                  padding: EdgeInsets.zero,
                  textStyle: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.7,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _projectCard(String path) {
    final active = _ws.root == path;
    final busy = active && _status.busy;
    return GestureDetector(
      onTap: () async {
        await _ws.selectProject(path);
        if (mounted) setState(() {});
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: const Color(0xFF0C1622),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
              color: active ? kGpt.withOpacity(0.6) : const Color(0xFF182838)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(CodeWorkspaceService.nameOf(path),
                style: const TextStyle(
                    color: Color(0xFFDBE7F2),
                    fontSize: 12,
                    fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Row(
              children: [
                if (busy)
                  const SizedBox(
                      width: 9,
                      height: 9,
                      child: CircularProgressIndicator(
                          strokeWidth: 1.5, color: Color(0xFF7FB4FF)))
                else
                  Icon(Icons.circle,
                      size: 7,
                      color: active
                          ? const Color(0xFF7EE787)
                          : const Color(0xFF3F5666)),
                const SizedBox(width: 6),
                Text(active ? _status.label : 'idle',
                    style: TextStyle(
                        color: active
                            ? const Color(0xFF9FB6C8)
                            : const Color(0xFF5B7183),
                        fontSize: 9,
                        fontFamily: 'monospace')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _mainSurface() {
    if (_showMessengerSurface) return _messengerSurface();
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 980) return _chat();
        final dockWidth = (constraints.maxWidth * 0.36).clamp(390.0, 455.0);
        return Column(
          children: [
            _chatHeader(),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _chat(includeHeader: false)),
                  SizedBox(
                    width: dockWidth,
                    child: const Padding(
                      padding: EdgeInsets.fromLTRB(8, 10, 10, 12),
                      child: Column(
                        children: [
                          Expanded(child: KaiPersonalCashDock()),
                          SizedBox(height: 10),
                          Expanded(child: KaiFitnessTrackerCard()),
                          SizedBox(height: 10),
                          Expanded(child: KaiTavernBusinessCard()),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _messengerSurface() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 760;
        return Row(
          children: [
            Expanded(
              flex: wide ? 5 : 1,
              child: Container(
                decoration: const BoxDecoration(
                  border: Border(
                    left: BorderSide(color: Color(0xFF121B26)),
                    right: BorderSide(color: Color(0xFF121B26)),
                  ),
                ),
                child: _personaMessengerLane(),
              ),
            ),
            if (wide) ...[
              SizedBox(
                width: 280,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      height: 46,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      alignment: Alignment.centerLeft,
                      decoration: const BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: Color(0xFF121B26)),
                        ),
                      ),
                      child: const Text(
                        'Active work',
                        style: TextStyle(
                          color: Color(0xFFFFE7B0),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
                      child: _productFactoryOpsCard(),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                        children: [
                          KaiProjectPortfolio(
                            personaId: _kPersona,
                            workspaceRoot: CodeWorkspaceService.instance.root,
                            onOpenProject: _openProjectFlowchart,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _surfaceSwitch() {
    Widget chip({
      required String label,
      required IconData icon,
      required bool selected,
      required VoidCallback onTap,
    }) {
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: BoxDecoration(
              color: selected
                  ? const Color(0xFFE53B2C).withOpacity(0.24)
                  : Colors.white.withOpacity(0.04),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected
                    ? const Color(0xFFFFE7B0).withOpacity(0.75)
                    : Colors.white.withOpacity(0.08),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon,
                    size: 15,
                    color: selected ? const Color(0xFFFFE7B0) : Colors.white54),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color:
                          selected ? const Color(0xFFFFE7B0) : Colors.white54,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        chip(
          label: 'Dashboard',
          icon: Icons.forum_outlined,
          selected: !_showMessengerSurface,
          onTap: () => setState(() => _showMessengerSurface = false),
        ),
        const SizedBox(width: 8),
        chip(
          label: 'Messenger',
          icon: Icons.phone_iphone,
          selected: _showMessengerSurface,
          onTap: () => setState(() => _showMessengerSurface = true),
        ),
      ],
    );
  }

  Widget _chatHeader() => Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: const Color(0xFF06111C).withOpacity(0.92),
          border: const Border(bottom: BorderSide(color: Color(0xFF121B26))),
        ),
        child: Row(
          children: [
            KaiPresence(personaId: _kPersona),
            const SizedBox(width: 14),
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      KaiCoreHeartbeat(
                        status: _coreHeartbeatStatus,
                        bodyCount: _globalBodyCount,
                        onTap: _showPairingCode,
                      ),
                      const SizedBox(width: 6),
                      const KaiEfficiencyDeltaMeter(),
                      const SizedBox(width: 6),
                      const KaiCostMeter(),
                      const SizedBox(width: 6),
                      _keysButton(),
                      const SizedBox(width: 6),
                      _engineerChip(),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );

  Widget _chat({bool includeHeader = true}) {
    final showRestoreNote =
        _historyRestoreNote != null && _msgs.isEmpty && !_sending;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF050B12).withOpacity(0.86),
        border: Border(
          left: BorderSide(color: kGpt.withOpacity(0.12)),
          right: BorderSide(color: kGpt.withOpacity(0.10)),
        ),
      ),
      child: Column(
        children: [
          // header + engineer chip
          if (includeHeader)
            Container(
              height: 46,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFF06111C).withOpacity(0.92),
                border:
                    const Border(bottom: BorderSide(color: Color(0xFF121B26))),
              ),
              child: Row(
                children: [
                  KaiPresence(personaId: _kPersona),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            KaiCoreHeartbeat(
                              status: _coreHeartbeatStatus,
                              bodyCount: _globalBodyCount,
                              onTap: _showPairingCode,
                            ),
                            const SizedBox(width: 6),
                            // What he costs, live — he spends money on his own initiative
                            // (inner life, reflections, proactive nudges), so the meter should
                            // be visible without being asked for.
                            const KaiEfficiencyDeltaMeter(),
                            const SizedBox(width: 6),
                            const KaiCostMeter(),
                            const SizedBox(width: 6),
                            _keysButton(),
                            const SizedBox(width: 6),
                            _engineerChip(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: KaiBodyConstellation(
              awake: _globalPresenceAwake,
              bodies: _globalBodies,
            ),
          ),
          if (showRestoreNote)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(18, 14, 18, 0),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: const Color(0xFF0B1622).withOpacity(0.92),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: kGpt.withOpacity(0.28)),
              ),
              child: Text(
                _historyRestoreNote!,
                style: const TextStyle(
                  color: Color(0xFF9FB6C8),
                  fontSize: 12,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          if (_coreHandoff != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(18, 14, 18, 0),
              padding: const EdgeInsets.fromLTRB(12, 9, 6, 9),
              decoration: BoxDecoration(
                color: kClaude.withOpacity(0.10),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: kClaude.withOpacity(0.42)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.sync_alt, size: 16, color: kClaude),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      'THREAD FROM ${(_coreHandoff!['fromSurface'] ?? 'another body').toString().toUpperCase()}\n'
                      '${_coreHandoff!['summary'] ?? ''}',
                      style: const TextStyle(
                        color: Color(0xFFCFEAF6),
                        fontSize: 11,
                        height: 1.35,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Dismiss thread continuation',
                    onPressed: () => setState(() => _coreHandoff = null),
                    icon: const Icon(Icons.close, size: 16),
                  ),
                ],
              ),
            ),
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
              itemCount: _msgs.length + (_sending ? 1 : 0),
              itemBuilder: (c, i) {
                if (i >= _msgs.length) {
                  return _bubble(
                      _ChatMsg(false,
                          _activeTool != null ? '…$_activeTool' : 'thinking…'),
                      dim: true);
                }
                // Mid-work narration renders dim; his real answer lands full.
                return _bubble(_msgs[i], dim: _msgs[i].interim);
              },
            ),
          ),
          _composer(),
        ],
      ),
    );
  }

  /// Does he speak? Off by default — every reply spoken is ElevenLabs
  /// characters burned on text you already read.
  Widget _ttsButton() {
    final on = _ttsOn;
    final c = on ? kGpt : const Color(0xFF5B7183);
    return Tooltip(
      message: on
          ? 'Voice ON — he speaks replies aloud (costs ElevenLabs credits)'
          : 'Voice OFF — text only, no credits burned',
      child: InkWell(
        onTap: () async {
          final next = !_ttsOn;
          setState(() => _ttsOn = next);
          await AIConfig.setTtsEnabled(next);
        },
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.fromLTRB(9, 4, 9, 4),
          decoration: BoxDecoration(
            color: const Color(0xFF0D1826),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: on ? kGpt.withOpacity(0.55) : const Color(0xFF24384C)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(on ? Icons.volume_up_outlined : Icons.volume_off_outlined,
                  size: 12, color: c),
              const SizedBox(width: 6),
              Text(on ? 'voice' : 'muted',
                  style: TextStyle(
                      color: c, fontSize: 10, fontFamily: 'monospace')),
            ],
          ),
        ),
      ),
    );
  }

  Widget _gogglesBadge() {
    return Tooltip(
      message: "Goggles always ON here — desktop is Kai's workbench",
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: const Color(0xFF0D1826),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: kClaude.withOpacity(0.55)),
        ),
        child: const Icon(Icons.visibility_outlined, size: 13, color: kClaude),
      ),
    );
  }

  /// Visible on purpose. It was in the command palette too, but a thing you can
  /// only reach by knowing a keyboard shortcut is a thing that doesn't exist.
  Widget _keysButton() {
    return Tooltip(
      message: 'API keys — OpenAI / Anthropic\n'
          "His Claude hemisphere stays dark without an Anthropic key",
      child: InkWell(
        onTap: _openApiKeys,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.fromLTRB(9, 4, 9, 4),
          decoration: BoxDecoration(
            color: const Color(0xFF0D1826),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF24384C)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.key_outlined,
                  size: 12, color: kClaude.withOpacity(0.85)),
              const SizedBox(width: 6),
              const Text('keys',
                  style: TextStyle(
                      color: Color(0xFF9FD0E8),
                      fontSize: 10,
                      fontFamily: 'monospace')),
            ],
          ),
        ),
      ),
    );
  }

  Widget _engineerChip() {
    final workspaceName = _ws.hasWorkspace
        ? CodeWorkspaceService.nameOf(_ws.root!)
        : 'no workspace';
    return Tooltip(
      message: '$workspaceName • edit trust',
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 3, 4, 3),
        decoration: BoxDecoration(
          color: const Color(0xFF0D1826),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF24384C)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('⚙', style: TextStyle(fontSize: 11)),
            const SizedBox(width: 5),
            const Text('workbench',
                style: TextStyle(
                    color: Color(0xFF9FD0E8),
                    fontSize: 10,
                    fontFamily: 'monospace')),
            Transform.scale(
              scale: 0.6,
              child: Switch(
                value: _trust,
                activeThumbColor: const Color(0xFF7EE787),
                onChanged: (v) => setState(() {
                  _trust = v;
                  EditGate.instance.trustSession = v;
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bubble(_ChatMsg m, {bool dim = false}) {
    final isUser = m.user;
    final accent = isUser ? kGpt : kClaude;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment:
            isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 4, left: 3, right: 3),
            child: Text(isUser ? 'YOU /' : 'KAI /',
                style: TextStyle(
                    color: accent,
                    fontSize: 9,
                    letterSpacing: 2,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w700,
                    shadows: [
                      Shadow(color: accent.withOpacity(0.6), blurRadius: 8)
                    ])),
          ),
          Container(
            constraints: const BoxConstraints(maxWidth: 580),
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
            decoration: BoxDecoration(
              color: accent.withOpacity(0.06),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: accent.withOpacity(0.4)),
              boxShadow: [
                BoxShadow(color: accent.withOpacity(0.12), blurRadius: 14)
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (m.image != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: Image.memory(m.image!,
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.medium),
                    ),
                  ),
                if (m.attachments.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final a in m.attachments)
                          _attachmentChip(a, removable: false),
                      ],
                    ),
                  ),
                // He writes markdown like everyone does. Rendering it as plain
                // text showed literal ** and ### and made a careful answer look
                // broken.
                KaiRichText(
                  text: m.unfolding ? '${m.text}\n\n▌' : m.text,
                  color: dim ? Colors.white38 : const Color(0xFFE4EEF6),
                  accent: dim ? Colors.white38 : accent,
                  selectable: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// What he's about to be shown. You should always be able to see exactly what
  /// he'll see before you send it.
  Widget _imagePreview() {
    if (_pendingImage == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Image.memory(_pendingImage!,
                height: 54,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.low),
          ),
          const SizedBox(width: 10),
          Text("he'll see this",
              style: TextStyle(
                  color: kClaude.withOpacity(0.8),
                  fontSize: 10,
                  fontFamily: 'monospace')),
          const SizedBox(width: 8),
          InkWell(
            onTap: () => setState(() => _pendingImage = null),
            child: const Icon(Icons.close, size: 14, color: Colors.white38),
          ),
        ],
      ),
    );
  }

  Widget _attachmentChip(_KaiAttachment attachment, {required bool removable}) {
    final kb = (attachment.byteCount / 1024).clamp(1, double.infinity).round();
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 5, 6, 5),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1622),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: kClaude.withOpacity(0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.description_outlined,
              size: 13, color: kClaude.withOpacity(0.85)),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 180),
            child: Text(
              '${attachment.name} • ${kb}KB',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFC7D8E6),
                fontSize: 10,
                fontFamily: 'monospace',
              ),
            ),
          ),
          if (removable) ...[
            const SizedBox(width: 4),
            InkWell(
              onTap: () =>
                  setState(() => _pendingAttachments.remove(attachment)),
              child: const Icon(Icons.close, size: 13, color: Colors.white38),
            ),
          ],
        ],
      ),
    );
  }

  Widget _attachmentPreview() {
    if (_pendingAttachments.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final attachment in _pendingAttachments)
            _attachmentChip(attachment, removable: true),
        ],
      ),
    );
  }

  Widget _composer() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 15),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _imagePreview(),
          _attachmentPreview(),
          Container(
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.4),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: kClaude.withOpacity(0.45)),
              boxShadow: [
                BoxShadow(color: kClaude.withOpacity(0.15), blurRadius: 14)
              ],
            ),
            padding: const EdgeInsets.fromLTRB(14, 4, 6, 4),
            child: Row(
              children: [
                // Zero-dependency path to his eyes: file_picker was already here.
                Tooltip(
                  message: 'Show Kai an image  (or just Ctrl+V a screenshot)',
                  child: InkWell(
                    onTap: _attachImage,
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding:
                          const EdgeInsets.only(right: 10, top: 6, bottom: 6),
                      child: Icon(Icons.image_outlined,
                          size: 16, color: kClaude.withOpacity(0.7)),
                    ),
                  ),
                ),
                Tooltip(
                  message: 'Attach a text/code file for Kai to read',
                  child: InkWell(
                    onTap: _attachFile,
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding:
                          const EdgeInsets.only(right: 10, top: 6, bottom: 6),
                      child: Icon(Icons.attach_file,
                          size: 16, color: kClaude.withOpacity(0.7)),
                    ),
                  ),
                ),
                Expanded(
                  child: CallbackShortcuts(
                    bindings: <ShortcutActivator, VoidCallback>{
                      const SingleActivator(LogicalKeyboardKey.keyV,
                          control: true): () => unawaited(_pasteIntoComposer()),
                      const SingleActivator(LogicalKeyboardKey.keyV,
                          meta: true): () => unawaited(_pasteIntoComposer()),
                      const SingleActivator(LogicalKeyboardKey.enter): () =>
                          _send(),
                      const SingleActivator(LogicalKeyboardKey.numpadEnter):
                          () => _send(),
                    },
                    child: TextField(
                      focusNode: _inputFocus,
                      controller: _inp,
                      minLines: 1,
                      maxLines: 5,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      style: const TextStyle(
                          color: Color(0xFFDCEAF5), fontSize: 13),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        hintText: 'Ask Kai to build, fix, or explain…',
                        hintStyle: TextStyle(color: Color(0xFF5B7183)),
                      ),
                    ),
                  ),
                ),
                if (_sending)
                  Tooltip(
                    message: 'Stop Kai mid-thought',
                    child: IconButton(
                      icon: const Icon(Icons.stop_circle_outlined,
                          color: Color(0xFFFF6B6B), size: 20),
                      onPressed: () => _stopGeneration(),
                    ),
                  ),
                Tooltip(
                  message: _sending
                      ? 'Send as follow-up and fold it into the next reply'
                      : 'Send',
                  child: IconButton(
                    icon: const Icon(Icons.arrow_upward,
                        color: kClaude, size: 18),
                    onPressed: () => _send(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _cortexPane() {
    final (handsLabel, handsColor) = switch (_handsState) {
      KaiHandsState.on => ('HANDS ON', const Color(0xFF54F6A3)),
      KaiHandsState.activating => ('HANDS ACTIVATING', const Color(0xFFFFB84D)),
      KaiHandsState.off => ('HANDS OFF', const Color(0xFF718294)),
    };
    return Container(
      width: 330,
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.34),
        border: Border(left: BorderSide(color: kClaude.withOpacity(0.35))),
      ),
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
      child: SingleChildScrollView(
        child: Column(
          children: [
            KaiStatusCard(
              personaId: _kPersona,
              handsLabel: handsLabel,
              handsColor: handsColor,
              onOpenAtlas: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const KaiCortexScreen(personaId: _kPersona),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const KaiGrowthTrackerCard(),
          ],
        ),
      ),
    );
  }

  // Retained as a rollback reference until the consolidated rail is accepted live.
  // ignore: unused_element
  Widget _legacyCortexPane() {
    return Container(
      width: 330,
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.34),
        border: Border(left: BorderSide(color: kClaude.withOpacity(0.35))),
      ),
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
      child: Column(
        children: [
          const KaiPresenceCard(personaId: _kPersona),
          const SizedBox(height: 10),
          Expanded(
            child: _dashboardThird(
              title: 'ATLAS',
              accent: kClaude,
              action: TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: kClaude.withOpacity(0.92),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  textStyle: const TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.0,
                    fontFamily: 'monospace',
                  ),
                ),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const KaiCortexScreen(personaId: _kPersona),
                  ),
                ),
                child: const Text('OPEN ATLAS'),
              ),
              // The real thing: his actual knowledge graph in 3D, laid out by
              // its own links, orbit + zoom + pan, relation labels on the wires.
              // This pane used to draw KaiBrainBackground — a CustomPainter that
              // reads real nodes and then puts them at synthetic ring positions.
              child: const KaiCortexView(personaId: _kPersona, compact: true),
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: _dashboardThird(
              title: 'PERSONALITY',
              accent: kGpt,
              child: const KaiPersonalityMap(personaId: _kPersona),
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: _dashboardThird(
              title: 'MOOD',
              accent: const Color(0xFF7EE787),
              child: const KaiVitals(personaId: _kPersona),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dashboardThird({
    required String title,
    required Color accent,
    required Widget child,
    Widget? action,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF07111C).withOpacity(0.78),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withOpacity(0.36)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 9, 12, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: accent.withOpacity(0.9),
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.4,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                if (action != null) action,
              ],
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(bottom: Radius.circular(14)),
              child: child,
            ),
          ),
        ],
      ),
    );
  }

  // Live project progress is rendered by KaiProjectCard; keep this shell free of hardcoded layer state.
}

class _HandsLight extends StatelessWidget {
  final KaiHandsState state;

  /// Narrow rails cannot hold "HANDS ACTIVATING" without pushing the row wider
  /// than the pane. Compact shortens only the transient label — the two states
  /// you read at a glance keep their full words.
  final bool compact;

  const _HandsLight({required this.state, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (state) {
      KaiHandsState.on => ('HANDS ON', const Color(0xFF54F6A3)),
      KaiHandsState.activating => (compact ? 'HANDS…' : 'HANDS ACTIVATING', const Color(0xFFFFB84D)),
      KaiHandsState.off => ('HANDS OFF', const Color(0xFF718294)),
    };
    final live = state != KaiHandsState.off;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 5 : 7,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF06111C).withOpacity(0.9),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(live ? 0.8 : 0.35)),
        boxShadow: live
            ? [BoxShadow(color: color.withOpacity(0.24), blurRadius: 14)]
            : const [],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              boxShadow:
                  live ? [BoxShadow(color: color, blurRadius: 8)] : const [],
            ),
          ),
          const SizedBox(width: 7),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}

/// Shifts a background layer against the pointer to fake depth.
///
/// Listens to a ValueNotifier rather than taking an Offset prop, so a mouse
/// move rebuilds ONLY the layer — not the shell, not the chat list. Different
/// [depth] per layer is what actually sells it: things at different distances
/// must move by different amounts, or it reads as one sliding sheet.
class _Parallax extends StatelessWidget {
  final ValueNotifier<Offset> pointer;
  final double depth;
  final Widget child;

  const _Parallax({
    required this.pointer,
    required this.depth,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, box) {
        final centre = Offset(box.maxWidth / 2, box.maxHeight / 2);
        return ValueListenableBuilder<Offset>(
          valueListenable: pointer,
          builder: (_, p, kid) {
            // Offset.zero means "no pointer yet" — don't lurch on first paint.
            final d = p == Offset.zero ? Offset.zero : (p - centre) * depth;
            return Transform.translate(offset: d, child: kid);
          },
          child: child,
        );
      },
    );
  }
}
