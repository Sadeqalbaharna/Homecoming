// Kai's living cortex, rendered natively (no WebView).
//
//   • KaiBrainBackground — a giant, faint, non-interactive dual-hemisphere
//     neuron cloud behind the whole app. Left = ChatGPT (golden orange),
//     right = Claude (fluorescent blue). Pulses, glows, rotates, grows w/ mood.
//   • KaiVitals — Kai's live mood / personality / affinity as glowing
//     Stark-style concentric ring-gauges in the two house colors.
//
// Streams state from Firebase via KaiStateService. Pure Flutter CustomPaint.
library;

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../services/core/kai_state_service.dart';

// ── House palette ────────────────────────────────────────────────────────────
const kGpt = Color(0xFFFF9D2F); // golden orange — ChatGPT / left hemisphere
const kClaude = Color(0xFF2ED9FF); // fluorescent blue — Claude / right hemisphere

// ── Shared 3D geometry ───────────────────────────────────────────────────────

class _P {
  final double x, y, z;
  const _P(this.x, this.y, this.z);
  double dist(_P o) {
    final dx = x - o.x, dy = y - o.y, dz = z - o.z;
    return math.sqrt(dx * dx + dy * dy + dz * dz);
  }
}

class _Node {
  final _P p;
  final int lobe; // 0 = left/GPT/orange, 1 = right/Claude/blue
  const _Node(this.p, this.lobe);
}

class _Proj {
  final double x, y, z, persp;
  const _Proj(this.x, this.y, this.z, this.persp);
}

class _BrainGeom {
  final List<_Node> nodes;
  final List<List<int>> links;
  const _BrainGeom(this.nodes, this.links);
}

_BrainGeom _makeBrain() {
  final rnd = math.Random(7);
  final nodes = <_Node>[];
  _P lobe(double cx) {
    while (true) {
      final x = rnd.nextDouble() * 2 - 1;
      final y = rnd.nextDouble() * 2 - 1;
      final z = rnd.nextDouble() * 2 - 1;
      if (x * x / 0.85 + y * y / 1.2 + z * z / 1.0 <= 1) {
        return _P(x * 0.5 + cx, y * 0.62, z * 0.55);
      }
    }
  }

  for (var i = 0; i < 58; i++) {
    nodes.add(_Node(lobe(-0.46), 0));
  }
  for (var i = 0; i < 58; i++) {
    nodes.add(_Node(lobe(0.46), 1));
  }
  final links = <List<int>>[];
  for (var i = 0; i < nodes.length; i++) {
    final di = <MapEntry<int, double>>[];
    for (var j = 0; j < nodes.length; j++) {
      if (i == j) continue;
      di.add(MapEntry(j, nodes[i].p.dist(nodes[j].p)));
    }
    di.sort((a, b) => a.value.compareTo(b.value));
    links.add([di[0].key, di[1].key]);
  }
  return _BrainGeom(nodes, links);
}

// ── Background brain ─────────────────────────────────────────────────────────

class KaiBrainBackground extends StatefulWidget {
  final String personaId;
  final double opacity;
  final double radiusFactor;
  const KaiBrainBackground({
    super.key,
    required this.personaId,
    this.opacity = 0.26,
    this.radiusFactor = 0.5,
  });

  @override
  State<KaiBrainBackground> createState() => _KaiBrainBackgroundState();
}

class _KaiBrainBackgroundState extends State<KaiBrainBackground>
    with TickerProviderStateMixin {
  late final AnimationController _spin;
  late final AnimationController _pulse;
  late final _BrainGeom _geom;
  final _svc = KaiStateService();
  Map<String, int> _mood = const {};

  @override
  void initState() {
    super.initState();
    _geom = _makeBrain();
    _spin = AnimationController(vsync: this, duration: const Duration(seconds: 48))
      ..repeat();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 3200))
      ..repeat(reverse: true);
    _svc.moodStream(widget.personaId).listen((m) {
      if (mounted && m.isNotEmpty) setState(() => _mood = m);
    });
    _svc.getMood(widget.personaId).then((m) {
      if (mounted && m != null && m.isNotEmpty && _mood.isEmpty) setState(() => _mood = m);
    });
  }

  @override
  void dispose() {
    _spin.dispose();
    _pulse.dispose();
    super.dispose();
  }

  double _m(String k, [double d = 50]) => (_mood[k] ?? d).toDouble();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Opacity(
        opacity: widget.opacity,
        child: AnimatedBuilder(
          animation: Listenable.merge([_spin, _pulse]),
          builder: (_, __) => CustomPaint(
            painter: _BrainPainter(
              nodes: _geom.nodes,
              links: _geom.links,
              yaw: _spin.value * math.pi * 2,
              pitch: 0.18,
              pulse: _pulse.value,
              energy: _m('energy') / 100,
              valence: _m('valence') / 100,
              radiusFactor: widget.radiusFactor,
            ),
            size: Size.infinite,
          ),
        ),
      ),
    );
  }
}

// ── Vitals (ring gauges) ─────────────────────────────────────────────────────

class KaiVitals extends StatefulWidget {
  final String personaId;
  const KaiVitals({super.key, required this.personaId});

  @override
  State<KaiVitals> createState() => _KaiVitalsState();
}

class _KaiVitalsState extends State<KaiVitals> {
  final _svc = KaiStateService();
  Map<String, int> _mood = const {};
  Map<String, int> _personality = const {};
  Map<String, int> _affinity = const {};

  @override
  void initState() {
    super.initState();
    _svc.moodStream(widget.personaId).listen((m) {
      if (mounted && m.isNotEmpty) setState(() => _mood = m);
    });
    _svc.personalityStream(widget.personaId).listen((p) {
      if (mounted && p.isNotEmpty) setState(() => _personality = p);
    });
    _svc.affinityStream(widget.personaId).listen((a) {
      if (mounted && a.isNotEmpty) setState(() => _affinity = a);
    });
    _svc.getMood(widget.personaId).then((m) {
      if (mounted && m != null && m.isNotEmpty && _mood.isEmpty) setState(() => _mood = m);
    });
    _svc.getPersonality(widget.personaId).then((p) {
      if (mounted && p != null && p.isNotEmpty && _personality.isEmpty) setState(() => _personality = p);
    });
    _svc.getAffinity(widget.personaId).then((a) {
      if (mounted && a != null && a.isNotEmpty && _affinity.isEmpty) setState(() => _affinity = a);
    });
  }

  double _m(String k) => (_mood[k] ?? 50).toDouble();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _section('MOOD', kClaude),
          _wrap([
            _gauge('valence', _m('valence'), kClaude),
            _gauge('energy', _m('energy'), kClaude),
            _gauge('warmth', _m('warmth'), kGpt),
            _gauge('confid', _m('confidence'), kClaude),
            _gauge('play', _m('playfulness'), kGpt),
            _gauge('focus', _m('focus'), kClaude),
          ]),
          const SizedBox(height: 14),
          _section('PERSONALITY', kGpt),
          _wrap([
            for (final k in const ['extraversion', 'intuition', 'feeling', 'perceiving'])
              _gauge(k.substring(0, math.min(5, k.length)), (_personality[k] ?? 50).toDouble(), kGpt),
          ]),
          const SizedBox(height: 14),
          _section('AFFINITY', kGpt),
          _wrap([
            for (final k in const ['intimacy', 'physicality'])
              _gauge(k.substring(0, math.min(6, k.length)), (_affinity[k] ?? 50).toDouble(), kGpt),
          ]),
        ],
      ),
    );
  }

  Widget _wrap(List<Widget> children) =>
      Wrap(spacing: 6, runSpacing: 10, children: children);

  Widget _section(String t, Color color) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          children: [
            Text(t,
                style: TextStyle(
                    color: color,
                    fontSize: 10,
                    letterSpacing: 2.2,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w700,
                    shadows: [Shadow(color: color.withOpacity(0.7), blurRadius: 8)])),
            const SizedBox(width: 8),
            Expanded(child: Container(height: 1, color: color.withOpacity(0.28))),
          ],
        ),
      );

  Widget _gauge(String label, double value, Color color) {
    return SizedBox(
      width: 72,
      child: Column(
        children: [
          SizedBox(
            width: 64,
            height: 64,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: const Size(64, 64),
                  painter: _GaugePainter(value / 100, color),
                ),
                Text(
                  '${value.round()}',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'monospace',
                    shadows: [Shadow(color: color.withOpacity(0.9), blurRadius: 10)],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: Colors.white.withOpacity(0.62),
                fontSize: 8,
                letterSpacing: 1.2,
                fontFamily: 'monospace'),
          ),
        ],
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double pct;
  final Color color;
  _GaugePainter(this.pct, this.color);

  static const _start = 3 * math.pi / 4;
  static const _sweep = 3 * math.pi / 2;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - 5;
    final rect = Rect.fromCircle(center: c, radius: r);

    final tick = Paint()..strokeWidth = 1;
    for (int i = 0; i <= 24; i++) {
      final a = _start + _sweep * (i / 24);
      final long = i % 6 == 0;
      final r0 = r - (long ? 6 : 3);
      canvas.drawLine(
        Offset(c.dx + math.cos(a) * r0, c.dy + math.sin(a) * r0),
        Offset(c.dx + math.cos(a) * r, c.dy + math.sin(a) * r),
        tick..color = color.withOpacity(long ? 0.4 : 0.2),
      );
    }

    canvas.drawArc(
      rect, _start, _sweep, false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5
        ..color = Colors.white.withOpacity(0.08),
    );

    final vw = _sweep * pct.clamp(0.0, 1.0);
    canvas.drawArc(
      rect, _start, vw, false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round
        ..color = color.withOpacity(0.85)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawArc(
      rect, _start, vw, false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..color = color,
    );

    canvas.drawCircle(
      c, r * 0.6,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = color.withOpacity(0.22),
    );
  }

  @override
  bool shouldRepaint(covariant _GaugePainter old) =>
      old.pct != pct || old.color != color;
}

// ── Brain painter ────────────────────────────────────────────────────────────

class _BrainPainter extends CustomPainter {
  final List<_Node> nodes;
  final List<List<int>> links;
  final double yaw, pitch, pulse, energy, valence, radiusFactor;

  _BrainPainter({
    required this.nodes,
    required this.links,
    required this.yaw,
    required this.pitch,
    required this.pulse,
    required this.energy,
    required this.valence,
    this.radiusFactor = 0.30,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    final grow = 0.86 + 0.28 * ((valence + energy) / 2);
    final breathe = 1 + (0.05 + 0.05 * energy) * math.sin(pulse * math.pi * 2);
    final R = math.min(size.width, size.height) * radiusFactor * grow * breathe;

    final gptCol = Color.lerp(kGpt, Colors.white, 0.16 * energy)!;
    final clCol = Color.lerp(kClaude, Colors.white, 0.16 * energy)!;

    // twin halos, one per hemisphere
    final haloR = R * 1.8;
    canvas.drawCircle(
      Offset(cx - R * 0.5, cy),
      haloR,
      Paint()
        ..shader = RadialGradient(colors: [gptCol.withOpacity(0.14 + 0.12 * energy), Colors.transparent])
            .createShader(Rect.fromCircle(center: Offset(cx - R * 0.5, cy), radius: haloR)),
    );
    canvas.drawCircle(
      Offset(cx + R * 0.5, cy),
      haloR,
      Paint()
        ..shader = RadialGradient(colors: [clCol.withOpacity(0.14 + 0.12 * energy), Colors.transparent])
            .createShader(Rect.fromCircle(center: Offset(cx + R * 0.5, cy), radius: haloR)),
    );

    final cyw = math.cos(yaw), syw = math.sin(yaw);
    final cxp = math.cos(pitch), sxp = math.sin(pitch);
    final proj = List<_Proj>.filled(nodes.length, const _Proj(0, 0, 0, 0));
    const fov = 3.2;
    for (var i = 0; i < nodes.length; i++) {
      final p = nodes[i].p;
      final x1 = p.x * cyw + p.z * syw;
      final z1 = -p.x * syw + p.z * cyw;
      final y1 = p.y;
      final y2 = y1 * cxp - z1 * sxp;
      final z2 = y1 * sxp + z1 * cxp;
      final persp = fov / (fov - z2);
      proj[i] = _Proj(cx + x1 * persp * R, cy + y2 * persp * R, z2, persp);
    }

    for (var i = 0; i < links.length; i++) {
      for (final j in links[i]) {
        final a = proj[i], b = proj[j];
        final depth = ((a.z + b.z) / 2 + 1) / 2;
        final alpha = (0.05 + 0.24 * depth) * (0.6 + 0.4 * pulse);
        final col = nodes[i].lobe == 0 ? gptCol : clCol;
        canvas.drawLine(
          Offset(a.x, a.y),
          Offset(b.x, b.y),
          Paint()
            ..color = col.withOpacity(alpha.clamp(0.0, 0.55))
            ..strokeWidth = 0.9,
        );
      }
    }

    final order = List<int>.generate(nodes.length, (i) => i)
      ..sort((a, b) => proj[a].z.compareTo(proj[b].z));
    for (final i in order) {
      final pr = proj[i];
      final depth = (pr.z + 1) / 2;
      final col = nodes[i].lobe == 0 ? gptCol : clCol;
      final r = (1.4 + 3.2 * depth) * pr.persp;
      final a = 0.28 + 0.7 * depth;
      canvas.drawCircle(
        Offset(pr.x, pr.y),
        r * 2.6,
        Paint()
          ..color = col.withOpacity(0.12 * a)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
      canvas.drawCircle(
        Offset(pr.x, pr.y),
        r,
        Paint()..color = Color.lerp(col, Colors.white, 0.3 * depth)!.withOpacity(a),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BrainPainter old) => true;
}
