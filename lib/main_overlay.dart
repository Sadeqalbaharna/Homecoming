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
  
  // Check if we have overlay permission
  final bool status = await FlutterOverlayWindow.isPermissionGranted();
  
  if (!status) {
    // Need to request permission - show permission screen
    runApp(const PermissionRequestApp());
  } else {
    // Permission granted, start overlay immediately
    await startOverlay();
    
    // Wait for overlay to fully initialize before closing main activity
    await Future.delayed(const Duration(milliseconds: 3000));
    
    // Close the main activity (but keep the service running)
    // Don't use exit(0) as it kills the overlay service too!
    SystemNavigator.pop();
  }
}

Future<void> startOverlay() async {
  await FlutterOverlayWindow.showOverlay(
    enableDrag: true,
    overlayTitle: "Kai",
    overlayContent: "Tap to chat with Kai!",
    flag: OverlayFlag.defaultFlag,
    visibility: NotificationVisibility.visibilityPublic,
    positionGravity: PositionGravity.none,
    width: WindowSize.matchParent,
    height: WindowSize.matchParent,
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

class PermissionScreen extends StatelessWidget {
  const PermissionScreen({super.key});

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
                  // Request permission
                  final granted = await FlutterOverlayWindow.requestPermission();
                  if (granted == true) {
                    // Start overlay
                    await startOverlay();
                    // Exit the app - overlay runs independently
                    exit(0);
                  } else {
                    // Permission denied, show error
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Permission denied. Kai needs overlay permission to work.'),
                        backgroundColor: Colors.red,
                      ),
                    );
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

class _OverlayWidgetState extends State<OverlayWidget> {
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

  @override
  void initState() {
    super.initState();
    _player.onPlayerStateChanged.listen((state) {
      if (mounted) setState(() => _playerState = state);
    });
  }

  @override
  void dispose() {
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
    
    // Calculate position relative to the center of the 280x280 container
    final centerX = 140.0; // Center of 280px container
    final centerY = 140.0; // Center of 280px container
    
    final x = centerX + radius * cos(radians);
    final y = centerY + radius * sin(radians);
    
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
          onTap: onTap,
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
              size: 24, // Original icon size
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
    
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // No background widget - transparent areas will pass through!
          
          // Floating Kai (draggable when minimized)
          if (!_expanded)
            Positioned(
              left: _positioned ? _avatarX : (screenWidth / 2 - 140), // Center horizontally with menu space
              top: _positioned ? _avatarY : (screenHeight / 2 - 140), // Center vertically with menu space
              child: GestureDetector(
                onTap: () => setState(() => _showMenu = !_showMenu),
                onLongPress: () async {
                  // Close overlay on long press
                  await FlutterOverlayWindow.closeOverlay();
                },
                onPanUpdate: (details) {
                  setState(() {
                    _positioned = true;
                    _avatarX += details.delta.dx;
                    _avatarY += details.delta.dy;
                    
                    // Keep avatar within screen bounds (accounting for full widget size)
                    // Clamp X position
                    if (_avatarX < 0) _avatarX = 0;
                    if (_avatarX > screenWidth - 280) _avatarX = screenWidth - 280;
                    
                    // Clamp Y position
                    if (_avatarY < 0) _avatarY = 0;
                    if (_avatarY > screenHeight - 280) _avatarY = screenHeight - 280;
                  });
                },
                child: SizedBox(
                  width: 280, // Container: 80px radius * 2 + 100px avatar + margin
                  height: 280,
                  child: Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.center,
                    children: [
                      // Kai avatar - centered at original size
                      Positioned(
                        left: 90, // Center: (280 - 100) / 2
                        top: 80, // Center: (280 - 120) / 2
                        child: Container(
                          width: 100, // Original avatar size
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
                      ),
                  
                  // Circular menu buttons
                  if (_showMenu) ...[
                    // Chat button (top)
                    _buildCircularButton(
                      angle: -90,
                      radius: 80, // Original radius
                      icon: Icons.chat_bubble,
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
                      radius: 80, // Original radius
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
                      radius: 80, // Original radius
                      icon: Icons.settings,
                      onTap: () {
                        setState(() => _showMenu = false);
                        // TODO: Open settings
                      },
                    ),
                    
                    // Microphone button (bottom-right)
                    _buildCircularButton(
                      angle: 45,
                      radius: 80, // Original radius
                      icon: Icons.mic,
                      onTap: () {
                        setState(() => _showMenu = false);
                        // TODO: Start voice recording
                      },
                    ),
                    
                    // Close button (bottom)
                    _buildCircularButton(
                      angle: 90,
                      radius: 80, // Original radius
                      icon: Icons.close,
                      onTap: () async {
                        await FlutterOverlayWindow.closeOverlay();
                      },
                    ),
                    
                    // Info button (bottom-left)
                    _buildCircularButton(
                      angle: 135,
                      radius: 80, // Original radius
                      icon: Icons.info_outline,
                      onTap: () {
                        setState(() => _showMenu = false);
                        // TODO: Show info
                      },
                    ),
                    
                    // Minimize button (left)
                    _buildCircularButton(
                      angle: 180,
                      radius: 80, // Original radius
                      icon: Icons.minimize,
                      onTap: () {
                        setState(() => _showMenu = false);
                      },
                    ),
                    
                    // Favorite/bookmark button (top-left)
                    _buildCircularButton(
                      angle: -135,
                      radius: 80, // Original radius
                      icon: Icons.favorite_border,
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
      ),
    );
  }
}
