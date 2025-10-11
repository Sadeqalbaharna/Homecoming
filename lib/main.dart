// main_pure_flutter.dart
// Pure Flutter implementation - No Python backend needed!

import 'package:gif/gif.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart' as acrylic;
import 'package:window_manager/window_manager.dart';
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
const bool kAlwaysOnTop = false;

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
  
  await acrylic.Window.initialize();
  await windowManager.ensureInitialized();
  await acrylic.Window.setEffect(
      effect: acrylic.WindowEffect.transparent, color: Colors.transparent);

  const options = WindowOptions(
    size: Size(kCanvasWidth, kCanvasHeight),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
  );
  windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.setAsFrameless();
    await windowManager.setAlwaysOnTop(kAlwaysOnTop);
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(const KaiOverlay());
}

class KaiOverlay extends StatelessWidget {
  const KaiOverlay({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(scaffoldBackgroundColor: Colors.transparent),
      home: Transform.translate(
        offset: const Offset(0, -kUiLiftPx),
        child: const _FloatingKai(),
      ),
    );
  }
}

class _FloatingKai extends StatefulWidget {
  const _FloatingKai();
  @override
  State<_FloatingKai> createState() => _FloatingKaiState();
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

class _FloatingKaiState extends State<_FloatingKai>
    with TickerProviderStateMixin, WindowListener {
  // persona runtime
  String _personaId = kPersonaKai;
  bool get _isClone => _personaId == kPersonaClone;

  // drag
  Offset _dragStart = Offset.zero;
  void _startDrag(DragStartDetails d) {
    _dragStart = d.globalPosition;
    _markInteraction();
  }

  void _drag(DragUpdateDetails d) async {
    final pos = await windowManager.getPosition();
    final delta = d.globalPosition - _dragStart;
    _dragStart = d.globalPosition;
    await windowManager.setPosition(Offset(pos.dx + delta.dx, pos.dy + delta.dy));
    _markInteraction();
  }

  // keys/center
  final _stackKey = GlobalKey();
  final _avatarKey = GlobalKey();
  Offset? _avatarCenterPx;

  void _scheduleCenterUpdate() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateCenterNow());
  }

  void _updateCenterNow() {
    final stackBox = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    final avatarBox = _avatarKey.currentContext?.findRenderObject() as RenderBox?;
    if (stackBox == null || avatarBox == null) return;
    final avatarOffsetGlobal = avatarBox.localToGlobal(Offset.zero);
    final avatarSize = avatarBox.size;
    final avatarCenterGlobal =
        avatarOffsetGlobal + Offset(avatarSize.width / 2, avatarSize.height / 2);
    final avatarCenterLocal = stackBox.globalToLocal(avatarCenterGlobal);
    setState(() => _avatarCenterPx = avatarCenterLocal);
  }

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

    windowManager.addListener(this);
    _scheduleCenterUpdate();

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
    windowManager.removeListener(this);
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

  @override
  void onWindowResize() => _scheduleCenterUpdate();
  @override
  void onWindowMove() => _scheduleCenterUpdate();

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

  Offset _fallbackCenter() {
    final cx = kCanvasWidth / 2;
    final cy = kCanvasHeight * 0.44;
    return Offset(cx, cy);
  }

  Offset _placePolar(Offset center, double radius, double deg) {
    final rad = deg * pi / 180.0;
    return Offset(center.dx + radius * cos(rad), center.dy + radius * sin(rad));
  }

  bool _isPointInsideAvatar(Offset global) {
    final center = _avatarCenterPx ?? _fallbackCenter();
    final r = kSpriteSize / 2;
    final box = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return false;
    final local = box.globalToLocal(global);
    return (local - center).distance <= r;
  }

  @override
  Widget build(BuildContext context) {
    final center = _avatarCenterPx ?? _fallbackCenter();

    const ringItemSize = 56.0;
    const ringItemHalf = ringItemSize / 2;
    const ringSafety = 8.0;
    final minEdgeDist = min(
      min(center.dx, kCanvasWidth - center.dx),
      min(center.dy, kCanvasHeight - center.dy),
    );
    final maxAllowed = (minEdgeDist - ringItemHalf - ringSafety).clamp(80.0, 999.0);
    final target = (kSpriteSize * 0.90) + (kRingPadding * 0.45);
    final ringRadius = min(maxAllowed.toDouble(), target);

    final posSpeaker = _placePolar(center, ringRadius, 340);
    final posEmpathy = _placePolar(center, ringRadius, 305);
    final posPersona = _placePolar(center, ringRadius, 270);
    final posModel = _placePolar(center, ringRadius, 235);
    final posSwitch = _placePolar(center, ringRadius, 200);

    final avatarState = _resolveAvatarState();
    final avatarAsset = _avatarAssetFor(avatarState);
    final stroke = const Color(0xFFFFE7B0);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: Listener(
          onPointerHover: (_) => _markInteraction(),
          onPointerDown: (_) => _markInteraction(),
          child: GestureDetector(
            onPanStart: _startDrag,
            onPanUpdate: _drag,
            onTapDown: (d) {
              _markInteraction();
              if (_isPointInsideAvatar(d.globalPosition)) _pulseAttention();
            },
            onTap: () {
              setState(() => _showBubble = !_showBubble);
              _scheduleCenterUpdate();
              if (_showBubble) {
                Future.delayed(const Duration(milliseconds: 50),
                    () => _focus.requestFocus());
              }
            },
            child: SizedBox(
              key: _stackKey,
              width: kCanvasWidth,
              height: kCanvasHeight,
              child: AnimatedBuilder(
                animation: _glow,
                builder: (context, _) {
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // avatar + glow
                      Align(
                        alignment: Alignment(0, kSpriteAlignY),
                        child: Stack(
                          key: _avatarKey,
                          alignment: Alignment.center,
                          children: [
                            SizedBox(
                              width: kSpriteSize + kRingPadding * 2.8,
                              height: kSpriteSize + kRingPadding * 2.8,
                              child: CustomPaint(
                                painter: _GlowRingPainter(intensity: _glow.value),
                              ),
                            ),
                            SizedBox(
                              width: kSpriteSize,
                              height: kSpriteSize,
                              child: ClipOval(
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 220),
                                  switchInCurve: Curves.easeOut,
                                  switchOutCurve: Curves.easeIn,
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
                            Positioned(
                              bottom: -18,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.45),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(color: stroke.withOpacity(0.7)),
                                ),
                                child: Text(
                                  'Kai',
                                  style: TextStyle(
                                    color: _isClone ? Colors.redAccent : Colors.white70,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // rising delta bubbles
                      ..._floaters.map((f) {
                        final anim = CurvedAnimation(
                            parent: f.ctrl, curve: Curves.easeOutCubic);
                        final baseR = kSpriteSize * 0.72;
                        final travel = 24.0;
                        final r = baseR + anim.value * travel;

                        final x = center.dx + r * cos(f.angle);
                        final y = center.dy + r * sin(f.angle) - anim.value * 18;

                        return Positioned(
                          left: x - 40,
                          top: y - 16,
                          child: Opacity(
                            opacity: (1.0 - anim.value).clamp(0.0, 1.0),
                            child: Transform.scale(
                              scale: 0.85 + (1 - anim.value) * 0.15,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.6),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                      color: f.color.withOpacity(0.9), width: 1.4),
                                ),
                                child: Text(
                                  f.text,
                                  style: TextStyle(
                                      color: f.color, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ),
                          ),
                        );
                      }),

                      // buttons in top arc
                      _RingButton(
                        center: posSpeaker,
                        icon: Icons.volume_up,
                        onTap: () async => _toggleVoice(),
                      ),
                      if (!_isClone)
                        _RingButton(
                          center: posEmpathy,
                          icon: _adaptToUser ? Icons.favorite : Icons.favorite_border,
                          onTap: () => setState(() => _adaptToUser = !_adaptToUser),
                        ),
                      _RingButton(
                        center: posPersona,
                        icon: Icons.person,
                        onTap: () => _openPersonaPanel(context),
                      ),
                      _RingBadge(
                        center: posModel,
                        label: _modelId == 'gpt-5' ? '5' : '4o',
                        onTap: () => setState(() {
                          _modelId = _modelId == 'gpt-4o' ? 'gpt-5' : 'gpt-4o';
                        }),
                      ),
                      _RingBadge(
                        center: posSwitch,
                        label: 'Kai',
                        labelColor: _isClone ? Colors.redAccent : null,
                        onTap: _togglePersona,
                      ),

                      // speech bubble
                      if (_showBubble)
                        Positioned(
                          top: 72,
                          left: (kCanvasWidth - 420) / 2,
                          child: _ComicBubble(
                            maxWidth: 420,
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
                            onVoiceTap: () async => _toggleVoice(),
                            voiceLoading: _ttsLoading,
                            hasVoice: _ttsPath != null,
                            playingStream: _player.onPlayerStateChanged,
                            personaId: _personaId,
                            pg13: _isClone,
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Copy all the UI widget classes from original main.dart
class _RingButton extends StatelessWidget {
  final Offset center;
  final IconData icon;
  final VoidCallback onTap;
  const _RingButton(
      {required this.center, required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) {
    const stroke = Color(0xFFFFE7B0);
    return Positioned(
      left: center.dx - 26,
      top: center.dy - 26,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(26),
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.35),
            shape: BoxShape.circle,
            border: Border.all(color: stroke, width: 2),
          ),
          child: Icon(icon, color: stroke),
        ),
      ),
    );
  }
}

class _RingBadge extends StatelessWidget {
  final Offset center;
  final String label;
  final VoidCallback onTap;
  final Color? labelColor;

  const _RingBadge(
      {required this.center,
      required this.label,
      required this.onTap,
      this.labelColor});

  @override
  Widget build(BuildContext context) {
    const stroke = Color(0xFFFFE7B0);
    final textColor = labelColor ?? stroke;
    return Positioned(
      left: center.dx - 28,
      top: center.dy - 28,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(28),
        child: Container(
          width: 56,
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.35),
            shape: BoxShape.circle,
            border: Border.all(color: stroke, width: 2),
          ),
          child: Text(label,
              style: TextStyle(
                  color: textColor, fontWeight: FontWeight.w800, fontSize: 16)),
        ),
      ),
    );
  }
}

class _ComicBubble extends StatelessWidget {
  final double maxWidth;
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

  const _ComicBubble({
    required this.maxWidth,
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

    return Material(
      color: Colors.transparent,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            bottom: -10,
            left: maxWidth * 0.5 - 14,
            child: Transform.rotate(
              angle: -0.2,
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: bg,
                  border: Border.all(color: stroke, width: 2),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: stroke, width: 2),
                boxShadow: const [
                  BoxShadow(
                      blurRadius: 8, offset: Offset(0, 4), color: Colors.black26)
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // header
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Tooltip(
                        message: 'Persona',
                        child: IconButton(
                          onPressed: onPersonaTap,
                          icon: const Icon(Icons.person),
                          color: stroke,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints.tightFor(
                              width: 36, height: 36),
                        ),
                      ),
                      Text(
                        'Kai (Pure Flutter)',
                        style: TextStyle(
                          color: pg13 ? Colors.redAccent : Colors.white70,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      TextButton(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          foregroundColor: stroke,
                        ),
                        onPressed: onToggleDev,
                        child: Text(devOpen ? 'DEV ▲' : 'DEV ▼'),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: onClose,
                        icon: const Icon(Icons.close),
                        color: stroke,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(
                            width: 36, height: 36),
                      ),
                    ],
                  ),

                  // input row
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: controller,
                          focusNode: focusNode,
                          minLines: 1,
                          maxLines: 3,
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            isDense: true,
                            hintText: 'Ask Kai…',
                            hintStyle: TextStyle(color: Colors.white54),
                            border: InputBorder.none,
                          ),
                          onSubmitted: (_) => onSend(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Send',
                        onPressed: sending ? null : onSend,
                        icon: sending
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.send),
                        color: stroke,
                      ),
                    ],
                  ),

                  // reply + voice
                  if (error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      error!,
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                  ] else if ((reply ?? '').isNotEmpty) ...[
                    const Divider(height: 14, color: Colors.white12),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 180),
                      child: SingleChildScrollView(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            reply!,
                            style: const TextStyle(
                                color: Colors.white, height: 1.25),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text('Voice:', style: TextStyle(color: stroke)),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          style: ButtonStyle(
                            backgroundColor:
                                const MaterialStatePropertyAll<Color>(
                                    Colors.transparent),
                            foregroundColor:
                                MaterialStatePropertyAll<Color>(stroke),
                            side: MaterialStatePropertyAll<BorderSide>(
                              BorderSide(color: stroke, width: 1.2),
                            ),
                            padding:
                                const MaterialStatePropertyAll<EdgeInsets>(
                              EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 8),
                            ),
                            shape:
                                MaterialStatePropertyAll<RoundedRectangleBorder>(
                              RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                            elevation:
                                const MaterialStatePropertyAll<double>(0),
                          ),
                          onPressed: voiceLoading ? null : onVoiceTap,
                          icon: voiceLoading
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2),
                                )
                              : StreamBuilder<PlayerState>(
                                  stream: playingStream,
                                  builder: (context, snap) {
                                    final playing =
                                        snap.data == PlayerState.playing;
                                    return Icon(playing
                                        ? Icons.pause
                                        : Icons.play_arrow);
                                  },
                                ),
                          label: const Text('Play/Pause'),
                        ),
                      ],
                    ),
                  ],

                  // DEV panel
                  if (devOpen) ...[
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2A2119),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: Colors.amber.withOpacity(0.6)),
                      ),
                      child: FutureBuilder<Map<String, dynamic>>(
                        future: aiService.getDiagnostics(),
                        builder: (context, snapshot) {
                          final diag = snapshot.data ?? {};
                          final env = diag['env'] as Map? ?? {};
                          return DefaultTextStyle(
                            style: const TextStyle(
                                color: Colors.amber,
                                fontSize: 12,
                                height: 1.25),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Pure Flutter AI Service'),
                                const SizedBox(height: 4),
                                Text('OpenAI: ${env['OPENAI_API_KEY_set'] ?? false ? 'configured' : 'missing'}'),
                                Text('ElevenLabs: ${env['ELEVENLABS_API_KEY_set'] ?? false ? 'configured' : 'missing'}'),
                                Text('Google: ${env['GOOGLE_API_KEY_set'] ?? false ? 'configured' : 'missing'}'),
                                const SizedBox(height: 6),
                                const Text('No Python backend required!'),
                              ],
                            ),
                          );
                        },
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

// Persona dialog and other UI components (copied from original)
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
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: faint,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: stroke.withOpacity(0.6), width: 1),
                ),
                child:
                    Text(label, style: const TextStyle(color: Colors.white)),
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
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: stroke, width: 2),
      ),
      child: Container(
        width: 500,
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
                    const Text('Kai — Pure Flutter Persona',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w600)),
                    const Spacer(),
                    if (widget.initial.mbti != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
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

                _CardBox(
                  title: 'Personality',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      sliderRow(
                          title: 'Extraversion',
                          max: 1000,
                          value: _pc['extraversion'] ?? 0,
                          onChanged: (v) =>
                              setState(() => _pc['extraversion'] = v),
                          label: (pl['extraversion'] ?? '—').toString()),
                      sliderRow(
                          title: 'Intuition',
                          max: 1000,
                          value: _pc['intuition'] ?? 0,
                          onChanged: (v) =>
                              setState(() => _pc['intuition'] = v),
                          label: (pl['intuition'] ?? '—').toString()),
                      sliderRow(
                          title: 'Feeling',
                          max: 1000,
                          value: _pc['feeling'] ?? 0,
                          onChanged: (v) =>
                              setState(() => _pc['feeling'] = v),
                          label: (pl['feeling'] ?? '—').toString()),
                      sliderRow(
                          title: 'Perceiving',
                          max: 1000,
                          value: _pc['perceiving'] ?? 0,
                          onChanged: (v) =>
                              setState(() => _pc['perceiving'] = v),
                          label: (pl['perceiving'] ?? '—').toString()),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                _CardBox(
                  title: 'Mood',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      sliderRow(
                          title: 'Valence',
                          max: 100,
                          value: _mc['valence'] ?? 0,
                          onChanged: (v) =>
                              setState(() => _mc['valence'] = v),
                          label: (ml['valence'] ?? '—').toString()),
                      sliderRow(
                          title: 'Energy',
                          max: 100,
                          value: _mc['energy'] ?? 0,
                          onChanged: (v) =>
                              setState(() => _mc['energy'] = v),
                          label: (ml['energy'] ?? '—').toString()),
                      sliderRow(
                          title: 'Warmth',
                          max: 100,
                          value: _mc['warmth'] ?? 0,
                          onChanged: (v) =>
                              setState(() => _mc['warmth'] = v),
                          label: (ml['warmth'] ?? '—').toString()),
                      sliderRow(
                          title: 'Confidence',
                          max: 100,
                          value: _mc['confidence'] ?? 0,
                          onChanged: (v) =>
                              setState(() => _mc['confidence'] = v),
                          label: (ml['confidence'] ?? '—').toString()),
                      sliderRow(
                          title: 'Playfulness',
                          max: 100,
                          value: _mc['playfulness'] ?? 0,
                          onChanged: (v) =>
                              setState(() => _mc['playfulness'] = v),
                          label: (ml['playfulness'] ?? '—').toString()),
                      sliderRow(
                          title: 'Focus',
                          max: 100,
                          value: _mc['focus'] ?? 0,
                          onChanged: (v) =>
                              setState(() => _mc['focus'] = v),
                          label: (ml['focus'] ?? '—').toString()),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                if (!widget.pg13)
                  _CardBox(
                    title: 'Affinity',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        sliderRow(
                            title: 'Intimacy',
                            max: 100,
                            value: _ac['intimacy'] ?? 50,
                            onChanged: (v) =>
                                setState(() => _ac['intimacy'] = v)),
                        sliderRow(
                            title: 'Physicality',
                            max: 100,
                            value: _ac['physicality'] ?? 50,
                            onChanged: (v) =>
                                setState(() => _ac['physicality'] = v)),
                      ],
                    ),
                  ),
                if (!widget.pg13) const SizedBox(height: 12),

                Row(
                  children: [
                    TextButton.icon(
                      onPressed: () async {
                        try {
                          await widget.onSave(_pc, _mc, _ac);
                          if (context.mounted) {
                            Navigator.of(context).pop();
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('Saved locally')));
                          }
                        } catch (e) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Save failed: $e')));
                        }
                      },
                      icon: const Icon(Icons.save),
                      label: const Text('Save'),
                      style: TextButton.styleFrom(foregroundColor: stroke),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () => Navigator.of(context).pop(),
                      style: TextButton.styleFrom(
                          foregroundColor: stroke,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8)),
                      icon: const Icon(Icons.check),
                      label: const Text('Close'),
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

class _CardBox extends StatelessWidget {
  final String title;
  final Widget child;
  const _CardBox({required this.title, required this.child});
  @override
  Widget build(BuildContext context) {
    final stroke = const Color(0xFFFFE7B0);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2119),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: stroke.withOpacity(0.6), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _GlowRingPainter extends CustomPainter {
  final double intensity;
  const _GlowRingPainter({required this.intensity});
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = min(size.width, size.height) / 2 - 6;

    final fillPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFFFE7B0).withOpacity(0.12 * (0.6 + 0.4 * intensity)),
          const Color(0xFFFFE7B0).withOpacity(0.00),
        ],
        stops: const [0.0, 1.0],
      ).createShader(Rect.fromCircle(center: c, radius: r + 14));
    canvas.drawCircle(c, r + 10, fillPaint);

    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..color = const Color(0xFFFFD38A)
          .withOpacity(0.65 * (0.55 + 0.45 * intensity));
    canvas.drawCircle(c, r - 8, ring);

    final halo = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 18
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 28)
      ..color = const Color(0xFFFFE7B0).withOpacity(0.28 * intensity);
    canvas.drawCircle(c, r, halo);
  }

  @override
  bool shouldRepaint(covariant _GlowRingPainter old) =>
      old.intensity != intensity;
}