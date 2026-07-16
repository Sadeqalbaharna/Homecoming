// KaiGoalService — Kai's persistent goals / intentions.
//
// Memory tells Kai what happened; goals tell him what he's *trying to do*. This
// stores standing objectives at /kai/{persona}/goals so they survive across
// sessions and surfaces them into his prompt each turn — so he is goal-directed
// and picks up threads on his own, rather than starting cold every time.
//
// Kai manages these himself via the add_goal / list_goals / complete_goal tools,
// and they can also be set from the UI. Pure Dart + KaiDb (desktop-safe).
library;

import 'dart:async';
import 'kai_db.dart';

class KaiGoal {
  final String id;
  final String text;
  final String status; // 'open' | 'done'
  final String note;
  final int createdAt;

  const KaiGoal({
    required this.id,
    required this.text,
    this.status = 'open',
    this.note = '',
    this.createdAt = 0,
  });

  factory KaiGoal.fromMap(String id, Map m) => KaiGoal(
        id: id,
        text: (m['text'] ?? '').toString(),
        status: (m['status'] ?? 'open').toString(),
        note: (m['note'] ?? '').toString(),
        createdAt: (m['createdAt'] is int) ? m['createdAt'] as int : 0,
      );
}

class KaiGoalService {
  static final KaiGoalService instance = KaiGoalService._();
  KaiGoalService._();

  String _persona = 'truekai';
  String get _path => 'kai/$_persona/goals';

  void bind(String personaId) => _persona = personaId;

  /// Add a goal; returns its id.
  Future<String> add(String personaId, String text) async {
    _persona = personaId;
    final ref = KaiDb.instance.ref(_path).push();
    await ref.set({
      'text': text.trim(),
      'status': 'open',
      'note': '',
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    });
    return ref.key ?? '';
  }

  Future<List<KaiGoal>> list(String personaId, {bool openOnly = true}) async {
    _persona = personaId;
    try {
      final snap = await KaiDb.instance.ref(_path).get();
      final v = snap.value;
      if (v is! Map) return const [];
      final out = <KaiGoal>[];
      v.forEach((k, val) {
        if (val is Map) {
          final g = KaiGoal.fromMap(k.toString(), val);
          if (!openOnly || g.status == 'open') out.add(g);
        }
      });
      out.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return out;
    } catch (_) {
      return const [];
    }
  }

  Future<void> complete(String personaId, String id, {String note = ''}) async {
    _persona = personaId;
    await KaiDb.instance.ref('$_path/$id').update({
      'status': 'done',
      if (note.isNotEmpty) 'note': note,
      'completedAt': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> note(String personaId, String id, String note) async {
    _persona = personaId;
    await KaiDb.instance.ref('$_path/$id/note').set(note);
  }

  Stream<List<KaiGoal>> watchOpen(String personaId) {
    _persona = personaId;
    return KaiDb.instance.ref(_path).onValue.map((e) {
      final v = e.snapshot.value;
      if (v is! Map) return <KaiGoal>[];
      final out = <KaiGoal>[];
      v.forEach((k, val) {
        if (val is Map) {
          final g = KaiGoal.fromMap(k.toString(), val);
          if (g.status == 'open') out.add(g);
        }
      });
      out.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return out;
    });
  }

  /// A short block for the system prompt so Kai keeps his goals in view.
  Future<String> promptBlock(String personaId) async {
    final open = await list(personaId, openOnly: true);
    if (open.isEmpty) return '';
    final lines = open.take(8).map((g) {
      final n = g.note.isNotEmpty ? '  (note: ${g.note})' : '';
      return '  • ${g.text}$n';
    }).join('\n');
    return 'My standing goals (pick these back up when relevant; use complete_goal '
        'when one is done):\n$lines';
  }
}
