// KaiProjectCard — the work stack. A layered project, live and collapsible.
//
// The previous version of this was a hardcoded `const layers = [...]` inside the
// shell, which meant the only way to "make progress" was to edit a string
// literal — and that's exactly what happened: seven `'status': 'done'` and a
// test asserting the text said done.
//
// This one can't lie the same way. It streams from RTDB, so:
//   • it shows what's ACTUALLY recorded, updating mid-run as Kai reports
//   • progress is a NUMBER per layer, not a word — a half-built layer looks
//     half-built instead of rounding itself up to "done"
//   • the frozen `intent` is displayed, so the goal is visible next to the
//     claim. You can always see what was actually promised.
//
// ── Why it's collapsible ───────────────────────────────────────────────────
//
// It used to render all seven layers expanded, unconditionally:
//
//     for (final l in p.layers) _layer(l)
//
// …inside a Column, inside a SizedBox(height: 300). Seven layers × ~76px of
// title + intent + bar + evidence ≈ 833px. Result: "BOTTOM OVERFLOWED BY 533
// PIXELS" painted across the UI, and the bottom four layers unreachable.
//
// A stack of seven things doesn't want to be seven open drawers. Collapsed it's
// one line each — number, title, state — and the one you're actually working on
// is open. The body scrolls, so it can never overflow again regardless of how
// many layers exist.
//
// Wire-up: KaiProjectCard(personaId: 'truekai', projectId: KaiProjectService.smarterId)
library;

import 'package:flutter/material.dart';
import '../services/core/kai_project_service.dart';

const _gpt = Color(0xFFFF9D2F); // in progress
const _claude = Color(0xFF2ED9FF); // next up
const _done = Color(0xFF7EE787); // done
const _later = Color(0xFF5B7183); // not started, not next

/// What a layer is, at a glance. Kept separate from `progress` on purpose:
/// "next" isn't a number, it's a position in the queue, and it's the single most
/// useful thing on this card.
enum _State { done, active, next, later }

class KaiProjectCard extends StatefulWidget {
  final String personaId;
  final String projectId;

  const KaiProjectCard({
    super.key,
    required this.personaId,
    this.projectId = KaiProjectService.smarterId,
  });

  @override
  State<KaiProjectCard> createState() => _KaiProjectCardState();
}

class _KaiProjectCardState extends State<KaiProjectCard> {
  /// Which layer is open. Null = all collapsed.
  ///
  /// Nullable and single-valued: opening one closes the others, because the
  /// point of the stack is "what am I on", not "read everything at once". That
  /// was the old behaviour and it's what overflowed.
  int? _open;

  /// True once the user has touched it — after that, stop auto-opening. Nothing
  /// worse than a panel that keeps reopening itself because the data ticked.
  bool _touched = false;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<KaiProject?>(
      stream: KaiProjectService.instance.watch(widget.personaId, widget.projectId),
      builder: (context, snap) {
        final p = snap.data;
        if (p == null || p.layers.isEmpty) return const SizedBox.shrink();
        final pct = (p.completion * 100).round();

        // The first layer that isn't done is "next". Everything after it is
        // "later" — visible, but clearly not the thing.
        final nextIdx = p.layers.indexWhere((l) => !l.isDone);

        // Open the layer he's actually mid-way through; failing that, the next
        // one. That's the line you want your eye on when you glance at this.
        if (!_touched && _open == null && nextIdx >= 0) {
          final active = p.layers.indexWhere((l) => !l.isDone && l.progress > 0);
          _open = active >= 0 ? active : nextIdx;
        }

        return Container(
          margin: const EdgeInsets.all(10),
          padding: const EdgeInsets.fromLTRB(12, 11, 12, 8),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.32),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _claude.withOpacity(0.28)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(p.name.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      letterSpacing: 1.6,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(p.why,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.38),
                      fontSize: 9.5,
                      fontStyle: FontStyle.italic)),
              const SizedBox(height: 9),
              Row(
                children: [
                  // Real completion — the MEAN of actual progress, not a count
                  // of the word "done". 7/7 has to be earned in numbers.
                  Text('$pct%',
                      style: TextStyle(
                          color: pct >= 100 ? _done : _gpt,
                          fontSize: 13,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w700)),
                  const SizedBox(width: 8),
                  Text('${p.doneCount}/${p.layers.length} layers done',
                      style: const TextStyle(
                          color: Color(0xFF6B8194),
                          fontSize: 9,
                          fontFamily: 'monospace')),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: p.completion,
                  minHeight: 3,
                  backgroundColor: Colors.white.withOpacity(0.07),
                  valueColor: AlwaysStoppedAnimation(pct >= 100 ? _done : _gpt),
                ),
              ),
              const SizedBox(height: 8),
              // Expanded + ListView: the stack takes whatever room it's given and
              // scrolls the rest. Whatever height the parent decides, and however
              // many layers exist, this cannot overflow again.
              Expanded(
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  itemCount: p.layers.length,
                  itemBuilder: (_, i) => _layerTile(
                    p.layers[i],
                    i,
                    i == nextIdx
                        ? _State.next
                        : p.layers[i].isDone
                            ? _State.done
                            : p.layers[i].progress > 0
                                ? _State.active
                                : _State.later,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static Color _colour(_State s) => switch (s) {
        _State.done => _done,
        _State.active => _gpt,
        _State.next => _claude,
        _State.later => _later,
      };

  static String _label(_State s, KaiLayer l) => switch (s) {
        _State.done => 'DONE',
        _State.active => '${l.progress}%',
        _State.next => 'NEXT',
        _State.later => l.progress > 0 ? '${l.progress}%' : '—',
      };

  Widget _layerTile(KaiLayer l, int i, _State s) {
    final c = _colour(s);
    final open = _open == i;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── The collapsed row. One line, always. ────────────────────────
          InkWell(
            onTap: () => setState(() {
              _touched = true;
              _open = open ? null : i;
            }),
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Container(
                    width: 16,
                    height: 16,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: s == _State.next ? c.withOpacity(0.16) : null,
                      border: Border.all(color: c.withOpacity(0.7)),
                    ),
                    child: Text('${l.n}',
                        style: TextStyle(
                            color: c, fontSize: 8, fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(l.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: Colors.white
                                .withOpacity(s == _State.later ? 0.5 : 0.85),
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: 4),
                  Text(_label(s, l),
                      style: TextStyle(
                          color: c,
                          fontSize: 9,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w700)),
                  // Affordance: this thing opens. Without it nobody discovers
                  // that the evidence is in there.
                  Icon(open ? Icons.expand_less : Icons.expand_more,
                      size: 13, color: Colors.white.withOpacity(0.25)),
                ],
              ),
            ),
          ),

          // ── Open: the goal, the bar, the receipt. ───────────────────────
          if (open)
            Padding(
              padding: const EdgeInsets.only(left: 23, top: 2, bottom: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // The FROZEN goal, shown next to the claim. The whole failure
                  // last time was the goal drifting to match the work — here you
                  // can always read what was actually promised.
                  Text(l.intent,
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.32),
                          fontSize: 8.8,
                          height: 1.35)),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: l.progress / 100,
                      minHeight: 2,
                      backgroundColor: Colors.white.withOpacity(0.06),
                      valueColor: AlwaysStoppedAnimation(c.withOpacity(0.8)),
                    ),
                  ),
                  if (l.evidence.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('› ${l.evidence.last}',
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: c.withOpacity(0.55),
                              fontSize: 8.2,
                              height: 1.3,
                              fontFamily: 'monospace')),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
