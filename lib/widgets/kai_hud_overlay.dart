// KaiHudOverlay — a JARVIS / Stark-desktop holographic HUD.
//
// Dual-house theme: ChatGPT = golden orange (left), Claude = fluorescent blue
// (right). Non-interactive, full-bleed: circuit traces, top tick-ruler, corner
// brackets, satellite reactors, and a central multi-ring reactor with a pulsing
// core, split tick gauges, and segmented + dashed rings.
library;

import 'dart:math' as math;
import 'package:flutter/material.dart';

const _gpt = Color(0xFFFF9D2F); // golden orange — ChatGPT
const _claude = Color(0xFF2ED9FF); // fluorescent blue — Claude

class KaiHudOverlay extends StatefulWidget {
  final double opacity;
  const KaiHudOverlay({super.key, this.opacity = 0.62});

  @override
  State<KaiHudOverlay> createState() => _KaiHudOverlayState();
}

class _KaiHudOverlayState extends State<KaiHudOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(seconds: 60))
      ..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Opacity(
        opacity: widget.opacity,
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, __) => CustomPaint(
            painter: _HudPainter(_c.value),
            size: Size.infinite,
          ),
        ),
      ),
    );
  }
}

class _HudPainter extends CustomPainter {
  final double t;
  _HudPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final cx = w / 2, cy = h / 2;
    final ang = t * 2 * math.pi;
    final base = math.min(w, h);
    final pulse = 0.5 + 0.5 * math.sin(t * 2 * math.pi * 3);

    _grid(canvas, size);
    _circuitTraces(canvas, size);
    _topRuler(canvas, size);
    _cornerBrackets(canvas, size);

    _miniReactor(canvas, Offset(w * 0.24, h * 0.30), base * 0.075, _gpt, ang);
    _miniReactor(canvas, Offset(w * 0.76, h * 0.70), base * 0.075, _claude, -ang);

    final r = base * 0.40;
    _splitTickRing(canvas, cx, cy, r, ang * 0.2);
    _segRing(canvas, cx, cy, r * 0.86, -ang * 0.35);
    _dashRing(canvas, cx, cy, r * 0.72, ang * 0.5, _claude, 56);
    _tickRing(canvas, cx, cy, r * 0.58, -ang * 0.28, _gpt);
    _circle(canvas, cx, cy, r * 0.46, _claude, 0.25);
    _core(canvas, cx, cy, r * 0.15 * (0.85 + 0.15 * pulse));
  }

  void _grid(Canvas canvas, Size size) {
    final p = Paint()
      ..color = _claude.withOpacity(0.045)
      ..strokeWidth = 1;
    const step = 46.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  void _circuitTraces(Canvas canvas, Size size) {
    final rnd = math.Random(42);
    final w = size.width, h = size.height;
    for (int i = 0; i < 34; i++) {
      final fromLeft = rnd.nextBool();
      final col = fromLeft ? _gpt : _claude;
      final line = Paint()
        ..color = col.withOpacity(0.16)
        ..strokeWidth = 1.1
        ..style = PaintingStyle.stroke;
      final node = Paint()..color = col.withOpacity(0.34);
      final y0 = rnd.nextDouble() * h;
      final start = fromLeft ? Offset(0, y0) : Offset(w, y0);
      final midX = fromLeft ? rnd.nextDouble() * w * 0.4 : w - rnd.nextDouble() * w * 0.4;
      final y1 = rnd.nextDouble() * h;
      canvas.drawPath(
        Path()
          ..moveTo(start.dx, start.dy)
          ..lineTo(midX, start.dy)
          ..lineTo(midX, y1),
        line,
      );
      canvas.drawRect(
          Rect.fromCenter(center: Offset(midX, start.dy), width: 3, height: 3), node);
      canvas.drawCircle(Offset(midX, y1), 1.6, node);
    }
  }

  void _topRuler(Canvas canvas, Size size) {
    final p = Paint()..strokeWidth = 1;
    const step = 26.0;
    int i = 0;
    for (double x = 30; x < size.width - 30; x += step, i++) {
      final long = i % 5 == 0;
      canvas.drawLine(Offset(x, 6), Offset(x, 6 + (long ? 11 : 6)),
          p..color = _claude.withOpacity(long ? 0.5 : 0.22));
    }
  }

  void _cornerBrackets(Canvas canvas, Size size) {
    const m = 16.0, len = 32.0;
    final w = size.width, h = size.height;
    Paint pen(Color c) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = c.withOpacity(0.6);
    final o = pen(_gpt), b = pen(_claude);
    canvas.drawLine(const Offset(m, m), const Offset(m + len, m), o);
    canvas.drawLine(const Offset(m, m), const Offset(m, m + len), o);
    canvas.drawLine(Offset(m, h - m), Offset(m + len, h - m), o);
    canvas.drawLine(Offset(m, h - m), Offset(m, h - m - len), o);
    canvas.drawLine(Offset(w - m, m), Offset(w - m - len, m), b);
    canvas.drawLine(Offset(w - m, m), Offset(w - m, m + len), b);
    canvas.drawLine(Offset(w - m, h - m), Offset(w - m - len, h - m), b);
    canvas.drawLine(Offset(w - m, h - m), Offset(w - m, h - m - len), b);
  }

  void _circle(Canvas canvas, double cx, double cy, double r, Color c, double op) {
    canvas.drawCircle(
        Offset(cx, cy),
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = c.withOpacity(op));
  }

  void _splitTickRing(Canvas canvas, double cx, double cy, double r, double rot) {
    final p = Paint()..strokeWidth = 1.2;
    for (int i = 0; i < 84; i++) {
      final a = rot + i * (2 * math.pi / 84);
      final long = i % 7 == 0;
      final r0 = r - (long ? 12 : 6);
      final col = math.cos(a) < 0 ? _gpt : _claude;
      canvas.drawLine(
        Offset(cx + math.cos(a) * r0, cy + math.sin(a) * r0),
        Offset(cx + math.cos(a) * r, cy + math.sin(a) * r),
        p..color = col.withOpacity(long ? 0.6 : 0.3),
      );
    }
  }

  void _segRing(Canvas canvas, double cx, double cy, double r, double rot) {
    final rect = Rect.fromCircle(center: Offset(cx, cy), radius: r);
    const n = 12;
    final seg = 2 * math.pi / n;
    for (int i = 0; i < n; i++) {
      final col = i.isEven ? _gpt : _claude;
      canvas.drawArc(
        rect, rot + i * seg, seg * 0.66, false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..color = col.withOpacity(0.5),
      );
    }
  }

  void _dashRing(Canvas canvas, double cx, double cy, double r, double rot, Color c, int n) {
    final rect = Rect.fromCircle(center: Offset(cx, cy), radius: r);
    final seg = (2 * math.pi) / n;
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = c.withOpacity(0.42);
    for (int i = 0; i < n; i++) {
      if (i.isOdd) continue;
      canvas.drawArc(rect, rot + i * seg, seg * 0.6, false, p);
    }
  }

  void _tickRing(Canvas canvas, double cx, double cy, double r, double rot, Color c) {
    final p = Paint()..strokeWidth = 1;
    for (int i = 0; i < 60; i++) {
      final a = rot + i * (2 * math.pi / 60);
      final long = i % 5 == 0;
      final r0 = r - (long ? 8 : 4);
      canvas.drawLine(
        Offset(cx + math.cos(a) * r0, cy + math.sin(a) * r0),
        Offset(cx + math.cos(a) * r, cy + math.sin(a) * r),
        p..color = c.withOpacity(long ? 0.55 : 0.28),
      );
    }
  }

  void _core(Canvas canvas, double cx, double cy, double r) {
    final blend = Color.lerp(_gpt, _claude, 0.5)!;
    canvas.drawCircle(
      Offset(cx, cy),
      r * 2.6,
      Paint()
        ..color = blend.withOpacity(0.18)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );
    canvas.drawCircle(
      Offset(cx, cy),
      r,
      Paint()
        ..shader = RadialGradient(colors: [Colors.white.withOpacity(0.9), blend.withOpacity(0.0)])
            .createShader(Rect.fromCircle(center: Offset(cx, cy), radius: r)),
    );
    _circle(canvas, cx, cy, r * 1.5, blend, 0.4);
  }

  void _miniReactor(Canvas canvas, Offset c, double r, Color col, double rot) {
    final rect = Rect.fromCircle(center: c, radius: r);
    for (int i = 0; i < 3; i++) {
      canvas.drawArc(rect, rot + i * (2 * math.pi / 3), 1.1, false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..strokeCap = StrokeCap.round
            ..color = col.withOpacity(0.4));
    }
    _tickRing(canvas, c.dx, c.dy, r * 0.66, -rot, col);
    canvas.drawCircle(c, r * 0.28, Paint()..color = col.withOpacity(0.3));
  }

  @override
  bool shouldRepaint(covariant _HudPainter old) => old.t != t;
}
