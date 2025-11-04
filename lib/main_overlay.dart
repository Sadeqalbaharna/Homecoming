// main_overlay.dart
// True system overlay using flutter_overlay_window - floats above ALL apps like Shimeji!

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';

import 'services/ai_service.dart';
import 'services/voice_service.dart';
import 'services/audio_player_service.dart';
import 'services/secure_storage_service.dart';
import 'services/firebase_service.dart';
import 'services/curiosity_service.dart';
import 'services/proactive_service.dart';
import 'screens/personality_screen.dart';
import 'screens/usage_stats_screen.dart';
import 'api_key_setup_screen.dart';
import 'widgets/debug_button.dart';
import 'widgets/memory_chips.dart';
import 'widgets/expanded_window.dart';
import 'widgets/curiosity_indicator.dart';
import 'package:permission_handler/permission_handler.dart';

// API KEYS - Read from build-time environment (--dart-define)
// These are injected by GitHub Actions from secrets during CI/CD build
const String OPENAI_API_KEY = String.fromEnvironment('OPENAI_API_KEY', defaultValue: '');
const String ELEVENLABS_API_KEY = String.fromEnvironment('ELEVENLABS_API_KEY', defaultValue: '');

// DEV CONFIG - Only for local development without rebuild
const bool USE_DEV_MODE = true; // Set to true locally, false in repo
const bool SKIP_API_CHECK_FOR_UI_DEV = true; // NEW: Skip API checks for UI development
class DevConfig {
  static const String DEV_OPENAI_KEY = 'dummy-key-for-ui-dev';
  static const String DEV_ELEVENLABS_KEY = 'dummy-key-for-ui-dev';
  static bool get hasDevKeys => DEV_OPENAI_KEY.isNotEmpty && DEV_ELEVENLABS_KEY.isNotEmpty;
}

/// Kai avatar assets - Frame-based animations (lightweight!)
const String kAvatarIdleFrameDir = 'assets/avatar/idle_frames/';
const String kAvatarAttentionFrameDir = 'assets/avatar/attention_frames/';
const String kAvatarThinkingFrameDir = 'assets/avatar/thinking_frames/';
const String kAvatarSpeakingFrameDir = 'assets/avatar/speaking_frames/';
const int kIdleFrameCount = 121;
const int kAttentionFrameCount = 121;
const int kThinkingFrameCount = 241;
const int kSpeakingFrameCount = 121;
// Fallback static image
const String kAvatarFallback = 'assets/avatar/images/mage.png';

/// Global AI service instance
final aiService = AIService();

/// Global voice service instance
final voiceService = VoiceService();

// ============= OVERLAY ENTRY POINT =============
// This function runs in a separate isolate for the overlay window
@pragma("vm:entry-point")
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: OverlayWidget(),
    ),
  );
}

// ============= MAIN APP ENTRY POINT =============
// This starts the overlay service then closes
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Check for API keys first
  final secureStorage = SecureStorageService();
  
  // Priority 1: Use build-time keys from --dart-define (GitHub Actions)
  if (OPENAI_API_KEY.isNotEmpty && ELEVENLABS_API_KEY.isNotEmpty) {
    print('🔑 Using API keys from build-time environment (--dart-define)');
    await secureStorage.setOpenAIKey(OPENAI_API_KEY);
    await secureStorage.setElevenLabsKey(ELEVENLABS_API_KEY);
  }
  // Priority 2: DEV MODE (local development)
  else if (USE_DEV_MODE && DevConfig.hasDevKeys) {
    print('🔧 DEV MODE: Using hardcoded API keys');
    await secureStorage.setOpenAIKey(DevConfig.DEV_OPENAI_KEY);
    await secureStorage.setElevenLabsKey(DevConfig.DEV_ELEVENLABS_KEY);
  }
  
  final hasKeys = await secureStorage.hasKeys();
  
  if (!hasKeys) {
    // No API keys - show setup screen first
    runApp(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.amber,
        brightness: Brightness.dark,
      ),
      home: ApiKeySetupScreen(
        onComplete: () async {
          // Keys configured, now request microphone permission
          final micStatus = await Permission.microphone.request();
          print('🎤 Microphone permission: $micStatus');
          
          // Check overlay permission
          final status = await FlutterOverlayWindow.isPermissionGranted();
          if (!status) {
            // Need overlay permission
            runApp(const PermissionRequestApp());
          } else {
            // Start overlay
            await startOverlay();
            const platform = MethodChannel('com.homecoming.app/activity');
            try {
              await platform.invokeMethod('finishActivity');
            } catch (e) {
              SystemNavigator.pop();
            }
          }
        },
      ),
    ));
    return;
  }
  
  // API keys exist, request microphone permission if needed
  final micStatus = await Permission.microphone.status;
  if (!micStatus.isGranted) {
    await Permission.microphone.request();
    print('🎤 Microphone permission requested: ${await Permission.microphone.status}');
  }
  
  // API keys exist, check overlay permission
  final bool status = await FlutterOverlayWindow.isPermissionGranted();
  
  if (!status) {
    // Need to request permission - show permission screen
    runApp(const PermissionRequestApp());
  } else {
    // Permission granted, start overlay immediately
    await startOverlay();
    
    // Finish MainActivity immediately - no delay needed
    // The overlay service is already started and runs independently
    const platform = MethodChannel('com.homecoming.app/activity');
    try {
      await platform.invokeMethod('finishActivity');
    } catch (e) {
      // If method channel fails, fall back to SystemNavigator
      SystemNavigator.pop();
    }
  }
}

Future<void> startOverlay() async {
  await FlutterOverlayWindow.showOverlay(
    enableDrag: true, // Let Java handle drag natively for smooth performance!
    overlayTitle: "Kai",
    overlayContent: "Tap to chat with Kai!",
    flag: OverlayFlag.defaultFlag, // Start with defaultFlag - no keyboard focus for floating avatar
    visibility: NotificationVisibility.visibilityPublic,
    positionGravity: PositionGravity.none, // No snap-to-edge behavior
    width: 200, // Compact size for floating: Kai (100px) + minimal padding
    height: 200, // Compact size for floating
  );
}

// ============= PERMISSION REQUEST SCREEN =============
class PermissionRequestApp extends StatelessWidget {
  const PermissionRequestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.amber,
        brightness: Brightness.dark,
      ),
      home: const PermissionScreen(),
    );
  }
}

class PermissionScreen extends StatefulWidget {
  const PermissionScreen({super.key});

  @override
  State<PermissionScreen> createState() => _PermissionScreenState();
}

class _PermissionScreenState extends State<PermissionScreen> with WidgetsBindingObserver {
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // When user returns from settings
    if (state == AppLifecycleState.resumed) {
      _checkPermissionAndStart();
    }
  }

  Future<void> _checkPermissionAndStart() async {
    final granted = await FlutterOverlayWindow.isPermissionGranted();
    if (granted) {
      // Permission granted! Start overlay
      await startOverlay();
      
      // Finish MainActivity
      const platform = MethodChannel('com.homecoming.app/activity');
      try {
        await platform.invokeMethod('finishActivity');
      } catch (e) {
        SystemNavigator.pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0A07),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFFFE7B0), width: 3),
                ),
                child: ClipOval(
                  child: Image.asset(kAvatarFallback, fit: BoxFit.cover),
                ),
              ),
              const SizedBox(height: 32),
              const Text(
                'Kai needs permission to float',
                style: TextStyle(
                  color: Color(0xFFFFE7B0),
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              const Text(
                'Allow Kai to appear on top of other apps so you can chat anywhere!',
                style: TextStyle(color: Colors.white70, fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),
              ElevatedButton(
                onPressed: () async {
                  // Request permission - this will open settings
                  await FlutterOverlayWindow.requestPermission();
                  // When user returns, didChangeAppLifecycleState will handle it
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFE7B0),
                  foregroundColor: const Color(0xFF0D0A07),
                  padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
                child: const Text(
                  'Grant Permission',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============= CHAT MESSAGE MODEL =============
class ChatMessage {
  final String text;
  final bool isUser; // true = user, false = Kai
  final DateTime timestamp;
  final String? audioPath; // Optional: path to audio file for this message
  final List<String> memoriesUsed; // NEW: Memories referenced in this response
  final Map<String, dynamic>? debugInfo; // DEBUG: AI decision-making data

  ChatMessage({
    required this.text,
    required this.isUser,
    DateTime? timestamp,
    this.audioPath,
    this.memoriesUsed = const [], // NEW: Default to empty list
    this.debugInfo, // DEBUG: Optional debug data
  }) : timestamp = timestamp ?? DateTime.now();
}

// ============= DELTA FLOATER MODEL =============
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

// ============= OVERLAY WIDGET =============
// This is the actual floating widget that appears over other apps
class OverlayWidget extends StatefulWidget {
  const OverlayWidget({super.key});

  @override
  State<OverlayWidget> createState() => _OverlayWidgetState();
}

class _OverlayWidgetState extends State<OverlayWidget> with TickerProviderStateMixin {
  bool _expanded = false;
  bool _showMenu = false; // New: controls circular menu visibility
  bool _showPersonality = false; // Controls personality screen fullscreen
  bool _showAnalytics = false; // Controls analytics screen fullscreen
  bool _showExpandedWindow = false; // NEW: Controls unified expanded window with tabs
  int _expandedWindowInitialTab = 0; // NEW: Which tab to open (0=Chat, 1=Personality, 2=Analytics)
  final _controller = TextEditingController();
  final _player = AudioPlayer();
  
  // Chat history
  final List<ChatMessage> _chatHistory = [];
  final ScrollController _chatScrollController = ScrollController();
  
  bool _sending = false;
  String? _reply;
  String? _error;
  String? _ttsPath;
  PlayerState? _playerState;
  Map<String, dynamic>? _debugInfo; // Debug info from AI response
  
  // Voice recording - TODO: Re-enable after fixing record package
  // final _voiceService = VoiceService();
  bool _isRecording = false;
  String? _recordedAudioPath; // Store the recorded audio path for playback
  final _audioPlayer = AudioPlayerService();
  bool _isPlayingRecording = false;
  
  // Delta popups
  final List<_Floater> _floaters = [];
  final Random _rng = Random();
  
  // Sound indicators for recording
  final _beepPlayer = AudioPlayer();
  
  // TEST: Simple audio recording/playback test (will use service when fixed)
  bool _isTestRecording = false;
  String? _testAudioPath;
  bool _isPlayingTest = false;
  
  // Proactive AI service
  final ProactiveService _proactive = ProactiveService();
  
  // Auto-movement variables
  Timer? _moveTimer;
  bool _isAutoMoving = false;
  double _currentX = 0.0;
  double _currentY = 0.0;
  double _velocityX = 0.0; // For bounce physics
  double _velocityY = 0.0;
  final Random _random = Random();
  bool _positionInitialized = false;
  Timer? _positionMonitor;
  bool _userIsDragging = false;
  Timer? _dragResumeTimer;
  
  // Animation state - automatic based on app activity
  String _currentAnimation = 'idle'; // 'idle', 'attention', 'thinking', 'speaking'
  int _currentFrame = 0;
  AnimationController? _frameAnimController;
  
  // Helper to get current frame count based on animation
  int _getFrameCount(String animType) {
    switch (animType) {
      case 'idle': return kIdleFrameCount;
      case 'attention': return kAttentionFrameCount;
      case 'thinking': return kThinkingFrameCount;
      case 'speaking': return kSpeakingFrameCount;
      default: return kIdleFrameCount;
    }
  }
  
  // Helper to switch animation and start frame controller
  void _switchToAnimation(String animType) {
    setState(() {
      _currentAnimation = animType;
      _currentFrame = 0;
    });
    
    // Dispose old controller
    _frameAnimController?.dispose();
    _frameAnimController = null;
    
    // Create controller for all animations (including idle!)
    final frameCount = _getFrameCount(animType);
    _frameAnimController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: frameCount * 40), // ~25 fps
    )..addListener(() {
      if (mounted) {
        setState(() {
          _currentFrame = (_frameAnimController!.value * frameCount).floor() % frameCount;
        });
      }
    })..repeat();
  }
  
  // Build avatar widget based on current animation
  Widget _buildAvatarWidget() {
    // All animations now use frame-based animation
    String frameDir;
    switch (_currentAnimation) {
      case 'idle': frameDir = kAvatarIdleFrameDir; break;
      case 'attention': frameDir = kAvatarAttentionFrameDir; break;
      case 'thinking': frameDir = kAvatarThinkingFrameDir; break;
      case 'speaking': frameDir = kAvatarSpeakingFrameDir; break;
      default: frameDir = kAvatarIdleFrameDir;
    }
    
    return Image.asset(
      '${frameDir}frame_${_currentFrame.toString().padLeft(4, '0')}.png',
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) {
        return Image.asset(kAvatarFallback, fit: BoxFit.contain);
      },
    );
  }
  
  // Update animation based on app state (automatic mode)
  void _updateAnimationState() {
    String targetAnim = 'idle';
    
    // Priority order: recording > playing > sending > idle
    if (_isRecording) {
      targetAnim = 'attention'; // Listening animation when recording
    } else if (_playerState == PlayerState.playing) {
      targetAnim = 'speaking'; // Speaking animation when playing TTS
    } else if (_sending) {
      targetAnim = 'thinking'; // Thinking animation when loading/processing
    }
    // else stays 'idle'
    
    if (targetAnim != _currentAnimation) {
      _switchToAnimation(targetAnim);
    }
  }
  
  // Precache animation frames to prevent glitchy first load
  Future<void> _precacheAnimationFrames() async {
    if (!mounted) return;
    
    // Precache first few frames of each animation
    final animations = [
      (kIdleFrameCount, kAvatarIdleFrameDir),
      (kAttentionFrameCount, kAvatarAttentionFrameDir),
      (kThinkingFrameCount, kAvatarThinkingFrameDir),
      (kSpeakingFrameCount, kAvatarSpeakingFrameDir),
    ];
    
    for (final (frameCount, frameDir) in animations) {
      // Precache first 10 frames of each animation
      final framesToCache = frameCount < 10 ? frameCount : 10;
      for (int i = 0; i < framesToCache; i++) {
        final framePath = '${frameDir}frame_${i.toString().padLeft(4, '0')}.png';
        precacheImage(AssetImage(framePath), context);
      }
    }
  }

  // Start auto-movement - moves the entire window programmatically
  void _startAutoMovement() async {
    if (_isAutoMoving || _expanded || _showMenu) return;
    
    // Get current position from Java first
    if (!_positionInitialized) {
      try {
        final pos = await FlutterOverlayWindow.getOverlayPosition();
        _currentX = pos.x;
        _currentY = pos.y;
        _positionInitialized = true;
        print('📍 Initialized position: ($_currentX, $_currentY)');
      } catch (e) {
        print('❌ Failed to get position: $e');
        // Default to center
        _currentX = 440.0; // (1080 - 200) / 2
        _currentY = 1070.0; // (2340 - 200) / 2
        _positionInitialized = true;
      }
    }
    
    // Use actual screen dimensions (measured: 1080x2400px at 420dpi = 411x914dp)
    const screenWidth = 411.0;  // dp
    const screenHeight = 914.0; // dp
    const windowSize = 200.0;
    
    // Avatar positioning within window (from UI layout):
    // Avatar is 100x120dp at position (50, 40) within 200x200 window
    // So avatar occupies: left=50dp, right=150dp, top=40dp, bottom=160dp
    const avatarLeft = 50.0;   // Left margin in window
    const avatarRight = 50.0;  // Right margin in window (200 - 150)
    const avatarTop = 40.0;    // Top margin in window
    const avatarBottom = 40.0; // Bottom margin in window (200 - 160)
    
    print('📱 Screen dimensions: ${screenWidth}dp x ${screenHeight}dp');
    
    // Initialize random velocity (bouncing ball physics)
    _velocityX = (_random.nextDouble() * 4.0 - 2.0); // -2 to 2 dp per frame
    _velocityY = (_random.nextDouble() * 4.0 - 2.0);
    
    print('🎾 Bounce physics starting: position=($_currentX, $_currentY) velocity=($_velocityX, $_velocityY)');
    _isAutoMoving = true;
    
    // Monitor position for user drag detection (start after a short delay)
    Future.delayed(const Duration(milliseconds: 500), () {
      if (!mounted || !_isAutoMoving) return;
      
      _positionMonitor = Timer.periodic(const Duration(milliseconds: 50), (timer) async {
        if (!_isAutoMoving || !mounted) {
          timer.cancel();
          return;
        }
        
        try {
          final pos = await FlutterOverlayWindow.getOverlayPosition();
          final diffX = (pos.x - _currentX).abs();
          final diffY = (pos.y - _currentY).abs();
          
          // If position changed significantly without us moving it, user is dragging
          // Lower threshold for quicker response - 5dp is enough to detect intentional drag
          if (diffX > 5 || diffY > 5) {
            if (!_userIsDragging) {
              print('👆 User drag detected! Pausing auto-movement...');
            }
            _userIsDragging = true;
            
            // Update tracked position but clamp it within bounds
            // Account for avatar position within window so avatar stays fully visible
            const minX = -avatarLeft;  // Allow window to go left until avatar's left edge hits screen left
            const maxX = screenWidth - windowSize + avatarRight;  // Allow window to go right until avatar's right edge hits screen right
            const minY = -avatarTop;   // Allow window to go up until avatar's top edge hits screen top
            const maxY = screenHeight - windowSize + avatarBottom; // Allow window to go down until avatar's bottom edge hits screen bottom
            _currentX = pos.x.clamp(minX, maxX);
            _currentY = pos.y.clamp(minY, maxY);
            
            // Cancel previous resume timer and create a new one
            _dragResumeTimer?.cancel();
            _dragResumeTimer = Timer(const Duration(seconds: 2), () {
              if (mounted && _userIsDragging) {
                _userIsDragging = false;
                print('✅ Resuming auto-movement from ($_currentX, $_currentY)');
              }
            });
          }
        } catch (e) {
          // Ignore position check errors
        }
      });
    });
    
    _moveTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (_expanded || _showMenu || !mounted) {
        timer.cancel();
        _isAutoMoving = false;
        return;
      }
      
      // Skip movement if user is dragging
      if (_userIsDragging) return;
      
      // Calculate boundaries accounting for avatar position within window
      const minX = -avatarLeft;
      const maxX = screenWidth - windowSize + avatarRight;
      const minY = -avatarTop;
      const maxY = screenHeight - windowSize + avatarBottom;
      
      // Apply velocity (bouncing ball physics)
      _currentX += _velocityX;
      _currentY += _velocityY;
      
      // Bounce off left/right edges
      if (_currentX <= minX) {
        _currentX = minX;
        _velocityX = _velocityX.abs(); // Bounce right
        print('⬅️ Bounced off left edge, velocity now: $_velocityX');
      } else if (_currentX >= maxX) {
        _currentX = maxX;
        _velocityX = -_velocityX.abs(); // Bounce left
        print('➡️ Bounced off right edge, velocity now: $_velocityX');
      }
      
      // Bounce off top/bottom edges
      if (_currentY <= minY) {
        _currentY = minY;
        _velocityY = _velocityY.abs(); // Bounce down
        print('⬆️ Bounced off top edge, velocity now: $_velocityY');
      } else if (_currentY >= maxY) {
        _currentY = maxY;
        _velocityY = -_velocityY.abs(); // Bounce up
        print('⬇️ Bounced off bottom edge, velocity now: $_velocityY');
      }
      
      // Force clamp to be absolutely sure (safety net)
      _currentX = _currentX.clamp(minX, maxX);
      _currentY = _currentY.clamp(minY, maxY);
      
      // Move the overlay window
      FlutterOverlayWindow.moveOverlay(OverlayPosition(_currentX, _currentY));
    });
  }
  
  // Stop auto-movement
  void _stopAutoMovement() async {
    _moveTimer?.cancel();
    _moveTimer = null;
    _positionMonitor?.cancel();
    _positionMonitor = null;
    _dragResumeTimer?.cancel();
    _dragResumeTimer = null;
    _isAutoMoving = false;
    _userIsDragging = false;
    
    // Update current position from Java when stopping
    try {
      final pos = await FlutterOverlayWindow.getOverlayPosition();
      _currentX = pos.x;
      _currentY = pos.y;
      print('📍 Updated position after stop: ($_currentX, $_currentY)');
    } catch (e) {
      print('❌ Failed to update position: $e');
    }
  }

  // Resize overlay window based on UI state
  Future<void> _resizeOverlay(bool chatExpanded) async {
    if (chatExpanded) {
      // Chat/Personality/Analytics expanded: Use WindowSize.matchParent for full screen
      // WindowSize.matchParent = -1, which tells Android to match parent dimensions
      const expandedWidth = -1; // WindowSize.matchParent
      const expandedHeight = -1; // WindowSize.matchParent
      
      print('📱 [SCREEN] Expanding overlay to FULL SCREEN using WindowSize.matchParent');
      print('📱 [SCREEN] Window will be FIXED (not draggable) to allow scrolling');
      
      try {
        await FlutterOverlayWindow.resizeOverlay(expandedWidth, expandedHeight, false); // false = NOT draggable when expanded
        print('✅ [SCREEN] Resize successful to full screen!');
      } catch (e) {
        print('❌ [SCREEN] Resize failed: $e');
      }
    } else {
      // Menu/avatar only: compact square window (200x200)
      print('📱 [SCREEN] Shrinking overlay back to compact: 200x200');
      try {
        await FlutterOverlayWindow.resizeOverlay(200, 200, true); // true = draggable when compact
        print('✅ [SCREEN] Shrink successful!');
      } catch (e) {
        print('❌ [SCREEN] Shrink failed: $e');
      }
    }
  }
  
  // Helper to close chat and reset flags
  Future<void> _closeChat() async {
    setState(() => _expanded = false);
    await _resizeOverlay(false);
    // Reset flag to defaultFlag when closing chat (no keyboard needed)
    await FlutterOverlayWindow.updateFlag(OverlayFlag.defaultFlag);
  }

  Future<void> _openPersonalityScreen() async {
    print('🧠 [PERSONALITY] Opening personality screen...');
    setState(() {
      _showPersonality = true;
      _expanded = false;
      _showAnalytics = false;
    });
    print('🧠 [PERSONALITY] State updated, calling resize...');
    await _resizeOverlay(true); // Resize to fullscreen
    print('🧠 [PERSONALITY] Personality screen opened!');
  }

  Future<void> _closePersonalityScreen() async {
    setState(() => _showPersonality = false);
    await _resizeOverlay(false);
    await FlutterOverlayWindow.updateFlag(OverlayFlag.defaultFlag);
  }

  Future<void> _openUsageStatsScreen() async {
    print('📊 [ANALYTICS] Opening analytics screen...');
    setState(() {
      _showAnalytics = true;
      _expanded = false;
      _showPersonality = false;
    });
    print('📊 [ANALYTICS] State updated, calling resize...');
    await _resizeOverlay(true); // Resize to fullscreen
    print('📊 [ANALYTICS] Analytics screen opened!');
  }

  Future<void> _closeUsageStatsScreen() async {
    setState(() => _showAnalytics = false);
    await _resizeOverlay(false);
    await FlutterOverlayWindow.updateFlag(OverlayFlag.defaultFlag);
  }

  // NEW: Open unified expanded window with tabs
  Future<void> _openExpandedWindow(int initialTab) async {
    print('📱 [EXPANDED] Opening unified expanded window (tab: $initialTab)...');
    
    // Save current position before moving to (0,0)
    try {
      final pos = await FlutterOverlayWindow.getOverlayPosition();
      _currentX = pos.x;
      _currentY = pos.y;
      print('📍 [EXPANDED] Saved current position: ($_currentX, $_currentY)');
    } catch (e) {
      print('❌ [EXPANDED] Failed to save position: $e');
    }
    
    setState(() {
      _showExpandedWindow = true;
      _expandedWindowInitialTab = initialTab;
      _expanded = false;
      _showPersonality = false;
      _showAnalytics = false;
    });
    print('📱 [EXPANDED] State updated, moving to (0,0) and resizing...');
    
    // CRITICAL: Move overlay to (0,0) BEFORE resizing to full screen
    // This ensures the full-screen window covers the entire device screen
    try {
      await FlutterOverlayWindow.moveOverlay(const OverlayPosition(0, 0));
      print('📱 [EXPANDED] Moved overlay to position (0, 0)');
    } catch (e) {
      print('❌ [EXPANDED] Failed to move overlay: $e');
    }
    
    await _resizeOverlay(true); // Resize to fullscreen
    // Use focusPointer to allow keyboard input in expanded window
    await FlutterOverlayWindow.updateFlag(OverlayFlag.focusPointer);
    print('📱 [EXPANDED] Expanded window opened with keyboard support!');
  }

  // NEW: Close unified expanded window
  Future<void> _closeExpandedWindow() async {
    print('📱 [EXPANDED] Closing unified expanded window...');
    setState(() => _showExpandedWindow = false);
    await _resizeOverlay(false);
    
    // Restore previous position after resizing back to compact
    try {
      await FlutterOverlayWindow.moveOverlay(OverlayPosition(_currentX, _currentY));
      print('📍 [EXPANDED] Restored position to ($_currentX, $_currentY)');
    } catch (e) {
      print('❌ [EXPANDED] Failed to restore position: $e');
    }
    
    await FlutterOverlayWindow.updateFlag(OverlayFlag.defaultFlag);
    print('📱 [EXPANDED] Expanded window closed!');
  }

  // Initialize Firebase and test connection
  Future<void> _initializeFirebase() async {
    try {
      print('🔵 [FIREBASE] Initializing Firebase in overlay...');
      await FirebaseService.initialize();
      
      if (FirebaseService.isAvailable) {
        print('✅ [FIREBASE] Firebase connected successfully!');
        print('🔗 [FIREBASE] Database URL: https://homecoming-74f73-default-rtdb.europe-west1.firebasedatabase.app');
        
        // Test logging to Firebase
        await FirebaseService.logAppUsage(
          action: 'overlay_opened',
          additionalData: {
            'timestamp': DateTime.now().toIso8601String(),
            'platform': Platform.operatingSystem,
          },
        );
        print('✅ [FIREBASE] Test log sent successfully');
        
        // Try to get usage stats
        final stats = await FirebaseService.getUsageStats();
        if (stats.isNotEmpty) {
          print('📊 [FIREBASE] Usage stats retrieved: ${stats['totalEvents']} events');
        }
      } else {
        print('⚠️ [FIREBASE] Firebase not available - working offline');
      }
    } catch (e) {
      print('❌ [FIREBASE] Initialization error: $e');
    }
  }

  /// Initialize proactive AI that initiates conversations
  Future<void> _initializeProactiveAI() async {
    try {
      await _proactive.initialize();
      
      // Set callback for when Kai wants to start a conversation
      _proactive.onProactiveMessage = (message, trigger) async {
        print('💬 [PROACTIVE] Kai initiated: "$message"');
        
        // Add as user message (what Kai is asking/saying)
        setState(() {
          _chatHistory.add(ChatMessage(
            isUser: false, // It's from Kai
            text: message,
            timestamp: DateTime.now(),
          ));
        });
        
        // Expand window to show the message
        if (!_showExpandedWindow) {
          setState(() {
            _showExpandedWindow = true;
            _expandedWindowInitialTab = 0; // Open to chat tab
          });
        }
        
        // Scroll to bottom
        Future.delayed(const Duration(milliseconds: 100), () {
          if (_chatScrollController.hasClients) {
            _chatScrollController.animateTo(
              _chatScrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        });
        
        // Play TTS for the proactive message
        await _playTTS(message);
      };
      
      print('✅ [PROACTIVE] AI initialized and ready');
    } catch (e) {
      print('❌ [PROACTIVE] Initialization error: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    
    // Initialize Firebase and test connection
    _initializeFirebase();
    
    // Precache animation frames to prevent glitchy first load
    _precacheAnimationFrames();
    
    // Start idle animation immediately
    _switchToAnimation('idle');
    
    // Initialize proactive AI
    _initializeProactiveAI();
    
    _player.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() {
          _playerState = state;
          // Clear test playing state when playback stops
          if (state == PlayerState.stopped || state == PlayerState.completed) {
            _isPlayingTest = false;
          }
        });
        // Update animation automatically when player state changes
        _updateAnimationState();
      }
    });
    
    // Start auto-movement after a delay (gives time for window to be created)
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) _startAutoMovement();
    });
  }

  @override
  void dispose() {
    _proactive.stop(); // Stop proactive monitoring
    _stopAutoMovement();
    _controller.dispose();
    _chatScrollController.dispose();
    _player.dispose();
    _beepPlayer.dispose();
    voiceService.dispose();
    _frameAnimController?.dispose(); // Dispose frame animation controller
    // Dispose all delta animation controllers
    for (final f in _floaters) {
      f.ctrl.dispose();
    }
    super.dispose();
  }

  // Spawn delta popup bubbles
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

  Future<String> _writeTempMp3(Uint8List bytes) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/kai_${DateTime.now().millisecondsSinceEpoch}.mp3');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }
  
  /// Start voice recording
  Future<void> _startVoiceRecording() async {
    print('🎤 [UI] Start voice recording requested');
    
    // Check permission first
    final hasPermission = await voiceService.hasPermission();
    print('🎤 [UI] Has permission: $hasPermission');
    
    if (!hasPermission) {
      setState(() {
        _error = 'Requesting microphone permission...';
      });
      
      // Request permission
      final granted = await voiceService.requestPermission();
      print('🎤 [UI] Permission granted: $granted');
      
      if (!granted) {
        setState(() {
          _error = 'Microphone permission denied.\n\nPlease enable manually:\n1. Open Settings\n2. Apps → Homecoming\n3. Permissions → Microphone → Allow';
          _isRecording = false;
        });
        _updateAnimationState(); // Return to idle
        return;
      }
      
      setState(() {
        _error = null;
      });
    }
    
    setState(() {
      _error = null;
      _isRecording = true;
    });
    _updateAnimationState(); // Switch to attention (listening) animation
    
    print('🎤 [UI] Starting recording...');
    final started = await voiceService.startRecording();
    print('🎤 [UI] Recording started: $started');
    
    if (!started) {
      setState(() {
        _error = 'Failed to start recording.\n\nTroubleshooting:\n1. Check Settings → Apps → Homecoming → Permissions\n2. Ensure Microphone is allowed\n3. Try restarting the app';
        _isRecording = false;
      });
      _updateAnimationState(); // Return to idle on error
    } else {
      print('✅ [UI] Voice recording started successfully');
    }
  }
  
  /// Stop voice recording and save for playback/sending
  Future<void> _stopVoiceRecording() async {
    if (!_isRecording) return;
    
    setState(() {
      _isRecording = false;
      _reply = null;
      _error = null;
    });
    _updateAnimationState(); // Return to idle animation
    
    try {
      // Stop recording
      final audioPath = await voiceService.stopRecording();
      if (audioPath == null) {
        throw Exception('Failed to save recording');
      }
      
      // Check file size and copy for debugging
      final file = File(audioPath);
      final fileSize = await file.length();
      print('📊 Audio file size: $fileSize bytes');
      
      // Copy to Downloads for debugging
      try {
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final downloadsDir = Directory('/storage/emulated/0/Download');
        final debugFile = File('${downloadsDir.path}/kai_debug_$timestamp.m4a');
        await file.copy(debugFile.path);
        print('🐛 Debug copy saved: ${debugFile.path}');
      } catch (e) {
        print('⚠️ Could not save debug copy: $e');
      }
      
      setState(() {
        _recordedAudioPath = audioPath;
      });
      
      print('✅ Recording saved: $audioPath');
      print('🎧 Auto-transcribing and sending to chat...');
      
      // Automatically transcribe and send to chat (for PTT on avatar)
      await _transcribeAndSend();
      
    } catch (e) {
      setState(() {
        _error = 'Voice recording failed: $e';
      });
      print('❌ Voice recording error: $e');
    }
  }
  
  /// Play back the recorded audio
  Future<void> _playRecording() async {
    if (_recordedAudioPath == null) return;
    
    try {
      if (_isPlayingRecording) {
        await _audioPlayer.stop();
        setState(() => _isPlayingRecording = false);
        print('⏹️ Stopped playback');
      } else {
        final success = await _audioPlayer.play(_recordedAudioPath!);
        if (success) {
          setState(() => _isPlayingRecording = true);
          print('▶️ Playing recording');
          
          // Auto-stop after playback completes (estimate ~5 seconds)
          Future.delayed(const Duration(seconds: 6), () {
            if (mounted && _isPlayingRecording) {
              setState(() => _isPlayingRecording = false);
            }
          });
        }
      }
    } catch (e) {
      print('❌ Playback error: $e');
      setState(() => _isPlayingRecording = false);
    }
  }
  
  /// Transcribe and send the recorded audio
  Future<void> _transcribeAndSend() async {
    if (_recordedAudioPath == null) return;
    
    setState(() {
      _reply = null;
      _error = null;
    });
    
    try {
      print('🎯 Transcribing audio...');
      
      // Transcribe audio
      final transcription = await voiceService.transcribeAudio(_recordedAudioPath!);
      if (transcription == null || transcription.isEmpty) {
        throw Exception('Failed to transcribe audio');
      }
      
      print('✅ Transcription: $transcription');
      
      // Clear the recorded audio path
      setState(() => _recordedAudioPath = null);
      
      // Set transcription as input and send
      _controller.text = transcription;
      print('📝 Set controller text to: "$transcription"');
      print('📤 Calling _send()...');
      await _send();
      print('✅ _send() completed');
      
    } catch (e) {
      setState(() {
        _error = 'Voice input failed: $e';
        _sending = false;
      });
      print('❌ Voice transcription error: $e');
    }
  }
  
  /// Cancel the recorded audio
  void _cancelRecording() {
    if (_recordedAudioPath != null) {
      // Delete the file
      try {
        final file = File(_recordedAudioPath!);
        if (file.existsSync()) {
          file.deleteSync();
          print('🗑️ Deleted recorded audio');
        }
      } catch (e) {
        print('⚠️ Failed to delete recording: $e');
      }
    }
    
    setState(() {
      _recordedAudioPath = null;
      _isPlayingRecording = false;
    });
  }
  
  // ============= TEST AUDIO FUNCTIONS =============
  /// TEST: Simple record/playback test - no transcription
  Future<void> _toggleTestRecording() async {
    if (_isTestRecording) {
      // Stop recording
      await _stopTestRecording();
    } else {
      // Start recording
      await _startTestRecording();
    }
  }
  
  Future<void> _startTestRecording() async {
    print('🧪 [TEST] Start test recording (using VoiceService)');
    
    setState(() {
      _isTestRecording = true;
      _testAudioPath = null;
      _error = null;
    });
    
    final started = await voiceService.startRecording();
    if (!started) {
      setState(() {
        _error = 'TEST: Failed to start recording - check service binding';
        _isTestRecording = false;
      });
    }
  }
  
  Future<void> _stopTestRecording() async {
    print('🧪 [TEST] Stop test recording');
    
    setState(() {
      _isTestRecording = false;
    });
    
    try {
      final audioPath = await voiceService.stopRecording();
      
      if (audioPath == null) {
        throw Exception('No audio path returned');
      }
      
      final file = File(audioPath);
      if (!await file.exists()) {
        throw Exception('Audio file not found at: $audioPath');
      }
      
      final fileSize = await file.length();
      print('🧪 [TEST] Recorded audio: $fileSize bytes at $audioPath');
      
      setState(() {
        _testAudioPath = audioPath;
        _error = 'TEST: Recorded $fileSize bytes';
      });
    } catch (e) {
      print('❌ [TEST] Failed to stop: $e');
      setState(() {
        _error = 'TEST: Failed to stop: $e';
      });
    }
  }
  
  Future<void> _playTestAudio() async {
    if (_testAudioPath == null) {
      print('🧪 [TEST] No test audio to play');
      return;
    }
    
    print('🧪 [TEST] Playing test audio: $_testAudioPath');
    
    setState(() {
      _isPlayingTest = true;
      _error = null;
    });
    
    try {
      // Stop if already playing
      if (_isPlayingTest) {
        await _audioPlayer.stop();
        setState(() => _isPlayingTest = false);
        print('🧪 [TEST] Stopped playback');
        return;
      }
      
      final success = await _audioPlayer.play(_testAudioPath!);
      if (success) {
        print('🧪 [TEST] Playback started');
        
        // Auto-stop after playback completes (estimate)
        Future.delayed(const Duration(seconds: 6), () {
          if (mounted && _isPlayingTest) {
            setState(() => _isPlayingTest = false);
          }
        });
      } else {
        setState(() {
          _isPlayingTest = false;
          _error = 'TEST: Failed to start playback';
        });
      }
    } catch (e) {
      print('🧪 [TEST] Playback error: $e');
      setState(() {
        _error = 'TEST: Playback failed: $e';
        _isPlayingTest = false;
      });
    }
  }
  
  void _deleteTestAudio() {
    if (_testAudioPath != null) {
      try {
        final file = File(_testAudioPath!);
        if (file.existsSync()) {
          file.deleteSync();
        }
      } catch (e) {
        print('🧪 [TEST] Failed to delete: $e');
      }
    }
    
    setState(() {
      _testAudioPath = null;
      _error = null;
    });
  }
  
  /// Auto-scroll chat to bottom
  void _scrollToBottom() {
    if (_chatScrollController.hasClients) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (_chatScrollController.hasClients) {
          _chatScrollController.animateTo(
            _chatScrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }
  
  /// Play beep sound when recording starts
  Future<void> _playRecordingStartBeep() async {
    try {
      await _beepPlayer.play(AssetSource('audio/record_start.wav'));
      print('🔊 BEEP: Recording started');
    } catch (e) {
      print('⚠️ Failed to play start beep: $e');
    }
  }
  
  /// Play beep sound when recording stops
  Future<void> _playRecordingStopBeep() async {
    try {
      await _beepPlayer.play(AssetSource('audio/record_stop.wav'));
      print('🔊 BEEP: Recording stopped');
    } catch (e) {
      print('⚠️ Failed to play stop beep: $e');
    }
  }
  
  /// Build a message bubble widget
  Widget _buildMessageBubble(ChatMessage message) {
    return Align(
      alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: message.isUser 
              ? Colors.blue.withOpacity(0.7) 
              : const Color(0xFF2A2119),
          borderRadius: BorderRadius.circular(18),
          border: message.isUser
              ? null
              : Border.all(color: const Color(0xFFFFE7B0).withOpacity(0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Memory chips - show if debugInfo has memory details OR if memoriesUsed is not empty
            if (!message.isUser && 
                ((message.debugInfo != null && message.debugInfo!['memory_query']?['memory_details'] != null) ||
                 message.memoriesUsed.isNotEmpty)) ...[
              MemoryChips(
                memoryDetails: (message.debugInfo?['memory_query']?['memory_details'] as List?)
                    ?.cast<Map<String, dynamic>>() ?? 
                    message.memoriesUsed.map((m) => {'text': m}).toList(),
              ),
            ],
            Text(
              message.text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
              ),
            ),
            if (message.audioPath != null) ...[
              const SizedBox(height: 8),
              InkWell(
                onTap: () async {
                  if (_playerState == PlayerState.playing) {
                    await _player.pause();
                  } else {
                    await _player.play(DeviceFileSource(message.audioPath!));
                  }
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _playerState == PlayerState.playing ? Icons.pause_circle : Icons.play_circle,
                      color: const Color(0xFFFFE7B0),
                      size: 20,
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      'Play voice',
                      style: TextStyle(
                        color: Color(0xFFFFE7B0),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            // DEBUG: Show debug button if debugInfo available
            if (!message.isUser && message.debugInfo != null) ...[
              const SizedBox(height: 8),
              DebugButton(
                debugInfo: message.debugInfo!,
                personaId: 'truekai',
              ),
            ],
          ],
        ),
      ),
    );
  }
  
  /// Send message with text (extracted from _send for reuse)
  Future<void> _sendMessage(String text) async {
    print('🟢 _sendMessage called with: "$text"');
    if (text.isEmpty) {
      print('⚠️ Text is empty, returning');
      return;
    }
    
    // Record user interaction for proactive AI
    _proactive.recordInteraction();
    
    // Add user message to chat history
    setState(() {
      _chatHistory.add(ChatMessage(text: text, isUser: true));
      _sending = true;
      _reply = null;
      _error = null;
      _ttsPath = null;
    });
    
    // Update animation to thinking state
    _updateAnimationState();
    
    // Clear the text field
    _controller.clear();
    
    // Auto-scroll to bottom
    _scrollToBottom();
    
    print('🟢 State set: sending=true');
    
    try {
      print('🟢 Calling aiService.sendMessage...');
      final resp = await aiService.sendMessage(
        text: text,
        personaId: 'truekai',
        model: 'gpt-4o',
        adaptUser: true,
        ctxTurns: 5,
      );
      
      final replyText = resp.reply.isEmpty ? "(no reply)" : resp.reply;
      
      // Capture debug info from AI response
      _debugInfo = resp.debugInfo;
      print('🔍 [DEBUG] debugInfo captured: ${_debugInfo != null ? "YES" : "NO"}');
      if (_debugInfo != null) {
        print('🔍 [DEBUG] debugInfo keys: ${_debugInfo!.keys.join(", ")}');
      }
      
      // Extract personality/mood deltas
      print('🧠 Personality deltas: ${resp.personalityDelta}');
      print('🧠 Mood deltas: ${resp.moodDelta}');
      print('🧠 Actual deltas: ${resp.actualDeltas}');
      
      // Spawn delta popup bubbles
      if (resp.actualDeltas.isNotEmpty) {
        _spawnDeltas(resp.actualDeltas);
      }
      
      // Handle TTS
      String? audioPath;
      if (resp.ttsBase64 != null) {
        final mp3Path = await _writeTempMp3(base64Decode(resp.ttsBase64!));
        await _player.play(DeviceFileSource(mp3Path));
        audioPath = mp3Path;
      }
      
      // Add Kai's reply to chat history
      setState(() {
        _chatHistory.add(ChatMessage(
          text: replyText,
          isUser: false,
          audioPath: audioPath,
          memoriesUsed: resp.memoriesUsed, // NEW: Include memory info
          debugInfo: _debugInfo, // DEBUG: Include debug data
        ));
        _reply = replyText;
        _ttsPath = audioPath;
      });
      
      // DEBUG: Log what we're adding
      print('💬 [CHAT] Added message with:');
      print('   - audioPath: ${audioPath != null ? "YES" : "NO"}');
      print('   - memoriesUsed: ${resp.memoriesUsed.length} memories');
      print('   - debugInfo: ${_debugInfo != null ? "YES (${_debugInfo!.keys.length} keys)" : "NO"}');
      
      // Show curiosity indicator if question triggered
      if (resp.curiosityQuestion != null && mounted) {
        _showCuriosityIndicator(resp.curiosityQuestion!);
      }
      
      // Auto-scroll to bottom
      _scrollToBottom();
      
      // Note: Conversation already saved to Firebase in ai_service.sendMessage()
      
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _sending = false);
      // Update animation back to idle
      _updateAnimationState();
    }
  }
  
  /// Original send method (now calls _sendMessage)
  Future<void> _send() async {
    print('🔵 _send() called');
    final text = _controller.text.trim();
    print('🔵 Text from controller: "$text"');
    if (text.isEmpty || _sending) {
      print('⚠️ Returning early - empty: ${text.isEmpty}, sending: $_sending');
      return;
    }
    print('🔵 Calling _sendMessage("$text")');
    await _sendMessage(text);
    print('🔵 _sendMessage completed');
  }
  
  /// Show curiosity indicator when Kai has a question
  void _showCuriosityIndicator(CuriosityQuestion question) {
    print('🤔 [CURIOSITY] Showing indicator: ${question.question}');
    print('🤔 [CURIOSITY] Priority: ${question.priority}, Category: ${question.category}');
    
    if (!mounted) return;
    
    // Show floating question mark indicator
    CuriosityOverlay.show(
      context: context,
      question: question,
      alignment: Alignment.topRight,
      padding: const EdgeInsets.only(top: 80, right: 20),
      onTap: () {
        print('🤔 [CURIOSITY] User tapped indicator - adding question to chat');
        // Add the curiosity question to chat as if user asked it
        setState(() {
          _chatHistory.add(ChatMessage(
            text: "💭 ${question.question}",
            isUser: false, // From Kai (curiosity prompt)
          ));
        });
        _scrollToBottom();
      },
    );
  }
  
  /// Helper to build circular menu buttons around Kai
  Widget _buildCircularButton({
    required double angle,
    required double radius,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    // Convert angle to radians
    final radians = angle * pi / 180;
    
    // Calculate position relative to avatar's FIXED center position in the 200x200 window
    // Avatar is fixed at (50, 40), so center is at (50 + 50, 40 + 60) = (100, 100)
    const avatarCenterX = 100.0;
    const avatarCenterY = 100.0;
    
    final x = avatarCenterX + radius * cos(radians);
    final y = avatarCenterY + radius * sin(radians);
    
    return Positioned(
      left: x - 26, // 26 = half of button size (52/2)
      top: y - 26,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 300),
        curve: Curves.elasticOut,
        builder: (context, value, child) {
          return Transform.scale(
            scale: value,
            child: child,
          );
        },
        child: GestureDetector(
          behavior: HitTestBehavior.deferToChild, // Only respond to actual pixels
          onTap: onTap,
          child: ClipOval(
            child: Container(
              width: 52, // Original button size
              height: 52,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFFFFE7B0),
                  width: 2,
                ),
                // Removed boxShadow - it was expanding hit area!
              ),
              child: Icon(
                icon,
                color: const Color(0xFFFFE7B0),
                size: 24, // Original icon size
              ),
            ),
          ),
        ),
      ),
    );
  }
  
  /// Build animation test button
  /// Toggle between available voices (simple toggle, no modal)
  Future<void> _toggleVoice() async {
    final currentId = await AIConfig.getSelectedVoiceId();
    
    // Get list of voice IDs
    final voiceIds = AIConfig.availableVoices.values.map((v) => v['id']!).toList();
    
    // Find current index and get next voice
    final currentIndex = voiceIds.indexOf(currentId);
    final nextIndex = (currentIndex + 1) % voiceIds.length;
    final nextVoiceId = voiceIds[nextIndex];
    
    // Set new voice
    await AIConfig.setSelectedVoiceId(nextVoiceId);
    
    // Get voice name for feedback
    final voiceName = AIConfig.availableVoices.values
        .firstWhere((v) => v['id'] == nextVoiceId)['name']!;
    
    // Show brief feedback
    if (mounted) {
      FlutterOverlayWindow.showOverlay(
        height: 180,
        width: 180,
        alignment: OverlayAlignment.center,
      );
      
      // You could add a toast/snackbar here if desired
      print('🎤 Voice changed to: $voiceName');
    }
    
    setState(() {}); // Refresh UI
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
          // Debug: Window border indicator (only in avatar mode)
          if (!_expanded)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: const Color(0xFFFFE7B0).withOpacity(0.15), // Faint golden border
                    width: 1,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          
          // Floating Kai (draggable when minimized) - NO CONTAINER, direct positioning
          if (!_expanded) ...[
            // Kai avatar - FIXED at center of 400x400 window
            Positioned(
              left: 50.0, // Fixed center: (200/2 - 50)
              top: 40.0,  // Fixed center: (200/2 - 60)
              child: GestureDetector(
                behavior: HitTestBehavior.deferToChild, // Only respond to actual pixels
                onTap: () {
                  setState(() {
                    _showMenu = !_showMenu;
                    if (_showMenu) {
                      _stopAutoMovement(); // Stop when menu opens
                    } else {
                      // Resume after menu closes
                      Future.delayed(const Duration(seconds: 2), () {
                        if (mounted && !_showMenu && !_expanded) {
                          _startAutoMovement();
                        }
                      });
                    }
                  });
                },
                onLongPressStart: (_) async {
                  // Start voice recording when holding Kai avatar
                  await _playRecordingStartBeep();
                  await _startVoiceRecording();
                },
                onLongPressEnd: (_) async {
                  // Play stop beep IMMEDIATELY when releasing (before transcription)
                  await _playRecordingStopBeep();
                  // Stop voice recording when releasing Kai avatar
                  await _stopVoiceRecording();
                },
                // Drag handling removed - Java handles it natively now (enableDrag=true)
                // This gives buttery smooth dragging without Flutter->Java bridge overhead
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(50),
                  child: Container(
                    width: 100, // Original avatar size
                    height: 120,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(50),
                      // Removed boxShadow - it was expanding hit area!
                    ),
                    child: _buildAvatarWidget(), // Dynamic frame-based animation!
                  ),
                ),
              ),
            ),
                  
                  // Circular menu buttons
                  if (_showMenu) ...[
                    // Chat button (top)
                    _buildCircularButton(
                      angle: -90,
                      radius: 68, // Wrapped tightly around avatar
                      icon: Icons.chat_bubble,
                      onTap: () {
                        setState(() => _showMenu = false);
                        _openExpandedWindow(0); // Open with Chat tab (index 0)
                      },
                    ),
                    
                    // Voice/TTS button (top-right)
                    _buildCircularButton(
                      angle: -45,
                      radius: 68, // Wrapped tightly around avatar
                      icon: _playerState == PlayerState.playing ? Icons.pause : Icons.play_arrow,
                      onTap: () async {
                        if (_ttsPath != null) {
                          if (_playerState == PlayerState.playing) {
                            await _player.pause();
                          } else {
                            await _player.play(DeviceFileSource(_ttsPath!));
                          }
                        }
                      },
                    ),
                    
                    // Personality button (right)
                    _buildCircularButton(
                      angle: 0,
                      radius: 68, // Wrapped tightly around avatar
                      icon: Icons.psychology,
                      onTap: () {
                        setState(() => _showMenu = false);
                        _openExpandedWindow(1); // Open with Personality tab (index 1)
                      },
                    ),
                    
                    // Close button (bottom)
                    _buildCircularButton(
                      angle: 90,
                      radius: 68, // Wrapped tightly around avatar
                      icon: Icons.close,
                      onTap: () async {
                        await FlutterOverlayWindow.closeOverlay();
                      },
                    ),
                    
                    // Analytics/Usage Stats button (bottom-left)
                    _buildCircularButton(
                      angle: 135,
                      radius: 68, // Wrapped tightly around avatar
                      icon: Icons.analytics,
                      onTap: () {
                        setState(() => _showMenu = false);
                        _openExpandedWindow(2); // Open with Analytics tab (index 2)
                      },
                    ),
                    
                    // Minimize button (left)
                    _buildCircularButton(
                      angle: 180,
                      radius: 68, // Wrapped tightly around avatar
                      icon: Icons.minimize,
                      onTap: () {
                        setState(() => _showMenu = false);
                      },
                    ),
                    
                    // Voice toggle button (top-left) - cycles between voices
                    _buildCircularButton(
                      angle: -135,
                      radius: 68, // Wrapped tightly around avatar
                      icon: Icons.record_voice_over,
                      onTap: () async {
                        setState(() => _showMenu = false);
                        await _toggleVoice();
                      },
                    ),
                  ],
                  
                  // Delta popup floaters (personality/mood changes)
                  ..._floaters.map((f) {
                    final anim = CurvedAnimation(
                        parent: f.ctrl, curve: Curves.easeOutCubic);
                    // Position relative to avatar center (100, 100)
                    const avatarCenterX = 50.0 + 50.0; // left + width/2
                    const avatarCenterY = 40.0 + 60.0; // top + height/2
                    return Positioned(
                      left: avatarCenterX + cos(f.angle) * 70 * (1 + anim.value * 0.3),
                      top: avatarCenterY + sin(f.angle) * 70 * (1 + anim.value * 0.3) - anim.value * 20,
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
                  
                  // Animation is now fully automatic based on app state!
          ],
        
        // NEW: Unified Expanded Window with Tabs (Chat, Personality, Analytics)
        if (_showExpandedWindow)
          Positioned.fill(
            child: ExpandedWindow(
              personaId: 'truekai',
              onClose: _closeExpandedWindow,
              onSendMessage: (text) async {
                _controller.text = text;
                await _sendMessage(text);
              },
              messages: _chatHistory.map((msg) => {
                'role': msg.isUser ? 'user' : 'assistant',
                'content': msg.text,
                'timestamp': msg.timestamp,
                'memoriesUsed': msg.memoriesUsed,
                'audioPath': msg.audioPath, // ADD: Pass audio path for replay button
                'debugInfo': msg.debugInfo, // ADD: Pass debug info for debug button
              }).toList(),
              isLoading: _sending,
              scrollController: _chatScrollController,
              initialTab: _expandedWindowInitialTab, // Pass the initial tab
            ),
          ),
        
        // Expanded chat UI - Fills expanded overlay window (90% x 85% of screen)
        if (_expanded && !_showExpandedWindow)
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            bottom: 0,
            child: GestureDetector(
              onTap: () => _closeChat(),
              child: Container(
                color: Colors.transparent, // Fully transparent background
                child: GestureDetector(
                  onTap: () {}, // Prevents closing when tapping chat area
                  child: Material(
                    color: Colors.transparent,
                    child: Stack(
                      children: [
                        // Main content - full screen
                        Column(
                          children: [
                            // DRAG HANDLE - At the very top (NEW!)
                            GestureDetector(
                              onPanUpdate: (details) async {
                                // Enable dragging temporarily
                                await FlutterOverlayWindow.resizeOverlay(-1, -1, true);
                              },
                              onPanEnd: (details) async {
                                // Disable dragging after drag (for scrolling)
                                await FlutterOverlayWindow.resizeOverlay(-1, -1, false);
                              },
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.only(top: 40, bottom: 12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0D0A07).withOpacity(0.95),
                                  border: Border(
                                    bottom: BorderSide(
                                      color: const Color(0xFFFFE7B0).withOpacity(0.2),
                                      width: 1,
                                    ),
                                  ),
                                ),
                                child: Center(
                                  child: Column(
                                    children: [
                                      Container(
                                        width: 40,
                                        height: 4,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFFE7B0).withOpacity(0.5),
                                          borderRadius: BorderRadius.circular(2),
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        'Drag to move window',
                                        style: TextStyle(
                                          color: const Color(0xFFFFE7B0).withOpacity(0.6),
                                          fontSize: 10,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            
                            // Input area at TOP - semi-transparent background
                            Container(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), // Increased bottom padding for keyboard
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.5), // Semi-transparent background
                              ),
                              child: SafeArea(
                                bottom: true, // Now respect bottom inset (keyboard)
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: _controller,
                                        autofocus: false,
                                        enableInteractiveSelection: true,
                                        readOnly: false,
                                        style: const TextStyle(color: Colors.white),
                                        decoration: InputDecoration(
                                          hintText: 'Message Kai...',
                                          hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                                          filled: true,
                                          fillColor: const Color(0xFF2A2119),
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(25),
                                            borderSide: BorderSide.none,
                                          ),
                                        ),
                                        onTap: () async {
                                          print('📝 [KEYBOARD] TextField tapped');
                                          await FlutterOverlayWindow.updateFlag(OverlayFlag.focusPointer);
                                        },
                                        onEditingComplete: () {
                                          print('📝 [KEYBOARD] Editing complete');
                                        },
                                        onSubmitted: (_) => _send(),
                                      ),
                                    ),
                                const SizedBox(width: 8),
                                // Show playback controls if audio is recorded
                                if (_recordedAudioPath != null) ...[
                                  // Play button
                                  FloatingActionButton(
                                    mini: true,
                                    backgroundColor: _isPlayingRecording
                                        ? Colors.orange.withOpacity(0.8)
                                        : const Color(0xFFFFE7B0).withOpacity(0.8),
                                    onPressed: _playRecording,
                                    child: Icon(
                                      _isPlayingRecording ? Icons.stop : Icons.play_arrow,
                                      color: const Color(0xFF0D0A07),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  // Send (transcribe) button
                                  FloatingActionButton(
                                    mini: true,
                                    backgroundColor: Colors.green.withOpacity(0.8),
                                    onPressed: _sending ? null : _transcribeAndSend,
                                    child: _sending
                                        ? const SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                        : const Icon(Icons.send, color: Colors.white),
                                  ),
                                  const SizedBox(width: 8),
                                  // Cancel button
                                  FloatingActionButton(
                                    mini: true,
                                    backgroundColor: Colors.red.withOpacity(0.8),
                                    onPressed: _cancelRecording,
                                    child: const Icon(Icons.cancel, color: Colors.white),
                                  ),
                                ] else ...[
                                  // Microphone button for voice input in chat
                                  FloatingActionButton(
                                    mini: true,
                                    backgroundColor: _isRecording 
                                        ? Colors.red.withOpacity(0.8)
                                        : const Color(0xFFFFE7B0).withOpacity(0.8),
                                    onPressed: _sending ? null : () async {
                                      if (_isRecording) {
                                        await _stopVoiceRecording();
                                      } else {
                                        await _startVoiceRecording();
                                      }
                                    },
                                    child: Icon(
                                      _isRecording ? Icons.stop : Icons.mic,
                                      color: const Color(0xFF0D0A07),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  // Send button
                                  FloatingActionButton(
                                    mini: true,
                                    backgroundColor: const Color(0xFFFFE7B0),
                                    onPressed: _sending ? null : _send,
                                    child: _sending
                                        ? const SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Color(0xFF0D0A07),
                                            ),
                                          )
                                        : const Icon(Icons.send, color: Color(0xFF0D0A07)),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                            
                            // Messages area - FULL SCREEN scrollable below input
                            Expanded(
                              child: _chatHistory.isEmpty
                                  ? Center(
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.chat_bubble_outline,
                                            size: 64,
                                            color: const Color(0xFFFFE7B0).withOpacity(0.3),
                                          ),
                                          const SizedBox(height: 16),
                                          Text(
                                            'Start a conversation with Kai!',
                                            style: TextStyle(
                                              color: Colors.white.withOpacity(0.5),
                                              fontSize: 16,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            'Hold the avatar to record voice',
                                            style: TextStyle(
                                              color: Colors.white.withOpacity(0.3),
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                  : ListView.builder(
                                      controller: _chatScrollController,
                                      padding: const EdgeInsets.all(16),
                                      itemCount: _chatHistory.length,
                                      itemBuilder: (context, index) {
                                        final message = _chatHistory[index];
                                        return _buildMessageBubble(message);
                                      },
                                    ),
                            ),
                        ],
                      ),
                      
                      // Floating close button - top right corner
                      Positioned(
                        top: 40,
                        right: 16,
                        child: SafeArea(
                          child: FloatingActionButton(
                            mini: true,
                            backgroundColor: Colors.black.withOpacity(0.5),
                            onPressed: () => _closeChat(),
                            child: const Icon(Icons.close, color: Color(0xFFFFE7B0), size: 20),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          ),
        
        // Personality Screen - Fills expanded overlay window (90% x 85% of screen)
        if (_showPersonality && !_showExpandedWindow)
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            bottom: 0,
            child: Material(
              color: Colors.white,
              child: Stack(
                children: [
                  Column(
                    children: [
                      // DRAG HANDLE (NEW!)
                      GestureDetector(
                        onPanUpdate: (details) async {
                          await FlutterOverlayWindow.resizeOverlay(-1, -1, true);
                        },
                        onPanEnd: (details) async {
                          await FlutterOverlayWindow.resizeOverlay(-1, -1, false);
                        },
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.only(top: 40, bottom: 12),
                          decoration: BoxDecoration(
                            color: Colors.purple.withOpacity(0.1),
                            border: Border(
                              bottom: BorderSide(
                                color: Colors.purple.withOpacity(0.3),
                                width: 1,
                              ),
                            ),
                          ),
                          child: Center(
                            child: Column(
                              children: [
                                Container(
                                  width: 40,
                                  height: 4,
                                  decoration: BoxDecoration(
                                    color: Colors.purple.withOpacity(0.5),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Drag to move window',
                                  style: TextStyle(
                                    color: Colors.purple.withOpacity(0.6),
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      // Personality screen content
                      const Expanded(child: PersonalityScreen(personaId: 'truekai')),
                    ],
                  ),
                  
                  // Floating close button
                  Positioned(
                    top: 40,
                    right: 16,
                    child: SafeArea(
                      child: FloatingActionButton(
                        mini: true,
                        backgroundColor: Colors.purple.withOpacity(0.9),
                        onPressed: () => _closePersonalityScreen(),
                        child: const Icon(Icons.close, color: Colors.white, size: 20),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        
        // Analytics/Usage Stats Screen - Fills expanded overlay window (90% x 85% of screen)
        // Analytics/Usage Stats Screen - Fills expanded overlay window (90% x 85% of screen)
        if (_showAnalytics && !_showExpandedWindow)
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            bottom: 0,
            child: Material(
              color: Colors.white,
              child: Stack(
                children: [
                  Column(
                    children: [
                      // DRAG HANDLE (NEW!)
                      GestureDetector(
                        onPanUpdate: (details) async {
                          await FlutterOverlayWindow.resizeOverlay(-1, -1, true);
                        },
                        onPanEnd: (details) async {
                          await FlutterOverlayWindow.resizeOverlay(-1, -1, false);
                        },
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.only(top: 40, bottom: 12),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.1),
                            border: Border(
                              bottom: BorderSide(
                                color: Colors.green.withOpacity(0.3),
                                width: 1,
                              ),
                            ),
                          ),
                          child: Center(
                            child: Column(
                              children: [
                                Container(
                                  width: 40,
                                  height: 4,
                                  decoration: BoxDecoration(
                                    color: Colors.green.withOpacity(0.5),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Drag to move window',
                                  style: TextStyle(
                                    color: Colors.green.withOpacity(0.6),
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      // Usage stats screen content
                      const Expanded(child: UsageStatsScreen()),
                    ],
                  ),
                  
                  // Floating close button
                  Positioned(
                    top: 40,
                    right: 16,
                    child: SafeArea(
                      child: FloatingActionButton(
                        mini: true,
                        backgroundColor: Colors.green.withOpacity(0.9),
                        onPressed: () => _closeUsageStatsScreen(),
                        child: const Icon(Icons.close, color: Colors.white, size: 20),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
    );
  }
}
