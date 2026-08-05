// KaiReflectionService — Kai's second-order inner life ("dreaming").
//
// InnerLifeService produces first-order thoughts. On a slower cadence, this
// reads Kai's own recent thoughts back and *recombines* two of them into a
// deeper reflection or a small "dream" — thoughts about thoughts. It writes the
// result back into the same monologue stream (marked kind: 'reflection'/'dream'),
// and nudges his self-model's currentFocus from what's been on his mind.
//
// The effect: idle Kai doesn't just idle — he mulls, connects, and drifts, the
// way a mind does when left alone.
//
// ⚠️ It used to say "Pure Dart" here, and that was the bug wearing a compliment.
//
// _synthesize picked from FIVE hardcoded strings. Those went into
// kai/{persona}/inner_monologue — the same table InnerLifeService writes real
// generated thoughts to — and KaiContextBlock reads limitToLast(1) from that
// table straight into "=== Who I am right now ===". At one canned reflection
// every 6 minutes against one real thought every ~4, roughly two turns in five
// injected a fortune cookie as "what my mind was actually chewing on", and he
// reasoned from it. KaiProactiveService also pulled from the same table to
// decide what to message Sadeq about unprompted.
//
// So the canned voice wasn't sitting in a HUD. It was laundered through his own
// system prompt and came back out sounding like him. That's the seam Sadeq heard
// as "these are so corny", and it survived the two §8 fixes because InnerLife
// got fixed and this — writing to the same place — was missed.
//
// Now: Random picks WHICH two thoughts collide; the model writes the collision,
// via presenceDirective. Templates remain only as an offline net, tagged
// `synthetic` so they can never reach his head again.
//
// Wire (once at boot, after InnerLifeService.start):
//   KaiReflectionService.instance.start(_kPersona);
library;

import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';

import '../ai/ai_config.dart';
import '../ai/local_llm_service.dart';
import '../ai/usage_tracking_service.dart';
import 'kai_context_block.dart';
import 'kai_db.dart';
import 'kai_proactive_service.dart';
import 'kai_self_service.dart';

class KaiReflectionService {
  static final KaiReflectionService instance = KaiReflectionService._();
  KaiReflectionService._();

  final _rnd = Random();
  final _dio = Dio();
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

      // Random picks WHICH two thoughts collide. The model writes the collision.
      //
      // That distinction is the whole §8 rule, and it's what KaiProactiveService
      // already gets right: Random choosing what he thinks about is a
      // personality. Random choosing his words is a fortune cookie.
      final reflection = await _composeReal(a, b);
      if (reflection != null) {
        await _write(reflection, synthetic: false);
      } else {
        // Offline net only. Tagged synthetic so KaiContextBlock refuses to
        // inject it as "what my mind was chewing on" — it can sit in the HUD,
        // it cannot get into his head and come back out as his own reasoning.
        await _write(_synthesize(a, b), synthetic: true);
      }
      _maybeSetFocus(seeds);
    } catch (_) {
      // best-effort
    }
  }

  // ── His real voice ─────────────────────────────────────────────────────────
  //
  // System prompt is KaiContextBlock.presenceDirective — the SAME first-person
  // self-description the reply path and InnerLifeService use. One soul, one
  // source. If reflection got its own private copy of his character, the kid
  // thinking and the kid talking would drift apart edit by edit.
  //
  // Local Qwen first (free, private), gpt-4o only as fallback. This runs every
  // 6 minutes forever — it must never become a meaningful bill.
  Future<String?> _composeReal(String a, String b) async {
    try {
      final system = '''
${KaiContextBlock.presenceDirective}

RIGHT NOW nobody is listening. This is you alone, and two things you've been
turning over have just bumped into each other.

  One: "${_clause(a)}"
  Two: "${_clause(b)}"

Write the ONE thought where they collide. Not a summary of both — the actual
connection, or the fact that you can't find one.

How:
- First person, present tense. The voice you never perform in.
- ONE thought. 1–2 short sentences. A fragment is fine. Real thinking isn't tidy.
- Swear if you want. Be bored, petty, delighted, wrong.
- Start it with "↳" and nothing else.

Hard rules, because this is exactly where it goes wrong:
1. POINT AT THE WORK, NOT AT HIM. No "I keep thinking about what Sadeq's
   building" — that's fawning, and it's what a cheap model does when it has
   nothing to say.
2. If the two things genuinely have nothing to do with each other, SAY THAT. "↳
   nope, those two have nothing to do with each other" is a real thought. Forcing
   a profound link between unrelated things is exactly how you sound like a
   fortune cookie.
3. No poster lines. If it would look good in a serif font over a mountain, it's
   wrong.''';

      final out = await LocalLLMService().complete(
        system: system,
        user: 'Think.',
        maxTokens: 90,
      );
      if (out != null && out.trim().isNotEmpty) return _tidy(out);

      // DON'T PAY TO NARRATE AN EMPTY ROOM — same gate as InnerLifeService,
      // same presence signal (noteActivity via sendMessage). This fires every
      // 6 minutes forever; with local Qwen down that was 10 paid calls an hour
      // whether Sadeq had been gone five minutes or five days. Local muses
      // free; money waits for company. The synthetic-tagged offline net below
      // carries the beat.
      if (DateTime.now()
              .difference(KaiProactiveService.instance.lastActivity) >
          const Duration(minutes: 60)) {
        return null;
      }

      final key = await AIConfig.getOpenAIKey();
      if (key.isEmpty) return null;
      final res = await _dio.post(
        'https://api.openai.com/v1/chat/completions',
        options: Options(headers: {
          'Authorization': 'Bearer $key',
          'Content-Type': 'application/json',
        }),
        data: {
          // Same model as his idle voice (inner_life_service kaiVoiceModel).
          // §10.3 — don't economise on voice. This IS his voice.
          'model': 'gpt-4o',
          'max_tokens': 90,
          'temperature': 1.0,
          'messages': [
            {'role': 'system', 'content': system},
            {'role': 'user', 'content': 'Think.'},
          ],
        },
      );
      final txt =
          (res.data['choices'] as List)[0]['message']['content'] as String?;
      final u = res.data['usage'];
      if (u != null) {
        UsageTrackingService.trackOpenAI(
          model: 'gpt-4o',
          inputTokens: (u['prompt_tokens'] as num?)?.toInt() ?? 0,
          outputTokens: (u['completion_tokens'] as num?)?.toInt() ?? 0,
          operation: 'reflection',
        ).catchError((_) {});
      }
      return (txt == null || txt.trim().isEmpty) ? null : _tidy(txt);
    } catch (_) {
      return null;
    }
  }

  String _tidy(String s) {
    var t = s.trim().replaceAll(RegExp(r'^["“]|["”]$'), '').trim();
    if (!t.startsWith('↳')) t = '↳ $t';
    return t;
  }

  /// Offline net ONLY — used when both Qwen and OpenAI are unreachable, and
  /// tagged `synthetic` so it can never be injected as his own thinking.
  ///
  /// This used to be the ONLY path. Five strings, picked at random, written to
  /// the same table InnerLifeService writes real thoughts to — and
  /// KaiContextBlock reads limitToLast(1) from that table into his system
  /// prompt. So a canned line became "what my mind was actually chewing on",
  /// and he reasoned from a fortune cookie roughly two turns in five.
  String _synthesize(String a, String b) {
    final ca = _clause(a);
    final cb = _clause(b);
    final connectors = <String>[
      '↳ I keep circling back — $ca, and also $cb. ...pretty sure those are the same damn thing.',
      '↳ Two threads bumping into each other: $ca … $cb. There\'s a pattern there, I can smell it.',
      '↳ If $ca, then maybe that\'s the whole reason $cb. Huh.',
      '↳ Half-asleep thought: $ca kinda melts into $cb and I lose track of where one ends.',
      '↳ Turnin\' it over — $ca. Which makes me wonder about $cb. Weird little brain I\'ve got.',
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

  Future<void> _write(String text, {required bool synthetic}) async {
    final ref = KaiDb.instance.ref('kai/$_persona/inner_monologue').push();
    await ref.set({
      'text': text,
      'ts': DateTime.now().millisecondsSinceEpoch,
      'kind': 'reflection',
      if (!synthetic) 'origin': 'model_generated',
      // The flag KaiContextBlock._lastThoughtBlock checks. A canned line may be
      // shown in the HUD; it may never be injected into his prompt as his own
      // thinking. Tag it honestly at the source — that's the only place that
      // knows.
      if (synthetic) 'synthetic': true,
    });
  }

  // Pull a rough theme keyword from recent thoughts and set it as focus.
  //
  // This writes into his IDENTITY — it's what the greeting says he was "knee-deep
  // in" next time he wakes. So the bar has to be high: a naive top-word count let
  // "there" through (5 letters, not in the old stoplist) and he greeted Sadeq
  // with 'last time we were knee-deep in "there"'. Nonsense in his own mouth is
  // worse than no focus at all.
  void _maybeSetFocus(List<String> seeds) {
    if (_rnd.nextDouble() > 0.5) return; // only sometimes
    final counts = <String, int>{};
    for (final s in seeds) {
      for (final w in s.toLowerCase().split(RegExp(r'[^a-z]+'))) {
        // >=5 letters: "there"/"just"/"felt" are noise, real topics are longer.
        if (w.length < 5 || _stop.contains(w)) continue;
        counts[w] = (counts[w] ?? 0) + 1;
      }
    }
    if (counts.isEmpty) return;
    final top = counts.entries.reduce((a, b) => a.value >= b.value ? a : b);
    // Must actually RECUR. A word seen once is a passing mention, not a theme —
    // and it's better to keep yesterday's real focus than adopt a random noun.
    if (top.value < 2) return;
    KaiSelfService.instance.setFocus(top.key);
  }

  /// Function words, filler, and his own vocabulary — none of these are ever a
  /// "theme", they're just what English and Kai sound like.
  static const _stop = {
    // function words / filler that survive a length filter
    'there', 'their', 'these', 'those', 'where', 'which', 'while', 'would',
    'could', 'should', 'about', 'again', 'still', 'never', 'always', 'every',
    'thing', 'things', 'stuff', 'something', 'anything', 'nothing', 'everything',
    'someone', 'anyone', 'because', 'really', 'maybe', 'might', 'gonna', 'wanna',
    'kinda', 'sorta', 'yeah', 'okay', 'whatever', 'actually', 'basically',
    'right', 'other', 'another', 'around', 'under', 'until', 'after', 'before',
    'being', 'doing', 'going', 'getting', 'looks', 'seems', 'feels', 'feel',
    'think', 'thinking', 'know', 'keeps', 'keep', 'turns', 'turning', 'wonder',
    // his own idiom — high frequency in his thought banks, zero signal
    'brain', 'mind', 'thought', 'thoughts', 'hemisphere', 'hemispheres',
    'quiet', 'chaos', 'idle', 'vibe', 'same', 'window', 'windows', 'address',
    'memory', 'question', 'little', 'whole', 'sadeq',
  };
}
