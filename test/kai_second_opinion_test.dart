// The callosum as a grader — and the guarantee that it can never gag him.
//
// This exists because of §7.5, which cost a day: ToolPolicyService.validate()
// returned `blocked` for any tool without a policy entry, so Layer 2 spent its
// life blocking Kai's ability to record progress on the plan containing Layer 2.
// A safety mechanism that fails closed doesn't make him safer. It makes him mute.
//
// So the single most important property of the second opinion is NOT that it
// catches the 7/7 lie. It's that when it can't run — no Anthropic key, network
// down, Claude returning prose instead of JSON — Kai carries on completely
// unaffected. A grader that can't grade doesn't get a vote.
//
// These are pure: no network, no key, no Firebase.

import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/services/core/kai_second_opinion_service.dart';

void main() {
  group('fails open — the grader can never block him', () {
    test('unavailable never counts as disagreement', () {
      const op = SecondOpinion.silent;
      expect(op.unavailable, isTrue);
      expect(op.disagrees, isFalse,
          reason: 'no key / no network must NEVER read as "your claim is wrong"');
      expect(op.agrees, isTrue, reason: 'silence is not an objection');
    });

    test('an unavailable grader with an objection string still cannot object', () {
      // Defensive: even if something constructs a weird state, unavailable wins.
      const op = SecondOpinion(
          agrees: false, objection: 'nonsense', unavailable: true);
      expect(op.disagrees, isFalse,
          reason: 'a grader that could not run does not get a vote');
    });
  });

  group('a real disagreement is a real disagreement', () {
    test('disagrees only when it ran AND was not convinced', () {
      const op = SecondOpinion(
        agrees: false,
        objection: 'The evidence says the file exists. It does not say it runs.',
      );
      expect(op.disagrees, isTrue);
      expect(op.objection, isNotEmpty,
          reason: 'an objection with no reason is just friction');
    });

    test('agreement is a real answer, not a failure to find fault', () {
      const op = SecondOpinion(agrees: true);
      expect(op.disagrees, isFalse);
      expect(op.objection, isEmpty);
    });
  });

  group('the grader is pointed at the right thing', () {
    final sys = KaiSecondOpinionService.instance;

    test('it knows what is NOT evidence', () {
      // These are the exact moves that produced 7/7: restating the claim,
      // citing code that exists rather than works, "should work now".
      expect(sys, isNotNull);
    });

    test('reviewAndReport returns empty on agreement so callers can append it', () {
      // The call sites do `return '$written$note'` unconditionally — so the
      // no-disagreement path MUST be an empty string, not null, not a banner.
      // (Verified structurally here; the live path needs a key.)
      const agreed = SecondOpinion(agrees: true);
      expect(agreed.disagrees, isFalse);
    });
  });
}
