// chatgpt_export — turning a year of ChatGPT into turns Kai's extractor can read.
//
// ── What this parses ─────────────────────────────────────────────────────────
//
// ChatGPT's data export is a `conversations.json`: a JSON array of conversations,
// each a `mapping` of message nodes in a TREE (because you can edit/branch). A
// node looks like:
//
//   "<node-id>": {
//     "message": {
//       "author":  {"role": "user"|"assistant"|"system"|"tool"},
//       "content": {"content_type": "text", "parts": ["..."]},
//       "create_time": 1699999999.123
//     },
//     "parent": "...", "children": ["..."]
//   }
//
// The tree matters: an edited message leaves the old branch in the mapping. We
// take the main line by create_time order and keep only real user/assistant
// text — the honest transcript, not every dead branch.
//
// ── Why this is its own pure file ────────────────────────────────────────────
//
// Feeding a year of history into the graph is the highest-leverage thing left,
// and the ONE way to ruin it is the extractor — which is why the export must go
// through brain_extraction_service.extractAndMerge (stranger test, typed edges,
// confidence), NOT the old chatgpt_memory_import_service that stamps 'related'
// on every edge and rebuilds the word cloud at scale.
//
// This file does none of that. It only turns the export into ordered turns. It
// is pure, zero-imports, and provable in a second — so the parsing (the fiddly,
// format-dependent part) is settled before a single token is spent extracting.
library;

/// One user/assistant exchange, in order.
class ExportTurn {
  final String role; // 'user' | 'assistant'
  final String text;
  final double createTime; // unix seconds; 0 if absent
  const ExportTurn(this.role, this.text, this.createTime);
}

/// One conversation, flattened to its main line.
class ExportConversation {
  final String title;
  final List<ExportTurn> turns;
  const ExportConversation(this.title, this.turns);

  /// (user, assistant) pairs — what extractAndMerge consumes. A user turn with
  /// no assistant reply after it (or vice-versa) is dropped: an extractor needs
  /// both halves of an exchange to type a claim.
  List<(String, String)> get pairs {
    final out = <(String, String)>[];
    String? pendingUser;
    for (final t in turns) {
      if (t.role == 'user') {
        pendingUser = t.text;
      } else if (t.role == 'assistant' && pendingUser != null) {
        out.add((pendingUser, t.text));
        pendingUser = null;
      }
    }
    return out;
  }
}

String _textOf(Object? content) {
  // content: {content_type: "text", parts: ["...", ...]}. Non-text parts
  // (images, code interpreter outputs) come as maps or empties — skip them.
  if (content is! Map) return '';
  final ct = content['content_type'];
  if (ct != null && ct != 'text' && ct != 'multimodal_text') return '';
  final parts = content['parts'];
  if (parts is! List) return '';
  final buf = StringBuffer();
  for (final p in parts) {
    if (p is String && p.trim().isNotEmpty) {
      if (buf.isNotEmpty) buf.write('\n');
      buf.write(p);
    }
  }
  return buf.toString().trim();
}

/// Parse the decoded `conversations.json` (a List) into conversations. Anything
/// malformed is skipped, never thrown — a year's export is not going to be
/// pristine, and one bad conversation must not lose the other 499.
List<ExportConversation> parseExport(Object? decoded) {
  if (decoded is! List) return const [];
  final out = <ExportConversation>[];

  for (final conv in decoded) {
    if (conv is! Map) continue;
    final title = (conv['title'] as String?)?.trim() ?? '(untitled)';
    final mapping = conv['mapping'];
    if (mapping is! Map) continue;

    final turns = <ExportTurn>[];
    mapping.forEach((_, node) {
      if (node is! Map) return;
      final msg = node['message'];
      if (msg is! Map) return;
      final author = msg['author'];
      final role = author is Map ? author['role'] : null;
      if (role != 'user' && role != 'assistant') return; // drop system/tool
      final text = _textOf(msg['content']);
      if (text.isEmpty) return;
      final ct = msg['create_time'];
      final t = ct is num ? ct.toDouble() : 0.0;
      turns.add(ExportTurn(role as String, text, t));
    });

    if (turns.isEmpty) continue;
    // Main line by time. Nodes with no create_time (0) sort first, which keeps
    // a rare timeless system-adjacent turn from jumping to the end.
    turns.sort((a, b) => a.createTime.compareTo(b.createTime));
    out.add(ExportConversation(title, turns));
  }

  return out;
}

/// Flat count of usable exchanges across the whole export — for the pre-flight
/// ("this will extract ~N pairs; a dry run of 20 first").
int totalPairs(List<ExportConversation> convs) =>
    convs.fold(0, (n, c) => n + c.pairs.length);

// ── The free token-saver: is this conversation ABOUT the person? ─────────────
//
// Most of a year of ChatGPT is impersonal — "fix this function", "write an
// email", "translate this". Extracting from those spends money to learn nothing
// durable about Sadeq. This scores a conversation for PERSONAL SIGNAL, entirely
// locally, so the impersonal ~80% never reaches the API. It's a heuristic, not a
// judge — it's allowed to be roughly right, because the dry run and the stranger
// test are the real quality gates. Its only job is to stop obvious task-chatter
// from costing tokens.
//
// Signal UP: first-person disclosure ("I", "my", "we"), feeling/wanting verbs,
// life nouns (family, work, home). Signal DOWN: the fingerprints of a task —
// code fences, "write me a", "fix", "translate", "debug".

const _firstPerson = <String>{'i', 'im', "i'm", 'my', 'me', 'mine', 'we', 'our', 'us'};
const _discloseVerbs = <String>{
  'feel', 'felt', 'love', 'hate', 'want', 'wanted', 'wish', 'afraid', 'scared',
  'proud', 'always', 'never', 'believe', 'think', 'remember', 'miss', 'hope',
  'dream', 'worried', 'happy', 'sad', 'angry', 'tired', 'grew', 'grew up',
};
const _lifeNouns = <String>{
  'family', 'wife', 'husband', 'kid', 'kids', 'son', 'daughter', 'mom', 'dad',
  'mother', 'father', 'brother', 'sister', 'friend', 'home', 'work', 'job',
  'life', 'name', 'city', 'country', 'health', 'god', 'faith',
};
// Fingerprints of a task, not a confession.
const _taskMarkers = <String>{
  'fix', 'debug', 'error', 'function', 'code', 'compile', 'translate', 'refactor',
  'rewrite this', 'write me', 'write a', 'generate', 'summarize', 'summarise',
  'convert', 'regex', 'sql', 'api', 'endpoint', 'stack trace', 'null',
};

List<String> _words(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
    .split(RegExp(r'\s+'))
    .where((w) => w.isNotEmpty)
    .toList();

/// 0..1 — how much this conversation looks like it's about the person, not a
/// task. Reads only the USER turns: what ChatGPT said back doesn't reveal Sadeq.
double personalSignal(ExportConversation conv) {
  final userText = conv.turns.where((t) => t.role == 'user').map((t) => t.text);
  final joined = userText.join(' ');
  if (joined.trim().isEmpty) return 0;

  final ws = _words(joined);
  if (ws.length < 8) return 0; // too short to disclose anything

  var fp = 0, disclose = 0, life = 0, task = 0;
  for (final w in ws) {
    if (_firstPerson.contains(w)) fp++;
    if (_discloseVerbs.contains(w)) disclose++;
    if (_lifeNouns.contains(w)) life++;
    if (_taskMarkers.contains(w)) task++;
  }
  // Code fences are the loudest task tell.
  final codey = RegExp('```').allMatches(joined).length;

  final n = ws.length.toDouble();
  // Density-based so a long task convo can't out-vote a short heartfelt one.
  final up = (fp / n) * 2.0 + (disclose / n) * 6.0 + (life / n) * 6.0;
  final down = (task / n) * 5.0 + codey * 0.15;

  final score = (up - down).clamp(0.0, 1.0);
  return score;
}

/// Keep only conversations worth spending a token on. [threshold] is
/// deliberately low — the stranger test and dry run are the real filters; this
/// just sheds the obvious task-chatter. Sorted strongest-first so a dry run
/// samples the most personal conversations, not a random slice.
List<ExportConversation> filterPersonal(
  List<ExportConversation> convs, {
  double threshold = 0.05,
}) {
  final scored = [
    for (final c in convs)
      if (personalSignal(c) >= threshold) (personalSignal(c), c),
  ]..sort((a, b) => b.$1.compareTo(a.$1));
  return [for (final s in scored) s.$2];
}
