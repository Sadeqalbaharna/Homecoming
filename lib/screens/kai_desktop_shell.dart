// KaiDesktopShell — the desktop "engineer + companion" window.
//
// Composes the pieces we've been building into one screen:
//  • left  — PROJECTS panel (multi-workspace + live engineer-loop status)
//  • centre— chat wired to the REAL AIService (same personality, memory, tools,
//            and both brains as the mobile app — it's the same Kai)
//  • right — the 3D cortex (kai_cortex.html) reacting to real brain activity,
//            with an engineer chip (active workspace + trust toggle)
//
// It reuses AIService.sendMessage, so nothing about Kai's behaviour is
// re-implemented — this is a new front-end onto the existing brain.

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../services/ai/ai_service.dart';
import '../services/core/code_workspace_service.dart';
import '../services/core/engineer_status_bus.dart';
import '../services/core/edit_gate.dart';
import '../services/core/cortex_activity_bus.dart';
import '../widgets/kai_brain_panel.dart';
import '../widgets/kai_hud_overlay.dart';

// Must match main_mobile's persona so it's the same Kai (memory/personality).
const String _kPersona = 'truekai';

class _ChatMsg {
  final bool user;
  String text;
  _ChatMsg(this.user, this.text);
}

class KaiDesktopShell extends StatefulWidget {
  const KaiDesktopShell({super.key});
  @override
  State<KaiDesktopShell> createState() => _KaiDesktopShellState();
}

class _KaiDesktopShellState extends State<KaiDesktopShell> {
  final AIService _ai = AIService();
  final CodeWorkspaceService _ws = CodeWorkspaceService.instance;
  final _inp = TextEditingController();
  final _scroll = ScrollController();

  final List<_ChatMsg> _msgs = [];
  bool _sending = false;
  String? _activeTool;

  WebViewController? _cortex;
  bool _cortexReady = false;
  StreamSubscription<CortexEvent>? _cortexSub;
  StreamSubscription<EngineerStatus>? _engSub;
  EngineerStatus _status = const EngineerStatus(label: 'idle');
  bool _trust = EditGate.instance.trustSession;

  @override
  void initState() {
    super.initState();
    _ws.load().then((_) {
      if (mounted) setState(() {});
    });
    _cortexSub = CortexActivityBus.instance.stream.listen(_forwardCortex);
    _engSub = EngineerStatusBus.instance.stream.listen((s) {
      if (mounted) setState(() => _status = s);
    });
    _initCortex();
    _msgs.add(_ChatMsg(false,
        "Evening, Sadeq. Both hemispheres are warm and your memory's synced. "
        "Ask me anything — or point me at a project on the left and I'll work in it."));
  }

  @override
  void dispose() {
    _cortexSub?.cancel();
    _engSub?.cancel();
    _inp.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _initCortex() {
    try {
      final c = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(const Color(0xFF04070D))
        ..setNavigationDelegate(
            NavigationDelegate(onPageFinished: (_) => _cortexReady = true))
        ..loadFlutterAsset('assets/brain/kai_cortex.html');
      setState(() => _cortex = c);
    } catch (_) {}
  }

  void _forwardCortex(CortexEvent e) {
    if (!_cortexReady || _cortex == null) return;
    _cortex!
        .runJavaScript(
            'window.KaiCortex && window.KaiCortex.event(${jsonEncode(e.toJson())});')
        .catchError((_) {});
  }

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _inp.text).trim();
    if (text.isEmpty || _sending) return;
    _inp.clear();
    setState(() {
      _msgs.add(_ChatMsg(true, text));
      _sending = true;
      _activeTool = null;
    });
    _autoscroll();
    try {
      final resp = await _ai.sendMessage(
        text: text,
        personaId: _kPersona,
        model: 'gpt-4o',
        onToolCall: (t) {
          if (mounted) setState(() => _activeTool = t);
        },
      );
      if (!mounted) return;
      setState(() => _msgs.add(_ChatMsg(false, resp.reply.isEmpty ? '(no reply)' : resp.reply)));
    } catch (e) {
      if (mounted) setState(() => _msgs.add(_ChatMsg(false, '⚠️ Something went wrong: $e')));
    } finally {
      if (mounted) setState(() { _sending = false; _activeTool = null; });
      _autoscroll();
    }
  }

  void _autoscroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _addProject() async {
    try {
      final dir = await FilePicker.platform
          .getDirectoryPath(dialogTitle: 'Add a project folder for Kai');
      if (dir != null && dir.isNotEmpty) {
        await _ws.addProject(dir);
        await _ws.selectProject(dir);
        if (mounted) setState(() {});
      }
    } catch (_) {}
  }

  // ── UI ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF070B12),
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: KaiBrainBackground(
                  personaId: _kPersona, opacity: 0.22, radiusFactor: 0.5),
            ),
            const Positioned.fill(child: KaiHudOverlay(opacity: 0.55)),
            Row(
              children: [
                _projectsPanel(),
                Expanded(child: _chat()),
                _cortexPane(),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _projectsPanel() {
    return Container(
      width: 210,
      color: Colors.black.withOpacity(0.32),
      padding: const EdgeInsets.fromLTRB(10, 14, 10, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Kai',
                  style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
              const Spacer(),
              IconButton(
                tooltip: 'Add project',
                icon: const Icon(Icons.add, color: Color(0xFFFFE7B0), size: 20),
                onPressed: _addProject,
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text('PROJECTS',
              style: TextStyle(color: Color(0xFF3F5666), fontSize: 9, letterSpacing: 1.5, fontFamily: 'monospace')),
          const SizedBox(height: 8),
          Expanded(
            child: _ws.projects.isEmpty
                ? const Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: Text('No projects yet.\nTap + to add a folder.',
                        style: TextStyle(color: Colors.white38, fontSize: 11)),
                  )
                : ListView(
                    children: [
                      for (final p in _ws.projects) _projectCard(p),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _projectCard(String path) {
    final active = _ws.root == path;
    final busy = active && _status.busy;
    return GestureDetector(
      onTap: () async {
        await _ws.selectProject(path);
        if (mounted) setState(() {});
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: const Color(0xFF0C1622),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: active ? const Color(0xFF2F4F66) : const Color(0xFF182838)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(CodeWorkspaceService.nameOf(path),
                style: const TextStyle(color: Color(0xFFDBE7F2), fontSize: 12, fontWeight: FontWeight.w600),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Row(
              children: [
                if (busy)
                  const SizedBox(
                      width: 9, height: 9,
                      child: CircularProgressIndicator(strokeWidth: 1.5, color: Color(0xFF7FB4FF)))
                else
                  Icon(Icons.circle, size: 7, color: active ? const Color(0xFF7EE787) : const Color(0xFF3F5666)),
                const SizedBox(width: 6),
                Text(active ? _status.label : 'idle',
                    style: TextStyle(
                        color: active ? const Color(0xFF9FB6C8) : const Color(0xFF5B7183),
                        fontSize: 9, fontFamily: 'monospace')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _chat() {
    return Column(
      children: [
        // header + engineer chip
        Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xFF121B26))),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _ws.hasWorkspace ? '${CodeWorkspaceService.nameOf(_ws.root!)} · engineer mode' : 'Kai',
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
              _engineerChip(),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
            itemCount: _msgs.length + (_sending ? 1 : 0),
            itemBuilder: (c, i) {
              if (i >= _msgs.length) {
                return _bubble(_ChatMsg(false, _activeTool != null ? '…$_activeTool' : 'thinking…'), dim: true);
              }
              return _bubble(_msgs[i]);
            },
          ),
        ),
        _composer(),
      ],
    );
  }

  Widget _engineerChip() {
    return Container(
      padding: const EdgeInsets.fromLTRB(11, 4, 6, 4),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1826),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF24384C)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('⚙', style: TextStyle(fontSize: 11)),
          const SizedBox(width: 6),
          Text(_ws.hasWorkspace ? CodeWorkspaceService.nameOf(_ws.root!) : 'no workspace',
              style: const TextStyle(color: Color(0xFF9FD0E8), fontSize: 10, fontFamily: 'monospace')),
          const SizedBox(width: 8),
          const Text('trust', style: TextStyle(color: Color(0xFF5B7183), fontSize: 9, fontFamily: 'monospace')),
          Transform.scale(
            scale: 0.7,
            child: Switch(
              value: _trust,
              activeThumbColor: const Color(0xFF7EE787),
              onChanged: (v) => setState(() {
                _trust = v;
                EditGate.instance.trustSession = v;
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bubble(_ChatMsg m, {bool dim = false}) {
    final isUser = m.user;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) _avatar('🧠', const [Color(0x3338E1FF), Color(0x33FF8A3D)]),
          if (!isUser) const SizedBox(width: 10),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isUser ? const Color(0xFF14283A) : const Color(0xFF0D1622),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: isUser ? const Color(0xFF1F3A52) : const Color(0xFF182838)),
              ),
              child: Text(m.text,
                  style: TextStyle(
                      color: dim ? Colors.white38 : const Color(0xFFDBE7F2), fontSize: 13.5, height: 1.5)),
            ),
          ),
          if (isUser) const SizedBox(width: 10),
          if (isUser) _avatar('🧑', const [Color(0xFF14283A), Color(0xFF14283A)]),
        ],
      ),
    );
  }

  Widget _avatar(String glyph, List<Color> grad) {
    return Container(
      width: 26, height: 26,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: grad),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF223444)),
      ),
      alignment: Alignment.center,
      child: Text(glyph, style: const TextStyle(fontSize: 13)),
    );
  }

  Widget _composer() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 15),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0D1622),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF1D2C3C)),
        ),
        padding: const EdgeInsets.fromLTRB(14, 4, 6, 4),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _inp,
                minLines: 1,
                maxLines: 5,
                style: const TextStyle(color: Color(0xFFDCEAF5), fontSize: 13),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  hintText: 'Ask Kai to build, fix, or explain…',
                  hintStyle: TextStyle(color: Color(0xFF5B7183)),
                ),
                onSubmitted: (_) => _send(),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.arrow_upward, color: Colors.white, size: 18),
              onPressed: _sending ? null : () => _send(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cortexPane() {
    return Container(
      width: 300,
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.32),
        border: const Border(left: BorderSide(color: Color(0xFF14202C))),
      ),
      child: KaiVitals(personaId: _kPersona),
    );
  }
}
