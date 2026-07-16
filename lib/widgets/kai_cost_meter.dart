// KaiCostMeter — what Kai actually costs, live.
//
// Everything he does already gets tracked by UsageTrackingService (every OpenAI
// call, ElevenLabs character, Google query, web fetch, Firebase read/write) —
// nothing ever read it back. This is that readout.
//
// It matters more than usual here because Kai is not request/response: he has an
// inner life, he reflects on a timer, and he reaches out on his own. Those are
// real model calls that happen while you're not looking. You should be able to
// see the meter turning.
//
// Two rows:
//   SESSION — what this run has cost (resettable, the one you watch)
//   TOTAL   — all-time, so the number never quietly runs away
//
// Reads SharedPreferences on a slow poll (cheap, local, no network).
//
// Wire-up:  const KaiCostMeter()  — e.g. in the shell header or a corner.
library;

import 'dart:async';
import 'package:flutter/material.dart';
import '../services/ai/usage_tracking_service.dart';

const _gpt = Color(0xFFFF9D2F);
const _claude = Color(0xFF2ED9FF);

class KaiCostMeter extends StatefulWidget {
  /// Compact = one line for a header. Otherwise a small stacked panel.
  final bool compact;
  final Duration refresh;

  const KaiCostMeter({
    super.key,
    this.compact = true,
    this.refresh = const Duration(seconds: 4),
  });

  @override
  State<KaiCostMeter> createState() => _KaiCostMeterState();
}

class _KaiCostMeterState extends State<KaiCostMeter> {
  Map<String, dynamic> _session = const {};
  Map<String, dynamic> _all = const {};
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(widget.refresh, (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final s = await UsageTrackingService.getSessionStats();
      final a = await UsageTrackingService.getUsageStats();
      if (!mounted) return;
      setState(() {
        _session = s;
        _all = a;
      });
    } catch (_) {
      // a missed refresh is fine
    }
  }

  double get _sessionCost => (_session['cost'] as num?)?.toDouble() ?? 0.0;
  int get _sessionTokens => (_session['tokens'] as int?) ?? 0;
  int get _sessionCalls => (_session['openai_calls'] as int?) ?? 0;
  double get _totalCost => (_all['total_cost'] as num?)?.toDouble() ?? 0.0;
  int get _totalTokens => (_all['total_tokens'] as int?) ?? 0;

  /// Cost is a quiet number until it isn't — warm it up as it climbs so a
  /// runaway loop is visible at a glance instead of buried in a decimal.
  Color get _costColor {
    if (_sessionCost >= 1.0) return const Color(0xFFFF6B6B);
    if (_sessionCost >= 0.25) return _gpt;
    return const Color(0xFF7EE787);
  }

  @override
  Widget build(BuildContext context) {
    final cost = UsageTrackingService.formatCost(_sessionCost);
    final toks = UsageTrackingService.formatTokens(_sessionTokens);

    final semantic = 'Kai usage this session: $cost across $_sessionCalls calls '
        'and $_sessionTokens tokens. All time: '
        '${UsageTrackingService.formatCost(_totalCost)}.';

    if (widget.compact) {
      return Semantics(
        label: semantic,
        container: true,
        child: Tooltip(
          message: 'Session: $cost · $toks tokens · $_sessionCalls calls\n'
              'All time: ${UsageTrackingService.formatCost(_totalCost)} · '
              '${UsageTrackingService.formatTokens(_totalTokens)} tokens',
          child: Container(
            padding: const EdgeInsets.fromLTRB(9, 4, 9, 4),
            decoration: BoxDecoration(
              color: const Color(0xFF0D1826),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF24384C)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _costColor,
                    boxShadow: [
                      BoxShadow(color: _costColor.withOpacity(0.7), blurRadius: 6),
                    ],
                  ),
                ),
                const SizedBox(width: 7),
                Text(cost,
                    style: TextStyle(
                        color: _costColor,
                        fontSize: 10.5,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w700)),
                const SizedBox(width: 8),
                Text(toks,
                    style: const TextStyle(
                        color: Color(0xFF9FD0E8),
                        fontSize: 10,
                        fontFamily: 'monospace')),
                const SizedBox(width: 6),
                const Text('tok',
                    style: TextStyle(
                        color: Color(0xFF5B7183),
                        fontSize: 9,
                        fontFamily: 'monospace')),
              ],
            ),
          ),
        ),
      );
    }

    return Semantics(
      label: semantic,
      container: true,
      child: DefaultTextStyle(
        style: const TextStyle(fontFamily: 'monospace', fontSize: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _row('SESSION', cost, '$toks tok · $_sessionCalls calls', _costColor),
            const SizedBox(height: 4),
            _row(
                'TOTAL',
                UsageTrackingService.formatCost(_totalCost),
                '${UsageTrackingService.formatTokens(_totalTokens)} tok',
                _claude),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String cost, String sub, Color c) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 52,
          child: Text(label,
              style: const TextStyle(
                  color: Color(0xFF5B7183), fontSize: 8.5, letterSpacing: 1.2)),
        ),
        Text(cost,
            style: TextStyle(color: c, fontWeight: FontWeight.w700, fontSize: 11)),
        const SizedBox(width: 8),
        Text(sub, style: const TextStyle(color: Color(0xFF6B8194), fontSize: 9)),
      ],
    );
  }
}
