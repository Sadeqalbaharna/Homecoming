// Kai's living cortex, rendered natively (no WebView).
//
//   • KaiBrainBackground — a giant, faint, non-interactive dual-hemisphere
//     neuron cloud behind the whole app. Left = ChatGPT (golden orange),
//     right = Claude (fluorescent blue). Pulses, glows, rotates, grows w/ mood.
//   • KaiVitals — Kai's live mood / personality / affinity as glowing
//     Stark-style concentric ring-gauges in the two house colors.
//
// Streams state from Firebase via KaiStateService. Pure Flutter CustomPaint.
library;

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../services/core/kai_db.dart';
import '../services/core/kai_state_service.dart';

// ── House palette ────────────────────────────────────────────────────────────
const kGpt = Color(0xFFFF9D2F); // golden orange — ChatGPT / left hemisphere
const kClaude = Color(0xFF2ED9FF); // fluorescent blue — Claude / right hemisphere

// ── Shared 3D geometry ───────────────────────────────────────────────────────

class _P {
  final double x, y, z;
  const _P(this.x, this.y, this.z);
  double dist(_P o) {
    final dx = x - o.x, dy = y - o.y, dz = z - o.z;
    return math.sqrt(dx * dx + dy * dy + dz * dz);
  }
}

class _Node {
  final _P p;
  final int lobe; // 0 = left/GPT/orange, 1 = right/Claude/blue
  const _Node(this.p, this.lobe);
}

class _Proj {
  final double x, y, z, persp;
  const _Proj(this.x, this.y, this.z, this.persp);
}

class _BrainGeom {
  final List<_Node> nodes;
  final List<List<int>> links;
  const _BrainGeom(this.nodes, this.links);
}

_BrainGeom _makeBrain() {
  final rnd = math.Random(7);
  final nodes = <_Node>[];
  _P lobe(double cx) {
    while (true) {
      final x = rnd.nextDouble() * 2 - 1;
      final y = rnd.nextDouble() * 2 - 1;
      final z = rnd.nextDouble() * 2 - 1;
      if (x * x / 0.85 + y * y / 1.2 + z * z / 1.0 <= 1) {
        return _P(x * 0.5 + cx, y * 0.62, z * 0.55);
      }
    }
  }

  for (var i = 0; i < 58; i++) {
    nodes.add(_Node(lobe(-0.46), 0));
  }
  for (var i = 0; i < 58; i++) {
    nodes.add(_Node(lobe(0.46), 1));
  }
  final links = <List<int>>[];
  for (var i = 0; i < nodes.length; i++) {
    final di = <MapEntry<int, double>>[];
    for (var j = 0; j < nodes.length; j++) {
      if (i == j) continue;
      di.add(MapEntry(j, nodes[i].p.dist(nodes[j].p)));
    }
    di.sort((a, b) => a.value.compareTo(b.value));
    links.add([di[0].key, di[1].key]);
  }
  return _BrainGeom(nodes, links);
}

// ── Background brain ─────────────────────────────────────────────────────────

class KaiBrainBackground extends StatefulWidget {
  final String personaId;
  final double opacity;
  final double radiusFactor;
  const KaiBrainBackground({
    super.key,
    required this.personaId,
    this.opacity = 0.26,
    this.radiusFactor = 0.5,
  });

  @override
  State<KaiBrainBackground> createState() => _KaiBrainBackgroundState();
}

class _KaiBrainBackgroundState extends State<KaiBrainBackground>
    with TickerProviderStateMixin {
  late final AnimationController _spin;
  late final AnimationController _pulse;
  late final _BrainGeom _geom;
  final _svc = KaiStateService();
  Map<String, int> _mood = const {};
  // Held so it can be cancelled: on desktop these streams are REST polls, so an
  // uncancelled listener keeps hitting the network for the life of the process.
  StreamSubscription<Map<String, int>>? _moodSub;

  @override
  void initState() {
    super.initState();
    _geom = _makeBrain();
    _spin = AnimationController(vsync: this, duration: const Duration(seconds: 48))
      ..repeat();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 3200))
      ..repeat(reverse: true);
    _moodSub = _svc.moodStream(widget.personaId).listen((m) {
      if (mounted && m.isNotEmpty) setState(() => _mood = m);
    });
    _svc.getMood(widget.personaId).then((m) {
      if (mounted && m != null && m.isNotEmpty && _mood.isEmpty) setState(() => _mood = m);
    });
  }

  @override
  void dispose() {
    _moodSub?.cancel();
    _spin.dispose();
    _pulse.dispose();
    super.dispose();
  }

  double _m(String k, [double d = 50]) => (_mood[k] ?? d).toDouble();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Opacity(
        opacity: widget.opacity,
        child: AnimatedBuilder(
          animation: Listenable.merge([_spin, _pulse]),
          builder: (_, __) => CustomPaint(
            painter: _BrainPainter(
              nodes: _geom.nodes,
              links: _geom.links,
              yaw: _spin.value * math.pi * 2,
              pitch: 0.18,
              pulse: _pulse.value,
              energy: _m('energy') / 100,
              valence: _m('valence') / 100,
              radiusFactor: widget.radiusFactor,
            ),
            size: Size.infinite,
          ),
        ),
      ),
    );
  }
}

// ── Vitals (ring gauges) ─────────────────────────────────────────────────────


class KaiBrainMap extends StatefulWidget {
  final String personaId;
  final double opacity;
  final double radiusFactor;

  const KaiBrainMap({
    super.key,
    required this.personaId,
    this.opacity = 0.42,
    this.radiusFactor = 0.86,
  });

  @override
  State<KaiBrainMap> createState() => _KaiBrainMapState();
}

class _KaiBrainMapState extends State<KaiBrainMap> with TickerProviderStateMixin {
  late final AnimationController _spin;
  late final AnimationController _pulse;
  late _BrainGeom _geom;
  final _svc = KaiStateService();
  Map<String, int> _mood = const {};
  bool _usingRealtimeGraph = false;
  int _realNodeCount = 0;
  int _realLinkCount = 0;
  String? _graphError;
  StreamSubscription<Map<String, int>>? _moodSub;
  StreamSubscription<KaiEvent>? _graphSub;

  @override
  void initState() {
    super.initState();
    _geom = _makeBrain();
    _spin = AnimationController(vsync: this, duration: const Duration(seconds: 48))
      ..repeat();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 3200))
      ..repeat(reverse: true);
    _moodSub = _svc.moodStream(widget.personaId).listen((m) {
      if (mounted && m.isNotEmpty) setState(() => _mood = m);
    });
    _svc.getMood(widget.personaId).then((m) {
      if (mounted && m != null && m.isNotEmpty && _mood.isEmpty) setState(() => _mood = m);
    });
    _graphSub = KaiDb.instance
        .ref('knowledge_graph/${widget.personaId}')
        .onValue
        .listen(_handleGraphEvent, onError: _handleGraphError);
  }

  @override
  void dispose() {
    _moodSub?.cancel();
    _graphSub?.cancel();
    _spin.dispose();
    _pulse.dispose();
    super.dispose();
  }

  void _handleGraphError(Object error) {
    if (!mounted) return;
    setState(() {
      _graphError = error.toString();
      _usingRealtimeGraph = false;
      _geom = _makeBrain();
      _realNodeCount = 0;
      _realLinkCount = 0;
    });
  }

  void _handleGraphEvent(KaiEvent event) {
    final parsed = _brainGeomFromKnowledgeGraph(event.snapshot.value);
    if (!mounted) return;
    setState(() {
      _graphError = null;
      if (parsed == null || parsed.nodes.isEmpty) {
        _usingRealtimeGraph = false;
        _geom = _makeBrain();
        _realNodeCount = 0;
        _realLinkCount = 0;
      } else {
        _usingRealtimeGraph = true;
        _geom = parsed;
        _realNodeCount = parsed.nodes.length;
        _realLinkCount = parsed.links.length;
      }
    });
  }

  double _m(String k, [double d = 50]) => (_mood[k] ?? d).toDouble();

  @override
  Widget build(BuildContext context) {
    final source = _graphError != null
        ? 'source: fallback / RTDB error'
        : _usingRealtimeGraph
            ? 'source: RTDB'
            : 'source: procedural fallback';
    final stats = _usingRealtimeGraph
        ? 'real nodes: $_realNodeCount   links: $_realLinkCount'
        : 'waiting for real nodes';

    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: Opacity(
              opacity: widget.opacity,
              child: AnimatedBuilder(
                animation: Listenable.merge([_spin, _pulse]),
                builder: (_, __) => CustomPaint(
                  painter: _BrainPainter(
                    nodes: _geom.nodes,
                    links: _geom.links,
                    yaw: _spin.value * math.pi * 2,
                    pitch: 0.18,
                    pulse: _pulse.value,
                    energy: _m('energy') / 100,
                    valence: _m('valence') / 100,
                    radiusFactor: widget.radiusFactor,
                  ),
                  size: Size.infinite,
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 10,
          right: 10,
          bottom: 8,
          child: IgnorePointer(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.30),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    source,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _usingRealtimeGraph ? kClaude : Colors.white70,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    stats,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.58),
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

_BrainGeom? _brainGeomFromKnowledgeGraph(Object? raw) {
  if (raw is! Map) return null;

  final nodeEntries = _knowledgeNodeEntries(raw['nodes']);
  if (nodeEntries.isEmpty) return null;

  nodeEntries.sort((a, b) {
    final ai = _numFrom(a.value['importance']) ?? 0;
    final bi = _numFrom(b.value['importance']) ?? 0;
    final byImportance = bi.compareTo(ai);
    if (byImportance != 0) return byImportance;
    return a.key.compareTo(b.key);
  });

  final limitedEntries = nodeEntries.take(80).toList(growable: false);
  final indexById = <String, int>{};
  final nodes = <_Node>[];

  for (var i = 0; i < limitedEntries.length; i++) {
    final entry = limitedEntries[i];
    final id = entry.key;
    final data = entry.value;
    indexById[id] = nodes.length;

    final label = (data['label'] ?? data['name'] ?? data['title'] ?? id).toString();
    final domain = (data['domain'] ?? data['type'] ?? '').toString().toLowerCase();
    final side = _brainSideFor(label.toLowerCase(), domain, nodes.length, limitedEntries.length);

    final storedX = _numFrom(data['x']);
    final storedY = _numFrom(data['y']);
    final angle = (nodes.length / math.max(1, limitedEntries.length)) * math.pi * 2;
    final ring = 0.32 + ((nodes.length % 9) / 9.0) * 0.52;
    final sideOffset = side < 0 ? -0.34 : 0.34;
    final x = storedX != null
        ? (storedX.clamp(-1.0, 1.0) * 0.42) + sideOffset
        : sideOffset + math.cos(angle) * ring * 0.32;
    final y = storedY != null
        ? storedY.clamp(-1.0, 1.0) * 0.68
        : math.sin(angle * 1.37) * ring * 0.68;
    final z = math.sin(angle) * 0.24;

    // _Node takes (_P, lobe) — build the point, then map side onto the lobe.
    // _brainSideFor returns -1 (left) / 1 (right); lobe is 0 (left/GPT/orange)
    // / 1 (right/Claude/blue). Passing `side` straight through would put every
    // left-brain node on the right.
    nodes.add(_Node(_P(x, y, z), side < 0 ? 0 : 1));
  }

  final links = <List<int>>[];
  final seen = <String>{};
  for (final edge in _knowledgeEdgeEntries(raw['edges'])) {
    final a = (edge['fromId'] ?? edge['from'] ?? edge['source']).toString();
    final b = (edge['toId'] ?? edge['to'] ?? edge['target']).toString();
    final ia = indexById[a];
    final ib = indexById[b];
    if (ia == null || ib == null || ia == ib) continue;
    final key = ia < ib ? '$ia:$ib' : '$ib:$ia';
    if (seen.add(key)) links.add([ia, ib]);
  }

  if (links.isEmpty && nodes.length > 1) {
    for (var i = 1; i < nodes.length; i++) {
      links.add([i - 1, i]);
    }
  }

  return _BrainGeom(nodes, links);
}

List<MapEntry<String, Map>> _knowledgeNodeEntries(Object? raw) {
  if (raw is Map) {
    return raw.entries
        .where((e) => e.value is Map)
        .map((e) => MapEntry(e.key.toString(), (e.value as Map).cast<dynamic, dynamic>()))
        .toList();
  }

  if (raw is List) {
    final out = <MapEntry<String, Map>>[];
    for (var i = 0; i < raw.length; i++) {
      final item = raw[i];
      if (item is! Map) continue;
      final id = (item['id'] ?? item['key'] ?? item['nodeId'] ?? i).toString();
      out.add(MapEntry(id, item.cast<dynamic, dynamic>()));
    }
    return out;
  }

  return const [];
}

List<Map> _knowledgeEdgeEntries(Object? raw) {
  if (raw is Map) {
    return raw.values.whereType<Map>().map((e) => e.cast<dynamic, dynamic>()).toList();
  }
  if (raw is List) {
    return raw.whereType<Map>().map((e) => e.cast<dynamic, dynamic>()).toList();
  }
  return const [];
}

double? _numFrom(Object? value) => value is num ? value.toDouble() : null;

int _brainSideFor(String label, String domain, int index, int total) {
  final text = '$label $domain';
  if (text.contains('claude') || text.contains('logic') || text.contains('code') || text.contains('tool')) {
    return 1;
  }
  if (text.contains('gpt') || text.contains('chat') || text.contains('memory') || text.contains('emotion')) {
    return -1;
  }
  return index < total / 2 ? -1 : 1;
}

class KaiVitals extends StatefulWidget {
  final String personaId;
  const KaiVitals({super.key, required this.personaId});

  @override
  State<KaiVitals> createState() => _KaiVitalsState();
}

class _KaiVitalsState extends State<KaiVitals> {
  final _svc = KaiStateService();
  Map<String, int> _mood = const {};
  Map<String, int> _personality = const {};
  Map<String, int> _affinity = const {};
  // Held so they can be cancelled — three REST polls per gauge panel otherwise
  // outlive the widget.
  StreamSubscription<Map<String, int>>? _moodSub;
  StreamSubscription<Map<String, int>>? _persSub;
  StreamSubscription<Map<String, int>>? _affSub;

  @override
  void dispose() {
    _moodSub?.cancel();
    _persSub?.cancel();
    _affSub?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _moodSub = _svc.moodStream(widget.personaId).listen((m) {
      if (mounted && m.isNotEmpty) setState(() => _mood = m);
    });
    _persSub = _svc.personalityStream(widget.personaId).listen((p) {
      if (mounted && p.isNotEmpty) setState(() => _personality = p);
    });
    _affSub = _svc.affinityStream(widget.personaId).listen((a) {
      if (mounted && a.isNotEmpty) setState(() => _affinity = a);
    });
    _svc.getMood(widget.personaId).then((m) {
      if (mounted && m != null && m.isNotEmpty && _mood.isEmpty) setState(() => _mood = m);
    });
    _svc.getPersonality(widget.personaId).then((p) {
      if (mounted && p != null && p.isNotEmpty && _personality.isEmpty) setState(() => _personality = p);
    });
    _svc.getAffinity(widget.personaId).then((a) {
      if (mounted && a != null && a.isNotEmpty && _affinity.isEmpty) setState(() => _affinity = a);
    });
  }

  double _m(String k) => (_mood[k] ?? 50).toDouble();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _wrap([
            _gauge('valence', _m('valence'), kClaude),
            _gauge('energy', _m('energy'), kClaude),
            _gauge('warmth', _m('warmth'), kGpt),
            _gauge('confid', _m('confidence'), kClaude),
            _gauge('play', _m('playfulness'), kGpt),
            _gauge('focus', _m('focus'), kClaude),
          ]),
        ],
      ),
    );
  }

  Widget _wrap(List<Widget> children) =>
      Wrap(spacing: 6, runSpacing: 10, children: children);

  Widget _section(String t, Color color) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          children: [
            Text(t,
                style: TextStyle(
                    color: color,
                    fontSize: 10,
                    letterSpacing: 2.2,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w700,
                    shadows: [Shadow(color: color.withOpacity(0.7), blurRadius: 8)])),
            const SizedBox(width: 8),
            Expanded(child: Container(height: 1, color: color.withOpacity(0.28))),
          ],
        ),
      );

  Widget _gauge(String label, double value, Color color) {
    return SizedBox(
      width: 72,
      child: Column(
        children: [
          SizedBox(
            width: 64,
            height: 64,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: const Size(64, 64),
                  painter: _GaugePainter(value / 100, color),
                ),
                Text(
                  '${value.round()}',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'monospace',
                    shadows: [Shadow(color: color.withOpacity(0.9), blurRadius: 10)],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: Colors.white.withOpacity(0.62),
                fontSize: 8,
                letterSpacing: 1.2,
                fontFamily: 'monospace'),
          ),
        ],
      ),
    );
  }
}

class KaiPersonalityMap extends StatefulWidget {
  final String personaId;
  const KaiPersonalityMap({super.key, required this.personaId});

  @override
  State<KaiPersonalityMap> createState() => _KaiPersonalityMapState();
}

class _KaiPersonalityMapState extends State<KaiPersonalityMap> {
  final _svc = KaiStateService();
  StreamSubscription<Map<String, int>>? _sub;
  Map<String, int> _personality = const {};

  static const _axes = [
    _MbtiAxis(left: 'I', right: 'E', keyName: 'extraversion'),
    _MbtiAxis(left: 'S', right: 'N', keyName: 'intuition'),
    _MbtiAxis(left: 'T', right: 'F', keyName: 'feeling'),
    _MbtiAxis(left: 'J', right: 'P', keyName: 'perceiving'),
  ];

  @override
  void initState() {
    super.initState();
    _sub = _svc.personalityStream(widget.personaId).listen((p) {
      if (mounted && p.isNotEmpty) setState(() => _personality = p);
    });
    _svc.getPersonality(widget.personaId).then((p) {
      if (mounted && p != null && p.isNotEmpty && _personality.isEmpty) {
        setState(() => _personality = p);
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  int _raw(String key) => (_personality[key] ?? 500).clamp(0, 1000);

  double _positive(String key) => _raw(key) / 1000.0;

  String get _type {
    final e = _positive('extraversion') >= 0.5 ? 'E' : 'I';
    final n = _positive('intuition') >= 0.5 ? 'N' : 'S';
    final f = _positive('feeling') >= 0.5 ? 'F' : 'T';
    final p = _positive('perceiving') >= 0.5 ? 'P' : 'J';
    return '$e$n$f$p';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        children: [
          Text(
            _type,
            style: TextStyle(
              color: Colors.white.withOpacity(0.92),
              fontSize: 20,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w900,
              letterSpacing: 2.0,
              shadows: [Shadow(color: kClaude.withOpacity(0.65), blurRadius: 8)],
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: CustomPaint(
              painter: _MbtiGraphPainter(
                axes: _axes,
                values: {for (final axis in _axes) axis.keyName: _positive(axis.keyName)},
              ),
              child: const SizedBox.expand(),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final axis in _axes) _axisChip(axis),
            ],
          ),
        ],
      ),
    );
  }

  Widget _axisChip(_MbtiAxis axis) {
    final positive = _positive(axis.keyName);
    final rightWins = positive >= 0.5;
    final letter = rightWins ? axis.right : axis.left;
    final strength = rightWins ? positive : 1 - positive;
    final color = rightWins ? kClaude : kGpt;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.34)),
      ),
      child: Text(
        '$letter ${(strength * 100).round()}%',
        style: TextStyle(
          color: Colors.white.withOpacity(0.78),
          fontSize: 10,
          fontFamily: 'monospace',
          fontWeight: FontWeight.w700,
          letterSpacing: 1.0,
        ),
      ),
    );
  }
}

class _MbtiAxis {
  final String left;
  final String right;
  final String keyName;
  const _MbtiAxis({required this.left, required this.right, required this.keyName});
}

class _MbtiGraphPainter extends CustomPainter {
  final List<_MbtiAxis> axes;
  final Map<String, double> values;

  const _MbtiGraphPainter({required this.axes, required this.values});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) * 0.34;
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withOpacity(0.10);

    for (final scale in const [0.25, 0.5, 0.75, 1.0]) {
      canvas.drawCircle(center, radius * scale, ringPaint);
    }

    final spokePaint = Paint()
      ..strokeWidth = 1
      ..color = Colors.white.withOpacity(0.12);

    final points = <Offset>[];
    for (var i = 0; i < axes.length; i++) {
      final axis = axes[i];
      final angle = -math.pi / 2 + (math.pi * i / axes.length);
      final dir = Offset(math.cos(angle), math.sin(angle));
      final positive = (values[axis.keyName] ?? 0.5).clamp(0.0, 1.0);
      final signed = (positive - 0.5) * 2;
      final point = center + dir * (radius * signed);
      points.add(point);

      final axisColor = Color.lerp(kGpt, kClaude, positive) ?? Colors.white;
      canvas.drawLine(center - dir * radius, center + dir * radius, spokePaint);
      canvas.drawLine(
        center,
        point,
        Paint()
          ..strokeWidth = 2.8
          ..strokeCap = StrokeCap.round
          ..color = axisColor.withOpacity(0.72),
      );
      _drawLabel(canvas, center - dir * (radius + 18), axis.left, kGpt, 12, FontWeight.w800);
      _drawLabel(canvas, center + dir * (radius + 18), axis.right, kClaude, 12, FontWeight.w800);
    }

    final poly = Path()..moveTo(points.first.dx, points.first.dy);
    for (final p in points.skip(1)) {
      poly.lineTo(p.dx, p.dy);
    }
    poly.close();

    final solidFillPaint = Paint()
      ..style = PaintingStyle.fill
      ..shader = LinearGradient(
        colors: [kGpt.withOpacity(0.72), kClaude.withOpacity(0.78)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(Rect.fromCircle(center: center, radius: radius * 1.05));
    canvas.drawPath(poly, solidFillPaint);

    final glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeJoin = StrokeJoin.round
      ..color = kClaude.withOpacity(0.22)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
    canvas.drawPath(poly, glowPaint);

    canvas.drawPath(
      poly,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeJoin = StrokeJoin.round
        ..color = Colors.white.withOpacity(0.88),
    );

    for (final p in points) {
      canvas.drawCircle(p, 4.5, Paint()..color = kClaude.withOpacity(0.85));
      canvas.drawCircle(
        p,
        8,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = Colors.white.withOpacity(0.22),
      );
    }

    // MBTI type is rendered above the graph by the widget, not inside the canvas.
  }

  void _drawLabel(Canvas canvas, Offset center, String text, Color color, double size, FontWeight weight) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: size,
          fontFamily: 'monospace',
          fontWeight: weight,
          letterSpacing: size > 14 ? 2.0 : 1.2,
          shadows: [Shadow(color: color.withOpacity(0.65), blurRadius: 8)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, center - Offset(painter.width / 2, painter.height / 2));
  }

  @override
  // `type` used to live on this painter; it moved out to the widget (see the
  // note in paint()). shouldRepaint kept pointing at the ghost — compare the
  // fields the painter actually has.
  bool shouldRepaint(covariant _MbtiGraphPainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.axes != axes;
}

class _GaugePainter extends CustomPainter {
  final double pct;
  final Color color;
  _GaugePainter(this.pct, this.color);

  static const _start = 3 * math.pi / 4;
  static const _sweep = 3 * math.pi / 2;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - 5;
    final rect = Rect.fromCircle(center: c, radius: r);

    final tick = Paint()..strokeWidth = 1;
    for (int i = 0; i <= 24; i++) {
      final a = _start + _sweep * (i / 24);
      final long = i % 6 == 0;
      final r0 = r - (long ? 6 : 3);
      canvas.drawLine(
        Offset(c.dx + math.cos(a) * r0, c.dy + math.sin(a) * r0),
        Offset(c.dx + math.cos(a) * r, c.dy + math.sin(a) * r),
        tick..color = color.withOpacity(long ? 0.4 : 0.2),
      );
    }

    canvas.drawArc(
      rect, _start, _sweep, false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5
        ..color = Colors.white.withOpacity(0.08),
    );

    final vw = _sweep * pct.clamp(0.0, 1.0);
    canvas.drawArc(
      rect, _start, vw, false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round
        ..color = color.withOpacity(0.85)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawArc(
      rect, _start, vw, false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..color = color,
    );

    canvas.drawCircle(
      c, r * 0.6,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = color.withOpacity(0.22),
    );
  }

  @override
  bool shouldRepaint(covariant _GaugePainter old) =>
      old.pct != pct || old.color != color;
}

// ── Brain painter ────────────────────────────────────────────────────────────

class _BrainPainter extends CustomPainter {
  final List<_Node> nodes;
  final List<List<int>> links;
  final double yaw, pitch, pulse, energy, valence, radiusFactor;

  _BrainPainter({
    required this.nodes,
    required this.links,
    required this.yaw,
    required this.pitch,
    required this.pulse,
    required this.energy,
    required this.valence,
    this.radiusFactor = 0.30,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    final grow = 0.86 + 0.28 * ((valence + energy) / 2);
    final breathe = 1 + (0.05 + 0.05 * energy) * math.sin(pulse * math.pi * 2);
    final R = math.min(size.width, size.height) * radiusFactor * grow * breathe;

    final gptCol = Color.lerp(kGpt, Colors.white, 0.16 * energy)!;
    final clCol = Color.lerp(kClaude, Colors.white, 0.16 * energy)!;

    // twin halos, one per hemisphere
    final haloR = R * 1.8;
    canvas.drawCircle(
      Offset(cx - R * 0.5, cy),
      haloR,
      Paint()
        ..shader = RadialGradient(colors: [gptCol.withOpacity(0.14 + 0.12 * energy), Colors.transparent])
            .createShader(Rect.fromCircle(center: Offset(cx - R * 0.5, cy), radius: haloR)),
    );
    canvas.drawCircle(
      Offset(cx + R * 0.5, cy),
      haloR,
      Paint()
        ..shader = RadialGradient(colors: [clCol.withOpacity(0.14 + 0.12 * energy), Colors.transparent])
            .createShader(Rect.fromCircle(center: Offset(cx + R * 0.5, cy), radius: haloR)),
    );

    final cyw = math.cos(yaw), syw = math.sin(yaw);
    final cxp = math.cos(pitch), sxp = math.sin(pitch);
    final proj = List<_Proj>.filled(nodes.length, const _Proj(0, 0, 0, 0));
    const fov = 3.2;
    for (var i = 0; i < nodes.length; i++) {
      final p = nodes[i].p;
      final x1 = p.x * cyw + p.z * syw;
      final z1 = -p.x * syw + p.z * cyw;
      final y1 = p.y;
      final y2 = y1 * cxp - z1 * sxp;
      final z2 = y1 * sxp + z1 * cxp;
      final persp = fov / (fov - z2);
      proj[i] = _Proj(cx + x1 * persp * R, cy + y2 * persp * R, z2, persp);
    }

    for (var i = 0; i < links.length; i++) {
      for (final j in links[i]) {
        final a = proj[i], b = proj[j];
        final depth = ((a.z + b.z) / 2 + 1) / 2;
        final alpha = (0.05 + 0.24 * depth) * (0.6 + 0.4 * pulse);
        final col = nodes[i].lobe == 0 ? gptCol : clCol;
        canvas.drawLine(
          Offset(a.x, a.y),
          Offset(b.x, b.y),
          Paint()
            ..color = col.withOpacity(alpha.clamp(0.0, 0.55))
            ..strokeWidth = 0.9,
        );
      }
    }

    final order = List<int>.generate(nodes.length, (i) => i)
      ..sort((a, b) => proj[a].z.compareTo(proj[b].z));
    for (final i in order) {
      final pr = proj[i];
      final depth = (pr.z + 1) / 2;
      final col = nodes[i].lobe == 0 ? gptCol : clCol;
      final r = (1.4 + 3.2 * depth) * pr.persp;
      final a = 0.28 + 0.7 * depth;
      canvas.drawCircle(
        Offset(pr.x, pr.y),
        r * 2.6,
        Paint()
          ..color = col.withOpacity(0.12 * a)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
      canvas.drawCircle(
        Offset(pr.x, pr.y),
        r,
        Paint()..color = Color.lerp(col, Colors.white, 0.3 * depth)!.withOpacity(a),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BrainPainter old) => true;
}
