// main_mobile.dart
// Mobile-compatible version without desktop-specific dependencies

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:firebase_core/firebase_core.dart';

import 'services/ai/ai_service.dart';
import 'services/core/firebase_service.dart';
import 'services/core/memory_consolidation_service.dart';
import 'services/automation/wake_on_lan_service.dart';
import 'services/voice/voice_activation_service.dart';
import 'services/automation/home_automation_service.dart';
import 'screens/home_remote_screen.dart';
import 'screens/chaos_journal_screen.dart';
import 'screens/mind_map_screen.dart';
import 'screens/brain_3d_screen.dart';
import 'screens/activity_feed_screen.dart';
import 'services/core/activity_card_service.dart';
import 'firebase_options.dart';
import 'widgets/debug_button.dart';
import 'api_key_setup_screen.dart';
import 'services/core/kai_state_service.dart';
import 'services/core/emotional_event_service.dart';
import 'services/core/memory_reflection_service.dart';
import 'services/core/personality_drift_service.dart';
import 'services/core/proactive_service.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

/// ===== Layout / Window =====
const double kSpriteSize = 170;
const double kRingPadding = 48;
const double kCanvasWidth = 560;
const double kCanvasHeight = 600;
const double kSpriteAlignY = 0.30;
const double kUiLiftPx = 64;

/// ===== Avatar assets + timings =====
const String kAvatarIdleFrameDir      = 'assets/avatar/idle_frames/';
const String kAvatarAttentionFrameDir = 'assets/avatar/attention_frames/';
const String kAvatarThinkingFrameDir  = 'assets/avatar/thinking_frames/';
const String kAvatarSpeakingFrameDir  = 'assets/avatar/speaking_frames/';
const String kAvatarFallback          = 'assets/avatar/images/mage.png';
const int kIdleFrameCount      = 121;
const int kAttentionFrameCount = 121;
const int kThinkingFrameCount  = 241;
const int kSpeakingFrameCount  = 121;

const Duration kIdleAfter = Duration(seconds: 15);
const Duration kAttentionPulse = Duration(seconds: 2);

/// Persona IDs
const String kPersonaKai = 'truekai';

/// Global AI service instance
final aiService = AIService();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Show loading state while initializing
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
  
  // Initialize Firebase with error handling
  bool firebaseInitialized = false;
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    await FirebaseService.initialize();
    firebaseInitialized = true;
    print('✅ Firebase initialized successfully');
  } catch (e) {
    print('⚠️ Firebase initialization failed: $e');
    print('📱 App will continue with local storage only');
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
      theme: ThemeData(
        scaffoldBackgroundColor: const Color(0xFF0D0A07),
        primarySwatch: Colors.amber,
        brightness: Brightness.dark,
      ),
      home: _MobileKai(firebaseInitialized: firebaseInitialized),
    );
  }
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
    with TickerProviderStateMixin {
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
  bool _sending = false;
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
  DateTime _lastInteraction = DateTime.now();
  DateTime _attentionUntil = DateTime.fromMillisecondsSinceEpoch(0);
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
      // Close any overlay left over from a previous session / hot restart
      try {
        if (await FlutterOverlayWindow.isActive()) {
          await FlutterOverlayWindow.closeOverlay();
          print('🔵 [Init] Closed stale overlay from previous session');
        }
      } catch (_) {}

      // 1 — avatar frames (the slow one)
      _setStep('Loading avatar…');
      await _precacheAnimation(kAvatarIdleFrameDir, kIdleFrameCount);
      if (mounted) _switchToAnimation('idle');

      // 2 — warm up the AI persona
      _setStep('Waking Kai…');
      await aiService.bootstrapPersona(_personaId)
          .catchError((e) => print('⚠️ [Bootstrap] $e'));

      // 3 — check for a message Kai left while we were away
      _setStep('Checking messages…');
      await ProactiveService().initialize(_personaId)
          .catchError((e) => print('⚠️ [Proactive] $e'));
      final pending = await ProactiveService()
          .checkPendingMessage(_personaId)
          .catchError((e) { print('⚠️ [Proactive] $e'); return null; });
      if (pending != null && mounted) {
        await ProactiveService().markDelivered(_personaId, pending.id);
        setState(() => _reply = pending.message);
        _setBubble(true);
      }

      // Done — show UI immediately, other animations load on first use
      if (mounted) setState(() => _isLoading = false);
      MemoryReflectionService().maybeReflect(personaId: _personaId)
          .catchError((e) => print('⚠️ [Reflection] $e'));
      PersonalityDriftService().maybeDrift(personaId: _personaId)
          .catchError((e) => print('⚠️ [Drift] $e'));
    } catch (e) {
      print('❌ [Init] $e');
      // Don't block the user — just open the app
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _markInteraction() {
    _lastInteraction = DateTime.now();
    _resetIdleTimer();
  }

  void _setBubble(bool open) {
    if (_showBubble == open) return;
    setState(() => _showBubble = open);
    if (open) {
      VoiceActivationService().pause();
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
    _attentionUntil = DateTime.now().add(kAttentionPulse);
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
      case 'attention': return kAttentionFrameCount;
      case 'thinking':  return kThinkingFrameCount;
      case 'speaking':  return kSpeakingFrameCount;
      default:          return kIdleFrameCount;
    }
  }

  String _getFrameDir(String animType) {
    switch (animType) {
      case 'attention': return kAvatarAttentionFrameDir;
      case 'thinking':  return kAvatarThinkingFrameDir;
      case 'speaking':  return kAvatarSpeakingFrameDir;
      default:          return kAvatarIdleFrameDir;
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
        final frame = (ctrl.value * frameCount).floor().clamp(0, frameCount - 1);
        final framePath = '${dir}frame_${frame.toString().padLeft(4, '0')}.png';
        return Image.asset(
          framePath,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Image.asset(kAvatarFallback, fit: BoxFit.cover),
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    KaiStateService().setSurface('mobile');
    EmotionalEventService().setSurface('mobile');
    _glowCtrl =
        AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))
          ..repeat(reverse: true);
    _glow = Tween(begin: 0.35, end: 1.0)
        .chain(CurveTween(curve: Curves.easeInOut))
        .animate(_glowCtrl);

    WidgetsBinding.instance.addPostFrameCallback((_) => _initialize());

    _stateSub = _player.onPlayerStateChanged.listen((s) {
      _currentState = s;

      // Switch animation based on audio state
      if (s == PlayerState.playing) {
        _switchToAnimation('speaking');
        print('🔇 [MAIN_MOBILE] Audio playing - PAUSING voice activation');
        VoiceActivationService().pause();
      } else if (s == PlayerState.stopped || s == PlayerState.completed) {
        _switchToAnimation('idle');
        print('🔊 [MAIN_MOBILE] Audio stopped/completed - RESUMING voice activation (with buffer)');
        VoiceActivationService().resume();
      }
      
      if (mounted) setState(() {});
    });

    // Listen for messages from the flame overlay
    _overlayMsgSub = FlutterOverlayWindow.overlayListener.listen((data) {
      if (data is! Map) return;
      final action = data['action'];
      if (action == 'expand') {
        // Tap: expand the app normally
        _exitBackground();
      } else if (action == 'pauseVoice') {
        // Long press step 1: pause Porcupine so Android SpeechRecognizer can take the mic
        VoiceActivationService().pause();
      } else if (action == 'message') {
        // Long press step 2: transcript arrived — send silently, resume wake word
        final text = (data['text'] as String? ?? '').trim();
        if (text.isNotEmpty) {
          _controller.text = text;
          _send(); // runs in background; TTS plays the response
        }
        VoiceActivationService().resume();
      }
    });

    // Subscribe to wake-word events (VoiceActivationService singleton)
    _wakeWordSub = VoiceActivationService().onWakeWordDetected.listen((transcript) {
      // Wake word brings the app back from background if the overlay is active
      if (mounted) _exitBackground(initialMessage: transcript);
    });

    // Start 3-minute idle-to-background timer
    _resetIdleTimer();
  }

  @override
  void dispose() {
    _glowCtrl.dispose();
    _frameAnimController?.dispose();
    _controller.dispose();
    _focus.dispose();
    _stateSub.cancel();
    _wakeWordSub?.cancel();
    _overlayMsgSub?.cancel();
    _idleBackgroundTimer?.cancel();
    _player.dispose();
    for (final f in _floaters) {
      f.ctrl.dispose();
    }
    super.dispose();
  }

  // ── Background mode ────────────────────────────────────────────────────────

  Future<void> _enterBackground() async {
    if (_inBackgroundTransition) return;
    if (await FlutterOverlayWindow.isActive()) return; // already sleeping
    _inBackgroundTransition = true;
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

      // 2. Now show the flame on top of the home screen (no overlap with the app)
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
      print('🔵 [BackgroundMode] Overlay shown');

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
    _inBackgroundTransition = true;
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
    _switchToAnimation('thinking');
    setState(() {
      _sending = true;
      _reply = null;
      _error = null;
      _ttsPath = null;
      _devOpen = false;
      _memoriesUsed = []; // Clear previous memories
    });
    try {
      final resp = await aiService.sendMessage(
        text: text,
        personaId: _personaId,
        model: _modelId,
        adaptUser: _adaptToUser,
        ctxTurns: _ctxTurns,
      );
      setState(() {
        _reply = resp.reply.isEmpty ? "(no reply)" : resp.reply;
        _memoriesUsed = resp.memoriesUsed; // NEW: Track memories used
        _debugInfo = resp.debugInfo; // NEW: Track debug info
        print('🔍 [DEBUG] debugInfo captured: ${_debugInfo != null ? "YES" : "NO"}');
        if (_debugInfo != null) {
          print('🔍 [DEBUG] debugInfo keys: ${_debugInfo!.keys.join(", ")}');
        }
      });
      _spawnDeltas(resp.actualDeltas);

      // 🃏 Save activity card (fire-and-forget)
      ActivityCardService().saveCard(
        personaId:         _personaId,
        userMessage:       text,
        kaiReply:          resp.reply,
        personalityDelta:  resp.personalityDelta,
        moodDelta:         resp.moodDelta,
        tags:              resp.tags,
        mbti:              resp.mbti,
        memoriesUsed:      resp.memoriesUsed,
        webSearchUsed:     resp.webSearchUsed,
        curiosityQuestion: resp.curiosityQuestion?.question,
        inputTokens:       resp.promptInputTokens,
        outputTokens:      resp.promptOutputTokens,
        costUsd:           resp.promptCostUsd,
      ).catchError((e) => print('⚠️ [ActivityCard] $e'));

      // Note: Conversation already saved to Firebase in ai_service.sendMessage()
      
      if (resp.ttsBase64 != null) {
        final mp3Path = await _writeTempMp3(base64Decode(resp.ttsBase64!));
        if (_autoPlayTts) {
          await _player.stop();
          await _player.play(DeviceFileSource(mp3Path));
        }
        setState(() => _ttsPath = mp3Path);
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _devOpen = true;
      });
    } finally {
      if (!_isSpeaking) _switchToAnimation('idle');
      setState(() {
        _sending = false;
      });
    }
  }

  Future<String> _writeTempMp3(Uint8List bytes) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/kai_reply_${DateTime.now().millisecondsSinceEpoch}.mp3');
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
        await _sendAudioFeedback('I\'ve toggled the living room light for you! The LED strip should now be responding.');
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? '💡 Living Room light toggled! 🔊 Audio sent' : '❌ Light control failed'),
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
        await _sendAudioFeedback('Good morning! I\'m now online and ready to help.');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('📱 Pi needs manual power-on (WoL not supported on this model)'),
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
        await _sendAudioFeedback('Rainbow mode activated! Enjoy the beautiful cascade of colors flowing across your LED strip.');
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? '🌈 Rainbow effect started! 🔊 Audio sent' : '❌ Rainbow failed'),
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
        await _sendAudioFeedback('Blue pulse effect activated! Watch as the gentle blue waves flow through your lighting system.');
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? '💙 Blue pulse started! 🔊 Audio sent' : '❌ Pulse failed'),
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

  Future<void> _playMusic() async {
    // Show music selection dialog
    _showMusicSelectionDialog();
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
              const Text('🎶 Individual Songs:', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              ..._buildSongList(),
              
              const SizedBox(height: 16),
              
              // Mood Playlists  
              const Text('🎭 Mood Playlists:', style: TextStyle(color: Colors.green, fontWeight: FontWeight.w600)),
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
      {'name': 'Electronic Beat', 'genre': 'Electronic', 'duration': '3:00', 'id': 'electronic_beat'},
      {'name': 'Synthwave Nights', 'genre': 'Synthwave', 'duration': '4:00', 'id': 'synthwave_nights'},
      {'name': 'Ambient Space', 'genre': 'Ambient', 'duration': '5:00', 'id': 'ambient_space'},
      {'name': 'Nature Sounds', 'genre': 'Nature', 'duration': '10:00', 'id': 'nature_sounds'},
      {'name': 'Piano Meditation', 'genre': 'Classical', 'duration': '4:40', 'id': 'piano_meditation'},
      {'name': 'Lo-Fi Study', 'genre': 'Lo-Fi', 'duration': '3:20', 'id': 'lofi_study'},
      {'name': 'Chiptune Adventure', 'genre': '8-Bit', 'duration': '2:30', 'id': 'chiptune_adventure'},
    ];

    return songs.map((song) => Padding(
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
              const Icon(Icons.play_circle_outline, size: 20, color: Colors.purple),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(song['name']!, style: const TextStyle(fontWeight: FontWeight.w500)),
                    Text('${song['genre']} • ${song['duration']}', 
                         style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    )).toList();
  }

  List<Widget> _buildMoodList() {
    final moods = [
      {'name': 'Energetic', 'desc': 'Upbeat & electronic', 'id': 'energetic', 'icon': '⚡'},
      {'name': 'Relaxing', 'desc': 'Ambient & peaceful', 'id': 'relaxing', 'icon': '🧘'},
      {'name': 'Focused', 'desc': 'Lo-fi & concentration', 'id': 'focused', 'icon': '🎯'},
      {'name': 'Party', 'desc': 'High-energy dance', 'id': 'party', 'icon': '🎉'},
      {'name': 'Meditation', 'desc': 'Calm & mindful', 'id': 'meditation', 'icon': '🕉️'},
      {'name': 'Work', 'desc': 'Background productivity', 'id': 'work', 'icon': '💼'},
      {'name': 'Sleep', 'desc': 'Gentle lullabies', 'id': 'sleep', 'icon': '😴'},
    ];

    return moods.map((mood) => Padding(
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
                    Text(mood['name']!, style: const TextStyle(fontWeight: FontWeight.w500)),
                    Text(mood['desc']!, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                  ],
                ),
              ),
              const Icon(Icons.playlist_play, color: Colors.blue),
            ],
          ),
        ),
      ),
    )).toList();
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
        await _sendAudioFeedback('Now playing your selected song through Bluetooth speaker!');
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? '🎵 Song started! 🔊' : '❌ Song command failed'),
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
        await _sendAudioFeedback('Starting $mood music playlist! Perfect choice for your current mood.');
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? '🎭 $mood playlist started! 🔊' : '❌ Playlist command failed'),
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
        await _sendAudioFeedback('Starting energetic music playlist! Get ready for some great tunes through your Bluetooth speaker.');
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? '🎵 Music started!' : '❌ Music command failed'),
          duration: const Duration(seconds: 2),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Music error: $e'), duration: const Duration(seconds: 2), backgroundColor: Colors.red),
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


}  /// Open home remote control interface
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
                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF3D9BFF)),
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
                builder: (_) => ApiKeySetupScreen(onComplete: () => Navigator.pop(context)),
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
              // Avatar section
              SizedBox(
                height: 300,
                child: Center(
                  child: GestureDetector(
                    onTap: () {
                      _markInteraction();
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
                            Container(
                              width: kSpriteSize + kRingPadding * 2,
                              height: kSpriteSize + kRingPadding * 2,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: stroke.withOpacity(0.3 * _glow.value),
                                    blurRadius: 20,
                                    spreadRadius: 5,
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
                                  parent: f.ctrl, curve: Curves.easeOutCubic);
                              return Positioned(
                                left: cos(f.angle) * (kSpriteSize * 0.7) * (1 + anim.value * 0.3),
                                top: sin(f.angle) * (kSpriteSize * 0.7) * (1 + anim.value * 0.3) - anim.value * 20,
                                child: Opacity(
                                  opacity: (1.0 - anim.value).clamp(0.0, 1.0),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.6),
                                      borderRadius: BorderRadius.circular(12),
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
                    ),
                  ),
                ),
              ),

              // Name badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                        builder: (_) => ChaosJournalScreen(personaId: _personaId),
                      ),
                    ),
                  ),
                  _MobileButton(
                    icon: Icons.hub_outlined,
                    label: 'Brain',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => Brain3DScreen(personaId: _personaId),
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
                        builder: (_) => ActivityFeedScreen(personaId: _personaId),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // Chat section
              if (_showBubble)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: _MobileChatBubble(
                    sending: _sending,
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
              style: const TextStyle(color: stroke, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

class _MobileChatBubble extends StatelessWidget {
  final bool sending;
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

  const _MobileChatBubble({
    required this.sending,
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
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: Colors.purple.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.purple.withOpacity(0.5), width: 1),
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
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Text(
                        'Voice:',
                        style: TextStyle(color: stroke, fontWeight: FontWeight.w600),
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
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : StreamBuilder<PlayerState>(
                                stream: playingStream,
                                builder: (context, snap) {
                                  final playing = snap.data == PlayerState.playing;
                                  return Icon(playing ? Icons.pause : Icons.play_arrow);
                                },
                              ),
                        label: const Text('Play/Pause'),
                      ),
                      if (debugInfo != null) ...[
                        const SizedBox(width: 8),
                        DebugButton(
                          debugInfo: debugInfo!,
                          personaId: personaId,
                        ),
                      ] else ...[
                        // Debug: Show why button isn't appearing
                        const Text('No debug', style: TextStyle(color: Colors.red, fontSize: 10)),
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
                        style: const TextStyle(color: Colors.amber, fontSize: 12),
                      ),
                      Text(
                        'ElevenLabs: ${env['ELEVENLABS_API_KEY_set'] ?? false ? 'configured' : 'missing'}',
                        style: const TextStyle(color: Colors.amber, fontSize: 12),
                      ),
                      Text(
                        'Google: ${env['GOOGLE_API_KEY_set'] ?? false ? 'configured' : 'missing'}',
                        style: const TextStyle(color: Colors.amber, fontSize: 12),
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
          Map<String, num> pc, Map<String, num> mc, Map<String, num> ac)
      onSave;
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
    _mc = widget.initial.moodCurrent
        .map((k, v) => MapEntry(k, v.toDouble()));
    _ac = widget.initial.affinityCurrent
        .map((k, v) => MapEntry(k, v.toDouble()));
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                      style: const TextStyle(
                          color: Colors.white70, height: 1.25)),
                  const SizedBox(height: 12),
                ],

                // Developmental drift portrait
                FutureBuilder<DriftSummary?>(
                  future: PersonalityDriftService.getDriftSummary(widget.personaId),
                  builder: (context, snap) {
                    final drift = snap.data;
                    if (drift == null || drift.narrativeArc.isEmpty) return const SizedBox.shrink();
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
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0x22B8A9FF),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                drift.confidence.toUpperCase(),
                                style: const TextStyle(color: Color(0x88B8A9FF), fontSize: 9, letterSpacing: 0.8),
                              ),
                            ),
                          ]),
                          const SizedBox(height: 8),
                          // Narrative arc
                          Text(drift.narrativeArc,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 12, height: 1.4,
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
                          if (drift.cumulativeDescription != 'No significant drift yet') ...[
                            const SizedBox(height: 8),
                            Text(drift.cumulativeDescription,
                                style: const TextStyle(
                                    color: Color(0x66B8A9FF), fontSize: 10, letterSpacing: 0.3)),
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
                    border: Border.all(color: stroke.withOpacity(0.6), width: 1),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Personality', style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      sliderRow(
                          title: 'Extraversion',
                          max: 1000,
                          value: _pc['extraversion'] ?? 0,
                          onChanged: (v) => setState(() => _pc['extraversion'] = v),
                          label: (pl['extraversion'] ?? '—').toString()),
                      sliderRow(
                          title: 'Intuition',
                          max: 1000,
                          value: _pc['intuition'] ?? 0,
                          onChanged: (v) => setState(() => _pc['intuition'] = v),
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
                          onChanged: (v) => setState(() => _pc['perceiving'] = v),
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
                    border: Border.all(color: stroke.withOpacity(0.6), width: 1),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Mood', style: TextStyle(fontWeight: FontWeight.w600)),
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
                          onChanged: (v) => setState(() => _mc['confidence'] = v),
                          label: (ml['confidence'] ?? '—').toString()),
                      sliderRow(
                          title: 'Playfulness',
                          max: 100,
                          value: _mc['playfulness'] ?? 0,
                          onChanged: (v) => setState(() => _mc['playfulness'] = v),
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
                      border: Border.all(color: stroke.withOpacity(0.6), width: 1),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Affinity', style: TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        sliderRow(
                            title: 'Intimacy',
                            max: 100,
                            value: _ac['intimacy'] ?? 50,
                            onChanged: (v) => setState(() => _ac['intimacy'] = v)),
                        sliderRow(
                            title: 'Physicality',
                            max: 100,
                            value: _ac['physicality'] ?? 50,
                            onChanged: (v) => setState(() => _ac['physicality'] = v)),
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
                                  const SnackBar(content: Text('Saved locally')));
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

/// Music Control Button Widget
class _MusicControlButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _MusicControlButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon, color: Colors.white70, size: 18),
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
                    color: Color(0x88B8A9FF), fontSize: 10,
                    fontWeight: FontWeight.w600, letterSpacing: 0.5)),
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
    HomeAutomationService().sendCommand(
      personaId: 'truekai',
      deviceId: 'raspberry_pi_home',
      target: 'music',
      action: action,
      params: params ?? {},
    ).catchError((e) => print('GM music $action error: $e'));
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
                        color: stroke, fontSize: 12, fontWeight: FontWeight.w600)),
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
      ('⚡', 'Energetic'), ('🧘', 'Relaxing'), ('🎯', 'Focused'),
      ('🎉', 'Party'),     ('😴', 'Sleep'),    ('💼', 'Work'),
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
              width: 36, height: 4,
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
                      color: stroke, fontSize: 18, fontWeight: FontWeight.w700)),
            ],
          ),

          const SizedBox(height: 4),
          const Text('Gamemaster controls — physical devices & environment',
              style: TextStyle(color: dim, fontSize: 12)),

          const SizedBox(height: 20),

          // ── Pi & Environment ──────────────────────────────────────────────
          const Text('ENVIRONMENT', style: TextStyle(color: dim, fontSize: 11, letterSpacing: 1.2)),
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
          const Text('MUSIC', style: TextStyle(color: dim, fontSize: 11, letterSpacing: 1.2)),
          const SizedBox(height: 12),

          // Transport row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              transport(Icons.skip_previous, 'Prev',  () => _musicCmd('prev')),
              transport(Icons.play_arrow,    'Play',  () => _musicCmd('play')),
              transport(Icons.pause,         'Pause', () => _musicCmd('pause')),
              transport(Icons.stop,          'Stop',  () => _musicCmd('stop')),
              transport(Icons.skip_next,     'Next',  () => _musicCmd('next')),
              transport(Icons.shuffle,       'Shuffle',() => _musicCmd('shuffle')),
            ],
          ),

          const SizedBox(height: 14),

          // Mood chips
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: moods.map((m) => GestureDetector(
              onTap: () => _musicCmd('play_mood',
                  {'mood': m.$2.toLowerCase(), 'shuffle': true}),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0x33FFE7B0)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(m.$1, style: const TextStyle(fontSize: 14)),
                  const SizedBox(width: 5),
                  Text(m.$2, style: const TextStyle(color: stroke, fontSize: 12)),
                ]),
              ),
            )).toList(),
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
                    Text('Full Song Library', style: TextStyle(color: stroke, fontSize: 13)),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 20),

          // ── Remote ───────────────────────────────────────────────────────
          const Text('REMOTE', style: TextStyle(color: dim, fontSize: 11, letterSpacing: 1.2)),
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
                            color: stroke, fontSize: 14, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
          ),

          // ── Debug ─────────────────────────────────────────────────────────
          const SizedBox(height: 20),
          const Text('DEBUG', style: TextStyle(color: dim, fontSize: 11, letterSpacing: 1.2)),
          const SizedBox(height: 10),
          Builder(builder: (ctx) => GestureDetector(
            onTap: () async {
              ScaffoldMessenger.of(ctx).showSnackBar(
                const SnackBar(content: Text('🗜️ Running memory consolidation…'), duration: Duration(seconds: 2)),
              );
              try {
                await MemoryConsolidationService().forceConsolidate(personaId: personaId);
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('✅ Consolidation done — check Firebase'), duration: Duration(seconds: 3)),
                  );
                }
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(content: Text('❌ $e'), duration: const Duration(seconds: 4)),
                  );
                }
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.03),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withOpacity(0.15)),
              ),
              child: const Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('🗜️', style: TextStyle(fontSize: 18)),
                    SizedBox(width: 10),
                    Text('Force Memory Consolidation',
                        style: TextStyle(color: dim, fontSize: 13, fontWeight: FontWeight.w500)),
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
