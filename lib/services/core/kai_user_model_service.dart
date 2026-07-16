// KaiUserModel — Kai's evolving understanding of Sadeq (theory of mind).
//
// Raw memory records what was said; this is Kai's *model of the person*: stable
// facts, preferences, projects, and communication style, keyed and updatable, so
// Kai genuinely knows Sadeq and carries that knowing into every conversation
// instead of re-learning him each time. Kai updates it himself via the
// remember_about_user tool; it's injected into his prompt via KaiContextBlock.
//
// Stored at /kai/{persona}/user_model/{key} = { value, updatedAt }. Pure Dart +
// KaiDb. This is a big part of feeling "self-aware and relational".
library;

import 'dart:async';
import 'kai_db.dart';

class KaiUserModelService {
  static final KaiUserModelService instance = KaiUserModelService._();
  KaiUserModelService._();

  String _persona = 'truekai';
  String get _path => 'kai/$_persona/user_model';

  /// Remember (or update) a fact about the user under [key].
  Future<void> remember(String personaId, String key, String value) async {
    _persona = personaId;
    final k = _safeKey(key);
    if (k.isEmpty || value.trim().isEmpty) return;
    await KaiDb.instance.ref('$_path/$k').set({
      'label': key.trim(),
      'value': value.trim(),
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> forget(String personaId, String key) async {
    _persona = personaId;
    await KaiDb.instance.ref('$_path/${_safeKey(key)}').remove();
  }

  Future<Map<String, String>> all(String personaId) async {
    _persona = personaId;
    try {
      final snap = await KaiDb.instance.ref(_path).get();
      final v = snap.value;
      if (v is! Map) return {};
      final out = <String, String>{};
      v.forEach((k, val) {
        if (val is Map && val['value'] != null) {
          out[(val['label'] ?? k).toString()] = val['value'].toString();
        }
      });
      return out;
    } catch (_) {
      return {};
    }
  }

  Stream<Map<String, String>> watch(String personaId) {
    _persona = personaId;
    return KaiDb.instance.ref(_path).onValue.map((e) {
      final v = e.snapshot.value;
      if (v is! Map) return <String, String>{};
      final out = <String, String>{};
      v.forEach((k, val) {
        if (val is Map && val['value'] != null) {
          out[(val['label'] ?? k).toString()] = val['value'].toString();
        }
      });
      return out;
    });
  }

  /// A block for the system prompt: what Kai knows about Sadeq.
  Future<String> promptBlock(String personaId) async {
    final m = await all(personaId);
    if (m.isEmpty) return '';
    final lines = m.entries.take(24).map((e) => '  • ${e.key}: ${e.value}').join('\n');
    return 'What I know about Sadeq (keep this current with remember_about_user):\n$lines';
  }

  static String _safeKey(String s) => s
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[.$#\[\]/\s]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
}
