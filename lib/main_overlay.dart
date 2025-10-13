// main_overlay.dart
// True transparent overlay - see through to other apps, only Kai is visible

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:firebase_core/firebase_core.dart';

import 'services/ai_service.dart';
import 'services/firebase_service.dart';
import 'firebase_options.dart';

/// Kai avatar asset
const String kAvatarIdleGif = 'assets/avatar/images/mage.png';

/// Global AI service instance
final aiService = AIService();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Make status bar transparent
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );
  
  // Initialize Firebase
  bool firebaseInitialized = false;
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    await FirebaseService.initialize();
    firebaseInitialized = true;
    print('✅ Firebase initialized');
  } catch (e) {
    print('⚠️ Firebase init failed: $e');
  }
  
  runApp(KaiOverlayApp(firebaseInitialized: firebaseInitialized));
}

class KaiOverlayApp extends StatelessWidget {
  final bool firebaseInitialized;
  
  const KaiOverlayApp({super.key, required this.firebaseInitialized});
  
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Kai Overlay',
      theme: ThemeData(
        scaffoldBackgroundColor: Colors.transparent,
        brightness: Brightness.dark,
      ),
      home: OverlayHome(firebaseInitialized: firebaseInitialized),
    );
  }
}

class OverlayHome extends StatefulWidget {
  final bool firebaseInitialized;
  
  const OverlayHome({super.key, required this.firebaseInitialized});

  @override
  State<OverlayHome> createState() => _OverlayHomeState();
}

class _OverlayHomeState extends State<OverlayHome> {
  bool _expanded = false;
  final _controller = TextEditingController();
  final _player = AudioPlayer();
  
  bool _sending = false;
  String? _reply;
  String? _error;
  String? _ttsPath;
  PlayerState? _playerState;

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
      
      // Save to Firebase
      try {
        await FirebaseService.saveConversation(
          personaId: 'truekai',
          userMessage: text,
          aiResponse: resp.reply,
          personalityDeltas: resp.actualDeltas,
        );
      } catch (e) {
        print('⚠️ Firebase save failed: $e');
      }
      
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
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Floating Kai Avatar
          Positioned(
            top: _expanded ? 40 : screenHeight * 0.35,
            left: screenWidth / 2 - 85,
            child: GestureDetector(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Container(
                width: 170,
                height: 170,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFFFE7B0), width: 3),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFFE7B0).withOpacity(0.6),
                      blurRadius: 30,
                      spreadRadius: 10,
                    ),
                  ],
                ),
                child: ClipOval(
                  child: Image.asset(kAvatarIdleGif, fit: BoxFit.cover),
                ),
              ),
            ),
          ),
          
          // Chat Panel (slides up when expanded)
          if (_expanded)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF0D0A07).withOpacity(0.95),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                  border: Border.all(color: const Color(0xFFFFE7B0).withOpacity(0.3)),
                ),
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Chat with Kai',
                          style: TextStyle(
                            color: Color(0xFFFFE7B0),
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: () => setState(() => _expanded = false),
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 8),
                    
                    // Input field
                    Row(
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
                    
                    // Reply bubble
                    if (_reply != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2A2119),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _reply!,
                              style: const TextStyle(color: Colors.white),
                            ),
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
                                icon: Icon(
                                  _playerState == PlayerState.playing
                                      ? Icons.pause
                                      : Icons.play_arrow,
                                ),
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
                    ],
                    
                    // Error display
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red),
                        ),
                        child: Text(
                          _error!,
                          style: const TextStyle(color: Colors.red, fontSize: 12),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
