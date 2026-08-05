import 'package:flutter/material.dart';

import '../services/core/trace_store_service.dart';
import '../tools/replay.dart';

/// A small live surface for L6 Kai State Dashboard evidence.
///
/// TraceStore records the flight. replay.dart does the arithmetic. This widget is
/// the first visible cockpit instrument for those numbers, so they stop living as
/// test-only archaeology.
class KaiStateScorecardCard extends StatelessWidget {
  final Future<List<Map<String, dynamic>>> Function()? traceLoader;
  final int limit;

  const KaiStateScorecardCard({
    super.key,
    this.traceLoader,
    this.limit = 50,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: (traceLoader ?? (() => TraceStoreService.instance.readAll(limit: limit)))(),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const _ScorecardShell(
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }

        if (snap.hasError) {
          return _ScorecardShell(
            child: _StatusText(
              'KAI STATE SCORECARD',
              'trace reader coughed: ${snap.error}',
            ),
          );
        }

        final rows = snap.data ?? const <Map<String, dynamic>>[];
        if (rows.isEmpty) {
          return const _ScorecardShell(
            child: _StatusText(
              'KAI STATE SCORECARD',
              'no trace rows yet',
            ),
          );
        }

        final card = score(rows);
        final efficiency = efficiencySummary(rows, window: 8);
        return _ScorecardShell(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.monitor_heart, size: 14, color: Color(0xFFFFD48A)),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text(
                      'KAI STATE SCORECARD',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
                  Text(
                    '${card.turns} turns',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.52),
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _MetricLine(
                label: 'memory formed',
                value: Scorecard.ratio(card.memoriesFormed, card.turns),
              ),
              _MetricLine(
                label: 'retrieval usable',
                value: Scorecard.ratio(
                  card.retrievalsWithSomethingUsable,
                  card.retrievalsAttempted,
                ),
              ),
              _MetricLine(
                label: 'graph consulted',
                value: Scorecard.ratio(card.graphConsulted, card.turns),
              ),
              _MetricLine(
                label: 'route selected',
                value: Scorecard.ratio(card.routedTurns, card.turns),
              ),
              _MetricLine(
                label: 'route confident',
                value: Scorecard.ratio(card.highConfidenceRoutes, card.routedTurns),
              ),
              _MetricLine(
                label: 'tool outcomes',
                value: Scorecard.ratio(card.toolCallsRecorded, card.totalToolCalls),
              ),
              _MetricLine(
                label: 'tool failed',
                value: Scorecard.ratio(card.failedToolCalls, card.toolCallsRecorded),
              ),
              _MetricLine(
                label: 'recovered replies',
                value: Scorecard.ratio(card.recoveredReplies, card.turns),
              ),
              _MetricLine(
                label: 'post errors',
                value: '${card.postProcessErrors}',
              ),
              _MetricLine(
                label: 'jobs proved',
                value: Scorecard.ratio(card.jobsClosedWithProof, card.jobsClosed),
              ),
              _MetricLine(
                label: 'cost tracked',
                value: Scorecard.ratio(card.turnsWithCost, card.turns),
              ),
              _MetricLine(
                label: 'total cost',
                value: '\$${card.totalCostUsd.toStringAsFixed(6)}',
              ),
              _MetricLine(
                label: 'avg cost',
                value: card.turnsWithCost == 0
                    ? '— (no data)'
                    : '\$${card.averageCostUsd.toStringAsFixed(6)} / turn',
              ),
              _MetricLine(
                label: 'avg tokens',
                value: card.turnsWithCost == 0
                    ? '— (no data)'
                    : '${card.averageTokens} / turn',
              ),
              _MetricLine(
                label: 'efficiency window',
                value: 'latest ${efficiency.recent.turns} vs previous ${efficiency.previous.turns}',
              ),
              _MetricLine(
                label: 'token trend',
                value: _formatTrend(
                  efficiency.tokenReduction,
                  '${efficiency.previous.averageTokens} → ${efficiency.recent.averageTokens} tok/turn',
                ),
              ),
              _MetricLine(
                label: 'schema trend',
                value: _formatTrend(
                  efficiency.schemaReduction,
                  '${efficiency.previous.averageSchemaTokens} → ${efficiency.recent.averageSchemaTokens} schema/turn',
                ),
              ),
              _MetricLine(
                label: 'cost trend',
                value: _formatTrend(
                  efficiency.costReduction,
                  '\$${efficiency.previous.averageCostUsd.toStringAsFixed(6)} → '
                      '\$${efficiency.recent.averageCostUsd.toStringAsFixed(6)} / turn',
                ),
              ),
              _MetricLine(
                label: 'recent token mix',
                value: efficiency.recent.costedTurns == 0
                    ? '— (no costed turns)'
                    : '${efficiency.recent.averageInputTokens} in / '
                        '${efficiency.recent.averageOutputTokens} out · '
                        'schema ${efficiency.recent.schemaShareOfInputPercent}% of input',
              ),
              _MetricLine(
                label: 'tool trim saved',
                value: efficiency.recent.toolTrimTurns == 0
                    ? '— (no trimmed loops)'
                    : '${efficiency.recent.averageToolTrimTokensSaved} tok/trimmed turn '
                        '(${efficiency.recent.totalToolTrimCompactedResults} compacted, '
                        '${efficiency.recent.totalToolTrimHardCappedResults} capped)',
              ),
              _MetricLine(
                label: 'setup trend',
                value: _formatTrend(
                  efficiency.latencyReduction,
                  '${efficiency.previous.averageTimeToGptSendMs}ms → '
                      '${efficiency.recent.averageTimeToGptSendMs}ms to GPT',
                ),
              ),
              _MetricLine(
                label: 'mood tracked',
                value: Scorecard.ratio(card.turnsWithMood, card.turns),
              ),
              _MetricLine(
                label: 'avg energy',
                value: card.turnsWithMood == 0
                    ? '— (no data)'
                    : '${card.averageMoodEnergy}',
              ),
              _MetricLine(
                label: 'avg focus',
                value: card.turnsWithMood == 0
                    ? '— (no data)'
                    : '${card.averageMoodFocus}',
              ),
              _MetricLine(
                label: 'confidence dips',
                value: '${card.confidenceDips}',
              ),
              _MetricLine(
                label: 'play spikes',
                value: '${card.playfulnessSpikes}',
              ),
              _MetricLine(
                label: 'setup to GPT',
                value: card.medianTimeToGptSend == 0
                    ? '— (no data)'
                    : '${card.medianTimeToGptSend}ms median',
              ),
              const SizedBox(height: 6),
              Text(
                'replay.dart over latest trace rows',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.34),
                  fontSize: 8.2,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

String _formatTrend(double? value, String absolute) {
  if (value == null) return '— (no baseline) · $absolute';
  final arrow = value >= 0 ? '↓' : '↑';
  return '$arrow ${value.abs().round()}% · $absolute';
}

class _ScorecardShell extends StatelessWidget {
  final Widget child;

  const _ScorecardShell({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF120D07).withOpacity(0.74),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFD48A).withOpacity(0.24)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFFB86B).withOpacity(0.05),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _StatusText extends StatelessWidget {
  final String title;
  final String message;

  const _StatusText(this.title, this.message);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10.5,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          message,
          style: TextStyle(color: Colors.white.withOpacity(0.48), fontSize: 9.5),
        ),
      ],
    );
  }
}

class _MetricLine extends StatelessWidget {
  final String label;
  final String value;

  const _MetricLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withOpacity(0.54),
                fontSize: 8.9,
                letterSpacing: 0.2,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 5,
            child: Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              softWrap: true,
              style: const TextStyle(
                color: Color(0xFFFFD48A),
                fontSize: 8.6,
                fontWeight: FontWeight.w800,
                height: 1.12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
