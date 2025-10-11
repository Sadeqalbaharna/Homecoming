// lib/overlay/floating_kai.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/constants.dart';

class _FloatingKai extends StatefulWidget {
  const _FloatingKai();
  @override
  State<_FloatingKai> createState() => _FloatingKaiState();
}

// Public alias so other files can import it.
class FloatingKai extends _FloatingKai {
  const FloatingKai() : super();
}

enum _KaiMood { idle, attention, thinking, speaking }

class _FloatingKaiState extends State<_FloatingKai> with TickerProviderStateMixin {
  String _personaId = kPersonaKai;
  bool get _isClone => _personaId == kPersonaClone;

  _KaiMood _mood = _KaiMood.idle;
  late final AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(vsync: this, duration: kAttentionPulse)..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  String get _gif {
    switch (_mood) {
      case _KaiMood.speaking:  return kAvatarSpeakingGif;
      case _KaiMood.thinking:  return kAvatarThinkingGif;
      case _KaiMood.attention: return kAvatarAttentionGif;
      case _KaiMood.idle:
      default:                 return kAvatarIdleGif;
    }
  }

  @override
  Widget build(BuildContext context) {
    final double cw = kCanvasWidth;
    final double ch = kCanvasHeight;

    final double sprite = kSpriteSize;
    final double ringOuter = sprite + (kRingPadding * 2);
    final double ringRadius = ringOuter / 2;

    final Alignment spriteAlign = Alignment(0, kSpriteAlignY * 2 - 1);

    return SizedBox(
      width: cw,
      height: ch,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: spriteAlign,
            child: _SoftGlowCircle(
              radius: ringRadius,
              intensity: Tween<double>(begin: 0.5, end: 1.0).animate(
                CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
              ),
            ),
          ),
          Align(
            alignment: spriteAlign,
            child: _RingWidget(diameter: ringOuter, stroke: 2.0, color: kRingColor),
          ),
          Align(
            alignment: spriteAlign,
            child: SizedBox(
              width: sprite,
              height: sprite,
              child: ClipOval(
                child: Image.asset(
                  _gif,
                  gaplessPlayback: true,
                  filterQuality: FilterQuality.high,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.35),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text('Kai', style: TextStyle(color: Colors.white, fontSize: 12)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RingWidget extends StatelessWidget {
  final double diameter;
  final double stroke;
  final Color color;
  const _RingWidget({required this.diameter, required this.stroke, required this.color});

  @override
  Widget build(BuildContext context) {
    final double d = diameter;
    return SizedBox(
      width: d,
      height: d,
      child: CustomPaint(painter: _RingPainter(stroke, color)),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double stroke;
  final Color color;
  _RingPainter(this.stroke, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final Paint p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = color;
    final double r = math.min(size.width.toDouble(), size.height.toDouble()) / 2;
    canvas.drawCircle(Offset(size.width / 2, size.height / 2), r - stroke / 2, p);
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) {
    return oldDelegate.stroke != stroke || oldDelegate.color != color;
  }
}

class _SoftGlowCircle extends AnimatedWidget {
  final double radius;
  final Animation<double> intensity;
  const _SoftGlowCircle({required this.radius, required this.intensity}) : super(listenable: intensity);

  @override
  Widget build(BuildContext context) {
    final double r = radius;
    return SizedBox(
      width: r * 2,
      height: r * 2,
      child: ShaderMask(
        shaderCallback: (Rect bounds) {
          return const RadialGradient(
            center: Alignment.center,
            radius: 1.0,
            colors: [kGlowColor, Colors.transparent],
            stops: [0.0, 1.0],
          ).createShader(bounds);
        },
        blendMode: BlendMode.plus,
        child: Container(
          decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
        ),
      ),
    );
  }
}
