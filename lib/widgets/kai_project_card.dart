// KaiProjectCard — a layered project, live.
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
// Wire-up: KaiProjectCard(personaId: 'truekai', projectId: KaiProjectService.smarterId)
library;

import 'package:flutter/material.dart';
import '../services/core/kai_project_service.dart';

const _gpt = Color(0xFFFF9D2F);
const _claude = Color(0xFF2ED9FF);
const _done = Color(0xFF7EE787);

class KaiProjectCard extends StatelessWidget {
  final String personaId;
  final String projectId;

  const KaiProjectCard({
    super.key,
    required this.personaId,
    this.projectId = KaiProjectService.smarterId,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<KaiProject?>(
      stream: KaiProjectService.instance.watch(personaId, projectId),
      builder: (context, snap) {
        final p = snap.data;
        if (p == null || p.layers.isEmpty) return const SizedBox.shrink();
        final pct = (p.completion * 100).round();

        return Container(
          margin: const EdgeInsets.all(10),
          padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.32),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _claude.withOpacity(0.28)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(p.name.toUpperCase(),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      letterSpacing: 1.6,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(p.why,
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
              const SizedBox(height: 10),
              for (final l in p.layers) _layer(l),
            ],
          ),
        );
      },
    );
  }

  Widget _layer(KaiLayer l) {
    final c = l.isDone
        ? _done
        : l.progress > 0
            ? _gpt
            : const Color(0xFF5B7183);

    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 16,
                height: 16,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: c.withOpacity(0.7)),
                ),
                child: Text('${l.n}',
                    style: TextStyle(
                        color: c, fontSize: 8, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(l.title,
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.85),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600)),
              ),
              Text(l.isDone ? 'DONE' : '${l.progress}%',
                  style: TextStyle(
                      color: c,
                      fontSize: 9,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w700)),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 23, top: 3),
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
                    padding: const EdgeInsets.only(top: 3),
                    child: Text('› ${l.evidence.last}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: c.withOpacity(0.55),
                            fontSize: 8.2,
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
