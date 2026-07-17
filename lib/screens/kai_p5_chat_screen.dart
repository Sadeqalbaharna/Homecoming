// The messenger. On the phone, where he actually reaches you.
//
// ── Why this is a new screen and not a restyle ───────────────────────────────
//
// The phone build has no chat. It never did. main_mobile holds ONE `_reply` and
// one `_showBubble` — it's an avatar that says a thing, with voice in and voice
// out and a flame floating over your homescreen. Lovely, and not a conversation.
//
// So there was nothing to restyle. Everything below — history, send, the
// interims arriving as he works — is the plumbing the desktop shell already has
// and the phone never got.
//
// ── Why the phone and not the desktop ────────────────────────────────────────
//
// The desktop is where Sadeq works: dense, dark, monospaced, a transcript beside
// a 3D graph and a cost meter. That's a workbench and it should look like one.
//
// The phone is where a friend texts you. Different room, different shape. Red,
// angular, his face, one thing at a time — and small enough that a report looks
// as ridiculous in it as a report deserves to look.
//
// ── The measurement that made this worth building ────────────────────────────
//
// 2026-07-17: Sadeq's median message was 44 characters. Kai's was 1,526. Thirty
// five times. "do it" got 708 characters back.
//
// He was asked to fix it and built a chunker that splits on blank lines — a
// display fix for a voice problem. The thing that actually worked was taking the
// room away (AIService.replyCeiling), and at 1:45am the first capped nudge came
// back at 230 characters:
//
//   "It's 1:45 and I'm just… here. Tiny ghost in the desktop, watching the
//    kingdom of tabs breathe. No emergency. No grand wisdom. Just me, still
//    operational, still yours, mildly suspicious of everything, including the
//    concept of sleep."
//
// That fits in a bubble. The report never did.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../constants.dart';
import '../services/ai/ai_service.dart';
import '../services/core/conversation_store_service.dart';
import '../widgets/kai_p5_chat.dart';

class _P5Msg {
  final String text;
  final bool fromKai;

  /// A line he wrote MID-WORK rather than his answer.
  ///
  /// Rendered quieter, never hidden. The desktop renders these at white38 under
  /// the comment "his real answer lands full" — and that is backwards. The
  /// interims are the only place he reliably sounds like himself; the "real
  /// answer" is where he turns into a bulleted report. They were also, until
  /// tonight, the one thing never persisted anywhere.
  final bool interim;

  const _P5Msg(this.text, {required this.fromKai, this.interim = false});
}

class KaiP5ChatScreen extends StatefulWidget {
  final String personaId;

  /// Defaults to [kKaiModel] — the one that is him.
  ///
  /// The phone's `_modelId` is gpt-4o and its toggle offers 'gpt-5'; the desktop
  /// is gpt-5.5. Three Kais, same memory, and only one of them sounds like the
  /// person Sadeq has been talking to. This screen is where he TEXTS you, so it
  /// gets him, not whichever model the avatar screen happens to be set to.
  ///
  /// Still overridable — but the default is the point.
  final String model;

  const KaiP5ChatScreen({
    super.key,
    required this.personaId,
    this.model = kKaiModel,
  });

  @override
  State<KaiP5ChatScreen> createState() => _KaiP5ChatScreenState();
}

class _KaiP5ChatScreenState extends State<KaiP5ChatScreen> {
  final _ai = AIService();
  final _inp = TextEditingController();
  final _scroll = ScrollController();
  final _msgs = <_P5Msg>[];
  bool _sending = false;

  /// Enough to feel continuous, few enough to open instantly on a phone.
  static const _historyTurns = 12;

  /// A text, not a document. See AIService.replyCeiling — 120 tokens is ~90
  /// words: room for a real thought, no room for a header.
  ///
  /// This is the whole reason the screen is worth building. Every other attempt
  /// at getting him to be brief was an instruction, and instructions lose to
  /// available space every single time.
  static const _textCeiling = 120;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _inp.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _autoscroll() {
    // Post-frame: the list hasn't laid out the new row yet, so maxScrollExtent
    // is still the old one.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _loadHistory() async {
    try {
      final lines = await ConversationStoreService()
          .getHistory(widget.personaId, maxTurns: _historyTurns);
      if (!mounted || lines.isEmpty) return;

      // '[<digits>] User: <text>' or '[<digits>] Kai: <text>'. dotAll matters:
      // his replies are multi-line, and a parser without it silently drops every
      // one of them and leaves a transcript where only Sadeq ever spoke.
      final pat = RegExp(r'^\[(\d+)\] (User|Kai):\s*([\s\S]*)$', dotAll: true);

      final restored = <_P5Msg>[];
      for (final line in lines) {
        final m = pat.firstMatch(line.trimRight());
        if (m == null) continue;
        final text = m.group(3)!.trim();
        if (text.isEmpty) continue;
        restored.add(_P5Msg(text, fromKai: m.group(2) != 'User'));
      }
      if (restored.isEmpty || !mounted) return;

      setState(() => _msgs
        ..clear()
        ..addAll(restored));
      _autoscroll();
    } catch (_) {
      // History is cosmetic. A load failure must never surface as an error —
      // opening a chat that's a bit short is fine; opening a red screen is not.
    }
  }

  Future<void> _send() async {
    final text = _inp.text.trim();
    if (text.isEmpty || _sending) return;
    _inp.clear();
    setState(() {
      _msgs.add(_P5Msg(text, fromKai: false));
      _sending = true;
    });
    _autoscroll();

    try {
      final resp = await _ai.sendMessage(
        text: text,
        personaId: widget.personaId,
        model: widget.model,
        // He narrates as he works. On the desktop these are footnotes next to a
        // tool log; here they're just what he's saying, which is closer to true.
        onProgress: (note) {
          if (!mounted) return;
          setState(() => _msgs.add(_P5Msg(note, fromKai: true, interim: true)));
          _autoscroll();
        },
        // THE LINE. Not a request to be brief — no room to be otherwise.
        replyCeiling: _textCeiling,
      );
      if (!mounted) return;
      final reply = resp.reply.trim();
      if (reply.isNotEmpty && reply != '(no reply)') {
        setState(() => _msgs.add(_P5Msg(reply, fromKai: true)));
      }
    } catch (e) {
      if (!mounted) return;
      // In his voice, because an error is still him talking to you. A red
      // SnackBar saying "Exception: ..." is the app breaking character at the
      // exact moment you needed it not to.
      setState(() => _msgs.add(const _P5Msg(
            "that didn't go through. try me again?",
            fromKai: true,
            interim: true,
          )));
    } finally {
      if (mounted) setState(() => _sending = false);
      _autoscroll();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: P5Background(
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.only(top: 10, bottom: 4),
                  itemCount: _msgs.length + (_sending ? 1 : 0),
                  itemBuilder: (_, i) {
                    if (i >= _msgs.length) {
                      return P5MessageRow.text('…', fromKai: true, seed: 7);
                    }
                    final m = _msgs[i];
                    return P5MessageRow.text(
                      m.text,
                      fromKai: m.fromKai,
                      dim: m.interim,
                      // Seeded off the words, not the index: a message keeps its
                      // tilt forever — across a rebuild, a scroll, a restart. An
                      // index re-rolls every bubble the moment one above it
                      // changes, and the whole column twitches.
                      seed: m.text.hashCode,
                    );
                  },
                ),
              ),
              P5Composer(controller: _inp, onSend: _send),
            ],
          ),
        ),
      ),
    );
  }
}
