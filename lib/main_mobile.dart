// main_mobile.dart
// Mobile-compatible version without desktop-specific dependencies

import 'package:gif/gif.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
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

/// ===== Avatar GIF assets + timings =====
const String kAvatarIdleGif = 'assets/avatar/idle.gif';
const String kAvatarAttentionGif = 'assets/avatar/attention.gif';
const String kAvatarThinkingGif = 'assets/avatar/thinking.gif';
const String kAvatarSpeakingGif = 'assets/avatar/speaking.gif';

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
  
  // Initialize Firebase
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    await FirebaseService.initialize();
    print('✅ Firebase initialized successfully');
  } catch (e) {
    print('⚠️ Firebase initialization failed: $e');
    print('📱 App will continue with local storage only');
  }
  
  runApp(const KaiMobileApp());
}

class KaiMobileApp extends StatelessWidget {
  const KaiMobileApp({super.key});
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
      home: const _MobileKai(),
    );
  }
}

class _MobileKai extends StatefulWidget {
  const _MobileKai();
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
  // persona runtime
  String _personaId = kPersonaKai;
  bool get _isClone => _personaId == kPersonaClone;

  // glow
  late final AnimationController _glowCtrl;
  late final Animation<double> _glow;

  // bubble state
  bool _showBubble = false;
  bool _devOpen = false;
  final _controller = TextEditingController();
  final _focus = FocusNode();
  String? _reply;
  String? _error;
  bool _sending = false;

  // audio
  final _player = AudioPlayer();
  late final StreamSubscription<PlayerState> _stateSub;
  PlayerState _currentState = PlayerState.stopped;

  bool _ttsLoading = false;
  String? _ttsPath;
  bool _autoPlayTts = true;
  bool _adaptToUser = false;
  String _modelId = 'gpt-4o';
  int _ctxTurns = 20;

  // delta bubbles
  final List<_Floater> _floaters = [];
  final Random _rng = Random();

  // avatar state machine
  DateTime _lastInteraction = DateTime.now();
  DateTime _attentionUntil = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _idleTicker;

  void _markInteraction() {
    _lastInteraction = DateTime.now();
  }

  void _pulseAttention() {
    _attentionUntil = DateTime.now().add(kAttentionPulse);
    setState(() {});
  }

  bool get _isSpeaking => _currentState == PlayerState.playing;

  _AvatarState _resolveAvatarState() {
    if (_isSpeaking) return _AvatarState.speaking;
    if (_sending) return _AvatarState.thinking;
    if (DateTime.now().isBefore(_attentionUntil)) return _AvatarState.attention;
    final idleFor = DateTime.now().difference(_lastInteraction);
    if (idleFor >= kIdleAfter) return _AvatarState.idle;
    return _AvatarState.idle;
  }

  String _avatarAssetFor(_AvatarState s) {
    switch (s) {
      case _AvatarState.speaking:
        return kAvatarSpeakingGif;
      case _AvatarState.thinking:
        return kAvatarThinkingGif;
      case _AvatarState.attention:
        return kAvatarAttentionGif;
      case _AvatarState.idle:
        return kAvatarIdleGif;
    }
  }

  // persona toggle
  Future<void> _togglePersona() async {
    setState(() {
      _personaId = _personaId == kPersonaKai ? kPersonaClone : kPersonaKai;
    });
    unawaited(aiService.bootstrapPersona(_personaId));
    if (_isClone && _devOpen) setState(() => _devOpen = false);
  }

  @override
  void initState() {
    super.initState();
    _glowCtrl =
        AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))
          ..repeat(reverse: true);
    _glow = Tween(begin: 0.35, end: 1.0)
        .chain(CurveTween(curve: Curves.easeInOut))
        .animate(_glowCtrl);

    _stateSub = _player.onPlayerStateChanged.listen((s) {
      _currentState = s;
      if (mounted) setState(() {});
    });

    _idleTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      for (final p in [
        kAvatarIdleGif,
        kAvatarAttentionGif,
        kAvatarThinkingGif,
        kAvatarSpeakingGif
      ]) {
        precacheImage(AssetImage(p), context);
      }
      unawaited(aiService.bootstrapPersona(_personaId));
    });
  }

  @override
  void dispose() {
    _glowCtrl.dispose();
    _controller.dispose();
    _focus.dispose();
    _stateSub.cancel();
    _player.dispose();
    _idleTicker?.cancel();
    for (final f in _floaters) {
      f.ctrl.dispose();
    }
    super.dispose();
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
      _spawnDeltas(resp.actualDeltas);
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
            pg13: _isClone,
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

  @override
  Widget build(BuildContext context) {
    final avatarState = _resolveAvatarState();
    final avatarAsset = _avatarAssetFor(avatarState);
    final stroke = const Color(0xFFFFE7B0);

    return Scaffold(
      backgroundColor: const Color(0xFF0D0A07),
      appBar: AppBar(
        title: Text(
          'Kai - AI Avatar',
          style: TextStyle(color: _isClone ? Colors.redAccent : Colors.white),
        ),
        backgroundColor: Colors.black.withOpacity(0.3),
        elevation: 0,
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: _togglePersona,
            icon: Icon(
              Icons.swap_horiz,
              color: _isClone ? Colors.redAccent : stroke,
            ),
            tooltip: 'Switch Persona',
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
                      setState(() => _showBubble = !_showBubble);
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
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 220),
                                  child: Gif(
                                    key: ValueKey(avatarAsset),
                                    image: AssetImage(avatarAsset),
                                    autostart: Autostart.loop,
                                    fit: BoxFit.cover,
                                    fps: 24,
                                  ),
                                ),
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
                  'Kai${_isClone ? ' (Clone)' : ''}',
                  style: TextStyle(
                    color: _isClone ? Colors.redAccent : Colors.white,
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
                  _MobileButton(
                    icon: Icons.volume_up,
                    label: 'Voice',
                    onTap: _toggleVoice,
                  ),
                  if (!_isClone)
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
                    devOpen: _devOpen,
                    controller: _controller,
                    focusNode: _focus,
                    onSend: _send,
                    onClose: () => setState(() => _showBubble = false),
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
                    pg13: _isClone,
                  ),
                ),

              // Tap to chat message
              if (!_showBubble)
                Padding(
                  padding: const EdgeInsets.all(16),
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

  const _MobileButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const stroke = Color(0xFFFFE7B0);
    return GestureDetector(
      onTap: onTap,
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
  final bool pg13;

  const _MobileChatBubble({
    required this.sending,
    required this.reply,
    required this.error,
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
    required this.pg13,
  });

  @override
  Widget build(BuildContext context) {
    final bg = const Color(0xFF1F1A15);
    final stroke = const Color(0xFFFFE7B0);

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
              Text(
                'Kai (Mobile)',
                style: TextStyle(
                  color: pg13 ? Colors.redAccent : Colors.white70,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: onToggleDev,
                child: Text(
                  devOpen ? 'DEV ▲' : 'DEV ▼',
                  style: TextStyle(color: stroke),
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
                      borderSide: BorderSide(color: stroke),
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
                  Text(
                    reply!,
                    style: const TextStyle(color: Colors.white, height: 1.4),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Text(
                        'Voice:',
                        style: TextStyle(color: stroke, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: voiceLoading ? null : onVoiceTap,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          foregroundColor: stroke,
                          side: BorderSide(color: stroke),
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
  final Future<void> Function(
          Map<String, num> pc, Map<String, num> mc, Map<String, num> ac)
      onSave;
  final bool pg13;
  const PersonaDialog(
      {super.key, required this.initial, required this.onSave, this.pg13 = false});
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
    final bg = const Color(0xFF1F1A15);
    final stroke = const Color(0xFFFFE7B0);
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
        side: BorderSide(color: stroke, width: 2),
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

                // Affinity section (not for clone)
                if (!widget.pg13)
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
                if (!widget.pg13) const SizedBox(height: 12),

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
                          side: BorderSide(color: stroke),
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