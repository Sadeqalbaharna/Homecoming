// query_terms.dart — what to ask his memory about. Pure, zero imports.
//
// ── The bug this replaces ────────────────────────────────────────────────────
//
// ai_service.dart, before tonight:
//
//     if (memoryResult != null && memoryResult.results.isNotEmpty) {
//       memoriesUsed = memoryResult.results.where((r) => r.similarity > 0.28)...
//       if (memoriesUsed.isNotEmpty) {                          // <-- GATE
//         final retrievedWords = memoriesUsed
//             .expand((s) => s.toLowerCase().split(RegExp(r'\W+')))
//             .where((w) => w.length > 3)
//             .toSet().toList();                                // <-- SEED
//         _brain.reinforceNodes(personaId, retrievedWords);
//         final spreadBlock = await _brain.spreadActivation(
//             personaId, retrievedWords, currentMood: mood);
//
// Two defects, one line apart.
//
// **(a) The graph was downstream of the chat log.** `spreadActivation` — the
// only path by which anything Kai KNOWS reaches his prompt — could not run
// unless a cosine search over transcript fragments cleared 0.28 first. From the
// 2026-07-16 traces:
//
//     "chat is still not starting…"          0.46   graph consulted
//     "so, what do you think we should do?"  0.41   graph consulted
//     "sure go ahead"                        —      NOT consulted
//     "what are mojibake?"                   0.21   NOT consulted
//     "why does it keep happening?"          0.25   NOT consulted
//
// Three of five turns, his knowledge was never reached. Not empty — unasked.
// He answered "why does it keep happening?" from theory while the answer sat in
// a graph nobody queried.
//
// **(b) It was never a query.** `retrievedWords` is every word over three
// characters from five unrelated chat summaries — a hundred-odd tokens of "said",
// "that", "okay", "worked". That is why the log reads `reinforced 271 retrieved
// nodes`, and roughly 271 EVERY time. It wasn't retrieving what mattered; it was
// activating everything that shared a word with a random fragment. And since
// reinforceNodes bumps importance for all 271, the importance signal was being
// destroyed on every single turn. If everything is important, nothing is.
//
// ── What this does instead ───────────────────────────────────────────────────
//
// Seed from what SADEQ ACTUALLY SAID. A small, capped, stopword-free set of
// terms drawn from the message itself. Then the graph gets asked a question
// instead of being splashed with noise, and it can answer even when no
// transcript matches — which is exactly the level-5 gate.
//
// Zero imports on purpose: see lib/logic/salience.dart. A decision that cannot
// be executed cannot be trusted, and this one runs on every turn.
library;

/// Words that carry no retrieval signal. Deliberately includes the
/// conversational filler Sadeq actually uses — "okay", "yeah", "lets" — because
/// those were a real chunk of the 271.
const kStopwords = <String>{
  // grammar
  'this', 'that', 'these', 'those', 'there', 'their', 'them', 'they', 'then',
  'than', 'with', 'without', 'from', 'into', 'onto', 'about', 'above', 'after',
  'again', 'against', 'because', 'been', 'before', 'being', 'below', 'between',
  'both', 'cannot', 'could', 'does', 'doing', 'down', 'during', 'each', 'even',
  'ever', 'every', 'have', 'having', 'here', 'itself', 'just', 'like', 'more',
  'most', 'much', 'must', 'only', 'other', 'over', 'same', 'should', 'some',
  'such', 'through', 'under', 'until', 'very', 'were', 'what', 'when', 'where',
  'which', 'while', 'will', 'would', 'your', 'yours', 'ours', 'mine',
  // conversational filler — the stuff that matched everything.
  //
  // 'ahead' is in this list because a test caught it. "sure go ahead" yielded
  // {ahead}, which would have seeded spreading activation with a preposition and
  // lit up every node containing it — the 271-node problem in miniature, shipped
  // by the person who wrote the comment above about the 271-node problem.
  // Directional and quantity fillers all belong here for the same reason.
  'ahead', 'alright', 'anyway', 'anything', 'something', 'nothing', 'everything',
  'thing', 'things', 'stuff', 'kinda', 'sorta', 'quite', 'rather', 'pretty',
  'okay', 'yeah', 'yep', 'nope', 'nah', 'sure', 'thanks', 'please', 'lets',
  'gonna', 'wanna', 'really', 'actually', 'maybe', 'still', 'also', 'well',
  'good', 'nice', 'cool', 'great', 'right', 'sorry', 'know', 'think', 'want',
  'need', 'make', 'made', 'take', 'come', 'came', 'give', 'gave', 'went',
  'goes', 'going', 'done', 'doesnt', 'dont', 'didnt', 'cant', 'wont', 'isnt',
  'arent', 'wasnt', 'werent', 'thats', 'whats', 'hows', 'theres', 'heres',
  // transcript scaffolding — these WERE in the seed set, every turn
  'said', 'says', 'saying', 'told', 'asked', 'reply', 'replied',
};

/// Extract the terms worth asking his memory about.
///
/// [max] is a cap, not a target. It exists because the thing this replaces had
/// no cap and lit up 271 nodes a turn. A question with forty terms in it is not
/// a question.
Set<String> queryTerms(String message, {int max = 12}) {
  final words = message
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9_]+'))
      .where((w) => w.length > 3)
      .where((w) => !kStopwords.contains(w))
      // A bare number is never an entity. A version or an identifier (gpt5,
      // 4o) survives because it isn't bare.
      .where((w) => !RegExp(r'^[0-9]+$').hasMatch(w))
      .toList();

  // Preserve order of first appearance, then cap. Earlier words in a sentence
  // are usually the subject; taking the first N beats taking a random N.
  final seen = <String>{};
  final out = <String>{};
  for (final w in words) {
    if (seen.add(w)) {
      out.add(w);
      if (out.length >= max) break;
    }
  }
  return out;
}

/// True when a message has nothing worth asking the graph about.
///
/// Note the difference from "is this trivial": "why does it keep happening?"
/// yields {happening} — thin, but a real question about a real thing, and the
/// graph should get asked. Only an empty term set means don't bother.
bool worthAsking(String message) => queryTerms(message).isNotEmpty;
