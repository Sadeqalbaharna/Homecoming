// main_overlay.dart
// Transparent overlay version of the Kai app

import 'package:gif/gif.dart';
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

import 'services/ai_service.dart';
import 'services/firebase_service.dart';
import 'firebase_options.dart';

/// ===== Layout / Window =====
const double kSpriteSize = 170;
const double kRingPadding = 48;
const double kCanvasWidth = 560;
const double kCanvasHeight = 600;
const double kSpriteAlignY = 0.30;
const double kUiLiftPx = 64;

/// ===== Avatar assets + timings =====
const String kAvatarIdleGif = 'assets/avatar/images/mage.png';
const String kAvatarAttentionGif = 'assets/avatar/images/mage.png';
const String kAvatarThinkingGif = 'assets/avatar/images/mage.png';
const String kAvatarSpeakingGif = 'assets/avatar/images/mage.png';

const Duration kIdleAfter = Duration(seconds: 15);
const Duration kAttentionPulse = Duration(seconds: 2);

enum _AvatarState { idle, attention, thinking, speaking }

/// Persona IDs
const String kPersonaKai = 'truekai';
const String kPersonaClone = 'clonekai';

/// Global AI service instance
final aiService = AIService();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Set transparent status bar
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  
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
  
  // Run the overlay app
  runApp(KaiOverlayApp(firebaseInitialized: firebaseInitialized));
}

class KaiOverlayApp extends StatelessWidget {
  final bool firebaseInitialized;
  
  const KaiOverlayApp({super.key, required this.firebaseInitialized});
  
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Kai - Overlay',
      theme: ThemeData(
        scaffoldBackgroundColor: Colors.transparent,
        primarySwatch: Colors.amber,
        brightness: Brightness.dark,
      ),
      home: OverlayHomePage(firebaseInitialized: firebaseInitialized),
    );
  }
}

class OverlayHomePage extends StatefulWidget {
  final bool firebaseInitialized;
  
  const OverlayHomePage({super.key, required this.firebaseInitialized});

  @override
  State<OverlayHomePage> createState() => _OverlayHomePageState();
}

class _OverlayHomePageState extends State<OverlayHomePage> {
  bool _expanded = false;
  String _personaId = kPersonaKai;
  String _modelId = 'gpt-4o';
  bool _adaptToUser = true;
  int _ctxTurns = 5;
  
  final _controller = TextEditingController();
  final _player = AudioPlayer();
  
  bool _sending = false;
  String? _reply;
  String? _error;
  String? _ttsPath;
  bool _ttsLoading = false;
  bool _autoPlayTts = true;
  bool _devOpen = false;
  
  PlayerState? _currentState;

  @override
  void initState() {
    super.initState();
    _player.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() => _currentState = state);
      }
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
      _devOpen = false;
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
      });
      
      // Save conversation to Firebase
      try {
        await FirebaseService.saveConversation(
          personaId: _personaId,
          userMessage: text,
          aiResponse: resp.reply,
          personalityDeltas: resp.actualDeltas,
        );
        print('✅ Conversation logged to Firebase');
      } catch (e) {
        print('⚠️ Failed to log conversation to Firebase: $e');
      }
      
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withOpacity(0.3),
              Colors.black.withOpacity(0.7),
            ],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              // Floating Kai Avatar
              Positioned(
                top: _expanded ? 20 : MediaQuery.of(context).size.height * 0.3,
                left: MediaQuery.of(context).size.width / 2 - 85,
                child: GestureDetector(
                  onTap: () {
                    setState(() => _expanded = !_expanded);
                  },
                  child: Container(
                    width: 170,
                    height: 170,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFFFFE7B0),
                        width: 3,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFFE7B0).withOpacity(0.5),
                          blurRadius: 20,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: Image.asset(
                        kAvatarIdleGif,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
              ),
              
              // Chat interface (appears when expanded)
              if (_expanded)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D0A07).withOpacity(0.95),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                      border: Border.all(
                        color: const Color(0xFFFFE7B0).withOpacity(0.3),
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Drag handle
                        Container(
                          margin: const EdgeInsets.only(top: 8),
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        
                        // Header
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Kai (Overlay)',
                                style: TextStyle(
                                  color: Color(0xFFFFE7B0),
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close, color: Colors.white),
                                onPressed: () {
                                  setState(() => _expanded = false);
                                },
                              ),
                            ],
                          ),
                        ),
                        
                        // Message input
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _controller,
                                  style: const TextStyle(color: Colors.white),
                                  decoration: InputDecoration(
                                    hintText: 'Chat with Kai...',
                                    hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                                    filled: true,
                                    fillColor: const Color(0xFF2A2119),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(25),
                                      borderSide: BorderSide.none,
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                      vertical: 12,
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
                                    ? const CircularProgressIndicator(
                                        color: Color(0xFF0D0A07),
                                        strokeWidth: 2,
                                      )
                                    : const Icon(
                                        Icons.send,
                                        color: Color(0xFF0D0A07),
                                      ),
                              ),
                            ],
                          ),
                        ),
                        
                        // Reply bubble
                        if (_reply != null)
                          Container(
                            margin: const EdgeInsets.all(16),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2A2119),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(0xFFFFE7B0).withOpacity(0.3),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _reply!,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                  ),
                                ),
                                if (_ttsPath != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 12),
                                    child: ElevatedButton.icon(
                                      onPressed: () async {
                                        if (_currentState == PlayerState.playing) {
                                          await _player.pause();
                                        } else {
                                          await _player.play(DeviceFileSource(_ttsPath!));
                                        }
                                      },
                                      icon: Icon(
                                        _currentState == PlayerState.playing
                                            ? Icons.pause
                                            : Icons.play_arrow,
                                      ),
                                      label: const Text('Voice'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFFFFE7B0),
                                        foregroundColor: const Color(0xFF0D0A07),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        
                        // Error display
                        if (_error != null)
                          Container(
                            margin: const EdgeInsets.all(16),
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
                        
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
