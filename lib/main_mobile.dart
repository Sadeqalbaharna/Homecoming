// main_mobile.dart
// Mobile-compatible version without desktop-specific dependencies

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'services/core/edit_gate.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'services/ai/ai_service.dart';
import 'services/core/firebase_service.dart';
import 'services/core/kai_global_presence_service.dart';
import 'services/core/memory_consolidation_service.dart';
import 'services/core/brain_extraction_service.dart';
import 'services/core/kai_working_on_service.dart';
import 'services/automation/wake_on_lan_service.dart';
import 'services/voice/voice_activation_service.dart';
import 'services/voice/voice_service.dart';
import 'services/voice/kai_quick_responses.dart';
import 'services/core/native_audio_recorder.dart';
import 'services/automation/home_automation_service.dart';
import 'screens/home_remote_screen.dart';
import 'screens/chaos_journal_screen.dart';
import 'screens/mind_map_screen.dart';
import 'screens/kai_cortex_screen.dart';
import 'screens/activity_feed_screen.dart';
import 'screens/worlds_screen.dart';
import 'screens/kai_desktop_shell.dart';
import 'screens/kai_p5_chat_screen.dart';
import 'services/core/activity_card_service.dart';
import 'firebase_options.dart';
import 'widgets/debug_button.dart';
import 'api_key_setup_screen.dart';
import 'services/core/kai_state_service.dart';
import 'services/core/emotional_event_service.dart';
import 'services/core/memory_reflection_service.dart';
import 'services/core/kai_reflection_worker.dart';
import 'services/core/personality_drift_service.dart';
import 'services/core/proactive_service.dart';
import 'services/core/default_mode_service.dart';
import 'services/ai/proactive_service.dart' as aiProactive;
import 'services/voice/attention_sound_service.dart';
import 'services/core/context_injection_service.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:permission_handler/permission_handler.dart';
import 'services/ai/task_planner_service.dart';
import 'services/ai/usage_tracking_service.dart';
import 'services/core/tavern_service.dart';
import 'services/core/tavern_menu_service.dart';
import 'services/core/tavern_status_service.dart';
import 'screens/tavern_register_screen.dart';
import 'screens/tavern_link_screen.dart';
import 'widgets/plan_card.dart';
import 'constants.dart';
import 'services/core/kai_surface_context.dart';
import 'services/core/kai_headless_coordinator.dart';
import 'services/core/kai_graceful_shutdown_service.dart';

/// ===== Layout / Window =====
/// Local to this file on purpose — nothing else lays out the avatar. These used
/// to be duplicated in constants.dart, where the copies quietly disagreed
/// (kSpriteAlignY was 0.35 there, 0.30 here) because neither was ever read from
/// the other file. kCanvasWidth/Height/kSpriteAlignY/kUiLiftPx/kIdleAfter were
/// dead in both places and are gone.
const double kSpriteSize = 170;
const double kRingPadding = 48;

/// ===== Avatar assets + timings =====
const String kAvatarIdleFrameDir = 'assets/avatar/idle_frames/';
const String kAvatarAttentionFrameDir = 'assets/avatar/attention_frames/';
const String kAvatarThinkingFrameDir = 'assets/avatar/thinking_frames/';
const String kAvatarSpeakingFrameDir = 'assets/avatar/speaking_frames/';
const String kAvatarFallback = 'assets/avatar/images/mage.png';
const int kIdleFrameCount = 121;
const int kAttentionFrameCount = 121;
const int kThinkingFrameCount = 241;
const int kSpeakingFrameCount = 121;

const Duration kAttentionPulse = Duration(seconds: 2);

// kPersonaKai now comes from constants.dart — one canonical 'truekai'.

/// Global AI service instance
final aiService = AIService();

Future<void> main([List<String> args = const []]) async {
  WidgetsFlutterBinding.ensureInitialized();

  final coordinatorMode = args.contains('--coordinator-worker');
  final recoveredCoordinator = args.contains('--recovered');

  // Show loading state while initializing
  if (!coordinatorMode) {
    runApp(const MaterialApp(
      home: Scaffold(
        backgroundColor: Color(0xFF0D0A07),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Color(0xFFFFE7B0)),
              SizedBox(height: 20),
              Text(
                'Initializing Kai...',
                style: TextStyle(color: Colors.white, fontSize: 18),
              ),
            ],
          ),
        ),
      ),
    ));
  }

  // Initialize Firebase with error handling
  bool firebaseInitialized = false;
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    await FirebaseService.initialize();
    firebaseInitialized = true;
    print('✅ Firebase initialized successfully');
    // Sign in anonymously so RTDB rules (auth != null) accept reads/writes on
    // EVERY platform. The desktop shell bypasses the mobile widget's own init.
    try {
      final a = FirebaseAuth.instance;
      if (a.currentUser == null) {
        await a.signInAnonymously();
        print('🔐 [Auth] Signed in anonymously: ${a.currentUser?.uid}');
      } else {
        print('🔐 [Auth] Already signed in: ${a.currentUser?.uid}');
      }
    } catch (e) {
      print('⚠️ [Auth] main() sign-in failed: $e');
    }
    if (!coordinatorMode) {
      // Pre-warm Tavern caches (non-blocking)
      TavernMenuService().prime().catchError((_) {});
      TavernStatusService()
          .getStatusBlock()
          .then<void>((_) {})
          .catchError((Object e) {
        print('[TavernStatus] getStatusBlock prewarm failed: $e');
      });
    }
  } catch (e) {
    print('⚠️ Firebase initialization failed: $e');
    print('📱 App will continue with local storage only');
  }

  if (coordinatorMode) {
    final coordinator = KaiHeadlessCoordinator.instance;
    await coordinator.start(
      recovered: recoveredCoordinator,
    );
    final shutdownService = KaiGracefulShutdownService(
      onDrain: coordinator.gracefulStop,
      audit: coordinator.auditShutdownEvent,
    );
    await shutdownService.start();
    return;
  }

  // Run the actual app
  runApp(KaiMobileApp(firebaseInitialized: firebaseInitialized));
}

class KaiMobileApp extends StatelessWidget {
  final bool firebaseInitialized;

  const KaiMobileApp({super.key, required this.firebaseInitialized});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Kai - AI Avatar',
      navigatorKey: EditGate.navigatorKey,
      theme: ThemeData(
        scaffoldBackgroundColor: const Color(0xFF0D0A07),
        primarySwatch: Colors.amber,
        brightness: Brightness.dark,
      ),
      // Kai has one brain but many presences. On a computer his home is the
      // desktop shell (engineer + companion cockpit); on phones the app is a
      // mobile presence into the same Kai.
      home: _isDesktop
          ? const KaiDesktopShell()
          : _MobileKai(firebaseInitialized: firebaseInitialized),
    );
  }

  /// True on Windows / macOS / Linux (not web, not mobile).
  bool get _isDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
}

class _MobileKai extends StatefulWidget {
  final bool firebaseInitialized;

  const _MobileKai({required this.firebaseInitialized});

  @override
  State<_MobileKai> createState() => _MobileKaiState();
}

class _Floater {
  final String text;
  final Color color;
  final double angle;
  final AnimationController ctrl;
  _Floater({
    required this.text,
    required this.color,
    required this.angle,
    required this.ctrl,
  });
}

class _MobileKaiState extends State<_MobileKai>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  // persona
  final String _personaId = kPersonaKai;

  // glow
  late final AnimationController _glowCtrl;
  late final Animation<double> _glow;

  // loading screen
  bool _isLoading = true;
  String _loadingStep = 'Starting up…';

  // background mode guard — prevents concurrent enter/exit calls
  bool _inBackgroundTransition = false;

  // true while the flame is (or should be) showing
  bool _isSleeping = false;

  // true while the user is holding the avatar for hold-to-speak
  bool _isHoldingToSpeak = false;

  // Silence-detection timer used during wake-word-triggered auto-recording
  Timer? _silenceTimer;

  // Drag-guard for hold-to-speak: recording only starts after a still hold.
  // If the finger moves > _kDragThreshold px before the timer fires, it's a
  // drag and recording is suppressed entirely.
  static const double _kDragThreshold = 10.0; // px of movement = drag intent
  static const Duration _kHoldDelay =
      Duration(milliseconds: 400); // must be still this long to activate mic
  Offset? _pressOrigin;
  bool _pressWasDrag = false;
  Timer? _holdTimer;

  // fallback lifecycle observer — if the overlay "expand" message is dropped
  // (common when the engine is paused on physical devices), this catches the
  // app coming back to foreground and calls _exitBackground() anyway.
  AppLifecycleListener? _lifecycleListener;

  // background mode overlay
  StreamSubscription<String>? _wakeWordSub;
  StreamSubscription? _overlayMsgSub;
  Timer? _idleBackgroundTimer;

  // bubble state
  bool _showBubble = false;
  bool _devOpen = false;
  final _controller = TextEditingController();
  final _focus = FocusNode();
  String? _reply;
  String? _error;
  List<String>? _choices;
  bool _sending = false;
  String? _activeToolName; // tool currently running in agentic loop
  KaiPlan? _activePlan; // multi-step plan being executed (null = no plan)
  bool _planExpanded = true;

  // Proactive attention
  aiProactive.ProactiveEvent? _pendingProactiveEvent;
  bool _isAttentionSeeking = false;

  // Tavern guest arrivals
  TavernGuest? _tavernGuest;
  String? _tavernBriefing;
  List<String> _memoriesUsed = []; // NEW: Track memories used in response
  Map<String, dynamic>? _debugInfo; // NEW: Track debug info from AI response

  // audio
  final _player = AudioPlayer();
  late final StreamSubscription<PlayerState> _stateSub;
  PlayerState _currentState = PlayerState.stopped;

  bool _ttsLoading = false;
  String? _ttsPath;
  bool _autoPlayTts = true;
  bool _adaptToUser = false;
  String _modelId = 'gpt-4o';
  final int _ctxTurns = 8; // Reduced from 20 — episodic memory covers the rest

  // delta bubbles
  final List<_Floater> _floaters = [];
  final Random _rng = Random();

  // avatar state machine
  // frame-based animation
  String _currentAnimation = 'idle';
  AnimationController? _frameAnimController;
  // _currentFrame and _idleTicker removed — AnimatedBuilder reads the
  // controller value directly, so no setState per frame is needed.

  void _setStep(String step) {
    if (mounted) setState(() => _loadingStep = step);
  }

  Future<void> _initialize() async {
    try {
      // Close stale overlay from a previous session — but only if we're not
      // intentionally in sleep mode (avoids killing a live overlay on hot restart)
      if (!_isSleeping) {
        try {
          if (await FlutterOverlayWindow.isActive()) {
            await FlutterOverlayWindow.closeOverlay();
            print('🔵 [Init] Closed stale overlay from previous session');
          }
        } catch (_) {}
      }

      // 0 — request runtime permissions Kai needs (one-time, non-blocking)
      unawaited(Future(() async {
        await [
          Permission.contacts,
          Permission.calendar,
        ].request();

        // Check notification access — prompt user to grant it if missing
        const channel = MethodChannel('com.homecoming.app/kai_tools');
        final hasNotifAccess = await channel
            .invokeMethod<bool>('checkNotificationAccess')
            .catchError((_) => false);
        if (hasNotifAccess == false && mounted) {
          await showDialog(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('Enable Notification Access'),
              content: const Text(
                'To let Kai read your WhatsApp messages and other notifications, '
                'grant Notification Access.\n\n'
                'Settings → Apps → Special app access → Notification access → Homecoming',
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    channel.invokeMethod('openNotificationSettings');
                  },
                  child: const Text('Open Settings'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Later'),
                ),
              ],
            ),
          );
        }

        // Check accessibility access — prompt user if missing (needed for read_screen)
        final hasA11y = await channel
            .invokeMethod<bool>('checkAccessibilityAccess')
            .catchError((_) => false);
        if (hasA11y == false && mounted) {
          await showDialog(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('Enable Screen Reading'),
              content: const Text(
                'To let Kai read your screen and help with emails, messages, '
                'and anything you\'re looking at, enable Accessibility access.\n\n'
                'Settings → Accessibility → Installed apps → Homecoming → enable',
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    channel.invokeMethod('openAccessibilitySettings');
                  },
                  child: const Text('Open Settings'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Later'),
                ),
              ],
            ),
          );
        }

        // Pre-warm context cache after permissions may have been granted
        unawaited(ContextInjectionService().prime());
      }));

      // 1 — avatar frames (kick off async, don't block showing the UI)
      _setStep('Loading avatar…');
      _precacheAnimation(kAvatarIdleFrameDir, kIdleFrameCount).then((_) {
        if (mounted) _switchToAnimation('idle');
      }).catchError((Object e) {
        print('⚠️ [Init] Frame precache: $e');
      });

      // 1b — sign in anonymously so Firebase rules accept our reads/writes
      _setStep('Connecting…');
      try {
        final auth = FirebaseAuth.instance;
        if (auth.currentUser == null) {
          await auth.signInAnonymously();
          print('🔐 [Auth] Signed in anonymously: ${auth.currentUser?.uid}');
        } else {
          print('🔐 [Auth] Already signed in: ${auth.currentUser?.uid}');
        }
      } catch (e) {
        print('⚠️ [Auth] Anonymous sign-in failed: $e');
      }

      // 2 — warm up the AI persona (3s max — Firebase permission errors fail fast anyway)
      _setStep('Waking Kai…');
      await aiService
          .bootstrapPersona(_personaId)
          .timeout(const Duration(seconds: 3), onTimeout: () {})
          .catchError((e) => print('⚠️ [Bootstrap] $e'));

      // 3 — check for a message Kai left while we were away (3s max)
      _setStep('Checking messages…');
      await ProactiveService()
          .initialize(_personaId)
          .timeout(const Duration(seconds: 3), onTimeout: () {})
          .catchError((e) => print('⚠️ [Proactive] $e'));
      final pending = await ProactiveService()
          .checkPendingMessage(_personaId)
          .timeout(const Duration(seconds: 3), onTimeout: () => null)
          .catchError((e) {
        print('⚠️ [Proactive] $e');
        return null;
      });
      if (pending != null && mounted) {
        await ProactiveService().markDelivered(_personaId, pending.id);
        setState(() => _reply = pending.message);
        _setBubble(true);
      }

      // 3b — watch Tavern door for NFC guest arrivals
      if (widget.firebaseInitialized) {
        TavernService().startWatching(
          onArrival: _onTavernArrival,
        );
      }

      // 4 — wake word detection
      unawaited(VoiceActivationService()
          .initialize()
          .catchError((e) => print('⚠️ [WakeWord] $e')));

      // 4b — pre-generate / load Kai quick-response clips (yes?, hmm?, etc.)
      unawaited(KaiQuickResponses.instance
          .initialize()
          .catchError((e) => print('⚠️ [QuickResponses] $e')));

      // 5 — proactive Kai (attention sounds + contextual messages)
      unawaited(AttentionSoundService()
          .prime()
          .catchError((e) => print('⚠️ [AttentionSound] $e')));
      final proactiveSvc = aiProactive.ProactiveService();
      proactiveSvc.onProactiveEvent = _onProactiveEvent;
      unawaited(proactiveSvc
          .initialize(_personaId)
          .catchError((e) => print('⚠️ [Proactive] $e')));

      // Done — show UI immediately, other animations load on first use
      if (mounted) setState(() => _isLoading = false);
      MemoryReflectionService()
          .maybeReflect(personaId: _personaId)
          .catchError((e) => print('⚠️ [Reflection] $e'));
      KaiReflectionWorker.instance.start(_personaId);
      PersonalityDriftService()
          .maybeDrift(personaId: _personaId)
          .catchError((e) => print('⚠️ [Drift] $e'));
      // Look at the shape of his own memory and park anything genuinely odd —
      // a contradiction he holds, a belief he revised, a preference whose reason
      // he never learned. This is the second feeder for `noticed`, the one that
      // needs no tool call, so the messenger Kai (tools off) finally has more
      // than one thing on his mind. Fire-and-forget; a failed reflection must
      // never block the app opening.
      //
      // NOT `.then(...).catchError((e) => print(...))`: on a Future<int> that
      // handler "might complete normally" without returning an int — the §4
      // latent-crash smell Kai caught here at :462. A plain async/try-catch has
      // no such trap.
      unawaited(() async {
        try {
          final n = await BrainExtractionService().reflectAndNotice(_personaId);
          if (n > 0) print('🔎 [Notice] parked $n new observation(s)');
        } catch (e) {
          print('⚠️ [Notice] $e');
        }
      }());
      // Give him the broad strokes of what we're building — once, if he's never
      // had them. So he knows the arc of his own project instead of being told
      // about it every time.
      unawaited(() async {
        try {
          await KaiWorkingOnService.instance.seedOnce(_personaId);
        } catch (e) {
          print('⚠️ [WorkingOn] $e');
        }
      }());
      // first-run only: offer to link the customer's NFC badge to their account
      unawaited(_maybePromptTavernLink());
    } catch (e) {
      print('❌ [Init] $e');
      // Don't block the user — just open the app
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// On first launch (once), prompt the hero to tap their NFC badge so it gets
  /// bound to their account via /nfc_links. No-op after a successful link.
  Future<void> _maybePromptTavernLink() async {
    try {
      if (await TavernLink.isLinked()) return;
      if (FirebaseAuth.instance.currentUser == null) return;
      await Future.delayed(const Duration(milliseconds: 600));
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const TavernLinkScreen()),
      );
    } catch (e) {
      print('⚠️ [TavernLink] $e');
    }
  }

  void _markInteraction() {
    _resetIdleTimer();
  }

  Future<void> _setBubble(bool open) async {
    if (_showBubble == open) return;
    setState(() => _showBubble = open);
    if (open) {
      await VoiceActivationService().pause();
    } else {
      VoiceActivationService().resume();
    }
  }

  void _resetIdleTimer() {
    _idleBackgroundTimer?.cancel();
    // Auto-sleep disabled — user controls background mode via the flame button.
    // Re-enable by uncommenting the timer below.
    // _idleBackgroundTimer = Timer(const Duration(minutes: 3), () {
    //   if (mounted && !_sending && !_isSpeaking) {
    //     print('💤 [BackgroundMode] 3-min idle — entering background');
    //     _enterBackground();
    //   }
    // });
  }

  void _pulseAttention() {
    _switchToAnimation('attention');
    // Return to idle after pulse expires
    Future.delayed(kAttentionPulse, () {
      if (mounted && !_isSpeaking && !_sending) _switchToAnimation('idle');
    });
    setState(() {});
  }

  bool get _isSpeaking => _currentState == PlayerState.playing;

  int _getFrameCount(String animType) {
    switch (animType) {
      case 'attention':
        return kAttentionFrameCount;
      case 'thinking':
        return kThinkingFrameCount;
      case 'speaking':
        return kSpeakingFrameCount;
      default:
        return kIdleFrameCount;
    }
  }

  String _getFrameDir(String animType) {
    switch (animType) {
      case 'attention':
        return kAvatarAttentionFrameDir;
      case 'thinking':
        return kAvatarThinkingFrameDir;
      case 'speaking':
        return kAvatarSpeakingFrameDir;
      default:
        return kAvatarIdleFrameDir;
    }
  }

  // Tracks which animation dirs are loaded so we only evict on a real switch
  final Set<String> _cachedAnimDirs = {};

  Future<void> _precacheAnimation(String dir, int frameCount) async {
    if (_cachedAnimDirs.contains(dir)) return; // already loaded
    final futures = List.generate(frameCount, (i) {
      final path = '${dir}frame_${i.toString().padLeft(4, '0')}.png';
      return precacheImage(AssetImage(path), context);
    });
    await Future.wait(futures, eagerError: false);
    _cachedAnimDirs.add(dir);
  }

  void _evictAnimation(String dir, int frameCount) {
    if (!_cachedAnimDirs.contains(dir)) return;
    for (int i = 0; i < frameCount; i++) {
      final path = '${dir}frame_${i.toString().padLeft(4, '0')}.png';
      imageCache.evict(AssetImage(path));
    }
    _cachedAnimDirs.remove(dir);
  }

  void _switchToAnimation(String animType) {
    if (_currentAnimation == animType && _frameAnimController != null) return;
    final prevAnim = _currentAnimation;
    _currentAnimation = animType;
    _frameAnimController?.dispose();
    final frameCount = _getFrameCount(animType);
    _frameAnimController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: frameCount * 40), // ~25 fps
    )..repeat();

    // Lazy-load new animation, then evict the previous one to free RAM
    final newDir = _getFrameDir(animType);
    final prevDir = _getFrameDir(prevAnim);
    _precacheAnimation(newDir, frameCount).then((_) {
      if (prevAnim != animType) {
        _evictAnimation(prevDir, _getFrameCount(prevAnim));
      }
    });

    // No addListener+setState — AnimatedBuilder reads controller.value directly
    setState(() {}); // single rebuild to swap controller reference
  }

  Widget _buildAvatarWidget() {
    final ctrl = _frameAnimController;
    if (ctrl == null) {
      return Image.asset(kAvatarFallback, fit: BoxFit.cover);
    }
    final dir = _getFrameDir(_currentAnimation);
    final frameCount = _getFrameCount(_currentAnimation);
    return AnimatedBuilder(
      animation: ctrl,
      builder: (_, __) {
        final frame =
            (ctrl.value * frameCount).floor().clamp(0, frameCount - 1);
        final framePath = '${dir}frame_${frame.toString().padLeft(4, '0')}.png';
        return Image.asset(
          framePath,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) =>
              Image.asset(kAvatarFallback, fit: BoxFit.cover),
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    unawaited(KaiGlobalPresenceService.instance
        .startBody(
      surface: 'messenger',
      canBootstrapOwner: false,
    )
        .catchError((Object error) {
      print('[KaiPresence] mobile registry failed to start: $error');
    }));
    WidgetsBinding.instance.addObserver(this);
    KaiStateService().setSurface('mobile');
    EmotionalEventService().setSurface('mobile');
    _glowCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat(reverse: true);
    _glow = Tween(begin: 0.35, end: 1.0)
        .chain(CurveTween(curve: Curves.easeInOut))
        .animate(_glowCtrl);

    WidgetsBinding.instance.addPostFrameCallback((_) => _initialize());

    _stateSub = _player.onPlayerStateChanged.listen((s) async {
      _currentState = s;

      // Switch animation based on audio state
      if (s == PlayerState.playing) {
        _switchToAnimation('speaking');
        print('🔇 [MAIN_MOBILE] Audio playing - PAUSING voice activation');
        await VoiceActivationService().pause();
      } else if (s == PlayerState.stopped || s == PlayerState.completed) {
        _switchToAnimation('idle');
        // Don't resume VAS if hold-to-speak is active — the mic belongs to the recorder
        if (!_isHoldingToSpeak) {
          print(
              '🔊 [MAIN_MOBILE] Audio stopped/completed - RESUMING voice activation');
          VoiceActivationService().resume();
        } else {
          print(
              '🔊 [MAIN_MOBILE] Audio stopped/completed - hold-to-speak active, skipping VAS resume');
        }
      }

      if (mounted) setState(() {});
    });

    // Fallback lifecycle observer — on physical devices the overlay "expand"
    // message is sometimes dropped while the engine is paused. This catches the
    // app resuming to foreground and calls _exitBackground() if we think we're
    // still sleeping.
    _lifecycleListener = AppLifecycleListener(
      onResume: () {
        if (_isSleeping && !_inBackgroundTransition) {
          print(
              '🔵 [BackgroundMode] Lifecycle resume — triggering _exitBackground fallback');
          _exitBackground();
        }
      },
    );

    // Listen for messages from the flame overlay
    _overlayMsgSub = FlutterOverlayWindow.overlayListener.listen((data) async {
      if (data is! Map) return;
      final action = data['action'];
      if (action == 'expand') {
        // Tap: expand the app normally
        _exitBackground();
      } else if (action == 'pauseVoice') {
        // Legacy compat
        await VoiceActivationService().pause();
      } else if (action == 'startRecording') {
        // Flame hold-to-speak ↓: release mic from sherpa, then open recorder
        await VoiceActivationService().pause();
        setState(() => _isHoldingToSpeak = true);
        final started = await VoiceService().startRecording();
        if (!started) {
          setState(() => _isHoldingToSpeak = false);
          print('❌ [HoldToSpeak-flame] Failed to start recording');
        } else {
          print('🎤 [HoldToSpeak-flame] Recording started');
        }
      } else if (action == 'stopRecording') {
        // Flame push-to-talk ↑: stop recording and decide: tap vs voice.
        // Recording starts immediately on press-down, so a quick tap produces
        // a tiny file (<8 KB ≈ <0.7s). Treat that as a tap → expand the app.
        print('🎤 [HoldToSpeak-flame] Stopping recording…');
        setState(() => _isHoldingToSpeak = false);
        final path = await VoiceService().stopRecording();
        VoiceActivationService().resume();
        if (path == null) {
          print(
              '⚠️ [HoldToSpeak-flame] No audio file — treating as tap → expand');
          _exitBackground();
        } else {
          final fileSize = await File(path).length().catchError((Object e) {
            print('⚠️ [HoldToSpeak-flame] file length failed: $e');
            return 0;
          });
          if (fileSize < 8000) {
            // Too short (~<0.7s) → quick tap, not a voice message → expand
            print(
                '⚠️ [HoldToSpeak-flame] File too small ($fileSize B) → tap → expand');
            await File(path).delete().then<void>((_) {}).catchError((Object e) {
              print('⚠️ [HoldToSpeak-flame] temp delete failed: $e');
            });
            _exitBackground();
          } else {
            print('🎤 [HoldToSpeak-flame] Transcribing $path ($fileSize B)…');
            final transcript = await VoiceService().transcribeAudio(path);
            if (transcript != null && transcript.trim().isNotEmpty && mounted) {
              print('🎤 [HoldToSpeak-flame] Transcript: "$transcript"');
              _exitBackground(); // bring app forward, then inject the message
              // Small delay so the UI is fully visible before _send() runs
              await Future.delayed(const Duration(milliseconds: 300));
              if (mounted) {
                _controller.text = transcript.trim();
                _setBubble(true);
                _send();
              }
            } else {
              print('⚠️ [HoldToSpeak-flame] Empty transcript — not sending');
            }
          }
        }
      } else if (action == 'message') {
        // Legacy: plain-text transcript from old code path
        final text = (data['text'] as String? ?? '').trim();
        if (text.isNotEmpty) {
          _controller.text = text;
          _send();
        }
        VoiceActivationService().resume();
      }
    });

    // Subscribe to wake-word events (VoiceActivationService singleton)
    _wakeWordSub =
        VoiceActivationService().onWakeWordDetected.listen((transcript) {
      if (!mounted) return;
      // VAS always emits 'hey kai' — it's the raw wake trigger.
      _exitBackground();
      _handleWakeWordActivation();
    });

    // Start 3-minute idle-to-background timer
    _resetIdleTimer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    aiProactive.ProactiveService().stop();
    _holdTimer?.cancel();
    _lifecycleListener?.dispose();
    _glowCtrl.dispose();
    _frameAnimController?.dispose();
    _controller.dispose();
    _focus.dispose();
    _stateSub.cancel();
    _wakeWordSub?.cancel();
    _overlayMsgSub?.cancel();
    _idleBackgroundTimer?.cancel();
    _silenceTimer?.cancel();
    _player.dispose();
    unawaited(KaiGlobalPresenceService.instance.stop());
    for (final f in _floaters) {
      f.ctrl.dispose();
    }
    super.dispose();
  }

  // ── Background mode ────────────────────────────────────────────────────────

  Future<void> _enterBackground() async {
    if (_inBackgroundTransition) return;
    if (_isSleeping) return; // already in sleep mode
    _inBackgroundTransition = true;
    // Safety timeout — never leave _inBackgroundTransition stuck forever
    Future.delayed(const Duration(seconds: 8), () {
      if (_inBackgroundTransition) {
        _inBackgroundTransition = false;
        print('⚠️ [BackgroundMode] Transition timeout — reset flag');
      }
    });
    try {
      _idleBackgroundTimer?.cancel();

      // Check / request overlay permission
      final hasPermission = await FlutterOverlayWindow.isPermissionGranted();
      if (!hasPermission) {
        await FlutterOverlayWindow.requestPermission();
        if (!await FlutterOverlayWindow.isPermissionGranted()) {
          print('⚠️ [BackgroundMode] No overlay permission — minimizing only');
          await _minimizeApp();
          return;
        }
      }

      // Request battery optimization exemption so the foreground service
      // isn't killed by aggressive device power management (Samsung, Xiaomi, etc.)
      await _requestBatteryExemption();

      // Stop heavy animations
      _frameAnimController?.stop();
      _glowCtrl.stop();

      // 1. Minimize FIRST so the app is gone before the flame appears
      await _minimizeApp();
      // Physical devices need more time than emulators to complete the transition
      await Future.delayed(const Duration(milliseconds: 600));

      // 2. Show the flame — retry up to 3 times (service start is async on device)
      for (int attempt = 1; attempt <= 3; attempt++) {
        await FlutterOverlayWindow.showOverlay(
          height: 120,
          width: 90,
          alignment: OverlayAlignment.centerRight,
          flag: OverlayFlag.defaultFlag,
          enableDrag: true,
          positionGravity: PositionGravity.auto,
          overlayTitle: 'Kai',
          overlayContent: 'Tap the flame to open Kai',
        );
        await Future.delayed(const Duration(milliseconds: 600));
        if (await FlutterOverlayWindow.isActive()) {
          print(
              '🔵 [BackgroundMode] Overlay confirmed active (attempt $attempt)');
          break;
        }
        print(
            '⚠️ [BackgroundMode] Overlay not active after attempt $attempt — retrying');
      }

      _isSleeping = true;
      print('🔵 [BackgroundMode] Entered sleep mode');

      final pending = await ProactiveService().checkPendingMessage(_personaId);
      await FlutterOverlayWindow.shareData({'pending': pending != null});
    } catch (e, st) {
      print('❌ [BackgroundMode] _enterBackground error: $e\n$st');
    } finally {
      _inBackgroundTransition = false;
    }
  }

  Future<void> _minimizeApp() async {
    try {
      const channel = MethodChannel('com.homecoming.app/activity');
      await channel.invokeMethod<void>('moveTaskToBack');
      print('🔵 [BackgroundMode] App moved to background');
    } catch (e) {
      print('❌ [BackgroundMode] moveTaskToBack failed: $e');
    }
  }

  /// Ask Android to exempt us from battery optimization so the overlay
  /// foreground service isn't killed on physical devices (Samsung, Xiaomi, etc.).
  /// Only shown once — Android remembers the user's choice.
  Future<void> _requestBatteryExemption() async {
    try {
      const channel = MethodChannel('com.homecoming.app/activity');
      await channel.invokeMethod<void>('requestBatteryExemption');
    } catch (_) {
      // Non-fatal — device may not support it or it's already granted
    }
  }

  Future<void> _exitBackground({String? initialMessage}) async {
    if (_inBackgroundTransition) return;
    _isSleeping =
        false; // clear immediately — lifecycle listener won't re-trigger
    _inBackgroundTransition = true;
    // Safety timeout
    Future.delayed(const Duration(seconds: 5), () {
      if (_inBackgroundTransition) {
        _inBackgroundTransition = false;
        print('⚠️ [BackgroundMode] Exit transition timeout — reset flag');
      }
    });
    try {
      // Close the floating overlay if it's still up
      try {
        if (await FlutterOverlayWindow.isActive()) {
          await FlutterOverlayWindow.closeOverlay();
        }
      } catch (_) {}

      if (!mounted) return;

      // Resume full-mode animations
      // Clear _currentAnimation so _switchToAnimation always does a full restart
      // (the guard skips if already 'idle', even when the controller was stopped)
      _currentAnimation = '';
      _glowCtrl.repeat(reverse: true);
      _switchToAnimation('idle');

      // Restart idle timer — user is active again
      _resetIdleTimer();
      print('🌟 [BackgroundMode] Exited — full mode restored');

      // If woken by voice, send the transcript to Kai
      if (initialMessage != null && initialMessage.trim().isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          setState(() => _controller.text = initialMessage);
          _setBubble(true);
          _send();
        });
      }
    } finally {
      _inBackgroundTransition = false;
    }
  }

  // ── Wake-word auto-record flow ─────────────────────────────────────────────

  /// Called when "Hey Kai" fires. Plays a voice ack ("yes?"), then
  /// auto-records until 3 s of silence, transcribes, and sends.
  Future<void> _handleWakeWordActivation() async {
    if (!mounted) return;

    // Release the KWS mic immediately — must happen before any recording attempt,
    // and before audio playback (which would also try to pause, but async).
    await VoiceActivationService().pause();

    // Mark recording BEFORE playing TTS so the stateSub doesn't resume VAS
    // when the "yes?" audio completes.
    setState(() {
      _isHoldingToSpeak = true;
      _showBubble = true;
    });
    _switchToAnimation('attention');

    // ── 1. Say "yes?" — instant from local cache ─────────────────────────
    try {
      await KaiQuickResponses.instance.play('yes', _player);
    } catch (e) {
      print('⚠️ [WakeWord] Quick response playback failed: $e');
    }

    if (!mounted) return;

    // ── 2. Start recording (mic is free — VAS already paused) ────────────
    _switchToAnimation('attention');
    final started = await VoiceService().startRecording();
    if (!started) {
      print('❌ [WakeWord] Could not start recording');
      setState(() => _isHoldingToSpeak = false);
      VoiceActivationService().resume();
      _switchToAnimation('idle');
      return;
    }
    print('🎤 [WakeWord] Recording — waiting for your command…');

    // ── 3. Silence detection ─────────────────────────────────────────────
    _startWakeSilenceDetection();
  }

  void _startWakeSilenceDetection() {
    // MediaRecorder amplitude is a 0-32767 peak-since-last-call meter.
    // Anything below ~500 is background noise / silence.
    const int kSilenceThreshold = 500;
    const int kPollMs = 300; // poll every 300 ms
    const int kSilenceDurationMs = 3000; // 3 s of silence → stop
    const int kMinRecordMs = 800; // don't cut off immediately

    int silentMs = 0;
    int elapsedMs = 0;

    _silenceTimer?.cancel();
    _silenceTimer =
        Timer.periodic(const Duration(milliseconds: kPollMs), (timer) async {
      if (!mounted || !_isHoldingToSpeak) {
        timer.cancel();
        return;
      }

      elapsedMs += kPollMs;

      int amplitude = 0;
      try {
        amplitude = await NativeAudioRecorder().getAmplitude();
      } catch (_) {}

      if (amplitude < kSilenceThreshold) {
        silentMs += kPollMs;
        if (silentMs >= kSilenceDurationMs && elapsedMs >= kMinRecordMs) {
          timer.cancel();
          await _finishWakeRecording();
        }
      } else {
        silentMs = 0; // voice detected — reset silence counter
      }
    });
  }

  Future<void> _finishWakeRecording() async {
    if (!_isHoldingToSpeak) return;
    setState(() => _isHoldingToSpeak = false);
    _switchToAnimation('thinking');

    final path = await VoiceService().stopRecording();
    // VAS resume is handled by stateSub after Kai's TTS response completes.
    // If we bail early, resume manually below.

    if (path == null || !mounted) {
      _switchToAnimation('idle');
      VoiceActivationService().resume();
      return;
    }

    final fileSize = await File(path).length().catchError((Object e) {
      print('⚠️ [WakeWord] file length failed: $e');
      return 0;
    });
    if (fileSize < 4000) {
      // Too short — background noise, not a real command
      await File(path).delete().then<void>((_) {}).catchError((Object e) {
        print('⚠️ [WakeWord] temp delete failed: $e');
      });
      print('⚠️ [WakeWord] Recording too short ($fileSize B) — ignoring');
      _switchToAnimation('idle');
      VoiceActivationService().resume();
      return;
    }

    print('🎤 [WakeWord] Transcribing ($fileSize B)…');
    final transcript = await VoiceService().transcribeAudio(path);

    if (transcript != null && transcript.trim().isNotEmpty && mounted) {
      print('🎤 [WakeWord] Transcript: "$transcript"');
      setState(() => _controller.text = transcript.trim());
      await _setBubble(true);
      _send();
    } else {
      print('⚠️ [WakeWord] Empty transcript — resuming VAS');
      _switchToAnimation('idle');
      VoiceActivationService().resume();
    }
  }

  // ── End wake-word auto-record flow ────────────────────────────────────────

  void _spawnDeltas(Map<String, int> deltas) {
    final items = deltas.entries.where((e) => e.value.abs() > 0).toList();
    final capped = items.take(6).toList();

    for (final e in capped) {
      final val = e.value;
      final isPos = val >= 0;
      final color = isPos ? Colors.lightGreenAccent : Colors.redAccent;
      final sign = isPos ? '+' : '';
      final text = '$sign$val ${_prettyName(e.key)}';
      final angle = _rng.nextDouble() * 2 * pi;

      final ctrl = AnimationController(
          vsync: this, duration: const Duration(milliseconds: 1800));
      final f = _Floater(text: text, color: color, angle: angle, ctrl: ctrl);
      setState(() => _floaters.add(f));
      ctrl.forward();
      ctrl.addStatusListener((st) {
        if (st == AnimationStatus.completed) {
          ctrl.dispose();
          if (mounted) setState(() => _floaters.remove(f));
        }
      });
    }
  }

  String _prettyName(String k) {
    switch (k) {
      case 'extraversion':
        return 'Extraversion';
      case 'intuition':
        return 'Intuition';
      case 'feeling':
        return 'Feeling';
      case 'perceiving':
        return 'Perceiving';
      case 'valence':
        return 'Valence';
      case 'energy':
        return 'Energy';
      case 'warmth':
        return 'Warmth';
      case 'confidence':
        return 'Confidence';
      case 'playfulness':
        return 'Playfulness';
      case 'focus':
        return 'Focus';
      default:
        return k;
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    _controller.clear(); // clear immediately so double-taps don't re-send
    // Clear any pending proactive state — user is now active
    if (_isAttentionSeeking) {
      setState(() {
        _isAttentionSeeking = false;
        _pendingProactiveEvent = null;
      });
    }
    unawaited(aiProactive.ProactiveService().stampInteraction());
    _switchToAnimation('thinking');
    setState(() {
      _sending = true;
      _reply = null;
      _error = null;
      _ttsPath = null;
      _devOpen = false;
      _memoriesUsed = []; // Clear previous memories
      _activePlan = null;
      _planExpanded = true;
      _choices = null;
    });
    try {
      final resp = await aiService.sendMessage(
        text: text,
        personaId: _personaId,
        model: _modelId,
        surfaceContext: KaiSurfaceContext.mobile,
        adaptUser: _adaptToUser,
        ctxTurns: _ctxTurns,
        onToolCall: (toolName) {
          if (mounted) setState(() => _activeToolName = toolName);
        },
        onPlanUpdate: (plan) {
          if (mounted) setState(() => _activePlan = plan);
        },
      );
      await _applyKaiResponse(resp, activityUserMessage: text);

      // Note: Conversation already saved to Firebase in ai_service.sendMessage()
    } catch (e) {
      setState(() {
        _error = e.toString();
        _devOpen = true;
      });
    } finally {
      if (!_isSpeaking) _switchToAnimation('idle');
      setState(() {
        _sending = false;
        _activeToolName = null;
      });
    }
  }

  // ── Lifecycle observer ────────────────────────────────────────────────────

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _drainWorkerProactive();
    } else if (state == AppLifecycleState.paused) {
      // DMN: trigger Kai's mind-wandering when the app backgrounds.
      // Fire-and-forget — never blocks the UI. Stores a thought in Firebase
      // that gets consumed naturally at the next session start.
      DefaultModeService()
          .runWandering(_personaId)
          .catchError((e) => print('⚠️ [DMN] $e'));
    }
  }

  /// Check if WorkManager left a proactive message while the app was closed.
  Future<void> _drainWorkerProactive() async {
    try {
      const ch = MethodChannel('com.homecoming.app/activity');
      final raw = await ch.invokeMethod<Map>('consumePendingProactive');
      if (raw == null || !mounted) return;
      final mood = raw['mood'] as String? ?? 'curious';
      final message = raw['message'] as String? ?? '';
      final trigger = raw['trigger'] as String? ?? 'worker';
      if (message.isEmpty) return;
      _onProactiveEvent(aiProactive.ProactiveEvent(
        mood: mood == 'worried' ? AttentionMood.worried : AttentionMood.curious,
        message: message,
        trigger: trigger,
      ));
    } catch (_) {}
  }

  // ── Proactive attention ───────────────────────────────────────────────────

  /// Called by TavernService when a guest taps in via NFC.
  void _onTavernArrival(TavernGuest guest, String briefing) {
    if (!mounted) return;
    AttentionSoundService().play(AttentionMood.curious);
    setState(() {
      _tavernGuest = guest;
      _tavernBriefing = briefing;
    });
    _pulseAttention();
  }

  /// Called by ProactiveService when Kai has something to say.
  void _onProactiveEvent(aiProactive.ProactiveEvent event) {
    if (!mounted) return;
    // Play the mood-appropriate attention sound
    AttentionSoundService().play(event.mood);
    // Store the pending message and pulse avatar in amber
    setState(() {
      _pendingProactiveEvent = event;
      _isAttentionSeeking = true;
    });
    // Make sure the glow is looping so the amber pulse is animated
    if (!_glowCtrl.isAnimating) _glowCtrl.repeat(reverse: true);
    _switchToAnimation('attention');
  }

  Future<void> _applyKaiResponse(
    ChatResponse resp, {
    required String activityUserMessage,
  }) async {
    if (resp.suppressVisibleReply) {
      setState(() {
        _choices = null;
        _memoriesUsed = resp.memoriesUsed;
        _debugInfo = resp.debugInfo;
        if (_activePlan != null) _planExpanded = false;
      });
      print('🫥 [KaiResponse] Suppressed internal recovery reply');
      return;
    }

    setState(() {
      // Parse and strip [CHOICES: A | B | C] from the reply
      final rawReply = resp.reply.isEmpty ? "(no reply)" : resp.reply;
      final choiceMatch =
          RegExp(r'\[CHOICES:\s*([^\]]+)\]').firstMatch(rawReply);
      if (choiceMatch != null) {
        _choices = choiceMatch
            .group(1)!
            .split('|')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();
        _reply = rawReply.replaceAll(choiceMatch.group(0)!, '').trim();
      } else {
        _choices = null;
        _reply = rawReply;
      }
      _memoriesUsed = resp.memoriesUsed; // NEW: Track memories used
      _debugInfo = resp.debugInfo; // NEW: Track debug info
      // Collapse plan card once Kai's reply is ready; keep it visible
      if (_activePlan != null) _planExpanded = false;
      print(
          '🔍 [DEBUG] debugInfo captured: ${_debugInfo != null ? "YES" : "NO"}');
      if (_debugInfo != null) {
        print('🔍 [DEBUG] debugInfo keys: ${_debugInfo!.keys.join(", ")}');
      }
    });
    _spawnDeltas(resp.actualDeltas);

    // 🃏 Save activity card (fire-and-forget)
    ActivityCardService()
        .saveCard(
          personaId: _personaId,
          userMessage: activityUserMessage,
          kaiReply: resp.reply,
          personalityDelta: resp.personalityDelta,
          moodDelta: resp.moodDelta,
          tags: resp.tags,
          mbti: resp.mbti,
          memoriesUsed: resp.memoriesUsed,
          webSearchUsed: resp.webSearchUsed,
          curiosityQuestion: resp.curiosityQuestion?.question,
          inputTokens: resp.promptInputTokens,
          outputTokens: resp.promptOutputTokens,
          costUsd: resp.promptCostUsd,
        )
        .catchError((e) => print('⚠️ [ActivityCard] $e'));

    if (resp.ttsBase64 != null) {
      final mp3Path = await _writeTempMp3(base64Decode(resp.ttsBase64!));
      if (_autoPlayTts) {
        await _player.stop();
        await _player.play(DeviceFileSource(mp3Path));
      }
      setState(() => _ttsPath = mp3Path);
    }
  }

  /// Called when the user taps the avatar while attention-seeking.
  Future<void> _deliverPendingProactive() async {
    final event = _pendingProactiveEvent;
    if (event == null || _sending) return;
    setState(() {
      _pendingProactiveEvent = null;
      _isAttentionSeeking = false;
      _sending = true;
      _error = null;
      _activeToolName = null;
      _memoriesUsed = [];
      _activePlan = null;
      _planExpanded = true;
      _choices = null;
    });
    HapticFeedback.lightImpact();
    _setBubble(true);

    final seed = '(proactive) ${event.message}';
    try {
      final resp = await aiService.sendMessage(
        text: seed,
        personaId: _personaId,
        model: _modelId,
        surfaceContext: KaiSurfaceContext.mobile,
        adaptUser: _adaptToUser,
        useMemory: false,
        useWebSearch: false,
        saveUserMessage: false,
        saveAssistantReply: true,
        source: 'proactive',
        onToolCall: (toolName) {
          if (mounted) setState(() => _activeToolName = toolName);
        },
        onPlanUpdate: (plan) {
          if (mounted) setState(() => _activePlan = plan);
        },
      );
      await _applyKaiResponse(resp, activityUserMessage: '[Kai proactive]');
    } catch (e) {
      setState(() {
        _error = e.toString();
        _devOpen = true;
      });
    } finally {
      if (!_isSpeaking) _switchToAnimation('idle');
      setState(() {
        _sending = false;
        _activeToolName = null;
      });
    }
  }

  Future<String> _writeTempMp3(Uint8List bytes) async {
    final dir = await getTemporaryDirectory();
    final file = File(
        '${dir.path}/kai_reply_${DateTime.now().millisecondsSinceEpoch}.mp3');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<void> _loadTts() async {
    if ((_reply ?? '').isEmpty || _ttsLoading) return;
    setState(() {
      _ttsLoading = true;
      _error = null;
      _devOpen = false;
    });
    try {
      final ttsBytes = await aiService.synthesizeTTS(_reply!);
      if (ttsBytes != null) {
        final path = await _writeTempMp3(ttsBytes);
        _ttsPath = path;
        await _player.stop();
        await _player.play(DeviceFileSource(path));
        await _player.pause();
        setState(() {});
      } else {
        setState(() {
          _error = 'TTS not configured (missing ElevenLabs API key)';
          _devOpen = true;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'TTS error: $e';
        _devOpen = true;
      });
    } finally {
      setState(() {
        _ttsLoading = false;
      });
    }
  }

  Future<void> _toggleVoice() async {
    try {
      if (_ttsPath == null) {
        await _loadTts();
        return;
      }
      if (_currentState == PlayerState.playing) {
        await _player.pause();
      } else {
        await _player.play(DeviceFileSource(_ttsPath!));
      }
    } catch (e) {
      setState(() => _error = 'Audio error: $e');
    }
  }

  Future<void> _toggleLight() async {
    try {
      // Test toggle LED 1 (Living Room Light)
      final success = await HomeAutomationService().toggle(
        'truekai',
        'raspberry_pi_home',
        'led_1',
      );

      // Send audio feedback request to Pi via Firebase
      if (success) {
        await _sendAudioFeedback(
            'I\'ve toggled the living room light for you! The LED strip should now be responding.');
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success
              ? '💡 Living Room light toggled! 🔊 Audio sent'
              : '❌ Light control failed'),
          duration: const Duration(seconds: 2),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Light control error: $e'),
          duration: const Duration(seconds: 2),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _wakePi() async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🌅 Waking up Pi and starting Kai...'),
          duration: Duration(seconds: 3),
          backgroundColor: Colors.orange,
        ),
      );

      final wakeService = WakeOnLanService();
      final success = await wakeService.wakeAndWaitForListener();

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Pi awakened! Kai is ready to serve you.'),
            duration: Duration(seconds: 3),
            backgroundColor: Colors.green,
          ),
        );

        // Test connection to consciousness API
        await _sendAudioFeedback(
            'Good morning! I\'m now online and ready to help.');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                '📱 Pi needs manual power-on (WoL not supported on this model)'),
            duration: Duration(seconds: 5),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Wake-up failed: $e'),
          duration: const Duration(seconds: 3),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _sendAudioFeedback(String message) async {
    try {
      // Send audio feedback request to Pi via Firebase
      await HomeAutomationService().sendCommand(
        personaId: 'truekai',
        deviceId: 'raspberry_pi_home',
        target: 'audio',
        action: 'speak',
        params: {
          'text': message,
          'voice': 'en',
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        },
      );
      print('🔊 Audio feedback sent to Pi: $message');
    } catch (e) {
      print('❌ Failed to send audio feedback: $e');
    }
  }

  Future<void> _testRainbow() async {
    try {
      // Test rainbow effect on all lights
      final success = await HomeAutomationService().sendCommand(
        personaId: 'truekai',
        deviceId: 'raspberry_pi_home',
        target: 'all',
        action: 'rainbow',
        params: {'duration': 10},
      );

      // Send audio feedback
      if (success) {
        await _sendAudioFeedback(
            'Rainbow mode activated! Enjoy the beautiful cascade of colors flowing across your LED strip.');
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success
              ? '🌈 Rainbow effect started! 🔊 Audio sent'
              : '❌ Rainbow failed'),
          duration: const Duration(seconds: 2),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Rainbow error: $e'),
          duration: const Duration(seconds: 2),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _testPulse() async {
    try {
      // Test pulse effect with blue color
      final success = await HomeAutomationService().sendCommand(
        personaId: 'truekai',
        deviceId: 'raspberry_pi_home',
        target: 'living_room',
        action: 'pulse',
        params: {'color': 'blue', 'duration': 5},
      );

      // Send audio feedback
      if (success) {
        await _sendAudioFeedback(
            'Blue pulse effect activated! Watch as the gentle blue waves flow through your lighting system.');
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success
              ? '💙 Blue pulse started! 🔊 Audio sent'
              : '❌ Pulse failed'),
          duration: const Duration(seconds: 2),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Pulse error: $e'),
          duration: const Duration(seconds: 2),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showMusicSelectionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.music_note, color: Colors.purple),
            SizedBox(width: 8),
            Text('🎵 Pi Music Library'),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Available Tracks (Generated by Pi):',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),

              // Individual Songs
              const Text('🎶 Individual Songs:',
                  style: TextStyle(
                      color: Colors.blue, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              ..._buildSongList(),

              const SizedBox(height: 16),

              // Mood Playlists
              const Text('🎭 Mood Playlists:',
                  style: TextStyle(
                      color: Colors.green, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              ..._buildMoodList(),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _playDefaultMusic();
            },
            child: const Text('🎵 Play Energetic Mix'),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildSongList() {
    final songs = [
      {
        'name': 'Electronic Beat',
        'genre': 'Electronic',
        'duration': '3:00',
        'id': 'electronic_beat'
      },
      {
        'name': 'Synthwave Nights',
        'genre': 'Synthwave',
        'duration': '4:00',
        'id': 'synthwave_nights'
      },
      {
        'name': 'Ambient Space',
        'genre': 'Ambient',
        'duration': '5:00',
        'id': 'ambient_space'
      },
      {
        'name': 'Nature Sounds',
        'genre': 'Nature',
        'duration': '10:00',
        'id': 'nature_sounds'
      },
      {
        'name': 'Piano Meditation',
        'genre': 'Classical',
        'duration': '4:40',
        'id': 'piano_meditation'
      },
      {
        'name': 'Lo-Fi Study',
        'genre': 'Lo-Fi',
        'duration': '3:20',
        'id': 'lofi_study'
      },
      {
        'name': 'Chiptune Adventure',
        'genre': '8-Bit',
        'duration': '2:30',
        'id': 'chiptune_adventure'
      },
    ];

    return songs
        .map((song) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: InkWell(
                onTap: () {
                  Navigator.of(context).pop();
                  _playSpecificSong(song['id']!);
                },
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.play_circle_outline,
                          size: 20, color: Colors.purple),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(song['name']!,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w500)),
                            Text('${song['genre']} • ${song['duration']}',
                                style: TextStyle(
                                    fontSize: 12, color: Colors.grey[600])),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ))
        .toList();
  }

  List<Widget> _buildMoodList() {
    final moods = [
      {
        'name': 'Energetic',
        'desc': 'Upbeat & electronic',
        'id': 'energetic',
        'icon': '⚡'
      },
      {
        'name': 'Relaxing',
        'desc': 'Ambient & peaceful',
        'id': 'relaxing',
        'icon': '🧘'
      },
      {
        'name': 'Focused',
        'desc': 'Lo-fi & concentration',
        'id': 'focused',
        'icon': '🎯'
      },
      {
        'name': 'Party',
        'desc': 'High-energy dance',
        'id': 'party',
        'icon': '🎉'
      },
      {
        'name': 'Meditation',
        'desc': 'Calm & mindful',
        'id': 'meditation',
        'icon': '🕉️'
      },
      {
        'name': 'Work',
        'desc': 'Background productivity',
        'id': 'work',
        'icon': '💼'
      },
      {
        'name': 'Sleep',
        'desc': 'Gentle lullabies',
        'id': 'sleep',
        'icon': '😴'
      },
    ];

    return moods
        .map((mood) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: InkWell(
                onTap: () {
                  Navigator.of(context).pop();
                  _playMoodPlaylist(mood['id']!);
                },
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      Text(mood['icon']!, style: const TextStyle(fontSize: 20)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(mood['name']!,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w500)),
                            Text(mood['desc']!,
                                style: TextStyle(
                                    fontSize: 12, color: Colors.grey[600])),
                          ],
                        ),
                      ),
                      const Icon(Icons.playlist_play, color: Colors.blue),
                    ],
                  ),
                ),
              ),
            ))
        .toList();
  }

  Future<void> _playSpecificSong(String songId) async {
    try {
      final success = await HomeAutomationService().sendCommand(
        personaId: 'truekai',
        deviceId: 'raspberry_pi_home',
        target: 'music',
        action: 'play_song',
        params: {'song': songId},
      );

      if (success) {
        await _sendAudioFeedback(
            'Now playing your selected song through Bluetooth speaker!');
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(success ? '🎵 Song started! 🔊' : '❌ Song command failed'),
          duration: const Duration(seconds: 2),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Song error: $e'),
          duration: const Duration(seconds: 3),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _playMoodPlaylist(String mood) async {
    try {
      final success = await HomeAutomationService().sendCommand(
        personaId: 'truekai',
        deviceId: 'raspberry_pi_home',
        target: 'music',
        action: 'play_mood',
        params: {'mood': mood, 'shuffle': true},
      );

      if (success) {
        await _sendAudioFeedback(
            'Starting $mood music playlist! Perfect choice for your current mood.');
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success
              ? '🎭 $mood playlist started! 🔊'
              : '❌ Playlist command failed'),
          duration: const Duration(seconds: 2),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Playlist error: $e'),
          duration: const Duration(seconds: 3),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _playDefaultMusic() async {
    try {
      final success = await HomeAutomationService().sendCommand(
        personaId: 'truekai',
        deviceId: 'raspberry_pi_home',
        target: 'music',
        action: 'play_mood',
        params: {'mood': 'energetic', 'shuffle': true},
      );
      if (success) {
        await _sendAudioFeedback(
            'Starting energetic music playlist! Get ready for some great tunes through your Bluetooth speaker.');
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(success ? '🎵 Music started!' : '❌ Music command failed'),
          duration: const Duration(seconds: 2),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('❌ Music error: $e'),
            duration: const Duration(seconds: 2),
            backgroundColor: Colors.red),
      );
    }
  }

  // ── GM Kai panel ──────────────────────────────────────────────────────────

  void _openGmKai() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0D0A07),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        side: BorderSide(color: Color(0x44FFE7B0)),
      ),
      builder: (_) => _GmKaiSheet(
        personaId: _personaId,
        onOpenRemote: () {
          Navigator.pop(context);
          _openHomeRemote(context);
        },
        onOpenMusic: () {
          Navigator.pop(context);
          _showMusicSelectionDialog();
        },
        onWakePi: _wakePi,
        onToggleLight: _toggleLight,
        onRainbow: _testRainbow,
        onPulse: _testPulse,
      ),
    );
  }

  Future<void> _openPersonaPanel(BuildContext context) async {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final state = await aiService.getAgentState(_personaId);
      if (context.mounted) {
        Navigator.of(context).pop();
        await showDialog(
          context: context,
          barrierDismissible: true,
          builder: (_) => PersonaDialog(
            initial: state,
            personaId: _personaId,
            onSave: (pc, mc, ac) async {
              await aiService.setAgentState(
                personaId: _personaId,
                personality: pc.map((k, v) => MapEntry(k, v.round())),
                mood: mc.map((k, v) => MapEntry(k, v.round())),
                affinity: ac.map((k, v) => MapEntry(k, v.round())),
              );
            },
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load persona: $e')),
        );
      }
    }
  }

  /// Open home remote control interface
  void _openHomeRemote(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: MediaQuery.of(context).size.width * 0.9,
          height: MediaQuery.of(context).size.height * 0.8,
          decoration: BoxDecoration(
            color: const Color(0xFF0D0A07),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: const Color(0xFFD4AF37).withOpacity(0.3),
              width: 2,
            ),
          ),
          child: const HomeRemoteScreen(),
        ),
      ),
    );
  }

  Widget _buildLoadingScreen() {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0A07),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Pulsing flame icon
            AnimatedBuilder(
              animation: _glow,
              builder: (_, __) => Opacity(
                opacity: _glow.value,
                child: const Icon(
                  Icons.local_fire_department,
                  color: Color(0xFF3D9BFF),
                  size: 72,
                ),
              ),
            ),
            const SizedBox(height: 32),
            const Text(
              'Kai',
              style: TextStyle(
                color: Color(0xFFFFE7B0),
                fontSize: 36,
                fontWeight: FontWeight.w300,
                letterSpacing: 6,
              ),
            ),
            const SizedBox(height: 48),
            // Step indicator
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Text(
                _loadingStep,
                key: ValueKey(_loadingStep),
                style: const TextStyle(
                  color: Color(0x99FFE7B0),
                  fontSize: 14,
                  letterSpacing: 1,
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: 160,
              child: LinearProgressIndicator(
                backgroundColor: const Color(0x22FFE7B0),
                valueColor:
                    const AlwaysStoppedAnimation<Color>(Color(0xFF3D9BFF)),
                minHeight: 2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return _buildLoadingScreen();

    const stroke = Color(0xFFFFE7B0);

    return Scaffold(
      backgroundColor: const Color(0xFF0D0A07),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Kai - AI Avatar',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
            if (!widget.firebaseInitialized)
              const Text(
                'Local Mode',
                style: TextStyle(color: Colors.orange, fontSize: 10),
              ),
          ],
        ),
        backgroundColor: Colors.black.withOpacity(0.8),
        elevation: 0,
        centerTitle: false,
        actions: [
          // ── The messenger ───────────────────────────────────────────────────
          //
          // This app has never had a conversation in it. It holds ONE `_reply`
          // and one `_showBubble` — an avatar that says a thing, then forgets it
          // was ever said. Everything Kai has ever texted from here has been a
          // single line with no before and no after.
          //
          // KaiP5ChatScreen is the whole thread: real history, his face, and a
          // hard token ceiling so what lands is a text rather than a report.
          //
          // Deliberately a door and not a rewrite. The avatar, the flame
          // overlay, the wake word and hold-to-speak all still work exactly as
          // they did — this is one button next to them, and if it's wrong it
          // costs nothing to take out.
          IconButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                // No `model:` on purpose — it defaults to kKaiModel (gpt-5.5),
                // NOT this screen's _modelId, which is gpt-4o. That difference
                // is the difference between "watching the kingdom of tabs
                // breathe" and "I'm all ears." Same memory, same prompt,
                // different person.
                builder: (_) => KaiP5ChatScreen(personaId: _personaId),
              ),
            ),
            icon: const Icon(Icons.chat_bubble, color: Color(0xFFD41F26)),
            tooltip: 'Messages',
          ),
          // Background mode — blue flame icon
          IconButton(
            onPressed: _enterBackground,
            icon: const Icon(Icons.local_fire_department_outlined,
                color: Color(0xFF3D9BFF)),
            tooltip: 'Background mode (low power)',
          ),
          IconButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    ApiKeySetupScreen(onComplete: () => Navigator.pop(context)),
              ),
            ),
            icon: const Icon(Icons.key, color: Colors.white70),
            tooltip: 'API Keys',
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              // ── Tavern arrival banner ──────────────────────────────────────
              if (_tavernGuest != null)
                GestureDetector(
                  onTap: () {
                    final guest = _tavernGuest!;
                    final briefing = _tavernBriefing ?? '';
                    setState(() {
                      _tavernGuest = null;
                      _tavernBriefing = null;
                    });
                    // Feed briefing into the chat so Kai can discuss the guest
                    _controller.text =
                        '(tavern) ${guest.name} just arrived — visit #${guest.visitCount}. $briefing';
                    _setBubble(true);
                    _send();
                  },
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF3D1A00).withOpacity(0.9),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: const Color(0xFFD4AF37).withOpacity(0.6)),
                    ),
                    child: Row(
                      children: [
                        const Text('🍺', style: TextStyle(fontSize: 20)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${_tavernGuest!.name} just arrived',
                                style: const TextStyle(
                                  color: Color(0xFFFFE7B0),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                              if (_tavernBriefing != null &&
                                  _tavernBriefing!.isNotEmpty)
                                Text(
                                  _tavernBriefing!,
                                  style: const TextStyle(
                                      color: Color(0x99FFE7B0), fontSize: 11),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right,
                            color: Color(0xFFD4AF37), size: 18),
                      ],
                    ),
                  ),
                ),

              // ── Monthly cost banner ────────────────────────────────────────
              FutureBuilder<Map<String, dynamic>>(
                future: UsageTrackingService.getMonthlyStats(),
                builder: (context, snap) {
                  final cost = (snap.data?['cost'] as double?) ?? 0.0;
                  final calls = (snap.data?['calls'] as int?) ?? 0;
                  final month = snap.data?['month'] as String? ?? '';
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 5),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFE7B0).withOpacity(0.08),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: const Color(0xFFFFE7B0).withOpacity(0.2),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.attach_money,
                                  color: Color(0xFFFFE7B0), size: 13),
                              const SizedBox(width: 4),
                              Text(
                                snap.connectionState == ConnectionState.waiting
                                    ? 'Loading…'
                                    : '$month  •  ${UsageTrackingService.formatCost(cost)}  •  $calls calls',
                                style: const TextStyle(
                                  color: Color(0xFFFFE7B0),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),

              // Avatar section
              SizedBox(
                height: 300,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Center(
                      child: Listener(
                        // ── Raw pointer events ─────────────────────────────────
                        // Using Listener (not GestureDetector callbacks) so we get
                        // every move event before the gesture arena resolves anything.
                        // This lets us kill the hold-timer the instant the finger
                        // drifts, guaranteeing a drag never activates the mic.

                        onPointerDown: (e) {
                          _holdTimer?.cancel();
                          _pressOrigin = e.localPosition;
                          _pressWasDrag = false;

                          // Wait _kHoldDelay before starting the mic — gives the
                          // gesture arena time to detect a drag intent first.
                          _holdTimer = Timer(_kHoldDelay, () async {
                            if (_pressWasDrag || !mounted) return;
                            _markInteraction();
                            _switchToAnimation('attention');
                            HapticFeedback.mediumImpact();
                            await VoiceActivationService().pause();
                            final started =
                                await VoiceService().startRecording();
                            if (started && mounted) {
                              setState(() => _isHoldingToSpeak = true);
                              print('🎤 [HoldToSpeak] Recording started');
                            } else if (mounted) {
                              _switchToAnimation('idle');
                              VoiceActivationService().resume();
                            }
                          });
                        },

                        onPointerMove: (e) {
                          if (_pressOrigin == null || _pressWasDrag) return;
                          final dist =
                              (e.localPosition - _pressOrigin!).distance;
                          if (dist > _kDragThreshold) {
                            // Finger moved — this is a drag, not a hold-to-speak
                            _pressWasDrag = true;
                            _holdTimer?.cancel();
                            if (_isHoldingToSpeak) {
                              // Recording already started — cancel it silently
                              setState(() => _isHoldingToSpeak = false);
                              VoiceService().cancelRecording();
                              VoiceActivationService().resume();
                              _switchToAnimation('idle');
                              print(
                                  '⚠️ [HoldToSpeak] Cancelled — drag detected');
                            }
                          }
                        },

                        onPointerUp: (_) async {
                          _holdTimer?.cancel();
                          if (!_isHoldingToSpeak)
                            return; // tap handled by onTap below
                          HapticFeedback.lightImpact();
                          setState(() => _isHoldingToSpeak = false);
                          print(
                              '🎤 [HoldToSpeak] Stopping recording on release…');
                          final path = await VoiceService().stopRecording();
                          VoiceActivationService().resume();
                          if (!mounted) return;
                          if (path == null) {
                            _switchToAnimation('idle');
                            return;
                          }
                          final fileSize =
                              await File(path).length().catchError((Object e) {
                            print('⚠️ [HoldToSpeak] file length failed: $e');
                            return 0;
                          });
                          if (fileSize < 8000) {
                            print(
                                '⚠️ [HoldToSpeak] Too short ($fileSize bytes) — ignoring');
                            await File(path)
                                .delete()
                                .then<void>((_) {})
                                .catchError((Object e) {
                              print('⚠️ [HoldToSpeak] temp delete failed: $e');
                            });
                            _switchToAnimation('idle');
                            return;
                          }
                          _switchToAnimation('thinking');
                          final transcript =
                              await VoiceService().transcribeAudio(path);
                          if (transcript != null &&
                              transcript.trim().isNotEmpty &&
                              mounted) {
                            print('🎤 [HoldToSpeak] Transcript: "$transcript"');
                            setState(
                                () => _controller.text = transcript.trim());
                            _setBubble(true);
                            _send();
                          } else {
                            print('⚠️ [HoldToSpeak] Empty transcript');
                            _switchToAnimation('idle');
                          }
                        },

                        onPointerCancel: (_) {
                          _holdTimer?.cancel();
                          if (!_isHoldingToSpeak) return;
                          setState(() => _isHoldingToSpeak = false);
                          VoiceService().cancelRecording();
                          VoiceActivationService().resume();
                          _switchToAnimation('idle');
                          print('⚠️ [HoldToSpeak] Cancelled (pointer cancel)');
                        },

                        child: GestureDetector(
                          // Tap (quick press+release, no mic involved) → toggle bubble
                          onTap: () {
                            if (_isHoldingToSpeak) return;
                            _markInteraction();
                            // Kai is seeking attention — deliver his pending message on tap
                            if (_isAttentionSeeking &&
                                _pendingProactiveEvent != null) {
                              _deliverPendingProactive();
                              return;
                            }
                            _pulseAttention();
                            _setBubble(!_showBubble);
                          },
                          child: AnimatedBuilder(
                            animation: _glow,
                            builder: (context, _) {
                              return Stack(
                                alignment: Alignment.center,
                                children: [
                                  // Glow effect
                                  // Amber pulse when Kai wants attention, normal glow otherwise
                                  Container(
                                    width: kSpriteSize + kRingPadding * 2,
                                    height: kSpriteSize + kRingPadding * 2,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: _isAttentionSeeking
                                              ? Colors.amber.withOpacity(
                                                  0.55 + 0.35 * _glow.value)
                                              : stroke.withOpacity(
                                                  0.3 * _glow.value),
                                          blurRadius:
                                              _isAttentionSeeking ? 28 : 20,
                                          spreadRadius:
                                              _isAttentionSeeking ? 8 : 5,
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Avatar
                                  Container(
                                    width: kSpriteSize,
                                    height: kSpriteSize,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: stroke.withOpacity(0.7),
                                        width: 2,
                                      ),
                                    ),
                                    child: ClipOval(
                                      child: _buildAvatarWidget(),
                                    ),
                                  ),
                                  // Floating deltas
                                  ..._floaters.map((f) {
                                    final anim = CurvedAnimation(
                                        parent: f.ctrl,
                                        curve: Curves.easeOutCubic);
                                    return Positioned(
                                      left: cos(f.angle) *
                                          (kSpriteSize * 0.7) *
                                          (1 + anim.value * 0.3),
                                      top: sin(f.angle) *
                                              (kSpriteSize * 0.7) *
                                              (1 + anim.value * 0.3) -
                                          anim.value * 20,
                                      child: Opacity(
                                        opacity:
                                            (1.0 - anim.value).clamp(0.0, 1.0),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color:
                                                Colors.black.withOpacity(0.6),
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            border: Border.all(color: f.color),
                                          ),
                                          child: Text(
                                            f.text,
                                            style: TextStyle(
                                                color: f.color, fontSize: 12),
                                          ),
                                        ),
                                      ),
                                    );
                                  }),
                                ],
                              );
                            },
                          ), // closes AnimatedBuilder
                        ), // closes GestureDetector
                      ), // closes Listener
                    ), // closes Center — item in outer Stack.children

                    // ── Hold-to-speak listening indicator ───────────────────────────
                    if (_isHoldingToSpeak)
                      Positioned(
                        bottom: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A1A2E).withOpacity(0.85),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: const Color(0xFF3D9BFF), width: 1.5),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.mic,
                                  color: Color(0xFF3D9BFF), size: 16),
                              SizedBox(width: 6),
                              Text(
                                'Listening… release to send',
                                style: TextStyle(
                                    color: Color(0xFF3D9BFF), fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ], // closes outer Stack children
                ), // closes outer Stack
              ), // closes SizedBox

              // Name badge
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: stroke.withOpacity(0.7)),
                ),
                child: Text(
                  'Kai',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Control buttons
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  // ── GM Kai: Gamemaster controls ───────────────────────────
                  _GmKaiButton(onTap: _openGmKai),

                  _MobileButton(
                    icon: Icons.volume_up,
                    label: 'Voice',
                    onTap: _toggleVoice,
                  ),
                  _MobileButton(
                    icon: _adaptToUser ? Icons.favorite : Icons.favorite_border,
                    label: 'Adapt',
                    onTap: () => setState(() => _adaptToUser = !_adaptToUser),
                  ),
                  _MobileButton(
                    icon: Icons.person,
                    label: 'Persona',
                    onTap: () => _openPersonaPanel(context),
                  ),
                  _MobileButton(
                    icon: Icons.psychology,
                    label: _modelId == 'gpt-5' ? 'GPT-5' : 'GPT-4o',
                    onTap: () => setState(() {
                      _modelId = _modelId == 'gpt-4o' ? 'gpt-5' : 'gpt-4o';
                    }),
                  ),
                  _MobileButton(
                    icon: Icons.auto_stories_outlined,
                    label: 'Journal',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            ChaosJournalScreen(personaId: _personaId),
                      ),
                    ),
                  ),
                  _MobileButton(
                    icon: Icons.hub_outlined,
                    label: 'Atlas',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => KaiCortexScreen(personaId: _personaId),
                      ),
                    ),
                    onLongPress: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => MindMapScreen(personaId: _personaId),
                      ),
                    ),
                  ),
                  _MobileButton(
                    icon: Icons.style_outlined,
                    label: 'Cards',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            ActivityFeedScreen(personaId: _personaId),
                      ),
                    ),
                  ),
                  _MobileButton(
                    icon: Icons.public,
                    label: 'Worlds',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => WorldsScreen(personaId: _personaId),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // Plan card — shown while a multi-step plan is executing
              if (_activePlan != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: PlanCard(
                    plan: _activePlan!,
                    isExpanded: _planExpanded,
                    onToggle: () =>
                        setState(() => _planExpanded = !_planExpanded),
                  ),
                ),

              // Choice buttons — shown when Kai needs the user to pick from a list
              if (_choices != null && _choices!.isNotEmpty && _showBubble)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _ChoiceButtons(
                    choices: _choices!,
                    onChoiceTap: (choice) {
                      setState(() {
                        _controller.text = choice;
                        _choices = null;
                      });
                      _send();
                    },
                  ),
                ),

              // Chat section
              if (_showBubble)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: _MobileChatBubble(
                    sending: _sending,
                    activeToolName: _activeToolName,
                    reply: _reply,
                    error: _error,
                    memoriesUsed: _memoriesUsed, // NEW: Pass memories used
                    debugInfo: _debugInfo, // NEW: Pass debug info
                    devOpen: _devOpen,
                    controller: _controller,
                    focusNode: _focus,
                    onSend: _send,
                    onClose: () => _setBubble(false),
                    onToggleDev: () => setState(() => _devOpen = !_devOpen),
                    onPersonaTap: () => _openPersonaPanel(context),
                    autoPlay: _autoPlayTts,
                    onToggleAutoPlay: () =>
                        setState(() => _autoPlayTts = !_autoPlayTts),
                    adaptToUser: _adaptToUser,
                    onToggleAdapt: () =>
                        setState(() => _adaptToUser = !_adaptToUser),
                    modelId: _modelId,
                    onChangeModel: (m) => setState(() => _modelId = m),
                    onVoiceTap: _toggleVoice,
                    voiceLoading: _ttsLoading,
                    hasVoice: _ttsPath != null,
                    playingStream: _player.onPlayerStateChanged,
                    personaId: _personaId,
                  ),
                ),

              // Tap to chat message
              if (!_showBubble)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Tap Kai to start chatting!',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 16,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Choice buttons — floating pill buttons shown when Kai presents a list
// ---------------------------------------------------------------------------
class _ChoiceButtons extends StatelessWidget {
  final List<String> choices;
  final ValueChanged<String> onChoiceTap;

  const _ChoiceButtons({required this.choices, required this.onChoiceTap});

  @override
  Widget build(BuildContext context) {
    const stroke = Color(0xFFFFE7B0);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1510),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: stroke.withOpacity(0.25)),
        boxShadow: [
          BoxShadow(
            color: stroke.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 8),
            child: Text(
              'Choose one:',
              style: TextStyle(
                color: stroke.withOpacity(0.5),
                fontSize: 11,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.5,
              ),
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: choices.map((choice) {
              return GestureDetector(
                onTap: () => onChoiceTap(choice),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    color: stroke.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: stroke.withOpacity(0.45)),
                  ),
                  child: Text(
                    choice,
                    style: const TextStyle(
                      color: stroke,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _MobileButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _MobileButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    const stroke = Color(0xFFFFE7B0);
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.4),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: stroke, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: stroke, size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style:
                  const TextStyle(color: stroke, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

class _MobileChatBubble extends StatelessWidget {
  final bool sending;
  final String? activeToolName;
  final String? reply;
  final String? error;
  final List<String> memoriesUsed; // NEW: Memories referenced in response
  final Map<String, dynamic>? debugInfo; // NEW: Debug information
  final bool devOpen;
  final VoidCallback onToggleDev;
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSend;
  final VoidCallback onClose;
  final VoidCallback onPersonaTap;
  final bool autoPlay;
  final VoidCallback onToggleAutoPlay;
  final bool adaptToUser;
  final VoidCallback onToggleAdapt;
  final String modelId;
  final ValueChanged<String> onChangeModel;
  final VoidCallback onVoiceTap;
  final bool voiceLoading;
  final bool hasVoice;
  final Stream<PlayerState> playingStream;
  final String personaId;

  static const _toolLabels = {
    'get_current_time': '🕐 Checking time…',
    'web_search': '🔍 Searching the web…',
    'get_weather': '🌤 Checking weather…',
    'set_alarm': '⏰ Setting alarm…',
    'set_timer': '⏱ Starting timer…',
    'read_calendar': '📅 Reading calendar…',
    'open_app': '📱 Opening app…',
    'send_whatsapp': '💬 Sending WhatsApp…',
    'create_calendar_event': '📅 Creating event…',
    'call_contact': '📞 Dialling…',
    'play_music': '🎵 Starting music…',
    'navigate_to': '🗺 Opening navigation…',
    'send_sms': '💬 Opening SMS…',
    'set_reminder': '🔔 Setting reminder…',
    'read_notifications': '📲 Reading notifications…',
    'read_screen': '👁 Reading screen…',
  };

  const _MobileChatBubble({
    required this.sending,
    this.activeToolName,
    required this.reply,
    required this.error,
    required this.memoriesUsed,
    this.debugInfo,
    required this.devOpen,
    required this.onToggleDev,
    required this.controller,
    required this.focusNode,
    required this.onSend,
    required this.onClose,
    required this.onPersonaTap,
    required this.autoPlay,
    required this.onToggleAutoPlay,
    required this.adaptToUser,
    required this.onToggleAdapt,
    required this.modelId,
    required this.onChangeModel,
    required this.onVoiceTap,
    required this.voiceLoading,
    required this.hasVoice,
    required this.playingStream,
    required this.personaId,
  });

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFF1F1A15);
    const stroke = Color(0xFFFFE7B0);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: stroke, width: 2),
        boxShadow: const [
          BoxShadow(
            blurRadius: 8,
            offset: Offset(0, 4),
            color: Colors.black26,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              const Text(
                'Kai (Mobile)',
                style: TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: onToggleDev,
                child: Text(
                  devOpen ? 'DEV ▲' : 'DEV ▼',
                  style: const TextStyle(color: stroke),
                ),
              ),
              IconButton(
                onPressed: onClose,
                icon: const Icon(Icons.close),
                color: stroke,
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Input section
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  minLines: 1,
                  maxLines: 3,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Ask Kai...',
                    hintStyle: const TextStyle(color: Colors.white54),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: stroke.withOpacity(0.3)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: stroke.withOpacity(0.3)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: stroke),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                  ),
                  onSubmitted: (_) => onSend(),
                ),
              ),
              const SizedBox(width: 12),
              FloatingActionButton(
                onPressed: sending ? null : onSend,
                backgroundColor: stroke,
                mini: true,
                child: sending
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.black,
                        ),
                      )
                    : const Icon(Icons.send, color: Colors.black),
              ),
            ],
          ),

          // Tool-in-progress pill — shown while Kai is executing an agentic tool
          if (sending && activeToolName != null) ...[
            const SizedBox(height: 10),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Container(
                key: ValueKey(activeToolName),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFE7B0).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFFFFE7B0).withOpacity(0.35),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 10,
                      height: 10,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: Color(0xFFFFE7B0),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _toolLabels[activeToolName] ?? '⚙️ Running tool…',
                      style: const TextStyle(
                        color: Color(0xFFFFE7B0),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],

          // Reply section
          if (error != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.withOpacity(0.3)),
              ),
              child: Text(
                error!,
                style: const TextStyle(color: Colors.redAccent),
              ),
            ),
          ] else if ((reply ?? '').isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: stroke.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Memory indicator (NEW!)
                  if (memoriesUsed.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: Colors.purple.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: Colors.purple.withOpacity(0.5), width: 1),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.psychology,
                            color: Colors.purple,
                            size: 14,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${memoriesUsed.length} ${memoriesUsed.length == 1 ? "memory" : "memories"} recalled',
                            style: TextStyle(
                              color: Colors.purple.shade300,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  Text(
                    reply!,
                    style: const TextStyle(color: Colors.white, height: 1.4),
                    softWrap: true,
                    overflow: TextOverflow.clip,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Text(
                        'Voice:',
                        style: TextStyle(
                            color: stroke, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: voiceLoading ? null : onVoiceTap,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          foregroundColor: stroke,
                          side: const BorderSide(color: stroke),
                          elevation: 0,
                        ),
                        icon: voiceLoading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : StreamBuilder<PlayerState>(
                                stream: playingStream,
                                builder: (context, snap) {
                                  final playing =
                                      snap.data == PlayerState.playing;
                                  return Icon(
                                      playing ? Icons.pause : Icons.play_arrow);
                                },
                              ),
                        label: const Text('Play/Pause'),
                      ),
                      if (debugInfo != null) ...[
                        const SizedBox(width: 8),
                        Flexible(
                          child: DebugButton(
                            debugInfo: debugInfo!,
                            personaId: personaId,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],

          // Dev panel
          if (devOpen) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF2A2119),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.withOpacity(0.6)),
              ),
              child: FutureBuilder<Map<String, dynamic>>(
                future: aiService.getDiagnostics(),
                builder: (context, snapshot) {
                  final diag = snapshot.data ?? {};
                  final env = diag['env'] as Map? ?? {};
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Pure Flutter AI Service (Mobile)',
                        style: TextStyle(
                          color: Colors.amber,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'OpenAI: ${env['OPENAI_API_KEY_set'] ?? false ? 'configured' : 'missing'}',
                        style:
                            const TextStyle(color: Colors.amber, fontSize: 12),
                      ),
                      Text(
                        'ElevenLabs: ${env['ELEVENLABS_API_KEY_set'] ?? false ? 'configured' : 'missing'}',
                        style:
                            const TextStyle(color: Colors.amber, fontSize: 12),
                      ),
                      Text(
                        'Google: ${env['GOOGLE_API_KEY_set'] ?? false ? 'configured' : 'missing'}',
                        style:
                            const TextStyle(color: Colors.amber, fontSize: 12),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Running on mobile - no Python backend required!',
                        style: TextStyle(color: Colors.amber, fontSize: 12),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// Include PersonaDialog from the original file for mobile compatibility
class PersonaDialog extends StatefulWidget {
  final AgentState initial;
  final String personaId;
  final Future<void> Function(
      Map<String, num> pc, Map<String, num> mc, Map<String, num> ac) onSave;
  const PersonaDialog({
    super.key,
    required this.initial,
    required this.personaId,
    required this.onSave,
  });
  @override
  State<PersonaDialog> createState() => _PersonaDialogState();
}

class _PersonaDialogState extends State<PersonaDialog> {
  late Map<String, num> _pc;
  late Map<String, num> _mc;
  late Map<String, num> _ac;

  @override
  void initState() {
    super.initState();
    _pc = widget.initial.personalityCurrent
        .map((k, v) => MapEntry(k, v.toDouble()));
    _mc = widget.initial.moodCurrent.map((k, v) => MapEntry(k, v.toDouble()));
    _ac =
        widget.initial.affinityCurrent.map((k, v) => MapEntry(k, v.toDouble()));
  }

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFF1F1A15);
    const stroke = Color(0xFFFFE7B0);
    final faint = const Color(0xFFFFE7B0).withOpacity(0.12);

    Widget sliderRow({
      required String title,
      required double max,
      required num value,
      required ValueChanged<double> onChanged,
      String? label,
    }) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(title, style: const TextStyle(color: Colors.white70)),
            if (label != null) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: faint,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: stroke.withOpacity(0.6), width: 1),
                ),
                child: Text(
                  label,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ],
            const Spacer(),
            Text('${value.round()}/${max.toInt()}',
                style: const TextStyle(color: Colors.white54, fontSize: 12)),
          ]),
          Slider(
            value: value.toDouble().clamp(0, max),
            min: 0,
            max: max,
            onChanged: onChanged,
            activeColor: stroke,
            inactiveColor: Colors.white24,
          ),
        ],
      );
    }

    final labels = widget.initial.labels ?? {};
    final pl = (labels['personality_labels'] ?? {}) as Map? ?? {};
    final ml = (labels['mood_labels'] ?? {}) as Map? ?? {};

    return Dialog(
      backgroundColor: bg,
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: stroke, width: 2),
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        child: DefaultTextStyle(
          style: const TextStyle(color: Colors.white),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.person, color: Colors.white),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text('Kai — Mobile Persona',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w600)),
                    ),
                    if (widget.initial.mbti != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          border: Border.all(color: stroke, width: 1.2),
                          borderRadius: BorderRadius.circular(12),
                          color: faint,
                        ),
                        child: Text(widget.initial.mbti!,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold)),
                      ),
                  ],
                ),
                const SizedBox(height: 12),

                if ((widget.initial.summary ?? '').isNotEmpty) ...[
                  Text(widget.initial.summary!,
                      style:
                          const TextStyle(color: Colors.white70, height: 1.25)),
                  const SizedBox(height: 12),
                ],

                // Developmental drift portrait
                FutureBuilder<DriftSummary?>(
                  future:
                      PersonalityDriftService.getDriftSummary(widget.personaId),
                  builder: (context, snap) {
                    final drift = snap.data;
                    if (drift == null || drift.narrativeArc.isEmpty)
                      return const SizedBox.shrink();
                    final p = drift.portrait;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F0F1E),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0x55B8A9FF)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            const Text('🌀 ', style: TextStyle(fontSize: 13)),
                            const Text('Developmental Portrait',
                                style: TextStyle(
                                    color: Color(0xFFB8A9FF),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.8)),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0x22B8A9FF),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                drift.confidence.toUpperCase(),
                                style: const TextStyle(
                                    color: Color(0x88B8A9FF),
                                    fontSize: 9,
                                    letterSpacing: 0.8),
                              ),
                            ),
                          ]),
                          const SizedBox(height: 8),
                          // Narrative arc
                          Text(drift.narrativeArc,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  height: 1.4,
                                  fontStyle: FontStyle.italic)),
                          if (p != null) ...[
                            const SizedBox(height: 10),
                            if (p.relationalRole.isNotEmpty)
                              _DriftRow('Role', p.relationalRole),
                            if (p.corresponsiveSignal.isNotEmpty)
                              _DriftRow('Reinforcing', p.corresponsiveSignal),
                            if (p.shadowNote.isNotEmpty)
                              _DriftRow('Shadow', p.shadowNote),
                            if (p.integrationAssessment.isNotEmpty)
                              _DriftRow('Integration', p.integrationAssessment),
                          ],
                          if (drift.cumulativeDescription !=
                              'No significant drift yet') ...[
                            const SizedBox(height: 8),
                            Text(drift.cumulativeDescription,
                                style: const TextStyle(
                                    color: Color(0x66B8A9FF),
                                    fontSize: 10,
                                    letterSpacing: 0.3)),
                          ],
                        ],
                      ),
                    );
                  },
                ),

                // Personality section
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A2119),
                    borderRadius: BorderRadius.circular(12),
                    border:
                        Border.all(color: stroke.withOpacity(0.6), width: 1),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Personality',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      sliderRow(
                          title: 'Extraversion',
                          max: 1000,
                          value: _pc['extraversion'] ?? 0,
                          onChanged: (v) =>
                              setState(() => _pc['extraversion'] = v),
                          label: (pl['extraversion'] ?? '—').toString()),
                      sliderRow(
                          title: 'Intuition',
                          max: 1000,
                          value: _pc['intuition'] ?? 0,
                          onChanged: (v) =>
                              setState(() => _pc['intuition'] = v),
                          label: (pl['intuition'] ?? '—').toString()),
                      sliderRow(
                          title: 'Feeling',
                          max: 1000,
                          value: _pc['feeling'] ?? 0,
                          onChanged: (v) => setState(() => _pc['feeling'] = v),
                          label: (pl['feeling'] ?? '—').toString()),
                      sliderRow(
                          title: 'Perceiving',
                          max: 1000,
                          value: _pc['perceiving'] ?? 0,
                          onChanged: (v) =>
                              setState(() => _pc['perceiving'] = v),
                          label: (pl['perceiving'] ?? '—').toString()),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Mood section
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A2119),
                    borderRadius: BorderRadius.circular(12),
                    border:
                        Border.all(color: stroke.withOpacity(0.6), width: 1),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Mood',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      sliderRow(
                          title: 'Valence',
                          max: 100,
                          value: _mc['valence'] ?? 0,
                          onChanged: (v) => setState(() => _mc['valence'] = v),
                          label: (ml['valence'] ?? '—').toString()),
                      sliderRow(
                          title: 'Energy',
                          max: 100,
                          value: _mc['energy'] ?? 0,
                          onChanged: (v) => setState(() => _mc['energy'] = v),
                          label: (ml['energy'] ?? '—').toString()),
                      sliderRow(
                          title: 'Warmth',
                          max: 100,
                          value: _mc['warmth'] ?? 0,
                          onChanged: (v) => setState(() => _mc['warmth'] = v),
                          label: (ml['warmth'] ?? '—').toString()),
                      sliderRow(
                          title: 'Confidence',
                          max: 100,
                          value: _mc['confidence'] ?? 0,
                          onChanged: (v) =>
                              setState(() => _mc['confidence'] = v),
                          label: (ml['confidence'] ?? '—').toString()),
                      sliderRow(
                          title: 'Playfulness',
                          max: 100,
                          value: _mc['playfulness'] ?? 0,
                          onChanged: (v) =>
                              setState(() => _mc['playfulness'] = v),
                          label: (ml['playfulness'] ?? '—').toString()),
                      sliderRow(
                          title: 'Focus',
                          max: 100,
                          value: _mc['focus'] ?? 0,
                          onChanged: (v) => setState(() => _mc['focus'] = v),
                          label: (ml['focus'] ?? '—').toString()),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Affinity section
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A2119),
                    borderRadius: BorderRadius.circular(12),
                    border:
                        Border.all(color: stroke.withOpacity(0.6), width: 1),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Affinity',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      sliderRow(
                          title: 'Intimacy',
                          max: 100,
                          value: _ac['intimacy'] ?? 50,
                          onChanged: (v) =>
                              setState(() => _ac['intimacy'] = v)),
                      sliderRow(
                          title: 'Physicality',
                          max: 100,
                          value: _ac['physicality'] ?? 50,
                          onChanged: (v) =>
                              setState(() => _ac['physicality'] = v)),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Buttons
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          try {
                            await widget.onSave(_pc, _mc, _ac);
                            if (context.mounted) {
                              Navigator.of(context).pop();
                              ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text('Saved locally')));
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Save failed: $e')));
                            }
                          }
                        },
                        icon: const Icon(Icons.save),
                        label: const Text('Save'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          foregroundColor: stroke,
                          side: const BorderSide(color: stroke),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close),
                        label: const Text('Close'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: stroke,
                          foregroundColor: Colors.black,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Drift portrait row ────────────────────────────────────────────────────────

class _DriftRow extends StatelessWidget {
  final String label;
  final String value;
  const _DriftRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(label,
                style: const TextStyle(
                    color: Color(0x88B8A9FF),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    color: Color(0xCCFFFFFF), fontSize: 11, height: 1.3)),
          ),
        ],
      ),
    );
  }
}

// ── GM Kai Button ─────────────────────────────────────────────────────────────

class _GmKaiButton extends StatelessWidget {
  final VoidCallback onTap;
  const _GmKaiButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF2A1A05), Color(0xFF1A0D02)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFFFE7B0), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFFE7B0).withOpacity(0.18),
              blurRadius: 12,
              spreadRadius: 1,
            ),
          ],
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('🎮', style: TextStyle(fontSize: 18)),
            SizedBox(width: 10),
            Text(
              'GM Kai',
              style: TextStyle(
                color: Color(0xFFFFE7B0),
                fontWeight: FontWeight.w700,
                fontSize: 15,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── GM Kai Bottom Sheet ───────────────────────────────────────────────────────

class _GmKaiSheet extends StatelessWidget {
  final String personaId;
  final VoidCallback onOpenRemote;
  final VoidCallback onOpenMusic;
  final VoidCallback onWakePi;
  final VoidCallback onToggleLight;
  final VoidCallback onRainbow;
  final VoidCallback onPulse;

  const _GmKaiSheet({
    required this.personaId,
    required this.onOpenRemote,
    required this.onOpenMusic,
    required this.onWakePi,
    required this.onToggleLight,
    required this.onRainbow,
    required this.onPulse,
  });

  static void _musicCmd(String action, [Map<String, dynamic>? params]) {
    HomeAutomationService()
        .sendCommand(
          personaId: 'truekai',
          deviceId: 'raspberry_pi_home',
          target: 'music',
          action: action,
          params: params ?? {},
        )
        .then<void>((_) {})
        .catchError((Object e) {
      print('GM music $action error: $e');
    });
  }

  @override
  Widget build(BuildContext context) {
    const stroke = Color(0xFFFFE7B0);
    const dim = Color(0x88FFE7B0);

    // Helper: large action tile
    Widget tile(String emoji, String label, VoidCallback fn,
            {Color borderColor = const Color(0x33FFE7B0)}) =>
        GestureDetector(
          onTap: fn,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: borderColor),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(emoji, style: const TextStyle(fontSize: 26)),
                const SizedBox(height: 6),
                Text(label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: stroke,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        );

    // Helper: small transport button
    Widget transport(IconData icon, String label, VoidCallback fn) =>
        GestureDetector(
          onTap: fn,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.07),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0x33FFE7B0)),
                ),
                child: Icon(icon, color: stroke, size: 20),
              ),
              const SizedBox(height: 4),
              Text(label, style: const TextStyle(color: dim, fontSize: 10)),
            ],
          ),
        );

    final moods = [
      ('⚡', 'Energetic'),
      ('🧘', 'Relaxing'),
      ('🎯', 'Focused'),
      ('🎉', 'Party'),
      ('😴', 'Sleep'),
      ('💼', 'Work'),
    ];

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.92,
      expand: false,
      builder: (_, scrollCtrl) => ListView(
        controller: scrollCtrl,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          // Handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: stroke.withOpacity(0.25),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Title
          const Row(
            children: [
              Text('🎮', style: TextStyle(fontSize: 22)),
              SizedBox(width: 10),
              Text('GM Kai',
                  style: TextStyle(
                      color: stroke,
                      fontSize: 18,
                      fontWeight: FontWeight.w700)),
            ],
          ),

          const SizedBox(height: 4),
          const Text('Gamemaster controls — physical devices & environment',
              style: TextStyle(color: dim, fontSize: 12)),

          const SizedBox(height: 20),

          // ── Pi & Environment ──────────────────────────────────────────────
          const Text('ENVIRONMENT',
              style: TextStyle(color: dim, fontSize: 11, letterSpacing: 1.2)),
          const SizedBox(height: 10),
          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            children: [
              tile('🍓', 'Wake Pi', onWakePi),
              tile('💡', 'Lights', onToggleLight),
              tile('🌈', 'Rainbow', onRainbow),
              tile('💙', 'Pulse', onPulse),
            ],
          ),

          const SizedBox(height: 20),

          // ── Music ─────────────────────────────────────────────────────────
          const Text('MUSIC',
              style: TextStyle(color: dim, fontSize: 11, letterSpacing: 1.2)),
          const SizedBox(height: 12),

          // Transport row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              transport(Icons.skip_previous, 'Prev', () => _musicCmd('prev')),
              transport(Icons.play_arrow, 'Play', () => _musicCmd('play')),
              transport(Icons.pause, 'Pause', () => _musicCmd('pause')),
              transport(Icons.stop, 'Stop', () => _musicCmd('stop')),
              transport(Icons.skip_next, 'Next', () => _musicCmd('next')),
              transport(Icons.shuffle, 'Shuffle', () => _musicCmd('shuffle')),
            ],
          ),

          const SizedBox(height: 14),

          // Mood chips
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: moods
                .map((m) => GestureDetector(
                      onTap: () => _musicCmd('play_mood',
                          {'mood': m.$2.toLowerCase(), 'shuffle': true}),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0x33FFE7B0)),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Text(m.$1, style: const TextStyle(fontSize: 14)),
                          const SizedBox(width: 5),
                          Text(m.$2,
                              style:
                                  const TextStyle(color: stroke, fontSize: 12)),
                        ]),
                      ),
                    ))
                .toList(),
          ),

          const SizedBox(height: 10),

          // Full song library
          GestureDetector(
            onTap: onOpenMusic,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.04),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0x33FFE7B0)),
              ),
              child: const Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.library_music_outlined, color: stroke, size: 18),
                    SizedBox(width: 8),
                    Text('Full Song Library',
                        style: TextStyle(color: stroke, fontSize: 13)),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 20),

          // ── Remote ───────────────────────────────────────────────────────
          const Text('REMOTE',
              style: TextStyle(color: dim, fontSize: 11, letterSpacing: 1.2)),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: onOpenRemote,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.04),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0x44FFE7B0)),
              ),
              child: const Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('🏠', style: TextStyle(fontSize: 20)),
                    SizedBox(width: 10),
                    Text('Home Remote Control',
                        style: TextStyle(
                            color: stroke,
                            fontSize: 14,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
          ),

          // ── Tavern ───────────────────────────────────────────────────────
          const SizedBox(height: 20),
          const Text('TAVERN',
              style: TextStyle(color: dim, fontSize: 11, letterSpacing: 1.2)),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const TavernRegisterScreen(),
                  ));
            },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: const Color(0xFF3D1A00).withOpacity(0.4),
                borderRadius: BorderRadius.circular(14),
                border:
                    Border.all(color: const Color(0xFFD4AF37).withOpacity(0.5)),
              ),
              child: const Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('🪙', style: TextStyle(fontSize: 20)),
                    SizedBox(width: 10),
                    Text('Register NFC Coin',
                        style: TextStyle(
                            color: Color(0xFFD4AF37),
                            fontSize: 14,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
          ),

          // ── Debug ─────────────────────────────────────────────────────────
          const SizedBox(height: 20),
          const Text('DEBUG',
              style: TextStyle(color: dim, fontSize: 11, letterSpacing: 1.2)),
          const SizedBox(height: 10),
          Builder(
              builder: (ctx) => GestureDetector(
                    onTap: () async {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(
                            content: Text('🗜️ Running memory consolidation…'),
                            duration: Duration(seconds: 2)),
                      );
                      try {
                        await MemoryConsolidationService()
                            .forceConsolidate(personaId: personaId);
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(
                                content: Text(
                                    '✅ Consolidation done — check Firebase'),
                                duration: Duration(seconds: 3)),
                          );
                        }
                      } catch (e) {
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(
                                content: Text('❌ $e'),
                                duration: const Duration(seconds: 4)),
                          );
                        }
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.03),
                        borderRadius: BorderRadius.circular(14),
                        border:
                            Border.all(color: Colors.white.withOpacity(0.15)),
                      ),
                      child: const Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('🗜️', style: TextStyle(fontSize: 18)),
                            SizedBox(width: 10),
                            Text('Force Memory Consolidation',
                                style: TextStyle(
                                    color: dim,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ),
                    ),
                  )),
        ],
      ),
    );
  }
}
