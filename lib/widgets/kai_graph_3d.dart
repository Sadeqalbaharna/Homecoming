// KaiGraph3D — his knowledge graph, in 3D, drawn natively.
//
// Why native and not the Three.js scene in assets/brain/kai_cortex.html:
// `webview_flutter` has no Windows implementation. It resolves to _android,
// _wkwebview and _platform_interface — that's it. On Windows,
// `WebViewPlatform.instance` is null and constructing a controller throws. The
// shell hid that for a long time behind `try{...}catch(_){}`, which is why the
// cortex was dead and silent rather than dead and loud. §4.5 of the handover
// records the identical hole in `firebase_database`.
//
// So this draws the graph with a CustomPainter: no plugin, no WebView2 runtime,
// no nuget, and the same picture on Windows and mobile.
//
// The shape comes from the LINKS.
//
//   Sadeq's spec, verbatim: "it shouldn't be in clusters of types but links and
//   nodes, so a node that is Sadeq and Kai would have a link of 'cares for'".
//
// That's not a layout preference, it's the data model. Nodes are entities.
// Edges carry the claim. Things sit near each other because they are actually
// related — not because someone filed them under the same heading. Every prior
// version of this scattered nodes at random inside a brain silhouette and threw
// the real structure away.

library;

import 'dart:async';
import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;

import '../models/knowledge_node.dart';
import '../services/core/firebase_service.dart';
import '../services/core/kai_db.dart';

const _kGpt = Color(0xFFFF9D2F);
const _kClaude = Color(0xFF2ED9FF);
const _kShared = Color(0xFFFFCF6A);

// ── internals ────────────────────────────────────────────────────────────────

class _V3 {
  double x, y, z;
  _V3(this.x, this.y, this.z);
}

class _GNode {
  final String id;
  final String label;
  final NodeType type;
  final double importance;
  final _V3 p = _V3(0, 0, 0);
  final _V3 v = _V3(0, 0, 0);
  _GNode(this.id, this.label, this.type, this.importance);
}

class _GEdge {
  final int a;
  final int b;
  final String relation;
  final EdgeType type;
  final double strength;

  /// Retired — he used to believe this. Drawn as a ghost, never as a fact.
  final bool superseded;

  /// Memory shards this claim came from. The map can point at the words.
  final List<String> sources;

  _GEdge(this.a, this.b, this.relation, this.type, this.strength,
      {this.superseded = false, this.sources = const []});
}

class KaiGraph3D extends StatefulWidget {
  final String personaId;

  /// Cap, strongest-importance first. The layout is O(n²) per rebuild and every
  /// node paints a label; 120 is comfortable, unbounded is a slideshow.
  final int maxNodes;

  /// Hide the chrome (counts, hint) when this is a small dashboard pane.
  final bool compact;

  const KaiGraph3D({
    super.key,
    required this.personaId,
    this.maxNodes = 120,
    this.compact = false,
  });

  @override
  State<KaiGraph3D> createState() => _KaiGraph3DState();
}

class _KaiGraph3DState extends State<KaiGraph3D>
    with SingleTickerProviderStateMixin {
  final List<_GNode> _nodes = [];
  final List<_GEdge> _edges = [];
  StreamSubscription? _sub;
  Timer? _debounce;
  Ticker? _ticker;

  double _yaw = 0.4;
  double _pitch = -0.15;
  double _zoom = 1.0;
  bool _autoRotate = true;

  // gesture bookkeeping
  double _zoom0 = 1;

  @override
  void initState() {
    super.initState();
    _startSync();
    _ticker = createTicker((_) {
      if (_autoRotate) {
        _yaw += 0.0016;
        if (mounted) setState(() {});
      }
    })
      ..start();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _debounce?.cancel();
    _ticker?.dispose();
    super.dispose();
  }

  void _startSync() {
    if (!FirebaseService.isAvailable) return;
    _sub = KaiDb.instance
        .ref('knowledge_graph/${widget.personaId}')
        .onValue
        .listen((e) {
      // Desktop `onValue` is a 4s REST poll — it fires whether or not anything
      // changed. Debounce, or the layout re-runs faster than it can be drawn.
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 350), () {
        _rebuild(e.snapshot.value);
      });
    }, onError: (_) {});
  }

  void _rebuild(Object? raw) {
    if (raw is! Map) return;
    final m = Map<String, dynamic>.from(raw);

    // ── nodes ───────────────────────────────────────────────────────────────
    final all = <_GNode>[];
    for (final n in _asList(m['nodes'])) {
      if (n is! Map) continue;
      final nm = Map<String, dynamic>.from(n);
      final id = nm['id']?.toString();
      final label = (nm['label'] ?? '').toString();
      if (id == null || label.isEmpty) continue;
      all.add(_GNode(
        id,
        label,
        _parseType(nm['type']?.toString() ?? ''),
        (nm['importance'] as num?)?.toDouble() ?? 0.5,
      ));
    }
    if (all.isEmpty) return;
    all.sort((a, b) => b.importance.compareTo(a.importance));
    final nodes = all.take(widget.maxNodes).toList();
    final idx = <String, int>{};
    for (var i = 0; i < nodes.length; i++) {
      idx[nodes[i].id] = i;
    }

    // ── edges ───────────────────────────────────────────────────────────────
    final edges = <_GEdge>[];
    for (final e in _asList(m['edges'])) {
      if (e is! Map) continue;
      final em = Map<String, dynamic>.from(e);
      final a = idx[(em['fromId'] ?? em['from'] ?? em['source'])?.toString()];
      final b = idx[(em['toId'] ?? em['to'] ?? em['target'])?.toString()];
      if (a == null || b == null || a == b) continue;
      edges.add(_GEdge(
        a,
        b,
        (em['label'] ?? '').toString().trim(),
        _parseEdge(em['type']?.toString() ?? ''),
        (em['strength'] as num?)?.toDouble() ?? 0.5,
        superseded: em['supersededAt'] != null,
        sources: (em['sources'] as List?)?.map((e) => e.toString()).toList() ??
            const [],
      ));
    }

    _layout(nodes, edges);

    setState(() {
      _nodes
        ..clear()
        ..addAll(nodes);
      _edges
        ..clear()
        ..addAll(edges);
    });
  }

  // ── 3D force-directed layout ──────────────────────────────────────────────
  //
  // Fruchterman–Reingold. O(n²) repulsion, which is fine: n is capped and this
  // runs once per graph change, not per frame.
  static void _layout(List<_GNode> ns, List<_GEdge> es) {
    final n = ns.length;
    if (n == 0) return;

    // Fibonacci-sphere seed. Deterministic on purpose — a reload shouldn't
    // reshuffle his whole head and make you relearn where everything lives.
    for (var i = 0; i < n; i++) {
      final y = 1 - (i / max(1, n - 1)) * 2;
      final r = sqrt(max(0, 1 - y * y));
      final th = i * 2.399963229;
      ns[i].p
        ..x = cos(th) * r * 120
        ..y = y * 120
        ..z = sin(th) * r * 120;
      ns[i].v
        ..x = 0
        ..y = 0
        ..z = 0;
    }

    const k = 68.0, iters = 320;
    for (var it = 0; it < iters; it++) {
      final t = 1 - it / iters; // cooling

      for (var i = 0; i < n; i++) {
        for (var j = i + 1; j < n; j++) {
          var dx = ns[i].p.x - ns[j].p.x;
          var dy = ns[i].p.y - ns[j].p.y;
          var dz = ns[i].p.z - ns[j].p.z;
          var dd = dx * dx + dy * dy + dz * dz;
          if (dd < 0.01) {
            dx = 0.1;
            dy = 0.1;
            dz = 0.1;
            dd = 0.03;
          }
          final d = sqrt(dd), f = (k * k) / dd;
          final ux = dx / d, uy = dy / d, uz = dz / d;
          ns[i].v..x += ux * f..y += uy * f..z += uz * f;
          ns[j].v..x -= ux * f..y -= uy * f..z -= uz * f;
        }
      }

      // Attraction along real edges. A stronger relationship pulls harder, so
      // "cares about" sits tighter than "mentioned once".
      for (final e in es) {
        // A belief he's retired shouldn't still be shaping the map. It stays
        // visible as history; it stops having gravity.
        if (e.superseded) continue;
        final a = ns[e.a], b = ns[e.b];
        final dx = a.p.x - b.p.x, dy = a.p.y - b.p.y, dz = a.p.z - b.p.z;
        final d = sqrt(dx * dx + dy * dy + dz * dz);
        if (d < 0.01) continue;
        final f = (d * d) / k * (0.4 + e.strength);
        final ux = dx / d, uy = dy / d, uz = dz / d;
        a.v..x -= ux * f..y -= uy * f..z -= uz * f;
        b.v..x += ux * f..y += uy * f..z += uz * f;
      }

      for (var i = 0; i < n; i++) {
        final o = ns[i];
        o.v..x -= o.p.x * 0.012..y -= o.p.y * 0.012..z -= o.p.z * 0.012;
        final sp = sqrt(o.v.x * o.v.x + o.v.y * o.v.y + o.v.z * o.v.z);
        final cap = sp < 1e-6 ? 0.0 : min(sp, 12 * t + 0.6) / sp;
        o.p..x += o.v.x * cap..y += o.v.y * cap..z += o.v.z * cap;
        o.v..x *= 0.55..y *= 0.55..z *= 0.55;
      }
    }

    var mx = 1.0;
    for (final o in ns) {
      mx = max(mx, sqrt(o.p.x * o.p.x + o.p.y * o.p.y + o.p.z * o.p.z));
    }
    final s = 150 / mx;
    for (final o in ns) {
      o.p..x *= s..y *= s..z *= s;
    }
  }

  static List<dynamic> _asList(dynamic v) {
    if (v is List) return v.where((e) => e != null).toList();
    if (v is Map) return v.values.where((e) => e != null).toList();
    return const [];
  }

  static NodeType _parseType(String s) => NodeType.values.firstWhere(
        (t) => t.name == s,
        orElse: () => NodeType.concept,
      );

  static EdgeType _parseEdge(String s) => EdgeType.values.firstWhere(
        (t) => t.name == s,
        orElse: () => EdgeType.related,
      );

  @override
  Widget build(BuildContext context) {
    if (_nodes.isEmpty) {
      return Center(
        child: Text(
          FirebaseService.isAvailable ? 'mapping…' : 'offline',
          style: TextStyle(
              color: Colors.white.withOpacity(0.30),
              fontSize: 10,
              letterSpacing: 2,
              fontFamily: 'monospace'),
        ),
      );
    }

    return Listener(
      // Scroll wheel — the desktop way to zoom. Trackpad pinch arrives here too.
      onPointerSignal: (s) {
        if (s is PointerScrollEvent) {
          setState(() {
            _zoom = (_zoom * (1 - s.scrollDelta.dy / 900)).clamp(0.35, 4.0);
          });
        }
      },
      // Scale only — never scale + pan together. Flutter asserts if a pan and a
      // scale recognizer are both declared, and a one-finger drag arrives here
      // anyway as focalPointDelta with pointerCount == 1.
      child: GestureDetector(
        onScaleStart: (_) {
          _zoom0 = _zoom;
          // Stop spinning the instant it's grabbed. Autorotate fighting a drag
          // is maddening when you're trying to read a label.
          _autoRotate = false;
        },
        onScaleUpdate: (d) {
          setState(() {
            // Two fingers → pinch zoom. One finger (or mouse drag) → orbit.
            if (d.pointerCount > 1) {
              _zoom = (_zoom0 * d.scale).clamp(0.35, 4.0);
            }
            _yaw += d.focalPointDelta.dx * 0.006;
            _pitch = (_pitch + d.focalPointDelta.dy * 0.006).clamp(-1.4, 1.4);
          });
        },
        onDoubleTap: () => setState(() {
          _autoRotate = true;
          _zoom = 1.0;
          _pitch = -0.15;
        }),
        child: CustomPaint(
          painter: _GraphPainter(
            nodes: _nodes,
            edges: _edges,
            yaw: _yaw,
            pitch: _pitch,
            zoom: _zoom,
            compact: widget.compact,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _GraphPainter extends CustomPainter {
  final List<_GNode> nodes;
  final List<_GEdge> edges;
  final double yaw, pitch, zoom;
  final bool compact;

  _GraphPainter({
    required this.nodes,
    required this.edges,
    required this.yaw,
    required this.pitch,
    required this.zoom,
    required this.compact,
  });

  // Rotate by yaw/pitch, then perspective-divide. Returns screen point + a
  // depth factor (1 = near, 0 = far) used for size, alpha and label culling.
  ({Offset p, double depth}) _project(_V3 v, Size size) {
    final cy = cos(yaw), sy = sin(yaw);
    final x1 = v.x * cy - v.z * sy;
    final z1 = v.x * sy + v.z * cy;
    final cp = cos(pitch), sp = sin(pitch);
    final y2 = v.y * cp - z1 * sp;
    final z2 = v.y * sp + z1 * cp;

    const camZ = 420.0;
    final persp = camZ / (camZ + z2);
    final s = min(size.width, size.height) / 380 * zoom;
    return (
      p: Offset(
        size.width / 2 + x1 * persp * s,
        size.height / 2 + y2 * persp * s,
      ),
      depth: persp.clamp(0.35, 2.2),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (nodes.isEmpty) return;

    final proj = nodes.map((n) => _project(n.p, size)).toList();

    // ── edges ───────────────────────────────────────────────────────────────
    // Coloured by EdgeType — the switch in models/knowledge_node.dart that has
    // existed since the model was written and never once fired, because every
    // edge was stamped `related` on the way in.
    for (final e in edges) {
      final a = proj[e.a], b = proj[e.b];
      final depth = (a.depth + b.depth) / 2;
      final base = KnowledgeEdge(
        fromId: '', toId: '', type: e.type,
        strength: e.strength, timestamp: DateTime.now(),
      ).color;

      // Superseded claims are drawn as faint grey ghosts — he used to think
      // this. Kept, not deleted: a mind that changed is more real than one that
      // was always right, and "he believed X until March" is knowledge too.
      final col = e.superseded ? const Color(0xFF6B7A88) : base;
      final op = e.superseded
          ? 0.10 * depth
          : (base.opacity * (0.35 + e.strength * 0.5) * depth);

      canvas.drawLine(
        a.p,
        b.p,
        Paint()
          ..color = col.withOpacity(op.clamp(0.0, 0.9))
          ..strokeWidth =
              (e.superseded ? 0.5 : (0.6 + e.strength * 1.4)) * depth,
      );
    }

    // ── relation labels ─────────────────────────────────────────────────────
    // "cares for" on the wire — the thing this whole exercise exists for. Only
    // when zoomed in: every relation at once is an unreadable hairball.
    if (zoom > 1.35) {
      final reveal = ((zoom - 1.35) / 0.5).clamp(0.0, 1.0);
      for (final e in edges) {
        if (e.relation.isEmpty || e.relation == 'relates to') continue;
        if (e.superseded) continue; // history, not a current claim
        final a = proj[e.a], b = proj[e.b];
        final depth = (a.depth + b.depth) / 2;
        if (depth < 0.75) continue; // behind the mass — don't clutter
        _text(
          canvas,
          Offset((a.p.dx + b.p.dx) / 2, (a.p.dy + b.p.dy) / 2),
          e.relation,
          const Color(0xFFA8C6DE).withOpacity(0.85 * reveal),
          8.5,
        );
      }
    }

    // ── nodes, painter's algorithm (far first) ──────────────────────────────
    final order = List.generate(nodes.length, (i) => i)
      ..sort((i, j) => proj[i].depth.compareTo(proj[j].depth));

    for (final i in order) {
      final n = nodes[i];
      final pr = proj[i];
      final col = _nodeColour(n.type);
      final r = (1.6 + n.importance * 3.4) * pr.depth;

      // cheap bloom: a wide soft disc under a bright core
      canvas.drawCircle(pr.p, r * 2.6,
          Paint()..color = col.withOpacity(0.10 * pr.depth));
      canvas.drawCircle(pr.p, r,
          Paint()..color = col.withOpacity((0.55 + n.importance * 0.45).clamp(0.0, 1.0)));
    }

    // ── node names ──────────────────────────────────────────────────────────
    // Legible at rest — you should be able to read what's in there without
    // flying around. Culled to the front half so the back doesn't bleed through.
    final labelBudget = compact ? 14 : 48;
    final byImp = List.generate(nodes.length, (i) => i)
      ..sort((i, j) => nodes[j].importance.compareTo(nodes[i].importance));
    var drawn = 0;
    for (final i in byImp) {
      if (drawn >= labelBudget) break;
      final pr = proj[i];
      if (pr.depth < 0.9) continue;
      _text(
        canvas,
        pr.p + Offset(0, -(6 + nodes[i].importance * 4)),
        nodes[i].label,
        _nodeColour(nodes[i].type)
            .withOpacity((0.45 + nodes[i].importance * 0.5).clamp(0.0, 0.95)),
        compact ? 7.5 : 9.5,
      );
      drawn++;
    }

    if (!compact) {
      _text(
        canvas,
        Offset(size.width / 2, size.height - 12),
        '${nodes.length} nodes · ${edges.length} links · drag to orbit · scroll to zoom',
        Colors.white.withOpacity(0.28),
        8,
      );
    }
  }

  static Color _nodeColour(NodeType t) {
    switch (t) {
      case NodeType.person:
        return _kShared;
      case NodeType.topic:
      case NodeType.memory:
        return _kShared.withOpacity(0.9);
      case NodeType.emotion:
      case NodeType.preference:
        return _kGpt;
      case NodeType.belief:
      case NodeType.goal:
      case NodeType.concept:
        return _kClaude;
      default:
        return _kClaude.withOpacity(0.75);
    }
  }

  void _text(Canvas c, Offset at, String s, Color col, double size) {
    final tp = TextPainter(
      text: TextSpan(
        text: s.length > 26 ? '${s.substring(0, 25)}…' : s,
        style: TextStyle(
          color: col,
          fontSize: size,
          fontFamily: 'monospace',
          letterSpacing: 0.4,
          shadows: [Shadow(color: col.withOpacity(0.5), blurRadius: 6)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, at - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _GraphPainter old) =>
      old.yaw != yaw ||
      old.pitch != pitch ||
      old.zoom != zoom ||
      old.nodes != nodes ||
      old.edges != edges;
}
