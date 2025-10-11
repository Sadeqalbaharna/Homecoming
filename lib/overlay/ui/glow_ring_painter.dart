// lib/features/shell/ui/glow_ring_painter.dart
part of floating_kai;

/* =============================== GLOW RING PAINTER ================================ */

class _GlowRingPainter extends CustomPainter {
  final double intensity;
  const _GlowRingPainter({required this.intensity});
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = min(size.width, size.height) / 2 - 8;

    // Softer, smaller fill and halo so no square shows
    final fillPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFFFE7B0).withOpacity(0.08 * (0.6 + 0.4 * intensity)),
        const Color(0xFFFFE7B0).withOpacity(0.00),
        ],
        stops: const [0.0, 1.0],
      ).createShader(Rect.fromCircle(center: c, radius: r));
    canvas.drawCircle(c, r - 6, fillPaint);

    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = const Color(0xFFFFD38A)
          .withOpacity(0.58 * (0.55 + 0.45 * intensity));
    canvas.drawCircle(c, r - 10, ring);

    final halo = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 24)
      ..color = const Color(0xFFFFE7B0).withOpacity(0.20 * intensity);
    canvas.drawCircle(c, r - 2, halo);
  }

  @override
  bool shouldRepaint(covariant _GlowRingPainter old) =>
      old.intensity != intensity;
}
