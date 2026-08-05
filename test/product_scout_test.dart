// Tests for product_scout.dart — the scoring spine of Kai's gap scouting.
//
// The cases below are NOT invented. They are the real candidates from the live
// research run on 2026-07-19, with their actual citations, so the tests double
// as the worked examples Kai learns the method from.
//
// The most important tests here are the REFUSALS. Anyone can write a scorer
// that returns a winner; the whole value of this module is that it returns an
// empty hand when the evidence isn't there.

import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/logic/product_scout.dart';

void main() {
  // ── The real run: CodeCanyon Flutter templates ─────────────────────────────
  final codeCanyon = Candidate(
    name: 'Flutter templates on CodeCanyon',
    market: 'developer tools',
    evidence: const [
      Evidence(
        kind: EvidenceKind.competitorCount,
        source: 'https://codecanyon.net/category/mobile/flutter',
        claim: '3,800+ Flutter items already listed',
        value: 3800,
      ),
      Evidence(
        kind: EvidenceKind.paidPrice,
        source: 'https://codecanyon.net/popular_item/by_category',
        claim: 'top sellers priced \$39-79',
        value: 79,
      ),
      Evidence(
        kind: EvidenceKind.salesCount,
        source: 'https://codecanyon.net/popular_item/by_category',
        claim: 'single-digit weekly sales on best sellers',
        value: 11,
      ),
    ],
    scores: {
      Axis.distribution: 4, // real marketplace search traffic
      Axis.monetization: 3, // people do pay, but low
      Axis.headroom: 1, // 3,800 competitors
      Axis.feasibility: 5, // he could ship this in days
      Axis.operatorFit: 4, // he ships Flutter apps; he could explain a template
    },
  );

  // ── The real run: AI-agent boilerplate ─────────────────────────────────────
  final boilerplate = Candidate(
    name: 'AI-agent app boilerplate',
    market: 'developer tools',
    evidence: const [
      Evidence(
        kind: EvidenceKind.revenueReport,
        source: 'https://shipfa.st/',
        claim: '8,300+ buyers; creator reportedly ~\$45k/month',
        value: 45000,
      ),
      Evidence(
        kind: EvidenceKind.paidPrice,
        source: 'https://www.buildmvpfast.com/blog/best-saas-boilerplate-starter-kit-2026-nextjs',
        claim: 'boilerplates sell direct at \$199-299',
        value: 249,
      ),
      Evidence(
        kind: EvidenceKind.complaint,
        source: 'https://www.forbes.com/councils/forbestechcouncil/2026/07/14/',
        claim: 'agentic devs report up to 50x cost overruns',
        value: 50,
      ),
      Evidence(
        kind: EvidenceKind.complaint,
        source: 'https://www.morphllm.com/llm-cost-optimization',
        claim: 'only 22% of orgs track AI spend per transaction',
        value: 22,
      ),
      Evidence(
        kind: EvidenceKind.marketSize,
        source: 'https://designrevision.com/blog/best-saas-starter-kits',
        claim: 'boilerplate market \$50M+ annually',
        value: 50,
      ),
    ],
    scores: {
      Axis.distribution: 3,
      Axis.monetization: 5,
      Axis.headroom: 3,
      Axis.feasibility: 4,
      // Scored as it was BEFORE the operator's verdict, so this test keeps
      // exercising promotion mechanics. The real-world operatorFit for this
      // candidate turned out to be 1 — see the dedicated gate tests below.
      Axis.operatorFit: 4,
    },
  );

  group('structural kills', () {
    test('saturation kills a candidate with excellent distribution', () {
      final r = scoreCandidate(codeCanyon);
      expect(r.verdict, Verdict.killed);
      expect(r.reasons.join(' '), contains('Market already served'));
    });

    test('a single credible source is enough to decline', () {
      // All three CodeCanyon citations share one domain. Killing must NOT
      // require the corroboration that claiming does.
      expect(codeCanyon.distinctSources, 1);
      expect(scoreCandidate(codeCanyon).verdict, Verdict.killed);
    });

    test('a missing axis scores zero — silence is not a pass', () {
      final silent = Candidate(
        name: 'Unscored',
        market: 'x',
        evidence: const [
          Evidence(kind: EvidenceKind.paidPrice, source: 'https://a.com', claim: '\$99'),
          Evidence(kind: EvidenceKind.salesCount, source: 'https://b.com', claim: '500 sold'),
        ],
        scores: {Axis.monetization: 5, Axis.feasibility: 5}, // distribution absent
      );
      expect(scoreCandidate(silent).verdict, Verdict.killed);
    });
  });

  group('refusals — the point of the module', () {
    test('perfect scores with zero evidence are REFUSED, not rated weak', () {
      final vibes = Candidate(
        name: 'A vibes-based idea',
        market: 'x',
        scores: {
          Axis.distribution: 5,
          Axis.monetization: 5,
          Axis.headroom: 5,
          Axis.feasibility: 5,
          Axis.operatorFit: 5,
        },
      );
      expect(scoreCandidate(vibes).verdict, Verdict.noDefensibleGap);
    });

    test('unsourced claims are discarded', () {
      final asserted = Candidate(
        name: 'Asserted',
        market: 'x',
        evidence: const [
          Evidence(kind: EvidenceKind.complaint, source: '', claim: 'people hate this'),
          Evidence(kind: EvidenceKind.paidPrice, source: '  ', claim: 'they would pay loads'),
        ],
        scores: {
          Axis.distribution: 5,
          Axis.monetization: 5,
          Axis.headroom: 5,
          Axis.feasibility: 5,
          Axis.operatorFit: 5,
        },
      );
      final r = scoreCandidate(asserted);
      expect(r.verdict, Verdict.noDefensibleGap);
      expect(r.reasons.join(' '), contains('no source'));
    });

    test('three quotes from one domain is still one source', () {
      final echo = Candidate(
        name: 'Echo chamber',
        market: 'x',
        evidence: const [
          Evidence(kind: EvidenceKind.paidPrice, source: 'https://example.com/a', claim: '\$99'),
          Evidence(kind: EvidenceKind.salesCount, source: 'https://example.com/b', claim: '500'),
          Evidence(kind: EvidenceKind.complaint, source: 'https://example.com/c', claim: 'bad'),
        ],
        scores: {
          Axis.distribution: 5,
          Axis.monetization: 5,
          Axis.headroom: 5,
          Axis.feasibility: 5,
          Axis.operatorFit: 5,
        },
      );
      expect(echo.distinctSources, 1);
      expect(scoreCandidate(echo).verdict, Verdict.noDefensibleGap);
    });

    test('market-size trivia alone proves nothing', () {
      final big = Candidate(
        name: 'Big market',
        market: 'x',
        evidence: const [
          Evidence(kind: EvidenceKind.marketSize, source: 'https://a.com', claim: '\$50M'),
          Evidence(kind: EvidenceKind.marketSize, source: 'https://b.com', claim: 'growing 40%'),
        ],
        scores: {
          Axis.distribution: 5,
          Axis.monetization: 5,
          Axis.headroom: 5,
          Axis.feasibility: 5,
          Axis.operatorFit: 5,
        },
      );
      expect(scoreCandidate(big).verdict, Verdict.noDefensibleGap);
    });
  });

  group('promotion', () {
    test('the boilerplate candidate clears every gate', () {
      final r = scoreCandidate(boilerplate);
      expect(r.verdict, Verdict.strong);
    });

    test('market-size evidence is excluded from the substantive count', () {
      expect(boilerplate.evidence.length, 5);
      expect(boilerplate.realEvidence.length, 4);
    });
  });

  group('operatorFit — the autonomy dial', () {
    // Exists because of a real failure: a candidate extracted from the operator's
    // own repository scored STRONG on every other axis, and he killed it with
    // "I don't understand it, and I feel weird selling something I don't
    // understand." Nothing else on the rubric would have caught that.
    Candidate withFit(int fit) => Candidate(
          name: 'Technically strong, personally opaque',
          market: 'dev',
          evidence: const [
            Evidence(kind: EvidenceKind.paidPrice, source: 'https://a.com', claim: r'$199'),
            Evidence(kind: EvidenceKind.salesCount, source: 'https://b.com', claim: '8,300 buyers'),
            Evidence(kind: EvidenceKind.complaint, source: 'https://c.com', claim: 'real pain'),
          ],
          scores: {
            Axis.distribution: 4,
            Axis.monetization: 5,
            Axis.headroom: 4,
            Axis.feasibility: 5,
            Axis.operatorFit: fit,
          },
        );

    test('while the machine is unproven, an unexplainable product is killed', () {
      final r = scoreCandidate(withFit(1), operatorFitRequired: 3);
      expect(r.verdict, Verdict.killed);
      expect(r.reasons.join(' '), contains('autonomy setting'));
    });

    test('the same candidate passes once autonomy is earned', () {
      // After enough calibrated runs the floor drops and the factory may ship
      // things the operator could not have picked himself. That is the point.
      expect(scoreCandidate(withFit(1), operatorFitRequired: 1).verdict,
          Verdict.strong);
    });

    test('a strong operatorFit never rescues a structural failure', () {
      final doomed = Candidate(
        name: 'He understands it perfectly; the market is gone',
        market: 'dev',
        evidence: const [
          Evidence(kind: EvidenceKind.competitorCount, source: 'https://a.com', claim: '10 free rivals'),
          Evidence(kind: EvidenceKind.paidPrice, source: 'https://b.com', claim: r'competitors charge $0'),
        ],
        scores: {
          Axis.distribution: 4,
          Axis.monetization: 1,
          Axis.headroom: 0, // saturated
          Axis.feasibility: 5,
          Axis.operatorFit: 5, // he lived it
        },
      );
      expect(scoreCandidate(doomed, operatorFitRequired: 3).verdict,
          Verdict.killed);
    });

    test('the default is the cautious floor, not the permissive one', () {
      // A caller that forgets the parameter must get the safe behaviour.
      expect(scoreCandidate(withFit(1)).verdict, Verdict.killed);
    });
  });

  group('report', () {
    test('strongest first, and the dead are retained not filtered', () {
      final vibes = Candidate(name: 'Vibes', market: 'x');
      final report = scoutReport([vibes, codeCanyon, boilerplate]);
      expect(report.first.verdict, Verdict.strong);
      expect(report.length, 3, reason: 'the record of what died is the point');
      expect(noWinner(report), isFalse);
    });

    test('noWinner is true when nothing survives — an empty hand is a result', () {
      final vibes = Candidate(name: 'Vibes', market: 'x');
      expect(noWinner(scoutReport([vibes, codeCanyon])), isTrue);
    });

    test('verdicts do not depend on input order', () {
      final a = scoutReport([codeCanyon, boilerplate]).map((r) => r.verdict).toList();
      final b = scoutReport([boilerplate, codeCanyon]).map((r) => r.verdict).toList();
      expect(a, b);
    });
  });
}
