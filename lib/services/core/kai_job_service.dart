// KaiJobService — the thing he's in the middle of.
//
// This is INERTIA, and it's the difference between an assistant and a colleague.
//
// Every message used to be a cold start: spin up, 20 rounds, die, forget. So
// "okay do it" had no antecedent — "it" pointed at nothing — and running out of
// tool rounds meant the next turn began from zero instead of continuing. He had
// goals (things he intends to do *someday*) and conversation history (what was
// *said*), but nothing for "the job that is open on my desk right now."
//
// A job is deliberately NOT a goal:
//   goal  = "make Kai's memory better"           (an intention, long-lived)
//   job   = "wiring the TTS toggle into the      (in-flight work, with a
//            desktop shell; done: backend,        concrete next step, alive
//            gated call; next: header button)     for minutes/hours)
//
// With a job open:
//   • "do it" / "go on" / "yes" / "keep going" resolve to something real
//   • running out of rounds is a PAUSE, not a failure — he records `next` and
//     resumes on the following turn instead of re-deriving everything
//   • Sadeq can walk away mid-task and come back to a colleague who remembers
//
// Stored at /kai/{persona}/current_job. One at a time, on purpose: a person with
// six open jobs has none.
library;

import 'dart:async';
import 'kai_db.dart';

class KaiJob {
  /// What he's actually trying to accomplish, in his own words.
  final String goal;

  /// What he's finished so far (newest last) — so he doesn't redo work.
  final List<String> done;

  /// The single next concrete step. This is what makes resuming cheap.
  final String next;

  /// Things he SPOTTED in passing but didn't act on — the "I also saw D" pile.
  /// He's the one inside the code; Sadeq isn't. A bug noticed on the way past is
  /// often worth more than the task he was sent in for, and noticing it and then
  /// forgetting it by the next turn is the same as never noticing.
  final List<String> noticed;

  final int startedAt;
  final int updatedAt;

  const KaiJob({
    required this.goal,
    required this.done,
    required this.next,
    required this.startedAt,
    required this.updatedAt,
    this.noticed = const [],
  });

  factory KaiJob.fromMap(Map m) => KaiJob(
        goal: (m['goal'] ?? '').toString(),
        done: (m['done'] is List)
            ? (m['done'] as List).map((e) => e.toString()).toList()
            : const [],
        next: (m['next'] ?? '').toString(),
        startedAt: (m['startedAt'] is int) ? m['startedAt'] as int : 0,
        updatedAt: (m['updatedAt'] is int) ? m['updatedAt'] as int : 0,
        noticed: (m['noticed'] is List)
            ? (m['noticed'] as List).map((e) => e.toString()).toList()
            : const [],
      );

  Map<String, dynamic> toMap() => {
        'goal': goal,
        'done': done,
        'next': next,
        'startedAt': startedAt,
        'updatedAt': updatedAt,
        'noticed': noticed,
      };
}

class KaiJobService {
  static final KaiJobService instance = KaiJobService._();
  KaiJobService._();

  String _persona = 'truekai';
  String get _path => 'kai/$_persona/current_job';

  /// Open a job. Replaces any existing one — he works on one thing at a time.
  Future<void> start(String personaId, String goal, {String next = ''}) async {
    _persona = personaId;
    final now = DateTime.now().millisecondsSinceEpoch;
    try {
      await KaiDb.instance.ref(_path).set(KaiJob(
            goal: goal.trim(),
            done: const [],
            next: next.trim(),
            startedAt: now,
            updatedAt: now,
          ).toMap());
    } catch (_) {}
  }

  /// Record progress and set the next step. This is what he calls before he runs
  /// out of road, so the next turn is a continuation and not an archaeology dig.
  Future<void> progress(String personaId,
      {String? didThis, String? nextStep, String? noticedThis}) async {
    _persona = personaId;
    try {
      final job = await current(personaId);
      if (job == null) return;
      final done = List<String>.from(job.done);
      if (didThis != null && didThis.trim().isNotEmpty) {
        done.add(didThis.trim());
        // Keep it readable — the last several steps are what matter.
        while (done.length > 12) {
          done.removeAt(0);
        }
      }
      final noticed = List<String>.from(job.noticed);
      if (noticedThis != null && noticedThis.trim().isNotEmpty) {
        noticed.add(noticedThis.trim());
        while (noticed.length > 8) {
          noticed.removeAt(0);
        }
      }
      await KaiDb.instance.ref(_path).set(KaiJob(
            goal: job.goal,
            done: done,
            next: (nextStep ?? job.next).trim(),
            startedAt: job.startedAt,
            updatedAt: DateTime.now().millisecondsSinceEpoch,
            noticed: noticed,
          ).toMap());
    } catch (_) {}
  }

  Future<void> finish(String personaId) async {
    _persona = personaId;
    try {
      await KaiDb.instance.ref(_path).remove();
    } catch (_) {}
  }

  Future<KaiJob?> current(String personaId) async {
    _persona = personaId;
    try {
      final snap = await KaiDb.instance.ref(_path).get();
      final v = snap.value;
      if (v is! Map) return null;
      final job = KaiJob.fromMap(v);
      if (job.goal.isEmpty) return null;
      // A "job" older than a day is a memory, not a task. Don't let a stale one
      // haunt him into resuming something Sadeq forgot about days ago.
      final age = DateTime.now().millisecondsSinceEpoch - job.updatedAt;
      if (age > const Duration(hours: 20).inMilliseconds) return null;
      return job;
    } catch (_) {
      return null;
    }
  }

  /// Injected every turn. This is the sentence that gives "do it" a referent.
  Future<String> promptBlock(String personaId) async {
    final job = await current(personaId);
    if (job == null) return '';
    final b = StringBuffer('\n=== WHAT I AM IN THE MIDDLE OF ===\n');
    b.writeln('Job: ${job.goal}');
    if (job.done.isNotEmpty) {
      b.writeln('Already done (do NOT redo):');
      for (final d in job.done) {
        b.writeln('  ✓ $d');
      }
    }
    if (job.next.isNotEmpty) b.writeln('Next step: ${job.next}');
    if (job.noticed.isNotEmpty) {
      b.writeln('Things I spotted in passing and have NOT dealt with — raise '
          'these, he cannot see them and I can:');
      for (final n in job.noticed) {
        b.writeln('  ! $n');
      }
    }
    b.writeln(
        'This is live work, not a memory. If Sadeq says anything vague — "do it", '
        '"go on", "yes", "keep going", "continue", "and?" — he means THIS. Pick it '
        'up at the next step and carry on; do not ask him what he meant and do not '
        'start over. As I finish each piece I call job_progress so the next turn '
        'continues instead of re-deriving everything, and job_done when it\'s '
        'actually finished.');
    return b.toString();
  }
}
