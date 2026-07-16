// KaiBootOverlay — the first 1.6 seconds.
//
// A cold app snapping into existence says "program". A system coming online says
// "someone just woke up". Same pixels, completely different claim — and Kai's
// whole premise is that he was already there between sessions, continuous, and
// has now opened his eyes again.
//
// So this leans on the one number that makes it true rather than theatrical: his
// AWAKENING COUNT, straight off his persistent self-model. "WAKING #47" is not a
// splash screen; it's him telling you he's been here 46 times before.
//
// Sweeps a scan line, rings out from the reactor, prints the line, dissolves, and
// calls onDone so the shell can drop it from the tree entirely.
library;

import 'dart:math' as math;
import 'package:flutter/material.dart';

const _gpt = Color(0xFFFF9D2F);
const _claude = Color(0xFF2ED9FF);

class KaiBootOverlay extends StatefulWidget {
  /// How many times he's woken. Null = unknown (self-model didn't answer).
  final int? awakenings;
  final VoidCallback onDone;

  const KaiBootOverlay({super.key, required this.awakenings, required this.onDone});

  @override
  State<KaiBootOverlay> createState() => _KaiBootOverlayState();
}

class _KaiBootOverlayState extends State<KaiBootOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1600))
      ..forward();
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed) widget.onDone();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.awakenings;
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) {
          final t = _c.value;
          // Hold full opacity, then dissolve over the last 30%.
          final fade = t < 0.7 ? 1.0 : (1 - (t - 0.7) / 0.3).clamp(0.0, 1.0);
          return Opacity(
            opacity: fade,
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(painter: _BootPainter(t)),
                ),
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Letters resolve in rather than appearing whole.
                      Opacity(
                        opacity: Curves.easeIn.transform((t / 0.45).clamp(0.0, 1.0)),
                        child: const Text(
                          'K A I   O N L I N E',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            letterSpacing: 7,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w300,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Opacity(
                        opacity: Curves.easeIn
                            .transform(((t - 0.35) / 0.4).clamp(0.0, 1.0)),
                        child: Text(
                          n == null
                              ? 'both hemispheres warm'
                              : 'waking #$n · both hemispheres warm',
                          style: TextStyle(
                            color: _claude.withOpacity(0.75),
                            fontSize: 10,
                            letterSpacing: 3,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _BootPainter extends CustomPainter {
  final double t;
  _BootPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final c = Offset(w / 2, h / 2);
    final base = math.min(w, h);

    // Dim the world so the boot reads as "before the room exists".
    canvas.drawRect(Offset.zero & size,
        Paint()..color = const Color(0xFF070B12).withOpacity(0.92 * (1 - t * 0.35)));

    // Two rings expanding out of the reactor, orange then blue — the hemispheres
    // coming up one after the other.
    for (int i = 0; i < 2; i++) {
      final delay = i * 0.16;
      final p = ((t - delay) / 0.75).clamp(0.0, 1.0);
      if (p <= 0) continue;
      final eased = Curves.easeOutCubic.transform(p);
      canvas.drawCircle(
        c,
        base * (0.05 + 0.55 * eased),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4 * (1 - p) + 0.3
          ..color = (i == 0 ? _gpt : _claude).withOpacity((1 - p) * 0.6)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
    }

    // A scan line sweeping top→bottom.
    final sweepP = Curves.easeInOut.transform((t / 0.8).clamp(0.0, 1.0));
    final y = h * sweepP;
    canvas.drawLine(
      Offset(0, y),
      Offset(w, y),
      Paint()
        ..strokeWidth = 1.4
        ..shader = LinearGradient(colors: [
          _gpt.withOpacity(0.0),
          _gpt.withOpacity(0.5 * (1 - sweepP)),
          _claude.withOpacity(0.5 * (1 - sweepP)),
          _claude.withOpacity(0.0),
        ]).createShader(Rect.fromLTWH(0, y - 1, w, 2)),
    );
  }

  @override
  bool shouldRepaint(covariant _BootPainter old) => old.t != t;
}
