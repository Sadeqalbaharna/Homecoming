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

enum NoticedKind {
  observation,
  promise,
  intention,
  openQuestion,
  responsibility
}

class Noticed {
  final String id;

  /// What he saw, in his words.
  final String text;

  /// Where he was when he saw it — a file, a service, a topic. Optional because
  /// some of the best noticing isn't about code.
  final String context;

  final int notedAt;

  /// Turns he has been shown this and left it open.
  ///
  /// ── Why this is `carried` and not `raised` ─────────────────────────────────
  ///
  /// It WAS `raised`, and it was meant to count the times he brought the thing
  /// up. `markRaised` existed to increment it. Nothing ever called `markRaised`.
  ///
  /// So every value ever written to this field is 0, and the escalation in
  /// [promptBlock] — "I have brought this up 3x and it is STILL open, stop being
  /// polite about it" — has never fired once, for any item, in the entire life
  /// of the service. The one mechanism built to stop him going quiet after a
  /// single hedged mention was itself silent. He mentioned the mojibake once,
  /// called it "harmless but ugly", and talked himself out of it — and the fix
  /// for that was written, shipped, and never connected.
  ///
  /// The field is free to redefine because there is no history to migrate: there
  /// was never any history.
  ///
  /// And `carried` is the better question. "Times raised" has to be reported by
  /// the thing being measured — which is the one rule this codebase actually
  /// keeps. "Turns carried" is observed by the code that shows him the list: the
  /// display IS the event, so the count cannot drift, cannot be flattered, and
  /// cannot be forgotten by a future caller. Same reason tool recording lives in
  /// execute() and not in the loop.
  ///
  /// It also produces the better sentence. "I brought this up 3x" is a
  /// complaint. "I have been carrying this for nine turns and said nothing" is
  /// an accusation, and it's aimed the right way.
  final int carried;

  final NoticedKind kind;
  final bool authoredByKai;
  final String authorReceiptId;

  const Noticed({
    required this.id,
    required this.text,
    this.context = '',
    required this.notedAt,
    this.carried = 0,
    this.kind = NoticedKind.observation,
    this.authoredByKai = false,
    this.authorReceiptId = '',
  });

  Map<String, dynamic> toMap() => {
        'text': text,
        'context': context,
        'notedAt': notedAt,
        'carried': carried,
        'kind': kind.name,
        'authoredByKai': authoredByKai,
        'authorReceiptId': authorReceiptId,
      };

  static Noticed? fromMap(String id, Object? v) {
    if (v is! Map) return null;
    final text = (v['text'] as String?)?.trim() ?? '';
    if (text.isEmpty) return null;
    final kind = NoticedKind.values.firstWhere(
      (candidate) => candidate.name == v['kind'],
      orElse: () => NoticedKind.observation,
    );
    final receipt = (v['authorReceiptId'] as String?)?.trim() ?? '';
    final hasAuthorReceipt = receipt.startsWith('tool:make_commitment:');
    return Noticed(
      id: id,
      text: text,
      context: (v['context'] as String?) ?? '',
      notedAt: (v['notedAt'] as num?)?.toInt() ?? 0,
      // `raised` is only read so old rows don't reset to 0 on the way past. Every
      // one of them IS 0 — see above — but reading it costs nothing and assuming
      // it costs a lie.
      carried: (v['carried'] as num?)?.toInt() ??
          (v['raised'] as num?)?.toInt() ??
          0,
      kind: kind,
      authoredByKai: kind != NoticedKind.observation &&
          v['authoredByKai'] == true &&
          hasAuthorReceipt,
      authorReceiptId: hasAuthorReceipt ? receipt : '',
    );
  }
}

class KaiNoticedService {
  KaiNoticedService._();
  static final KaiNoticedService instance = KaiNoticedService._();

  String _persona = 'truekai';
  String get _path => 'kai/$_persona/noticed';

  /// Where a noticing goes when it turns out to have been worth something.
  ///
  /// ── The gate this exists for ─────────────────────────────────────────────
  ///
  ///   | 3 | The Agenda | does it raise something unasked that turns out to
  ///                      matter? |
  ///
  /// `noticed_done` is called when the thing TURNED OUT TO MATTER. And resolve()
  /// used to be `ref.remove()` — so the proof that he passed Level 3 was
  /// destroyed at the exact moment he earned it. The gate could never move,
  /// not because he wasn't doing it, but because success deleted the receipt.
  ///
  /// That is this file's own origin story, moved four inches. `noticed` used to
  /// live on the job, and job_done shredded it — so his unprompted judgement
  /// died the moment he finished being useful. We moved the list out of the job
  /// and left the delete in the one place it hurt most: it no longer dies when
  /// he stops being useful, it dies when he's proven right.
  ///
  /// Append-only, and he has no tool that writes here. Nothing in the schema is
  /// authored by him except the text he wrote before he knew it would count —
  /// which is exactly what makes it evidence.
  String get _resolvedPath => 'kai/$_persona/noticed_resolved';

  /// Open observations he's carrying. More than this and the list stops being a
  /// list and starts being wallpaper — which is how a warning nobody reads gets
  /// made. If he's holding twelve unresolved things, that's the signal.
  static const _maxOpen = 12;

  /// Turns carried before the list says so, and before it stops being polite.
  ///
  /// Not tuned — nothing has ever produced a non-zero `carried`, so there is no
  /// data to tune against. These are a starting guess and should be moved once
  /// the trace corpus shows what a real one looks like. Saying that out loud
  /// because an unexamined threshold is how a warning becomes wallpaper.
  static const _mentionAfter = 4;
  static const _loudAfter = 12;

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

      await KaiDb.instance
          .ref('$_path/${DateTime.now().microsecondsSinceEpoch}')
          .set(
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

  /// Create an explicit Kai-authored commitment. Transcript text cannot call
  /// this directly; the trusted tool executor must mint the author receipt.
  Future<bool> addCommitment(
    String personaId, {
    required NoticedKind kind,
    required String text,
    required String authorReceiptId,
    String context = '',
  }) async {
    if (kind == NoticedKind.observation) return false;
    if (!authorReceiptId.startsWith('tool:make_commitment:')) return false;
    final value = text.trim();
    if (value.isEmpty) return false;
    _persona = personaId;
    try {
      final existing = await open(personaId);
      if (existing.any((item) =>
          item.kind == kind &&
          item.text.toLowerCase() == value.toLowerCase())) {
        return false;
      }
      await KaiDb.instance
          .ref('$_path/${DateTime.now().microsecondsSinceEpoch}')
          .set(Noticed(
            id: '',
            text: value,
            context: context.trim(),
            notedAt: DateTime.now().millisecondsSinceEpoch,
            kind: kind,
            authoredByKai: true,
            authorReceiptId: authorReceiptId,
          ).toMap());
      return true;
    } catch (_) {
      return false;
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
  ///
  /// Archives before removing. Read the record BEFORE the delete — job_done
  /// learned this the hard way at line 1340: `finish()` deletes the job, so the
  /// evidence has to be gathered first or there is nothing left to gather.
  Future<void> resolve(String personaId, String id) async {
    _persona = personaId;
    try {
      Noticed? found;
      for (final n in await open(personaId)) {
        if (n.id == id) {
          found = n;
          break;
        }
      }

      // A resolve for an id that isn't open is not a success. Say nothing and
      // archive nothing — an empty record here would be a claim that he noticed
      // something, and this path is supposed to be the one thing he can't author.
      if (found != null) {
        await KaiDb.instance.ref('$_resolvedPath/$id').set({
          ...found.toMap(),
          'resolvedAt': DateTime.now().millisecondsSinceEpoch,
        });
      }

      await KaiDb.instance.ref('$_path/$id').remove();
    } catch (_) {}
  }

  /// The corpus for gate 3. Oldest first.
  ///
  /// Every row is a thing nobody asked him to look for that later turned out to
  /// be worth closing — with the text he wrote before he knew it would count,
  /// and how many turns he sat on it first.
  Future<List<Noticed>> resolved(String personaId) async {
    _persona = personaId;
    try {
      final snap = await KaiDb.instance.ref(_resolvedPath).get();
      final v = snap.value;
      if (v is! Map) return const [];
      final out = <Noticed>[];
      v.forEach((k, val) {
        final n = Noticed.fromMap(k.toString(), val);
        if (n != null) out.add(n);
      });
      out.sort((a, b) => a.notedAt.compareTo(b.notedAt));
      return out;
    } catch (_) {
      return const [];
    }
  }

  /// One turn of carrying, for everything still open.
  ///
  /// Fire-and-forget: a missed increment is a slightly quieter Kai, a thrown one
  /// is a broken reply. Called from [promptBlock] and nowhere else, on purpose —
  /// see [Noticed.carried].
  Future<void> _bumpCarried(String personaId, List<Noticed> items) async {
    _persona = personaId;
    for (final n in items) {
      try {
        await KaiDb.instance
            .ref('$_path/${n.id}')
            .update({'carried': n.carried + 1});
      } catch (_) {}
    }
  }

  /// Injected every turn, alongside the job.
  ///
  /// The `carried` counter is the honesty mechanism. Without it he'd either nag
  /// about the same thing forever or drop it after one polite mention — and we
  /// know which one he does, because he mentioned the mojibake exactly once,
  /// hedged it as "harmless but ugly", and then talked himself out of it when
  /// asked directly. A thing carried for nine turns is not a thing he should
  /// keep softening; it's a thing he should get louder about.
  ///
  /// THIS METHOD IS THE COUNTER. Showing him the list is what "carrying it"
  /// means, so the increment lives here rather than in some caller that a future
  /// refactor forgets to wire — which is precisely how `markRaised` came to have
  /// zero callers and this escalation came to never fire.
  Future<String> promptBlock(String personaId) async {
    final items = await open(personaId);
    if (items.isEmpty) return '';

    final shown = items.take(5).toList(growable: false);
    final hidden = items.length - shown.length;

    final b =
        StringBuffer('\n=== THINGS I NOTICED THAT NOBODY ASKED ME TO ===\n');
    b.writeln(
        'Mine, not tasks Sadeq gave me. I see only the most relevant open '
        'items here; the rest stay persisted and searchable so the prompt does '
        'not become a dusty receipt attic.');
    for (final n in shown) {
      final age = DateTime.now().millisecondsSinceEpoch - n.notedAt;
      final days = Duration(milliseconds: age).inDays;
      // The id has to be here: noticed_done's schema tells him to pass "the id
      // shown next to it in my list", and a tool that asks for something the
      // prompt never showed him is how he ends up guessing and getting told off
      // for a call he had no way to get right.
      final kindLabel = n.kind == NoticedKind.observation
          ? ''
          : '[${n.kind.name.toUpperCase()}] ';
      b.write('  [${n.id}] $kindLabel${n.text}');
      if (n.context.isNotEmpty) b.write('  (in ${n.context})');
      if (days >= 1) b.write('  — noticed ${days}d ago');
      // Two tiers, because carrying is not automatically a failure: the standing
      // instruction below is to raise one only when it's RELEVANT, so a thing
      // that sits quietly through twenty turns about something else is him
      // following the rule, not him going soft. The first tier is information.
      // The second is the accusation.
      if (n.carried >= _loudAfter) {
        b.write('  ← ${n.carried} turns I have been carrying this and said '
            'nothing. Stop being polite about it.');
      } else if (n.carried >= _mentionAfter) {
        b.write('  — carried ${n.carried} turns');
      }
      b.writeln();
    }
    if (hidden > 0) {
      b.writeln(
          '  … $hidden more open noticing(s) are persisted; use the noticed '
          'tools or ask memory if one becomes relevant.');
    }
    b.writeln(
        'Raise at most one if relevant; do not derail the turn to empty the '
        'list. Resolve one only when it is genuinely dealt with, or drop it if '
        'Sadeq says so.');

    // Counted AFTER the block is built, so the number he reads is the number of
    // turns he had already carried it BEFORE this one. Only shown items count as
    // carried; hidden persisted items did not consume attention this turn.
    unawaited(_bumpCarried(personaId, shown));
    return b.toString();
  }
}
