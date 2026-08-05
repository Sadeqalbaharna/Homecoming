// KaiInnerMonologue — an ambient "stream of consciousness".
//
// Streams the thoughts InnerLifeService writes to /kai/{persona}/inner_monologue
// and shows them ONE AT A TIME: each fades in, lingers, then dissolves before the
// next surfaces. It's a mind wandering through the room, not a log.
//
// Why one at a time: a stacked list of thoughts grows, competes with the chat for
// attention, and (as we found) will happily sit on top of the input field. A
// single fading line stays ambient — you notice it when you glance over, and it
// never asks for anything.
//
// Non-interactive by construction (IgnorePointer), so it can never eat a tap or
// block the composer no matter where it's placed.
//
// Wire-up:  const KaiInnerMonologue(personaId: 'truekai')  inside a Stack,
// positioned in a corner of your choosing.
library;

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../services/core/kai_db.dart';

const _gpt = Color(0xFFFF9D2F);
const _claude = Color(0xFF2ED9FF);

// Fixed ambient lanes give the feeling of randomness without making widget tests
// flaky. The lanes deliberately avoid the bottom composer and the dead-center
// chat spine; thoughts should feel like background ghosts, not UI dandruff.
const _ambientLanes = <Offset>[
  Offset(0.06, 0.12), // upper-left mist
  Offset(0.68, 0.10), // upper-right whisper
  Offset(0.12, 0.36), // left-middle drift
  Offset(0.76, 0.34), // right-middle drift
  Offset(0.08, 0.62), // lower-left glow, above composer
  Offset(0.70, 0.58), // lower-right echo, above composer
];

class _Thought {
  final String text;
  final int ts;
  const _Thought(this.text, this.ts);
}

class KaiInnerMonologue extends StatefulWidget {
  final String personaId;

  /// How many recent thoughts to keep in rotation.
  final int maxLines;

  /// How long a thought stays fully visible before dissolving.
  final Duration hold;

  /// Fade in / fade out duration.
  final Duration fade;

  /// When true, the thought positions itself inside the available Stack space and
  /// chooses a new soft anchor each time it surfaces.
  final bool ambient;

  /// Maximum width of a thought line.
  final double maxWidth;

  const KaiInnerMonologue({
    super.key,
    required this.personaId,
    this.maxLines = 6,
    this.hold = const Duration(seconds: 7),
    this.fade = const Duration(milliseconds: 1100),
    this.ambient = false,
    this.maxWidth = 260,
  });

  static bool isGenuineThought(Map value) =>
      value['text'] != null &&
      value['synthetic'] != true &&
      value['origin'] == 'model_generated';

  /// Keeps AnimatedPositioned under its required Stack parent. Public only so
  /// the parent-data contract can be exercised without a live database stream.
  static Widget ambientLayer({
    required Widget child,
    required Offset anchor,
    required Duration duration,
  }) {
    return Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.none,
      children: [
        AnimatedPositioned(
          duration: duration,
          curve: Curves.easeInOutCubic,
          left: anchor.dx,
          top: anchor.dy,
          child: child,
        ),
      ],
    );
  }

  @override
  State<KaiInnerMonologue> createState() => _KaiInnerMonologueState();
}

class _KaiInnerMonologueState extends State<KaiInnerMonologue> {
  List<_Thought> _thoughts = const [];
  // Held so it can be cancelled — an uncancelled RTDB listener keeps this State
  // (and a polling timer, on desktop REST) alive after the widget is gone.
  StreamSubscription<KaiEvent>? _sub;
  Timer? _cycle;
  Timer? _swap;
  int _idx = 0;
  int _anchorSeed = 0;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _sub = KaiDb.instance
        .ref('kai/${widget.personaId}/inner_monologue')
        .limitToLast(widget.maxLines)
        .onValue
        .listen((event) {
      final v = event.snapshot.value;
      if (v is! Map) return;
      final list = <_Thought>[];
      v.forEach((_, val) {
        // Fail closed: only records explicitly stamped by a model-generation
        // path are inner thoughts. Historical templates and offline fallbacks
        // may remain in RTDB, but the UI must never impersonate them as mind.
        if (val is Map && KaiInnerMonologue.isGenuineThought(val)) {
          list.add(_Thought(
            (val['text'] ?? '').toString(),
            (val['ts'] is int) ? val['ts'] as int : 0,
          ));
        }
      });
      list.sort((a, b) => b.ts.compareTo(a.ts)); // newest first
      if (!mounted) return;
      setState(() {
        _thoughts = list;
        if (_idx >= list.length) _idx = 0;
      });
      // First thought to ever arrive: surface it.
      if (!_visible && list.isNotEmpty) _surface();
    });

    // Each beat: dissolve the current thought, then surface the next.
    _cycle = Timer.periodic(widget.hold + widget.fade * 2, (_) => _next());
  }

  @override
  void dispose() {
    _sub?.cancel();
    _cycle?.cancel();
    _swap?.cancel();
    super.dispose();
  }

  void _surface() {
    if (!mounted) return;
    setState(() => _visible = true);
  }

  void _next() {
    if (!mounted || _thoughts.isEmpty) return;
    // Fade out…
    setState(() => _visible = false);
    // …then swap the text while invisible and fade the next one in, so we never
    // cross-fade two different thoughts into an unreadable smear.
    _swap?.cancel();
    _swap = Timer(widget.fade, () {
      if (!mounted || _thoughts.isEmpty) return;
      setState(() {
        _idx = (_idx + 1) % _thoughts.length;
        _anchorSeed++;
        _visible = true;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_thoughts.isEmpty) return const SizedBox.shrink();
    final t = _thoughts[_idx.clamp(0, _thoughts.length - 1)];
    final child = _thoughtBubble(t);
    if (!widget.ambient) return child;

    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w =
              constraints.maxWidth.isFinite ? constraints.maxWidth : 900.0;
          final h =
              constraints.maxHeight.isFinite ? constraints.maxHeight : 600.0;
          final anchor = _ambientAnchor(w, h);
          return KaiInnerMonologue.ambientLayer(
            child: child,
            anchor: anchor,
            duration: widget.fade,
          );
        },
      ),
    );
  }

  Offset _ambientAnchor(double width, double height) {
    final usableW = math.max(0.0, width - widget.maxWidth - 48);
    final usableH = math.max(0.0, height - 190);
    final i = (_idx + _anchorSeed) % _ambientLanes.length;
    final base = _ambientLanes[i];
    return Offset(
      24 + usableW * base.dx,
      36 + usableH * base.dy,
    );
  }

  Widget _thoughtBubble(_Thought t) {
    // Reflections (recombined "dream" thoughts) are marked with ↳ — tint those
    // toward the Claude hemisphere, first-order thoughts toward GPT.
    final isReflection = t.text.trimLeft().startsWith('↳');
    final accent = isReflection ? _claude : _gpt;

    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: _visible ? 1.0 : 0.0,
        duration: widget.fade,
        curve: Curves.easeInOut,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: widget.maxWidth),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 5, right: 7),
                child: Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accent.withOpacity(0.75),
                    boxShadow: [
                      BoxShadow(color: accent.withOpacity(0.55), blurRadius: 7),
                    ],
                  ),
                ),
              ),
              Flexible(
                child: Text(
                  t.text,
                  style: TextStyle(
                    color:
                        Colors.white.withOpacity(widget.ambient ? 0.30 : 0.40),
                    fontSize: widget.ambient ? 11.0 : 11.5,
                    height: 1.4,
                    fontStyle: FontStyle.italic,
                    letterSpacing: 0.2,
                    shadows: [
                      Shadow(
                        color: Colors.black.withOpacity(0.55),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
