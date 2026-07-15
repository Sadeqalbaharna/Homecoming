// KaiInnerMonologue — an ambient "stream of consciousness".
//
// Streams the last few spontaneous thoughts InnerLifeService writes to
// /kai/{persona}/inner_monologue and renders them as a soft, fading column —
// Kai quietly thinking to himself. Non-interactive; drop it anywhere in a Stack
// (e.g. bottom-centre of the desktop shell).
//
// Wire-up:  const KaiInnerMonologue(personaId: 'truekai')  inside a Stack,
// wrapped in Align/Positioned as you like.
library;

import 'package:flutter/material.dart';
import '../services/core/kai_db.dart';

const _gpt = Color(0xFFFF9D2F);
const _claude = Color(0xFF2ED9FF);

class _Thought {
  final String text;
  final int ts;
  const _Thought(this.text, this.ts);
}

class KaiInnerMonologue extends StatefulWidget {
  final String personaId;
  final int maxLines;
  const KaiInnerMonologue({super.key, required this.personaId, this.maxLines = 4});

  @override
  State<KaiInnerMonologue> createState() => _KaiInnerMonologueState();
}

class _KaiInnerMonologueState extends State<KaiInnerMonologue> {
  List<_Thought> _thoughts = const [];

  @override
  void initState() {
    super.initState();
    KaiDb.instance
        .ref('kai/${widget.personaId}/inner_monologue')
        .limitToLast(widget.maxLines)
        .onValue
        .listen((event) {
      final v = event.snapshot.value;
      if (v is! Map) return;
      final list = <_Thought>[];
      v.forEach((_, val) {
        if (val is Map) {
          list.add(_Thought(
            (val['text'] ?? '').toString(),
            (val['ts'] is int) ? val['ts'] as int : 0,
          ));
        }
      });
      list.sort((a, b) => a.ts.compareTo(b.ts));
      if (mounted) setState(() => _thoughts = list);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_thoughts.isEmpty) return const SizedBox.shrink();
    final n = _thoughts.length;
    return IgnorePointer(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (int i = 0; i < n; i++)
              _line(_thoughts[i].text, (i + 1) / n),
          ],
        ),
      ),
    );
  }

  Widget _line(String text, double freshness) {
    // newest lines brighter; all soft
    final op = 0.16 + 0.42 * freshness;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6, right: 8),
            child: Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: (freshness > 0.8 ? _gpt : _claude).withOpacity(op + 0.2),
                boxShadow: [
                  BoxShadow(
                      color: (freshness > 0.8 ? _gpt : _claude).withOpacity(op),
                      blurRadius: 6),
                ],
              ),
            ),
          ),
          Flexible(
            child: Text(
              text,
              style: TextStyle(
                color: Colors.white.withOpacity(op),
                fontSize: 12,
                height: 1.35,
                fontStyle: FontStyle.italic,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
