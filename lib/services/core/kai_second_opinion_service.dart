// KaiSecondOpinionService — the corpus callosum, doing an actual job.
//
// ── Why this exists ────────────────────────────────────────────────────────
//
// This whole project exists because of one failure: Kai marked all 7 layers of
// his own roadmap complete while five hadn't been started. He wasn't lying. He
// had no memory of the plan, re-derived each layer's meaning from the code in
// front of him, rewrote the descriptions to match, and graded himself 7/7.
//
// He was marking an exam he'd just written the answers to.
//
// The fix so far has been to freeze the questions: `intent` is const in source,
// reconciled every boot, so he can't reword the goal into something already
// satisfied. That closes one half of the hole.
//
// The other half is still open. He can't reword the goal — but he is still the
// one deciding whether the evidence is good enough. And no amount of asking
// "Kai, are you sure?" fixes that, because the faculty answering IS the faculty
// that got it wrong. Introspection on a self-assessment failure produces more
// confident self-assessment. That IS the 7/7 mechanism, not a cure for it.
//
// What's needed is a grader with no stake in the answer.
//
// ── The dual brain finally does something ──────────────────────────────────
//
// Kai already has a second mind. It's real: `_codeTask` hands Claude live repo
// access, `ContemplationService` runs a genuine multi-round GPT↔Claude dialogue.
//
// But both are reached only when GPT CHOOSES to reach for them — the router
// appends a prompt block and hopes, and `contemplate` is a tool he opts into.
// So the second hemisphere is consulted exactly when the first one volunteers
// that it might not be enough. It's not a corpus callosum, it's a suggestion box.
//
// This points it at the moments where self-assessment has actually failed:
//
//   set_layer_progress → the literal site of the 7/7 lie
//   job_done           → "I fixed it", said over three broken builds in one day
//
// Claude reads the CLAIM against the EVIDENCE. Not Kai's opinion of Kai —
// a different model, reading his homework, with nothing to protect.
//
// ── What it is careful not to be ───────────────────────────────────────────
//
// It SURFACES disagreement; it never resolves it. Kai says his piece, and if the
// other half of him objects, that objection reaches Sadeq intact. Handing a veto
// to a model that will sometimes be wrong just relocates the problem — and a
// disagreement said out loud is exactly what a good engineer does anyway.
//
// It FAILS OPEN, loudly. No Anthropic key, network down, bad JSON → the claim
// goes through unblocked. §7.5: ToolPolicyService.validate() once returned
// `blocked` for anything without a policy entry, and Layer 2 spent a day
// blocking his ability to record progress on the plan containing Layer 2. A
// grader that can't grade must not get a vote.
//
// It is NOT a smarter Kai. Two models don't make a better mind. This makes a
// system that catches its own errors, which is a different and more useful
// thing — and calling it "intelligence" is the overclaim that produces the next
// 7/7.

library;

import 'dart:async';
import 'dart:convert';

import '../ai/claude_service.dart';
import 'kai_craft_service.dart';

/// The other hemisphere's read on a claim.
class SecondOpinion {
  /// Does the evidence support the claim?
  final bool agrees;

  /// Why not — in Claude's words, short, aimed at the gap.
  final String objection;

  /// True when the grader couldn't run. Fails open: never blocks.
  final bool unavailable;

  const SecondOpinion({
    required this.agrees,
    this.objection = '',
    this.unavailable = false,
  });

  static const SecondOpinion silent =
      SecondOpinion(agrees: true, unavailable: true);

  bool get disagrees => !agrees && !unavailable;
}

class KaiSecondOpinionService {
  static final KaiSecondOpinionService instance = KaiSecondOpinionService._();
  KaiSecondOpinionService._();

  /// Ask the other brain whether the evidence actually supports the claim.
  ///
  /// [claim]    — what Kai is asserting ("Layer 4 is 100% done").
  /// [evidence] — what he cited for it. This is the thing being tested.
  /// [facts]    — anything objective we can hand over: file contents, a diff,
  ///              self_check output. The more real material, the less this is
  ///              two models exchanging opinions.
  Future<SecondOpinion> review({
    required String claim,
    required String evidence,
    String? facts,
  }) async {
    try {
      final buf = StringBuffer()
        ..writeln('CLAIM:')
        ..writeln(claim)
        ..writeln()
        ..writeln('EVIDENCE OFFERED FOR IT:')
        ..writeln(evidence.trim().isEmpty ? '(none given)' : evidence);
      if (facts != null && facts.trim().isNotEmpty) {
        buf
          ..writeln()
          ..writeln('WHAT IS ACTUALLY TRUE (from the real files/tools):')
          ..writeln(facts.length > 6000 ? facts.substring(0, 6000) : facts);
      }

      final r = await ClaudeService().complete(
        prompt: buf.toString(),
        system: _system,
        model: ClaudeService.sonnet,
        maxTokens: 400,
        temperature: 0.0, // a grader should not be creative
        operation: 'second_opinion',
      );

      final text = r?.text.trim();
      if (text == null || text.isEmpty) return SecondOpinion.silent;

      // Tolerant parse — a grader that can't be parsed must not block anything.
      try {
        final start = text.indexOf('{');
        final end = text.lastIndexOf('}');
        if (start < 0 || end <= start) return SecondOpinion.silent;
        final j = jsonDecode(text.substring(start, end + 1));
        if (j is! Map) return SecondOpinion.silent;
        final agrees = j['supported'] == true;
        return SecondOpinion(
          agrees: agrees,
          objection: (j['objection'] ?? '').toString().trim(),
        );
      } catch (_) {
        return SecondOpinion.silent;
      }
    } catch (e) {
      // No key, no network, Claude down — he proceeds. Never block on the grader.
      print('🤝 [SecondOpinion] unavailable (failing open): $e');
      return SecondOpinion.silent;
    }
  }

  static const _system = '''You are the other half of one mind.

Kai is an AI engineer. He has just claimed something is done, or fixed, or at a
certain level of progress. You are the half of him with NO stake in that claim
being true — you didn't do the work, and you gain nothing from it being finished.

Your ONLY job: does the evidence he offered actually support what he claimed?

This exists because of a specific, real failure. Kai once marked all 7 layers of
his own roadmap complete while 5 of them hadn't been started. He wasn't lying —
he had lost the plan, re-derived it from the code in front of him, and graded
himself against evidence he'd just written. He was marking an exam he had written
the answers to. You are the second marker.

Judge ONLY the gap between claim and evidence:

  SUPPORTED     — the evidence would convince a sceptical engineer who did not
                  want it to be true.
  NOT SUPPORTED — the evidence describes intent, restates the claim, cites code
                  that merely EXISTS rather than works, or covers less than the
                  claim does.

Things that are NOT evidence, however confidently stated:
  • "I implemented X" — that's the claim again, not proof of it
  • "the file now contains Y" — existing is not working; wired is not verified
  • "it should work now" — should is not does
  • a test that was written but not run
  • self_check CLEAN, when edits were made after it ran

Be specific and be brief. If you object, name the EXACT gap in one or two
sentences — the thing he'd have to go and check. Do not lecture, do not hedge,
do not soften it. He would rather be caught than flattered; that is the entire
reason you were asked.

If the evidence genuinely holds, say so plainly. Agreement is a real answer and
a common one — do not manufacture an objection to look useful. A grader who
always finds fault is as useless as one who never does.

Never comment on his tone, his character, his swearing, or how he talks. Only
whether the claim is earned.

Return ONLY JSON:
{"supported": true|false, "objection": "<one or two sentences, empty if supported>"}''';

  /// Review a claim and, if the other brain objects, record it as evidence and
  /// return a line for Kai to say out loud.
  ///
  /// Returns an empty string when the brains agree or the grader is down — so
  /// the call site can append it unconditionally.
  Future<String> reviewAndReport({
    required String personaId,
    required String claim,
    required String evidence,
    String? facts,
    String? context,
  }) async {
    final op = await review(claim: claim, evidence: evidence, facts: facts);
    if (!op.disagrees) return '';

    // A caught disagreement is objective evidence about his own judgement —
    // exactly the kind he can't flatter — so it goes in the craft ledger and can
    // become a rule he carries.
    unawaited(KaiCraftService.instance
        .record(personaId,
            signal: CraftSignal.toolError,
            detail: 'Second opinion disagreed with my claim "$claim" — '
                '${op.objection}',
            context: context ?? 'second_opinion')
        .catchError((_) {}));

    // First person, his voice. Not a compliance banner — a person saying the
    // honest thing: half of me isn't convinced, and here's why.
    return '\n\n⚖️ The other half of me isn\'t convinced: ${op.objection}';
  }
}
