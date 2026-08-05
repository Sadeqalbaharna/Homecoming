// memory_classifier.dart — the deterministic half of legacy memory triage.
//
// ── Why this file exists ────────────────────────────────────────────────────
//
// Every memory written before scoping existed parses as `legacyUnscoped` and is
// visible only to trusted desktop/mobile. That fails closed, which is correct —
// and it also means Messenger Kai is working off almost no history. Something
// has to classify those rows so the personal ones can travel.
//
// The obvious move is to hand the whole pile to a model. That is exactly the
// move this file exists to avoid making unsupervised, for the same reason
// gumroad_guard.dart is not a prompt: a classifier that can be talked into
// widening visibility is the one thing this pass must not be. "Grade honestly"
// produced 7/7 self-completes elsewhere in this codebase. Deterministic code
// cannot be talked out of a score.
//
// ── The asymmetry that shapes everything here ───────────────────────────────
//
// NARROWING is safe. Marking a memory technical hides it from friend surfaces;
// if that's wrong, Kai is slightly thinner on Messenger and Sadeq can promote it
// later. Nothing leaked.
//
// WIDENING is not. Marking a memory personal exposes it to every friend
// surface, and a memory once recalled in the wrong room cannot be un-recalled.
//
// So this file only ever narrows. It answers exactly one question — "is this
// unmistakably technical?" — and abstains on everything else. It never returns
// "personal", because deterministic personal-detection would be a guess wearing
// a confidence score, and guesses that widen are the failure mode.
//
// Ambiguous rows stay legacyUnscoped. They can go to a model pass or to Sadeq,
// but they do NOT get promoted by this file. Abstention is free and expected;
// a classifier with no cheap abstain option guesses.
//
// ── Strong vs weak signals ──────────────────────────────────────────────────
//
// Topic words alone are not enough. "I'm proud of what we built" is a memory
// ABOUT technical work whose content is entirely personal, and hiding it from
// Messenger would delete precisely the kind of thing Kai should carry. So a
// single technical NOUN never decides anything.
//
// Strong signals are structural — code fences, file paths, stack traces, shell
// command forms. Prose about feelings does not accidentally contain `lib/x.dart`
// or `#0 `. Any one of those is decisive.
//
// Weak signals are vocabulary. Two or more are needed, on the theory that one
// stray "database" is someone talking about their week and three of them is a
// work log.
//
// Pure: zero imports.
library;

enum MemoryPrefilterVerdict {
  /// Unmistakably technical. Safe to narrow to privateCore without a human,
  /// because narrowing cannot leak.
  technical,

  /// Not decidable from structure. Stays legacyUnscoped. This is the DEFAULT
  /// and is not a failure — it is the file declining to guess.
  unclear,
}

class MemoryPrefilterDecision {
  final MemoryPrefilterVerdict verdict;

  /// Why, in words that can go straight into a dry-run report. A triage pass
  /// nobody can audit is a pass nobody should trust.
  final String reason;

  /// The specific signals that fired, so a reviewer can check the call rather
  /// than take it.
  final List<String> signals;

  const MemoryPrefilterDecision(this.verdict, this.reason, this.signals);

  bool get isTechnical => verdict == MemoryPrefilterVerdict.technical;
}

/// Structural markers. Any ONE of these decides the row.
///
/// Deliberately excluded: bare `at ` (matches "at the beach"), bare `error`
/// (matches "that was my error"), and `{`/`}` alone (matches nothing useful but
/// would match emoji-adjacent punctuation in odd exports).
const List<List<String>> _strongPatterns = [
  ['```', 'code fence'],
  ['#0 ', 'stack frame'],
  ['Traceback', 'python traceback'],
  ['StackTrace', 'dart stack trace'],
  ['Exception:', 'thrown exception'],
  ['=> ', 'arrow function or dart expression body'],
  ['();', 'call statement'],
  ['});', 'closure or block terminator'],
  ['null pointer', 'null pointer failure'],
  ['merge conflict', 'version control conflict'],
];

/// Command forms. A memory containing `git rebase` is a work log regardless of
/// what else is in it.
///
/// These are COMMAND+SUBCOMMAND pairs, not bare prefixes, and that is
/// load-bearing. Memories are stored as "Sadeq said: …\nI said: …", so a
/// command never sits at the start of the text and never at the start of a
/// line — anchoring to line starts missed all of them. But matching the bare
/// tool name anywhere would be worse: `pub `, `dart ` and `flutter ` are
/// ordinary English words. "we went to the pub", "my heart flutters", "a dart
/// board" would all have been filed as engineering.
///
/// The pair is what disambiguates. "the pub" is a Friday; "pub get" is a build.
const List<String> _commandPairs = [
  'git commit',
  'git push',
  'git pull',
  'git rebase',
  'git merge',
  'git checkout',
  'git clone',
  'git status',
  'git branch',
  'git stash',
  'git reset',
  'git diff',
  'flutter run',
  'flutter test',
  'flutter build',
  'flutter analyze',
  'flutter clean',
  'flutter doctor',
  'dart run',
  'dart test',
  'dart format',
  'dart analyze',
  'pub get',
  'pub upgrade',
  'npm install',
  'npm run',
  'npm start',
  'pip install',
  'docker run',
  'docker build',
];

/// Tool names with no ordinary-English meaning. Safe on their own.
const List<String> _unambiguousCommands = [
  'npx ',
  'sudo ',
  'ssh ',
  'kubectl ',
  'localhost:',
];

/// File extensions that only appear in a technical context. `.md` is included
/// because a remembered filename is a remembered file either way.
const List<String> _codeExtensions = [
  '.dart',
  '.js',
  '.ts',
  '.tsx',
  '.py',
  '.json',
  '.yaml',
  '.yml',
  '.html',
  '.css',
  '.kt',
  '.swift',
  '.java',
  '.rb',
  '.go',
  '.rs',
  '.sh',
  '.md',
  '.sql',
];

/// Vocabulary. Two or more required — see the header on why one is not enough.
///
/// Words with common personal meanings are omitted on purpose: `commit`
/// (commitment), `token` (gesture), `thread` (conversation), `build` (physique,
/// building things together in VR), `test` (medical), `crash` (sleep, cars).
const List<String> _weakVocabulary = [
  'api',
  'endpoint',
  'database',
  'firebase',
  'schema',
  'refactor',
  'compile',
  'deploy',
  'regex',
  'async',
  'await',
  'widget',
  'repository',
  'parameter',
  'boolean',
  'backend',
  'frontend',
  'localhost',
  'runtime',
  'stacktrace',
  'debugger',
  'breakpoint',
  'changelog',
  'pull request',
  'codebase',
];

/// How many weak signals make a work log.
const int _kWeakThreshold = 2;

bool _looksLikeFilePath(String lower) {
  for (final ext in _codeExtensions) {
    final at = lower.indexOf(ext);
    if (at <= 0) continue;
    // Require a path-ish or identifier-ish character immediately before the
    // extension so "see you in the a.m." style text can't trip `.md`.
    final before = lower[at - 1];
    final isWordChar = RegExp(r'[a-z0-9_/\\-]').hasMatch(before);
    if (isWordChar) return true;
  }
  return false;
}

/// Is this memory unmistakably technical?
///
/// Returns [MemoryPrefilterVerdict.unclear] for anything it cannot prove, which
/// is most rows. That is the intended outcome — this pass exists to remove the
/// obvious from the pile cheaply, not to classify everything.
MemoryPrefilterDecision classifyLegacyMemory(String summary) {
  final text = summary.trim();
  if (text.isEmpty) {
    return const MemoryPrefilterDecision(
      MemoryPrefilterVerdict.unclear,
      'empty summary — nothing to judge',
      [],
    );
  }

  final lower = text.toLowerCase();
  final signals = <String>[];

  for (final pattern in _strongPatterns) {
    if (text.contains(pattern[0])) {
      return MemoryPrefilterDecision(
        MemoryPrefilterVerdict.technical,
        'structural marker: ${pattern[1]}',
        ['strong:${pattern[1]}'],
      );
    }
  }

  for (final pair in _commandPairs) {
    if (lower.contains(pair)) {
      return MemoryPrefilterDecision(
        MemoryPrefilterVerdict.technical,
        'shell command: $pair',
        ['strong:command:$pair'],
      );
    }
  }

  for (final command in _unambiguousCommands) {
    if (lower.contains(command)) {
      return MemoryPrefilterDecision(
        MemoryPrefilterVerdict.technical,
        'shell command: ${command.trim()}',
        ['strong:command:${command.trim()}'],
      );
    }
  }

  if (_looksLikeFilePath(lower)) {
    return const MemoryPrefilterDecision(
      MemoryPrefilterVerdict.technical,
      'file path with a code extension',
      ['strong:filepath'],
    );
  }

  for (final word in _weakVocabulary) {
    if (lower.contains(word)) signals.add('weak:$word');
  }

  if (signals.length >= _kWeakThreshold) {
    return MemoryPrefilterDecision(
      MemoryPrefilterVerdict.technical,
      '${signals.length} technical vocabulary signals',
      signals,
    );
  }

  return MemoryPrefilterDecision(
    MemoryPrefilterVerdict.unclear,
    signals.isEmpty
        ? 'no technical markers — not decidable here'
        : 'only ${signals.length} weak signal(s); below the threshold to narrow',
    signals,
  );
}
