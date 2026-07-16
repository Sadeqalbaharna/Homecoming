// Brain3DScreen
// Renders Kai's knowledge graph as an interactive 3D force-directed graph
// using Three.js via WebView. Touch to rotate, pinch to zoom, tap nodes to inspect.
//
// Uses 3d-force-graph (vasturiano) — Three.js + OrbitControls under the hood.
// Graph data is loaded from Firebase and injected into the HTML at render time.

import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../services/core/kai_db.dart';
import '../services/core/firebase_service.dart';
import '../services/core/brain_extraction_service.dart';
import '../tools/brain_backfill.dart';
import 'chatgpt_import_screen.dart';

List<dynamic> _asList(dynamic v) {
  if (v is List) return v;
  if (v is Map) return v.values.toList();
  return [];
}

class Brain3DScreen extends StatefulWidget {
  final String personaId;
  const Brain3DScreen({super.key, required this.personaId});

  @override
  State<Brain3DScreen> createState() => _Brain3DScreenState();
}

class _Brain3DScreenState extends State<Brain3DScreen> {
  WebViewController? _controller;
  Map<String, dynamic>? _graphData;
  bool _loading = true;
  String? _error;

  bool get _useNativeInspector =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  // Backfill state
  bool _backfilling = false;
  String? _backfillStatus;

  // Label overlay toggle
  bool _showLabels = false;

  // Desktop native mind-map selection.
  String? _selectedNativeNodeId;

  @override
  void initState() {
    super.initState();
    _initGraph();
  }

  Future<void> _initGraph() async {
    try {
      final graphData = await _loadGraphData();

      if (_useNativeInspector) {
        if (mounted) {
          setState(() {
            _graphData = graphData;
            _controller = null;
            _loading = false;
          });
        }
        return;
      }

      final html = _buildHtml(graphData);

      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(const Color(0xFF000011))
        ..loadHtmlString(html, baseUrl: 'https://localhost');

      if (mounted) {
        setState(() {
          _graphData = graphData;
          _controller = controller;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _runBackfill() async {
    if (_backfilling) return;
    setState(() {
      _backfilling = true;
      _backfillStatus = 'Starting…';
    });

    try {
      final result = await BrainBackfill.run(
        widget.personaId,
        onProgress: (msg) {
          if (mounted) setState(() => _backfillStatus = msg);
        },
      );

      if (mounted) {
        setState(() {
          _backfilling = false;
          _backfillStatus =
              'Done — ${result.written} turns extracted, ${result.skipped} skipped.';
        });
        // Reload the graph to show new nodes
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) {
          setState(() {
            _backfillStatus = null;
            _loading = true;
          });
          _initGraph();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _backfilling = false;
          _backfillStatus = 'Error: $e';
        });
      }
    }
  }

  Future<void> _runPrune() async {
    if (_backfilling) return;
    setState(() {
      _backfilling = true;
      _backfillStatus = 'Pruning noise nodes…';
    });
    try {
      final removed = await BrainExtractionService().pruneGraph(widget.personaId);
      if (mounted) {
        setState(() {
          _backfilling = false;
          _backfillStatus = removed > 0
              ? 'Pruned $removed noise nodes.'
              : 'Nothing to prune — graph is clean.';
        });
        if (removed > 0) {
          await Future.delayed(const Duration(seconds: 2));
          if (mounted) {
            setState(() { _backfillStatus = null; _loading = true; });
            _initGraph();
          }
        } else {
          await Future.delayed(const Duration(seconds: 2));
          if (mounted) setState(() => _backfillStatus = null);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() { _backfilling = false; _backfillStatus = 'Error: $e'; });
      }
    }
  }

  Future<Map<String, dynamic>> _loadGraphData() async {
    if (!FirebaseService.isAvailable) {
      return {'nodes': [], 'links': []};
    }

    final snap = await KaiDb.instance
        .ref('knowledge_graph/${widget.personaId}')
        .get();

    if (!snap.exists || snap.value == null) {
      return {'nodes': [], 'links': []};
    }

    final raw = Map<String, dynamic>.from(snap.value as Map);

    // Build nodes list
    final nodes = <Map<String, dynamic>>[];
    for (final n in _asList(raw['nodes'])) {
      final m = Map<String, dynamic>.from(n as Map);
      final meta = m['metadata'] as Map?;
      nodes.add({
        'id':         m['id'],
        'label':      m['label'] ?? '',
        'type':       m['type'] ?? 'concept',
        'importance': (m['importance'] as num?)?.toDouble() ?? 0.5,
        // Age data — used for vitality-based brightness in the 3D renderer
        'lastSeen':   meta?['lastSeen'],  // ms epoch of last access
        'timestamp':  m['timestamp'],      // ms epoch of creation
      });
    }

    // Build links list (3d-force-graph uses 'source'/'target')
    final links = <Map<String, dynamic>>[];
    for (final e in _asList(raw['edges'])) {
      final m = Map<String, dynamic>.from(e as Map);
      links.add({
        'source':   m['fromId'],
        'target':   m['toId'],
        'relation': m['label'] ?? '',
        'strength': (m['strength'] as num?)?.toDouble() ?? 0.5,
      });
    }

    return {'nodes': nodes, 'links': links};
  }

  String _buildHtml(Map<String, dynamic> graphData) {
    final jsonData = jsonEncode(graphData);
    final nodeCount = (graphData['nodes'] as List).length;

    return '''<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, user-scalable=no">
<style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body { background: #000011; overflow: hidden; font-family: -apple-system, sans-serif; }
  #graph { width: 100vw; height: 100vh; }
  #info {
    position: fixed; top: 12px; left: 12px;
    color: rgba(255,231,176,0.4); font-size: 11px; letter-spacing: 1px;
    pointer-events: none;
  }
  #tooltip {
    position: fixed; display: none;
    background: rgba(10,8,5,0.92); border: 1px solid rgba(255,231,176,0.3);
    color: #FFE7B0; padding: 10px 14px; border-radius: 10px;
    font-size: 13px; pointer-events: none; max-width: 220px;
    bottom: 100px; left: 50%; transform: translateX(-50%);
  }
  /* Zoom controls bottom-right */
  #zoom-controls {
    position: fixed; bottom: 32px; right: 20px;
    display: flex; flex-direction: column; gap: 8px;
    z-index: 100;
  }
  .zoom-btn {
    width: 44px; height: 44px;
    background: rgba(13,10,7,0.85);
    border: 1px solid rgba(255,231,176,0.35);
    border-radius: 12px;
    color: #FFE7B0; font-size: 20px; line-height: 44px; text-align: center;
    cursor: pointer; user-select: none;
    -webkit-tap-highlight-color: transparent;
  }
  .zoom-btn:active { background: rgba(255,231,176,0.15); }
  /* Fit-all button bottom-left */
  #fit-btn {
    position: fixed; bottom: 32px; left: 20px;
    background: rgba(13,10,7,0.85);
    border: 1px solid rgba(255,231,176,0.35);
    border-radius: 12px;
    color: rgba(255,231,176,0.8); font-size: 11px; letter-spacing: 0.5px;
    padding: 10px 14px; cursor: pointer;
    -webkit-tap-highlight-color: transparent;
    z-index: 100;
  }
  #fit-btn:active { background: rgba(255,231,176,0.15); }
</style>
</head>
<body>
<div id="graph"></div>
<div id="info">${nodeCount} nodes</div>
<div id="tooltip"></div>

<div id="zoom-controls">
  <div class="zoom-btn" id="zoom-in">+</div>
  <div class="zoom-btn" id="zoom-out">−</div>
</div>
<div id="fit-btn">⊙ Fit all</div>

<script src="https://unpkg.com/3d-force-graph@1.73.4/dist/3d-force-graph.min.js"></script>
<script>
const graphData = $jsonData;

const tooltip = document.getElementById('tooltip');

// Label visibility state — toggled by toggleLabels()
let showLabels = false;

// ── Vitality-based node color ──────────────────────────────────────────────
// Each node's color is determined by two factors:
//   • Type (sets the hue — preserves color identity)
//   • Vitality (sets saturation + lightness — newest/most-important = bright,
//     oldest/forgotten = dim)
//
// Vitality = weighted blend of importance (0.65) + freshness (0.35)
// Freshness decays linearly over 45 days of no access.
//
// Result: nodes glow gold-bright when fresh; fade to dim blue-gray when stale.

const typeHues = {
  concept:    200,  // sky blue
  emotion:    35,   // amber
  belief:     260,  // violet
  memory:     120,  // mint green
  question:   50,   // gold
  goal:       300,  // rose
  preference: 5,    // coral
  insight:    210,  // steel blue
  person:     0,    // achromatic (white → dark gray)
  topic:      200,  // sky blue
  value:      35,   // amber
  pattern:    260,  // violet
  fact:       0,    // gray
  event:      130,  // pale green
  location:   55,   // khaki
};

function nodeVitality(node) {
  const imp      = node.importance || 0.5;
  const lastSeen = node.lastSeen || node.timestamp || Date.now();
  const ageDays  = Math.max(0, (Date.now() - lastSeen) / 86400000);
  const fresh    = Math.max(0, 1.0 - ageDays / 45.0); // 1.0 → 0.0 over 45 days
  return Math.min(1.0, imp * 0.65 + fresh * 0.35);
}

function nodeColorFn(node) {
  const v = nodeVitality(node);
  const hue = typeHues[node.type] || 200;
  if (node.type === 'person' || node.type === 'fact') {
    // Achromatic: bright white → dark charcoal
    const l = Math.round(18 + v * 67);
    return \`hsl(0, 0%, \${l}%)\`;
  }
  const sat   = Math.round(45 + v * 45);   // 45 % dim → 90 % vivid
  const light = Math.round(18 + v * 52);   // 18 % dark → 70 % bright
  return \`hsl(\${hue}, \${sat}%, \${light}%)\`;
}

// ── Canvas-based text sprite ───────────────────────────────────────────────
// No external three-spritetext dependency — uses THREE directly (which 3d-force-graph
// exposes globally as window.THREE in its UMD build).
function makeTextSprite(text) {
  if (!window.THREE) return null;
  const canvas = document.createElement('canvas');
  const ctx = canvas.getContext('2d');
  const fontSize = 26;
  const pad = 6;
  ctx.font = '600 ' + fontSize + 'px -apple-system, Helvetica Neue, sans-serif';
  const textW = Math.ceil(ctx.measureText(text).width);
  canvas.width  = textW + pad * 2;
  canvas.height = fontSize + pad * 2;
  // Redraw after canvas resize (resize clears the context state)
  ctx.font = '600 ' + fontSize + 'px -apple-system, Helvetica Neue, sans-serif';
  ctx.fillStyle = 'rgba(0,0,17,0.60)';
  ctx.fillRect(0, 0, canvas.width, canvas.height);
  ctx.fillStyle = '#FFE7B0';
  ctx.fillText(text, pad, fontSize + pad * 0.55);
  const texture  = new THREE.CanvasTexture(canvas);
  const material = new THREE.SpriteMaterial({ map: texture, transparent: true, depthWrite: false });
  const sprite   = new THREE.Sprite(material);
  const aspect   = canvas.width / canvas.height;
  sprite.scale.set(aspect * 9, 9, 1);
  return sprite;
}

const Graph = ForceGraph3D()(document.getElementById('graph'))
  .backgroundColor('#000011')
  .showNavInfo(false)

  // Nodes
  .nodeId('id')
  .nodeLabel('')          // suppress the built-in hover tooltip (we tap to inspect)
  .nodeColor(nodeColorFn)
  .nodeVal(n => Math.pow((n.importance || 0.5) * 6, 2))
  .nodeOpacity(0.92)
  .nodeResolution(12)

  // Label sprites — canvas-based THREE.Sprite floating above each node.
  // nodeThreeObjectExtend(true) keeps the default sphere; returning null is safe.
  .nodeThreeObjectExtend(true)
  .nodeThreeObject(node => {
    try {
      const sprite = makeTextSprite(node.label || node.id || '');
      if (!sprite) return null;
      const r = Math.pow((node.importance || 0.5) * 6, 2);
      sprite.position.set(0, Math.sqrt(r) + 5, 0);
      sprite.visible = showLabels;
      return sprite;
    } catch (_) {
      return null;  // fall back to default sphere — never crash node rendering
    }
  })

  // Links — width and opacity both scale with strength so weak links fade into
  // the background and strong connections stand clearly visible.
  .linkSource('source')
  .linkTarget('target')
  .linkColor(l => {
    const s = l.strength || 0.5;
    // Weak links (0.1) → barely visible; strong links (1.0) → clearly amber
    return \`rgba(255, 231, 176, \${(0.06 + s * 0.70).toFixed(2)})\`;
  })
  .linkWidth(l => Math.max(0.4, (l.strength || 0.5) * 3.5))
  .linkOpacity(1.0)   // opacity handled per-link via linkColor rgba
  .linkDirectionalParticles(l => Math.ceil((l.strength || 0.3) * 3))
  .linkDirectionalParticleWidth(l => (l.strength || 0.3) * 2.0)
  .linkDirectionalParticleColor(() => 'rgba(255,231,176,0.85)')
  .linkDirectionalParticleSpeed(0.004)

  // Interaction
  .onNodeClick(node => {
    const links = graphData.links.filter(
      l => l.source === node.id || l.target === node.id ||
           (l.source && l.source.id === node.id) ||
           (l.target && l.target.id === node.id)
    );
    const connected = links.map(l => {
      const other = (l.source.id || l.source) === node.id
        ? (l.target.label || l.target) : (l.source.label || l.source);
      return \`\${l.relation || '→'} \${other}\`;
    }).slice(0, 5).join('<br>');
    const v = nodeVitality(node);
    const imp = ((node.importance || 0.5) * 100).toFixed(0);
    const vPct = (v * 100).toFixed(0);
    tooltip.innerHTML = \`<b>\${node.label}</b><br><span style="opacity:0.6">\${node.type} · imp \${imp}% · vitality \${vPct}%</span>\${connected ? '<br><br>' + connected : ''}\`;
    tooltip.style.display = 'block';
    setTimeout(() => tooltip.style.display = 'none', 3000);
  })
  .onBackgroundClick(() => { tooltip.style.display = 'none'; })

  .graphData(graphData);

// ── Force tuning: spread nodes out ────────────────────────────────────────
Graph.d3Force('charge').strength(-200);        // stronger repulsion
Graph.d3Force('link').distance(80);            // longer links
Graph.d3Force('link').strength(0.15);          // softer link pull

// No auto-rotation — it fights with mobile touch controls
Graph.controls().autoRotate = false;

// Fit all nodes into view after the simulation settles
Graph.onEngineStop(() => {
  Graph.zoomToFit(600, 60);
});

// ── Zoom buttons ──────────────────────────────────────────────────────────
function zoomBy(factor) {
  const cam = Graph.camera();
  const controls = Graph.controls();
  const pos = cam.position;
  const dist = pos.length();
  const newDist = Math.max(50, Math.min(2000, dist * factor));
  const scale = newDist / dist;
  cam.position.set(pos.x * scale, pos.y * scale, pos.z * scale);
  controls.update();
}

document.getElementById('zoom-in').addEventListener('touchend', e => {
  e.preventDefault(); zoomBy(0.7);
}, { passive: false });
document.getElementById('zoom-out').addEventListener('touchend', e => {
  e.preventDefault(); zoomBy(1.4);
}, { passive: false });
document.getElementById('fit-btn').addEventListener('touchend', e => {
  e.preventDefault(); Graph.zoomToFit(600, 60);
}, { passive: false });

// Also wire click for desktop/WebView testing
document.getElementById('zoom-in').addEventListener('click', () => zoomBy(0.7));
document.getElementById('zoom-out').addEventListener('click', () => zoomBy(1.4));
document.getElementById('fit-btn').addEventListener('click', () => Graph.zoomToFit(600, 60));

// ── Label toggle — called from Flutter via runJavaScript ──────────────────
window.toggleLabels = function() {
  showLabels = !showLabels;
  // Walk the scene and flip visibility on every sprite
  Graph.scene().traverse(obj => {
    if (obj.isSprite) obj.visible = showLabels;
  });
};
</script>
</body>
</html>''';
  }

  Widget _buildNativeInspector() {
    final map = _NativeMindMapData.fromGraph(_graphData);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF050511).withOpacity(0.72),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0x334CEBFF)),
            boxShadow: [
              BoxShadow(
                color: const Color(0x334CEBFF).withOpacity(0.18),
                blurRadius: 24,
                spreadRadius: -8,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'INTERACTIVE RTDB MIND MAP',
                              style: TextStyle(
                                color: const Color(0xFFFFE7B0).withOpacity(0.82),
                                fontSize: 12,
                                letterSpacing: 1.6,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 9),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _statChip('source', 'RTDB'),
                                _statChip('nodes', map.nodes.length.toString()),
                                _statChip('links', map.links.length.toString()),
                                _statChip('gesture', 'pan / zoom / tap'),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      TextButton.icon(
                        onPressed: map.nodes.isEmpty
                            ? null
                            : () => setState(() => _selectedNativeNodeId = null),
                        icon: const Icon(Icons.center_focus_strong_rounded, size: 16),
                        label: const Text('RESET'),
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFF4CEBFF),
                          disabledForegroundColor: const Color(0x334CEBFF),
                          textStyle: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: map.nodes.isEmpty
                      ? Center(
                          child: Text(
                            'No knowledge graph nodes found for ${widget.personaId}.',
                            style: const TextStyle(
                              color: Color(0x88FFE7B0),
                              fontSize: 13,
                            ),
                          ),
                        )
                      : _NativeMindMapView(
                          data: map,
                          showLabels: _showLabels,
                          selectedNodeId: _selectedNativeNodeId,
                          onNodeSelected: (id) =>
                              setState(() => _selectedNativeNodeId = id),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  Widget _statChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0x14FFE7B0),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x22FFE7B0)),
      ),
      child: Text(
        '$label: $value',
        style: const TextStyle(
          color: Color(0xAAFFE7B0),
          fontSize: 11,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF000011),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              color: Color(0x88FFE7B0), size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          // Import ChatGPT memories
          IconButton(
            icon: const Icon(Icons.cloud_download_outlined,
                color: Color(0x88FFE7B0), size: 20),
            tooltip: 'Import ChatGPT memories',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      ChatGPTImportScreen(personaId: widget.personaId),
                ),
              );
              // Reload graph after returning in case new nodes were added
              setState(() => _loading = true);
              _initGraph();
            },
          ),
          // Retro-populate from conversation history
          IconButton(
            icon: _backfilling
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        color: Color(0xFFFFE7B0), strokeWidth: 1.5))
                : const Icon(Icons.history_edu_outlined,
                    color: Color(0x88FFE7B0), size: 20),
            tooltip: 'Build from history',
            onPressed: _backfilling ? null : _runBackfill,
          ),
          // Prune noise nodes
          IconButton(
            icon: const Icon(Icons.auto_fix_high_outlined,
                color: Color(0x66FFE7B0), size: 20),
            tooltip: 'Prune noise nodes',
            onPressed: _backfilling ? null : _runPrune,
          ),
          // Node label toggle
          IconButton(
            icon: Icon(
              _showLabels ? Icons.label_rounded : Icons.label_outline,
              color: _showLabels
                  ? const Color(0xFFFFE7B0)
                  : const Color(0x55FFE7B0),
              size: 20,
            ),
            tooltip: _showLabels ? 'Hide labels' : 'Show labels',
            onPressed: () {
              setState(() => _showLabels = !_showLabels);
              _controller?.runJavaScript('toggleLabels()');
            },
          ),
          IconButton(
            icon: const Icon(Icons.fit_screen_outlined,
                color: Color(0x88FFE7B0), size: 20),
            tooltip: 'Fit all nodes',
            onPressed: () => _controller?.runJavaScript('Graph.zoomToFit(600, 60)'),
          ),
          IconButton(
            icon: const Icon(Icons.refresh,
                color: Color(0x66FFE7B0), size: 20),
            tooltip: 'Reload graph',
            onPressed: () {
              setState(() => _loading = true);
              _initGraph();
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          if (_loading)
            const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(
                      color: Color(0xFFFFE7B0), strokeWidth: 1),
                  SizedBox(height: 20),
                  Text('Building brain…',
                      style: TextStyle(
                          color: Color(0x66FFE7B0),
                          fontSize: 12,
                          letterSpacing: 2)),
                ],
              ),
            )
          else if (_error != null)
            Center(
              child: Text(_error!,
                  style: const TextStyle(color: Colors.redAccent)))
          else if (_useNativeInspector)
            _buildNativeInspector()
          else
            WebViewWidget(controller: _controller!),

          // Backfill status banner
          if (_backfillStatus != null)
            Positioned(
              bottom: 32,
              left: 16,
              right: 16,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.85),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: const Color(0x44FFE7B0), width: 0.5),
                ),
                child: Row(
                  children: [
                    if (_backfilling)
                      const Padding(
                        padding: EdgeInsets.only(right: 10),
                        child: SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                              color: Color(0xFFFFE7B0), strokeWidth: 1.5),
                        ),
                      ),
                    Expanded(
                      child: Text(
                        _backfillStatus!,
                        style: const TextStyle(
                            color: Color(0xAAFFE7B0),
                            fontSize: 12,
                            letterSpacing: 0.5),
                      ),
                    ),
                    if (!_backfilling)
                      GestureDetector(
                        onTap: () =>
                            setState(() => _backfillStatus = null),
                        child: const Icon(Icons.close,
                            color: Color(0x66FFE7B0), size: 16),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _NativeMindMapNode {
  final String id;
  final String label;
  final String type;
  final double importance;
  final Offset position;

  const _NativeMindMapNode({
    required this.id,
    required this.label,
    required this.type,
    required this.importance,
    required this.position,
  });
}

class _NativeMindMapLink {
  final String source;
  final String target;
  final String relation;
  final double strength;

  const _NativeMindMapLink({
    required this.source,
    required this.target,
    required this.relation,
    required this.strength,
  });
}

class _NativeMindMapData {
  final List<_NativeMindMapNode> nodes;
  final List<_NativeMindMapLink> links;
  final Rect bounds;

  const _NativeMindMapData({
    required this.nodes,
    required this.links,
    required this.bounds,
  });

  factory _NativeMindMapData.fromGraph(Map<String, dynamic>? graph) {
    final rawNodes = (graph?['nodes'] as List?)
            ?.whereType<Map>()
            .map((n) => Map<String, dynamic>.from(n))
            .toList() ??
        <Map<String, dynamic>>[];
    final rawLinks = (graph?['links'] as List?)
            ?.whereType<Map>()
            .map((l) => Map<String, dynamic>.from(l))
            .toList() ??
        <Map<String, dynamic>>[];

    rawNodes.sort((a, b) {
      final ai = (a['importance'] as num?)?.toDouble() ?? 0;
      final bi = (b['importance'] as num?)?.toDouble() ?? 0;
      return bi.compareTo(ai);
    });

    if (rawNodes.isEmpty) {
      return const _NativeMindMapData(
        nodes: <_NativeMindMapNode>[],
        links: <_NativeMindMapLink>[],
        bounds: Rect.fromLTWH(-450, -320, 900, 640),
      );
    }

    final byType = <String, List<Map<String, dynamic>>>{};
    for (final node in rawNodes.take(180)) {
      final type = '${node['type'] ?? 'concept'}'.trim().isEmpty
          ? 'concept'
          : '${node['type'] ?? 'concept'}'.trim();
      byType.putIfAbsent(type, () => <Map<String, dynamic>>[]).add(node);
    }

    final typeKeys = byType.keys.toList()
      ..sort((a, b) => byType[b]!.length.compareTo(byType[a]!.length));

    final nodes = <_NativeMindMapNode>[];
    final links = <_NativeMindMapLink>[];
    final seenLinks = <String>{};

    const rootId = '__kai_memory_root__';
    nodes.add(const _NativeMindMapNode(
      id: rootId,
      label: 'Kai memory',
      type: 'root',
      importance: 1.0,
      position: Offset.zero,
    ));

    final branchCount = math.max(1, typeKeys.length);
    final branchRadius = 260.0 + math.min(180.0, rawNodes.length * 2.2);
    final idSet = <String>{rootId};
    final hubByType = <String, String>{};

    for (var ti = 0; ti < typeKeys.length; ti++) {
      final type = typeKeys[ti];
      final bucket = byType[type]!;
      final angle = -math.pi / 2 + (math.pi * 2 * ti / branchCount);
      final hubId = '__type_hub_$type';
      final hubPos = Offset(math.cos(angle) * branchRadius, math.sin(angle) * branchRadius);
      hubByType[type] = hubId;
      idSet.add(hubId);

      nodes.add(_NativeMindMapNode(
        id: hubId,
        label: type.toUpperCase(),
        type: 'hub:$type',
        importance: 0.86,
        position: hubPos,
      ));
      links.add(const _NativeMindMapLink(
        source: rootId,
        target: '',
        relation: 'branch',
        strength: 0.9,
      ).copyWith(target: hubId));

      final spread = math.min(math.pi * 0.78, math.pi * 0.20 + bucket.length * 0.035);
      final rows = math.max(1, (bucket.length / 10).ceil());
      for (var i = 0; i < bucket.length; i++) {
        final raw = bucket[i];
        final id = '${raw['id'] ?? raw['key'] ?? raw['label'] ?? 'node_${nodes.length}'}';
        if (!idSet.add(id)) continue;
        final label = '${raw['label'] ?? id}';
        final importance = ((raw['importance'] as num?)?.toDouble() ?? 0.5).clamp(0.0, 1.0);
        final lane = i % 10;
        final row = i ~/ 10;
        final t = bucket.length == 1 ? 0.5 : lane / math.max(1, math.min(9, bucket.length - 1));
        final leafAngle = angle - spread / 2 + spread * t;
        final distance = 130.0 + row * 92.0 + importance * 42.0;
        final sideJitter = (((id.hashCode & 0xFFFF) / 0xFFFF) - 0.5) * 26.0;
        final tangent = Offset(-math.sin(angle), math.cos(angle));
        final pos = hubPos +
            Offset(math.cos(leafAngle), math.sin(leafAngle)) * distance +
            tangent * sideJitter;

        nodes.add(_NativeMindMapNode(
          id: id,
          label: label,
          type: type,
          importance: importance,
          position: pos,
        ));
        links.add(_NativeMindMapLink(
          source: hubId,
          target: id,
          relation: 'contains',
          strength: math.max(0.35, importance),
        ));
      }
    }

    final realNodeIds = nodes
        .where((n) => !n.id.startsWith('__'))
        .map((n) => n.id)
        .toSet();

    for (final raw in rawLinks) {
      final source = '${raw['source'] ?? raw['fromId'] ?? raw['from'] ?? ''}';
      final target = '${raw['target'] ?? raw['toId'] ?? raw['to'] ?? ''}';
      if (!realNodeIds.contains(source) || !realNodeIds.contains(target) || source == target) continue;
      final key = source.compareTo(target) <= 0 ? '$source->$target' : '$target->$source';
      if (!seenLinks.add(key)) continue;
      links.add(_NativeMindMapLink(
        source: source,
        target: target,
        relation: '${raw['relation'] ?? raw['label'] ?? ''}',
        strength: ((raw['strength'] as num?)?.toDouble() ?? 0.5).clamp(0.05, 1.0),
      ));
    }

    var left = nodes.first.position.dx;
    var right = left;
    var top = nodes.first.position.dy;
    var bottom = top;
    for (final node in nodes) {
      left = math.min(left, node.position.dx);
      right = math.max(right, node.position.dx);
      top = math.min(top, node.position.dy);
      bottom = math.max(bottom, node.position.dy);
    }

    return _NativeMindMapData(
      nodes: nodes,
      links: links,
      bounds: Rect.fromLTRB(left - 260, top - 220, right + 260, bottom + 220),
    );
  }
}

extension _NativeMindMapLinkCopy on _NativeMindMapLink {
  _NativeMindMapLink copyWith({
    String? source,
    String? target,
    String? relation,
    double? strength,
  }) =>
      _NativeMindMapLink(
        source: source ?? this.source,
        target: target ?? this.target,
        relation: relation ?? this.relation,
        strength: strength ?? this.strength,
      );
}

class _NativeMindMapView extends StatefulWidget {
  final _NativeMindMapData data;
  final bool showLabels;
  final String? selectedNodeId;
  final ValueChanged<String?> onNodeSelected;

  const _NativeMindMapView({
    required this.data,
    required this.showLabels,
    required this.selectedNodeId,
    required this.onNodeSelected,
  });

  @override
  State<_NativeMindMapView> createState() => _NativeMindMapViewState();
}

class _NativeMindMapViewState extends State<_NativeMindMapView> {
  late final TransformationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TransformationController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = Size(
      math.max(900, widget.data.bounds.width),
      math.max(650, widget.data.bounds.height),
    );
    final origin = Offset(size.width / 2, size.height / 2);

    return Stack(
      children: [
        Positioned.fill(
          child: InteractiveViewer(
            transformationController: _controller,
            minScale: 0.18,
            maxScale: 3.8,
            boundaryMargin: const EdgeInsets.all(900),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (details) {
                final local = details.localPosition - origin;
                final hit = _hitNode(local);
                widget.onNodeSelected(hit?.id);
              },
              child: CustomPaint(
                size: size,
                painter: _MindMapPainter(
                  data: widget.data,
                  origin: origin,
                  showLabels: widget.showLabels,
                  selectedNodeId: widget.selectedNodeId,
                ),
              ),
            ),
          ),
        ),
        if (widget.selectedNodeId != null && widget.data.nodes.isNotEmpty)
          Positioned(
            left: 14,
            right: 14,
            bottom: 14,
            child: _NodeDetailCard(
              node: widget.data.nodes.firstWhere(
                (n) => n.id == widget.selectedNodeId,
                orElse: () => widget.data.nodes.first,
              ),
              links: widget.data.links
                  .where((l) => l.source == widget.selectedNodeId || l.target == widget.selectedNodeId)
                  .toList(),
              onClose: () => widget.onNodeSelected(null),
            ),
          ),
      ],
    );
  }

  _NativeMindMapNode? _hitNode(Offset local) {
    _NativeMindMapNode? best;
    var bestDistance = double.infinity;
    for (final node in widget.data.nodes) {
      final radius = 8 + node.importance * 17;
      final distance = (node.position - local).distance;
      if (distance <= radius + 12 && distance < bestDistance) {
        best = node;
        bestDistance = distance;
      }
    }
    return best;
  }
}

class _NodeDetailCard extends StatelessWidget {
  final _NativeMindMapNode node;
  final List<_NativeMindMapLink> links;
  final VoidCallback onClose;

  const _NodeDetailCard({
    required this.node,
    required this.links,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xEE050511),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x55FFE7B0)),
        boxShadow: const [
          BoxShadow(color: Color(0x66000000), blurRadius: 24, offset: Offset(0, 8)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  node.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFFFE7B0),
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton(
                onPressed: onClose,
                icon: const Icon(Icons.close, color: Color(0x88FFE7B0), size: 18),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _miniChip(node.type),
              _miniChip('importance ${(node.importance * 100).round()}%'),
              _miniChip('${links.length} links'),
            ],
          ),
          if (links.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              links.take(5).map((l) {
                final other = l.source == node.id ? l.target : l.source;
                return '${l.relation.isEmpty ? 'linked to' : l.relation} $other';
              }).join('  •  '),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0x99FFE7B0), fontSize: 12, height: 1.35),
            ),
          ],
        ],
      ),
    );
  }

  static Widget _miniChip(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0x14FFE7B0),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: const Color(0x22FFE7B0)),
        ),
        child: Text(
          text,
          style: const TextStyle(color: Color(0xAAFFE7B0), fontSize: 11),
        ),
      );
}

class _MindMapPainter extends CustomPainter {
  final _NativeMindMapData data;
  final Offset origin;
  final bool showLabels;
  final String? selectedNodeId;

  const _MindMapPainter({
    required this.data,
    required this.origin,
    required this.showLabels,
    required this.selectedNodeId,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF000011));
    _paintGrid(canvas, size);

    final byId = {for (final node in data.nodes) node.id: node};

    for (final link in data.links) {
      final a = byId[link.source];
      final b = byId[link.target];
      if (a == null || b == null) continue;
      final selected = selectedNodeId == a.id || selectedNodeId == b.id;
      final pa = origin + a.position;
      final pb = origin + b.position;
      final mid = Offset.lerp(pa, pb, 0.5)!;
      final normal = Offset(-(pb.dy - pa.dy), pb.dx - pa.dx);
      final len = normal.distance == 0 ? 1.0 : normal.distance;
      final control = mid + normal / len * 24;
      final path = Path()
        ..moveTo(pa.dx, pa.dy)
        ..quadraticBezierTo(control.dx, control.dy, pb.dx, pb.dy);

      final scaffold = a.id.startsWith('__') || b.id.startsWith('__');
      final alpha = selected
          ? 0.78
          : scaffold
              ? 0.50
              : (0.055 + link.strength * 0.16);
      final linkColor = scaffold
          ? Color.lerp(_colorForType(a.type), _colorForType(b.type), 0.55)!
          : const Color(0xFFFFC76A);
      canvas.drawPath(
        path,
        Paint()
          ..color = linkColor.withOpacity(alpha)
          ..strokeWidth = selected
              ? 2.8
              : scaffold
                  ? 1.6 + link.strength * 1.3
                  : 0.45 + link.strength * 1.0
          ..style = PaintingStyle.stroke
          ..maskFilter = scaffold || selected
              ? const MaskFilter.blur(BlurStyle.normal, 2.2)
              : null,
      );
    }

    for (final node in data.nodes) {
      _paintNode(canvas, origin + node.position, node);
    }
  }

  void _paintGrid(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x114CEBFF)
      ..strokeWidth = 0.6;
    const step = 72.0;
    for (var x = 0.0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  void _paintNode(Canvas canvas, Offset center, _NativeMindMapNode node) {
    final selected = selectedNodeId == node.id;
    final synthetic = node.id.startsWith('__');
    final root = node.type == 'root';
    final hub = node.type.startsWith('hub:');
    final color = _colorForType(node.type);
    final radius = root
        ? 32.0
        : hub
            ? 18.0
            : 7 + node.importance * 15;

    canvas.drawCircle(
      center,
      radius * (selected ? 2.2 : 1.8),
      Paint()
        ..color = color.withOpacity(selected ? 0.28 : 0.12)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16),
    );
    canvas.drawCircle(center, radius, Paint()..color = color.withOpacity(synthetic ? 0.78 : 0.90));
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = const Color(0xEE000011)
        ..style = PaintingStyle.stroke
        ..strokeWidth = selected ? 2.4 : 1.0,
    );

    if (root || hub || showLabels || selected || node.importance > 0.72) {
      final painter = TextPainter(
        text: TextSpan(
          text: node.label,
          style: TextStyle(
            color: selected ? const Color(0xFFFFE7B0) : const Color(0xCCFFE7B0),
            fontSize: root
                ? 15
                : hub
                    ? 12
                    : selected
                        ? 13
                        : 10.5,
            fontWeight: (selected || synthetic) ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
        maxLines: 2,
        ellipsis: '…',
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: selected ? 210 : 145);
      final rect = Rect.fromLTWH(
        center.dx + radius + 8,
        center.dy - painter.height / 2,
        painter.width + 10,
        painter.height + 6,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(8)),
        Paint()..color = const Color(0xAA050511),
      );
      painter.paint(canvas, rect.topLeft + const Offset(5, 3));
    }
  }

  Color _colorForType(String type) {
    switch (type.toLowerCase()) {
      case 'root':
        return const Color(0xFFFFE7B0);
      case 'hub:emotion':
      case 'hub:value':
      case 'emotion':
      case 'value':
        return const Color(0xFFFF9D2F);
      case 'hub:person':
      case 'person':
        return const Color(0xFFFFE7B0);
      case 'hub:goal':
      case 'hub:preference':
      case 'goal':
      case 'preference':
        return const Color(0xFFFF5FD2);
      case 'hub:memory':
      case 'hub:event':
      case 'memory':
      case 'event':
        return const Color(0xFF57FF9A);
      case 'hub:belief':
      case 'hub:pattern':
      case 'belief':
      case 'pattern':
        return const Color(0xFFB084FF);
      default:
        return const Color(0xFF4CEBFF);
    }
  }

  @override
  bool shouldRepaint(covariant _MindMapPainter oldDelegate) =>
      oldDelegate.data != data ||
      oldDelegate.showLabels != showLabels ||
      oldDelegate.selectedNodeId != selectedNodeId;
}
