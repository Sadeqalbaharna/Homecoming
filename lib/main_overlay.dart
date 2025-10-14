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
      home: Material(
        color: Colors.transparent,
        child: OverlayWidget(),
      ),
    ),
  );
}

// ============= MAIN APP ENTRY POINT =============
// This starts the overlay service then closes
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Always show the permission screen - it will handle checking permission
  runApp(const PermissionRequestApp());
}

Future<void> startOverlay() async {
  try {
    await FlutterOverlayWindow.showOverlay();
  } catch (e) {
    debugPrint('Error starting overlay: $e');
    rethrow;
  }
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
  bool _isChecking = true;
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermission();
  }
  
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // When user returns from Settings, check permission again
    if (state == AppLifecycleState.resumed) {
      _checkPermission();
    }
  }
  
  Future<void> _checkPermission() async {
    setState(() => _isChecking = true);
    final granted = await FlutterOverlayWindow.isPermissionGranted();
    setState(() => _isChecking = false);
    
    if (granted) {
      // Permission granted, start overlay after a short delay
      await Future.delayed(const Duration(milliseconds: 500));
      await _startOverlayAndExit();
    }
  }
  
  Future<void> _startOverlayAndExit() async {
    try {
      debugPrint('Starting overlay...');
      await startOverlay();
      debugPrint('Overlay started, waiting before exit...');
      // Give the overlay more time to fully initialize
      await Future.delayed(const Duration(milliseconds: 1000));
      debugPrint('Exiting main app...');
      exit(0);
    } catch (e) {
      debugPrint('Error starting overlay: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to start overlay: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
      setState(() => _isChecking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isChecking) {
      return const Scaffold(
        backgroundColor: Color(0xFF0D0A07),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Color(0xFFFFE7B0)),
              SizedBox(height: 16),
              Text(
                'Checking permissions...',
                style: TextStyle(color: Color(0xFFFFE7B0), fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }
    
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
                  setState(() => _isChecking = true);
                  
                  // Request permission
                  final granted = await FlutterOverlayWindow.requestPermission();
                  
                  if (granted == true) {
                    // Permission granted, check again (this will start overlay)
                    await _checkPermission();
                  } else {
                    setState(() => _isChecking = false);
                    
                    // Permission denied, show error
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Permission denied. Kai needs overlay permission to work.'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
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
  
  // Position for draggable Kai avatar
  double _avatarX = 0.0;
  double _avatarY = 0.0;
  bool _positioned = false;
  
  // Animation controller for staggered button appearance
  late AnimationController _menuAnimController;

  @override
  void initState() {
    super.initState();
    _player.onPlayerStateChanged.listen((state) {
      if (mounted) setState(() => _playerState = state);
    });
    
    // Initialize menu animation controller
    _menuAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _player.dispose();
    _menuAnimController.dispose();
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
  
  /// Helper to build circular menu buttons around Kai with staggered animation
  Widget _buildCircularButton({
    required double angle,
    required double radius,
    required IconData icon,
    required VoidCallback onTap,
    required int index,
    required int totalButtons,
  }) {
    // Convert angle to radians
    final radians = angle * pi / 180;
    
    // Calculate position
    final x = 50 + radius * cos(radians); // 50 = half of avatar width
    final y = 60 + radius * sin(radians); // 60 = half of avatar height
    
    // Calculate staggered delay for this button
    // Each button appears slightly after the previous one
    final double delayStart = (index / totalButtons) * 0.5;
    
    return Positioned(
      left: x - 26, // 26 = half of button size
      top: y - 26,
      child: AnimatedBuilder(
        animation: _menuAnimController,
        builder: (context, child) {
          // Calculate this button's animation progress (0.0 to 1.0)
          final double progress = (((_menuAnimController.value - delayStart) / 0.5).clamp(0.0, 1.0));
          
          // Scale from 0 to 1 with elastic effect
          final double scale = progress * progress * (3.0 - 2.0 * progress); // Smooth step
          
          // Fade in
          final double opacity = progress;
          
          return Transform.scale(
            scale: scale,
            child: Opacity(
              opacity: opacity,
              child: child,
            ),
          );
        },
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.7),
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color(0xFFFFE7B0),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFFE7B0).withOpacity(0.3),
                  blurRadius: 10,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Icon(
              icon,
              color: const Color(0xFFFFE7B0),
              size: 24,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Floating Kai (draggable when minimized)
        if (!_expanded)
          Positioned(
            left: _positioned ? _avatarX : null,
            top: _positioned ? _avatarY : null,
            bottom: _positioned ? null : 80,
            right: _positioned ? null : 20,
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _showMenu = !_showMenu;
                  if (_showMenu) {
                    _menuAnimController.forward(from: 0.0);
                  } else {
                    _menuAnimController.reverse();
                  }
                });
              },
              onLongPress: () async {
                // Close overlay on long press
                await FlutterOverlayWindow.closeOverlay();
              },
              onPanUpdate: (details) {
                setState(() {
                  _positioned = true;
                  _avatarX += details.delta.dx;
                  _avatarY += details.delta.dy;
                  
                  // Keep avatar within screen bounds
                  final screenWidth = MediaQuery.of(context).size.width;
                  final screenHeight = MediaQuery.of(context).size.height;
                  
                  // Clamp X position
                  if (_avatarX < 0) _avatarX = 0;
                  if (_avatarX > screenWidth - 100) _avatarX = screenWidth - 100;
                  
                  // Clamp Y position
                  if (_avatarY < 0) _avatarY = 0;
                  if (_avatarY > screenHeight - 120) _avatarY = screenHeight - 120;
                });
              },
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // Kai avatar
                  Container(
                    width: 100,
                    height: 120,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(50),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFFE7B0).withOpacity(0.5),
                          blurRadius: 20,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                    child: Image.asset(
                      kAvatarIdleGif,
                      fit: BoxFit.contain,
                    ),
                  ),
                  
                  // Circular menu buttons
                  if (_showMenu) ...[
                    // Chat button (top)
                    _buildCircularButton(
                      angle: -90,
                      radius: 80,
                      icon: Icons.chat_bubble,
                      index: 0,
                      totalButtons: 8,
                      onTap: () {
                        setState(() {
                          _showMenu = false;
                          _expanded = true;
                        });
                      },
                    ),
                    
                    // Voice/TTS button (top-right)
                    _buildCircularButton(
                      angle: -45,
                      radius: 80,
                      icon: _playerState == PlayerState.playing ? Icons.pause : Icons.play_arrow,
                      index: 1,
                      totalButtons: 8,
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
                      radius: 80,
                      icon: Icons.settings,
                      index: 2,
                      totalButtons: 8,
                      onTap: () {
                        setState(() => _showMenu = false);
                        // TODO: Open settings
                      },
                    ),
                    
                    // Microphone button (bottom-right)
                    _buildCircularButton(
                      angle: 45,
                      radius: 80,
                      icon: Icons.mic,
                      index: 3,
                      totalButtons: 8,
                      onTap: () {
                        setState(() => _showMenu = false);
                        // TODO: Start voice recording
                      },
                    ),
                    
                    // Close button (bottom)
                    _buildCircularButton(
                      angle: 90,
                      radius: 80,
                      icon: Icons.close,
                      index: 4,
                      totalButtons: 8,
                      onTap: () async {
                        await FlutterOverlayWindow.closeOverlay();
                      },
                    ),
                    
                    // Info button (bottom-left)
                    _buildCircularButton(
                      angle: 135,
                      radius: 80,
                      icon: Icons.info_outline,
                      index: 5,
                      totalButtons: 8,
                      onTap: () {
                        setState(() => _showMenu = false);
                        // TODO: Show info
                      },
                    ),
                    
                    // Minimize button (left)
                    _buildCircularButton(
                      angle: 180,
                      radius: 80,
                      icon: Icons.minimize,
                      index: 6,
                      totalButtons: 8,
                      onTap: () {
                        setState(() => _showMenu = false);
                      },
                    ),
                    
                    // Favorite/bookmark button (top-left)
                    _buildCircularButton(
                      angle: -135,
                      radius: 80,
                      icon: Icons.favorite_border,
                      index: 7,
                      totalButtons: 8,
                      onTap: () {
                        setState(() => _showMenu = false);
                        // TODO: Toggle favorite
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
        
        // Expanded chat UI
        if (_expanded)
          Positioned.fill(
            child: GestureDetector(
              onTap: () => setState(() => _expanded = false),
              child: Container(
                color: Colors.black.withOpacity(0.8),
                child: Center(
                  child: GestureDetector(
                    onTap: () {}, // Prevents closing when tapping chat area
                    child: Container(
                      width: MediaQuery.of(context).size.width * 0.9,
                      height: MediaQuery.of(context).size.height * 0.7,
                      decoration: BoxDecoration(
                        color: const Color(0xFF0D0A07),
                        borderRadius: BorderRadius.circular(20),
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
                                  onPressed: () => setState(() => _expanded = false),
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
          ),
      ],
    );
  }
}
