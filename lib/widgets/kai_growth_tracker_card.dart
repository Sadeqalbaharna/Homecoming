import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/core/kai_growth_tracker_service.dart';

typedef KaiGrowthLoader = Future<KaiGrowthSnapshot> Function(int days);

class KaiGrowthTrackerCard extends StatefulWidget {
  const KaiGrowthTrackerCard({super.key, this.loader});

  final KaiGrowthLoader? loader;

  @override
  State<KaiGrowthTrackerCard> createState() => _KaiGrowthTrackerCardState();
}

class _KaiGrowthTrackerCardState extends State<KaiGrowthTrackerCard> {
  late Future<KaiGrowthSnapshot> _future;

  KaiGrowthLoader get _loader =>
      widget.loader ?? (days) => KaiGrowthTrackerService().load(days: days);

  @override
  void initState() {
    super.initState();
    _future = _loader(28);
  }

  void _refresh() => setState(() => _future = _loader(28));

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<KaiGrowthSnapshot>(
      future: _future,
      builder: (context, snapshot) {
        return _GrowthCardShell(
          onTap: snapshot.hasData
              ? () => _showDetail(context, snapshot.data!)
              : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.trending_up,
                      size: 15, color: Color(0xFF64E5CC)),
                  const SizedBox(width: 7),
                  const Expanded(
                    child: Text(
                      'GROWTH // SOCIAL + SALES',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: .8,
                      ),
                    ),
                  ),
                  if (snapshot.hasData)
                    const Icon(Icons.open_in_full,
                        size: 13, color: Colors.white38),
                ],
              ),
              const SizedBox(height: 9),
              if (snapshot.connectionState != ConnectionState.done)
                const SizedBox(
                  height: 116,
                  child: Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else if (snapshot.hasError)
                _GrowthUnavailable(
                    error: '${snapshot.error}', onRetry: _refresh)
              else if (snapshot.data?.hasChartData != true)
                _GrowthUnavailable(
                  error: 'No comparable Growth days yet.',
                  onRetry: _refresh,
                )
              else ...[
                _GrowthLegend(series: snapshot.data!.series, compact: true),
                const SizedBox(height: 7),
                SizedBox(
                  key: const Key('growth-compact-chart'),
                  height: 104,
                  width: double.infinity,
                  child: CustomPaint(
                    painter: KaiGrowthChartPainter(snapshot.data!.series),
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  'Indexed to each line’s own average · tap for real figures',
                  style: TextStyle(
                    color: Colors.white.withOpacity(.45),
                    fontSize: 8.5,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Future<void> _showDetail(
    BuildContext context,
    KaiGrowthSnapshot initial,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (context) =>
          _GrowthDetailDialog(loader: _loader, initial: initial),
    );
  }
}

class _GrowthCardShell extends StatelessWidget {
  const _GrowthCardShell({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const Key('kai-growth-tracker-card'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: const Color(0xFF071713).withOpacity(.88),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF35C7AC).withOpacity(.28)),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _GrowthUnavailable extends StatelessWidget {
  const _GrowthUnavailable({required this.error, required this.onRetry});

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 116,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            error.replaceFirst('Bad state: ', ''),
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFF9DB6AE), fontSize: 10),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 13),
            label: const Text('Retry', style: TextStyle(fontSize: 10)),
          ),
        ],
      ),
    );
  }
}

class _GrowthDetailDialog extends StatefulWidget {
  const _GrowthDetailDialog({required this.loader, required this.initial});

  final KaiGrowthLoader loader;
  final KaiGrowthSnapshot initial;

  @override
  State<_GrowthDetailDialog> createState() => _GrowthDetailDialogState();
}

class _GrowthDetailDialogState extends State<_GrowthDetailDialog> {
  int _days = 28;
  late Future<KaiGrowthSnapshot> _future;

  @override
  void initState() {
    super.initState();
    _future = Future.value(widget.initial);
  }

  void _select(int days) {
    setState(() {
      _days = days;
      _future = widget.loader(days);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF091410),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: FutureBuilder<KaiGrowthSnapshot>(
            future: _future,
            builder: (context, snapshot) {
              final data = snapshot.data;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Growth detail',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            SizedBox(height: 3),
                            Text(
                              'Social movement against daily sales',
                              style: TextStyle(
                                  color: Color(0xFF94AAA3), fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      for (final days in const [7, 28, 90]) ...[
                        ChoiceChip(
                          label: Text('${days}d'),
                          selected: _days == days,
                          onSelected: (_) => _select(days),
                        ),
                        const SizedBox(width: 6),
                      ],
                      IconButton(
                        tooltip: 'Close',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  if (snapshot.connectionState != ConnectionState.done)
                    const Expanded(
                        child: Center(child: CircularProgressIndicator()))
                  else if (snapshot.hasError ||
                      data == null ||
                      !data.hasChartData)
                    Expanded(
                      child: Center(
                        child: Text(
                          snapshot.hasError
                              ? '${snapshot.error}'
                              : 'No comparable days.',
                          style: const TextStyle(color: Color(0xFFB6C7C1)),
                        ),
                      ),
                    )
                  else ...[
                    _GrowthLegend(series: data.series),
                    const SizedBox(height: 14),
                    Expanded(
                      child: Container(
                        key: const Key('growth-detail-chart'),
                        padding: const EdgeInsets.fromLTRB(8, 12, 8, 5),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(.18),
                          borderRadius: BorderRadius.circular(14),
                          border:
                              Border.all(color: Colors.white.withOpacity(.07)),
                        ),
                        child: CustomPaint(
                          painter: KaiGrowthChartPainter(data.series,
                              detailed: true),
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final series in data.series)
                          _GrowthMetricTile(series: series),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      '100 = that line’s own daily average. Social channels are never summed. '
                      'Sales is dashed and shown in BHD below.',
                      style: TextStyle(color: Color(0xFF789088), fontSize: 10),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _GrowthMetricTile extends StatelessWidget {
  const _GrowthMetricTile({required this.series});

  final KaiGrowthSeries series;

  @override
  Widget build(BuildContext context) {
    final value = series.latest;
    final isMoney = series.platform == KaiGrowthPlatform.sales;
    final formatted = value == null
        ? '—'
        : isMoney
            ? 'BD ${value.toStringAsFixed(3)}'
            : value.toStringAsFixed(value == value.roundToDouble() ? 0 : 1);
    return Container(
      width: 140,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: growthColour(series.platform).withOpacity(.08),
        borderRadius: BorderRadius.circular(10),
        border:
            Border.all(color: growthColour(series.platform).withOpacity(.26)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            series.platform.label,
            style: TextStyle(
              color: growthColour(series.platform),
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(formatted,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w800)),
          Text(
            '${series.reportedDays} reporting days · ${series.platform.unit}',
            style: const TextStyle(color: Color(0xFF789088), fontSize: 8.5),
          ),
        ],
      ),
    );
  }
}

class _GrowthLegend extends StatelessWidget {
  const _GrowthLegend({required this.series, this.compact = false});

  final List<KaiGrowthSeries> series;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: compact ? 8 : 14,
      runSpacing: 5,
      children: [
        for (final item in series)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 12,
                height: 3,
                color: growthColour(item.platform),
              ),
              const SizedBox(width: 4),
              Text(
                item.platform.label,
                style: TextStyle(
                  color: Colors.white.withOpacity(.72),
                  fontSize: compact ? 8 : 10,
                ),
              ),
            ],
          ),
      ],
    );
  }
}

Color growthColour(KaiGrowthPlatform platform) => switch (platform) {
      KaiGrowthPlatform.instagram => const Color(0xFFD98AB5),
      KaiGrowthPlatform.tiktok => const Color(0xFF6FD3D0),
      KaiGrowthPlatform.ads => const Color(0xFF7FA8E0),
      KaiGrowthPlatform.google => const Color(0xFFE0C070),
      KaiGrowthPlatform.sales => const Color(0xFF72D590),
    };

class KaiGrowthChartPainter extends CustomPainter {
  KaiGrowthChartPainter(this.series, {this.detailed = false});

  final List<KaiGrowthSeries> series;
  final bool detailed;

  @override
  void paint(Canvas canvas, Size size) {
    if (series.isEmpty || size.width <= 0 || size.height <= 0) return;
    final all = series.expand((line) => line.indexedValues).whereType<double>();
    if (all.isEmpty) return;
    var minY = all.reduce(math.min);
    var maxY = all.reduce(math.max);
    minY = math.min(minY, 100);
    maxY = math.max(maxY, 100);
    final padding = math.max(8.0, (maxY - minY) * .12);
    minY = math.max(0, minY - padding);
    maxY += padding;
    final range = math.max(1.0, maxY - minY);
    final count =
        series.map((line) => line.indexedValues.length).fold(0, math.max);
    if (count < 2) return;

    double x(int index) => index * size.width / (count - 1);
    double y(double value) =>
        size.height - ((value - minY) / range) * size.height;

    final baseline = Paint()
      ..color = Colors.white.withOpacity(.16)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, y(100)), Offset(size.width, y(100)), baseline);

    for (final line in series) {
      final paint = Paint()
        ..color = growthColour(line.platform)
        ..strokeWidth = detailed ? 2.3 : 1.6
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      final values = line.indexedValues;
      var path = Path();
      var hasPoint = false;
      for (var i = 0; i < values.length; i++) {
        final value = values[i];
        if (value == null) {
          if (hasPoint) _drawSeriesPath(canvas, path, paint, line.platform);
          path = Path();
          hasPoint = false;
          continue;
        }
        final point = Offset(x(i), y(value));
        if (!hasPoint) {
          path.moveTo(point.dx, point.dy);
          hasPoint = true;
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      if (hasPoint) _drawSeriesPath(canvas, path, paint, line.platform);
    }
  }

  void _drawSeriesPath(
    Canvas canvas,
    Path path,
    Paint paint,
    KaiGrowthPlatform platform,
  ) {
    if (platform != KaiGrowthPlatform.sales) {
      canvas.drawPath(path, paint);
      return;
    }
    for (final metric in path.computeMetrics()) {
      var start = 0.0;
      while (start < metric.length) {
        final end = math.min(start + 7, metric.length);
        canvas.drawPath(metric.extractPath(start, end), paint);
        start += 11;
      }
    }
  }

  @override
  bool shouldRepaint(covariant KaiGrowthChartPainter oldDelegate) =>
      oldDelegate.series != series || oldDelegate.detailed != detailed;
}
