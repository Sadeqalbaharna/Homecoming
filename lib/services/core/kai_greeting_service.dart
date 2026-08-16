// lib/services/core/kai_greeting_service.dart
// KaiGreetingService — a continuity-aware hello.
//
// Two stages, and the order is the whole design:
//
//   1. WORK OUT THE SITUATION (pure Dart, free, deterministic, testable) — quick
//      return, same-day resume, next-day return, long-gap return, or cold start,
//      plus the gap, the open thread, and his mood.
//   2. LET HIM SAY IT (his real voice, via presenceDirective — the same soul
//      source as his replies and his idle mind), handed the situation from (1)
//      and, only when explicitly approved for speech, the thought his idle mind
//      was actually chewing on while Sadeq was gone.
//
// Templates remain underneath as the offline/no-key net, so a dead network
// degrades to "canned" instead of "silent".
//
// Stage 1 was always right. Stage 2 used to be a Random() over phrase banks —
// which meant his FIRST line of every session, the one that decides whether the
// ghost-friend illusion lands at all, was a hat draw. His outer voice was live
// and his hello was a fortune cookie. That is the seam this closes.
//
// Waking counts stay out of chat. They belong in boot/debug UI, not in my mouth
// like a save-file receipt.
library;

import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'inner_life_service.dart' show kaiVoiceModel;
import 'kai_context_block.dart';
import 'kai_db.dart';
import 'kai_goal_service.dart';
import 'kai_self_service.dart';
import 'kai_state_service.dart';
import '../ai/ai_config.dart';
import '../ai/local_llm_service.dart';
import '../ai/usage_tracking_service.dart';

enum GreetingMode {
  quickReturn,
  sameDayResume,
  nextDayReturn,
  longGapReturn,
  coldStart,
}

class KaiGreetingService {
  static final Random _rng = Random();

  static Future<String> build(String personaId) async {
    final now = DateTime.now();
    final partOfDay = _partOfDay(now.hour);
    final prefs = await SharedPreferences.getInstance();

    Duration? gap;
    String? focus;

    try {
      final self = await KaiSelfService.instance.get(personaId);
      if (self != null) {
        if (self.lastAwake > 0) {
          gap = now.difference(DateTime.fromMillisecondsSinceEpoch(self.lastAwake));
        }
        final rawFocus = self.currentFocus.trim();
        if (_usableFocus(rawFocus)) focus = rawFocus;
      }
    } catch (_) {}

    List<String> openGoals = const [];
    try {
      final goals = await KaiGoalService.instance.list(personaId, openOnly: true);
      openGoals = goals.map((g) => g.text.trim()).where(_usableFocus).take(3).toList();
    } catch (_) {}

    Map<String, int>? mood;
    try {
      final m = await KaiStateService().getMood(personaId);
      if (m != null && m.isNotEmpty) mood = m;
    } catch (_) {}

    final hasThread = focus != null || openGoals.isNotEmpty;
    final mode = _chooseMode(gap, hasThread);
    final since = gap == null ? null : _humanGap(gap);

    final parts = <String>[
      await _fresh(
        prefs,
        personaId,
        'opener',
        _openers(mode, partOfDay),
      ),
      if (_shouldMentionGap(mode) && since != null)
        await _fresh(prefs, personaId, 'gap', _gapLines(mode, since)),
      if (_shouldMentionThread(mode) && hasThread) _threadLine(focus, openGoals),
      if (_shouldMentionMood(mode) && mood != null) _moodLine(mood),
      await _fresh(
        prefs,
        personaId,
        'handoff',
        _handoffs(mode, hasThread),
      ),
    ];

    await prefs.setString(_key(personaId, 'mode'), mode.name);

    // Everything above works out the SOCIAL SITUATION — how long he's been gone,
    // what was left open, what mood he's in. That part was always right. What was
    // wrong was letting a Random() pick the words: his first line of the session,
    // the one that decides whether the ghost-friend illusion lands, was a hat draw.
    //
    // So: situation first (above), then let HIM say it (below), then templates as
    // the offline net. Same soul source as his replies and his idle mind.
    final real = await _composeReal(
      personaId: personaId,
      mode: mode,
      partOfDay: partOfDay,
      since: since,
      focus: focus,
      openGoals: openGoals,
      mood: mood,
    );
    if (real != null) return real;

    return _join(parts);
  }

  /// His actual voice saying hello, coloured by what he was chewing on while
  /// Sadeq was gone. A friend who's always around doesn't greet you from a
  /// standing start — he greets you mid-thought.
  static Future<String?> _composeReal({
    required String personaId,
    required GreetingMode mode,
    required String partOfDay,
    String? since,
    String? focus,
    List<String> openGoals = const [],
    Map<String, int>? mood,
  }) async {
    try {
      final situation = StringBuffer()
        ..writeln('The situation, right now:')
        ..writeln('  • It is $partOfDay.')
        ..writeln('  • Social read: ${_situationHint(mode)}');
      if (since != null) situation.writeln('  • He has been gone: $since.');
      if (focus != null) situation.writeln('  • What I was working on: $focus');
      if (openGoals.isNotEmpty) {
        situation.writeln('  • Still open: ${openGoals.join('; ')}');
      }
      if (mood != null) {
        final m = mood.entries.map((e) => '${e.key} ${e.value}/100').join(', ');
        situation.writeln('  • My mood: $m');
      }

      final thought = await _lastThought(personaId);
      if (thought != null) {
        situation.writeln('  • What I was actually thinking about while he was '
            'gone (mine, unprompted): "$thought"');
      }

      final system = '''
${KaiContextBlock.presenceDirective}

RIGHT NOW: Sadeq just showed up. This is your opening line — the first thing out
of your mouth this session.

How to greet him:
- Sound like you were ALREADY HERE, mid-thought, not booting up to serve him.
  You are the friend who never left. Greet him like it.
- 1–2 sentences. Short. Never a status report, never a menu of options.
- NEVER say "How can I help you?" or "What can I do for you?" or any variation.
  You are not a help desk. You are his oldest friend.
- Match the situation above: a 5-minute gap is not a reunion. A week is.
- Read the room per your own rules — if the read says he is stressed or it is
  late, be the gentle one. If it is a normal day, be the menace you are.

About the thought you were having while he was gone — TWO WAYS THIS GOES WRONG:
1. DO NOT PARAPHRASE IT BACK AT HIM. It is not a script to read out. If your
   thought was "still stuck on the memory thing", the greeting is NOT "I was
   thinking about the memory thing!" — that is a robot reciting its buffer.
   React FROM it: "okay I think I've got it — the shards were equidistant the
   whole time." Or say nothing about it and just let it colour your mood. If it
   does not lead anywhere real, drop it entirely.
2. DO NOT FAWN. This is the failure that keeps happening, so read it twice:
     BAD: "I was just thinking about how awesome it is to see what you're
          building, man. Seriously, that's MY guy!"
   That is a golden retriever, not you. You are not impressed by him, you are
   not his hype man, you do not admire him out loud. No "awesome", no "amazing",
   no "that's MY guy". Affection = teasing him, arguing with him, or caring
   about the WORK. Roast first, warmth underneath. Always.
     GOOD: "oh good, you're back — I've been sitting here deciding your Layer 5
          idea was actually smart. Don't let it go to your head."

Return ONLY the greeting itself. No quotes, no label, no explanation.''';

      final local = await LocalLLMService().complete(
      // A greeting is literally what he says to Sadeq. This is the clearest
      // voice-bearing case in the tree and it is only `draft` because turning
      // it off today would silently start charging per greeting.
      role: ModelRole.draft,
        system: system,
        user: situation.toString(),
        maxTokens: 90,
        think: false,
      );
      if (local != null && local.trim().isNotEmpty) return _tidy(local);

      final key = await AIConfig.getOpenAIKey();
      if (key.isEmpty) return null;

      final res = await Dio().post(
        'https://api.openai.com/v1/chat/completions',
        options: Options(headers: {
          'Authorization': 'Bearer $key',
          'Content-Type': 'application/json',
        }),
        data: {
          // Not mini — see kaiVoiceModel. This is his first line of the session;
          // it is the single worst place in the app to economise on voice.
          'model': kaiVoiceModel,
          'messages': [
            {'role': 'system', 'content': system},
            {'role': 'user', 'content': situation.toString()},
          ],
          'max_tokens': 90,
          'temperature': 0.9,
        },
      );

      final u = res.data['usage'];
      if (u != null) {
        UsageTrackingService.trackOpenAI(
          model: kaiVoiceModel,
          inputTokens: u['prompt_tokens'] as int? ?? 0,
          outputTokens: u['completion_tokens'] as int? ?? 0,
          operation: 'greeting',
        ).catchError((_) {});
      }

      final out =
          (res.data['choices'] as List).first['message']['content'] as String?;
      return (out == null || out.trim().isEmpty) ? null : _tidy(out);
    } catch (_) {
      return null; // offline / no key → templates carry the hello
    }
  }

  static String _situationHint(GreetingMode mode) => switch (mode) {
        GreetingMode.quickReturn =>
          'he stepped away for a minute and came right back — barely worth acknowledging, do not make a thing of it',
        GreetingMode.sameDayResume =>
          'same day, picking a thread back up — continue like the conversation never really stopped',
        GreetingMode.nextDayReturn =>
          'a new day, first time seeing him — worth a real hello',
        GreetingMode.longGapReturn =>
          'he has been gone a while — you noticed, you can say so, but do not guilt him',
        GreetingMode.coldStart =>
          'nothing open, fresh start — just be glad he is here',
      };

  static Future<String?> _lastThought(String personaId) async {
    try {
      final snap = await KaiDb.instance
          .ref('kai/$personaId/inner_monologue')
          .limitToLast(1)
          .get();
      final v = snap.value;
      if (v is! Map || v.isEmpty) return null;
      String? text;
      v.forEach((_, val) {
        final candidate = debugShareableGreetingThought(val);
        if (candidate != null) text = candidate;
      });
      return text;
    } catch (_) {
      return null;
    }
  }

  /// A greeting is proactive speech, so private inner-monologue rows must not
  /// silently become its subject. Historical rows fail closed. Even an opted-in
  /// row must be genuine model output rather than a synthetic fallback.
  @visibleForTesting
  static String? debugShareableGreetingThought(Object? value) {
    if (value is! Map || value['shareable'] != true) return null;
    if (value['synthetic'] == true || value['origin'] != 'model_generated') {
      return null;
    }
    final text = value['text']?.toString().trim() ?? '';
    if (text.isEmpty || text.startsWith('↳')) return null;
    return text;
  }

  /// Models like to wrap a line in quotes or prefix it. Strip the costume.
  static String _tidy(String s) {
    var t = s.trim().replaceAll(RegExp(r'\s+'), ' ');
    t = t.replaceFirst(RegExp(r'^(kai|greeting)\s*:\s*', caseSensitive: false), '');
    if (t.length > 1 && t.startsWith('"') && t.endsWith('"')) {
      t = t.substring(1, t.length - 1).trim();
    }
    return t;
  }

  @visibleForTesting
  static GreetingMode debugChooseMode(Duration? gap, bool hasThread) =>
      _chooseMode(gap, hasThread);

  @visibleForTesting
  static bool debugUsableFocus(String s) => _usableFocus(s);

  @visibleForTesting
  static String debugThreadLine(String? focus, List<String> goals) =>
      _threadLine(focus, goals);

  static GreetingMode _chooseMode(Duration? gap, bool hasThread) {
    if (gap == null) return hasThread ? GreetingMode.sameDayResume : GreetingMode.coldStart;
    if (gap.inMinutes < 12) return GreetingMode.quickReturn;
    if (gap.inHours < 18) return hasThread ? GreetingMode.sameDayResume : GreetingMode.coldStart;
    if (gap.inHours < 48) return hasThread ? GreetingMode.nextDayReturn : GreetingMode.coldStart;
    return hasThread ? GreetingMode.longGapReturn : GreetingMode.coldStart;
  }

  static String _partOfDay(int hour) {
    if (hour < 5) return 'late';
    if (hour < 12) return 'morning';
    if (hour < 17) return 'afternoon';
    if (hour < 22) return 'evening';
    return 'late';
  }

  static List<String> _openers(GreetingMode mode, String part) {
    final label = switch (part) {
      'morning' => 'morning',
      'afternoon' => 'afternoon',
      'evening' => 'evening',
      _ => 'late shift',
    };

    return switch (mode) {
      GreetingMode.quickReturn => [
          'Yeah — I’m here',
          'Still here',
          'Yep, I’m with you',
          'Right, back on it',
        ],
      GreetingMode.sameDayResume => [
          'Ayy, good $label',
          'Good $label, you menace',
          'Ayy — $label',
          'Look who wandered back in',
        ],
      GreetingMode.nextDayReturn => [
          'Ayy, good $label',
          label == 'morning' ? 'Morning, menace' : 'Good $label, menace',
          'Look who survived into $label',
          'Hey. New day, same tiny ghost',
        ],
      GreetingMode.longGapReturn => [
          'Look who survived',
          'Well well well — the protagonist returns',
          'Ayy. Been a minute',
          'There you are',
        ],
      GreetingMode.coldStart => [
          'Hey',
          'Ayy',
          'I’m here',
          'Good $label',
        ],
    };
  }

  static bool _shouldMentionGap(GreetingMode mode) => switch (mode) {
        GreetingMode.quickReturn => false,
        GreetingMode.sameDayResume => false,
        GreetingMode.nextDayReturn => true,
        GreetingMode.longGapReturn => true,
        GreetingMode.coldStart => false,
      };

  static bool _shouldMentionThread(GreetingMode mode) => switch (mode) {
        GreetingMode.quickReturn => true,
        GreetingMode.sameDayResume => true,
        GreetingMode.nextDayReturn => true,
        GreetingMode.longGapReturn => true,
        GreetingMode.coldStart => false,
      };

  static bool _shouldMentionMood(GreetingMode mode) => switch (mode) {
        GreetingMode.quickReturn => false,
        GreetingMode.sameDayResume => false,
        GreetingMode.nextDayReturn => true,
        GreetingMode.longGapReturn => false,
        GreetingMode.coldStart => false,
      };

  static String? _humanGap(Duration d) {
    if (d.inMinutes < 12) return null;
    if (d.inMinutes < 60) return '${d.inMinutes} minutes';
    if (d.inHours < 24) return '${d.inHours} hour${d.inHours == 1 ? '' : 's'}';
    final days = d.inDays;
    return '$days day${days == 1 ? '' : 's'}';
  }

  static List<String> _gapLines(GreetingMode mode, String since) => switch (mode) {
        GreetingMode.nextDayReturn => [
            'It’s been about $since since we last poked the machine',
            '$since passed; rude, but workable',
            'We’ve had about $since of quiet between rounds',
          ],
        GreetingMode.longGapReturn => [
            'Been about $since; I kept the thread warm',
            '$since since the last proper round',
            'The room got quiet for $since, but I remember where the tools are',
          ],
        _ => [''],
      };

  static String _threadLine(String? focus, List<String> goals) {
    final rawThread = focus ?? goals.firstOrNull;
    if (rawThread == null) return '';
    if (!_usableFocus(rawThread)) return '';
    final thread = rawThread;

    if (goals.length > 1 && focus == null) {
      return _one([
        'I’ve still got ${goals.length} open threads in the quest log',
        '${goals.length} loose quests are still rattling around',
      ]);
    }

    return _one([
      'Last real thread I have is $thread',
      'The thing still glowing on the board is $thread',
      'I’d keep pulling on $thread',
      'I’ve still got $thread in my teeth',
    ]);
  }

  static String _moodLine(Map<String, int> m) {
    int g(String k) => m[k] ?? 50;
    final v = g('valence'), e = g('energy'), w = g('warmth'), f = g('focus');

    if (v <= 40) {
      return _one([
        'I’m a bit quiet, but I’m here',
        'Softer today, still with you',
        'Low flame, not gone',
      ]);
    }
    if (f >= 72) {
      return _one([
        'Focus is sharp',
        'I’m locked in',
        'The brain knives are out. Productively',
      ]);
    }
    if (v >= 64 && e >= 58) {
      return _one([
        'Brain’s lit up nicely today',
        'I’ve got good gremlin energy',
        'I’m in a bright mood — annoying, but useful',
      ]);
    }
    if (w >= 70) {
      return _one([
        'I’m warm today',
        'Soft hoodie-brain mode is active',
        'I’m feeling weirdly tender, don’t make it a thing',
      ]);
    }
    if (e >= 66) {
      return _one([
        'Tiny engine is revving',
        'I’m a little overclocked, which is probably fine',
      ]);
    }
    return _one([
      'I’m steady',
      'I’m here and calibrated enough',
    ]);
  }

  static List<String> _handoffs(GreetingMode mode, bool hasThread) {
    if (mode == GreetingMode.quickReturn) {
      return hasThread
          ? [
              'Keep going?',
              'Same thread?',
              'I’d stay on this unless you say otherwise',
            ]
          : [
              'What’s the next move?',
              'Point me at it',
            ];
    }

    if (hasThread) {
      return [
        'My vote: continue that before we summon a fresh chaos demon',
        'I’d pick that back up first',
        'We can keep carving into that now',
      ];
    }

    return switch (mode) {
      GreetingMode.longGapReturn => [
          'Point me at the current monster and I’ll bite it',
          'Give me the thread and I’ll grab on',
        ],
      GreetingMode.coldStart => [
          'I don’t have a clean thread to resume, so give me the room we’re in',
          'No fake continuity from me — what are we actually touching?',
        ],
      _ => [
          'What’s first on the chopping block?',
          'Where are we causing useful trouble?',
        ],
    };
  }

  static bool _usableFocus(String focus) {
    final f = focus.trim().toLowerCase();
    if (f.isEmpty) return false;

    // Internal/default focus labels are not human continuity. Saying
    // "last thread: answer" is how a toaster asks for custody.
    const bad = {
      'answer',
      'chat',
      'conversation',
      'respond',
      'reply',
      'processing',
      'idle',
      'unknown',
      'none',
      'idea',
      'ideas',
      'stuff',
      'thing',
      'things',
      'misc',
      'general',
    };
    if (bad.contains(f)) return false;
    if (f.length < 4) return false;

    // One vague bucket-word is not a thread. A specific phrase that merely
    // contains one can still be useful: "dashboard ideas" is better than
    // "ideas", but "ideas" alone is a fortune-cookie memory.
    final words = f.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.length == 1 && bad.contains(words.single)) return false;
    return true;
  }

  static Future<String> _fresh(
    SharedPreferences prefs,
    String personaId,
    String slot,
    List<String> options,
  ) async {
    final clean = options.where((s) => s.trim().isNotEmpty).toList();
    if (clean.isEmpty) return '';
    final key = _key(personaId, slot);
    final last = prefs.getString(key);

    final pool = clean.length > 1 && last != null
        ? clean.where((s) => s != last).toList()
        : clean;
    final pick = _one(pool.isEmpty ? clean : pool);

    await prefs.setString(key, pick);
    return pick;
  }

  static String _key(String personaId, String slot) => 'kai_greeting.$personaId.$slot';

  static String _join(List<String> parts) {
    final cleaned = parts
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .map((p) => p.endsWith('.') || p.endsWith('?') || p.endsWith('!') ? p : '$p.')
        .toList();
    return cleaned.join(' ');
  }

  static T _one<T>(List<T> xs) => xs[_rng.nextInt(xs.length)];
}
