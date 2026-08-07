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

  // Desktop memory atlas selection.
  String? _selectedAtlasNodeId;

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
          // -1 is ABORTED, not zero. The prune refuses to delete anything it
          // cannot archive first — and this line used to render that refusal as
          // "graph is clean", which is the most reassuring possible way to say
          // "I did not run".
          _backfillStatus = removed < 0
              ? 'ABORTED — could not archive first, so NOTHING was deleted. '
                  'This is not a clean graph, it is a prune that refused to run. '
                  'Deploy the rules: firebase deploy --only database'
              : removed > 0
                  ? 'Pruned $removed noise nodes.'
                  : 'Nothing to prune — graph is clean.';
        });
        if (removed > 0) {
          await Future.delayed(const Duration(seconds: 2));
          if (mounted) {
            setState(() { _backfillStatus = null; _loading = true; });
            _initGraph();
          }
        } else if (removed == 0) {
          await Future.delayed(const Duration(seconds: 2));
          if (mounted) setState(() => _backfillStatus = null);
        }
        // removed < 0 → ABORTED: leave it on screen. A failure that fades out
        // after two seconds like a success is a failure nobody reads.
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
        // Living Memory Atlas position data — lets the native Atlas restore
        // hand-placed chambers instead of regenerating the constellation.
        'atlasPosition': m['atlasPosition'],
        'atlasX': m['atlasX'],
        'atlasY': m['atlasY'],
        'x': m['x'],
        'y': m['y'],
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

  Future<void> _saveAtlasNodePosition(String nodeId, Offset position) async {
    final graphData = _graphData;
    final rawNodes = graphData?['nodes'];
    if (rawNodes is List) {
      for (final rawNode in rawNodes) {
        if (rawNode is Map && rawNode['id'] == nodeId) {
          rawNode['atlasPosition'] = {'x': position.dx, 'y': position.dy};
          rawNode['atlasX'] = position.dx;
          rawNode['atlasY'] = position.dy;
          break;
        }
      }
    }

    if (!FirebaseService.isAvailable) return;

    final nodes = _asList(_graphData?['nodes']);
    final nodeIndex = nodes.indexWhere((node) {
      if (node is! Map) return false;
      return node['id'] == nodeId;
    });
    if (nodeIndex < 0) return;

    await KaiDb.instance
        .ref('knowledge_graph/${widget.personaId}/nodes/$nodeIndex')
        .update({
      'atlasPosition': {'x': position.dx, 'y': position.dy},
      'atlasX': position.dx,
      'atlasY': position.dy,
    });
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
    final map = _MemoryAtlasData.fromGraph(_graphData);

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
                              'INTERACTIVE MEMORY ATLAS',
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
                            : () => setState(() => _selectedAtlasNodeId = null),
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
                      : _MemoryAtlasView(
                          data: map,
                          showLabels: _showLabels,
                          selectedNodeId: _selectedAtlasNodeId,
                          onNodeSelected: (id) =>
                              setState(() => _selectedAtlasNodeId = id),
                          onNodePositioned: _saveAtlasNodePosition,
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

class _AtlasNode {
  final String id;
  final String label;
  final String type;
  final double importance;
  final Offset position;

  const _AtlasNode({
    required this.id,
    required this.label,
    required this.type,
    required this.importance,
    required this.position,
  });

  _AtlasNode copyWith({Offset? position}) => _AtlasNode(
        id: id,
        label: label,
        type: type,
        importance: importance,
        position: position ?? this.position,
      );
}

class _AtlasLink {
  final String source;
  final String target;
  final String relation;
  final double strength;

  const _AtlasLink({
    required this.source,
    required this.target,
    required this.relation,
    required this.strength,
  });
}

class _MemoryAtlasData {
  final List<_AtlasNode> nodes;
  final List<_AtlasLink> links;
  final Rect bounds;

  const _MemoryAtlasData({
    required this.nodes,
    required this.links,
    required this.bounds,
  });

  _AtlasNode? nodeById(String id) {
    for (final node in nodes) {
      if (node.id == id) return node;
    }
    return null;
  }

  factory _MemoryAtlasData.fromGraph(Map<String, dynamic>? graph) {
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
      return const _MemoryAtlasData(
        nodes: <_AtlasNode>[],
        links: <_AtlasLink>[],
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

    final nodes = <_AtlasNode>[];
    final links = <_AtlasLink>[];
    final seenLinks = <String>{};

    const rootId = '__kai_memory_root__';
    nodes.add(const _AtlasNode(
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

      nodes.add(_AtlasNode(
        id: hubId,
        label: type.toUpperCase(),
        type: 'hub:$type',
        importance: 0.86,
        position: hubPos,
      ));
      links.add(const _AtlasLink(
        source: rootId,
        target: '',
        relation: 'branch',
        strength: 0.9,
      ).copyWith(target: hubId));

      final spread = math.min(math.pi * 0.78, math.pi * 0.20 + bucket.length * 0.035);
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
        final fallbackPos = hubPos +
            Offset(math.cos(leafAngle), math.sin(leafAngle)) * distance +
            tangent * sideJitter;
        final pos = _readPersistedAtlasPosition(raw) ?? fallbackPos;

        nodes.add(_AtlasNode(
          id: id,
          label: label,
          type: type,
          importance: importance,
          position: pos,
        ));
        links.add(_AtlasLink(
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
      links.add(_AtlasLink(
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

    return _MemoryAtlasData(
      nodes: nodes,
      links: links,
      bounds: Rect.fromLTRB(left - 120, top - 120, right + 120, bottom + 120),
    );
  }
}

Offset? _readPersistedAtlasPosition(Map<String, dynamic> raw) {
  final atlasPosition = raw['atlasPosition'];
  if (atlasPosition is Map) {
    final x = (atlasPosition['x'] as num?)?.toDouble();
    final y = (atlasPosition['y'] as num?)?.toDouble();
    if (x != null && y != null) return Offset(x, y);
  }

  final x = (raw['atlasX'] ?? raw['x']) as num?;
  final y = (raw['atlasY'] ?? raw['y']) as num?;
  if (x != null && y != null) return Offset(x.toDouble(), y.toDouble());
  return null;
}

extension _AtlasLinkCopy on _AtlasLink {
  _AtlasLink copyWith({
    String? source,
    String? target,
    String? relation,
    double? strength,
  }) =>
      _AtlasLink(
        source: source ?? this.source,
        target: target ?? this.target,
        relation: relation ?? this.relation,
        strength: strength ?? this.strength,
      );
}

class _MemoryAtlasView extends StatefulWidget {
  final _MemoryAtlasData data;
  final bool showLabels;
  final String? selectedNodeId;
  final ValueChanged<String?> onNodeSelected;
  final Future<void> Function(String nodeId, Offset position) onNodePositioned;

  const _MemoryAtlasView({
    required this.data,
    required this.showLabels,
    required this.selectedNodeId,
    required this.onNodeSelected,
    required this.onNodePositioned,
  });

  @override
  State<_MemoryAtlasView> createState() => _MemoryAtlasViewState();
}

class _MemoryAtlasViewState extends State<_MemoryAtlasView> {
  static const double _memoryChamberFocusScale = 2.15;

  late final TransformationController _controller;
  final Map<String, Offset> _draggedNodePositions = <String, Offset>{};
  _AtlasNode? _draggingNode;
  Offset? _dragOffset;
  Offset? _dragStartPosition;
  bool _nodeDragConsumedTap = false;
  double _atlasZoom = 1.0;
  String? _atlasPositionStatus;

  String get _semanticZoomBand {
    if (_atlasZoom < 0.72) return 'constellation';
    if (_atlasZoom > 1.85) return 'memory chamber';
    return 'neighbourhood';
  }

  _MemoryAtlasData get _paintedData {
    if (_draggedNodePositions.isEmpty) return widget.data;
    return _MemoryAtlasData(
      nodes: widget.data.nodes
          .map(
            (node) => node.copyWith(
              position: _draggedNodePositions[node.id] ?? node.position,
            ),
          )
          .toList(growable: false),
      links: widget.data.links,
      bounds: widget.data.bounds,
    );
  }

  @override
  void initState() {
    super.initState();
    _controller = TransformationController();
    _controller.addListener(_syncAtlasZoom);
  }

  void _syncAtlasZoom() {
    final zoom = _controller.value.getMaxScaleOnAxis();
    if ((zoom - _atlasZoom).abs() < 0.04) return;
    setState(() => _atlasZoom = zoom);
  }

  @override
  void didUpdateWidget(covariant _MemoryAtlasView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data) {
      _resetAtlasView();
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_syncAtlasZoom);
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
    final selectedNode = widget.selectedNodeId == null
        ? null
        : widget.data.nodeById(widget.selectedNodeId!);

    return LayoutBuilder(
      builder: (context, constraints) {
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
                    if (_nodeDragConsumedTap) {
                      _nodeDragConsumedTap = false;
                      return;
                    }
                    if (_draggingNode != null) return;
                    final local = details.localPosition - origin;
                    final hit = _hitNode(local);
                    widget.onNodeSelected(hit?.id);
                    _travelToMemoryChamber(
                      hit,
                      viewport: constraints.biggest,
                      origin: origin,
                    );
                  },
                  onPanStart: (details) {
                    final local = details.localPosition - origin;
                    final hit = _hitNode(local);
                    if (hit == null) return;
                    setState(() {
                      _draggingNode = hit;
                      _dragOffset = hit.position - local;
                      _dragStartPosition = hit.position;
                      widget.onNodeSelected(hit.id);
                    });
                  },
                  onPanUpdate: (details) {
                    final node = _draggingNode;
                    final dragOffset = _dragOffset;
                    if (node == null || dragOffset == null) return;
                    final local = details.localPosition - origin;
                    final nextPosition = local + dragOffset;
                    setState(() {
                      _draggedNodePositions[node.id] = nextPosition;
                    });
                  },
                  onPanEnd: (_) => _finishNodeDrag(),
                  onPanCancel: _finishNodeDrag,
                  child: CustomPaint(
                    size: size,
                    painter: _MemoryAtlasPainter(
                      data: _paintedData,
                      origin: origin,
                      showLabels: widget.showLabels,
                      selectedNodeId: widget.selectedNodeId,
                      semanticZoomBand: _semanticZoomBand,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 12,
              left: 12,
              child: _MemoryAtlasHud(
                selectedNode: selectedNode,
                nodeCount: widget.data.nodes.length,
                linkCount: widget.data.links.length,
                semanticZoomBand: _semanticZoomBand,
                positionStatus: _atlasPositionStatus,
                onReset: _resetAtlasView,
                onFlyToSelected: selectedNode == null
                    ? null
                    : () => _focusMemoryChamber(
                          selectedNode,
                          viewport: constraints.biggest,
                          origin: origin,
                        ),
              ),
            ),
            if (selectedNode != null && widget.data.nodes.isNotEmpty)
              Positioned(
                left: 14,
                right: 14,
                bottom: 14,
                child: _NodeDetailCard(
                  node: selectedNode,
                  links: widget.data.links
                      .where((l) => l.source == widget.selectedNodeId || l.target == widget.selectedNodeId)
                      .toList(),
                  onClose: () => widget.onNodeSelected(null),
                ),
              ),
          ],
        );
      },
    );
  }

  void _travelToMemoryChamber(
    _AtlasNode? node, {
    required Size viewport,
    required Offset origin,
  }) {
    if (node == null) return;

    _focusMemoryChamber(node, viewport: viewport, origin: origin);
  }

  void _focusMemoryChamber(
    _AtlasNode node, {
    required Size viewport,
    required Offset origin,
  }) {
    final scale = _memoryChamberFocusScale;
    final graphPoint = origin + node.position;
    final center = Offset(viewport.width / 2, viewport.height / 2);
    final matrix = Matrix4.identity()
      ..translate(center.dx - graphPoint.dx * scale, center.dy - graphPoint.dy * scale)
      ..scale(scale);
    _controller.value = matrix;
    if ((_atlasZoom - scale).abs() >= 0.04) {
      setState(() => _atlasZoom = scale);
    }
  }

  void _resetAtlasView() {
    _controller.value = Matrix4.identity();
    if ((_atlasZoom - 1.0).abs() >= 0.04) {
      setState(() => _atlasZoom = 1.0);
    }
  }

  Future<void> _finishNodeDrag() async {
    final node = _draggingNode;
    final position = node == null ? null : _draggedNodePositions[node.id];
    final startPosition = _dragStartPosition;
    final moved = position != null &&
        startPosition != null &&
        (position - startPosition).distance > 1;
    setState(() {
      _draggingNode = null;
      _dragOffset = null;
      _dragStartPosition = null;
      _nodeDragConsumedTap = moved;
      if (moved) {
        _atlasPositionStatus = 'saving…';
      }
    });
    if (node == null || position == null || !moved) {
      return;
    }

    try {
      await widget.onNodePositioned(node.id, position);
      if (!mounted) return;
      setState(() => _atlasPositionStatus = 'saved');
    } catch (_) {
      if (!mounted) return;
      setState(() => _atlasPositionStatus = 'save failed');
    }
  }

  _AtlasNode? _hitNode(Offset local) {
    _AtlasNode? best;
    var bestDistance = double.infinity;
    for (final node in _paintedData.nodes) {
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

class _MemoryAtlasHud extends StatelessWidget {
  final _AtlasNode? selectedNode;
  final int nodeCount;
  final int linkCount;
  final String semanticZoomBand;
  final String? positionStatus;
  final VoidCallback onReset;
  final VoidCallback? onFlyToSelected;

  const _MemoryAtlasHud({
    required this.selectedNode,
    required this.nodeCount,
    required this.linkCount,
    required this.semanticZoomBand,
    required this.positionStatus,
    required this.onReset,
    required this.onFlyToSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 330),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xCC02030B),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x334CEBFF)),
        boxShadow: const [
          BoxShadow(color: Color(0x55000000), blurRadius: 22, offset: Offset(0, 8)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.rocket_launch_rounded, color: Color(0xFF4CEBFF), size: 16),
              SizedBox(width: 7),
              Text(
                'LIVING MEMORY ATLAS',
                style: TextStyle(
                  color: Color(0xFFBDF7FF),
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            selectedNode == null
                ? 'Pan, zoom, tap a memory to enter its chamber.'
                : 'Chamber: ${selectedNode!.label}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xCCFFE7B0), fontSize: 12, height: 1.3),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              _hudChip('nodes', '$nodeCount'),
              _hudChip('links', '$linkCount'),
              _hudChip('semantic zoom', semanticZoomBand),
              if (positionStatus != null) _hudChip('atlas position', positionStatus!),
              _hudChip('quest path', 'AR cockpit'),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _hudButton(
                icon: Icons.center_focus_strong_rounded,
                label: 'RESET ATLAS',
                onPressed: onReset,
              ),
              const SizedBox(width: 8),
              _hudButton(
                icon: Icons.travel_explore_rounded,
                label: 'ENTER CHAMBER',
                onPressed: onFlyToSelected,
              ),
            ],
          ),
        ],
      ),
    );
  }

  static Widget _hudChip(String label, String value) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0x124CEBFF),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: const Color(0x224CEBFF)),
        ),
        child: Text(
          '$label: $value',
          style: const TextStyle(color: Color(0xAAE9FCFF), fontSize: 10.5),
        ),
      );

  static Widget _hudButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
  }) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 14),
      label: Text(label),
      style: TextButton.styleFrom(
        foregroundColor: const Color(0xFF4CEBFF),
        disabledForegroundColor: const Color(0x334CEBFF),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: const TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _NodeDetailCard extends StatelessWidget {
  final _AtlasNode node;
  final List<_AtlasLink> links;
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
              _miniChip('memory chamber'),
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

class _MemoryAtlasPainter extends CustomPainter {
  final _MemoryAtlasData data;
  final Offset origin;
  final bool showLabels;
  final String? selectedNodeId;
  final String semanticZoomBand;

  const _MemoryAtlasPainter({
    required this.data,
    required this.origin,
    required this.showLabels,
    required this.selectedNodeId,
    required this.semanticZoomBand,
  });

  bool get _constellationMode => semanticZoomBand == 'constellation';
  bool get _memoryChamberMode => semanticZoomBand == 'memory chamber';

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF000011));
    _paintGrid(canvas, size);

    final byId = {for (final node in data.nodes) node.id: node};
    final focusedNodeIds = _focusedNodeIdsFor(selectedNodeId);
    final focusActive = selectedNodeId != null;

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
      final chamberNeighbour = focusedNodeIds.contains(a.id) && focusedNodeIds.contains(b.id);
      final alpha = selected
          ? 0.90
          : _memoryChamberMode && focusActive
              ? (chamberNeighbour ? 0.42 : 0.018)
              : focusActive
                  ? 0.025
                  : _constellationMode && !scaffold
                      ? 0.018
                      : scaffold
                          ? (_constellationMode ? 0.62 : 0.50)
                          : (0.055 + link.strength * 0.16);
      final linkColor = scaffold
          ? Color.lerp(_colorForType(a.type), _colorForType(b.type), 0.55)!
          : const Color(0xFFFFC76A);
      canvas.drawPath(
        path,
        Paint()
          ..color = linkColor.withOpacity(alpha)
          ..strokeWidth = selected
              ? 3.1
              : focusActive
                  ? 0.32
                  : scaffold
                      ? 1.6 + link.strength * 1.3
                      : 0.45 + link.strength * 1.0
          ..style = PaintingStyle.stroke
          ..maskFilter = selected
              ? const MaskFilter.blur(BlurStyle.normal, 2.8)
              : scaffold && !focusActive
                  ? const MaskFilter.blur(BlurStyle.normal, 2.2)
                  : null,
      );
    }

    if (selectedNodeId != null) {
      final selected = byId[selectedNodeId];
      if (selected != null) {
        _paintFocusReticle(canvas, origin + selected.position, selected);
      }
    }

    for (final node in data.nodes.where((n) => !focusedNodeIds.contains(n.id))) {
      _paintNode(
        canvas,
        origin + node.position,
        node,
        focusActive: focusActive,
        focused: false,
      );
    }
    for (final node in data.nodes.where((n) => focusedNodeIds.contains(n.id))) {
      _paintNode(
        canvas,
        origin + node.position,
        node,
        focusActive: focusActive,
        focused: true,
      );
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

  void _paintNode(
    Canvas canvas,
    Offset center,
    _AtlasNode node, {
    required bool focusActive,
    required bool focused,
  }) {
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
    final constellationAmbient = _constellationMode && !root && !hub && !selected;
    final chamberDistant = _memoryChamberMode && focusActive && !focused && !selected;
    final nodeOpacity = chamberDistant
        ? 0.08
        : focusActive && !focused
            ? 0.18
            : constellationAmbient
                ? 0.46
                : 1.0;
    final glowOpacity = selected
        ? 0.34
        : focused
            ? 0.20
            : chamberDistant
                ? 0.018
                : focusActive
                    ? 0.035
                    : constellationAmbient
                        ? 0.055
                        : 0.12;

    canvas.drawCircle(
      center,
      radius * (selected ? 2.35 : focused ? 2.0 : 1.8),
      Paint()
        ..color = color.withOpacity(glowOpacity)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16),
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()..color = color.withOpacity((synthetic ? 0.78 : 0.90) * nodeOpacity),
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = const Color(0xEE000011).withOpacity(focusActive && !focused ? 0.36 : 0.93)
        ..style = PaintingStyle.stroke
        ..strokeWidth = selected ? 2.4 : focused ? 1.45 : 1.0,
    );

    final ambientImportanceCutoff = _constellationMode ? 0.86 : 0.72;
    final showAmbientLabel = !focusActive &&
        (root || hub || showLabels || node.importance > ambientImportanceCutoff);
    final showFocusLabel = focusActive &&
        focused &&
        (!_memoryChamberMode || selected || hub || root || node.importance > 0.34);
    if (selected || showFocusLabel || showAmbientLabel) {
      final painter = TextPainter(
        text: TextSpan(
          text: node.label,
          style: TextStyle(
            color: selected
                ? const Color(0xFFFFE7B0)
                : focused
                    ? const Color(0xDDE9FCFF)
                    : const Color(0xCCFFE7B0),
            fontSize: root
                ? 15
                : hub
                    ? 12
                    : selected
                        ? 13
                        : focused
                            ? 11.5
                            : 10.5,
            fontWeight: (selected || synthetic || focused) ? FontWeight.w800 : FontWeight.w600,
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

  Set<String> _focusedNodeIdsFor(String? nodeId) {
    if (nodeId == null) return const <String>{};
    final ids = <String>{nodeId};
    for (final link in data.links) {
      if (link.source == nodeId) ids.add(link.target);
      if (link.target == nodeId) ids.add(link.source);
    }
    return ids;
  }

  void _paintFocusReticle(Canvas canvas, Offset center, _AtlasNode node) {
    final color = _colorForType(node.type);
    final radius = 44 + node.importance * 18;
    final paint = Paint()
      ..color = color.withOpacity(0.42)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.8);

    canvas.drawCircle(center, radius, paint);
    canvas.drawCircle(
      center,
      radius + 13,
      Paint()
        ..color = color.withOpacity(0.13)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );

    const tick = 10.0;
    for (final angle in const [0.0, math.pi / 2, math.pi, math.pi * 1.5]) {
      final direction = Offset(math.cos(angle), math.sin(angle));
      final outer = center + direction * (radius + 7);
      final inner = center + direction * (radius - tick);
      canvas.drawLine(
        inner,
        outer,
        Paint()
          ..color = color.withOpacity(0.46)
          ..strokeWidth = 1.4
          ..style = PaintingStyle.stroke,
      );
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
  bool shouldRepaint(covariant _MemoryAtlasPainter oldDelegate) =>
      oldDelegate.data != data ||
      oldDelegate.showLabels != showLabels ||
      oldDelegate.selectedNodeId != selectedNodeId ||
      oldDelegate.semanticZoomBand != semanticZoomBand;
}
