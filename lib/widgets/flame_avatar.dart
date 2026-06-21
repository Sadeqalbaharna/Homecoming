// flame_avatar.dart
//
// Flickering blue flame widget for Kai's background mode.
//
// The flame is rendered with a layered CustomPainter using radial gradients:
//   outer corona  →  deep blue (#0A1628)
//   mid flame     →  electric blue (#1E6FFF)
//   inner core    →  cyan-white (#A0E8FF / white)
//
// Three independent AnimationControllers drive the flicker:
//   _breathe  — slow scale pulse  (2.0s, ease-in-out)
//   _flicker  — fast opacity jitter (0.18s, linear, sine)
//   _waver    — horizontal sway    (1.2s, ease-in-out, asymmetric)
//
// To swap in a custom animation (Lottie, Rive, frame sequence):
//   1. Pass `customBuilder` to the constructor.
//   2. The builder receives the current flicker value (0.0–1.0) as input.
//   3. When `customBuilder` is non-null, the custom painter is NOT drawn.

library;

import 'package:flutter/material.dart';

typedef FlameBuilder = Widget Function(BuildContext ctx, double flicker);

class FlameAvatar extends StatefulWidget {
  /// Diameter of the flame widget.
  final double size;

  /// If non-null, renders this widget instead of the built-in painter.
  /// Receives a flicker value in [0, 1] for animation sync.
  final FlameBuilder? customBuilder;

  /// Whether the flame should pulse urgently (e.g. pending message).
  final bool urgent;

  const FlameAvatar({
    super.key,
    this.size = 120,
    this.customBuilder,
    this.urgent = false,
  });

  @override
  State<FlameAvatar> createState() => _FlameAvatarState();
}

class _FlameAvatarState extends State<FlameAvatar>
    with TickerProviderStateMixin {
  // ── Animation controllers ──────────────────────────────────────────────────
  late final AnimationController _breatheCtrl;
  late final AnimationController _flickerCtrl;
  late final AnimationController _waverCtrl;
  late final AnimationController _urgentCtrl;

  late final Animation<double> _breatheAnim;
  late final Animation<double> _flickerAnim;
  late final Animation<double> _waverAnim;
  late final Animation<double> _urgentAnim;

  // Sine-modulated flicker value exposed to custom builders
  double _flickerValue = 1.0;

  @override
  void initState() {
    super.initState();

    // Slow breathing scale
    _breatheCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _breatheAnim = Tween<double>(begin: 0.92, end: 1.08)
        .chain(CurveTween(curve: Curves.easeInOut))
        .animate(_breatheCtrl);

    // Fast flicker opacity
    _flickerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    )..repeat(reverse: true);
    _flickerAnim = Tween<double>(begin: 0.70, end: 1.0)
        .chain(CurveTween(curve: Curves.easeIn))
        .animate(_flickerCtrl);

    // Side sway
    _waverCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _waverAnim = Tween<double>(begin: -4.0, end: 4.0)
        .chain(CurveTween(curve: Curves.easeInOut))
        .animate(_waverCtrl);

    // Urgent pulse (faster, larger scale)
    _urgentCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _urgentAnim = Tween<double>(begin: 1.0, end: 1.3)
        .chain(CurveTween(curve: Curves.easeOut))
        .animate(_urgentCtrl);

    if (widget.urgent) _urgentCtrl.repeat(reverse: true);

    _flickerCtrl.addListener(() {
      _flickerValue = _flickerAnim.value;
    });
  }

  @override
  void didUpdateWidget(FlameAvatar old) {
    super.didUpdateWidget(old);
    if (widget.urgent && !old.urgent) {
      _urgentCtrl.repeat(reverse: true);
    } else if (!widget.urgent && old.urgent) {
      _urgentCtrl.stop();
      _urgentCtrl.value = 0;
    }
  }

  @override
  void dispose() {
    _breatheCtrl.dispose();
    _flickerCtrl.dispose();
    _waverCtrl.dispose();
    _urgentCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(
          [_breatheCtrl, _flickerCtrl, _waverCtrl, _urgentCtrl]),
      builder: (ctx, _) {
        final scale = _breatheAnim.value *
            (widget.urgent ? _urgentAnim.value : 1.0);
        final opacity = _flickerAnim.value;
        final sway = _waverAnim.value;

        return Transform.translate(
          offset: Offset(sway, 0),
          child: Transform.scale(
            scale: scale,
            child: Opacity(
              opacity: opacity,
              child: SizedBox(
                width: widget.size,
                height: widget.size * 1.35, // flames are taller than wide
                child: widget.customBuilder != null
                    ? widget.customBuilder!(ctx, _flickerValue)
                    : _BuiltInFlame(size: widget.size),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── Built-in flame painter ─────────────────────────────────────────────────

class _BuiltInFlame extends StatelessWidget {
  final double size;
  const _BuiltInFlame({required this.size});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size * 1.35),
      painter: _FlamePainter(),
    );
  }
}

class _FlamePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final h = size.height;

    // ── Layer 1: Outer blue corona ─────────────────────────────────────────
    _drawFlameLayer(
      canvas,
      cx: cx,
      baseY: h,
      tipY: h * 0.05,
      widthFactor: 0.95,
      gradient: RadialGradient(
        center: Alignment.bottomCenter,
        radius: 0.85,
        colors: [
          const Color(0xFF1E6FFF).withOpacity(0.6),
          const Color(0xFF0A2A6B).withOpacity(0.2),
          Colors.transparent,
        ],
        stops: const [0.0, 0.65, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, size.width, h)),
    );

    // ── Layer 2: Mid electric blue ─────────────────────────────────────────
    _drawFlameLayer(
      canvas,
      cx: cx,
      baseY: h,
      tipY: h * 0.18,
      widthFactor: 0.65,
      gradient: RadialGradient(
        center: const Alignment(0, 0.3),
        radius: 0.7,
        colors: [
          const Color(0xFF3D9BFF),
          const Color(0xFF1E6FFF).withOpacity(0.8),
          Colors.transparent,
        ],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(Rect.fromLTWH(0, h * 0.1, size.width, h * 0.9)),
    );

    // ── Layer 3: Inner cyan core ───────────────────────────────────────────
    _drawFlameLayer(
      canvas,
      cx: cx,
      baseY: h,
      tipY: h * 0.33,
      widthFactor: 0.38,
      gradient: RadialGradient(
        center: const Alignment(0, 0.5),
        radius: 0.6,
        colors: [
          Colors.white,
          const Color(0xFFA0E8FF),
          const Color(0xFF3DCDFF).withOpacity(0.6),
          Colors.transparent,
        ],
        stops: const [0.0, 0.25, 0.6, 1.0],
      ).createShader(Rect.fromLTWH(cx * 0.3, h * 0.25, cx * 1.4, h * 0.75)),
    );

    // ── Base glow: blue embers at base ─────────────────────────────────────
    final basePaint = Paint()
      ..shader = RadialGradient(
        center: Alignment.bottomCenter,
        radius: 0.5,
        colors: [
          const Color(0xFF5AB0FF).withOpacity(0.7),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(cx - size.width * 0.4, h * 0.75,
          size.width * 0.8, h * 0.25));
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(cx, h * 0.92),
          width: size.width * 0.7,
          height: h * 0.12),
      basePaint,
    );
  }

  void _drawFlameLayer(
    Canvas canvas, {
    required double cx,
    required double baseY,
    required double tipY,
    required double widthFactor,
    required Shader gradient,
  }) {
    final w = cx * widthFactor;
    final path = Path();

    // Flame silhouette using cubic bezier curves
    path.moveTo(cx, tipY); // tip
    path.cubicTo(
      cx + w * 0.55, tipY + (baseY - tipY) * 0.3,  // right upper ctrl
      cx + w * 0.9,  tipY + (baseY - tipY) * 0.7,  // right lower ctrl
      cx + w,        baseY,                           // right base
    );
    // Base arc
    path.quadraticBezierTo(cx, baseY + (baseY - tipY) * 0.04, cx - w, baseY);
    path.cubicTo(
      cx - w * 0.9,  tipY + (baseY - tipY) * 0.7,  // left lower ctrl
      cx - w * 0.55, tipY + (baseY - tipY) * 0.3,  // left upper ctrl
      cx,            tipY,                            // back to tip
    );
    path.close();

    canvas.drawPath(path, Paint()..shader = gradient);
  }

  @override
  bool shouldRepaint(_FlamePainter old) => true; // always repaint for animation
}

// ── Convenience: small floating version with a circular backdrop ─────────────

class FlameAvatarCompact extends StatelessWidget {
  final double size;
  final bool urgent;
  final VoidCallback? onTap;
  final FlameBuilder? customBuilder;

  const FlameAvatarCompact({
    super.key,
    this.size = 72,
    this.urgent = false,
    this.onTap,
    this.customBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Dark glass backdrop
          Container(
            width: size * 1.3,
            height: size * 1.3,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black.withOpacity(0.45),
              border: Border.all(
                color: const Color(0xFF1E6FFF).withOpacity(0.4),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF1E6FFF).withOpacity(0.25),
                  blurRadius: 20,
                  spreadRadius: 4,
                ),
              ],
            ),
          ),
          FlameAvatar(size: size, urgent: urgent, customBuilder: customBuilder),
          // Urgent dot
          if (urgent)
            Positioned(
              top: 4,
              right: 4,
              child: Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  color: Color(0xFF00D4FF),
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
