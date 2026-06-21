// Brain3DScreen
// Renders Kai's knowledge graph as an interactive 3D force-directed graph
// using Three.js via WebView. Touch to rotate, pinch to zoom, tap nodes to inspect.
//
// Uses 3d-force-graph (vasturiano) — Three.js + OrbitControls under the hood.
// Graph data is loaded from Firebase and injected into the HTML at render time.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:firebase_database/firebase_database.dart';
import '../services/core/firebase_service.dart';
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
  bool _loading = true;
  String? _error;

  // Backfill state
  bool _backfilling = false;
  String? _backfillStatus;

  // Node type → hex color (matches Obsidian-style palette)
  static const _nodeColors = {
    'concept':    '#7EC8E3', // sky blue
    'emotion':    '#FFB347', // amber
    'belief':     '#B8A9FF', // violet
    'memory':     '#B8E994', // mint
    'question':   '#FFE066', // gold
    'goal':       '#D4A5C9', // rose
    'preference': '#E88080', // coral
    'insight':    '#9EB8D9', // steel blue
    'person':     '#FFFFFF', // white
    'topic':      '#7EC8E3', // sky blue
    'value':      '#FFB34799', // amber dim
    'pattern':    '#B8A9FF99', // violet dim
    'fact':       '#AAAAAA', // grey
    'event':      '#98FB98', // pale green
    'location':   '#F0E68C', // khaki
  };

  @override
  void initState() {
    super.initState();
    _initGraph();
  }

  Future<void> _initGraph() async {
    try {
      final graphData = await _loadGraphData();
      final html = _buildHtml(graphData);

      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(const Color(0xFF000011))
        ..loadHtmlString(html, baseUrl: 'https://localhost');

      if (mounted) {
        setState(() {
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

  Future<Map<String, dynamic>> _loadGraphData() async {
    if (!FirebaseService.isAvailable) {
      return {'nodes': [], 'links': []};
    }

    final snap = await FirebaseDatabase.instance
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
      nodes.add({
        'id':         m['id'],
        'label':      m['label'] ?? '',
        'type':       m['type'] ?? 'concept',
        'importance': (m['importance'] as num?)?.toDouble() ?? 0.5,
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
    final colorsJson = jsonEncode(_nodeColors);
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
const nodeColors = $colorsJson;
const graphData  = $jsonData;

const tooltip = document.getElementById('tooltip');

const Graph = ForceGraph3D()(document.getElementById('graph'))
  .backgroundColor('#000011')
  .showNavInfo(false)

  // Nodes
  .nodeId('id')
  .nodeLabel('label')
  .nodeColor(n => nodeColors[n.type] || '#888888')
  .nodeVal(n => Math.pow((n.importance || 0.5) * 6, 2))
  .nodeOpacity(0.92)
  .nodeResolution(12)

  // Links
  .linkSource('source')
  .linkTarget('target')
  .linkColor(() => 'rgba(255,231,176,0.15)')
  .linkWidth(l => (l.strength || 0.5) * 1.5)
  .linkOpacity(0.6)
  .linkDirectionalParticles(l => Math.ceil((l.strength || 0.3) * 3))
  .linkDirectionalParticleWidth(l => (l.strength || 0.3) * 1.5)
  .linkDirectionalParticleColor(() => 'rgba(255,231,176,0.8)')
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
    tooltip.innerHTML = \`<b>\${node.label}</b><br><span style="opacity:0.6">\${node.type}</span>\${connected ? '<br><br>' + connected : ''}\`;
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
</script>
</body>
</html>''';
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
