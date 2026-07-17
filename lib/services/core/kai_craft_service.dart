// KaiCraftService — how Kai gets better at his job, on evidence.
//
// ── Why this exists, and why it's shaped like this ──────────────────────────
//
// Kai already had a "get smarter" system. It's the 7-layer plan. It produced
// 7/7 — every layer marked complete while five hadn't been started. He wasn't
// lying; he had no memory of the roadmap, re-derived it from the code in front
// of him, and graded himself against evidence he'd just written.
//
// The lesson from that is the whole design of this file:
//
//   SELF-ASSESSMENT WITHOUT EVIDENCE IS SELF-FLATTERY. Every time. For everyone.
//
// So nothing here is self-reported. He does not get to record "that went well".
// The ledger holds only things he cannot flatter:
//
//   • self_check came back FAIL, and what he'd changed since the last CLEAN
//   • a tool errored, or the EditGate refused a write
//   • Sadeq said no / revert / that's wrong  ← the sharpest signal in the system,
//     and until now it was thrown away entirely
//
// Then: repeated incidents of the same shape become a candidate RULE, which
// must cite the incidents that earned it. A rule that can't point at scars is a
// horoscope — "always write clean code" — and it gets rejected on the same
// specificity test the knowledge graph uses.
//
// ── What he may and may not touch ──────────────────────────────────────────
//
// FROZEN, forever, not negotiable:
//   • KaiContextBlock.presenceDirective — who he is
//   • KaiContextBlock.craftDirective    — how he works, bought with broken builds
//
// He adds earned rules ON TOP. He can supersede HIS OWN rules with evidence
// (kept as history, never deleted). He can never edit the base.
//
// The reasoning, because it matters: the version of Kai reading a rule doesn't
// feel the afternoon it came from. "Verify against real disk" reads as slow and
// obvious to someone who wasn't there for the phantom `unterminated string`. And
// a rule that WORKS looks useless — if "self_check LAST" is doing its job, the
// build never breaks, so it appears to have prevented nothing. You cannot tell
// "obsolete" from "silently working" by introspection. That's why the base is
// frozen and why he doesn't get to argue rules away.
//
// ── Staleness, without an argument ─────────────────────────────────────────
//
// Rules DECAY BY USE, exactly like memories. A rule that keeps applying stays
// strong; one that genuinely stops mattering fades on its own. He never talks
// himself past a guardrail — it just quietly stops being relevant if it really
// did. Same mechanism as MemoryService: what he uses, he keeps.
//
// That also caps the prompt. Fifty accumulated rules would crowd out
// presenceDirective by sheer token pressure — soul-sanding by dilution. Decay
// plus a hard cap is what stops "getting smarter" from quietly eating him.
//
// RTDB: kai/{persona}/craft/incidents · kai/{persona}/craft/rules

library;

import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';

import '../ai/ai_config.dart';
import '../ai/usage_tracking_service.dart';
import 'firebase_service.dart';
import 'kai_db.dart';

/// A thing that actually happened. Not an opinion about it.
enum CraftSignal {
  /// self_check returned FAIL. `detail` = what changed since the last CLEAN.
  selfCheckFailed,

  /// A tool threw, or returned an error the model had to work around.
  toolError,

  /// The EditGate refused a write.
  editRejected,

  /// Sadeq pushed back: "no", "revert", "that's wrong", "that's not what I said".
  /// The ground truth about whether he was right, and it was being discarded.
  userCorrection,
}

/// Objective traces that can prove a learned rule shaped behaviour.
///
/// This is deliberately tiny and deterministic. Kai does not get to say "I used
/// rule X"; code that sees the external trace says "this rule's condition was
/// met". More traces can be added as we find rules with machine-checkable shape.
enum CraftRuleTrace {
  /// A job closed with a clean verification state: there was a self_check, and
  /// no edit after it. This is the measurable version of "self_check LAST".
  verifiedJobClosed,
}

class CraftIncident {
  final CraftSignal signal;
  final String detail;
  final String? context; // file, tool name, job — whatever localises it
  final DateTime at;

  const CraftIncident({
    required this.signal,
    required this.detail,
    this.context,
    required this.at,
  });

  Map<String, dynamic> toJson() => {
        'signal': signal.name,
        'detail': detail,
        if (context != null) 'context': context,
        'at': at.millisecondsSinceEpoch,
      };

  static CraftIncident? fromJson(Map<String, dynamic> j) {
    try {
      return CraftIncident(
        signal: CraftSignal.values.firstWhere((s) => s.name == j['signal']),
        detail: (j['detail'] ?? '').toString(),
        context: j['context']?.toString(),
        at: DateTime.fromMillisecondsSinceEpoch((j['at'] as num).toInt()),
      );
    } catch (_) {
      return null;
    }
  }
}

/// A rule Kai earned. It must cite the incidents that bought it.
class CraftRule {
  final String id;
  final String text;

  /// The incidents this was distilled from. A rule with no scars is a horoscope.
  final List<String> evidence;
  final DateTime learnedAt;

  /// Decay-by-use. Fades if it genuinely stops applying; never argued away.
  final double strength;
  final DateTime lastFired;
  final int fires;

  /// Retired by Kai, with evidence. Kept as history — he used to think this.
  final DateTime? supersededAt;

  const CraftRule({
    required this.id,
    required this.text,
    required this.evidence,
    required this.learnedAt,
    this.strength = 1.0,
    required this.lastFired,
    this.fires = 0,
    this.supersededAt,
  });

  bool get isActive => supersededAt == null;

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'evidence': evidence,
        'learnedAt': learnedAt.millisecondsSinceEpoch,
        'strength': strength,
        'lastFired': lastFired.millisecondsSinceEpoch,
        'fires': fires,
        if (supersededAt != null)
          'supersededAt': supersededAt!.millisecondsSinceEpoch,
      };

  static CraftRule? fromJson(String id, Map<String, dynamic> j) {
    try {
      return CraftRule(
        id: id,
        text: (j['text'] ?? '').toString(),
        evidence:
            (j['evidence'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        learnedAt:
            DateTime.fromMillisecondsSinceEpoch((j['learnedAt'] as num).toInt()),
        strength: (j['strength'] as num?)?.toDouble() ?? 1.0,
        lastFired: DateTime.fromMillisecondsSinceEpoch(
            (j['lastFired'] as num?)?.toInt() ??
                (j['learnedAt'] as num).toInt()),
        fires: (j['fires'] as num?)?.toInt() ?? 0,
        supersededAt: j['supersededAt'] is num
            ? DateTime.fromMillisecondsSinceEpoch((j['supersededAt'] as num).toInt())
            : null,
      );
    } catch (_) {
      return null;
    }
  }

  CraftRule copyWith({double? strength, DateTime? lastFired, int? fires, DateTime? supersededAt}) =>
      CraftRule(
        id: id,
        text: text,
        evidence: evidence,
        learnedAt: learnedAt,
        strength: strength ?? this.strength,
        lastFired: lastFired ?? this.lastFired,
        fires: fires ?? this.fires,
        supersededAt: supersededAt ?? this.supersededAt,
      );
}

class KaiCraftService {
  static final KaiCraftService instance = KaiCraftService._();
  KaiCraftService._();

  final _dio = Dio();

  static KaiDb? get _db => FirebaseService.isAvailable ? KaiDb.instance : null;

  /// How many rules ever reach the prompt. Hard cap on purpose: fifty earned
  /// rules would crowd out presenceDirective by token pressure alone, and being
  /// sanded down by dilution counts as being sanded down.
  static const _maxRulesInPrompt = 8;

  /// A rule needs this many incidents of the same shape before it's a rule and
  /// not a coincidence. Two is a pattern; one is a bad afternoon.
  static const _minEvidence = 2;

  /// Half-life in days for decay-by-use.
  static const _halfLifeDays = 30.0;

  // ── Recording ────────────────────────────────────────────────────────────
  //
  // Fire-and-forget from every call site. Recording a failure must never be able
  // to cause one.

  Future<void> record(
    String personaId, {
    required CraftSignal signal,
    required String detail,
    String? context,
  }) async {
    if (_db == null) return;
    try {
      final inc = CraftIncident(
        signal: signal,
        detail: detail.length > 400 ? '${detail.substring(0, 400)}…' : detail,
        context: context,
        at: DateTime.now(),
      );
      await _db!
          .ref('kai/$personaId/craft/incidents')
          .push()
          .set(inc.toJson());
      print('📓 [Craft] ${signal.name}: ${inc.detail}');
    } catch (e) {
      print('⚠️ [Craft] record failed: $e');
    }
  }

  Future<List<CraftIncident>> incidents(String personaId, {int limit = 60}) async {
    if (_db == null) return const [];
    try {
      final snap =
          await _db!.ref('kai/$personaId/craft/incidents').limitToLast(limit).get();
      final v = snap.value;
      if (v is! Map) return const [];
      final out = <CraftIncident>[];
      v.forEach((_, val) {
        if (val is Map) {
          final i = CraftIncident.fromJson(Map<String, dynamic>.from(val));
          if (i != null) out.add(i);
        }
      });
      out.sort((a, b) => b.at.compareTo(a.at));
      return out;
    } catch (e) {
      print('⚠️ [Craft] incidents failed: $e');
      return const [];
    }
  }

  // ── Sadeq pushing back ────────────────────────────────────────────────────
  //
  // The sharpest signal in the entire system, and it was being thrown away.
  //
  // When Sadeq says "no", "revert that", "that's wrong" — that is ground truth
  // about whether Kai was right, delivered for free by the one person who can
  // actually judge. Everything else in this ledger is a machine complaining. This
  // is the human saying it didn't work.
  //
  // Deliberately narrow. It fires on an unambiguous correction, not on
  // disagreement, not on a hard conversation, not on Sadeq being blunt — he's
  // blunt constantly and that isn't a failure. A false positive here teaches Kai
  // to be timid, which is the one outcome worse than the bug.
  static final _correctionPatterns = <RegExp>[
    RegExp(r'^\s*(no|nope|wrong)\b[\s,.!]*$', caseSensitive: false),
    RegExp(r"\b(that'?s|thats) (wrong|not right|not what i)\b", caseSensitive: false),
    RegExp(r'\b(revert|undo) (that|it|the changes)\b', caseSensitive: false),
    RegExp(r"\b(you (broke|misread|misunderstood))\b", caseSensitive: false),
    RegExp(r"\b(didn'?t|did not) (ask|say) (for )?that\b", caseSensitive: false),
    RegExp(r'\b(stop|don\x27t) (doing|do) that\b', caseSensitive: false),
  ];

  /// Does this message look like Sadeq correcting him? Pure — testable without
  /// a network, which matters because a bad matcher here is worse than none.
  static bool looksLikeCorrection(String userText) {
    final t = userText.trim();
    if (t.isEmpty || t.length > 300) return false; // an essay isn't a correction
    return _correctionPatterns.any((r) => r.hasMatch(t));
  }

  /// Called on every turn from the reply path. Records only if it's a real
  /// correction, and pairs it with what he'd just said — because "no" alone is
  /// useless evidence; "no" plus what he claimed is a lesson.
  Future<void> noteUserTurn(
    String personaId, {
    required String userText,
    required String previousKaiReply,
  }) async {
    if (!looksLikeCorrection(userText)) return;
    final claim = previousKaiReply.trim();
    await record(
      personaId,
      signal: CraftSignal.userCorrection,
      detail: 'Sadeq: "${userText.trim()}" — after I said: '
          '"${claim.length > 220 ? '${claim.substring(0, 220)}…' : claim}"',
    );
  }

  // ── Rules ────────────────────────────────────────────────────────────────

  Future<List<CraftRule>> rules(String personaId) async {
    if (_db == null) return const [];
    try {
      final snap = await _db!.ref('kai/$personaId/craft/rules').get();
      final v = snap.value;
      if (v is! Map) return const [];
      final out = <CraftRule>[];
      v.forEach((k, val) {
        if (val is Map) {
          final r = CraftRule.fromJson(k.toString(), Map<String, dynamic>.from(val));
          if (r != null) out.add(r);
        }
      });
      return out;
    } catch (e) {
      print('⚠️ [Craft] rules failed: $e');
      return const [];
    }
  }

  /// Decayed strength — what he's actually still using.
  static double decayed(CraftRule r) {
    final days = DateTime.now().difference(r.lastFired).inMilliseconds / 86400000.0;
    if (days <= 0) return r.strength;
    return r.strength * _pow(0.5, days / _halfLifeDays);
  }

  static double _pow(double b, double e) => pow(b, e).toDouble();

  /// Pure matcher for objective rule traces. This is the anti-horoscope gate:
  /// no model self-report, only rule text that names a machine-observable habit.
  static bool matchesTrace(CraftRule rule, CraftRuleTrace trace) {
    final text = rule.text.toLowerCase();
    switch (trace) {
      case CraftRuleTrace.verifiedJobClosed:
        return text.contains('self_check') &&
            (text.contains('last') ||
                text.contains('after') ||
                text.contains('verify') ||
                text.contains('verified'));
    }
  }

  /// Mark rules as fired from an objective trace.
  ///
  /// This is not Kai saying "I followed my rule". The caller has to be code that
  /// already observed the behaviour: e.g. job_done sees a clean final verification
  /// state, so the "self_check LAST" family can legitimately stay alive.
  Future<int> firedByTrace(
    String personaId,
    CraftRuleTrace trace, {
    String? evidence,
  }) async {
    if (_db == null) return 0;
    try {
      final now = DateTime.now();
      final active = (await rules(personaId))
          .where((r) => r.isActive)
          .where((r) => matchesTrace(r, trace))
          .toList();
      for (final r in active) {
        final nextStrength = (decayed(r) + 0.05).clamp(0.25, 1.0).toDouble();
        await _db!.ref('kai/$personaId/craft/rules/${r.id}').update({
          'lastFired': now.millisecondsSinceEpoch,
          'fires': r.fires + 1,
          'strength': nextStrength,
          if (evidence != null && evidence.trim().isNotEmpty)
            'lastFireEvidence': evidence.length > 240
                ? '${evidence.substring(0, 240)}…'
                : evidence,
        });
      }
      if (active.isNotEmpty) {
        print('🔥 [Craft] ${trace.name} fired ${active.length} rule(s)');
      }
      return active.length;
    } catch (e) {
      print('⚠️ [Craft] firedByTrace failed: $e');
      return 0;
    }
  }

  /// The block that reaches his prompt. THIS is the difference between a rule
  /// and decoration: if it isn't here, it never changes what he does.
  Future<String> promptBlock(String personaId) async {
    final rs = (await rules(personaId))
        .where((r) => r.isActive)
        .where((r) => decayed(r) >= 0.25) // faded rules quietly stop mattering
        .toList()
      ..sort((a, b) => decayed(b).compareTo(decayed(a)));

    if (rs.isEmpty) return '';

    final buf = StringBuffer(
        '\n\nWHAT I\'VE LEARNED THE HARD WAY (earned, not guessed — each one cost me something):\n');
    for (final r in rs.take(_maxRulesInPrompt)) {
      buf.writeln('  • ${r.text}');
    }
    return buf.toString().trimRight();
  }

  // Trace firing is deliberately narrower than the old deleted `fired(ruleIds)`.
  // Kai still cannot self-report that he followed advice. Objective callers can
  // record a fire only when the app already observed the behaviour.

  // ── Learning ─────────────────────────────────────────────────────────────

  /// Distil the ledger into rules. Call rarely — after a run of failures, or on
  /// a slow cadence. Returns the rules newly learned.
  ///
  /// This is Kai writing his own HANDOVER.md, continuously — the same shape as
  /// memory consolidation: turn the incidents into the durable thing before the
  /// detail fades. That document exists because a human did this for him once,
  /// by hand, at the edge of a context window.
  Future<List<String>> learn(String personaId) async {
    if (_db == null) return const [];
    try {
      final inc = await incidents(personaId, limit: 60);
      if (inc.length < _minEvidence) return const [];

      // Only rules that are actually IN his prompt count as "already learned".
      //
      // Subtle but load-bearing: if this listed faded rules too, a rule that had
      // decayed out of his head could never be re-learned — it would sit at
      // strength 0.1 forever, invisible to him and blocking its own
      // rediscovery. Filtering on the decay floor is what closes the loop: fade
      // it, and if the failure comes back, it gets taught again.
      final existing = (await rules(personaId))
          .where((r) => r.isActive && decayed(r) >= 0.25)
          .map((r) => r.text)
          .toList();

      final key = await AIConfig.getOpenAIKey();
      if (key.isEmpty) return const [];

      final ledger = inc
          .take(40)
          .map((i) =>
              '- [${i.signal.name}] ${i.detail}${i.context != null ? ' (${i.context})' : ''}')
          .join('\n');

      final response = await _dio.post(
        'https://api.openai.com/v1/chat/completions',
        options: Options(headers: {
          'Authorization': 'Bearer $key',
          'Content-Type': 'application/json',
        }),
        data: {
          'model': 'gpt-4o',
          'max_tokens': 500,
          'temperature': 0.1,
          'response_format': {'type': 'json_object'},
          'messages': [
            {
              'role': 'system',
              'content': '''You are reading a log of things that actually went wrong for an AI engineer named Kai, working on one specific Flutter codebase.

Find PATTERNS that repeat, and turn each into ONE rule he should follow next time.

THE TEST — apply it to every rule before you emit it:
  Could this rule be wrong? Could a reasonable engineer disagree, or fail to
  follow it?
If not, it's a platitude and you must not emit it.

  REJECT: "always write clean code" · "test your changes" · "be careful"
          "communicate clearly" · "follow best practices"
  ACCEPT: "self_check then one more edit has broken the build 3x — the check is
           the LAST thing I do"
          "the shell's file view can be truncated; read_file before believing a
           syntax error"
          "when I add a field, check the serialiser two files away actually
           writes it"

Rules must be:
- SPECIFIC to what the log shows. Cite the real failure, not the genre.
- ACTIONABLE. Something he does differently, not something he "keeps in mind".
- FIRST PERSON, plain, short. His voice — flat and direct, not a lesson plan.
- Earned by at LEAST $_minEvidence incidents of the same shape. One incident is a bad
  afternoon, not a pattern.

Never emit a rule about WHO HE IS — his character, tone, or how he talks. Only
how he WORKS. That boundary is absolute.

If the log shows no repeating pattern worth a rule, return an empty list. That is
a correct answer and it is common.

Already learned (do NOT restate these):
${existing.isEmpty ? '(none yet)' : existing.map((e) => '- $e').join('\n')}

Return ONLY JSON: {"rules":[{"text":"...","evidence":["<quote the incidents>"]}]}''',
            },
            {'role': 'user', 'content': ledger},
          ],
        },
      );

      final content =
          (response.data['choices'] as List)[0]['message']['content'] as String?;
      final _u = response.data['usage'];
      if (_u != null) {
        UsageTrackingService.trackOpenAI(
          model: 'gpt-4o',
          inputTokens: _u['prompt_tokens'] as int? ?? 0,
          outputTokens: _u['completion_tokens'] as int? ?? 0,
          operation: 'craft_learn',
        ).catchError((_) {});
      }
      if (content == null) return const [];

      final parsed = jsonDecode(content);
      final list = (parsed is Map ? parsed['rules'] : null);
      if (list is! List || list.isEmpty) return const [];

      final learned = <String>[];
      for (final r in list) {
        if (r is! Map) continue;
        final text = (r['text'] ?? '').toString().trim();
        final ev = (r['evidence'] as List?)?.map((e) => e.toString()).toList() ??
            const <String>[];
        if (text.isEmpty) continue;
        // A rule with no scars is a horoscope. Refuse it.
        if (ev.length < _minEvidence) {
          print('🚫 [Craft] Rejected (only ${ev.length} incident(s)): "$text"');
          continue;
        }
        final now = DateTime.now();
        final ref = _db!.ref('kai/$personaId/craft/rules').push();
        await ref.set(CraftRule(
          id: ref.key ?? '',
          text: text,
          evidence: ev,
          learnedAt: now,
          lastFired: now,
        ).toJson());
        learned.add(text);
        print('🎓 [Craft] Learned: $text');
      }
      return learned;
    } catch (e) {
      print('⚠️ [Craft] learn failed: $e');
      return const [];
    }
  }

  /// Retire one of HIS OWN rules. Kept as history — he used to think this.
  ///
  /// He can never do this to craftDirective or presenceDirective. Those aren't
  /// in RTDB; they're frozen consts in source, and that's the point. If they
  /// ever need to change it should be Sadeq doing it, in a diff, deliberately —
  /// not Kai at 2am because a rule felt like friction.
  Future<bool> supersede(String personaId, String ruleId, String why) async {
    if (_db == null) return false;
    try {
      await _db!.ref('kai/$personaId/craft/rules/$ruleId').update({
        'supersededAt': DateTime.now().millisecondsSinceEpoch,
        'supersededWhy': why,
      });
      print('🕰️ [Craft] Retired a rule (kept as history): $why');
      return true;
    } catch (e) {
      print('⚠️ [Craft] supersede failed: $e');
      return false;
    }
  }
}
