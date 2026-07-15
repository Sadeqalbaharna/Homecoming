// KaiCommandPalette — a keyboard-first command surface (JARVIS "just tell it").
//
// A translucent overlay with a search field and a filtered action list. Type to
// filter; ↑/↓ to move; Enter runs the highlighted action, or — if nothing
// matches — sends what you typed to Kai as a prompt; Esc closes.
//
// Self-contained: the parent decides when to show it (e.g. a Ctrl/⌘+K shortcut)
// and passes the actions + an onPrompt callback. Accessible: real focus + a
// Semantics-labelled field.
//
// Wire sketch (in the shell):
//   if (_paletteOpen)
//     Positioned.fill(child: KaiCommandPalette(
//       actions: [ KaiCommand('Open Worlds', Icons.public, _openWorlds), ... ],
//       onPrompt: (t) { _inp.text = t; _send(); },
//       onClose: () => setState(() => _paletteOpen = false),
//     )),
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const _gpt = Color(0xFFFF9D2F);
const _claude = Color(0xFF2ED9FF);

class KaiCommand {
  final String label;
  final IconData icon;
  final VoidCallback onRun;
  const KaiCommand(this.label, this.icon, this.onRun);
}

class KaiCommandPalette extends StatefulWidget {
  final List<KaiCommand> actions;
  final void Function(String prompt) onPrompt;
  final VoidCallback onClose;
  const KaiCommandPalette({
    super.key,
    required this.actions,
    required this.onPrompt,
    required this.onClose,
  });

  @override
  State<KaiCommandPalette> createState() => _KaiCommandPaletteState();
}

class _KaiCommandPaletteState extends State<KaiCommandPalette> {
  final _ctl = TextEditingController();
  final _focus = FocusNode();
  int _sel = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _ctl.dispose();
    _focus.dispose();
    super.dispose();
  }

  List<KaiCommand> get _filtered {
    final q = _ctl.text.trim().toLowerCase();
    if (q.isEmpty) return widget.actions;
    return widget.actions
        .where((a) => a.label.toLowerCase().contains(q))
        .toList();
  }

  void _run() {
    final f = _filtered;
    if (f.isNotEmpty) {
      final cmd = f[_sel.clamp(0, f.length - 1)];
      widget.onClose();
      cmd.onRun();
    } else if (_ctl.text.trim().isNotEmpty) {
      final t = _ctl.text.trim();
      widget.onClose();
      widget.onPrompt(t);
    }
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final f = _filtered;
    if (e.logicalKey == LogicalKeyboardKey.escape) {
      widget.onClose();
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() => _sel = (f.isEmpty ? 0 : (_sel + 1) % f.length));
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() => _sel = (f.isEmpty ? 0 : (_sel - 1 + f.length) % f.length));
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.enter) {
      _run();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final f = _filtered;
    return Stack(
      children: [
        // scrim
        Positioned.fill(
          child: GestureDetector(
            onTap: widget.onClose,
            child: Container(color: Colors.black.withOpacity(0.5)),
          ),
        ),
        Align(
          alignment: const Alignment(0, -0.35),
          child: FocusScope(
            child: Focus(
              onKeyEvent: _onKey,
              child: Container(
                width: 560,
                constraints: const BoxConstraints(maxHeight: 440),
                decoration: BoxDecoration(
                  color: const Color(0xF20A0F16),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _claude.withOpacity(0.5)),
                  boxShadow: [BoxShadow(color: _claude.withOpacity(0.18), blurRadius: 30)],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                      child: Semantics(
                        label: 'Command palette. Type a command or a message for Kai.',
                        textField: true,
                        child: Row(
                          children: [
                            const Icon(Icons.bolt, color: _gpt, size: 18),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                controller: _ctl,
                                focusNode: _focus,
                                autofocus: true,
                                style: const TextStyle(color: Colors.white, fontSize: 15),
                                cursorColor: _claude,
                                decoration: const InputDecoration(
                                  isDense: true,
                                  border: InputBorder.none,
                                  hintText: 'Command, or ask Kai anything…',
                                  hintStyle: TextStyle(color: Color(0xFF5B7183)),
                                ),
                                onChanged: (_) => setState(() => _sel = 0),
                                onSubmitted: (_) => _run(),
                              ),
                            ),
                            const Text('ESC',
                                style: TextStyle(
                                    color: Color(0xFF5B7183),
                                    fontSize: 10,
                                    fontFamily: 'monospace')),
                          ],
                        ),
                      ),
                    ),
                    Container(height: 1, color: _claude.withOpacity(0.15)),
                    Flexible(
                      child: f.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.all(18),
                              child: Text(
                                _ctl.text.trim().isEmpty
                                    ? 'Type to search commands.'
                                    : 'Press Enter to send “${_ctl.text.trim()}” to Kai.',
                                style: const TextStyle(color: Color(0xFF7E93A6), fontSize: 13),
                              ),
                            )
                          : ListView.builder(
                              shrinkWrap: true,
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              itemCount: f.length,
                              itemBuilder: (_, i) => _row(f[i], i == _sel.clamp(0, f.length - 1)),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _row(KaiCommand c, bool sel) {
    return InkWell(
      onTap: () {
        widget.onClose();
        c.onRun();
      },
      child: Container(
        color: sel ? _claude.withOpacity(0.10) : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        child: Row(
          children: [
            Icon(c.icon, size: 17, color: sel ? _claude : const Color(0xFF7E93A6)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(c.label,
                  style: TextStyle(
                      color: sel ? Colors.white : const Color(0xFFC3D2DF), fontSize: 14)),
            ),
            if (sel)
              const Text('↵',
                  style: TextStyle(color: _claude, fontSize: 13, fontFamily: 'monospace')),
          ],
        ),
      ),
    );
  }
}
