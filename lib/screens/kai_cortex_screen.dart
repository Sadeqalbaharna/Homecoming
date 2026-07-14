// KaiCortexScreen
//
// The 3D holographic "unified cortex": a rotatable dual-hemisphere brain
// (GPT left / Claude right) rendered by assets/brain/kai_cortex.html in a
// WebView. Kai's real knowledge-graph memories are loaded from Firebase,
// tagged to a hemisphere by domain, and injected into the scene. Live brain
// activity (which stem fired, memories tapped, collaboration) streams in from
// CortexActivityBus and drives the pulses.
//
// This is the desktop centrepiece, but it works on any platform the Flutter
// app targets. It shares the same Firebase brain as the mobile app, so it's
// literally the same Kai.

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:firebase_database/firebase_database.dart';
import '../services/core/kai_db.dart';
import '../services/core/firebase_service.dart';
import '../services/core/cortex_activity_bus.dart';

List<dynamic> _asList(dynamic v) {
  if (v is List) return v;
  if (v is Map) return v.values.toList();
  return [];
}

class KaiCortexScreen extends StatefulWidget {
  final String personaId;
  const KaiCortexScreen({super.key, required this.personaId});

  @override
  State<KaiCortexScreen> createState() => _KaiCortexScreenState();
}

class _KaiCortexScreenState extends State<KaiCortexScreen> {
  WebViewController? _controller;
  bool _ready = false;
  String? _error;
  StreamSubscription<CortexEvent>? _sub;
  StreamSubscription<KaiEvent>? _graphSub;
  Timer? _debounce;
  String? _latestPayload;

  @override
  void initState() {
    super.initState();
    _sub = CortexActivityBus.instance.stream.listen(_forward);
    _startGraphSync();
    _init();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _graphSub?.cancel();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(const Color(0xFF02040A))
        ..addJavaScriptChannel('KaiBridge', onMessageReceived: (_) {})
        ..setNavigationDelegate(NavigationDelegate(
          onPageFinished: (_) {
            _ready = true;
            _inject(); // push whatever the DB has already streamed in
          },
        ))
        ..loadFlutterAsset('assets/brain/kai_cortex.html');
      if (mounted) setState(() => _controller = controller);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  // ── Forward live activity into the scene ─────────────────────────────────────
  void _forward(CortexEvent e) {
    if (!_ready || _controller == null) return;
    _controller!
        .runJavaScript('window.KaiCortex && window.KaiCortex.event(${jsonEncode(e.toJson())});')
        .catchError((_) {});
  }

  // ── Live database sync: rebuild the brain whenever the graph changes ─────────
  void _startGraphSync() {
    if (!FirebaseService.isAvailable) return;
    _graphSub = KaiDb.instance
        .ref('knowledge_graph/${widget.personaId}')
        .onValue
        .listen((event) {
      _latestPayload = _buildPayload(event.snapshot.value);
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 350), _inject);
    }, onError: (_) {});
  }

  void _inject() {
    if (!_ready || _controller == null || _latestPayload == null) return;
    _controller!
        .runJavaScript('window.KaiCortex && window.KaiCortex.setGraph($_latestPayload);')
        .catchError((_) {});
  }

  // Map the raw graph (nodes + edges) into the cortex payload, tagging each node
  // to a hemisphere by domain. Returns null when there's nothing to show — the
  // scene then keeps its self-generated demo brain.
  String? _buildPayload(Object? value) {
    if (value is! Map) return null;
    final raw = Map<String, dynamic>.from(value);
    final nodes = <Map<String, dynamic>>[];
    for (final n in _asList(raw['nodes'])) {
      final m = Map<String, dynamic>.from(n as Map);
      final label = (m['label'] ?? '').toString();
      final type = (m['type'] ?? 'concept').toString();
      nodes.add({
        'id': m['id'],
        'label': label,
        'cat': label.length > 14 ? label.substring(0, 14) : label,
        'side': _hemisphere(type, label),
        'importance': (m['importance'] as num?)?.toDouble() ?? 0.5,
      });
    }
    if (nodes.isEmpty) return null;
    final links = <Map<String, dynamic>>[];
    for (final e in _asList(raw['edges'])) {
      final m = Map<String, dynamic>.from(e as Map);
      final src = m['fromId'] ?? m['source'];
      final tgt = m['toId'] ?? m['target'];
      if (src == null || tgt == null) continue;
      links.add({'source': src, 'target': tgt});
    }
    return jsonEncode({'nodes': nodes, 'links': links});
  }

  // Domain → hemisphere. -1 = GPT/left (social, multimodal, actions),
  // 1 = Claude/right (code, reasoning, writing, analysis), 0 = shared.
  static const _claudeKw = [
    'code', 'program', 'bug', 'function', 'refactor', 'algorithm', 'script',
    'regex', 'api', 'debug', 'analysis', 'reason', 'logic', 'plan', 'write',
    'essay', 'draft', 'architecture', 'compile',
  ];
  static const _gptKw = [
    'image', 'photo', 'picture', 'draw', 'voice', 'audio', 'song', 'music',
    'web', 'search', 'news', 'weather', 'call', 'message', 'whatsapp', 'sms',
    'calendar', 'alarm', 'timer', 'navigate', 'social', 'joke', 'banter',
    'feeling', 'mood', 'emotion', 'chat',
  ];

  int _hemisphere(String type, String label) {
    final l = label.toLowerCase();
    for (final k in _claudeKw) {
      if (l.contains(k)) return 1;
    }
    for (final k in _gptKw) {
      if (l.contains(k)) return -1;
    }
    switch (type.toLowerCase()) {
      case 'person':
      case 'fact':
      case 'topic':
        return 0; // people/facts are shared
      case 'emotion':
        return -1; // emotional/social → GPT
      case 'concept':
        return 1; // abstract concepts lean analytical → Claude
      default:
        return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF02040A),
      body: SafeArea(
        child: Stack(
          c