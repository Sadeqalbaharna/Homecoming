// main_overlay.dart
// True system overlay using flutter_overlay_window - floats above ALL apps like Shimeji!

import 'dart:async';
import 'dart:convert';
import 'dart:io';
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
    // Exit the app after starting overlay (the overlay runs independently)
    exit(0);
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

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Transparent clickable background when minimized
        if (!_expanded)
          Positioned.fill(
            child: GestureDetector(
              onTap: () {}, // Captures taps but does nothing - makes area transparent
              child: Container(color: Colors.transparent),
            ),
          ),
        
        // Floating Kai (draggable when minimized)
        if (!_expanded)
          Positioned(
            left: _positioned ? _avatarX : null,
            top: _positioned ? _avatarY : null,
            bottom: _positioned ? null : 80,
            right: _positioned ? null : 20,
            child: GestureDetector(
              onTap: () => setState(() => _expanded = true),
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
              child: Container(
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
