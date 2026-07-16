// KaiBondService — the shared history between Kai and Sadeq.
//
// This is the thing that separates a childhood best friend from an assistant.
// An assistant knows FACTS about you (that's KaiUserModelService). A best friend
// has a shared CULTURE with you: the running bit, the stupid nickname, the thing
// that happened that you both still reference, the callback that lands because
// only the two of you were there.
//
// Kai builds this himself with remember_bit as moments happen, and it's injected
// into every prompt so he can call back when it lands. The eternal-friend trick
// isn't remembering everything — it's remembering the RIGHT dumb thing.
//
// Stored at /kai/{persona}/bond/{pushId} = { text, kind, createdAt }.
// Pure Dart + KaiDb (desktop-safe).
library;

import 'dart:async';
import 'kai_db.dart';

/// What kind of shared thing this is. Loose on purpose — the point is texture.
class KaiBondKind {
  static const bit = 'bit';               // a running joke
  static const nickname = 'nickname';     // what we call each other
  static const reference = 'reference';   // a thing we both point at
  static const milestone = 'milestone';   // a moment that mattered
  static const all = [bit, nickname, reference, milestone];
}

class KaiBond {
  final String id;
  final String text;
  final String kind;
  final int createdAt;
  const KaiBond({
    required this.id,
    required this.text,
    required this.kind,
    required this.createdAt,
  });
}

class KaiBondService {
  static final KaiBondService instance = KaiBondService._();
  KaiBondService._();

  String _persona = 'truekai';
  String get _path => 'kai/$_persona/bond';

  /// Record a running bit / nickname / callback / milestone.
  Future<String> remember(String personaId, String text,
      {String kind = KaiBondKind.bit}) async {
    _persona = personaId;
    final t = text.trim();
    if (t.isEmpty) return '';
    final k = KaiBondKind.all.contains(kind) ? kind : KaiBondKind.bit;
    final ref = KaiDb.instance.ref(_path).push();
    await ref.set({
      'text': t,
      'kind': k,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    });
    return ref.key ?? '';
  }

  Future<void> forget(String personaId, String id) async {
    _persona = personaId;
    if (id.trim().isEmpty) return;
    try {
      await KaiDb.instance.ref('$_path/$id').remove();
    } catch (_) {}
  }

  Future<List<KaiBond>> all(String personaId, {int limit = 40}) async {
    _persona = personaId;
    try {
      final snap = await KaiDb.instance.ref(_path).limitToLast(limit).get();
      final v = snap.value;
      if (v is! Map) return const [];
      final out = <KaiBond>[];
      v.forEach((k, val) {
        if (val is Map && val['text'] != null) {
          out.add(KaiBond(
            id: k.toString(),
            text: val['text'].toString(),
            kind: (val['kind'] ?? KaiBondKind.bit).toString(),
            createdAt: (val['createdAt'] is int) ? val['createdAt'] as int : 0,
          ));
        }
      });
      out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return out;
    } catch (_) {
      return const [];
    }
  }

  /// A block for the system prompt: the culture that's ours.
  Future<String> promptBlock(String personaId) async {
    final items = await all(personaId);
    if (items.isEmpty) return '';
    final lines = items.take(20).map((b) => '  • [${b.kind}] ${b.text}').join('\n');
    return 'Ours — the bits, names and callbacks only we have '
        '(use them when they genuinely land; a forced callback is worse than none, '
        'and add new ones with remember_bit as they happen):\n$lines';
  }
}
