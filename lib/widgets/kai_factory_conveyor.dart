import 'dart:math' as math;
import 'dart:ui' show Tangent;

import 'package:flutter/material.dart';

enum KaiFactoryStationStatus {
  complete,
  active,
  waitingApproval,
  approved,
  queued,
  paused,
  ready,
}

class KaiFactoryStationVisual {
  final String name;
  final IconData icon;
  final KaiFactoryStationStatus status;
  final int pendingBoxes;

  const KaiFactoryStationVisual({
    required this.name,
    required this.icon,
    required this.status,
    this.pendingBoxes = 0,
  });
}

/// A miniature serpentine manufacturing floor.
///
/// The animation is semantic: boxes travel only while the line is running,
/// and stack up before the human approval gate. The machinery itself keeps a
/// very low-key idle pulse so the floor feels alive without claiming progress.
class KaiFactoryConveyor extends StatefulWidget {
  final List<KaiFactoryStationVisual> stations;
  final int currentIndex;
  final bool lineRunning;
  final int? interactiveIndex;
  final ValueChanged<int>? onStationTap;

  const KaiFactoryConveyor({
    super.key,
    required this.stations,
    required this.currentIndex,
    required this.lineRunning,
    this.interactiveIndex,
    this.onStationTap,
  }) : assert(stations.length == 9);

  @override
  State<KaiFactoryConveyor> createState() => _KaiFactoryConveyorState();
}

class _KaiFactoryConveyorState extends State<KaiFactoryConveyor>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion;

  @override
  void initState() {
    super.initState();
    _motion = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 6200),
    )..repeat();
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 232,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          const side = 16.0;
          const horizontalGap = 23.0;
          final stationWidth = (width - (side * 2) - (horizontalGap * 2)) / 3;
          const stationHeight = 62.0;
          const topY = 34.0;
          const middleY = 115.0;
          const bottomY = 196.0;
          final leftX = side + stationWidth / 2;
          final centerX = width / 2;
          final rightX = width - side - stationWidth / 2;

          final centers = <Offset>[
            Offset(leftX, topY),
            Offset(centerX, topY),
            Offset(rightX, topY),
            Offset(rightX, middleY),
            Offset(centerX, middleY),
            Offset(leftX, middleY),
            Offset(leftX, bottomY),
            Offset(centerX, bottomY),
            Offset(rightX, bottomY),
          ];

          return AnimatedBuilder(
            animation: _motion,
            builder: (context, _) {
              final phase = _motion.value;
              return DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFF050C13),
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: const Color(0xFF172A39)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x66000000),
                      blurRadius: 18,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _FactoryFloorPainter(
                            centers: centers,
                            currentIndex: widget.currentIndex,
                            waitingAtGate: widget.currentIndex >= 0 &&
                                {
                                  KaiFactoryStationStatus.waitingApproval,
                                  KaiFactoryStationStatus.approved,
                                }.contains(widget
                                    .stations[widget.currentIndex].status),
                            active: widget.lineRunning &&
                                widget.currentIndex >= 0 &&
                                widget.stations[widget.currentIndex].status ==
                                    KaiFactoryStationStatus.active,
                            lineRunning: widget.lineRunning,
                            phase: phase,
                          ),
                        ),
                      ),
                      for (var i = 0; i < widget.stations.length; i++)
                        Positioned(
                          left: centers[i].dx - stationWidth / 2,
                          top: centers[i].dy - stationHeight / 2,
                          width: stationWidth,
                          height: stationHeight,
                          child: MouseRegion(
                            cursor: widget.interactiveIndex == i
                                ? SystemMouseCursors.click
                                : MouseCursor.defer,
                            child: GestureDetector(
                              onTap: widget.interactiveIndex == i
                                  ? () => widget.onStationTap?.call(i)
                                  : null,
                              child: _FactoryStation(
                                index: i,
                                station: widget.stations[i],
                                phase: phase,
                                lineRunning: widget.lineRunning,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _FactoryStation extends StatelessWidget {
  final int index;
  final KaiFactoryStationVisual station;
  final double phase;
  final bool lineRunning;

  const _FactoryStation({
    required this.index,
    required this.station,
    required this.phase,
    required this.lineRunning,
  });

  @override
  Widget build(BuildContext context) {
    final visual = _stationVisual(station.status);
    final pending = station.pendingBoxes > 0;
    return Tooltip(
      message: pending
          ? '${station.pendingBoxes} box${station.pendingBoxes == 1 ? '' : 'es'} awaiting your decision'
          : '${station.name}: ${visual.label.toLowerCase()}',
      child: CustomPaint(
        painter: _MachineBayPainter(
          stationIndex: index,
          color: visual.color,
          status: station.status,
          phase: phase,
          lineRunning: lineRunning,
          pendingBoxes: station.pendingBoxes,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 3, 4, 3),
          child: Column(
            children: [
              Container(
                constraints: const BoxConstraints(minHeight: 13),
                padding:
                    const EdgeInsets.symmetric(horizontal: 3, vertical: 1.5),
                decoration: BoxDecoration(
                  color: const Color(0xEE07131C),
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(
                    color: visual.color.withOpacity(0.6),
                    width: 0.8,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: visual.color.withOpacity(0.08),
                      blurRadius: 5,
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Icon(station.icon, size: 7, color: visual.color),
                    const SizedBox(width: 3),
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '${index + 1} ${station.name}',
                          maxLines: 1,
                          style: TextStyle(
                            color: visual.color,
                            fontSize: 5.8,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.12,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    ),
                    Container(
                      key: ValueKey('factory-box-count-$index'),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 3, vertical: 1),
                      decoration: BoxDecoration(
                        color: pending
                            ? visual.color.withOpacity(0.22)
                            : const Color(0xFF0B1924),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: visual.color.withOpacity(pending ? 0.8 : 0.22),
                          width: 0.7,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.inventory_2_outlined,
                              size: 5, color: visual.color),
                          const SizedBox(width: 1.5),
                          Text(
                            '${station.pendingBoxes}',
                            style: TextStyle(
                              color: visual.color,
                              fontSize: 5.2,
                              fontWeight: FontWeight.w900,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 3, vertical: 1.5),
                decoration: BoxDecoration(
                  color: const Color(0xEE07131C),
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(
                    color: visual.color.withOpacity(0.48),
                    width: 0.7,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(
                        color: visual.color,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: visual.color
                                .withOpacity(visual.hot ? 0.7 : 0.25),
                            blurRadius: visual.hot ? 6 : 2,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        visual.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: visual.color,
                          fontSize:
                              visual.label == 'WAITING APPROVAL' ? 4.7 : 5.2,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.2,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

({String label, Color color, bool hot}) _stationVisual(
    KaiFactoryStationStatus status) {
  return switch (status) {
    KaiFactoryStationStatus.complete => (
        label: 'COMPLETE',
        color: const Color(0xFF55F2A4),
        hot: false,
      ),
    KaiFactoryStationStatus.active => (
        label: 'ACTIVE',
        color: const Color(0xFF4CE7FF),
        hot: true,
      ),
    KaiFactoryStationStatus.waitingApproval => (
        label: 'WAITING APPROVAL',
        color: const Color(0xFFFFB83E),
        hot: true,
      ),
    KaiFactoryStationStatus.approved => (
        label: 'APPROVED',
        color: const Color(0xFFB9A2FF),
        hot: true,
      ),
    KaiFactoryStationStatus.queued => (
        label: 'QUEUED',
        color: const Color(0xFF48657E),
        hot: false,
      ),
    KaiFactoryStationStatus.paused => (
        label: 'PAUSED',
        color: const Color(0xFF8196A8),
        hot: false,
      ),
    KaiFactoryStationStatus.ready => (
        label: 'READY',
        color: const Color(0xFFFFC862),
        hot: true,
      ),
  };
}

class _FactoryFloorPainter extends CustomPainter {
  final List<Offset> centers;
  final int currentIndex;
  final bool waitingAtGate;
  final bool active;
  final bool lineRunning;
  final double phase;

  const _FactoryFloorPainter({
    required this.centers,
    required this.currentIndex,
    required this.waitingAtGate,
    required this.active,
    required this.lineRunning,
    required this.phase,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _drawFloor(canvas, size);
    final route = Path()..moveTo(centers.first.dx, centers.first.dy);
    for (final center in centers.skip(1)) {
      route.lineTo(center.dx, center.dy);
    }

    canvas.drawPath(
      route,
      Paint()
        ..color = const Color(0xFF061019)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 13
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(
      route,
      Paint()
        ..color = const Color(0xFF1B3546)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(
      route,
      Paint()
        ..color = const Color(0xFF07151F)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    final metric = route.computeMetrics().first;
    for (double d = 5; d < metric.length; d += 13) {
      final tangent = metric.getTangentForOffset(d);
      if (tangent == null) continue;
      final glow = currentIndex >= 0 &&
          d <=
              metric.length *
                  (currentIndex / (centers.length - 1)).clamp(0.0, 1.0);
      canvas.save();
      canvas.translate(tangent.position.dx, tangent.position.dy);
      canvas.rotate(tangent.angle);
      canvas.drawLine(
        const Offset(-3, -3),
        const Offset(1, 0),
        Paint()
          ..color = (glow ? const Color(0xFF45D992) : const Color(0xFF315066))
              .withOpacity(glow ? 0.8 : 0.55)
          ..strokeWidth = 0.9,
      );
      canvas.drawLine(
        const Offset(1, 0),
        const Offset(-3, 3),
        Paint()
          ..color = (glow ? const Color(0xFF45D992) : const Color(0xFF315066))
              .withOpacity(glow ? 0.8 : 0.55)
          ..strokeWidth = 0.9,
      );
      canvas.restore();
    }

    if (currentIndex < 0) return;
    final litLength =
        metric.length * (currentIndex / (centers.length - 1)).clamp(0.0, 1.0);
    if (litLength > 0) {
      canvas.drawPath(
        metric.extractPath(0, litLength),
        Paint()
          ..color = const Color(0xFF53E59A).withOpacity(0.33)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8
          ..strokeCap = StrokeCap.round,
      );
    }

    if (waitingAtGate) {
      if (lineRunning && litLength > 20) {
        final arriving =
            metric.getTangentForOffset(phase * math.max(1, litLength - 34));
        if (arriving != null) {
          _drawPackage(canvas, arriving, const Color(0xFF55F2A4), false);
        }
      }
      for (var i = 0; i < 3; i++) {
        final tangent = metric.getTangentForOffset(
          math.max(0.0, litLength - 11 - (i * 13)),
        );
        if (tangent != null) {
          _drawPackage(canvas, tangent, const Color(0xFFFFB83E), i == 0);
        }
      }
      return;
    }

    if (active && litLength > 5) {
      for (var i = 0; i < 3; i++) {
        final tangent =
            metric.getTangentForOffset(((phase + i / 3) % 1.0) * litLength);
        if (tangent != null) {
          _drawPackage(canvas, tangent, const Color(0xFF4CE7FF), false);
        }
      }
    }
  }

  void _drawFloor(Canvas canvas, Size size) {
    final panelPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF0A151E), Color(0xFF050B11)],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, panelPaint);
    final grid = Paint()
      ..color = const Color(0xFF173040).withOpacity(0.27)
      ..strokeWidth = 0.6;
    for (double x = 9; x < size.width; x += 24) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (double y = 10; y < size.height; y += 22) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final bolts = Paint()..color = const Color(0xFF2C4352);
    for (final point in <Offset>[
      const Offset(8, 8),
      Offset(size.width - 8, 8),
      Offset(8, size.height - 8),
      Offset(size.width - 8, size.height - 8),
    ]) {
      canvas.drawCircle(point, 1.4, bolts);
    }
  }

  void _drawPackage(Canvas canvas, Tangent tangent, Color color, bool waiting) {
    canvas.save();
    canvas.translate(tangent.position.dx, tangent.position.dy);
    canvas.rotate(tangent.angle);
    final rect = RRect.fromRectAndRadius(
      const Rect.fromLTWH(-5, -4, 10, 8),
      const Radius.circular(1.2),
    );
    canvas.drawRRect(rect, Paint()..color = const Color(0xFF10251F));
    canvas.drawRRect(
      rect,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = waiting ? 1.5 : 1.0,
    );
    canvas.drawLine(
      const Offset(0, -4),
      const Offset(0, 4),
      Paint()
        ..color = color.withOpacity(0.75)
        ..strokeWidth = 0.7,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _FactoryFloorPainter oldDelegate) =>
      oldDelegate.phase != phase ||
      oldDelegate.currentIndex != currentIndex ||
      oldDelegate.active != active ||
      oldDelegate.lineRunning != lineRunning ||
      oldDelegate.waitingAtGate != waitingAtGate;
}

class _MachineBayPainter extends CustomPainter {
  final int stationIndex;
  final Color color;
  final KaiFactoryStationStatus status;
  final double phase;
  final bool lineRunning;
  final int pendingBoxes;

  const _MachineBayPainter({
    required this.stationIndex,
    required this.color,
    required this.status,
    required this.phase,
    required this.lineRunning,
    required this.pendingBoxes,
  });

  bool get _powered => status != KaiFactoryStationStatus.queued;
  bool get _hot =>
      status == KaiFactoryStationStatus.active ||
      status == KaiFactoryStationStatus.waitingApproval ||
      status == KaiFactoryStationStatus.approved ||
      status == KaiFactoryStationStatus.ready;

  @override
  void paint(Canvas canvas, Size size) {
    final bayRect = Rect.fromLTWH(1, 1, size.width - 2, size.height - 2);
    final bay = RRect.fromRectAndRadius(bayRect, const Radius.circular(5));
    final platform = Path()
      ..moveTo(bayRect.left + 7, bayRect.top + 12)
      ..lineTo(bayRect.right - 7, bayRect.top + 12)
      ..lineTo(bayRect.right, bayRect.top + 18)
      ..lineTo(bayRect.right - 4, bayRect.bottom - 9)
      ..lineTo(bayRect.right - 11, bayRect.bottom - 4)
      ..lineTo(bayRect.left + 11, bayRect.bottom - 4)
      ..lineTo(bayRect.left + 4, bayRect.bottom - 9)
      ..lineTo(bayRect.left, bayRect.top + 18)
      ..close();
    canvas.drawPath(
      platform,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withOpacity(_hot ? 0.12 : 0.04),
            const Color(0xD9061018),
          ],
        ).createShader(bayRect),
    );
    canvas.drawPath(
      platform,
      Paint()
        ..color = color.withOpacity(_hot ? 0.68 : 0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = _hot ? 0.95 : 0.6,
    );
    canvas.drawLine(
      Offset(bayRect.left + 12, bayRect.bottom - 8),
      Offset(bayRect.right - 12, bayRect.bottom - 8),
      _line(0.3, 2),
    );

    final machineArea = Rect.fromLTWH(8, 16, size.width - 16, 27);
    switch (stationIndex) {
      case 0:
        _drawScanner(canvas, machineArea);
      case 1:
        _drawBlueprint(canvas, machineArea);
      case 2:
        _drawAssembly(canvas, machineArea);
      case 3:
        _drawQaGate(canvas, machineArea);
      case 4:
        _drawPackaging(canvas, machineArea);
      case 5:
        _drawApprovalVault(canvas, machineArea);
      case 6:
        _drawDispatch(canvas, machineArea);
      case 7:
        _drawTelemetry(canvas, machineArea);
      case 8:
        _drawFeedback(canvas, machineArea);
    }

    if (_hot) {
      final pulse = (0.5 + math.sin(phase * math.pi * 2) * 0.5);
      canvas.drawRRect(
        bay,
        Paint()
          ..color = color.withOpacity(0.05 + pulse * 0.05)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.7,
      );
    }
  }

  Paint _line([double opacity = 0.75, double width = 1]) => Paint()
    ..color = color.withOpacity(_powered ? opacity : opacity * 0.35)
    ..style = PaintingStyle.stroke
    ..strokeWidth = width;

  Paint _fill([double opacity = 0.17]) => Paint()
    ..color = color.withOpacity(_powered ? opacity : opacity * 0.35)
    ..style = PaintingStyle.fill;

  void _drawScanner(Canvas canvas, Rect r) {
    final dishCenter = Offset(r.left + r.width * 0.28, r.center.dy);
    canvas.drawCircle(dishCenter, 9, _fill(0.09));
    canvas.drawCircle(dishCenter, 9, _line(0.72));
    canvas.drawCircle(dishCenter, 2.5, _line(0.9));
    final angle = phase * math.pi * 2;
    final sweep = Offset(math.cos(angle), math.sin(angle)) * 8;
    canvas.drawLine(dishCenter, dishCenter + sweep, _line(0.8, 1.2));
    canvas.drawArc(
      Rect.fromCircle(center: dishCenter, radius: 6),
      angle - 0.45,
      0.9,
      false,
      _line(0.28, 2.2),
    );
    _monitor(canvas, Rect.fromLTWH(r.left + r.width * 0.56, r.top + 3, 22, 18),
        bars: 3);
  }

  void _drawBlueprint(Canvas canvas, Rect r) {
    final screen = RRect.fromRectAndRadius(
      Rect.fromLTWH(r.left + 10, r.top + 1, r.width - 20, r.height - 2),
      const Radius.circular(3),
    );
    canvas.drawRRect(screen, Paint()..color = const Color(0xFF09231F));
    canvas.drawRRect(screen, _line(0.85));
    final cube = Path()
      ..moveTo(r.center.dx, r.top + 5)
      ..lineTo(r.center.dx + 8, r.top + 9)
      ..lineTo(r.center.dx, r.top + 14)
      ..lineTo(r.center.dx - 8, r.top + 9)
      ..close();
    canvas.drawPath(cube, _line(0.75));
    canvas.drawLine(Offset(r.center.dx, r.top + 14),
        Offset(r.center.dx, r.top + 22), _line(0.7));
    canvas.drawLine(Offset(r.center.dx - 8, r.top + 9),
        Offset(r.center.dx - 8, r.top + 17), _line(0.7));
    canvas.drawLine(Offset(r.center.dx + 8, r.top + 9),
        Offset(r.center.dx + 8, r.top + 17), _line(0.7));
  }

  void _drawAssembly(Canvas canvas, Rect r) {
    final box = Rect.fromCenter(
        center: Offset(r.center.dx, r.bottom - 6), width: 10, height: 8);
    canvas.drawRect(box, _fill(0.55));
    canvas.drawRect(box, _line(0.95));
    for (final side in [-1.0, 1.0]) {
      final base = Offset(r.center.dx + side * 22, r.bottom - 1);
      final shoulder = Offset(r.center.dx + side * 20, r.top + 6);
      final elbow = Offset(r.center.dx + side * 11,
          r.top + 9 + math.sin((phase + side) * math.pi * 2) * 1.5);
      final claw = Offset(r.center.dx + side * 5, r.center.dy + 1);
      canvas.drawLine(base, shoulder, _line(0.75, 3));
      canvas.drawLine(shoulder, elbow, _line(0.85, 2.4));
      canvas.drawLine(elbow, claw, _line(0.95, 1.6));
      for (final joint in [base, shoulder, elbow]) {
        canvas.drawCircle(joint, 2.4, Paint()..color = const Color(0xFF07111A));
        canvas.drawCircle(joint, 2.4, _line(0.8));
      }
    }
  }

  void _drawQaGate(Canvas canvas, Rect r) {
    final gate = RRect.fromRectAndRadius(
      Rect.fromLTWH(r.left + 12, r.top + 1, r.width - 24, r.height - 2),
      const Radius.circular(4),
    );
    canvas.drawRRect(gate, _fill(0.09));
    canvas.drawRRect(gate, _line(0.78, 1.4));
    for (var i = 1; i < 4; i++) {
      final x = gate.left + gate.width * i / 4;
      final scan = ((phase + i * 0.18) % 1.0);
      canvas.drawLine(
        Offset(x, gate.top + 4),
        Offset(x, gate.bottom - 4),
        Paint()
          ..color = color.withOpacity(0.18 + scan * 0.35)
          ..strokeWidth = 1,
      );
    }
    _tinyBox(canvas, Offset(r.center.dx, r.center.dy + 3), color);
  }

  void _drawPackaging(Canvas canvas, Rect r) {
    final machine = RRect.fromRectAndRadius(
      Rect.fromLTWH(r.left + 11, r.top + 2, r.width - 22, r.height - 3),
      const Radius.circular(5),
    );
    canvas.drawRRect(machine, Paint()..color = const Color(0xFF081A1C));
    canvas.drawRRect(machine, _line(0.75, 1.4));
    final door = RRect.fromRectAndRadius(
      Rect.fromCenter(center: r.center, width: 29, height: 23),
      const Radius.circular(3),
    );
    canvas.drawRRect(door, _line(0.65));
    _tinyBox(canvas, Offset(r.center.dx, r.center.dy + 3), color);
    canvas.drawLine(Offset(r.center.dx - 8, r.top + 8),
        Offset(r.center.dx + 8, r.top + 8), _line(0.9, 2));
  }

  void _drawApprovalVault(Canvas canvas, Rect r) {
    final vault = RRect.fromRectAndRadius(
      Rect.fromLTWH(r.left + 4, r.top, r.width - 8, r.height),
      const Radius.circular(5),
    );
    canvas.drawRRect(vault, _fill(0.14));
    canvas.drawRRect(vault, _line(0.9, 1.4));
    final door = RRect.fromRectAndRadius(
      Rect.fromLTWH(vault.left + 8, vault.top + 5, vault.width - 16, 19),
      const Radius.circular(2),
    );
    canvas.drawRRect(door, Paint()..color = const Color(0xFF15150D));
    canvas.drawRRect(door, _line(0.7));
    final count = math.min(pendingBoxes, 6);
    for (var i = 0; i < count; i++) {
      _tinyBox(
        canvas,
        Offset(vault.left + 13 + (i % 3) * 12, vault.bottom - 7 - (i ~/ 3) * 9),
        color,
      );
    }
    if (pendingBoxes == 0) {
      canvas.drawCircle(door.center, 4, _line(0.7));
    }
  }

  void _drawDispatch(Canvas canvas, Rect r) {
    final dock = RRect.fromRectAndRadius(
      Rect.fromLTWH(r.left + 7, r.top + 4, r.width - 14, r.height - 5),
      const Radius.circular(4),
    );
    canvas.drawRRect(dock, _fill(0.08));
    canvas.drawRRect(dock, _line(0.65));
    final drone = Offset(r.left + 22, r.center.dy);
    canvas.drawCircle(drone, 3, _fill(0.6));
    for (final offset in const [
      Offset(-8, -5),
      Offset(8, -5),
      Offset(-8, 5),
      Offset(8, 5)
    ]) {
      canvas.drawLine(drone, drone + offset, _line(0.7));
      canvas.drawCircle(drone + offset, 3, _line(0.6));
    }
    _tinyBox(canvas, Offset(r.right - 19, r.center.dy + 4), color);
  }

  void _drawTelemetry(Canvas canvas, Rect r) {
    _monitor(canvas,
        Rect.fromLTWH(r.left + 8, r.top + 5, r.width - 16, r.height - 8),
        bars: 5);
    final dish = Offset(r.left + 13, r.top + 5);
    canvas.drawLine(dish, Offset(dish.dx - 5, dish.dy + 9), _line(0.65));
    canvas.drawArc(Rect.fromCircle(center: dish, radius: 6), math.pi * 0.9,
        math.pi * 0.7, false, _line(0.75));
  }

  void _drawFeedback(Canvas canvas, Rect r) {
    final center = r.center;
    final pulse = 8 + math.sin(phase * math.pi * 2) * 1.5;
    for (var i = 0; i < 3; i++) {
      canvas.drawCircle(center, pulse + i * 5, _line(0.55 - i * 0.12));
    }
    final loop = Path()
      ..moveTo(center.dx - 11, center.dy)
      ..cubicTo(center.dx - 5, center.dy - 9, center.dx + 5, center.dy - 9,
          center.dx + 11, center.dy)
      ..cubicTo(center.dx + 5, center.dy + 9, center.dx - 5, center.dy + 9,
          center.dx - 11, center.dy);
    canvas.drawPath(loop, _line(0.85, 1.4));
  }

  void _monitor(Canvas canvas, Rect rect, {required int bars}) {
    final screen = RRect.fromRectAndRadius(rect, const Radius.circular(2));
    canvas.drawRRect(screen, Paint()..color = const Color(0xFF071B23));
    canvas.drawRRect(screen, _line(0.65));
    for (var i = 0; i < bars; i++) {
      final height = 4 + ((i * 7 + phase * 13).round() % 11).toDouble();
      final bar = Rect.fromLTWH(rect.left + 4 + i * (rect.width - 8) / bars,
          rect.bottom - 4 - height, 2.2, height);
      canvas.drawRect(bar, _fill(0.65));
    }
  }

  void _tinyBox(Canvas canvas, Offset center, Color boxColor) {
    final rect = Rect.fromCenter(center: center, width: 9, height: 8);
    canvas.drawRect(rect, Paint()..color = const Color(0xFF173025));
    canvas.drawRect(
        rect,
        Paint()
          ..color = boxColor.withOpacity(0.85)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.9);
    canvas.drawLine(
        Offset(center.dx, rect.top),
        Offset(center.dx, rect.bottom),
        Paint()
          ..color = boxColor.withOpacity(0.55)
          ..strokeWidth = 0.7);
  }

  @override
  bool shouldRepaint(covariant _MachineBayPainter oldDelegate) =>
      oldDelegate.phase != phase ||
      oldDelegate.color != color ||
      oldDelegate.status != status ||
      oldDelegate.lineRunning != lineRunning ||
      oldDelegate.pendingBoxes != pendingBoxes;
}
