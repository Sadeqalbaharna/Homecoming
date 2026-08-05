// KaiProjectCard — live project progress as an interactive pie.
//
// Each slice is one frozen-goal layer. Click a slice and the evidence/intent
// opens as a floating ticket instead of eating permanent dashboard space.
library;

import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../services/core/kai_project_service.dart';

class KaiProjectCard extends StatefulWidget {
  final String personaId;
  final String projectId;

  const KaiProjectCard({
    super.key,
    required this.personaId,
    this.projectId = KaiProjectService.smarterId,
  });

  @override
  State<KaiProjectCard> createState() => _KaiProjectCardState();
}

class _KaiProjectCardState extends State<KaiProjectCard> {
  int? _selectedLayer;

  @override
  void didUpdateWidget(covariant KaiProjectCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.projectId != widget.projectId) {
      _selectedLayer = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<KaiProject?>(
      stream: KaiProjectService.instance.watch(widget.personaId, widget.projectId),
      builder: (context, snap) {
        final p = snap.data;
        if (p == null) {
          return _Shell(
            child: Center(
              child: Text(
                'PROJECT OFFLINE',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.42),
                  fontSize: 10,
                  letterSpacing: 1.3,
                ),
              ),
            ),
          );
        }

        final layers = p.layers;
        final selected = layers.where((l) => l.n == _selectedLayer).firstOrNull;
        final accent = _projectAccent(p.id);
        final pct = (p.completion * 100).round();

        return _Shell(
          accent: accent,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          p.name.toUpperCase(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.1,
                          ),
                        ),
                      ),
                      Text(
                        '$pct%',
                        style: TextStyle(
                          color: accent,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.8,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${p.doneCount}/${layers.length} complete • tap a slice',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.46),
                      fontSize: 8.8,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final chartSize = math.min(
                          constraints.maxWidth,
                          constraints.maxHeight,
                        );
                        return Center(
                          child: SizedBox(
                            width: chartSize,
                            height: chartSize,
                            child: _ProjectPie(
                              project: p,
                              selectedLayer: _selectedLayer,
                              accent: accent,
                              onSelected: (layer) {
                                setState(() {
                                  _selectedLayer =
                                      _selectedLayer == layer.n ? null : layer.n;
                                });
                              },
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 6),
                  _MiniLegend(project: p, selectedLayer: _selectedLayer),
                ],
              ),
              if (selected != null)
                Positioned(
                  left: -6,
                  right: -6,
                  bottom: 22,
                  child: _LayerTicket(
                    layer: selected,
                    accent: _sliceColor(selected.n),
                    onClose: () => setState(() => _selectedLayer = null),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Shell extends StatelessWidget {
  final Widget child;
  final Color accent;

  const _Shell({
    required this.child,
    this.accent = const Color(0xFF7CFFEA),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.035),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withOpacity(0.22)),
        boxShadow: [
          BoxShadow(
            color: accent.withOpacity(0.07),
            blurRadius: 18,
            spreadRadius: 0.5,
          ),
        ],
      ),
      padding: const EdgeInsets.all(10),
      child: child,
    );
  }
}

class _ProjectPie extends StatelessWidget {
  final KaiProject project;
  final int? selectedLayer;
  final Color accent;
  final ValueChanged<KaiLayer> onSelected;

  const _ProjectPie({
    required this.project,
    required this.selectedLayer,
    required this.accent,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (details) {
        final layer = _hitTest(details.localPosition, context.size ?? Size.zero);
        if (layer != null) onSelected(layer);
      },
      child: CustomPaint(
        painter: _ProjectPiePainter(
          project: project,
          selectedLayer: selectedLayer,
          accent: accent,
        ),
        child: Center(
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black.withOpacity(0.62),
              border: Border.all(color: Colors.white.withOpacity(0.10)),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${(project.completion * 100).round()}%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.8,
                  ),
                ),
                Text(
                  'overall',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.42),
                    fontSize: 8,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  KaiLayer? _hitTest(Offset local, Size size) {
    if (project.layers.isEmpty || size.shortestSide <= 0) return null;
    final center = Offset(size.width / 2, size.height / 2);
    final delta = local - center;
    final radius = size.shortestSide / 2;
    final distance = delta.distance;
    if (distance < radius * 0.34 || distance > radius) return null;

    var angle = math.atan2(delta.dy, delta.dx) + math.pi / 2;
    if (angle < 0) angle += math.pi * 2;

    final sweep = math.pi * 2 / project.layers.length;
    final idx = (angle / sweep).floor().clamp(0, project.layers.length - 1);
    return project.layers[idx];
  }
}

class _ProjectPiePainter extends CustomPainter {
  final KaiProject project;
  final int? selectedLayer;
  final Color accent;

  _ProjectPiePainter({
    required this.project,
    required this.selectedLayer,
    required this.accent,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final layers = project.layers;
    if (layers.isEmpty) return;

    final center = Offset(size.width / 2, size.height / 2);
    final baseRadius = size.shortestSide / 2 - 4;
    final stroke = math.max(18.0, size.shortestSide * 0.18);
    final rect = Rect.fromCircle(center: center, radius: baseRadius - stroke / 2);
    final sweep = math.pi * 2 / layers.length;
    const gap = 0.018;

    final bg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt
      ..color = Colors.white.withOpacity(0.06);

    final fg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.butt
      ..strokeWidth = stroke;

    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withOpacity(0.08);

    for (var i = 0; i < layers.length; i++) {
      final layer = layers[i];
      final start = -math.pi / 2 + i * sweep + gap;
      final usableSweep = sweep - gap * 2;
      final selected = layer.n == selectedLayer;
      final color = _sliceColor(layer.n);
      final progressSweep = usableSweep * (layer.honestProgress / 100);
      final drawRect = selected
          ? Rect.fromCircle(center: center, radius: baseRadius - stroke / 2 + 2)
          : rect;

      canvas.drawArc(drawRect, start, usableSweep, false, bg);
      fg
        ..strokeWidth = selected ? stroke + 5 : stroke
        ..shader = SweepGradient(
          startAngle: start,
          endAngle: start + usableSweep,
          colors: [color.withOpacity(0.95), color.withOpacity(0.42)],
        ).createShader(drawRect);
      canvas.drawArc(drawRect, start, progressSweep, false, fg);
      fg.shader = null;

      final labelAngle = start + usableSweep / 2;
      final labelOffset = Offset(
        center.dx + math.cos(labelAngle) * (baseRadius - stroke / 2),
        center.dy + math.sin(labelAngle) * (baseRadius - stroke / 2),
      );
      _drawLabel(canvas, labelOffset, layer.n.toString(), selected, color);
    }

    canvas.drawCircle(center, baseRadius, outline);
    canvas.drawCircle(center, baseRadius - stroke, outline);

    final pulse = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = accent.withOpacity(0.20);
    canvas.drawCircle(center, baseRadius + 2, pulse);
  }

  void _drawLabel(
    Canvas canvas,
    Offset offset,
    String text,
    bool selected,
    Color color,
  ) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: selected ? Colors.black : Colors.white.withOpacity(0.86),
          fontSize: selected ? 10.5 : 9,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final r = Rect.fromCenter(
      center: offset,
      width: selected ? 20 : 17,
      height: selected ? 20 : 17,
    );
    canvas.drawOval(
      r,
      Paint()
        ..color = selected ? color : Colors.black.withOpacity(0.55)
        ..style = PaintingStyle.fill,
    );
    canvas.drawOval(
      r,
      Paint()
        ..color = color.withOpacity(selected ? 0.95 : 0.40)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    tp.paint(canvas, offset - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _ProjectPiePainter oldDelegate) =>
      oldDelegate.project != project ||
      oldDelegate.selectedLayer != selectedLayer ||
      oldDelegate.accent != accent;
}

class _LayerTicket extends StatelessWidget {
  final KaiLayer layer;
  final Color accent;
  final VoidCallback onClose;

  const _LayerTicket({
    required this.layer,
    required this.accent,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final lastEvidence = layer.evidence.isEmpty ? 'No evidence logged yet.' : layer.evidence.last;
    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF071014).withOpacity(0.96),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: accent.withOpacity(0.55)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.55),
              blurRadius: 28,
              offset: const Offset(0, 12),
            ),
            BoxShadow(color: accent.withOpacity(0.15), blurRadius: 22),
          ],
        ),
        padding: const EdgeInsets.all(10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accent.withOpacity(0.95),
                  ),
                  child: Text(
                    '${layer.n}',
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    layer.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  '${layer.honestProgress}%',
                  style: TextStyle(
                    color: accent,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(width: 4),
                InkWell(
                  onTap: onClose,
                  borderRadius: BorderRadius.circular(999),
                  child: Padding(
                    padding: const EdgeInsets.all(3),
                    child: Icon(
                      Icons.close_rounded,
                      size: 14,
                      color: Colors.white.withOpacity(0.55),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              layer.intent,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withOpacity(0.72),
                fontSize: 9.2,
                height: 1.3,
              ),
            ),
            if (layer.checklist.isNotEmpty) ...[
              const SizedBox(height: 7),
              Text(
                'checklist proven: ${layer.checklistProven}/${layer.checklist.length}',
                style: TextStyle(
                  color: accent.withOpacity(0.82),
                  fontSize: 8.4,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                layer.checklist.map((i) {
                  final status = layer.checklistStatus[i] ?? ChecklistStatus.pending;
                  return '• [${status.label}] $i';
                }).join('\n'),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.52),
                  fontSize: 8.1,
                  height: 1.18,
                ),
              ),
            ],
            const SizedBox(height: 7),
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.045),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withOpacity(0.07)),
              ),
              padding: const EdgeInsets.all(8),
              child: Text(
                'last: $lastEvidence',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.50),
                  fontSize: 8.6,
                  height: 1.25,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniLegend extends StatelessWidget {
  final KaiProject project;
  final int? selectedLayer;

  const _MiniLegend({required this.project, required this.selectedLayer});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: project.layers.map((l) {
        final selected = l.n == selectedLayer;
        final color = _sliceColor(l.n);
        return AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: selected ? 20 : 14,
          height: 5,
          decoration: BoxDecoration(
            color: color.withOpacity(selected ? 0.95 : 0.35),
            borderRadius: BorderRadius.circular(999),
          ),
        );
      }).toList(),
    );
  }
}

Color _sliceColor(int n) {
  const colors = [
    Color(0xFF7CFFEA),
    Color(0xFF8EA7FF),
    Color(0xFFFFC857),
    Color(0xFFFF6B9A),
    Color(0xFFB967FF),
    Color(0xFF65FF8F),
    Color(0xFFFF8A5B),
    Color(0xFF58D1FF),
  ];
  return colors[(n - 1).abs() % colors.length];
}

Color _projectAccent(String id) {
  if (id == KaiProjectService.sentienceId) return const Color(0xFFB967FF);
  return const Color(0xFF7CFFEA);
}
