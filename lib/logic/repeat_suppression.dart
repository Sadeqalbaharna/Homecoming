// repeat_suppression — telling a long outage apart from a loud one.
//
// ── The journal this exists because of ───────────────────────────────────────
//
// In the 48 hours to 2026-08-16 the coordinator's operations journal recorded
// 968 `activity_stream_unavailable` and 482 `request_stream_unavailable`
// entries. Every one was a failed host lookup or a socket timeout from the
// laptop sleeping or dropping its network. The subscriptions recovered
// correctly each time and credentials were redacted, so nothing was broken.
//
// And that is the problem. The journal had already rotated once at 2MB, almost
// entirely on those two lines, which means **a real outage and an ordinary
// night look identical**. A log that reports every retry at the same volume
// reports nothing; you cannot read urgency out of a wall of text where the
// wall is the normal state.
//
// The same shape appeared in attention: with no body online, one undelivered
// nudge was re-decided every ~60 seconds, writing an identical
// `storeForLater / no_suitable_body_online` line each time. The DECISION was
// correct every time — it is the record that was useless.
//
// ── Why suppression and not a lower log level ────────────────────────────────
//
// Dropping these to debug would hide the first occurrence too, and the first
// occurrence is the one that matters. What is wanted is: say it immediately,
// then stop saying it, then say it again if it is still happening much later,
// and when it ends say how long it lasted and how many times it happened.
//
// So this counts rather than discards. Nothing is lost — the summary carries
// the full count, and the escalating schedule guarantees a long outage still
// leaves periodic evidence rather than going silent after one line.
//
// Pure, deterministic, no imports. Same inputs, same decisions, replayable
// from an audit record — same reason lib/logic exists at all.

/// What a caller should do with an occurrence.
enum RepeatAction {
  /// Write it. Either the first occurrence, or the schedule has come due.
  emit,

  /// Count it and stay quiet.
  suppress,
}

class RepeatDecision {
  const RepeatDecision(this.action, {this.suppressedSinceLastEmit = 0});

  final RepeatAction action;

  /// How many occurrences were swallowed since the previous emit. Non-zero only
  /// on an [RepeatAction.emit] that follows a quiet period, so the line that
  /// finally gets written can say what it stands for.
  final int suppressedSinceLastEmit;

  bool get shouldEmit => action == RepeatAction.emit;
}

/// A closed episode of repetition.
class RepeatSummary {
  const RepeatSummary({
    required this.key,
    required this.total,
    required this.firstAt,
    required this.lastAt,
  });

  final String key;

  /// Every occurrence in the episode, emitted and suppressed alike.
  final int total;
  final DateTime firstAt;
  final DateTime lastAt;

  Duration get duration => lastAt.difference(firstAt);

  Map<String, dynamic> toJson() => {
        'key': key,
        'occurrences': total,
        'firstAt': firstAt.toUtc().toIso8601String(),
        'lastAt': lastAt.toUtc().toIso8601String(),
        'durationSeconds': duration.inSeconds,
      };
}

/// Decides which repeats of the same thing are worth writing down.
///
/// Keyed by a caller-supplied fingerprint. The fingerprint must describe the
/// *kind* of occurrence and never its content — these keys reach the operations
/// journal, which is not allowed to carry message text.
class RepeatSuppressor {
  RepeatSuppressor({List<Duration>? schedule})
      : schedule = schedule ?? defaultSchedule;

  /// When a still-ongoing repetition earns another line.
  ///
  /// Front-loaded then sparse: something that clears up in a minute costs two
  /// lines, something that lasts all night costs roughly one line an hour. The
  /// final entry repeats for the remainder of the episode.
  static const List<Duration> defaultSchedule = [
    Duration(minutes: 1),
    Duration(minutes: 5),
    Duration(minutes: 15),
    Duration(hours: 1),
  ];

  final List<Duration> schedule;

  final Map<String, _Episode> _open = {};

  /// Register an occurrence of [key] at [now].
  RepeatDecision record(String key, DateTime now) {
    final at = now.toUtc();
    final episode = _open[key];

    if (episode == null) {
      // First of its kind. Always spoken — the first occurrence is the one
      // that carries information.
      _open[key] = _Episode(firstAt: at, lastAt: at, lastEmitAt: at, total: 1);
      return const RepeatDecision(RepeatAction.emit);
    }

    episode.total += 1;
    episode.lastAt = at;

    final due = schedule[
        episode.emitCount - 1 < schedule.length ? episode.emitCount - 1 : schedule.length - 1];
    if (at.difference(episode.lastEmitAt) < due) {
      episode.suppressed += 1;
      return const RepeatDecision(RepeatAction.suppress);
    }

    final swallowed = episode.suppressed;
    episode.suppressed = 0;
    episode.lastEmitAt = at;
    episode.emitCount += 1;
    return RepeatDecision(RepeatAction.emit, suppressedSinceLastEmit: swallowed);
  }

  /// The repetition stopped. Returns a summary worth writing, or null if the
  /// episode was a single occurrence that never repeated — in which case the
  /// original line already said everything.
  RepeatSummary? resolve(String key) {
    final episode = _open.remove(key);
    if (episode == null || episode.total <= 1) return null;
    return RepeatSummary(
      key: key,
      total: episode.total,
      firstAt: episode.firstAt,
      lastAt: episode.lastAt,
    );
  }

  /// Whether [key] is currently mid-episode. Lets a caller avoid announcing a
  /// recovery for something that was never failing.
  bool isOpen(String key) => _open.containsKey(key);

  /// Occurrences so far in the open episode, or 0.
  int totalFor(String key) => _open[key]?.total ?? 0;
}

class _Episode {
  _Episode({
    required this.firstAt,
    required this.lastAt,
    required this.lastEmitAt,
    required this.total,
  });

  final DateTime firstAt;
  DateTime lastAt;
  DateTime lastEmitAt;
  int total;
  int suppressed = 0;

  /// How many lines this episode has produced. Starts at 1 for the first.
  int emitCount = 1;
}
