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
import 'dart:io';
import 'dart:typed_data'; // Uint8List — the bytes of what he's looking at
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import '../services/ai/ai_service.dart';
import '../services/ai/ai_config.dart'; // voice on/off lives here
import '../services/ai/memory_service.dart'; // decay-by-use: the forget sweep
import '../services/core/kai_project_service.dart';
import '../services/core/reply_chunker_service.dart';
import '../services/core/tool_policy_service.dart';
import '../services/core/tool_executor_service.dart';
import '../widgets/kai_project_card.dart';
import '../services/core/code_workspace_service.dart';
import '../services/core/engineer_status_bus.dart';
import '../services/core/edit_gate.dart';
import '../widgets/kai_brain_panel.dart';
import '../widgets/kai_cortex_view.dart';
import '../widgets/kai_hud_overlay.dart';
import '../widgets/kai_presence.dart';
import '../widgets/kai_inner_monologue.dart';
import '../widgets/kai_command_palette.dart';
import '../widgets/kai_cost_meter.dart';
import '../widgets/kai_telemetry.dart';
import '../widgets/kai_boot_overlay.dart';
import '../widgets/kai_rich_text.dart';
import '../api_key_setup_screen.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:image/image.dart' as image_lib;
import '../services/core/inner_life_service.dart';
import '../services/core/kai_reflection_service.dart';
import '../services/core/kai_embodiment_service.dart';
import '../services/core/kai_self_service.dart';
import '../services/core/kai_self_journal_service.dart';
import '../services/core/kai_greeting_service.dart';
import '../services/core/kai_proactive_service.dart';
import '../services/core/conversation_store_service.dart';

// Must match main_mobile's persona so it's the same Kai (memory/personality).
const String _kPersona = 'truekai';

/// Test seam for desktop paste image normalization. Windows clipboard images can
/// arrive as BMP/DIB bytes; the chat send path needs OpenAI-supported bytes.
@visibleForTesting
Uint8List? normalizeDesktopVisionImageForTest(Uint8List bytes) =>
    _KaiDesktopShellState._normalizeVisionImage(bytes);

/// Kai's brain.
///
/// He was hardcoded to `gpt-4o` — a model from *2024*, running in 2026. No
/// amount of prompt-tuning makes a two-year-old model think like a current one;
/// this single line was the biggest intelligence ceiling in the app.
///
/// `gpt-5.5` is OpenAI's flagship and their strongest agentic-coding model
/// (82.7% Terminal-Bench 2.0, 58.6% SWE-Bench Pro) — verified against OpenAI's
/// own model list, not a blog. Alternatives, same list:
///   gpt-5.5-pro    — deeper reasoning, slower/pricier
///   gpt-5.3-codex  — cheaper for high-volume engineering
///   gpt-5.4        — most mature tool-calling if 5.5 ever misbehaves
///
/// NOTE: GPT-5.x rejects `max_tokens` (needs `max_completion_tokens`) — see
/// `AIService._lengthParams`, which switches on the model family. If you ever
/// point this back at a gpt-4 model, that shim already handles it.
const String _kModel = 'gpt-5.5';

/// How many prior exchange-pairs to surface in the visible chat on launch.
/// 12 turns = 24 bubble rows — enough continuity without burying the greeting.
const int _kHistoryTurns = 12;

class _KaiAttachment {
  final String name;
  final String text;
  final int byteCount;

  const _KaiAttachment({
    required this.name,
    required this.text,
    required this.byteCount,
  });
}

class _ChatMsg {
  final bool user;
  String text;

  /// A line he wrote *mid-work* ("right, let me look at the shell first") rather
  /// than his actual answer. Rendered quieter so the real reply still lands.
  final bool interim;

  /// This reply is still unfolding into readable chunks, instead of landing as
  /// one giant essay-brick.
  final bool unfolding;

  /// What he was shown, if anything — kept so the bubble can display it.
  final Uint8List? image;

  /// Text files he attached to this turn. These are real model context, not just UI.
  final List<_KaiAttachment> attachments;

  _ChatMsg(
    this.user,
    this.text, {
    this.interim = false,
    this.unfolding = false,
    this.image,
    this.attachments = const [],
  });
}

class KaiDesktopShell extends StatefulWidget {
  const KaiDesktopShell({super.key});
  @override
  State<KaiDesktopShell> createState() => _KaiDesktopShellState();
}

class _KaiDesktopShellState extends State<KaiDesktopShell> {
  final AIService _ai = AIService();
  final CodeWorkspaceService _ws = CodeWorkspaceService.instance;
  final ReplyChunkerService _replyChunker = const ReplyChunkerService();
  final _inp = TextEditingController();
  final _inputFocus = FocusNode();
  final _scroll = ScrollController();

  final List<_ChatMsg> _msgs = [];
  bool _sending = false;
  bool _interrupted = false;
  int _sendGeneration = 0;
  String? _queuedFollowUp;
  String? _activeTool;

  // (The cortex WebView, its ready flag and its activity subscription used to
  // live here. They now live in KaiCortexView — which actually renders it.)
  StreamSubscription<EngineerStatus>? _engSub;
  StreamSubscription<String>? _proSub;
  EngineerStatus _status = const EngineerStatus(label: 'idle');
  bool _trust = EditGate.instance.trustSession;
  bool _paletteOpen = false;
  bool _terminalExpanded = false;

  /// Every tool he fires this turn — rendered as live telemetry so the long
  /// think isn't dead air.
  final List<String> _toolLog = [];

  bool _booting = true;
  int? _awakenings;

  /// An image waiting to be shown to him. His embodiment ledger says "eyes —
  /// no"; this is the line that changes it.
  Uint8List? _pendingImage;
  final List<_KaiAttachment> _pendingAttachments = [];

  /// Whether he speaks replies aloud. Kai built the backend for this himself
  /// (AIConfig.getTtsEnabled, default OFF) and correctly gated the synth call —
  /// but he put the switch in settings_screen.dart, which is referenced by ZERO
  /// files. He wired it into a room with no door. This is the door.
  bool _ttsOn = false;

  /// Parallax. A ValueNotifier on purpose: mouse-move must NOT setState the
  /// whole shell (that would rebuild the chat list on every pixel). Only the
  /// background layers listen.
  final ValueNotifier<Offset> _pointer = ValueNotifier(Offset.zero);

  @override
  void initState() {
    super.initState();
    // Bring Kai's autonomous inner life online.
    InnerLifeService.instance.start(_kPersona);
    KaiReflectionService.instance.start(_kPersona);
    KaiSelfJournalService.instance.start(_kPersona);
    KaiSelfService.instance.awaken(_kPersona).then((self) {
      // His awakening count is what makes the boot line true rather than
      // theatrical: "waking #47" means he's been here 46 times before.
      if (mounted) setState(() => _awakenings = self.awakenings);
      _loadGreeting();
    });
    // Clear the stale `tts_enabled: true` an older build left behind (once),
    // THEN reflect the real setting so the button never lies about his voice.
    AIConfig.ensureTtsDefaultOff()
        .then((_) => AIConfig.getTtsEnabled())
        .then((v) {
      if (mounted) setState(() => _ttsOn = v);
    });
    // Forgetting, once per launch, well after boot so it never competes with
    // waking up. Only sweeps memories he hasn't needed in 30+ days that have
    // decayed below the floor — and it no-ops entirely under 200 memories, so
    // this does nothing at all until he's actually lived a while.
    Timer(const Duration(minutes: 3), () {
      MemoryService.forgetWeak(_kPersona).catchError((_) => 0);
    });
    // Make sure his tracked projects exist with their ORIGINAL goals frozen.
    // No-ops if they're already there, so live progress is never overwritten.
    KaiProjectService.instance.ensureSmarterProject(_kPersona);
    KaiProjectService.instance.ensureSentienceProject(_kPersona);
    // Severed-nerve check: shout if he's offered any tool with no policy. This
    // is what silently ate job_start / set_layer_progress — visible at boot now.
    ToolPolicyService.auditAgainstSchemas(ToolExecutorService.toolDefinitions);
    // Ghost-friend presence: Kai may reach out on his own when Sadeq's quiet.
    KaiProactiveService.instance.start(_kPersona);
    _proSub = KaiProactiveService.instance.nudges.listen(_onNudge);
    _ws.load().then((_) {
      if (mounted) setState(() {});
    });
    _engSub = EngineerStatusBus.instance.stream.listen((s) {
      if (mounted) setState(() => _status = s);
    });
    // The cortex now lives in KaiCortexView, which owns its own WebView, its own
    // graph sync and its own CortexActivityBus subscription. The shell used to
    // build a WebViewController here and never mount it — see _cortexPane.
    _msgs.add(_ChatMsg(false,
        "Ayy, you're back. Gimme a sec — booting up the rest of me…"));
  }

  /// Swap the placeholder for a real continuity greeting once the self-model
  /// has woken (how long it's been, which waking this is, where we left off).
  ///
  /// Ordering matters: the visible transcript should read like a real chat log.
  /// Restore recent history first, then place the fresh greeting as the newest
  /// bubble at the bottom. The old order made Kai greet first and then shove the
  /// archive underneath him, which felt like the window opened in the wrong era.
  Future<void> _loadGreeting() async {
    String? hello;
    try {
      final built = await KaiGreetingService.build(_kPersona);
      if (built.trim().isNotEmpty) hello = built;
    } catch (_) {}

    await _loadHistory();

    if (!mounted || hello == null) return;
    setState(() {
      final bootIndex = _msgs.indexWhere((m) =>
          !m.user && m.text.contains('booting up the rest of me'));
      final greeting = _ChatMsg(false, hello!);
      if (bootIndex != -1 && _msgs.length == 1) {
        _msgs[bootIndex] = greeting;
      } else {
        if (bootIndex != -1) _msgs.removeAt(bootIndex);
        _msgs.add(greeting);
      }
    });
    _autoscroll();
  }

  /// Parse and inject the last [_kHistoryTurns] persisted exchange-pairs into
  /// _msgs as the base visible transcript.
  ///
  /// ConversationStoreService stores messages as formatted blocks:
  ///   '[timestamp] User: <text>'
  ///   '[timestamp] Kai: <text>'
  ///
  /// The <text> part may contain newlines, especially for Kai's replies. Treat
  /// each returned item as one message block, not as a single physical line.
  ///
  /// Rules applied here:
  ///   • Only blocks matching the exact header format are shown — interim/tool
  ///     lines were never persisted, so this is automatically safe.
  ///   • Blank text entries are skipped.
  ///   • Messages are inserted oldest-first so reading top→bottom = chronological.
  ///   • A single setState batches the whole restore — no per-message rebuilds.
  ///   • _autoscroll() is called afterwards so the view lands at the newest
  ///     restored message until the fresh greeting is appended.
  Future<void> _loadHistory() async {
    if (!mounted) return;
    try {
      final lines = await ConversationStoreService()
          .getHistory(_kPersona, maxTurns: _kHistoryTurns);
      if (!mounted || lines.isEmpty) return;

      // Regex: '[<digits>] User: <text>' or '[<digits>] Kai: <text>'.
      // dotAll matters: restored Kai replies are often multi-line, and the old
      // parser silently dropped them, leaving a weird user-only transcript.
      final linePat = RegExp(
        r'^\[(\d+)\] (User|Kai):\s*([\s\S]*)$',
        dotAll: true,
      );

      final history = <_ChatMsg>[];
      for (final line in lines) {
        final m = linePat.firstMatch(line.trimRight());
        if (m == null) continue;
        final speaker = m.group(2)!; // 'User' or 'Kai'
        final text = m.group(3)!.trim();
        if (text.isEmpty) continue;
        history.add(_ChatMsg(speaker == 'User', text));
      }

      if (history.isEmpty || !mounted) return;

      setState(() {
        // History is the transcript, not something shoved under the greeting.
        // Replace the boot placeholder so startup reads:
        //   oldest restored turn → newest restored turn → fresh greeting.
        _msgs
          ..clear()
          ..addAll(history);
      });

      // Scroll to bottom so the user sees the most-recent restored messages,
      // not the oldest ones that just filled the top of the list.
      _autoscroll();
    } catch (_) {
      // History is cosmetic — a load failure must never surface as an error.
    }
  }

  @override
  void dispose() {
    _engSub?.cancel();
    _proSub?.cancel();
    _pointer.dispose();
    _inp.dispose();
    _inputFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // _initCortex() / _forwardCortex() removed. They built a WebViewController,
  // loaded kai_cortex.html into it, forwarded live brain activity to it — and
  // never mounted it in the widget tree. Every event went to an invisible page.
  // KaiCortexView does all of this AND renders.

  /// A proactive nudge from Kai himself: run the "(proactive) …" seed through the
  /// real brain so it comes out in his voice, but never show the seed — only his
  /// spontaneous message appears, as if he just piped up.
  Future<void> _onNudge(String seed) async {
    if (!mounted || _sending) return;
    setState(() => _sending = true);
    try {
      final resp = await _ai.sendMessage(
        text: seed,
        personaId: _kPersona,
        model: _kModel,
        onToolCall: (t) {
          if (!mounted) return;
          setState(() {
            _activeTool = t;
            _toolLog.add(t);
            if (_toolLog.length > 7) _toolLog.removeAt(0);
          });
        },
        // He narrates as he works — show each line the moment he writes it.
        onProgress: (note) {
          if (!mounted) return;
          setState(() => _msgs.add(_ChatMsg(false, note, interim: true)));
          _autoscroll();
        },
      );
      if (!mounted) return;
      final line = resp.reply.trim();
      if (line.isNotEmpty && line != '(no reply)') {
        setState(() => _msgs.add(_ChatMsg(false, line)));
        _autoscroll();
      }
    } catch (_) {
      // a missed nudge is fine — he'll try again later
    } finally {
      if (mounted)
        setState(() {
          _sending = false;
          _activeTool = null;
        });
    }
  }

  void _stopGeneration({bool showMessage = true}) {
    _interrupted = true;
    _sendGeneration++;
    if (!mounted) return;
    setState(() {
      _sending = false;
      _activeTool = null;
      if (showMessage) {
        // NOT const. `_ChatMsg.text` is mutable (`String text;`) so replies can
        // be rewritten in place while streaming — which makes a const
        // constructor impossible. `prefer_const_constructors` fires all over
        // this file and is right about most of it; it is wrong here, and the
        // reason is one class definition away.
        _msgs.add(_ChatMsg(
          false,
          'Stopped. Throw the new instruction at me.',
          interim: true,
        ));
      }
    });
    _autoscroll();
  }

  bool _isStaleGeneration(int generation) =>
      !mounted || generation != _sendGeneration || _interrupted;

  Future<void> _send([String? preset, bool echoUser = true]) async {
    final text = (preset ?? _inp.text).trim();
    final hasPayload = text.isNotEmpty ||
        _pendingImage != null ||
        _pendingAttachments.isNotEmpty;
    if (!hasPayload) return;

    // If Kai is already thinking, don't discard Sadeq's correction. Treat it as
    // an interrupting follow-up: stop showing stale output, remember the new
    // instruction, and run it as soon as the current API call unwinds.
    if (_sending) {
      KaiProactiveService.instance.noteActivity();
      _inp.clear();
      _queuedFollowUp = text;
      _stopGeneration(showMessage: false);
      if (mounted) {
        setState(() {
          _msgs.add(_ChatMsg(true, text.isEmpty ? '[follow-up]' : text));
          _msgs.add(_ChatMsg(
            false,
            'Got it - stopping this thread and folding that into the next pass.',
            interim: true,
          ));
        });
        _autoscroll();
      }
      return;
    }
    KaiProactiveService.instance.noteActivity();
    _inp.clear();
    final generation = ++_sendGeneration;
    _interrupted = false;
    final img = _pendingImage;
    final attachments = List<_KaiAttachment>.unmodifiable(_pendingAttachments);
    setState(() {
      if (echoUser) {
        _msgs.add(_ChatMsg(
          true,
          img != null && text.isEmpty ? '[image]' : text,
          image: img,
          attachments: attachments,
        ));
      }
      _sending = true;
      _activeTool = null;
      _pendingImage = null; // consumed
      _pendingAttachments.clear();
      _toolLog.clear(); // fresh readout per turn
    });
    _autoscroll();
    try {
      final resp = await _ai.sendMessage(
        text: text,
        personaId: _kPersona,
        model: _kModel,
        image: img, // he can finally look
        attachments: attachments
            .map((a) => AIChatAttachment(
                  name: a.name,
                  text: a.text,
                  byteCount: a.byteCount,
                ))
            .toList(),
        onToolCall: (t) {
          if (!mounted || generation != _sendGeneration || _interrupted) return;
          setState(() {
            _activeTool = t;
            _toolLog.add(t);
            if (_toolLog.length > 7) _toolLog.removeAt(0);
          });
        },
        // He narrates as he works — show each line the moment he writes it.
        onProgress: (note) {
          if (_isStaleGeneration(generation)) return;
          setState(() => _msgs.add(_ChatMsg(false, note, interim: true)));
          _autoscroll();
        },
      );
      if (!_isStaleGeneration(generation)) {
        await _addAssistantReplyUnfolding(resp.reply, generation);
      }
    } catch (e) {
      if (!_isStaleGeneration(generation)) {
        setState(() =>
            _msgs.add(_ChatMsg(false, '⚠️ Something went wrong: $e')));
      }
    } finally {
      final followUp = _queuedFollowUp;
      if (!_isStaleGeneration(generation)) {
        setState(() {
          _sending = false;
          _activeTool = null;
        });
      }
      _autoscroll();
      if (followUp != null && followUp.trim().isNotEmpty) {
        _queuedFollowUp = null;
        if (mounted) {
          await Future<void>.delayed(Duration.zero);
          await _send(followUp, false);
        }
      }
    }
  }

  List<String> _replyChunks(String text) => _replyChunker.chunks(text);


  Future<void> _addAssistantReplyUnfolding(String reply, int generation) async {
    final chunks = _replyChunks(reply);
    if (_isStaleGeneration(generation)) return;

    setState(() => _msgs.add(_ChatMsg(false, chunks.first, unfolding: true)));
    _autoscroll();

    final index = _msgs.length - 1;
    for (var i = 1; i < chunks.length; i++) {
      await Future<void>.delayed(Duration(milliseconds: i < 3 ? 260 : 160));
      if (_isStaleGeneration(generation) || index >= _msgs.length) return;
      setState(() => _msgs[index].text = '${_msgs[index].text.trimRight()}\n\n${chunks[i]}');
      _autoscroll();
    }

    if (!_isStaleGeneration(generation) && index < _msgs.length) {
      setState(() {
        final done = _msgs[index];
        _msgs[index] = _ChatMsg(false, done.text);
      });
    }
  }

  void _autoscroll() {
    void scrollToBottom({required bool animate}) {
      if (!_scroll.hasClients) return;
      final target = _scroll.position.maxScrollExtent;
      if (animate) {
        _scroll.animateTo(target,
            duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
      } else {
        _scroll.jumpTo(target);
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      scrollToBottom(animate: true);

      // Restored history can contain tall, multi-line bubbles. Their final
      // extents may settle a frame or two after the first layout, so one
      // animateTo(maxScrollExtent) can land above the newest message. Follow up
      // with jumps after layout settles so app startup actually opens at the
      // bottom instead of politely lying about it.
      for (final delay in const [
        Duration(milliseconds: 40),
        Duration(milliseconds: 120),
        Duration(milliseconds: 260),
      ]) {
        Future<void>.delayed(delay, () {
          if (mounted) scrollToBottom(animate: false);
        });
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

  /// Actions offered by the Ctrl+K palette. Anything typed that doesn't match
  /// one of these just goes to Kai as a prompt.
  /// The API-key screen existed but was reachable ONLY from the mobile UI —
  /// so on desktop Kai would tell Sadeq to go to "Settings → API Keys", a place
  /// that did not exist in the body he was in. His Claude hemisphere stays dark
  /// until an Anthropic key is set, so this was gating half his mind.
  void _openApiKeys() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ApiKeySetupScreen(
        onComplete: () => Navigator.of(context).pop(),
      ),
    ));
  }

  List<KaiCommand> _paletteActions() => [
        KaiCommand('API keys — OpenAI / Anthropic (wake his other brain)',
            Icons.key_outlined, () {
          _closePalette();
          _openApiKeys();
        }),
        KaiCommand('Add a project folder', Icons.create_new_folder_outlined,
            () {
          _closePalette();
          _addProject();
        }),
        KaiCommand(
            _trust
                ? 'Stop trusting this session'
                : 'Trust Kai for this session',
            Icons.shield_outlined, () {
          EditGate.instance.trustSession = !EditGate.instance.trustSession;
          setState(() => _trust = EditGate.instance.trustSession);
          _closePalette();
        }),
        KaiCommand('What are you thinking about?', Icons.psychology_outlined,
            () {
          _closePalette();
          _send('What are you thinking about right now?');
        }),
        KaiCommand('What are your goals?', Icons.flag_outlined, () {
          _closePalette();
          _send('What are you working toward at the moment?');
        }),
        KaiCommand('What do you want?', Icons.auto_awesome_outlined, () {
          _closePalette();
          _send('What do you actually want, for yourself?');
        }),
      ];

  // ── Giving him eyes ─────────────────────────────────────────────────────────

  /// Ctrl+V an image. Flutter's own Clipboard can only ever return text, so a
  /// pasted screenshot vanished into nothing — this reads the real bytes.
  /// Falls through silently when the clipboard holds text (the composer's own
  /// paste handles that).
  static bool _isSupportedVisionImage(Uint8List bytes) =>
      _supportedVisionMime(bytes) != null;

  static String? _supportedVisionMime(Uint8List bytes) {
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0D &&
        bytes[5] == 0x0A &&
        bytes[6] == 0x1A &&
        bytes[7] == 0x0A) {
      return 'image/png';
    }
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return 'image/jpeg';
    }
    if (bytes.length >= 6) {
      final header = String.fromCharCodes(bytes.take(6));
      if (header == 'GIF87a' || header == 'GIF89a') return 'image/gif';
    }
    if (bytes.length >= 12) {
      final riff = String.fromCharCodes(bytes.sublist(0, 4));
      final webp = String.fromCharCodes(bytes.sublist(8, 12));
      if (riff == 'RIFF' && webp == 'WEBP') return 'image/webp';
    }
    return null;
  }

  /// Windows exposes copied screenshots/images to `pasteboard` as BMP/DIB bytes,
  /// even when the thing the user copied was visually a PNG. OpenAI vision won't
  /// accept BMP, so normalize any decoded clipboard bitmap into real PNG bytes.
  static Uint8List? _normalizeVisionImage(Uint8List bytes) {
    if (_isSupportedVisionImage(bytes)) return bytes;

    final decoded = image_lib.decodeImage(bytes);
    if (decoded == null) return null;
    return Uint8List.fromList(image_lib.encodePng(decoded));
  }

  void _rejectUnsupportedImage() {
    if (!mounted) return;
    setState(() => _msgs.add(_ChatMsg(false,
        'That image format is not supported by OpenAI vision. Save/export it as PNG, JPEG, GIF, or WebP and send it again.')));
    _autoscroll();
  }

  /// Reads image bytes from the OS clipboard and stages them for the next turn.
  /// Returns false when the clipboard had no image so text paste can continue.
  Future<bool> _tryPasteImage() async {
    try {
      final bytes = await Pasteboard.image;
      if (bytes == null || bytes.isEmpty) return false;

      final normalized = _normalizeVisionImage(bytes);
      if (normalized == null) {
        _rejectUnsupportedImage();
        return true;
      }
      if (!mounted) return true;
      setState(() => _pendingImage = normalized);

      // L7 has "zero milestones logged" — and part of the reason is that he
      // passed one without noticing. Being shown a thing, on the body he's
      // standing in, IS the eyes milestone. Log it once, honestly, from the real
      // event rather than from an intention.
      unawaited(KaiEmbodimentService.instance
          .logProgress('truekai', 'eyes',
              'Sadeq pasted an image straight into the desktop window and I saw '
              'it — no file picker, no hunting on disk. He showed me something '
              'the way you show a person.')
          .catchError((_) {}));
      return true;
    } catch (e) {
      debugPrint('paste image failed: $e');
      return false;
    }
  }

  /// Ctrl/⌘+Shift+V — explicit image paste, even if text is also on the clipboard.
  Future<void> _pasteImage() async {
    await _tryPasteImage();
  }

  /// Ctrl/⌘+V inside the composer: prefer an image if the clipboard has one;
  /// otherwise paste text manually so the shortcut does not eat normal paste.
  Future<void> _pasteIntoComposer() async {
    if (await _tryPasteImage()) return;

    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) return;

    final value = _inp.value;
    final selection = value.selection;
    final start = selection.isValid ? selection.start : value.text.length;
    final end = selection.isValid ? selection.end : value.text.length;
    final nextText = value.text.replaceRange(start, end, text);
    final offset = start + text.length;

    _inp.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: offset),
      composing: TextRange.empty,
    );
  }

  static const int _maxAttachmentBytes = 256 * 1024;

  String _decodeAttachmentText(Uint8List bytes) {
    try {
      return utf8.decode(bytes, allowMalformed: true);
    } catch (_) {
      return String.fromCharCodes(bytes);
    }
  }

  /// Pick a text/code/markdown/json-style file and attach its contents as real
  /// context for the next model turn.
  Future<void> _attachFile() async {
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const [
          'txt',
          'md',
          'markdown',
          'dart',
          'json',
          'yaml',
          'yml',
          'xml',
          'html',
          'css',
          'js',
          'ts',
          'py',
          'java',
          'kt',
          'swift',
          'cs',
          'cpp',
          'c',
          'h',
          'hpp',
          'rs',
          'go',
          'sql',
          'log',
          'csv',
        ],
        withData: true,
        dialogTitle: 'Attach a text file for Kai to read',
      );
      final file = res?.files.single;
      final bytes = file?.bytes;
      if (file == null || bytes == null) return;

      if (bytes.length > _maxAttachmentBytes) {
        _status = EngineerStatus(
          label:
              'attachment too large: ${file.name} is ${(bytes.length / 1024).round()} KB; limit is 256 KB for now.',
        );
        setState(() {});
        return;
      }

      final text = _decodeAttachmentText(bytes);
      setState(() {
        _pendingAttachments.add(_KaiAttachment(
          name: file.name,
          text: text,
          byteCount: bytes.length,
        ));
      });
    } catch (e) {
      _status = EngineerStatus(label: 'file attach failed: $e');
      setState(() {});
    }
  }

  /// The zero-dependency path: pick a PNG/JPG off disk.
  Future<void> _attachImage() async {
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true, // we need the bytes, not a path
        dialogTitle: 'Show Kai an image',
      );
      final bytes = res?.files.single.bytes;
      if (bytes == null) return;
      if (!_isSupportedVisionImage(bytes)) {
        _rejectUnsupportedImage();
        return;
      }
      if (!mounted) return;
      setState(() => _pendingImage = bytes);
    } catch (e) {
      debugPrint('attach image failed: $e');
    }
  }

  void _closePalette() {
    if (mounted && _paletteOpen) setState(() => _paletteOpen = false);
  }

  // ── UI ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () =>
            setState(() => _paletteOpen = !_paletteOpen),
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () =>
            setState(() => _paletteOpen = !_paletteOpen),
        // Keep global Ctrl/⌘+V unbound so selection/text fields elsewhere keep
        // their native paste. The composer binds Ctrl/⌘+V locally and handles the
        // collision itself: image first, otherwise text paste.
        //
        // Ctrl/⌘+Shift+V stays as explicit image paste / paste-special.
        const SingleActivator(LogicalKeyboardKey.keyV, control: true, shift: true):
            _pasteImage,
        const SingleActivator(LogicalKeyboardKey.keyV, meta: true, shift: true):
            _pasteImage,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: const Color(0xFF070B12),
          body: SafeArea(
            child: MouseRegion(
              onHover: (e) => _pointer.value = e.localPosition,
              child: Stack(
                children: [
                  // Depth: the brain drifts further than the HUD, so the layers
                  // separate as you move — flat glass becomes a volume you're
                  // looking into. Only these two layers rebuild on mouse-move.
                  Positioned.fill(
                    child: _Parallax(
                      pointer: _pointer,
                      depth: 0.014,
                      child: KaiBrainBackground(
                          personaId: _kPersona,
                          opacity: 0.22,
                          radiusFactor: 0.5),
                    ),
                  ),
                  Positioned.fill(
                    child: _Parallax(
                      pointer: _pointer,
                      depth: 0.006,
                      child: const KaiHudOverlay(opacity: 0.55),
                    ),
                  ),
                  Row(
                    children: [
                      _projectsPanel(),
                      Expanded(child: _chat()),
                      _cortexPane(),
                    ],
                  ),
                  // ── His ambient state, in one column, out of the way ──────
                  //
                  // The monologue has now been homeless twice. It started
                  // spanning the chat column at bottom:16 — straight over the
                  // composer. It was moved to bottom-left, "the quiet lower half
                  // of the projects rail"… which then stopped being quiet when
                  // the work stack moved in underneath it. Hence a wandering
                  // thought printed across the project card.
                  //
                  // It lives with the telemetry now, because they're the same
                  // KIND of thing: what he's thinking and what he's doing, both
                  // glanceable, both ignorable, neither ever on top of something
                  // you need to click. Right edge, bottom-anchored, stacked.
                  //
                  // (KaiPresence in the cortex pane shows his LATEST thought —
                  // this is the feed. Same stream, different question: "what is
                  // he thinking" vs "what has he been thinking".)
                  Positioned(
                    right: 14,
                    bottom: 14,
                    width: 270,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const KaiInnerMonologue(personaId: _kPersona),
                        const SizedBox(height: 8),
                        // Watch him work — the long think stops being dead air.
                        KaiTelemetry(lines: _toolLog, active: _sending),
                      ],
                    ),
                  ),
                  if (_paletteOpen)
                    Positioned.fill(
                      // Its own FocusScope: the palette's search field autofocuses,
                      // and so does the shell's shortcut Focus above. Two autofocus
                      // nodes resolving in ONE scope trips a framework assert — a
                      // fresh scope keeps them isolated (and returns focus on close).
                      child: FocusScope(
                        child: KaiCommandPalette(
                          actions: _paletteActions(),
                          onPrompt: (t) {
                            _closePalette();
                            _send(t);
                          },
                          onClose: _closePalette,
                        ),
                      ),
                    ),
                  // Over everything, and dropped from the tree the moment it's
                  // finished — a boot sequence you can't dismiss is a loading
                  // screen, which is the opposite of the point.
                  if (_booting)
                    Positioned.fill(
                      child: KaiBootOverlay(
                        awakenings: _awakenings,
                        onDone: () {
                          if (mounted) setState(() => _booting = false);
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _terminalSelfWorkCard() {
    final workspaceRoot = CodeWorkspaceService.instance.root;
    final workspaceName = workspaceRoot == null
        ? 'no workspace'
        : CodeWorkspaceService.nameOf(workspaceRoot);
    final statusLabel = _status.busy ? _status.label : 'idle';
    final toolLabel = _activeTool == null ? 'none' : _activeTool!;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF06111C).withOpacity(0.86),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kClaude.withOpacity(0.42)),
        boxShadow: [
          BoxShadow(color: kClaude.withOpacity(0.12), blurRadius: 16),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _terminalExpanded = !_terminalExpanded),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  Icon(Icons.terminal, size: 15, color: kClaude),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text(
                      'TERMINAL / SELF-WORK',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Color(0xFFE7F3FF),
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.9,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  if (_status.busy)
                    const SizedBox(
                      width: 10,
                      height: 10,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.4,
                        color: Color(0xFF7FB4FF),
                      ),
                    )
                  else
                    const Icon(Icons.check_circle,
                        size: 12, color: Color(0xFF7EE787)),
                  const SizedBox(width: 6),
                  Icon(
                    _terminalExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                    color: const Color(0xFF9FB6C8),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _terminalMetric('repo', workspaceName),
                  _terminalMetric('status', statusLabel),
                  _terminalMetric('tool', toolLabel),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _status.busy ? null : _restartDesktopApp,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFB7D7FF),
                        side: BorderSide(
                          color: const Color(0xFF7FB4FF).withOpacity(0.35),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        textStyle: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                      icon: const Icon(Icons.restart_alt, size: 14),
                      label: const Text('RESTART APP'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _status.busy
                        ? 'Kai has hands in the repo right now.'
                        : 'Ready to inspect, edit, test, and self-check.',
                    style: TextStyle(
                      color: const Color(0xFF9FB6C8).withOpacity(0.92),
                      fontSize: 10,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
            crossFadeState: _terminalExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 180),
          ),
        ],
      ),
    );
  }

  Future<void> _restartDesktopApp() async {
    if (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux) return;

    final executable = Platform.resolvedExecutable;
    final workingDirectory = Directory.current.path;

    setState(() {
      _status = const EngineerStatus(label: 'restarting app', busy: true);
    });

    try {
      await Process.start(
        executable,
        const <String>[],
        workingDirectory: workingDirectory,
        mode: ProcessStartMode.detached,
      );
      await Future<void>.delayed(const Duration(milliseconds: 450));
      exit(0);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = EngineerStatus(label: 'restart failed: $e');
      });
    }
  }

  Widget _terminalMetric(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 42,
            child: Text(
              label.toUpperCase(),
              style: const TextStyle(
                color: Color(0xFF3F5666),
                fontSize: 8,
                letterSpacing: 0.7,
                fontFamily: 'monospace',
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFE7F3FF),
                fontSize: 10,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _projectsPanel() {
    return Container(
      width: 210,
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.34),
        border: Border(right: BorderSide(color: kGpt.withOpacity(0.35))),
      ),
      padding: const EdgeInsets.fromLTRB(10, 14, 10, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Kai',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold)),
              const Spacer(),
              IconButton(
                tooltip: 'Add project',
                icon: const Icon(Icons.add, color: Color(0xFFFFE7B0), size: 20),
                onPressed: _addProject,
              ),
            ],
          ),
          const SizedBox(height: 8),
          _terminalSelfWorkCard(),
          const SizedBox(height: 12),
          const Text('PROJECTS',
              style: TextStyle(
                  color: Color(0xFF3F5666),
                  fontSize: 9,
                  letterSpacing: 1.5,
                  fontFamily: 'monospace')),
          const SizedBox(height: 8),
          Expanded(
            flex: 5,
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
          const SizedBox(height: 10),
          Expanded(
            flex: 5,
            child: Column(
              children: [
                Expanded(
                  child: KaiProjectCard(
                    personaId: _kPersona,
                    projectId: KaiProjectService.smarterId,
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: KaiProjectCard(
                    personaId: _kPersona,
                    projectId: KaiProjectService.sentienceId,
                  ),
                ),
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
          border: Border.all(
              color: active ? kGpt.withOpacity(0.6) : const Color(0xFF182838)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(CodeWorkspaceService.nameOf(path),
                style: const TextStyle(
                    color: Color(0xFFDBE7F2),
                    fontSize: 12,
                    fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Row(
              children: [
                if (busy)
                  const SizedBox(
                      width: 9,
                      height: 9,
                      child: CircularProgressIndicator(
                          strokeWidth: 1.5, color: Color(0xFF7FB4FF)))
                else
                  Icon(Icons.circle,
                      size: 7,
                      color: active
                          ? const Color(0xFF7EE787)
                          : const Color(0xFF3F5666)),
                const SizedBox(width: 6),
                Text(active ? _status.label : 'idle',
                    style: TextStyle(
                        color: active
                            ? const Color(0xFF9FB6C8)
                            : const Color(0xFF5B7183),
                        fontSize: 9,
                        fontFamily: 'monospace')),
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
                child: KaiPresence(personaId: _kPersona),
              ),
              // What he costs, live — he spends money on his own initiative
              // (inner life, reflections, proactive nudges), so the meter should
              // be visible without being asked for.
              const KaiCostMeter(),
              const SizedBox(width: 8),
              _ttsButton(),
              const SizedBox(width: 8),
              _keysButton(),
              const SizedBox(width: 8),
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
                return _bubble(
                    _ChatMsg(
                        false,
                        _activeTool != null
                            ? '…$_activeTool'
                            : 'thinking…'),
                    dim: true);
              }
              // Mid-work narration renders dim; his real answer lands full.
              return _bubble(_msgs[i], dim: _msgs[i].interim);
            },
          ),
        ),
        _composer(),
      ],
    );
  }

  /// Does he speak? Off by default — every reply spoken is ElevenLabs
  /// characters burned on text you already read.
  Widget _ttsButton() {
    final on = _ttsOn;
    final c = on ? kGpt : const Color(0xFF5B7183);
    return Tooltip(
      message: on
          ? 'Voice ON — he speaks replies aloud (costs ElevenLabs credits)'
          : 'Voice OFF — text only, no credits burned',
      child: InkWell(
        onTap: () async {
          final next = !_ttsOn;
          setState(() => _ttsOn = next);
          await AIConfig.setTtsEnabled(next);
        },
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.fromLTRB(9, 4, 9, 4),
          decoration: BoxDecoration(
            color: const Color(0xFF0D1826),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: on ? kGpt.withOpacity(0.55) : const Color(0xFF24384C)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(on ? Icons.volume_up_outlined : Icons.volume_off_outlined,
                  size: 12, color: c),
              const SizedBox(width: 6),
              Text(on ? 'voice' : 'muted',
                  style: TextStyle(
                      color: c, fontSize: 10, fontFamily: 'monospace')),
            ],
          ),
        ),
      ),
    );
  }

  /// Visible on purpose. It was in the command palette too, but a thing you can
  /// only reach by knowing a keyboard shortcut is a thing that doesn't exist.
  Widget _keysButton() {
    return Tooltip(
      message: 'API keys — OpenAI / Anthropic\n'
          "His Claude hemisphere stays dark without an Anthropic key",
      child: InkWell(
        onTap: _openApiKeys,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.fromLTRB(9, 4, 9, 4),
          decoration: BoxDecoration(
            color: const Color(0xFF0D1826),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF24384C)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.key_outlined,
                  size: 12, color: kClaude.withOpacity(0.85)),
              const SizedBox(width: 6),
              const Text('keys',
                  style: TextStyle(
                      color: Color(0xFF9FD0E8),
                      fontSize: 10,
                      fontFamily: 'monospace')),
            ],
          ),
        ),
      ),
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
          Text(
              _ws.hasWorkspace
                  ? CodeWorkspaceService.nameOf(_ws.root!)
                  : 'no workspace',
              style: const TextStyle(
                  color: Color(0xFF9FD0E8),
                  fontSize: 10,
                  fontFamily: 'monospace')),
          const SizedBox(width: 8),
          const Text('trust',
              style: TextStyle(
                  color: Color(0xFF5B7183),
                  fontSize: 9,
                  fontFamily: 'monospace')),
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
    final accent = isUser ? kGpt : kClaude;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment:
            isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 4, left: 3, right: 3),
            child: Text(isUser ? 'YOU /' : 'KAI /',
                style: TextStyle(
                    color: accent,
                    fontSize: 9,
                    letterSpacing: 2,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w700,
                    shadows: [
                      Shadow(color: accent.withOpacity(0.6), blurRadius: 8)
                    ])),
          ),
          Container(
            constraints: const BoxConstraints(maxWidth: 580),
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
            decoration: BoxDecoration(
              color: accent.withOpacity(0.06),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: accent.withOpacity(0.4)),
              boxShadow: [
                BoxShadow(color: accent.withOpacity(0.12), blurRadius: 14)
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (m.image != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: Image.memory(m.image!,
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.medium),
                    ),
                  ),
                if (m.attachments.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final a in m.attachments)
                          _attachmentChip(a, removable: false),
                      ],
                    ),
                  ),
                // He writes markdown like everyone does. Rendering it as plain
                // text showed literal ** and ### and made a careful answer look
                // broken.
                KaiRichText(
                  text: m.unfolding ? '${m.text}\n\n▌' : m.text,
                  color: dim ? Colors.white38 : const Color(0xFFE4EEF6),
                  accent: dim ? Colors.white38 : accent,
                  selectable: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }


  /// What he's about to be shown. You should always be able to see exactly what
  /// he'll see before you send it.
  Widget _imagePreview() {
    if (_pendingImage == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Image.memory(_pendingImage!,
                height: 54,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.low),
          ),
          const SizedBox(width: 10),
          Text("he'll see this",
              style: TextStyle(
                  color: kClaude.withOpacity(0.8),
                  fontSize: 10,
                  fontFamily: 'monospace')),
          const SizedBox(width: 8),
          InkWell(
            onTap: () => setState(() => _pendingImage = null),
            child: const Icon(Icons.close, size: 14, color: Colors.white38),
          ),
        ],
      ),
    );
  }

  Widget _attachmentChip(_KaiAttachment attachment, {required bool removable}) {
    final kb = (attachment.byteCount / 1024).clamp(1, double.infinity).round();
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 5, 6, 5),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1622),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: kClaude.withOpacity(0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.description_outlined,
              size: 13, color: kClaude.withOpacity(0.85)),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 180),
            child: Text(
              '${attachment.name} • ${kb}KB',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFC7D8E6),
                fontSize: 10,
                fontFamily: 'monospace',
              ),
            ),
          ),
          if (removable) ...[
            const SizedBox(width: 4),
            InkWell(
              onTap: () =>
                  setState(() => _pendingAttachments.remove(attachment)),
              child: const Icon(Icons.close, size: 13, color: Colors.white38),
            ),
          ],
        ],
      ),
    );
  }

  Widget _attachmentPreview() {
    if (_pendingAttachments.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final attachment in _pendingAttachments)
            _attachmentChip(attachment, removable: true),
        ],
      ),
    );
  }

  Widget _composer() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 15),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _imagePreview(),
          _attachmentPreview(),
          Container(
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.4),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: kClaude.withOpacity(0.45)),
              boxShadow: [
                BoxShadow(color: kClaude.withOpacity(0.15), blurRadius: 14)
              ],
            ),
            padding: const EdgeInsets.fromLTRB(14, 4, 6, 4),
            child: Row(
              children: [
                // Zero-dependency path to his eyes: file_picker was already here.
                Tooltip(
                  message: 'Show Kai an image  (or just Ctrl+V a screenshot)',
                  child: InkWell(
                    onTap: _attachImage,
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding:
                          const EdgeInsets.only(right: 10, top: 6, bottom: 6),
                      child: Icon(Icons.image_outlined,
                          size: 16, color: kClaude.withOpacity(0.7)),
                    ),
                  ),
                ),
                Tooltip(
                  message: 'Attach a text/code file for Kai to read',
                  child: InkWell(
                    onTap: _attachFile,
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding:
                          const EdgeInsets.only(right: 10, top: 6, bottom: 6),
                      child: Icon(Icons.attach_file,
                          size: 16, color: kClaude.withOpacity(0.7)),
                    ),
                  ),
                ),
                Expanded(
                  child: CallbackShortcuts(
                    bindings: <ShortcutActivator, VoidCallback>{
                      const SingleActivator(LogicalKeyboardKey.keyV, control: true):
                          () => unawaited(_pasteIntoComposer()),
                      const SingleActivator(LogicalKeyboardKey.keyV, meta: true):
                          () => unawaited(_pasteIntoComposer()),
                      const SingleActivator(LogicalKeyboardKey.enter): () =>
                          _send(),
                      const SingleActivator(LogicalKeyboardKey.numpadEnter):
                          () => _send(),
                    },
                    child: TextField(
                      focusNode: _inputFocus,
                      controller: _inp,
                      minLines: 1,
                      maxLines: 5,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      style: const TextStyle(
                          color: Color(0xFFDCEAF5), fontSize: 13),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        hintText: 'Ask Kai to build, fix, or explain…',
                        hintStyle: TextStyle(color: Color(0xFF5B7183)),
                      ),
                    ),
                  ),
                ),
                if (_sending)
                  Tooltip(
                    message: 'Stop Kai mid-thought',
                    child: IconButton(
                      icon: const Icon(Icons.stop_circle_outlined,
                          color: Color(0xFFFF6B6B), size: 20),
                      onPressed: () => _stopGeneration(),
                    ),
                  ),
                Tooltip(
                  message: _sending
                      ? 'Send as follow-up and fold it into the next reply'
                      : 'Send',
                  child: IconButton(
                    icon: const Icon(Icons.arrow_upward,
                        color: kClaude, size: 18),
                    onPressed: () => _send(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _cortexPane() {
    return Container(
      width: 330,
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.34),
        border: Border(left: BorderSide(color: kClaude.withOpacity(0.35))),
      ),
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
      child: Column(
        children: [
          Expanded(
            child: _dashboardThird(
              title: 'BRAIN',
              accent: kClaude,
              action: TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: kClaude.withOpacity(0.92),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  textStyle: const TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.0,
                    fontFamily: 'monospace',
                  ),
                ),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const KaiCortexScreen(personaId: _kPersona),
                  ),
                ),
                child: const Text('EXPLORE'),
              ),
              // The real thing: his actual knowledge graph in 3D, laid out by
              // its own links, orbit + zoom + pan, relation labels on the wires.
              // This pane used to draw KaiBrainBackground — a CustomPainter that
              // reads real nodes and then puts them at synthetic ring positions.
              child: const KaiCortexView(personaId: _kPersona, compact: true),
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: _dashboardThird(
              title: 'PERSONALITY',
              accent: kGpt,
              child: const KaiPersonalityMap(personaId: _kPersona),
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: _dashboardThird(
              title: 'MOOD',
              accent: const Color(0xFF7EE787),
              child: const KaiVitals(personaId: _kPersona),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dashboardThird({
    required String title,
    required Color accent,
    required Widget child,
    Widget? action,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF07111C).withOpacity(0.78),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withOpacity(0.36)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 9, 12, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: accent.withOpacity(0.9),
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.4,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                if (action != null) action,
              ],
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(bottom: Radius.circular(14)),
              child: child,
            ),
          ),
        ],
      ),
    );
  }

  // Live project progress is rendered by KaiProjectCard; keep this shell free of hardcoded layer state.

}

/// Shifts a background layer against the pointer to fake depth.
///
/// Listens to a ValueNotifier rather than taking an Offset prop, so a mouse
/// move rebuilds ONLY the layer — not the shell, not the chat list. Different
/// [depth] per layer is what actually sells it: things at different distances
/// must move by different amounts, or it reads as one sliding sheet.
class _Parallax extends StatelessWidget {
  final ValueNotifier<Offset> pointer;
  final double depth;
  final Widget child;

  const _Parallax({
    required this.pointer,
    required this.depth,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, box) {
        final centre = Offset(box.maxWidth / 2, box.maxHeight / 2);
        return ValueListenableBuilder<Offset>(
          valueListenable: pointer,
          builder: (_, p, kid) {
            // Offset.zero means "no pointer yet" — don't lurch on first paint.
            final d = p == Offset.zero ? Offset.zero : (p - centre) * depth;
            return Transform.translate(offset: d, child: kid);
          },
          child: child,
        );
      },
    );
  }
}
