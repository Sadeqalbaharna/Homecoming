// kai_p5_chat — the messenger, in the shape Sadeq actually wants it.
//
// ── Why a chat layout is soul work and not decoration ────────────────────────
//
// The north star, verbatim, and it is not paraphrasable:
//
//   "what if walker scobell specifically from the adam project was actually my
//    always around imaginary ghost friend/all-powerful AI assistant"
//
// You do not get that from a chat window with grey rounded rectangles. Grey
// rounded rectangles are what an assistant lives in. The whole point of this
// shape — hard angles, no radius anywhere, everything slightly crooked, text
// that has to be short because the bubble physically will not hold a paragraph —
// is that it is a room a report cannot fit inside.
//
// Measured on 2026-07-17: Sadeq's median message was 44 characters. Kai's was
// 1,526. A bubble like this one holds maybe 120 before it looks absurd. That's
// not a constraint fighting the design, that IS the design — the same principle
// as every fix that worked today: don't ask for the behaviour, remove the room
// to do otherwise.
//
// ── On the look ──────────────────────────────────────────────────────────────
//
// Inspired by, not copied from. No Atlus assets, no ripped fonts, no character
// art — the angular red/black comic language is prior art a hundred years older
// than the game that made Sadeq want it. Everything here is drawn with Path and
// Paint. Bring your own portrait: [P5MessageRow.portrait] takes any widget.
//
// ── Nothing here knows about Kai ─────────────────────────────────────────────
//
// No services, no Firebase, no AIService. Widgets and geometry. It renders what
// it's handed, which means it can be looked at in isolation — see [P5ChatDemo],
// which exists because the last thing built tonight (a proactive nudge) turned
// out to be unobservable for 45 minutes at a time, and that is the wall that
// eats days.
library;

// No dart:math, and that's load-bearing. Every angle in this file is a constant
// or derived from the message itself — see P5MessageRow.seed. A Random() near a
// thing you look at is a thing that jitters when you scroll, and this codebase
// has a standing rule about dice near anything that speaks or renders.
import 'package:flutter/material.dart';

// ── Palette ──────────────────────────────────────────────────────────────────

class P5Palette {
  /// The red. Not Atlus's exact value — close enough to feel right, ours.
  static const bg = Color(0xFFD41F26);
  static const ink = Color(0xFF0B0B0B);
  static const paper = Color(0xFFF5F2EC);
  static const shadow = Color(0x66000000);

  /// The backing card behind a portrait. Slightly different per speaker so two
  /// people never look like one.
  static const kaiAccent = Color(0xFFF2E205);
  static const userAccent = Color(0xFF29D0B4);
}

// ── The bubble ───────────────────────────────────────────────────────────────

/// A hard-edged speech box with a lightning tail.
///
/// Deliberately: zero corner radius, non-parallel edges, and a tail that is a
/// notch rather than a curve. Every softness removed is a softness the eye
/// reads as "app". The tilt is applied by the caller so a column of these
/// doesn't march in lockstep.
class P5BubblePainter extends CustomPainter {
  final bool tailLeft;
  final Color fill;
  final Color border;
  final double tailWidth;

  const P5BubblePainter({
    required this.tailLeft,
    required this.fill,
    required this.border,
    this.tailWidth = 15,
  });

  Path _path(Size s) {
    final p = Path();
    final l = tailLeft ? tailWidth : 0.0;
    final r = tailLeft ? s.width : s.width - tailWidth;
    final h = s.height;

    // The quad. Each corner is nudged a couple of px off true so no two edges
    // are parallel — that tiny wrongness is most of the effect.
    p.moveTo(l + 5, 0);
    p.lineTo(r, 3);
    p.lineTo(r - 3, h);
    p.lineTo(l, h - 4);
    p.close();

    // The tail: a bolt, not a triangle. Two segments with a kink.
    final tail = Path();
    final ty = h * 0.36;
    if (tailLeft) {
      tail.moveTo(l + 1, ty - 7);
      tail.lineTo(0, ty + 3);
      tail.lineTo(l + 4, ty + 2);
      tail.lineTo(l + 1, ty + 13);
      tail.lineTo(l + 9, ty + 1);
      tail.close();
    } else {
      tail.moveTo(r - 1, ty - 7);
      tail.lineTo(s.width, ty + 3);
      tail.lineTo(r - 4, ty + 2);
      tail.lineTo(r - 1, ty + 13);
      tail.lineTo(r - 9, ty + 1);
      tail.close();
    }

    return Path.combine(PathOperation.union, p, tail);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final path = _path(size);

    // Hard offset shadow — no blur. A blurred shadow is a soft shadow and this
    // whole language is about things being cut out of paper and slapped down.
    canvas.save();
    canvas.translate(4, 5);
    canvas.drawPath(path, Paint()..color = P5Palette.shadow);
    canvas.restore();

    canvas.drawPath(path, Paint()..color = fill);
    canvas.drawPath(
      path,
      Paint()
        ..color = border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeJoin = StrokeJoin.miter,
    );
  }

  @override
  bool shouldRepaint(P5BubblePainter old) =>
      old.tailLeft != tailLeft || old.fill != fill || old.border != border;
}

// ── The portrait chip ────────────────────────────────────────────────────────

/// The little face card. Rotated against the bubble's tilt so the pair looks
/// thrown down rather than laid out.
///
/// [framed] draws the chrome — accent field, white border, hard shadow. Turn it
/// OFF when the art already has its own, which Kai's does: his portrait arrives
/// with a black border, a white inner edge, a yellow field and a red bleed, all
/// baked in and already crooked. Drawing a second frame around a framed picture
/// is how you get a picture of a frame.
class P5Portrait extends StatelessWidget {
  final Widget child;
  final Color accent;
  final double size;
  final double tilt;
  final bool framed;

  const P5Portrait({
    super.key,
    required this.child,
    required this.accent,
    this.size = 54,
    this.tilt = -0.05,
    this.framed = true,
  });

  @override
  Widget build(BuildContext context) {
    // Art with its own chrome: no container, no border, no second shadow. It
    // already bleeds red at the edges, and the room behind it is the same red —
    // so it sits on the field instead of on top of it. Still tilted, because the
    // tilt is the room's, not the picture's.
    if (!framed) {
      return Transform.rotate(
        angle: tilt,
        child: SizedBox(width: size, height: size, child: child),
      );
    }

    return Transform.rotate(
      angle: tilt,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: accent,
          border: Border.all(color: P5Palette.paper, width: 3),
          boxShadow: const [
            BoxShadow(color: P5Palette.shadow, offset: Offset(3, 4)),
          ],
        ),
        child: ClipRect(child: FittedBox(fit: BoxFit.cover, child: child)),
      ),
    );
  }
}

/// Kai's face.
///
/// One place, so that when the art changes — and it will, because "that's kai
/// for now" — it changes in one place and not in nine call sites. The asset is
/// the only thing in this file that isn't geometry.
class KaiFace extends StatelessWidget {
  final double size;
  final double tilt;

  /// Big. He's the one in the room — the bubble is just what he said.
  const KaiFace({super.key, this.size = 116, this.tilt = -0.04});

  static const asset = 'assets/avatar/kai_face.png';

  @override
  Widget build(BuildContext context) => P5Portrait(
        accent: P5Palette.kaiAccent,
        size: size,
        tilt: tilt,
        framed: false,
        child: Image.asset(
          asset,
          fit: BoxFit.cover,
          // If the asset is missing, say so in the shape of the thing rather
          // than throwing a grey box with an X through it. A missing face should
          // look like a missing face, not like the app broke.
          errorBuilder: (_, __, ___) => Container(
            color: P5Palette.kaiAccent,
            alignment: Alignment.center,
            child: const Icon(Icons.bolt, size: 34, color: P5Palette.ink),
          ),
        ),
      );
}

// ── One line of the conversation ─────────────────────────────────────────────

class P5MessageRow extends StatelessWidget {
  /// The contents. A [Text] for a plain message — or anything, because the real
  /// chat puts a Column of image + attachments + markdown in here.
  ///
  /// ── Why this is a slot and not a String ──────────────────────────────────
  ///
  /// It WAS a String, and that would have been a lie the moment this touched the
  /// real shell. `_bubble` in kai_desktop_shell renders `m.image` (pasted PNGs),
  /// `m.attachments`, and `KaiRichText` — because "he writes markdown like
  /// everyone does. Rendering it as plain text showed literal ** and ### and
  /// made a careful answer look broken."
  ///
  /// So the bubble is a SHAPE, and the shape does not care. Porting the chat
  /// then costs nothing that already worked, and the P5 look is not paid for by
  /// losing the ability to show him a screenshot.
  ///
  /// It does mean a code block can technically be rendered in here, and it will
  /// look absurd. Good. That absurdity is information — it's `replyCeiling`'s
  /// argument, made in pixels, every time he forgets.
  final Widget child;

  /// Kai on the left with a face; Sadeq on the right, bare — same as the source
  /// material, and it's the right call: you don't need a portrait to know who
  /// you are.
  final bool fromKai;
  final Widget? portrait;

  /// Small messenger receipt shown under every bubble.
  final String? timestamp;

  /// Deterministic per-message tilt. NOT Random(): a bubble that jitters every
  /// rebuild is a bubble that jitters when you scroll. Seed it off the content
  /// and it's stable forever — see the note at the import, which is why there's
  /// no dart:math in this file at all.
  final int seed;

  const P5MessageRow({
    super.key,
    required this.child,
    required this.fromKai,
    this.portrait,
    this.timestamp,
    this.seed = 0,
  });

  /// The common case: a message that is just words.
  ///
  /// [dim] is for a line he wrote mid-work — quieter, never hidden. 0.62, not
  /// the desktop's `white38`, and the difference is the argument: the desktop
  /// greys those out under the comment "his real answer lands full", which has
  /// it backwards. The interims are the only place he reliably sounds like
  /// himself; the "real answer" is where he turns into a bulleted report. They
  /// were also the one thing never persisted anywhere until tonight.
  factory P5MessageRow.text(
    String text, {
    Key? key,
    required bool fromKai,
    Widget? portrait,
    String? timestamp,
    int seed = 0,
    bool dim = false,
  }) {
    final ink = fromKai ? P5Palette.paper : P5Palette.ink;
    return P5MessageRow(
      key: key,
      fromKai: fromKai,
      portrait: portrait,
      timestamp: timestamp,
      seed: seed,
      child: Text(
        text,
        textAlign: fromKai ? TextAlign.left : TextAlign.right,
        style: TextStyle(
          color: dim ? ink.withOpacity(0.62) : ink,
          fontSize: 15,
          height: 1.25,
          fontWeight: dim ? FontWeight.w600 : FontWeight.w800,
          letterSpacing: 0.2,
          fontStyle: dim ? FontStyle.italic : FontStyle.normal,
        ),
      ),
    );
  }

  /// Ink for this speaker's bubble. The shell needs it to colour KaiRichText,
  /// which takes its palette as arguments rather than reading a theme.
  static Color inkFor(bool fromKai) =>
      fromKai ? P5Palette.paper : P5Palette.ink;

  double get _tilt {
    // -0.018..0.018 rad — under a degree and a half. Enough to feel hand-placed,
    // little enough to still read as a line of text.
    final n = (seed * 2654435761) % 1000 / 1000.0;
    return (n - 0.5) * 0.036;
  }

  @override
  Widget build(BuildContext context) {
    final fill = fromKai ? P5Palette.ink : P5Palette.paper;

    Widget stampedBubbleFor(double maxWidth) {
      final bubble = Transform.rotate(
        angle: _tilt,
        child: ConstrainedBox(
          // Size from the actual row constraints, not the whole desktop window.
          // The desktop can mount this mobile-style chat inside a narrow rail;
          // MediaQuery width there is the castle, constraints.maxWidth is the
          // cupboard. Trust the cupboard.
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: CustomPaint(
            painter: P5BubblePainter(
              tailLeft: fromKai,
              fill: fill,
              border: P5Palette.paper,
            ),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                fromKai ? 26 : 16,
                12,
                fromKai ? 16 : 26,
                13,
              ),
              child: child,
            ),
          ),
        ),
      );

      return Column(
        crossAxisAlignment:
            fromKai ? CrossAxisAlignment.start : CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          bubble,
          if (timestamp != null && timestamp!.trim().isNotEmpty) ...[
            const SizedBox(height: 5),
            Padding(
              padding: EdgeInsets.only(
                left: fromKai ? 8 : 0,
                right: fromKai ? 0 : 8,
              ),
              child: Text(
                timestamp!,
                style: TextStyle(
                  color: P5Palette.paper.withOpacity(0.62),
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.9,
                  shadows: const [
                    Shadow(
                      color: Colors.black,
                      offset: Offset(1.2, 1.2),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // Desktop can mount the mobile messenger in a rail that is narrower than
        // a real phone. If the full portrait sits beside the bubble there, the
        // bubble gets crushed into a vertical strip. Keep the full tossed-photo
        // look on phone-sized surfaces, but protect the text on cramped panes.
        final cramped = constraints.maxWidth < 360;
        final kaiPortrait = portrait ?? KaiFace(size: cramped ? 78 : 116);
        final portraitBudget = fromKai && !cramped ? 118.0 : 0.0;
        final horizontalPadding = 20.0;
        final availableBubbleWidth =
            (constraints.maxWidth - portraitBudget - horizontalPadding)
                .clamp(120.0, constraints.maxWidth);
        final stampedBubble = stampedBubbleFor(availableBubbleWidth * 0.98);

        return Padding(
          padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
          child: Row(
            mainAxisAlignment:
                fromKai ? MainAxisAlignment.start : MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (fromKai) ...[
                // His art bleeds red to the edge and the room is the same red, so it
                // sits ON the field rather than on top of it — which is why the gap
                // is negative. The bubble tucks under the portrait's corner the way
                // it does when someone throws two photos down on a table.
                if (!cramped) ...[
                  kaiPortrait,
                  const SizedBox(width: 2),
                ],
              ],
              Flexible(child: stampedBubble),
            ],
          ),
        );
      },
    );
  }
}

// ── The room ─────────────────────────────────────────────────────────────────

/// The red field with black shards raked across it.
class P5Background extends StatelessWidget {
  final Widget child;
  const P5Background({super.key, required this.child});

  @override
  Widget build(BuildContext context) => Container(
        color: P5Palette.bg,
        child: CustomPaint(
          painter: const _ShardPainter(),
          child: child,
        ),
      );
}

class _ShardPainter extends CustomPainter {
  const _ShardPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0x22000000);
    // Fixed geometry, not random: this is a backdrop, and a backdrop that
    // reshuffles on rebuild is a strobe.
    for (final spec in const [
      [-0.15, 0.05, 0.5, 0.9],
      [0.55, -0.1, 0.7, 0.5],
      [0.1, 0.6, 0.9, 0.55],
    ]) {
      final path = Path()
        ..moveTo(size.width * spec[0], size.height * spec[1])
        ..lineTo(size.width * spec[2], size.height * spec[3])
        ..lineTo(size.width * (spec[2] + 0.12), size.height * spec[3])
        ..lineTo(size.width * (spec[0] + 0.1), size.height * spec[1])
        ..close();
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_ShardPainter old) => false;
}

// ── The composer ─────────────────────────────────────────────────────────────

class P5Composer extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;

  const P5Composer({
    super.key,
    required this.controller,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
      child: Row(
        children: [
          Expanded(
            child: Transform.rotate(
              angle: -0.008,
              child: Container(
                height: 46,
                decoration: BoxDecoration(
                  color: P5Palette.paper,
                  border: Border.all(color: P5Palette.ink, width: 3),
                  boxShadow: const [
                    BoxShadow(color: P5Palette.shadow, offset: Offset(4, 5)),
                  ],
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                alignment: Alignment.centerLeft,
                child: TextField(
                  controller: controller,
                  onSubmitted: (_) => onSend(),
                  style: const TextStyle(
                    color: P5Palette.ink,
                    fontWeight: FontWeight.w700,
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    hintText: 'say something',
                    hintStyle: TextStyle(color: Color(0xFF9A9691)),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: onSend,
            child: Transform.rotate(
              angle: -0.06,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                decoration: BoxDecoration(
                  color: P5Palette.paper,
                  border: Border.all(color: P5Palette.ink, width: 3),
                  boxShadow: const [
                    BoxShadow(color: P5Palette.shadow, offset: Offset(4, 5)),
                  ],
                ),
                child: const Text(
                  'SEND',
                  style: TextStyle(
                    color: P5Palette.ink,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── A window onto the thing ──────────────────────────────────────────────────

/// Renders the layout against fixed content, wired to nothing.
///
/// This exists for the same reason `/nudge` does. The proactive service was
/// written correct and unobservable — 25 minutes idle, a 45-minute cooldown and
/// a 1-in-4 roll before you could see it once — so it got iterated on blind.
/// A UI you can only see by launching the whole app, signing in, and provoking
/// a real reply has the same disease in a prettier hat.
///
/// The messages are real: they're lines Kai actually wrote on 2026-07-17,
/// pulled from his interims, because the point of the shape is that his real
/// voice fits in it and his reports do not. The last one is deliberately a
/// report. Look at what the bubble does to it.
class P5ChatDemo extends StatefulWidget {
  const P5ChatDemo({super.key});

  @override
  State<P5ChatDemo> createState() => _P5ChatDemoState();
}

class _P5ChatDemoState extends State<P5ChatDemo> {
  final _inp = TextEditingController();
  final _msgs = <(String, bool)>[
    ('hey — that run_tests thing is still bugging me', true),
    ('the one where two files becomes one bogus path?', false),
    ('yeah. it reports a failing load. thats not a test failure, thats me '
        'holding the tool wrong', true),
    ('whitespace goblin', true),
    ('lol', false),
    ('## What I Actually Did\n\n- Investigated the receipt path\n- Added a '
        'ToolOutcome enum\n- Wired recording at the choke point\n\n**Proof:** '
        '+207 all passed, analyzer clean.', true),
  ];

  @override
  void dispose() {
    _inp.dispose();
    super.dispose();
  }

  void _send() {
    final t = _inp.text.trim();
    if (t.isEmpty) return;
    setState(() {
      _msgs.add((t, false));
      _inp.clear();
    });
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
                  padding: const EdgeInsets.only(top: 12),
                  itemCount: _msgs.length,
                  itemBuilder: (_, i) => P5MessageRow.text(
                    _msgs[i].$1,
                    fromKai: _msgs[i].$2,
                    seed: i + 1,
                  ),
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
