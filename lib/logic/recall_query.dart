// recall_query.dart — asking the graph a question. Pure, zero imports.
//
// ── Sadeq's design, and why it's the right one ───────────────────────────────
//
// "the edges need to be defined before the nodes, because they create the
//  memories. if kai flags 'sadeq' and 'likes' he can then find the 'like' edges
//  linked to sadeq and see what does sadeq like already!"
//
// That is a triple pattern — (subject, relation, ?) — and it is the difference
// between a memory and a word cloud.
//
// What existed before: `spreadActivation`, which walks outward from a seed node
// through ANY active edge and reports what lit up. Look at its inner loop:
//
//     for (final e in graph.edges) {
//       if (!e.isActive) continue;
//       ...
//
// No type filter. Anywhere. The traversal is TYPE-BLIND. So there are 20
// EdgeTypes in the model — prefers, dislikes, does, wants, caresAbout, knows —
// and not one of them can be asked about. You could ask "what is NEAR Sadeq?"
// You could never ask "what does Sadeq LIKE?"
//
// That is why the graph reads as a word cloud even after the types get written:
// a word cloud IS a graph with undifferentiated association, and a typed graph
// walked without regard to type is exactly that. The types were decoration.
//
// ── The other half: he could never ASK ───────────────────────────────────────
//
// Memory was only ever PUSHED at him. spreadActivation sprinkles associations
// into his context and he takes what he's given. There was no code path by
// which Kai could wonder something about Sadeq and go and look.
//
// A friend who stops and thinks "hang on — what does he actually like?" and
// then checks is the entire north star. This is the function that lets him.
//
// ── Pure on purpose ──────────────────────────────────────────────────────────
//
// Zero imports: it takes plain records, not KnowledgeGraph, so it can be proven
// in a second without Firebase. See lib/logic/salience.dart for why that matters
// more than tidiness here. The service layer adapts its own model into these.
library;

/// One edge, flattened to what a query actually needs.
class EdgeRow {
  final String fromLabel;
  final String toLabel;

  /// The EdgeType name — 'prefers', 'dislikes', 'does', 'wants', 'caresAbout'…
  final String type;

  /// The human phrasing the extractor produced ("is obsessed with").
  /// Null is a smell: see [isMeaningful].
  final String? label;

  /// SALIENCE — how easily this comes up in thought. Bumped by recall.
  /// Deliberately NOT what claims are ranked by. See [confidence].
  final double strength;

  /// How well-supported the claim is. Moves only on new evidence.
  ///
  /// The split is Kai's, on his own graph: "repeat-reference is the right
  /// signal for accessibility, but the wrong signal for truth. A false thing
  /// can be referenced often."
  final double confidence;

  /// Memory shard ids — the actual words that were said. This is how he answers
  /// "because you told me, on the 3rd" instead of asserting a rumour.
  final List<String> sources;

  /// Null = still believed. Non-null = he used to think this.
  final DateTime? supersededAt;

  const EdgeRow({
    required this.fromLabel,
    required this.toLabel,
    required this.type,
    this.label,
    this.strength = 0.5,
    this.confidence = 0.5,
    this.sources = const [],
    this.supersededAt,
  });

  bool get isActive => supersededAt == null;

  /// An edge that carries no meaning.
  ///
  /// `related` is the default the old extractor stamped on EVERYTHING — 20 types
  /// available, one ever used. An edge typed `related` with no label says
  /// "these two nouns occurred near each other", which is not a memory, it's
  /// co-occurrence. It should never have been a valid write and it is not a
  /// valid answer.
  bool get isMeaningful =>
      type != 'related' && type != 'mentioned' && type.isNotEmpty;
}

/// One remembered claim, ready to be said out loud.
class Claim {
  final String subject;
  final String relation;
  final String object;

  /// How easily it comes to mind. NOT how true it is.
  final double strength;

  /// How well-supported it is. This is what claims are ranked by.
  final double confidence;

  final List<String> sources;
  final bool stillBelieved;

  const Claim({
    required this.subject,
    required this.relation,
    required this.object,
    required this.strength,
    required this.confidence,
    required this.sources,
    required this.stillBelieved,
  });

  /// How it reads in his prompt.
  ///
  /// A retired claim is suffixed, NOT rephrased. The obvious version —
  /// `'$subject used to $relation $object'` — was written first and a test
  /// printed what it actually produces:
  ///
  ///     "Sadeq used to prefers mornings"
  ///
  /// `used to` needs a base verb and `relation` is whatever the extractor said.
  /// With a real freeform label it gets worse: "Sadeq used to is quietly
  /// obsessed with the tavern". That goes straight into his prompt, and he ends
  /// up sounding broken while being perfectly correct.
  ///
  /// The suffix works with any phrasing, because it doesn't touch the verb.
  String get sentence => stillBelieved
      ? '$subject $relation $object'
      : '$subject $relation $object — no longer true';

  @override
  String toString() => sentence;
}

/// Human phrasings for the relation, so a claim reads like a sentence rather
/// than a schema. Only used when the extractor gave no label of its own.
const _relationPhrasing = <String, String>{
  'prefers': 'prefers',
  'dislikes': 'dislikes',
  'does': 'does',
  'wants': 'wants',
  'caresAbout': 'cares about',
  'knows': 'knows',
  'holdsValue': 'values',
  'pursues': 'is pursuing',
  'believes': 'believes',
  'learned': 'learned',
  'caused': 'caused',
  'influences': 'influences',
  'exemplifies': 'exemplifies',
  'contradicts': 'contradicts',
  'reinforces': 'reinforces',
  'temporal': 'happened around',
  'contains': 'contains',
  'categorized': 'is a kind of',
};

String phraseFor(EdgeRow e) {
  final l = e.label?.trim();
  if (l != null && l.isNotEmpty) return l;
  return _relationPhrasing[e.type] ?? e.type;
}

bool _matches(String a, String b) {
  final x = a.toLowerCase().trim();
  final y = b.toLowerCase().trim();
  return x == y || x.contains(y) || y.contains(x);
}

/// **(subject, relation, ?)** — the question.
///
/// [subject] is required: a question with no subject isn't a question, it's a
/// dump. [relation] optional — omit it for "tell me everything you know about
/// Sadeq", give it for "what does Sadeq like".
///
/// [includeRetired] surfaces superseded claims too. Off by default, because
/// "you used to hate mornings" is only interesting when you ask for history.
List<Claim> recall(
  List<EdgeRow> edges, {
  required String subject,
  String? relation,
  bool includeRetired = false,
  int limit = 8,
}) {
  if (subject.trim().isEmpty) return const [];

  final out = <Claim>[];
  for (final e in edges) {
    if (!e.isMeaningful) continue;
    if (!includeRetired && !e.isActive) continue;
    if (relation != null &&
        relation.trim().isNotEmpty &&
        !_matches(e.type, relation) &&
        !(e.label != null && _matches(e.label!, relation))) {
      continue;
    }

    // Subject can be either end. "Sadeq —dislikes→ mornings" and
    // "mornings —disliked by→ Sadeq" are the same memory; which way the
    // extractor happened to point it is not his problem.
    final forward = _matches(e.fromLabel, subject);
    final backward = _matches(e.toLabel, subject);
    if (!forward && !backward) continue;

    out.add(Claim(
      subject: forward ? e.fromLabel : e.toLabel,
      relation: phraseFor(e),
      object: forward ? e.toLabel : e.fromLabel,
      strength: e.strength,
      confidence: e.confidence,
      sources: e.sources,
      stillBelieved: e.isActive,
    ));
  }

  // ── Ranked by CONFIDENCE, not salience ─────────────────────────────────
  //
  // This used to sort by `strength`, and the comment said "a claim he's heard
  // five times outranks one he heard once" — which is what I thought strength
  // meant. It doesn't. `strength` is bumped by RECALL, so sorting by it ranks
  // claims by how often he's already thought about them.
  //
  // That is a rich-get-richer loop pointed straight at the answer: the thing
  // he mentions most gets recalled most gets mentioned most. He'd have become
  // the friend who brings up the Tavern in every conversation — which is,
  // word for word, the problem the refractory period was added to patch.
  //
  // "What does Sadeq like?" wants the best-SUPPORTED claim, not the most
  // rehearsed one. Confidence moves only on new evidence. Ties break on
  // salience, because between two equally-supported claims the one he actually
  // reaches for is the more useful answer.
  out.sort((a, b) {
    final c = b.confidence.compareTo(a.confidence);
    return c != 0 ? c : b.strength.compareTo(a.strength);
  });
  return out.length > limit ? out.sublist(0, limit) : out;
}

/// Which relations does he actually have anything to say about, for a subject?
///
/// This is what makes him able to WONDER rather than guess. Before asking
/// "what does Sadeq like", he can see whether `prefers` even exists for Sadeq —
/// so an empty answer is knowledge ("I've never learned that") instead of a
/// silence he has to interpret.
Map<String, int> relationsFor(List<EdgeRow> edges, String subject) {
  final counts = <String, int>{};
  for (final e in edges) {
    if (!e.isMeaningful || !e.isActive) continue;
    if (!_matches(e.fromLabel, subject) && !_matches(e.toLabel, subject)) {
      continue;
    }
    counts[e.type] = (counts[e.type] ?? 0) + 1;
  }
  return counts;
}

/// How much of the graph is meaningless — the word-cloud ratio.
///
/// `related`/`mentioned` with no label is co-occurrence, not memory. On a graph
/// where 271 nodes lit up on any input because every edge said "relates to",
/// this number is the diagnosis in one integer.
({int meaningful, int total}) meaningfulness(List<EdgeRow> edges) =>
    (meaningful: edges.where((e) => e.isMeaningful).length, total: edges.length);
