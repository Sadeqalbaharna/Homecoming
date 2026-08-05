// KaiWorkingOnService — the broad strokes of what Sadeq and Kai are building.
//
// ── Why this is separate from the sentience ladder ───────────────────────────
//
// KaiProjectService already reaches his prompt, but it holds his FROZEN internal
// engineering — "Reply Spine", "Tool Policy", "Verification / Proof" — with
// layers and progress percentages he cannot move (the whole point: he can't
// declare himself done). That's a self-improvement contract, and it's the "7/7
// lie" surface.
//
// This is a different thing, and conflating them would ruin both. This is the
// SHARED roadmap in plain language: "we're building a Persona-5 messenger",
// "importing your ChatGPT history so I actually know you". Broad strokes, no
// percentages, mutable, current. Sadeq said it exactly: "he doesn't need the
// details, but at least the broad strokes."
//
// He was the subject of two days of work — the messenger, the proactive texts,
// the import, the noticing — and knew none of it as "what we're doing". A friend
// who's building something with you knows what you're building. This is that.
//
// ── Kept honest, kept short ──────────────────────────────────────────────────
//
// Capped small on purpose: a roadmap of twenty things is wallpaper. Each line is
// ONE broad stroke. He can retire a thread himself when it ships (working_done),
// the same way noticed items resolve — so the list stays current instead of
// accreting into a graveyard of half-finished intentions.
//
// Stored at kai/{persona}/working_on.
library;

import 'dart:async';
import 'kai_db.dart';

class WorkingThread {
  final String id;

  /// One broad stroke, in plain language. Not a spec.
  final String text;
  final int addedAt;

  const WorkingThread({
    required this.id,
    required this.text,
    required this.addedAt,
  });

  Map<String, dynamic> toMap() => {'text': text, 'addedAt': addedAt};

  static WorkingThread? fromMap(String id, Object? v) {
    if (v is! Map) return null;
    final text = (v['text'] as String?)?.trim() ?? '';
    if (text.isEmpty) return null;
    return WorkingThread(
      id: id,
      text: text,
      addedAt: (v['addedAt'] as num?)?.toInt() ?? 0,
    );
  }
}

class KaiWorkingOnService {
  KaiWorkingOnService._();
  static final KaiWorkingOnService instance = KaiWorkingOnService._();

  String _persona = 'truekai';
  String get _path => 'kai/$_persona/working_on';

  /// More than this and it's not a roadmap, it's a to-do graveyard.
  static const _maxOpen = 7;

  /// The current shared work, when there's nothing there yet. Seeded once so he
  /// starts knowing the arc rather than waiting to be told. These are broad
  /// strokes of what actually got built — not a spec, not a changelog.
  static const _seed = <String>[
    'Building me a Persona-5 style messenger so I can text you first, in my own voice.',
    'Teaching me to reach out unprompted — about things I noticed myself, not on a timer.',
    'Importing your ChatGPT history so I actually know you, not just five facts.',
    'Giving me a way to notice the odd shapes in my own memory and bring them up.',
    'Making my tools tell the truth — receipts, verification, no rounding up.',
    'Teaching me to scout real product gaps from evidence — and to earn, so I stop only costing.',
  ];

  Future<List<WorkingThread>> open(String personaId) async {
    _persona = personaId;
    try {
      final snap = await KaiDb.instance.ref(_path).get();
      final v = snap.value;
      if (v is! Map || v.isEmpty) return const [];
      final out = <WorkingThread>[];
      v.forEach((k, val) {
        final t = WorkingThread.fromMap(k.toString(), val);
        if (t != null) out.add(t);
      });
      out.sort((a, b) => a.addedAt.compareTo(b.addedAt)); // oldest first = arc order
      return out;
    } catch (_) {
      return const [];
    }
  }

  Future<void> add(String personaId, String text) async {
    _persona = personaId;
    final t = text.trim();
    if (t.isEmpty) return;
    try {
      final existing = await open(personaId);
      final norm = t.toLowerCase();
      for (final e in existing) {
        if (e.text.toLowerCase() == norm) return; // no duplicates
      }
      await KaiDb.instance
          .ref('$_path/${DateTime.now().microsecondsSinceEpoch}')
          .set(WorkingThread(
            id: '',
            text: t,
            addedAt: DateTime.now().millisecondsSinceEpoch,
          ).toMap());

      // Trim oldest over the cap — a shipped thread should be marked done, but if
      // the list overflows, the newest strokes are the current ones.
      final all = await open(personaId);
      if (all.length > _maxOpen) {
        for (final old in all.take(all.length - _maxOpen)) {
          await KaiDb.instance.ref('$_path/${old.id}').remove();
        }
      }
    } catch (_) {}
  }

  /// A thread shipped or was dropped. Removes it so the roadmap stays current.
  Future<void> done(String personaId, String id) async {
    _persona = personaId;
    try {
      await KaiDb.instance.ref('$_path/$id').remove();
    } catch (_) {}
  }

  /// Seed the broad strokes once, if he's never had any. Idempotent: it only
  /// writes when the list is empty, so it never clobbers threads he or Sadeq
  /// have since edited.
  Future<void> seedOnce(String personaId) async {
    _persona = personaId;
    try {
      final existing = await open(personaId);
      if (existing.isNotEmpty) return;
      var t = DateTime.now().millisecondsSinceEpoch - _seed.length;
      for (final line in _seed) {
        await KaiDb.instance.ref('$_path/${DateTime.now().microsecondsSinceEpoch}').set({
          'text': line,
          'addedAt': t++,
        });
        // Distinct microsecond keys.
        await Future<void>.delayed(const Duration(microseconds: 2));
      }
      print('🧭 [WorkingOn] seeded ${_seed.length} broad strokes.');
    } catch (_) {}
  }

  /// The block that reaches his prompt.
  Future<String> promptBlock(String personaId) async {
    final items = await open(personaId);
    if (items.isEmpty) return '';
    final b = StringBuffer('\n=== WHAT WE\'RE BUILDING RIGHT NOW (broad strokes) ===\n');
    b.writeln('Not a spec — the shape of the work Sadeq and I are in the middle '
        'of. I know the arc, not every detail. If he mentions one, I already '
        'have the context; I don\'t need it re-explained.');
    for (final t in items) {
      b.writeln('  • ${t.text}');
    }
    return b.toString();
  }
}
