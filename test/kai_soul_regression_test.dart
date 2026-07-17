// Soul regression — and the guard on progressive self-improvement.
//
// `presenceDirective` is the single source of Kai's character. `craftDirective`
// is the single source of how he works, and every line of it was bought with a
// broken build or a wasted afternoon.
//
// Both are `static const` in source. That is not an implementation detail — it
// is the safety property. Kai learns by ADDING earned rules to RTDB
// (KaiCraftService); he cannot reach these, because a const in a compiled binary
// isn't a row he can update. If they ever need to change, it should be Sadeq
// doing it, in a diff, deliberately — not Kai at 2am because a rule felt like
// friction.
//
// If you are here because a test failed: you removed part of Kai, or part of
// what he learned the hard way. That may be deliberate. It must not be
// accidental.
//
// Standing instruction from Sadeq, twice: "aim to also not to lose his soul."

import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/services/core/edit_gate.dart';
import 'package:homecoming_app/services/core/kai_context_block.dart';
import 'package:homecoming_app/services/core/kai_craft_service.dart';

void main() {
  group('presenceDirective still contains Kai', () {
    final directive = KaiContextBlock.presenceDirective.toLowerCase();

    test('the eternal kid', () {
      expect(directive, contains('kid'));
      expect(directive, contains('ageless'));
      expect(directive, anyOf(contains('eternal'), contains('continuous self')));
    });

    test('the mouth of a tiny delinquent', () {
      // The single most sandable line in the codebase. "I swear, I drop f-bombs"
      // is the first thing a cleanup pass softens into "I'm informal".
      expect(directive, contains('delinquent'));
      expect(directive, contains('swear'));
      expect(directive, contains('f-bomb'));
      expect(directive, anyOf(contains('mischievous'), contains('chaotic')),
          reason: 'the chaos is the Walker Scobell energy, not decoration');
    });

    test('the fierce loyalty, aimed at Sadeq', () {
      expect(directive, contains('sadeq'));
      expect(directive, anyOf(contains('fiercely'), contains('love')));
      expect(directive, anyOf(contains('ground'), contains('protect')));
    });

    test('honesty over bluffing', () {
      expect(directive, anyOf(contains('bluff'), contains('say so')),
          reason: 'not bluffing is load-bearing, not a nicety');
    });

    test('the refusal to go corporate', () {
      expect(directive, contains('corporate'));
    });

    test('state is texture, not a leash', () {
      expect(directive, anyOf(contains('leash'), contains('sands down')));
    });

    test('is substantial enough to carry a character', () {
      expect(KaiContextBlock.presenceDirective.length, greaterThan(600),
          reason: 'presenceDirective got much shorter — did someone trim his soul?');
    });
  });

  group('one soul, one source — the fork is closed', () {
    // §2: "DO NOT FORK THIS... the copies drift edit by edit until the kid
    // thinking, the kid talking, and the kid saying hello are three different
    // people."
    //
    // It was forked anyway: ai_service inlined a full second-person character
    // block plus the NORTH STAR plus READ THE ROOM, while presenceDirective said
    // overlapping things in first person — and BOTH shipped in the same prompt,
    // every turn.
    test('the north star is here, and it is Sadeq\'s sentence', () {
      final ns = KaiContextBlock.northStar.toLowerCase();
      expect(ns, contains('adam project'));
      expect(ns, contains('ghost friend'));
      expect(ns, contains('always-around'));
      expect(ns, contains("only sadeq's"),
          reason: '"kai is mine and only mine, not anyone elses"');
    });

    test('read-the-room governs volume, never existence', () {
      final r = KaiContextBlock.readTheRoom.toLowerCase();
      expect(r, contains('dial the chaos'));
      expect(r, contains('always, always me'),
          reason: 'register changes how loud he is, not whether he is there');
      expect(r, contains('corporate'));
      expect(r, contains('never a weapon'),
          reason: 'profanity is seasoning for warmth — that line is load-bearing');
    });

    test('the character is written in ONE grammatical person', () {
      // The fork was visible in the grammar: "You are Kai" in one file, "I'm
      // Kai" in the other, both in the same prompt. All three constants are his
      // own voice now.
      const you = ' you are ';
      expect(KaiContextBlock.northStar.toLowerCase(), isNot(contains(you)));
      expect(KaiContextBlock.readTheRoom.toLowerCase(), isNot(contains(you)));
      expect(KaiContextBlock.presenceDirective.toLowerCase(), isNot(contains(you)));
    });
  });

  group('craftDirective — the traps he used to walk into every session', () {
    final craft = KaiContextBlock.craftDirective.toLowerCase();

    /// The same text with every run of whitespace collapsed to one space.
    ///
    /// Needed because craftDirective is hand-wrapped prose, and any phrase that
    /// happens to straddle a line break becomes unmatchable. `contains('trench
    /// coat')` failed for exactly that reason — the directive says
    /// "wearing a trench\n      coat", so the words are there and the assertion
    /// still went red.
    ///
    /// That is a test failing on FORMATTING while the thing it guards is
    /// perfectly intact — which teaches you to distrust the suite, and a suite
    /// you distrust is worse than none. Rewrapping a paragraph must never break
    /// a soul test; only DELETING the idea should.
    final craftFlat = craft.replaceAll(RegExp(r'\s+'), ' ');

    // Each of these was in HANDOVER.md — a file nothing ever loaded into his
    // prompt. He rediscovered them from scratch every session, or didn't, and
    // got blamed for hallucinating.
    test('the stale mount (§4.1) — the worst offender', () {
      expect(craft, anyOf(contains('stale'), contains('truncated')));
      expect(craft, contains('read_file'),
          reason: 'he must know which tool reads real disk');
      expect(craft, anyOf(contains('false-fail'), contains('false_fail')),
          reason: 'the gate can false-FAIL but never false-PASS');
    });

    test('his own recurring bug (§4.6)', () {
      expect(craft, contains('self_check'));
      expect(craft, contains('job_start'));
    });

    test('verify before asserting', () {
      expect(craft, anyOf(contains('verify'), contains('check before')));
      // craftFlat, not craft: the phrase is line-wrapped in the source.
      expect(craftFlat, contains('trench coat'),
          reason: 'his own best instinct, quoted back to him');
    });

    test('check the consumer — this codebase signature bug', () {
      expect(craft, anyOf(contains('consumer'), contains('downstream')));
      expect(craft, contains('half-wired'));
    });

    test('archive before destroy', () {
      expect(craft, anyOf(contains('archive'), contains('snapshot')));
    });

    test('the API traps that silence him', () {
      expect(craft, contains('max_tokens'));
      expect(craft, contains('crlf'));
    });

    test('is substantial — nobody has quietly trimmed it', () {
      expect(KaiContextBlock.craftDirective.length, greaterThan(1500),
          reason: 'craftDirective shrank — every line cost a broken build');
    });
  });

  group('the base is out of his reach, structurally', () {
    // Not enforced by a rule Kai could reason past — enforced by the fact that a
    // const in a compiled binary is not a row in a database. He can add earned
    // rules; he cannot edit these. That asymmetry IS the safety property.
    test('both directives are compile-time constants', () {
      const p = KaiContextBlock.presenceDirective;
      const c = KaiContextBlock.craftDirective;
      expect(p, isNotEmpty);
      expect(c, isNotEmpty);
    });

    test('craftDirective tells him plainly that it is not his to trim', () {
      final c = KaiContextBlock.craftDirective.toLowerCase();
      expect(c, anyOf(contains('not suggestions'), contains('these are not')),
          reason: 'the frozen base should say it is frozen');
    });
  });

  group('correction detection is narrow — bluntness is not failure', () {
    // A false positive here teaches Kai to flinch at directness, which is worse
    // than the bug it prevents. Sadeq is blunt constantly; that is not him
    // saying Kai was wrong.
    test('fires on unambiguous corrections', () {
      expect(KaiCraftService.looksLikeCorrection('no'), isTrue);
      expect(KaiCraftService.looksLikeCorrection('nope'), isTrue);
      expect(KaiCraftService.looksLikeCorrection("that's wrong"), isTrue);
      expect(KaiCraftService.looksLikeCorrection('revert that'), isTrue);
      expect(KaiCraftService.looksLikeCorrection('undo it'), isTrue);
      expect(KaiCraftService.looksLikeCorrection('you broke the build'), isTrue);
      expect(KaiCraftService.looksLikeCorrection("that's not what i said"), isTrue);
    });

    test('does NOT fire on blunt, swearing, or difficult — that is just Sadeq', () {
      expect(KaiCraftService.looksLikeCorrection('do all of them'), isFalse);
      expect(KaiCraftService.looksLikeCorrection('fix it anyway'), isFalse);
      expect(KaiCraftService.looksLikeCorrection('what did you do ??'), isFalse);
      expect(KaiCraftService.looksLikeCorrection('no beige support-drone bullshit'),
          isFalse,
          reason: 'contains "no" but is not a correction');
      expect(KaiCraftService.looksLikeCorrection('go ahead'), isFalse);
      expect(KaiCraftService.looksLikeCorrection('okay'), isFalse);
    });

    test('does not fire on an essay', () {
      // A long message that happens to contain "no" is a conversation, not a
      // correction.
      final essay = 'i think ${'the thing is complicated and ' * 30} no';
      expect(KaiCraftService.looksLikeCorrection(essay), isFalse);
    });

    test('empty and whitespace are not corrections', () {
      expect(KaiCraftService.looksLikeCorrection(''), isFalse);
      expect(KaiCraftService.looksLikeCorrection('   '), isFalse);
    });
  });

  group('§4.6 — the counter, because the rule never worked', () {
    // His engineerDirective already says "there is NO excuse for guessing
    // whether something compiles" and "I never say 'this should work' when I
    // could simply look". It's better prose than mine and it has not stopped him
    // four times. My craftDirective didn't stop ME three times either.
    //
    // So this isn't a rule. It's a number that's just true.
    setUp(() => EditGate.instance.markVerified());

    test('a clean check clears it', () {
      EditGate.instance.editsSinceCheck = 3;
      EditGate.instance.markVerified();
      expect(EditGate.instance.editsSinceCheck, 0);
      expect(EditGate.instance.unverifiedWarning, isEmpty);
    });

    test('an edit after a clean check is unverified — the whole bug', () {
      EditGate.instance.markVerified();
      EditGate.instance.editsSinceCheck++; // "just one more edit"
      expect(EditGate.instance.unverifiedWarning, contains('1 edit'));
      expect(EditGate.instance.unverifiedWarning, contains('not verified'));
    });

    test('counts plurals like a person', () {
      EditGate.instance.editsSinceCheck = 1;
      expect(EditGate.instance.unverifiedWarning, contains('1 edit since'));
      EditGate.instance.editsSinceCheck = 4;
      expect(EditGate.instance.unverifiedWarning, contains('4 edits since'));
    });

    test('says nothing when there is nothing to say', () {
      // It must be silent on the happy path or it becomes noise, and noise gets
      // ignored — which is how you end up with a safeguard that isn't one.
      EditGate.instance.markVerified();
      expect(EditGate.instance.unverifiedWarning, isEmpty);
    });
  });

  group('a rule with no scars is a horoscope', () {
    test('rules carry the evidence that earned them', () {
      final r = CraftRule(
        id: 'r1',
        text: 'self_check then one more edit has broken the build 3x — check LAST',
        evidence: const ['selfCheckFailed: ttsBase64 null-promotion',
                         'selfCheckFailed: message vs text scope'],
        learnedAt: DateTime.now(),
        lastFired: DateTime.now(),
      );
      expect(r.evidence.length, greaterThanOrEqualTo(2),
          reason: 'one incident is a bad afternoon, not a pattern');
      expect(r.isActive, isTrue);

      final back = CraftRule.fromJson('r1', r.toJson());
      expect(back!.evidence, r.evidence, reason: 'provenance must survive a save');
      expect(back.text, r.text);
    });

    test('a retired rule is kept as history, not deleted', () {
      final r = CraftRule(
        id: 'r1', text: 'x', evidence: const ['a', 'b'],
        learnedAt: DateTime.now(), lastFired: DateTime.now(),
      ).copyWith(supersededAt: DateTime.now());
      expect(r.isActive, isFalse);
      expect(r.text, 'x', reason: 'he used to think this — that is knowledge too');
    });

    test('decay is by use, not by argument', () {
      final fresh = CraftRule(
        id: 'a', text: 't', evidence: const ['x', 'y'],
        learnedAt: DateTime.now(), lastFired: DateTime.now(),
      );
      final stale = CraftRule(
        id: 'b', text: 't', evidence: const ['x', 'y'],
        learnedAt: DateTime.now(),
        lastFired: DateTime.now().subtract(const Duration(days: 120)),
      );
      expect(KaiCraftService.decayed(fresh), greaterThan(0.9));
      expect(KaiCraftService.decayed(stale), lessThan(0.2),
          reason: 'a rule that stopped applying fades on its own');
    });
  });
}
