// main_overlay.dart
// True system overlay using flutter_overlay_window - floats above ALL apps like Shimeji!

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';

import 'services/ai_service.dart';
import 'services/voice_service.dart';
import 'services/secure_storage_service.dart';
import 'api_key_setup_screen.dart';
import 'package:permission_handler/permission_handler.dart';

/// Kai avatar asset
const String kAvatarIdleGif = 'assets/avatar/images/mage.png';

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
                  child: Image.asset(kAvatarIdleGif, fit: BoxFit.cover),
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

// ============= OVERLAY WIDGET =============
// This is the actual floating widget that appears over other apps
class OverlayWidget extends StatefulWidget {
  const OverlayWidget({super.key});

  @override
  State<OverlayWidget> createState() => _OverlayWidgetState();
}

class _OverlayWidgetState extends State<OverlayWidget> with SingleTickerProviderStateMixin {
  bool _expanded = false;
  bool _showMenu = false; // New: controls circular menu visibility
  final _controller = TextEditingController();
  final _player = AudioPlayer();
  
  bool _sending = false;
  String? _reply;
  String? _error;
  String? _ttsPath;
  PlayerState? _playerState;
  
  // Voice recording - TODO: Re-enable after fixing record package
  // final _voiceService = VoiceService();
  bool _isRecording = false;
  
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
      // Chat expanded: make window taller for chat (300x600)
      await FlutterOverlayWindow.resizeOverlay(300, 600, true);
    } else {
      // Menu/avatar only: compact square window (200x200)
      await FlutterOverlayWindow.resizeOverlay(200, 200, true);
    }
  }
  
  // Helper to close chat and reset flags
  Future<void> _closeChat() async {
    setState(() => _expanded = false);
    await _resizeOverlay(false);
    // Reset flag to defaultFlag when closing chat (no keyboard needed)
    await FlutterOverlayWindow.updateFlag(OverlayFlag.defaultFlag);
  }

  @override
  void initState() {
    super.initState();
    _player.onPlayerStateChanged.listen((state) {
      if (mounted) setState(() => _playerState = state);
    });
    
    // Start auto-movement after a delay (gives time for window to be created)
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) _startAutoMovement();
    });
  }

  @override
  void dispose() {
    _stopAutoMovement();
    _controller.dispose();
    _player.dispose();
    voiceService.dispose();
    super.dispose();
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
    
    print('🎤 [UI] Starting recording...');
    final started = await voiceService.startRecording();
    print('🎤 [UI] Recording started: $started');
    
    if (!started) {
      setState(() {
        _error = 'Failed to start recording.\n\nTroubleshooting:\n1. Check Settings → Apps → Homecoming → Permissions\n2. Ensure Microphone is allowed\n3. Try restarting the app';
        _isRecording = false;
      });
    } else {
      print('✅ [UI] Voice recording started successfully');
    }
  }
  
  /// Stop voice recording and transcribe
  Future<void> _stopVoiceRecording() async {
    if (!_isRecording) return;
    
    setState(() {
      _isRecording = false;
      _sending = true;
      _reply = null;
      _error = null;
    });
    
    try {
      // Stop recording
      final audioPath = await voiceService.stopRecording();
      if (audioPath == null) {
        throw Exception('Failed to save recording');
      }
      
      print('🎯 Transcribing audio...');
      
      // Transcribe audio
      final transcription = await voiceService.transcribeAudio(audioPath);
      if (transcription == null || transcription.isEmpty) {
        throw Exception('Failed to transcribe audio');
      }
      
      print('✅ Transcription: $transcription');
      
      // Set transcription as input and send
      _controller.text = transcription;
      await _send();
      
    } catch (e) {
      setState(() {
        _error = 'Voice input failed: $e';
        _sending = false;
      });
      print('❌ Voice recording error: $e');
    }
  }
  
  /// Send message with text (extracted from _send for reuse)
  Future<void> _sendMessage(String text) async {
    if (text.isEmpty) return;
    
    setState(() {
      _sending = true;
      _reply = null;
      _error = null;
      _ttsPath = null;
    });
    
    try {
      final resp = await aiService.sendMessage(
        text: text,
        personaId: 'truekai',
        model: 'gpt-4o',
        adaptUser: true,
        ctxTurns: 5,
      );
      
      setState(() => _reply = resp.reply.isEmpty ? "(no reply)" : resp.reply);
      
      // Handle TTS
      if (resp.ttsBase64 != null) {
        final mp3Path = await _writeTempMp3(base64Decode(resp.ttsBase64!));
        await _player.play(DeviceFileSource(mp3Path));
        setState(() => _ttsPath = mp3Path);
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _sending = false);
    }
  }
  
  /// Original send method (now calls _sendMessage)
  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    await _sendMessage(text);
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
                onLongPress: () async {
                  // Close overlay on long press
                  await FlutterOverlayWindow.closeOverlay();
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
                    child: Image.asset(
                      kAvatarIdleGif,
                      fit: BoxFit.contain,
                    ),
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
                        setState(() {
                          _showMenu = false;
                          _expanded = true;
                        });
                        _resizeOverlay(true); // Resize to chat dimensions
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
                    
                    // Settings button (right)
                    _buildCircularButton(
                      angle: 0,
                      radius: 68, // Wrapped tightly around avatar
                      icon: Icons.settings,
                      onTap: () {
                        setState(() => _showMenu = false);
                        // TODO: Open settings
                      },
                    ),
                    
                    // Microphone button (bottom-right)
                    _buildCircularButton(
                      angle: 45,
                      radius: 68, // Wrapped tightly around avatar
                      icon: _isRecording ? Icons.mic_off : Icons.mic,
                      onTap: () async {
                        setState(() => _showMenu = false);
                        if (_isRecording) {
                          await _stopVoiceRecording();
                        } else {
                          await _startVoiceRecording();
                        }
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
                    
                    // Info button (bottom-left)
                    _buildCircularButton(
                      angle: 135,
                      radius: 68, // Wrapped tightly around avatar
                      icon: Icons.info_outline,
                      onTap: () {
                        setState(() => _showMenu = false);
                        // TODO: Show info
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
                    
                    // Favorite/bookmark button (top-left)
                    _buildCircularButton(
                      angle: -135,
                      radius: 68, // Wrapped tightly around avatar
                      icon: Icons.favorite_border,
                      onTap: () {
                        setState(() => _showMenu = false);
                        // TODO: Toggle favorite
                      },
                    ),
                  ],
          ],
        
        // Expanded chat UI - FIXED to screen edges, unmovable
        if (_expanded)
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            bottom: 0,
            child: GestureDetector(
              onTap: () => _closeChat(),
              child: Container(
                color: Colors.black.withOpacity(0.8),
                child: GestureDetector(
                  onTap: () {}, // Prevents closing when tapping chat area
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      margin: EdgeInsets.zero, // NO margin - goes to screen edges
                      decoration: BoxDecoration(
                        color: const Color(0xFF0D0A07),
                        border: Border.all(color: const Color(0xFFFFE7B0), width: 2),
                      ),
                        child: Column(
                        children: [
                          // Header
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(color: const Color(0xFFFFE7B0).withOpacity(0.3)),
                              ),
                            ),
                              child: Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(color: const Color(0xFFFFE7B0), width: 2),
                                  ),
                                  child: ClipOval(
                                    child: Image.asset(kAvatarIdleGif, fit: BoxFit.cover),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Expanded(
                                  child: Text(
                                    'Chat with Kai',
                                    style: TextStyle(
                                      color: Color(0xFFFFE7B0),
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.close, color: Colors.white),
                                  onPressed: () => _closeChat(),
                                ),
                              ],
                            ),
                          ),
                          
                          // Messages area
                          Expanded(
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                children: [
                                  if (_reply != null)
                                    Container(
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF2A2119),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(_reply!, style: const TextStyle(color: Colors.white)),
                                          if (_ttsPath != null) ...[
                                            const SizedBox(height: 12),
                                            ElevatedButton.icon(
                                              onPressed: () async {
                                                if (_playerState == PlayerState.playing) {
                                                  await _player.pause();
                                                } else {
                                                  await _player.play(DeviceFileSource(_ttsPath!));
                                                }
                                              },
                                              icon: Icon(_playerState == PlayerState.playing ? Icons.pause : Icons.play_arrow),
                                              label: const Text('Voice'),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: const Color(0xFFFFE7B0),
                                                foregroundColor: const Color(0xFF0D0A07),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  if (_error != null)
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: Colors.red.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          
                          // Input area
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              border: Border(
                                top: BorderSide(color: const Color(0xFFFFE7B0).withOpacity(0.3)),
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Focus(
                                    onFocusChange: (hasFocus) async {
                                      // Update flag to allow keyboard when TextField is focused
                                      if (hasFocus) {
                                        await FlutterOverlayWindow.updateFlag(OverlayFlag.focusPointer);
                                      } else {
                                        await FlutterOverlayWindow.updateFlag(OverlayFlag.defaultFlag);
                                      }
                                    },
                                    child: TextField(
                                      controller: _controller,
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
                                      onSubmitted: (_) => _send(),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
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
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
    );
  }
}
