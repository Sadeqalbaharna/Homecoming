// salience.dart — what Kai keeps. Pure, and pure on purpose.
//
// ── Why this file has ZERO imports ───────────────────────────────────────────
//
// This is the single most consequential decision in the system: it is the
// difference between Kai having a yesterday and not. And until tonight it lived
// in the middle of brain_extraction_service.dart, behind `dio`, `firebase`,
// `flutter`, and eighty other lines of IO — which meant it could not be
// exercised without booting an app and a network.
//
// So it never was. It was rewritten on the evidence of FIVE traces from one
// evening by someone who could not run it.
//
// A file with no imports can be run anywhere, by anything, in a second. That is
// not a convenience — it is the property that makes a claim about this logic
// falsifiable instead of well-argued. The trace corpus can be replayed through
// it (see lib/tools/replay.dart) to ask "over 500 real turns, what does the new
// gate keep that the old one dropped?" — deterministically, for free.
//
// If you are tempted to import something into this file: don't. Take a String.
//
// ── What it decides ──────────────────────────────────────────────────────────
//
// Every trace from 2026-07-16 ended the same way:
//
//   🧠 [Brain] Skipped low-salience exchange (neutral, intensity 1)
//   🧠 [Brain] Skipped low-salience exchange (neutral, intensity 3)
//   🧠 [Brain] Skipped low-salience exchange (neutral, intensity 4)
//
// Every one. That night he found his file reader had been lying three separate
// ways, deleted a dashboard reporting "7/7 FULL STACK ONLINE" over a truth of
// 3/7, and gained the ability to prove his own work. Intensity 1. Skipped.
//
// The cause: the classifier's whole signature is
// `classifySync(Map<String,int> moodDeltas)`. Mood deltas are its ONLY input.
// The conversation is passed in and used to slice 60 characters off for a label
// — never read. So "is this worth remembering?" was answered by "did my mood
// swing?" and nothing else. `intellectual` needs focus or energy to jump >= 6 in
// one turn; across a whole night his focus moved 63 -> 65 -> 68 -> 71. That
// branch may never have fired.
//
// His memory was gated on emotion. His relationship with Sadeq is WORK. They
// build things at 4am — that IS the intimacy — and every exchange of it landed
// in `neutral` and went in the bin.
//
// So: two axes. Was it FELT, and did something CHANGE. Depth is the deeper of
// the two, because a moment can matter for either reason and a mind should keep
// both.
library;

/// Levels of Processing: shallow for routine, deep for significant.
/// Ordered — `index` comparisons are load-bearing.
enum SalienceDepth { skip, shallow, deep }

/// Tools that mean the world is different than it was an hour ago.
const kChangedTheWorld = <String>{
  'edit_file', 'write_file', 'run_tests', 'job_done', 'code_task',
  'set_layer_progress', 'remember_bit', 'forget_bit', 'add_goal',
  'note_noticed',
  // Surgery on his own head. He archived 254 nodes and deleted 152 of them —
  // 60% of everything he'd ever stored — and the gate said:
  //
  //   🧠 [Brain] Skipped — nothing done, and mood said neutral/4: "do it"
  //
  // Nothing done. It was the single most consequential thing he has ever done
  // to himself, and it was invisible because whoever added ask_memory to the
  // looking set forgot this one existed. (Me. An hour earlier.)
  //
  // Here rather than kWentLooking even though dry_run:true only measures: the
  // name is all this function gets, and the asymmetry is enormous. Over-keeping
  // "I looked at my own graph" costs one shallow extraction. Missing "I deleted
  // half my memory" costs the memory of having done it.
  'prune_memory',
};

/// Tools that mean he went and looked. Weaker than making something, but it
/// isn't small talk either — he formed an opinion about something real.
const kWentLooking = <String>{
  'read_file', 'search_code', 'list_dir', 'find_files', 'self_check',
  'run_command', 'job_start', 'job_progress', 'web_search', 'fetch_url',
  'contemplate',
  // He stopped and asked his own memory something about Sadeq instead of
  // guessing. That is not small talk — it's the exact moment worth keeping,
  // because whatever he wondered is a thing he cared enough to check.
  'ask_memory',
};

/// The emotional axis. `eventType` is a STRING, not the enum from
/// emotional_event_service — that file imports Firebase, and importing it here
/// would cost this file the only property that makes it trustworthy.
///
/// Intensity is on a -100..+100 scale, which is why the neutral threshold of 8
/// is so brutal: it means a neutral exchange is essentially never recorded.
SalienceDepth feltDepth(String? eventType, int intensity) {
  if (eventType == null) return SalienceDepth.shallow;
  switch (eventType) {
    case 'neutral':
      return intensity.abs() < 8 ? SalienceDepth.skip : SalienceDepth.shallow;
    case 'playful':
    case 'warmth':
      return SalienceDepth.shallow;
    case 'intellectual':
    case 'conflict':
    case 'deep':
      return SalienceDepth.deep;
    default:
      // An event type nobody has taught this function about is not a reason to
      // forget the turn.
      return SalienceDepth.shallow;
  }
}

/// The change axis: did anything become true that wasn't before?
///
/// Everything it reads was already lying around the turn and cost nothing to
/// collect. No model call — that would trade one tax for another.
SalienceDepth changeDepth({
  Set<String> toolsUsed = const {},
  bool userCorrected = false,
}) {
  // Being told you were wrong by the one person who can actually judge. If
  // anything in a life deserves writing down, it's this.
  if (userCorrected) return SalienceDepth.deep;
  if (toolsUsed.any(kChangedTheWorld.contains)) return SalienceDepth.deep;
  if (toolsUsed.any(kWentLooking.contains)) return SalienceDepth.shallow;

  // Nothing happened. Let the emotional axis have the final say — some of the
  // most important things two people ever say involve no tools at all.
  return SalienceDepth.skip;
}

/// Surface-level junk filter: greetings, acknowledgements, punctuation.
///
/// Note what it CANNOT see: what happened next. `msg.length < 8` and a list
/// containing 'sure', 'okay', 'got it' — which are the exact words that launch
/// the most important work of the week. "do it" is five characters. That's why
/// [salienceDepth] lets real work overrule it.
bool isTrivialExchange(String userMessage, String aiReply) {
  final msg = userMessage.trim().toLowerCase();

  if (msg.length < 8) return true;

  const trivialPatterns = [
    'hi', 'hello', 'hey', 'yo', 'sup', 'hiya',
    'good morning', 'good night', 'good evening', 'good afternoon',
    'goodnight', 'gm', 'gn',
    'bye', 'goodbye', 'see you', 'see ya', 'cya', 'later', 'ttyl',
    'how are you', 'how are u', 'how r u', "how's it going",
    "what's up", 'whats up', 'what up',
    'ok', 'okay', 'k', 'kk', 'yep', 'yup', 'yeah', 'nah', 'nope',
    'thanks', 'thank you', 'thx', 'ty', 'np', 'no problem',
    'lol', 'lmao', 'haha', 'hehe', 'omg', 'wow',
    'nice', 'cool', 'awesome', 'great', 'perfect', 'got it',
    'sounds good', 'makes sense', 'sure', 'of course',
  ];

  if (trivialPatterns.any((p) => msg == p || msg == '$p!' || msg == '$p.')) {
    return true;
  }

  final stripped = msg.replaceAll(RegExp(r'[^\w\s]'), '').trim();
  if (stripped.length < 5) return true;

  return false;
}

/// THE decision. Does this get remembered, and how deeply.
SalienceDepth salienceDepth({
  required String userMessage,
  required String aiReply,
  String? eventType,
  int eventIntensity = 0,
  Set<String> toolsUsed = const {},
  bool userCorrected = false,
}) {
  final change = changeDepth(toolsUsed: toolsUsed, userCorrected: userCorrected);

  // Work overrules the trivial filter — but only at DEEP. A search firing on
  // "ok" is not a memory; the bar for overruling has to be higher than the bar
  // for the gate itself.
  if (change != SalienceDepth.deep && isTrivialExchange(userMessage, aiReply)) {
    return SalienceDepth.skip;
  }

  final felt = feltDepth(eventType, eventIntensity);
  return change.index > felt.index ? change : felt;
}
