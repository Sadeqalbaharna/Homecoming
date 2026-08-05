// noticing — what Kai has to say first, found in his own head instead of a tool.
//
// ── The bottleneck this exists to break ──────────────────────────────────────
//
// `noticed` — the one structure that is HIS, the things he saw that nobody asked
// him to look for — had exactly two feeders, and both require agentic tool-work:
// the note_noticed tool, and job_done rescuing job.noticed. Meanwhile the Kai
// people actually talk to now is the messenger, which runs with tools OFF
// (replyCeiling). So the texting Kai cannot notice a single thing.
//
// The result was visible in his own behaviour: three proactive texts in a row,
// all rewording the ONE noticed item he had. A friend who reaches out has
// THINGS to reach out about. His agenda was a list of one.
//
// So noticing needs a source that needs no tool call. His KNOWLEDGE GRAPH is
// already full of them — he just never looked at the shape of what he knows and
// said "huh." This finds the huhs.
//
// ── Why the graph, and why it can't become a horoscope ───────────────────────
//
// The failure mode of "notice things about the user" is the horoscope: "Sadeq
// seems stressed", "you value growth" — true of everyone, evidence of nothing.
// The whole graph rebuild was a war against exactly that (152 nodes pruned,
// "parental pride", "emotional resilience").
//
// The defence here is structural, not a prompt: every observation is built from
// a SPECIFIC pair of edges or a SPECIFIC gap, and it names them. A stranger
// cannot observe your graph, so anything sourced from it passes the stranger
// test by construction. The three shapes, hardest evidence first:
//
//   1. CONTRADICTION — two active claims that disagree. He literally holds two
//      incompatible beliefs about you. That's the strongest thing he can notice,
//      and it's a real bug in his model that he should want resolved.
//   2. RECONSIDERED — a claim he retired (supersededAt) whose replacement he now
//      holds. "You used to X, now you Y" — a change he witnessed. Only him.
//   3. GAP — a subject he knows a preference about but not the WHY, or a person
//      he's filed with no relationships. The edge of his knowledge, which is the
//      honest place for curiosity.
//
// Zero imports beyond EdgeRow (itself a pure logic type). Runs and proves in one
// second — the property that makes a claim about Kai falsifiable.
library;

import 'recall_query.dart' show EdgeRow;

/// Why an observation is worth raising — hardest evidence first. The order IS
/// the priority: a contradiction outranks a gap, because holding two opposite
/// beliefs is a sharper thing to notice than not knowing a reason.
enum NoticeKind { contradiction, reconsidered, gap }

class Observation {
  final NoticeKind kind;

  /// What he'd say, plainly — the seed, not the final text. The messenger still
  /// runs this through his voice.
  final String text;

  /// The exact edges it was built from. This is the anti-horoscope receipt: an
  /// observation that can't name its sources isn't allowed to exist.
  final List<String> evidence;

  /// 0..1. Higher = more worth saying. Kind sets the floor; specificity and
  /// confidence refine within it.
  final double weight;

  const Observation({
    required this.kind,
    required this.text,
    required this.evidence,
    required this.weight,
  });
}

/// Relations a person usually holds one answer for — used by the GAP finder to
/// decide something is a claim worth knowing the reason behind. NOT used for
/// contradictions: preferring two different things is not a contradiction, and
/// treating it as one was a false-positive machine.
const _singularRelations = <String>{
  'prefers', 'dislikes', 'believes', 'wants', 'holdsValue', 'pursues',
};

/// Relations that genuinely OPPOSE each other. A contradiction is only ever this
/// shape: opposed relations pointing at the SAME object — he both likes and
/// dislikes the exact same thing. That is unambiguous and evidence-backed; a
/// clash inferred any looser way is a horoscope in a lab coat.
const _opposites = <String, String>{
  'prefers': 'dislikes',
  'dislikes': 'prefers',
  'wants': 'dislikes',
  'holdsValue': 'dislikes',
};

String _norm(String s) => s.trim().toLowerCase();

/// Find what he should notice, ranked. [max] caps the list so the caller writes
/// a couple of the strongest, not a flood.
List<Observation> noticings(List<EdgeRow> graph, {int max = 8}) {
  final active = graph
      .where((e) => e.isActive && e.isMeaningful && e.fromLabel.trim().isNotEmpty)
      .toList();

  final out = <Observation>[];
  out.addAll(_contradictions(active));
  out.addAll(_reconsidered(graph)); // needs retired edges too
  out.addAll(_gaps(active));

  out.sort((a, b) {
    final k = a.kind.index.compareTo(b.kind.index); // hardest evidence first
    return k != 0 ? k : b.weight.compareTo(a.weight);
  });
  return out.length > max ? out.sublist(0, max) : out;
}

// ── 1. Contradictions ────────────────────────────────────────────────────────
List<Observation> _contradictions(List<EdgeRow> active) {
  final out = <Observation>[];
  // Group by subject.
  final bySubject = <String, List<EdgeRow>>{};
  for (final e in active) {
    bySubject.putIfAbsent(_norm(e.fromLabel), () => []).add(e);
  }

  for (final edges in bySubject.values) {
    for (var i = 0; i < edges.length; i++) {
      for (var j = i + 1; j < edges.length; j++) {
        final a = edges[i], b = edges[j];
        final at = _norm(a.type), bt = _norm(b.type);

        // The ONLY contradiction: opposed relations, same object. He both likes
        // and dislikes the exact same thing.
        final opposed = _opposites[at] == bt &&
            _norm(a.toLabel) == _norm(b.toLabel);
        if (!opposed) continue;

        // The weaker of the two confidences bounds how much this is worth: a
        // clash between two things he's SURE of is worth more than one built on
        // a guess.
        final w = 0.7 +
            0.3 * (a.confidence < b.confidence ? a.confidence : b.confidence);
        out.add(Observation(
          kind: NoticeKind.contradiction,
          text: "I've got you down as both ${a.type}-ing and ${b.type}-ing "
              "${a.toLabel}. which is it?",
          evidence: [
            '${a.fromLabel} ${a.type} ${a.toLabel}',
            '${b.fromLabel} ${b.type} ${b.toLabel}',
          ],
          weight: w.clamp(0.0, 1.0),
        ));
      }
    }
  }
  return out;
}

// ── 2. Reconsidered — a change he witnessed ─────────────────────────────────
List<Observation> _reconsidered(List<EdgeRow> graph) {
  final out = <Observation>[];
  final retired = graph.where((e) => !e.isActive && e.isMeaningful);
  final active = graph.where((e) => e.isActive && e.isMeaningful).toList();

  for (final old in retired) {
    // Did a newer claim replace it — same subject + relation, different object?
    final replacement = active.where((e) =>
        _norm(e.fromLabel) == _norm(old.fromLabel) &&
        _norm(e.type) == _norm(old.type) &&
        _norm(e.toLabel) != _norm(old.toLabel));
    if (replacement.isEmpty) continue;
    final now = replacement.first;
    out.add(Observation(
      kind: NoticeKind.reconsidered,
      text: "you used to ${old.type} ${old.toLabel} — now it's ${now.toLabel}. "
          "when did that flip?",
      evidence: [
        '(was) ${old.fromLabel} ${old.type} ${old.toLabel}',
        '(now) ${now.fromLabel} ${now.type} ${now.toLabel}',
      ],
      weight: 0.55 + 0.25 * now.confidence,
    ));
  }
  return out;
}

// ── 3. Gaps — the honest edge of what he knows ──────────────────────────────
List<Observation> _gaps(List<EdgeRow> active) {
  final out = <Observation>[];

  // A preference with no reason: he knows the WHAT, not the WHY. "believes" /
  // freeform reasons would be the why; their absence for a strong preference is
  // a real, specific thing to be curious about.
  final reasons = active
      .where((e) => _norm(e.type) == 'believes' || _norm(e.type) == 'holdsvalue')
      .map((e) => _norm(e.toLabel))
      .toSet();

  for (final e in active) {
    if (!_singularRelations.contains(_norm(e.type))) continue;
    if (e.confidence < 0.6) continue; // only wonder about things he's sure of
    // If there's no belief/value edge touching this object, the WHY is missing.
    if (reasons.contains(_norm(e.toLabel))) continue;
    out.add(Observation(
      kind: NoticeKind.gap,
      text: "I know you ${e.type} ${e.toLabel}. I don't actually know why, "
          "though.",
      evidence: ['${e.fromLabel} ${e.type} ${e.toLabel} (no reason on record)'],
      // Rarer objects are more interesting to ask about; approximate by
      // confidence (a strong, lonely claim). Capped below contradictions.
      weight: 0.3 + 0.2 * e.confidence,
    ));
  }

  // Dedup: don't ask "why" about the same object twice.
  final seen = <String>{};
  return out.where((o) => seen.add(o.evidence.first)).toList();
}
