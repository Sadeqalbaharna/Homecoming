// ActivityFeedScreen
//
// A reverse-chronological scrollable feed of activity cards — one card per
// conversation turn, showing every signal that came out of that exchange:
// personality changes, mood shifts, memories recalled, tags, web search, etc.

import 'package:flutter/material.dart';
import '../services/core/activity_card_service.dart';
import '../services/ai/usage_tracking_service.dart';

class ActivityFeedScreen extends StatefulWidget {
  final String personaId;
  const ActivityFeedScreen({super.key, required this.personaId});

  @override
  State<ActivityFeedScreen> createState() => _ActivityFeedScreenState();
}

class _ActivityFeedScreenState extends State<ActivityFeedScreen> {
  List<ActivityCard> _cards = [];
  bool _loading = true;
  Map<String, dynamic> _monthly = {};

  // Personality dimension display names
  static const _pDim = {
    'extraversion': 'E',
    'intuition':    'N',
    'feeling':      'F',
    'perceiving':   'P',
  };

  // Mood dimension display names
  static const _mDim = {
    'valence':      'mood',
    'energy':       'energy',
    'warmth':       'warmth',
    'confidence':   'confid.',
    'playfulness':  'play',
    'focus':        'focus',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      ActivityCardService().getCards(widget.personaId),
      UsageTrackingService.getMonthlyStats(),
    ]);
    if (mounted) setState(() {
      _cards   = results[0] as List<ActivityCard>;
      _monthly = results[1] as Map<String, dynamic>;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0806),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Color(0x88FFE7B0), size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Activity Feed',
          style: TextStyle(color: Color(0xCCFFE7B0), fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: 0.5),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Color(0x66FFE7B0), size: 20),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFFFE7B0), strokeWidth: 1.5))
          : _cards.isEmpty
              ? _emptyState()
              : RefreshIndicator(
                  color: const Color(0xFFFFE7B0),
                  backgroundColor: const Color(0xFF1A1410),
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                    itemCount: _cards.length + 1,
                    itemBuilder: (ctx, i) {
                      if (i == 0) return _MonthlyCostBar(monthly: _monthly);
                      return _CardTile(card: _cards[i - 1], pDim: _pDim, mDim: _mDim);
                    },
                  ),
                ),
    );
  }

  Widget _emptyState() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('🃏', style: TextStyle(fontSize: 40)),
        const SizedBox(height: 16),
        Text(
          'No activity yet',
          style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 15),
        ),
        const SizedBox(height: 6),
        Text(
          'Cards appear after each conversation turn',
          style: TextStyle(color: Colors.white.withOpacity(0.25), fontSize: 12),
        ),
      ],
    ),
  );
}

// ── Individual card ─────────────────────────────────────────────────────────

class _CardTile extends StatefulWidget {
  final ActivityCard card;
  final Map<String, String> pDim;
  final Map<String, String> mDim;
  const _CardTile({required this.card, required this.pDim, required this.mDim});

  @override
  State<_CardTile> createState() => _CardTileState();
}

class _CardTileState extends State<_CardTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.card;
    final ts = DateTime.fromMillisecondsSinceEpoch(c.timestamp);
    final timeStr = _fmt(ts);

    // Compute which personality dims actually changed
    final pChanges = widget.pDim.entries
        .where((e) => (c.personalityDelta[e.key] ?? 0) != 0)
        .toList();
    final mChanges = widget.mDim.entries
        .where((e) => (c.moodDelta[e.key] ?? 0) != 0)
        .toList();

    final hasMemories  = c.memoriesUsed.isNotEmpty;
    final hasCuriosity = c.curiosityQuestion != null;

    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF100D09),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0x33FFE7B0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ───────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      '💬 ${c.userMessage}',
                      style: const TextStyle(color: Color(0xEEFFE7B0), fontSize: 13, height: 1.4),
                      maxLines: _expanded ? null : 2,
                      overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(timeStr, style: const TextStyle(color: Color(0x55FFE7B0), fontSize: 10)),
                ],
              ),
            ),

            // ── Kai reply ────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
              child: Text(
                c.kaiReply,
                style: TextStyle(color: Colors.white.withOpacity(0.55), fontSize: 12, height: 1.4),
                maxLines: _expanded ? null : 3,
                overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
              ),
            ),

            const SizedBox(height: 10),
            const Divider(color: Color(0x22FFE7B0), height: 1),
            const SizedBox(height: 10),

            // ── Signal rows ───────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // MBTI + personality deltas
                  if (c.mbti.isNotEmpty || pChanges.isNotEmpty)
                    _SignalRow(
                      icon: '🧠',
                      label: 'PERSONALITY',
                      child: Row(
                        children: [
                          if (c.mbti.isNotEmpty) ...[
                            Text(c.mbti,
                              style: const TextStyle(color: Color(0xAAFFE7B0), fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1)),
                            const SizedBox(width: 8),
                          ],
                          ...pChanges.map((e) {
                            final v = c.personalityDelta[e.key]!;
                            return _DeltaChip(label: e.value, delta: v);
                          }),
                          if (pChanges.isEmpty)
                            const Text('no shift', style: TextStyle(color: Color(0x44FFE7B0), fontSize: 11)),
                        ],
                      ),
                    ),

                  // Mood deltas
                  if (mChanges.isNotEmpty)
                    _SignalRow(
                      icon: '🌊',
                      label: 'MOOD',
                      child: Wrap(
                        spacing: 6,
                        children: mChanges.map((e) {
                          final v = c.moodDelta[e.key]!;
                          return _DeltaChip(label: e.value, delta: v);
                        }).toList(),
                      ),
                    ),

                  // Tags
                  if (c.tags.isNotEmpty)
                    _SignalRow(
                      icon: '🏷️',
                      label: 'TAGS',
                      child: Wrap(
                        spacing: 5,
                        runSpacing: 4,
                        children: c.tags.take(8).map((t) => _Tag(t)).toList(),
                      ),
                    ),

                  // Memories recalled
                  if (hasMemories)
                    _SignalRow(
                      icon: '💾',
                      label: 'MEMORY',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${c.memoriesUsed.length} node${c.memoriesUsed.length == 1 ? '' : 's'} recalled',
                            style: const TextStyle(color: Color(0x99B8E994), fontSize: 11),
                          ),
                          if (_expanded) ...[
                            const SizedBox(height: 4),
                            ...c.memoriesUsed.map((m) => Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: Text('· $m',
                                style: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 10, height: 1.4),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            )),
                          ],
                        ],
                      ),
                    ),

                  // Web search
                  if (c.webSearchUsed)
                    _SignalRow(
                      icon: '🔍',
                      label: 'WEB',
                      child: const Text('live search used',
                        style: TextStyle(color: Color(0x999EB8D9), fontSize: 11)),
                    ),

                  // Curiosity question
                  if (hasCuriosity)
                    _SignalRow(
                      icon: '💡',
                      label: 'CURIOSITY',
                      child: Text(
                        c.curiosityQuestion!,
                        style: TextStyle(color: Colors.white.withOpacity(0.45), fontSize: 11, fontStyle: FontStyle.italic),
                        maxLines: _expanded ? null : 1,
                        overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
                      ),
                    ),

                  // Cost
                  if (c.costUsd > 0)
                    _SignalRow(
                      icon: '💰',
                      label: 'COST',
                      child: Row(
                        children: [
                          Text(
                            _formatCost(c.costUsd),
                            style: const TextStyle(color: Color(0xAAFFE7B0), fontSize: 11, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${c.inputTokens}↑ ${c.outputTokens}↓',
                            style: const TextStyle(color: Color(0x55FFE7B0), fontSize: 10),
                          ),
                        ],
                      ),
                    ),

                  // Expand/collapse hint
                  if (!_expanded)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text('tap for details',
                        style: TextStyle(color: Colors.white.withOpacity(0.2), fontSize: 10)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatCost(double cost) {
    if (cost == 0) return '\$0';
    if (cost < 0.001) return '< \$0.001';
    if (cost < 0.01) return '\$${cost.toStringAsFixed(4)}';
    return '\$${cost.toStringAsFixed(3)}';
  }

  String _fmt(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) {
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      return '$h:$m';
    }
    final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[dt.month-1]} ${dt.day}';
  }
}

// ── Sub-widgets ──────────────────────────────────────────────────────────────

class _SignalRow extends StatelessWidget {
  final String icon;
  final String label;
  final Widget child;
  const _SignalRow({required this.icon, required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(icon, style: const TextStyle(fontSize: 12)),
          const SizedBox(width: 6),
          SizedBox(
            width: 80,
            child: Text(label,
              style: const TextStyle(
                color: Color(0x66FFE7B0), fontSize: 9,
                fontWeight: FontWeight.w700, letterSpacing: 0.8)),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _DeltaChip extends StatelessWidget {
  final String label;
  final int delta;
  const _DeltaChip({required this.label, required this.delta});

  @override
  Widget build(BuildContext context) {
    final positive = delta > 0;
    final color = positive ? const Color(0xFF98FB98) : const Color(0xFFE88080);
    final sign = positive ? '+' : '';
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        '$label $sign$delta',
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String text;
  const _Tag(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0x1AFFE7B0),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text, style: const TextStyle(color: Color(0x88FFE7B0), fontSize: 10)),
    );
  }
}

// ── Monthly cost bar ─────────────────────────────────────────────────────────

class _MonthlyCostBar extends StatelessWidget {
  final Map<String, dynamic> monthly;
  const _MonthlyCostBar({required this.monthly});

  @override
  Widget build(BuildContext context) {
    final cost           = (monthly['cost']           as double?) ?? 0.0;
    final calls          = (monthly['calls']          as int?)    ?? 0;
    final tokens         = (monthly['tokens']         as int?)    ?? 0;
    final searches       = (monthly['searches']       as int?)    ?? 0;
    final month          = (monthly['month']          as String?) ?? '';
    final openaiCost     = (monthly['openai_cost']     as double?) ?? 0.0;
    final elevenlabsCost = (monthly['elevenlabs_cost'] as double?) ?? 0.0;
    final searchCost     = (monthly['search_cost']     as double?) ?? 0.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A1208), Color(0xFF0F0B06)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x44FFE7B0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text('💰', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      month.isNotEmpty ? 'This month ($month)' : 'This month',
                      style: const TextStyle(color: Color(0x88FFE7B0), fontSize: 10, letterSpacing: 0.8),
                    ),
                    Text(
                      _formatCost(cost),
                      style: const TextStyle(color: Color(0xFFFFE7B0), fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: -0.5),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('$calls calls', style: const TextStyle(color: Color(0x66FFE7B0), fontSize: 11)),
                  Text(_formatTokens(tokens), style: const TextStyle(color: Color(0x44FFE7B0), fontSize: 10)),
                  if (searches > 0)
                    Text('$searches searches', style: const TextStyle(color: Color(0x44FFE7B0), fontSize: 10)),
                ],
              ),
            ],
          ),

          // Per-service breakdown (only show if there's data)
          if (openaiCost > 0 || elevenlabsCost > 0 || searchCost > 0) ...[
            const SizedBox(height: 10),
            const Divider(color: Color(0x22FFE7B0), height: 1),
            const SizedBox(height: 8),
            Row(
              children: [
                if (openaiCost > 0)
                  _ServiceChip(label: 'OpenAI', cost: openaiCost, color: const Color(0xFF74AA9C)),
                if (elevenlabsCost > 0)
                  _ServiceChip(label: 'ElevenLabs', cost: elevenlabsCost, color: const Color(0xFF9B7FD4)),
                if (searchCost > 0)
                  _ServiceChip(label: 'Search', cost: searchCost, color: const Color(0xFF9EB8D9)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _formatCost(double cost) {
    if (cost == 0) return '\$0.00';
    if (cost < 0.001) return '< \$0.001';
    if (cost < 0.01) return '\$${cost.toStringAsFixed(4)}';
    return '\$${cost.toStringAsFixed(3)}';
  }

  String _formatTokens(int t) {
    if (t >= 1000000) return '${(t / 1000000).toStringAsFixed(1)}M tokens';
    if (t >= 1000) return '${(t / 1000).toStringAsFixed(1)}k tokens';
    return '$t tokens';
  }
}

class _ServiceChip extends StatelessWidget {
  final String label;
  final double cost;
  final Color color;
  const _ServiceChip({required this.label, required this.cost, required this.color});

  @override
  Widget build(BuildContext context) {
    final costStr = cost < 0.001 ? '< \$0.001'
        : cost < 0.01 ? '\$${cost.toStringAsFixed(4)}'
        : '\$${cost.toStringAsFixed(3)}';
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: color.withOpacity(0.7), fontSize: 9, letterSpacing: 0.5)),
          Text(costStr, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
