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

/// Kai avatar asset
const String kAvatarIdleGif = 'assets/avatar/images/mage.png';

/// Global AI service instance
final aiService = AIService();

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
  
  // Check if we have overlay permission
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
    enableDrag: false, // Disable Java's drag handling - we'll handle it in Flutter with moveOverlay
    overlayTitle: "Kai",
    overlayContent: "Tap to chat with Kai!",
    flag: OverlayFlag.focusPointer, // FLAG_NOT_TOUCH_MODAL - enables click-through on transparent areas!
    visibility: NotificationVisibility.visibilityPublic,
    positionGravity: PositionGravity.none,
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
  
  // Window position on screen (in dp)
  double _windowX = 0.0;
  double _windowY = 0.0;
  bool _positioned = false;
  
  // Auto-movement variables - now moves the window, not the avatar
  Timer? _moveTimer;
  bool _isAutoMoving = false;
  double _targetX = 0.0;
  double _targetY = 0.0;
  final Random _random = Random();

  // Helper to ensure window stays within screen bounds
  void _clampWindowPosition(double screenWidth, double screenHeight) {
    const windowSize = 200.0; // Our overlay window is 200x200
    
    // Keep window fully on screen
    _windowX = _windowX.clamp(0.0, screenWidth - windowSize);
    _windowY = _windowY.clamp(0.0, screenHeight - windowSize);
  }
  
  // Start auto-movement - moves the entire window
  void _startAutoMovement() {
    if (_isAutoMoving || _expanded || _showMenu) return;
    
    print('🚀 Starting auto-movement');
    _isAutoMoving = true;
    _moveTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (_expanded || _showMenu) {
        timer.cancel();
        _isAutoMoving = false;
        return;
      }
      
      if (!mounted) {
        timer.cancel();
        return;
      }
      
      final screenWidth = MediaQuery.of(context).size.width;
      final screenHeight = MediaQuery.of(context).size.height;
      
      // Initialize window position if needed - center on screen
      if (!_positioned) {
        const windowSize = 200.0;
        _windowX = (screenWidth - windowSize) / 2;
        _windowY = (screenHeight - windowSize) / 2;
        _positioned = true;
        
        // Don't move window here - it's already centered by Java side on creation
        // We just need to track its position in our variables
        
        // Set first random target - anywhere on screen within bounds
        _targetX = _random.nextDouble() * (screenWidth - windowSize);
        _targetY = _random.nextDouble() * (screenHeight - windowSize);
      }
      
      // Move window towards target
      const moveSpeed = 2.0;
      final dx = _targetX - _windowX;
      final dy = _targetY - _windowY;
      final distance = sqrt(dx * dx + dy * dy);
      
      if (distance < moveSpeed) {
        // Reached target, pick new one anywhere on screen
        const windowSize = 200.0;
        _targetX = _random.nextDouble() * (screenWidth - windowSize);
        _targetY = _random.nextDouble() * (screenHeight - windowSize);
      } else {
        // Move window towards target
        setState(() {
          _windowX += (dx / distance) * moveSpeed;
          _windowY += (dy / distance) * moveSpeed;
          _clampWindowPosition(screenWidth, screenHeight);
        });
        
        print('🚀 Auto-moving window to ($_windowX, $_windowY)');
        // Actually move the overlay window on screen
        FlutterOverlayWindow.moveOverlay(OverlayPosition(_windowX, _windowY));
      }
    });
  }
  
  // Stop auto-movement
  void _stopAutoMovement() {
    _moveTimer?.cancel();
    _moveTimer = null;
    _isAutoMoving = false;
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

  @override
  void initState() {
    super.initState();
    _player.onPlayerStateChanged.listen((state) {
      if (mounted) setState(() => _playerState = state);
    });
    
    // Initialize window position by getting actual position from platform
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!_positioned && mounted) {
        try {
          // Get the ACTUAL current window position from Java
          final currentPos = await FlutterOverlayWindow.getOverlayPosition();
          if (mounted) {
            _windowX = currentPos.x;
            _windowY = currentPos.y;
            _positioned = true;
            print('🎯 Got actual window position from platform: ($_windowX, $_windowY)');
          }
        } catch (e) {
          print('❌ Error getting position: $e');
          // Fallback if position not available
          final screenWidth = 1080.0;
          final screenHeight = 2340.0;
          const windowSize = 200.0;
          _windowX = screenWidth - windowSize - 20.0;
          _windowY = screenHeight - windowSize - 20.0;
          _positioned = true;
          print('🎯 Using fallback position: ($_windowX, $_windowY)');
        }
      }
    });
    
    // Start auto-movement after a short delay
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) _startAutoMovement();
    });
  }

  @override
  void dispose() {
    _stopAutoMovement();
    _controller.dispose();
    _player.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    
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

  Future<String> _writeTempMp3(Uint8List bytes) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/kai_${DateTime.now().millisecondsSinceEpoch}.mp3');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
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
    // Get screen size for proper positioning
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    
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
                onPanStart: (details) {
                  print('🎯 Pan started at ${details.localPosition}');
                  // Stop auto-movement when user starts dragging
                  _stopAutoMovement();
                  // Just log current position - it was already initialized in initState
                  print('🎯 Window position at drag start: (${_windowX}, ${_windowY}), _positioned: $_positioned');
                },
                onPanUpdate: (details) {
                  // Use hardcoded screen size since MediaQuery returns overlay size
                  const screenWidth = 1080.0;
                  const screenHeight = 2340.0;
                  
                  print('🎯 Pan update delta: ${details.delta}');
                  setState(() {
                    // Move the window by the drag delta
                    _windowX += details.delta.dx;
                    _windowY += details.delta.dy;
                    _clampWindowPosition(screenWidth, screenHeight);
                  });
                  
                  print('🎯 Moving window to (${_windowX}, ${_windowY})');
                  // Actually move the overlay window
                  FlutterOverlayWindow.moveOverlay(OverlayPosition(_windowX, _windowY));
                },
                onPanEnd: (details) {
                  // Resume auto-movement after a delay when user releases
                  Future.delayed(const Duration(seconds: 3), () {
                    if (mounted && !_showMenu && !_expanded) {
                      _startAutoMovement();
                    }
                  });
                },
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
                      icon: Icons.mic,
                      onTap: () {
                        setState(() => _showMenu = false);
                        // TODO: Start voice recording
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
              onTap: () {
                setState(() => _expanded = false);
                _resizeOverlay(false); // Resize back to avatar dimensions
              },
              child: Container(
                color: Colors.black.withOpacity(0.8),
                child: GestureDetector(
                  onTap: () {}, // Prevents closing when tapping chat area
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
                                  onPressed: () {
                                    setState(() => _expanded = false);
                                    _resizeOverlay(false); // Resize back to avatar dimensions
                                  },
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
                                const SizedBox(width: 8),
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
        ],
    );
  }
}
