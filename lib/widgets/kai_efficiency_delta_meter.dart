import 'package:flutter/material.dart';

import '../services/core/trace_store_service.dart';
import '../tools/replay.dart';
import 'kai_state_scorecard_card.dart';

/// Tiny always-visible header meter for whether Kai is getting cheaper/faster.
///
/// Compares the most recent costed/latency-bearing turns against the previous
/// same-sized window. Positive reduction is good; regression is shown honestly.
class KaiEfficiencyDeltaMeter extends StatelessWidget {
  final Future<List<Map<String, dynamic>>> Function()? traceLoader;
  final int limit;
  final int window;

  const KaiEfficiencyDeltaMeter({
    super.key,
    this.traceLoader,
    this.limit = 40,
    this.window = 8,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: (traceLoader ?? (() => TraceStoreService.instance.readAll(limit: limit)))(),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return _scorecardAnchor(
            context,
            const _EfficiencyShell(child: SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 1.4),
            )),
          );
        }

        if (snap.hasError) {
          return _scorecardAnchor(
            context,
            const _EfficiencyShell(child: _TinyText('EFF', 'trace?')),
          );
        }

        final rows = snap.data ?? const <Map<String, dynamic>>[];
        final stats = EfficiencyDelta.fromRows(rows, window: window);
        return _scorecardAnchor(
          context,
          _EfficiencyShell(child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _DeltaPill(label: 'tok', delta: stats.tokenReduction),
              const SizedBox(width: 5),
              _DeltaPill(label: 'sch', delta: stats.schemaReduction),
              const SizedBox(width: 5),
              _DeltaPill(label: 'lat', delta: stats.latencyReduction),
            ],
          )),
        );
      },
    );
  }

  Widget _scorecardAnchor(BuildContext context, Widget meter) {
    final viewport = MediaQuery.sizeOf(context);
    final panelWidth = (viewport.width - 32).clamp(280.0, 520.0);
    final panelHeight = (viewport.height - 92).clamp(320.0, 740.0);
    return MenuAnchor(
      key: const Key('kai-efficiency-scorecard-anchor'),
      alignmentOffset: const Offset(0, 8),
      style: MenuStyle(
        padding: const WidgetStatePropertyAll(EdgeInsets.all(8)),
        backgroundColor:
            const WidgetStatePropertyAll(Color(0xFF07111C)),
        maximumSize:
            WidgetStatePropertyAll(Size(panelWidth + 16, panelHeight + 16)),
        side: WidgetStatePropertyAll(
          BorderSide(color: const Color(0xFFFFD48A).withOpacity(.28)),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      menuChildren: [
        SizedBox(
          width: panelWidth,
          height: panelHeight,
          child: SingleChildScrollView(
            key: const Key('kai-efficiency-scorecard-panel'),
            primary: false,
            child: KaiStateScorecardCard(
              traceLoader: traceLoader,
              limit: limit,
            ),
          ),
        ),
      ],
      builder: (context, controller, child) => Tooltip(
        message: 'Open Kai State Scorecard',
        child: InkWell(
          key: const Key('kai-efficiency-scorecard-toggle'),
          borderRadius: BorderRadius.circular(999),
          onTap: controller.isOpen ? controller.close : controller.open,
          child: meter,
        ),
      ),
    );
  }
}

class EfficiencyDelta {
  final double? tokenReduction;
  final double? latencyReduction;
  final double? schemaReduction;

  const EfficiencyDelta({
    required this.tokenReduction,
    required this.latencyReduction,
    required this.schemaReduction,
  });

  static EfficiencyDelta fromRows(List<Map<String, dynamic>> rows, {int window = 8}) {
    return EfficiencyDelta(
      tokenReduction: _reduction(
        _costedTokens(rows).map((r) => promptInputTokens(r) + promptOutputTokens(r)).toList(),
        window,
      ),
      latencyReduction: _reduction(
        _latencies(rows).map((e) => e.$2).toList(),
        window,
      ),
      schemaReduction: _reduction(
        _manifestTokens(rows).map(manifestApproxTokens).toList(),
        window,
      ),
    );
  }

  static List<Map<String, dynamic>> _costedTokens(List<Map<String, dynamic>> rows) =>
      rows.where((r) => costTracked(r)).toList();

  static List<Map<String, dynamic>> _manifestTokens(List<Map<String, dynamic>> rows) =>
      rows.where((r) => manifestTracked(r)).toList();

  static List<(Map<String, dynamic>, int)> _latencies(List<Map<String, dynamic>> rows) =>
      rows
          .map((r) => (r, timeToGptSend(r)))
          .where((pair) => pair.$2 != null && pair.$2! > 0)
          .map((pair) => (pair.$1, pair.$2!))
          .toList();

  static double? _reduction(List<num> values, int window) {
    if (window <= 0 || values.length < window * 2) return null;
    // TraceStoreService.readAll() returns oldest first, so the previous window
    // comes before the recent one. Getting this backwards makes improvements
    // display as regressions, which is exactly the kind of tiny lie this meter
    // exists to catch.
    final windowed = values.length > window * 2
        ? values.sublist(values.length - (window * 2))
        : values;
    final previous = windowed.take(window).toList();
    final recent = windowed.skip(window).take(window).toList();
    final prevAvg = _avg(previous);
    if (prevAvg <= 0) return null;
    return ((prevAvg - _avg(recent)) / prevAvg) * 100;
  }

  static double _avg(List<num> values) =>
      values.isEmpty ? 0 : values.fold<double>(0, (sum, v) => sum + v) / values.length;
}

class _EfficiencyShell extends StatelessWidget {
  final Widget child;

  const _EfficiencyShell({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF101722).withOpacity(0.72),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFF7FB4FF).withOpacity(0.24)),
      ),
      child: child,
    );
  }
}

class _DeltaPill extends StatelessWidget {
  final String label;
  final double? delta;

  const _DeltaPill({required this.label, required this.delta});

  @override
  Widget build(BuildContext context) {
    final d = delta;
    final noData = d == null;
    final good = d != null && d >= 0;
    final color = noData
        ? Colors.white.withOpacity(0.42)
        : good
            ? const Color(0xFF7EE787)
            : const Color(0xFFFF8A8A);
    final value = noData
        ? '—'
        : '${good ? '↓' : '↑'} ${d.abs().round()}%';

    return _TinyText(label, value, color: color);
  }
}

class _TinyText extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;

  const _TinyText(this.label, this.value, {this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? Colors.white.withOpacity(0.52);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 76),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withOpacity(0.46),
                fontSize: 8.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4,
              ),
            ),
          ),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: c,
                fontSize: 9,
                fontWeight: FontWeight.w900,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
