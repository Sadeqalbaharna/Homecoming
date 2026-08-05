// kai_activity_gears.dart — the "he's working" indicator.
//
// Two meshed gears in the terminal header: one for CHURN (self-repair passes),
// one for FACTORY (autonomous product runs). They spin while the mode is on,
// and they mesh — so they counter-rotate, because two gears turning the same
// way is the kind of detail that makes a UI feel fake.
//
// ── Why this replaced two switches ──────────────────────────────────────────
//
// The header used to carry a labelled Switch for each mode, which overflowed
// the sidebar by 8 pixels and told you nothing at a glance beyond on/off. A
// spinning gear answers the question you actually have when you walk past the
// screen — *is he doing something right now?* — without reading anything.
//
// They're still the control: tap a gear to toggle its mode. Indicator and
// switch in the same object, which is why the space problem went away rather
// than being rearranged.
//
// Deliberately: OFF gears are dark and perfectly still. No idle drift, no
// "breathing" animation. If it moves, something is running — otherwise the
// signal is worthless.
library;

import 'dart:math' as math;
import 'package:flutter/material.dart';

class KaiActivityGears extends StatefulWidget {
  final bool churnOn;
  final bool factoryOn;

  /// Mid-turn. Both gears speed up — the difference between "armed" and
  /// "actively grinding" is worth seeing.
  final bool busy;

  final VoidCallback? onToggleChurn;
  final VoidCallback? onToggleFactory;

  const KaiActivityGears({
    super.key,
    required this.churnOn,
    required this.factoryOn,
    this.busy = false,
    this.onToggleChurn,
    this.onToggleFactory,
  });

  @override
  State<KaiActivityGears> createState() => _KaiActivityGearsState();
}

class _KaiActivityGearsState extends State<KaiActivityGears>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  static const _churnColor = Color(0xFF7EE787);
  static const _factoryColor = Color(0xFFFFC862);
  static const _offColor = Color(0xFF3A4E62);

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    );
    _syncSpin();
  }

  @override
  void didUpdateWidget(covariant KaiActivityGears old) {
    super.didUpdateWidget(old);
    if (old.churnOn != widget.churnOn ||
        old.factoryOn != widget.factoryOn ||
        old.busy != widget.busy) {
      _syncSpin();
    }
  }

  /// Run only while something is actually on — an animation ticking behind a
  /// static UI is a battery cost with no information in it.
  void _syncSpin() {
    final anyOn = widget.churnOn || widget.factoryOn;
    if (!anyOn) {
      _c.stop();
      return;
    }
    _c.duration = Duration(milliseconds: widget.busy ? 1400 : 5200);
    if (!_c.isAnimating) _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _gear(
          on: widget.churnOn,
          color: _churnColor,
          teeth: 8,
          radius: 9,
          clockwise: true,
          onTap: widget.onToggleChurn,
          tip: widget.churnOn
              ? 'CHURN is on — he keeps taking small verified repair passes '
                  'until something needs your judgement.'
              : 'CHURN is off. Tap to let him self-repair.',
        ),
        // Negative gap so the teeth visually mesh.
        const SizedBox(width: 1),
        _gear(
          on: widget.factoryOn,
          color: _factoryColor,
          teeth: 7,
          radius: 7.5,
          clockwise: false,
          onTap: widget.onToggleFactory,
          tip: widget.factoryOn
              ? 'FACTORY is on — he can scout, build and prepare a listing. '
                  'He still cannot put anything on sale without you.'
              : 'FACTORY is off. Tap to let him work on products.',
        ),
      ],
    );
  }

  Widget _gear({
    required bool on,
    required Color color,
    required int teeth,
    required double radius,
    required bool clockwise,
    required String tip,
    VoidCallback? onTap,
  }) {
    return Tooltip(
      message: tip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius + 4),
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: AnimatedBuilder(
            animation: _c,
            builder: (_, __) {
              final t = on ? _c.value : 0.0;
              return CustomPaint(
                size: Size.square(radius * 2 + 4),
                painter: _GearPainter(
                  turns: clockwise ? t : -t,
                  teeth: teeth,
                  radius: radius,
                  color: on ? color : _offColor,
                  glow: on,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _GearPainter extends CustomPainter {
  final double turns;
  final int teeth;
  final double radius;
  final Color color;
  final bool glow;

  _GearPainter({
    required this.turns,
    required this.teeth,
    required this.radius,
    required this.color,
    required this.glow,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final angle = turns * 2 * math.pi;

    final body = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..color = color;

    if (glow) {
      canvas.drawCircle(
        c,
        radius * 0.86,
        Paint()
          ..color = color.withOpacity(0.16)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
    }

    // Hub
    canvas.drawCircle(c, radius * 0.34, body);
    // Rim
    canvas.drawCircle(c, radius * 0.66, body);

    // Teeth — short radial spokes beyond the rim.
    for (var i = 0; i < teeth; i++) {
      final a = angle + (i * 2 * math.pi / teeth);
      final inner = Offset(
        c.dx + math.cos(a) * radius * 0.66,
        c.dy + math.sin(a) * radius * 0.66,
      );
      final outer = Offset(
        c.dx + math.cos(a) * radius,
        c.dy + math.sin(a) * radius,
      );
      canvas.drawLine(inner, outer, body);
    }
  }

  @override
  bool shouldRepaint(covariant _GearPainter old) =>
      old.turns != turns ||
      old.color != color ||
      old.glow != glow ||
      old.radius != radius;
}
