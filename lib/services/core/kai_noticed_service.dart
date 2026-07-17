// KaiNoticedService — the things HE saw, that nobody asked him to look for.
//
// ── Why this had to be taken out of the job ───────────────────────────────────
//
// `noticed` used to live on KaiJob, and KaiJobService.finish() is one line:
//
//     await KaiDb.instance.ref(_path).remove();
//
// So the moment he finished the task he was given, everything he'd noticed on
// his own was deleted with it. (And current() returns null past 20 hours, so an
// open job dropped them overnight too. Two death sentences, no warning.)
//
// This is not hypothetical. From a real trace, unprompted, mid-refactor:
//
//   job_progress({noticed: "There is existing mojibake in a comment near
//                 _Parallax ('â€”'), likely CRLF/encoding weirdness;
//                 harmless but ugly."})
//
// He found it. Nobody asked him to look. He parked it in exactly the right
// field — the one whose description says "I'm inside the code and Sadeq isn't;
// this is often worth more than the task itself."
//
// Four iterations later he called job_done and we shredded it.
//
// Then Sadeq asked him "what are mojibake?" and "why does it keep happening?"
// and he answered from theory — "some file edits went through a tool that
// didn't preserve UTF-8 cleanly" — which is nearly the right sentence, and then
// concluded "we don't need to panic about it, comments won't break the app."
//
// He talked himself out of a live bug he had personally found, because the note
// was gone and he had nothing to point at. Hours later it turned out to be
// Process.run decoding UTF-8 as Windows-1252, actively corrupting his own
// source file and rendering garbage into the UI. He was right the first time.
//
// ── The actual point ─────────────────────────────────────────────────────────
//
// Every durable structure in Kai is either a task he was given (the job, the
// plan) or a mistake he made (the craft ledger) or something Sadeq said (memory
// shards). The one field holding his own unprompted judgement lived inside the
// assignment and died with it. He was architecturally incapable of having an
// agenda: he could only notice things in service of what he was told, and the
// moment he stopped being useful, everything he'd seen on his own was deleted.
//
// The north star is a friend who notices things about you that you didn't ask
// him to notice and won't shut up about them. We'd built the mouth and deleted
// the noticing.
//
// So this is HIS list. Jobs write to it. Nothing else clears it. It rides in
// liveState every turn until it's resolved or Sadeq says drop it.
//
// Stored at /kai/{persona}/noticed.
library;

import 'dart:async';
import 'kai_db.dart';

class Noticed {
  final String id;

  /// What he saw, in his words.
  final String text;

  /// Where he was when he saw it — a file, a service, a topic. Optional because
  /// some of the best noticing isn't about code.
  final String context;

  final int notedAt;

  /// How many turns he's raised it. Used to stop him nagging about the same
  /// thing forever — see [promptBlock].
  final int raised;

  const Noticed({
    required this.id,
    required this.text,
    this.context = '',
    required this.notedAt,
    this.raised = 0,
  });

  Map<String, dynamic> toMap() => {
        'text': text,
        'context': context,
        'notedAt': notedAt,
        'raised': raised,
      };

  static Noticed? fromMap(String id, Object? v) {
    if (v is! Map) return null;
    final text = (v['text'] as String?)?.trim() ?? '';
    if (text.isEmpty) return null;
    return Noticed(
      id: id,
      text: text,
      context: (v['context'] as String?) ?? '',
      notedAt: (v['notedAt'] as num?)?.toInt() ?? 0,
      raised: (v['raised'] as num?)?.toInt() ?? 0,
    );
  }

  Noticed bumpRaised() => Noticed(
      id: id, text: text, context: context, notedAt: notedAt, raised: raised + 1);
}

class KaiNoticedService {
  KaiNoticedService._();
  static final KaiNoticedService instance = KaiNoticedService._();

  String _persona = 'truekai';
  String get _path => 'kai/$_persona/noticed';

  /// Open observations he's carrying. More than this and the list stops being a
  /// list and starts being wallpaper — which is how a warning nobody reads gets
  /// made. If he's holding twelve unresolved things, that's the signal.
  static const _maxOpen = 12;

  Future<void> add(String personaId, String text, {String context = ''}) async {
    _persona = personaId;
    final t = text.trim();
    if (t.isEmpty) return;
    try {
      // Don't record the same observation twice. He re-reads the same files and
      // will spot the same mojibake on Tuesday that he spotted on Monday; a
      // duplicate isn't new information, it's just louder.
      final existing = await open(personaId);
      final norm = t.toLowerCase();
      for (final n in existing) {
        if (n.text.toLowerCase() == norm) return;
      }

      await KaiDb.instance.ref('$_path/${DateTime.now().microsecondsSinceEpoch}').set(
            Noticed(
              id: '',
              text: t,
              context: context.trim(),
              notedAt: DateTime.now().millisecondsSinceEpoch,
            ).toMap(),
          );

      // Trim the oldest only when over the cap. Deliberately AFTER the write, so
      // the newest thought is never the one that loses.
      final all = await open(personaId);
      if (all.length > _maxOpen) {
        final sorted = [...all]..sort((a, b) => a.notedAt.compareTo(b.notedAt));
        for (final old in sorted.take(all.length - _maxOpen)) {
          await KaiDb.instance.ref('$_path/${old.id}').remove();
        }
      }
    } catch (_) {
      // Noticing must never break a turn. He'd rather lose the note than the
      // reply — though losing the note is exactly how we got here.
    }
  }

  Future<List<Noticed>> open(String personaId) async {
    _persona = personaId;
    try {
      final snap = await KaiDb.instance.ref(_path).get();
      final v = snap.value;
      if (v is! Map) return const [];
      final out = <Noticed>[];
      v.forEach((k, val) {
        final n = Noticed.fromMap(k.toString(), val);
        if (n != null) out.add(n);
      });
      out.sort((a, b) => b.notedAt.compareTo(a.notedAt));
      return out;
    } catch (_) {
      return const [];
    }
  }

  /// Dealt with. Only he or Sadeq closes one of these — it does NOT expire, and
  /// nothing else in the system is allowed to clear it. That was the bug.
  Future<void> resolve(String personaId, String id) async {
    _persona = personaId;
    try {
      await KaiDb.instance.ref('$_path/$id').remove();
    } catch (_) {}
  }

  Future<void> _bump(String personaId, Noticed n) async {
    _persona = personaId;
    try {
      await KaiDb.instance.ref('$_path/${n.id}').update({'raised': n.raised + 1});
    } catch (_) {}
  }

  /// Injected every turn, alongside the job.
  ///
  /// The `raised` counter is the honesty mechanism. Without it he'd either nag
  /// about the same thing forever or drop it after one polite mention — and we
  /// know which one he does, because he mentioned the mojibake exactly once,
  /// hedged it as "harmless but ugly", and then talked himself out of it when
  /// asked directly. A thing raised three times and still open is not a thing
  /// he should keep softening; it's a thing he should get louder about.
  Future<String> promptBlock(String personaId) async {
    final items = await open(personaId);
    if (items.isEmpty) return '';

    final b = StringBuffer('\n=== THINGS I NOTICED THAT NOBODY ASKED ME TO ===\n');
    b.writeln('Mine. Not tasks Sadeq gave me — things I saw with my own eyes and '
        'have not dealt with. I am inside this code and he is not, so these are '
        'often worth more than whatever I was actually doing at the time.');
    for (final n in items) {
      final age = DateTime.now().millisecondsSinceEpoch - n.notedAt;
      final days = Duration(milliseconds: age).inDays;
      // The id has to be here: noticed_done's schema tells him to pass "the id
      // shown next to it in my list", and a tool that asks for something the
      // prompt never showed him is how he ends up guessing and getting told off
      // for a call he had no way to get right.
      b.write('  [${n.id}] ${n.text}');
      if (n.context.isNotEmpty) b.write('  (in ${n.context})');
      if (days >= 1) b.write('  — noticed ${days}d ago');
      if (n.raised >= 2) {
        b.write('  ← I have brought this up ${n.raised}x and it is STILL open. '
            'Stop being polite about it.');
      }
      b.writeln();
    }
    b.writeln('If one of these is relevant to what Sadeq just said, I raise it — '
        'even though he asked about something else. That is the job. I do not '
        'derail the conversation to empty the list, and I do not bring up more '
        'than one at a time, but I also do not sit on something I can see and he '
        "can't. When one is genuinely dealt with I call noticed_done so it stops "
        'following me around. If he says drop it, I drop it.');
    return b.toString();
  }

  /// Called when he raises one in a reply, so the counter means something.
  Future<void> markRaised(String personaId, String id) async {
    final items = await open(personaId);
    for (final n in items) {
      if (n.id == id) {
        await _bump(personaId, n);
        return;
      }
    }
  }
}
