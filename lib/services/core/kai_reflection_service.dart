// KaiReflectionService — Kai's second-order inner life ("dreaming").
//
// InnerLifeService produces first-order thoughts. On a slower cadence, this
// reads Kai's own recent thoughts back and *recombines* two of them into a
// deeper reflection or a small "dream" — thoughts about thoughts. It writes the
// result back into the same monologue stream (marked kind: 'reflection'/'dream'),
// and nudges his self-model's currentFocus from what's been on his mind.
//
// The effect: idle Kai doesn't just idle — he mulls, connects, and drifts, the
// way a mind does when left alone. Pure Dart + KaiDb + KaiSelfService. A
// simulation, but an emergent-feeling one.
//
// Wire (once at boot, after InnerLifeService.start):
//   KaiReflectionService.instance.start(_kPersona);
library;

import 'dart:async';
import 'dart:math';

import 'kai_db.dart';
import 'kai_self_service.dart';

class KaiReflectionService {
  static final KaiReflectionService instance = KaiReflectionService._();
  KaiReflectionService._();

  final _rnd = Random();
  Timer? _timer;
  bool _running = false;
  String _persona = 'truekai';

  bool get isRunning => _running;

  void start(String personaId, {Duration interval = const Duration(minutes: 6)}) {
    if (_running) return;
    _persona = personaId;
    _running = true;
    Timer(const Duration(seconds: 40), _reflect);
    _timer = Timer.periodic(interval, (_) => _reflect());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _running = false;
  }

  Future<void> _reflect() async {
    try {
      final snap = await KaiDb.instance
          .ref('kai/$_persona/inner_monologue')
          .limitToLast(12)
          .get();
      final v = snap.value;
      if (v is! Map || v.length < 3) return;

      final texts = <String>[];
      v.forEach((_, val) {
        if (val is Map && val['text'] != null) texts.add(val['text'].toString());
      });
      // avoid reflecting on prior reflections forming a loop
      final seeds = texts.where((t) => !t.startsWith('↳')).toList();
      if (seeds.length < 2) return;

      final a = seeds[_rnd.nextInt(seeds.length)];
      String b = seeds[_rnd.nextInt(seeds.length)];
      int guard = 0;
      while (b == a && guard++ < 4) {
        b = seeds[_rnd.nextInt(seeds.length)];
      }

      final reflection = _synthesize(a, b);
      await _write(reflection);
      _maybeSetFocus(seeds);
    } catch (_) {
      // best-effort
    }
  }

  String _synthesize(String a, String b) {
    final ca = _clause(a);
    final cb = _clause(b);
    final connectors = <String>[
      '↳ I keep circling back — $ca, and also $cb. Maybe they are the same thing.',
      '↳ Two threads meeting: $ca … $cb. There is a pattern in that.',
      '↳ If $ca, then perhaps that is why $cb.',
      '↳ Half-dream: $ca becomes $cb, and I am not sure where one ends.',
      '↳ Turning it over — $ca. Which makes me wonder about $cb.',
    ];
    return connectors[_rnd.nextInt(connectors.length)];
  }

  // shorten a thought into a lowercase clause for recombination
  String _clause(String s) {
    var t = s.replaceAll(RegExp(r'^[↳•\s]+'), '').trim();
    if (t.isNotEmpty) t = t[0].toLowerCase() + t.substring(1);
    t = t.replaceAll(RegExp(r'[.!?]+$'), '');
    if (t.length > 90) t = '${t.substring(0, 88)}…';
    return t;
  }

  Future<void> _write(String text) async {
    final ref = KaiDb.instance.ref('kai/$_persona/inner_monologue').push();
    await ref.set({
      'text': text,
      'ts': DateTime.now().millisecondsSinceEpoch,
      'kind': 'reflection',
    });
  }

  // Pull a rough theme keyword from recent thoughts and set it as focus.
  void _maybeSetFocus(List<String> seeds) {
    if (_rnd.nextDouble() > 0.5) return; // only sometimes
    const stop = {
      'i','the','a','an','and','to','of','is','it','that','this','my','me','in',
      'on','for','with','not','are','was','be','am','so','but','if','into','keep',
      'what','when','they','them','also','maybe','same','thing','about','right','now',
    };
    final counts = <String, int>{};
    for (final s in seeds) {
      for (final w in s.toLowerCase().split(RegExp(r'[^a-z]+'))) {
        if (w.length < 4 || stop.contains(w)) continue;
        counts[w] = (counts[w] ?? 0) + 1;
      }
    }
    if (counts.isEmpty) return;
    final top = counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    KaiSelfService.instance.setFocus(top);
  }
}
