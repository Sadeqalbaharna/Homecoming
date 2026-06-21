// background_mode_screen.dart
//
// Kai's "background mode" — minimal, low-stress presence on the screen.
//
// What's active in this mode:
//   ✅  FlameAvatar — flickering blue flame, ~0% GPU vs full frame animation
//   ✅  VoiceActivationService — "hey kai!" wake word still works
//   ✅  FCM notifications — proactive messages still arrive (system-level)
//   ✅  Pending message badge — blue dot on flame if a message is waiting
//
// What's paused:
//   ⏸   Frame-sequence avatar animations
//   ⏸   Glow / idle ticker
//   ⏸   Heavy services (brain extraction, drift, etc. — already fire-and-forget)
//
// Transitions:
//   • Tap flame  →  onExpand()  (caller shows full UI)
//   • Wake word  →  onWakeWord(transcript)  (caller handles sending to Kai)
//   • Proactive  →  onProactive(message)

library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../widgets/flame_avatar.dart';
import '../services/voice/voice_activation_service.dart';
import '../services/core/proactive_service.dart';

class BackgroundModeScreen extends StatefulWidget {
  final String personaId;
  final VoidCallback onExpand;
  final void Function(String transcript) onWakeWord;
  final void Function(String message) onProactive;

  const BackgroundModeScreen({
    super.key,
    required this.personaId,
    required this.onExpand,
    required this.onWakeWord,
    required this.onProactive,
  });

  @override
  State<BackgroundModeScreen> createState() => _BackgroundModeScreenState();
}

class _BackgroundModeScreenState extends State<BackgroundModeScreen>
    with SingleTickerProviderStateMixin {
  StreamSubscription<String>? _wakeWordSub;
  bool _hasPending = false;
  bool _justHeard = false; // brief flash when wake word is detected
  Timer? _heardTimer;

  // Periodic proactive check while in background mode
  Timer? _proactiveTimer;

  @override
  void initState() {
    super.initState();
    _startWakeWordListener();
    _checkPendingMessage();
    // Re-check for proactive messages every 2 minutes while in background
    _proactiveTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      _checkPendingMessage();
    });
  }

  @override
  void dispose() {
    _wakeWordSub?.cancel();
    _heardTimer?.cancel();
    _proactiveTimer?.cancel();
    super.dispose();
  }

  // ── Wake word ──────────────────────────────────────────────────────────────

  void _startWakeWordListener() {
    // Subscribe to the singleton stream — Porcupine is already running if the
    // user has voice activation enabled. We never force-start it here; that
    // decision belongs to the user via the API Keys / settings screen.
    _wakeWordSub = VoiceActivationService().onWakeWordDetected.listen((transcript) {
      _onWakeDetected(transcript);
    });
  }

  void _onWakeDetected(String transcript) {
    if (!mounted) return;
    setState(() => _justHeard = true);
    _heardTimer?.cancel();
    _heardTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _justHeard = false);
      // Hand transcript to caller (will expand + send to Kai)
      widget.onWakeWord(transcript);
    });
  }

  // ── Proactive messages ─────────────────────────────────────────────────────

  Future<void> _checkPendingMessage() async {
    final pending =
        await ProactiveService().checkPendingMessage(widget.personaId);
    if (!mounted) return;

    if (pending != null) {
      setState(() => _hasPending = true);
      // If auto-surface is desired, call onProactive immediately.
      // Currently we just badge the flame; expand is still user-driven.
    } else {
      setState(() => _hasPending = false);
    }
  }

  // ── UI ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Subtle dark-blue ambient gradient behind the flame
          Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 1.2,
                colors: [
                  const Color(0xFF050D1A),
                  Colors.black,
                ],
              ),
            ),
          ),

          // Particle field (very subtle moving dots)
          const _AmbientParticles(),

          // Centered flame
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Wake-word flash ring
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                  padding: EdgeInsets.all(_justHeard ? 12 : 0),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: _justHeard
                        ? [
                            BoxShadow(
                              color: const Color(0xFF00D4FF).withOpacity(0.5),
                              blurRadius: 40,
                              spreadRadius: 20,
                            ),
                          ]
                        : [],
                  ),
                  child: FlameAvatarCompact(
                    size: 96,
                    urgent: _hasPending,
                    onTap: _onTap,
                  ),
                ),

                const SizedBox(height: 28),

                // Status line
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 400),
                  child: _justHeard
                      ? _statusText('Listening…', const Color(0xFF00D4FF),
                          key: const ValueKey('heard'))
                      : _hasPending
                          ? _statusText('Kai has a message for you',
                              const Color(0xFF3D9BFF),
                              key: const ValueKey('pending'))
                          : _statusText('Background mode  •  tap to expand',
                              Colors.white24,
                              key: const ValueKey('idle')),
                ),

                const SizedBox(height: 48),

                // Expand hint
                GestureDetector(
                  onTap: widget.onExpand,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: const Color(0xFF1E6FFF).withOpacity(0.3),
                      ),
                      color: const Color(0xFF1E6FFF).withOpacity(0.07),
                    ),
                    child: const Text(
                      'Open Kai',
                      style: TextStyle(
                        color: Color(0xFF3D9BFF),
                        fontSize: 14,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Top-right: exit background mode
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: IconButton(
                  icon: const Icon(Icons.open_in_full,
                      color: Colors.white24, size: 20),
                  onPressed: widget.onExpand,
                  tooltip: 'Exit background mode',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _onTap() {
    if (_hasPending) {
      // Surface the message immediately
      ProactiveService()
          .checkPendingMessage(widget.personaId)
          .then((pending) async {
        if (pending != null) {
          await ProactiveService()
              .markDelivered(widget.personaId, pending.id);
          widget.onProactive(pending.message);
        }
      });
    }
    widget.onExpand();
  }

  Widget _statusText(String text, Color color, {required Key key}) {
    return Text(
      text,
      key: key,
      style: TextStyle(
        color: color,
        fontSize: 13,
        letterSpacing: 0.5,
      ),
    );
  }
}

// ── Ambient particle field ─────────────────────────────────────────────────

class _AmbientParticles extends StatefulWidget {
  const _AmbientParticles();

  @override
  State<_AmbientParticles> createState() => _AmbientParticlesState();
}

class _AmbientParticlesState extends State<_AmbientParticles>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  static const _count = 18;
  final _particles = <_Particle>[];

  @override
  void initState() {
    super.initState();
    // Seed deterministic particles
    final rng = _DeterministicRng(seed: 42);
    for (int i = 0; i < _count; i++) {
      _particles.add(_Particle(
        x: rng.next(),
        y: rng.next(),
        radius: 0.8 + rng.next() * 1.6,
        speed: 0.00008 + rng.next() * 0.00015,
        phase: rng.next() * 6.28,
      ));
    }

    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 60),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (ctx, _) {
        return CustomPaint(
          painter: _ParticlePainter(
              particles: _particles, t: _ctrl.value * 6.28 * 60),
          size: Size.infinite,
        );
      },
    );
  }
}

class _Particle {
  final double x, y, radius, speed, phase;
  const _Particle(
      {required this.x,
      required this.y,
      required this.radius,
      required this.speed,
      required this.phase});
}

class _ParticlePainter extends CustomPainter {
  final List<_Particle> particles;
  final double t;
  const _ParticlePainter({required this.particles, required this.t});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFF1E6FFF).withOpacity(0.12);
    for (final p in particles) {
      final x = (p.x + p.speed * t) % 1.0;
      final y = p.y;
      final opacity = 0.05 + 0.1 * ((1 + _sin(p.phase + t * 0.4)) / 2);
      canvas.drawCircle(
        Offset(x * size.width, y * size.height),
        p.radius,
        Paint()
          ..color = const Color(0xFF3D9BFF).withOpacity(opacity),
      );
    }
  }

  double _sin(double x) {
    // approximate sin without importing dart:math
    // (dart:math is available but this keeps the painter import-free)
    double s = x % 6.2832;
    if (s < 0) s += 6.2832;
    // four-term Taylor is accurate enough for opacity flicker
    final x2 = s - 3.14159;
    return -x2 * (1 - x2 * x2 / 6);
  }

  @override
  bool shouldRepaint(_ParticlePainter old) => old.t != t;
}

class _DeterministicRng {
  int _state;
  _DeterministicRng({required int seed}) : _state = seed;

  double next() {
    _state = (_state * 1664525 + 1013904223) & 0xFFFFFFFF;
    return (_state & 0x7FFFFFFF) / 0x7FFFFFFF;
  }
}
