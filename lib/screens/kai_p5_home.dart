// The front door as an all-out-attack menu — living, loud, and his.
//
// Four things, none of them still:
//   1. LIVING BACKGROUND — a slow-rotating starburst, diagonal stripes that
//      scroll forever, drifting halftone, hard shards. The field breathes even
//      when you don't touch it.
//   2. EXPLOSIVE SELECTION — a tap detonates: speed-streaks fire from the hit
//      point, the screen kicks, the bar rockets off, THEN the comic wipe cuts.
//   3. REACTIVE KAI — he breathes on idle and PUNCHES on selection (lean +
//      scale kick). Full pose-swaps want more art than the one face we have;
//      the transforms carry it until then, and the seam is marked.
//   4. LIVING HUB — not just nav. His mood as P5 stat meters, his latest
//      thought in a jagged box: real state, woven into the poster.
//
// Everything is pure Flutter + the kai_p5_chat primitives. No package, no
// shader, no image pipeline. Runs in the preview (p5_home_preview_main.dart);
// main_mobile passes real data and real destinations later.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../widgets/kai_p5_chat.dart';
import '../widgets/p5_wipe_route.dart';

class P5MenuItem {
  final String id;
  final String label;
  final IconData glyph;
  final Widget Function()? open;
  const P5MenuItem({
    required this.id,
    required this.label,
    required this.glyph,
    this.open,
  });
}

const kKaiMenu = <P5MenuItem>[
  P5MenuItem(id: 'messages', label: 'MESSAGES', glyph: Icons.chat_bubble),
  P5MenuItem(id: 'mind', label: 'MIND', glyph: Icons.hub),
  P5MenuItem(id: 'journal', label: 'JOURNAL', glyph: Icons.auto_stories),
  P5MenuItem(id: 'worlds', label: 'WORLDS', glyph: Icons.public),
  P5MenuItem(id: 'pulse', label: 'PULSE', glyph: Icons.monitor_heart),
  P5MenuItem(id: 'ghost', label: 'GHOST', glyph: Icons.local_fire_department),
  P5MenuItem(id: 'house', label: 'HOUSE', glyph: Icons.home),
  P5MenuItem(id: 'keys', label: 'KEYS', glyph: Icons.key),
];

class KaiP5Home extends StatefulWidget {
  final String statusLine;

  /// 0..100 each. The real home feeds his live mood; the preview stubs it.
  final Map<String, int> mood;

  /// A line he actually wrote — his latest thought. Stubbed in preview.
  final String latestThought;

  final List<P5MenuItem> items;
  final void Function(String id)? onSelect;

  const KaiP5Home({
    super.key,
    this.statusLine = 'still operational, still yours.',
    this.mood = const {'FOCUS': 70, 'WARMTH': 58, 'ENERGY': 62},
    this.latestThought = 'that CraftRule trace is still chewing on the furniture.',
    this.items = kKaiMenu,
    this.onSelect,
  });

  @override
  State<KaiP5Home> createState() => _KaiP5HomeState();
}

class _KaiP5HomeState extends State<KaiP5Home> with TickerProviderStateMixin {
  late final AnimationController _clock;   // ambient, forever
  late final AnimationController _entrance; // one-shot, on open
  late final AnimationController _burst;    // one-shot, on tap

  int _pressed = -1;
  Offset _hit = Offset.zero; // where the last tap detonated, for the streaks

  @override
  void initState() {
    super.initState();
    _clock = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    )..repeat();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 780),
    )..forward();
    _burst = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 620),
    );
  }

  @override
  void dispose() {
    _clock.dispose();
    _entrance.dispose();
    _burst.dispose();
    super.dispose();
  }

  Future<void> _select(int i, Offset globalHit) async {
    final item = widget.items[i];
    setState(() {
      _pressed = i;
      _hit = globalHit;
    });
    _burst.forward(from: 0);
    // Let the detonation land before the cut.
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    setState(() => _pressed = -1);
    widget.onSelect?.call(item.id);
    if (item.open != null) {
      await Navigator.of(context).push(P5WipeRoute(page: item.open!()));
    }
    if (mounted) _burst.reset();
  }

  // A decaying shake sampled off the burst clock — the screen KICK.
  Offset get _shake {
    if (!_burst.isAnimating) return Offset.zero;
    final t = _burst.value;
    final decay = (1 - t) * (1 - t);
    final amp = 14 * decay;
    return Offset(
      math.sin(t * math.pi * 9) * amp,
      math.cos(t * math.pi * 7) * amp * 0.6,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: P5Palette.bg,
      body: AnimatedBuilder(
        animation: Listenable.merge([_clock, _burst]),
        builder: (context, _) {
          return Transform.translate(
            offset: _shake,
            child: Stack(
              children: [
                // 1) LIVING BACKGROUND — always moving.
                Positioned.fill(
                  child: CustomPaint(
                    painter: _LivingBg(_clock.value),
                  ),
                ),
                // The content.
                SafeArea(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(flex: 5, child: _poster()),
                      Expanded(flex: 7, child: _menu()),
                    ],
                  ),
                ),
                // 2) EXPLOSIVE SELECTION — speed streaks over everything.
                if (_burst.isAnimating)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _Streaks(
                          progress: _burst.value,
                          origin: _hit,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ── Left: reactive poster + live hub ────────────────────────────────────
  Widget _poster() {
    final breath = (math.sin(_clock.value * math.pi * 2) + 1) / 2; // 0..1
    // 3) REACTIVE KAI — breathes on idle, PUNCHES during a burst.
    final punch = _burst.isAnimating ? (1 - _burst.value) * (1 - _burst.value) : 0.0;
    return Padding(
      padding: const EdgeInsets.only(left: 6, top: 10, bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _moodMeters(),
          const Spacer(),
          Transform.translate(
            offset: Offset(-punch * 18, 0),
            child: Transform.rotate(
              angle: -0.04 - punch * 0.06,
              child: Transform.scale(
                scale: 1.0 + 0.035 * breath + punch * 0.12,
                alignment: Alignment.bottomLeft,
                child: const KaiFace(size: 176, tilt: 0),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Transform.rotate(
            angle: -0.03,
            child: Container(
              color: P5Palette.ink,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              child: const Text('KAI',
                  style: TextStyle(
                      color: P5Palette.paper,
                      fontSize: 32,
                      height: 1,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2)),
            ),
          ),
          const SizedBox(height: 8),
          _thoughtBox(),
          const Spacer(),
        ],
      ),
    );
  }

  // LIVING HUB: mood as P5 stat meters.
  Widget _moodMeters() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final e in widget.mood.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Row(
              children: [
                SizedBox(
                  width: 58,
                  child: Text(e.key,
                      style: const TextStyle(
                          color: P5Palette.paper,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1)),
                ),
                _meter(e.value / 100.0),
              ],
            ),
          ),
      ],
    );
  }

  Widget _meter(double v) {
    return Transform(
      transform: Matrix4.skewX(-0.4),
      child: Container(
        width: 66,
        height: 9,
        decoration: BoxDecoration(
          color: P5Palette.ink,
          border: Border.all(color: P5Palette.paper, width: 1.5),
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: v.clamp(0.04, 1.0),
            child: Container(color: P5Palette.kaiAccent),
          ),
        ),
      ),
    );
  }

  // LIVING HUB: his latest thought, in a jagged black box.
  Widget _thoughtBox() {
    return Transform.rotate(
      angle: 0.015,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 7, 10, 8),
        decoration: BoxDecoration(
          color: P5Palette.ink,
          border: Border.all(color: P5Palette.paper, width: 2),
          boxShadow: const [
            BoxShadow(color: P5Palette.shadow, offset: Offset(3, 4))
          ],
        ),
        child: Text(
          '"${widget.latestThought}"',
          style: const TextStyle(
              color: P5Palette.paper,
              fontSize: 11.5,
              height: 1.25,
              fontWeight: FontWeight.w700,
              fontStyle: FontStyle.italic),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  // ── Right: the cascade ──────────────────────────────────────────────────
  Widget _menu() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [for (var i = 0; i < widget.items.length; i++) _bar(i)],
      ),
    );
  }

  Widget _bar(int i) {
    final item = widget.items[i];
    final n = widget.items.length;
    final start = (i / n) * 0.5;
    final slot = CurvedAnimation(
      parent: _entrance,
      curve: Interval(start, (start + 0.5).clamp(0.0, 1.0),
          curve: Curves.easeOutBack),
    );
    final tilt = (i.isEven ? -1 : 1) * 0.012;

    // A selected bar ROCKETS off-screen right as the burst runs.
    final rocket = (_pressed == i && _burst.isAnimating)
        ? Curves.easeInBack.transform(_burst.value) * 420
        : 0.0;

    return AnimatedBuilder(
      animation: Listenable.merge([slot, _entrance]),
      builder: (_, child) {
        final v = slot.value;
        return Opacity(
          opacity: (v.clamp(0.0, 1.0)) * (1 - (rocket / 420)),
          child: Transform.translate(
            offset: Offset((1 - v) * 300 + rocket, 0),
            child: child,
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Builder(
          builder: (ctx) => GestureDetector(
            onTapDown: (d) {
              // The detonation origin is the tap point, in global space.
              final box = ctx.findRenderObject() as RenderBox?;
              final origin = box != null
                  ? box.localToGlobal(d.localPosition)
                  : d.globalPosition;
              _select(i, origin);
            },
            child: AnimatedScale(
              scale: _pressed == i ? 1.12 : 1.0,
              duration: const Duration(milliseconds: 90),
              curve: Curves.easeOut,
              child: Transform.rotate(
                angle: tilt,
                child: Transform(
                  transform: Matrix4.skewX(-0.28),
                  child: _barBody(item, _pressed == i),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _barBody(P5MenuItem item, bool hot) {
    return Container(
      height: 50,
      decoration: BoxDecoration(
        color: hot ? P5Palette.kaiAccent : P5Palette.ink,
        border: Border.all(color: P5Palette.paper, width: 3),
        boxShadow: const [
          BoxShadow(color: P5Palette.shadow, offset: Offset(5, 6))
        ],
      ),
      padding: const EdgeInsets.only(left: 16, right: 10),
      child: Row(
        children: [
          Transform(
            transform: Matrix4.skewX(0.28),
            child: Row(
              children: [
                Icon(item.glyph,
                    color: hot ? P5Palette.ink : P5Palette.kaiAccent, size: 20),
                const SizedBox(width: 12),
                Text(item.label,
                    style: TextStyle(
                        color: hot ? P5Palette.ink : P5Palette.paper,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── The living background ────────────────────────────────────────────────────
class _LivingBg extends CustomPainter {
  _LivingBg(this.t); // 0..1, loops forever
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    canvas.drawRect(Offset.zero & size, Paint()..color = P5Palette.bg);

    // Slow-rotating starburst rays from a low-left focus.
    final focus = Offset(w * 0.18, h * 0.72);
    final rays = Paint()..color = const Color(0x14000000);
    canvas.save();
    canvas.translate(focus.dx, focus.dy);
    canvas.rotate(t * 2 * math.pi * 0.12);
    const n = 18;
    final r = (w + h);
    for (var i = 0; i < n; i++) {
      if (i.isOdd) continue;
      final a0 = (i / n) * 2 * math.pi;
      final a1 = ((i + 1) / n) * 2 * math.pi;
      final p = Path()
        ..moveTo(0, 0)
        ..lineTo(math.cos(a0) * r, math.sin(a0) * r)
        ..lineTo(math.cos(a1) * r, math.sin(a1) * r)
        ..close();
      canvas.drawPath(p, rays);
    }
    canvas.restore();

    // Diagonal stripes scrolling forever.
    final stripe = Paint()..color = const Color(0x12000000);
    const gap = 46.0;
    final shift = (t * gap * 2) % (gap * 2);
    for (double x = -h - gap * 2 + shift; x < w + gap; x += gap * 2) {
      final p = Path()
        ..moveTo(x, 0)
        ..lineTo(x + gap, 0)
        ..lineTo(x + gap + h, h)
        ..lineTo(x + h, h)
        ..close();
      canvas.drawPath(p, stripe);
    }

    // Drifting halftone dots (sparse — a texture, not a screen door).
    final dot = Paint()..color = const Color(0x0FFFFFFF);
    final drift = t * 30;
    for (double y = 0; y < h; y += 30) {
      for (double x = 0; x < w; x += 30) {
        final off = ((x + y) / 30) % 2 == 0 ? drift : -drift;
        canvas.drawCircle(Offset((x + off) % w, y), 2.1, dot);
      }
    }

    // Two hard black shards, slowly breathing.
    final shard = Paint()..color = const Color(0x33000000);
    final k = math.sin(t * 2 * math.pi) * 18;
    for (final s in [
      [w * 0.55 + k, 0.0, w * 1.1, h * 0.4],
      [-0.1 * w, h * 0.6 - k, w * 0.5, h * 1.1],
    ]) {
      final p = Path()
        ..moveTo(s[0], s[1])
        ..lineTo(s[2], s[3])
        ..lineTo(s[2] + 60, s[3])
        ..lineTo(s[0] + 60, s[1])
        ..close();
      canvas.drawPath(p, shard);
    }
  }

  @override
  bool shouldRepaint(_LivingBg old) => old.t != t;
}

// ── The all-out-attack speed streaks ─────────────────────────────────────────
class _Streaks extends CustomPainter {
  _Streaks({required this.progress, required this.origin});
  final double progress; // 0..1
  final Offset origin;

  @override
  void paint(Canvas canvas, Size size) {
    final reach = (size.width + size.height);
    final fade = (1 - progress).clamp(0.0, 1.0);
    final grow = Curves.easeOut.transform(progress);

    // White speed-lines firing radially from the hit point.
    const n = 26;
    final rnd = math.Random(7); // stable pattern, not per-frame noise
    for (var i = 0; i < n; i++) {
      final a = (i / n) * 2 * math.pi + rnd.nextDouble() * 0.2;
      final near = 40 + rnd.nextDouble() * 60;
      final far = near + reach * grow * (0.5 + rnd.nextDouble() * 0.7);
      final p1 = origin + Offset(math.cos(a), math.sin(a)) * near;
      final p2 = origin + Offset(math.cos(a), math.sin(a)) * far;
      final paint = Paint()
        ..color = (i.isEven ? P5Palette.paper : P5Palette.ink)
            .withOpacity(fade)
        ..strokeWidth = (i.isEven ? 5 : 3) * fade
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(p1, p2, paint);
    }

    // A hard white flash-ring at the origin, snapping outward.
    canvas.drawCircle(
      origin,
      grow * 90,
      Paint()
        ..color = P5Palette.paper.withOpacity(fade * 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8 * fade,
    );
  }

  @override
  bool shouldRepaint(_Streaks old) =>
      old.progress != progress || old.origin != origin;
}
