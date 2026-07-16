// KaiCortexView — the 3D knowledge graph, wired to the real thing.
//
// ONE widget owns the cortex: the WebView, the live RTDB graph sync, the
// setGraph injection and the activity forwarding. Both the desktop shell panel
// and the full-screen route use this. That is the entire point of it existing.
//
// Why it exists at all: the shell embedded kai_cortex.html directly and only
// ever sent event() — it NEVER called setGraph, so the scene fell through to its
// self-generated demo brain: ~400 random points with random category labels.
// Meanwhile kai_cortex_screen.dart had the correct RTDB sync and setGraph
// wiring, complete and working, and NOTHING IMPORTED IT. Two copies of the same
// idea, one fake and visible, one real and unreachable.
//
// So: one widget, two mounts, no room for that to happen again.
//
// What actually reaches the scene now:
//   nodes — id, label, type, importance, hemisphere side
//   links — source, target, RELATION, strength
//
// That relation is the bit that was being thrown away. GPT extracts it
// (brain_extraction_service asks for {"from","to","relation","strength"} and
// stores it as edge.label), it has been sitting in Firebase all along, and the
// old payload builder dropped it on the floor at the last step before drawing.

library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/core/cortex_activity_bus.dart';
import '../services/core/firebase_service.dart';
import '../services/core/kai_db.dart';
import 'kai_graph_3d.dart';

/// True where `webview_flutter` actually has a platform implementation.
///
/// It resolves to exactly three packages — `_android`, `_wkwebview` (iOS/macOS)
/// and `_platform_interface`. There is no `webview_flutter_windows`; Flutter's
/// own tooling doesn't register one because none exists, and there's an open
/// feature request for official WebView2 support. On Windows/Linux,
/// `WebViewPlatform.instance` is null and constructing a WebViewController
/// throws an assertion.
///
/// Same shape as `kaiDbUsesRest` in kai_db.dart: a Flutter plugin with no
/// desktop implementation, so the app has to know where it is. See §4.5 —
/// `firebase_database` has the identical hole.
///
/// The old shell hid this: `_initCortex` wrapped the constructor in
/// `try{...}catch(_){}`, so it failed silently and the cortex was dead without
/// ever saying so.
bool get kaiWebViewSupported {
  if (kIsWeb) return false;
  try {
    return Platform.isAndroid || Platform.isIOS || Platform.isMacOS;
  } catch (_) {
    return false;
  }
}

class KaiCortexView extends StatefulWidget {
  final String personaId;

  /// Cap on nodes pushed to the scene, strongest-importance first.
  ///
  /// The layout is O(n²) per graph change and every node carries a canvas
  /// sprite. 120 is comfortable; unbounded is how you turn his head into a
  /// slideshow.
  final int maxNodes;

  /// Small dashboard pane vs full screen — trims the label budget and chrome.
  final bool compact;

  const KaiCortexView({
    super.key,
    required this.personaId,
    this.maxNodes = 120,
    this.compact = false,
  });

  @override
  State<KaiCortexView> createState() => _KaiCortexViewState();
}

class _KaiCortexViewState extends State<KaiCortexView> {
  WebViewController? _controller;
  StreamSubscription<CortexEvent>? _actSub;
  StreamSubscription? _graphSub;
  Timer? _debounce;
  String? _latestPayload;
  bool _ready = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // On desktop there is no WebView to talk to, so don't build one, don't sync
    // a graph into it, and don't forward events at it. Every one of those was
    // happening before — into a controller that had silently failed to
    // construct.
    if (!kaiWebViewSupported) return;
    _init();
    _startGraphSync();
    _actSub = CortexActivityBus.instance.stream.listen(_forward);
  }

  @override
  void dispose() {
    _actSub?.cancel();
    _graphSub?.cancel();
    _debounce?.cancel();
    super.dispose();
  }

  void _init() {
    try {
      final c = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(const Color(0xFF04070D))
        ..addJavaScriptChannel('KaiBridge', onMessageReceived: (_) {})
        ..setNavigationDelegate(NavigationDelegate(
          onPageFinished: (_) {
            _ready = true;
            _inject(); // push whatever the DB has already streamed in
          },
        ))
        ..loadFlutterAsset('assets/brain/kai_cortex.html');
      if (mounted) setState(() => _controller = c);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  // ── Live database sync: rebuild the graph whenever it changes ──────────────
  void _startGraphSync() {
    if (!FirebaseService.isAvailable) return;
    _graphSub = KaiDb.instance
        .ref('knowledge_graph/${widget.personaId}')
        .onValue
        .listen((event) {
      _latestPayload = _buildPayload(event.snapshot.value);
      // On desktop `onValue` is a 4s REST poll, so this fires on a timer whether
      // or not anything changed. Debounce so a busy graph can't rebuild the
      // whole scene (and re-run the layout) faster than it can draw it.
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 350), _inject);
    }, onError: (_) {});
  }

  void _inject() {
    if (!_ready || _controller == null || _latestPayload == null) return;
    _controller!
        .runJavaScript(
            'window.KaiCortex && window.KaiCortex.setGraph($_latestPayload);')
        .catchError((_) {});
  }

  void _forward(CortexEvent e) {
    if (!_ready || _controller == null) return;
    _controller!
        .runJavaScript(
            'window.KaiCortex && window.KaiCortex.event(${jsonEncode(e.toJson())});')
        .catchError((_) {});
  }

  // ── Graph → cortex payload ────────────────────────────────────────────────
  //
  // Returns null when there's nothing real to show; the scene then keeps its
  // demo brain rather than going blank.
  String? _buildPayload(Object? value) {
    if (value is! Map) return null;
    final raw = Map<String, dynamic>.from(value);

    // Nodes, strongest first, capped. Keep the full label — truncating to 14
    // chars for display is the renderer's problem, not the payload's.
    final all = <Map<String, dynamic>>[];
    for (final n in _asList(raw['nodes'])) {
      if (n is! Map) continue;
      final m = Map<String, dynamic>.from(n);
      final id = m['id'];
      final label = (m['label'] ?? '').toString();
      if (id == null || label.isEmpty) continue;
      final type = (m['type'] ?? 'concept').toString();
      all.add({
        'id': id,
        'label': label,
        'cat': label,
        'type': type,
        'side': _hemisphere(type, label),
        'importance': (m['importance'] as num?)?.toDouble() ?? 0.5,
      });
    }
    if (all.isEmpty) return null;
    all.sort((a, b) =>
        (b['importance'] as double).compareTo(a['importance'] as double));
    final nodes = all.take(widget.maxNodes).toList();
    final keep = nodes.map((n) => n['id']).toSet();

    // Links — WITH the relation. `label` is where brain_extraction_service puts
    // the relation phrase GPT extracted ("cares for"); `type` is the EdgeType
    // enum name, which is currently hardcoded to `related` at the extraction
    // site, so it's the weaker signal. Prefer the label, fall back to the type.
    final links = <Map<String, dynamic>>[];
    for (final e in _asList(raw['edges'])) {
      if (e is! Map) continue;
      final m = Map<String, dynamic>.from(e);
      final src = m['fromId'] ?? m['from'] ?? m['source'];
      final tgt = m['toId'] ?? m['to'] ?? m['target'];
      if (src == null || tgt == null) continue;
      // Dropping edges to culled nodes — a link to something that isn't drawn
      // is a line to nowhere.
      if (!keep.contains(src) || !keep.contains(tgt)) continue;

      final relation = (m['label'] ?? '').toString().trim();
      final type = (m['type'] ?? '').toString().trim();
      links.add({
        'source': src,
        'target': tgt,
        'relation': relation.isNotEmpty
            ? relation
            : (type.isNotEmpty && type != 'related' ? _humanise(type) : ''),
        'strength': (m['strength'] as num?)?.toDouble() ?? 0.5,
      });
    }

    return jsonEncode({'nodes': nodes, 'links': links});
  }

  /// `caresAbout` → `cares about`. The EdgeType names are camelCase enum names;
  /// nobody wants to read "holdsValue" on a wire.
  static String _humanise(String enumName) => enumName
      .replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}')
      .toLowerCase();

  static List<dynamic> _asList(dynamic v) {
    if (v is List) return v.where((e) => e != null).toList();
    if (v is Map) return v.values.where((e) => e != null).toList();
    return const [];
  }

  // ── Hemispheres: removed, deliberately ────────────────────────────────────
  //
  // There used to be a `_hemisphere(type, label)` here that sorted nodes into
  // "GPT left / Claude right" by keyword-matching the label — and the twin in
  // kai_brain_panel.dart fell through to `index < total / 2`, i.e. it put the
  // top half of the importance-sorted list on the left and the rest on the
  // right. "Mikey" landed in a hemisphere based on where he sorted.
  //
  // That is not a measurement, it's a coin flip wearing neuroanatomy, and
  // fiction shaped like data is worse than no data — it invites you to read
  // meaning into a sort order.
  //
  // Could it be made real? Yes: tag each node with the model that extracted it.
  // But extraction runs entirely on one model, so every node would land on one
  // side and the picture would be honest and useless.
  //
  // So the left/right conceit is gone. Everything is `side: 0` — one mind — and
  // colour now comes from NodeType, which is a real property of the thing.
  // Position comes from the force layout, which is a real property of the
  // links.
  static int _hemisphere(String type, String label) => 0;

  @override
  Widget build(BuildContext context) {
    // Windows/Linux: no WebView plugin exists, so draw the graph natively.
    // Same data, same force-directed layout, same relation labels — no plugin,
    // no WebView2 runtime, no nuget.
    if (!kaiWebViewSupported) {
      return KaiGraph3D(
        personaId: widget.personaId,
        maxNodes: widget.maxNodes,
        compact: widget.compact,
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Cortex unavailable\n$_error',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF8FB0C8), fontSize: 12)),
        ),
      );
    }
    final c = _controller;
    if (c == null) {
      return const Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 1.5),
        ),
      );
    }
    return WebViewWidget(controller: c);
  }
}

/// Full-screen cortex. Same widget as the shell panel — bigger canvas.
class KaiCortexScreen extends StatelessWidget {
  final String personaId;
  const KaiCortexScreen({super.key, required this.personaId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF02040A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF02040A),
        foregroundColor: const Color(0xFFCFE3F5),
        elevation: 0,
        title: const Text('Kai · Cortex',
            style: TextStyle(fontSize: 13, letterSpacing: 4)),
      ),
      body: KaiCortexView(personaId: personaId),
    );
  }
}
