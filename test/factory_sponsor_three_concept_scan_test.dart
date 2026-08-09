import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/logic/factory_scan_session.dart';

const factoryRunId = 'factory-run-sponsor-concepts-20260809-01';
const scanSessionId = 'factory-scan-sponsor-concepts-20260809-01';
const makeoverId = 'FSC-20260809-MAKEOVER-001';
const tiktokId = 'FSC-20260809-TIKTOK-002';
const youtubeId = 'FSC-20260809-YOUTUBE-003';
const sponsorQuote = 'I want all to be yes';

const makeoverFingerprint =
    'makeover simulator|own-image coordinated transformation|purchasable wardrobe hair tattoo appearance preview';
const tiktokFingerprint =
    'autonomous tiktok growth operator|legitimate sponsor-owned media portfolio|short-form create measure adapt monetize';
const youtubeFingerprint =
    'autonomous youtube studio|legitimate sponsor-owned media portfolio|short-and-long-form create measure adapt monetize';

FactoryScanSession buildSponsorThreeConceptScan() {
  var session = FactoryScanSession.start(
    factoryRunId: factoryRunId,
    id: scanSessionId,
    startedAtMs: 1786278127797,
    scanPolicyVersion: 'signal-scan-v2+sponsor-provenance-v1',
  );

  session = _record(
    session,
    packet: const ScanWorkPacket(
      id: 'attempt-makeover-01',
      hypothesis:
          'A coordinated preview can reduce expensive appearance-change regret.',
      query:
          'Official virtual try-on, appearance editor, biometric privacy, and buyer-risk evidence',
      filters: [
        ScanFilter('subject', 'consenting depicted adult 18+'),
        ScanFilter('claim', 'visual concept, not fit or body prediction'),
      ],
      requestedSources: [
        'official product documentation',
        'official consumer-protection guidance',
      ],
    ),
    completedAtMs: 1786278720000,
    candidate: const ScanCandidateObservation(
      id: makeoverId,
      identity: 'Makeover Simulator',
      fingerprint: makeoverFingerprint,
      reviewWorthy: true,
      strong: true,
      evidenceReferenceIds: [
        'makeover-google-tryon',
        'makeover-google-doppl',
        'makeover-youcam',
        'makeover-ftc-biometric',
      ],
      oneSentenceIdea:
          'Preview a coordinated wardrobe, hair, tattoo, and appearance concept on a consenting adult before costly real-world changes.',
      intendedConsumer:
          'An adult planning a meaningful style change and worried about expensive regret.',
      painOrDesire:
          'Separate tools do not show whether the complete transformation works together.',
      audienceRationale:
          'Virtual try-on and appearance editing are proven behaviors, while coordinated decision support remains a narrower wedge.',
      simplestProduct:
          'A manually reviewed three-look concept pack with purchasable garment links and explicit accuracy limits.',
      moneyPath:
          'Sell a one-off visual decision pack before considering premium software, affiliates, or referrals.',
      strongestRejection:
          'Incumbents already cover many features, while privacy, truthfulness, body-image harm, and fulfillment economics are severe.',
      proofState:
          'MARKET/CONSTRAINT EVIDENCE VERIFIED; WILLINGNESS TO PAY UNVERIFIED',
      traits: [
        'consumer visual tool',
        'pre-purchase confidence',
        'manual paid test',
        'sensitive depicted-subject data',
      ],
    ),
    evidence: const [
      ScanEvidenceReference(
        id: 'makeover-google-tryon',
        source: 'Google Shopping',
        reference:
            'https://blog.google/products-and-platforms/products/shopping/how-to-use-google-shopping-try-it-on/',
        observedFact:
            'Google supports own-photo apparel try-on, validating the behavior but increasing competitive pressure.',
      ),
      ScanEvidenceReference(
        id: 'makeover-google-doppl',
        source: 'Google Labs',
        reference:
            'https://blog.google/innovation-and-ai/models-and-research/google-labs/doppl/',
        observedFact:
            'Google states Doppl is experimental and fit, appearance, and clothing details may be inaccurate.',
      ),
      ScanEvidenceReference(
        id: 'makeover-youcam',
        source: 'Perfect Corp',
        reference: 'https://www.perfectcorp.com/consumer/apps/ymk?lang=en',
        observedFact:
            'YouCam already offers hair, hair color, body editing, clothes changing, and freemium premium access.',
      ),
      ScanEvidenceReference(
        id: 'makeover-ftc-biometric',
        source: 'US Federal Trade Commission',
        reference:
            'https://www.ftc.gov/news-events/news/press-releases/2023/05/ftc-warns-about-misuses-biometric-information-harm-consumers',
        observedFact:
            'The FTC warns about privacy, security, bias, and unsupported accuracy claims involving biometric information.',
      ),
    ],
  );

  session = _record(
    session,
    packet: const ScanWorkPacket(
      id: 'attempt-tiktok-01',
      hypothesis:
          'A governed short-form media engine can sell a human-approved experiment pack before automating a portfolio.',
      query:
          'Official TikTok authenticity, AI disclosure, publishing API, monetization, and automation constraints',
      filters: [
        ScanFilter('ownership', 'legitimate sponsor-owned brand'),
        ScanFilter('publishing', 'human approval and official interface only'),
      ],
      requestedSources: [
        'official TikTok policy',
        'official TikTok developer documentation',
      ],
    ),
    completedAtMs: 1786279020000,
    candidate: const ScanCandidateObservation(
      id: tiktokId,
      identity: 'Autonomous TikTok Growth Operator',
      fingerprint: tiktokFingerprint,
      reviewWorthy: true,
      strong: true,
      evidenceReferenceIds: [
        'tiktok-integrity',
        'tiktok-direct-post',
        'tiktok-creator-rewards',
        'media-buffer',
      ],
      oneSentenceIdea:
          'Operate a governed portfolio of legitimate sponsor-owned TikTok brands that tests original short-form formats and retires weak hypotheses.',
      intendedConsumer:
          'Initially, a small seller or creator who needs a repeatable content experiment but retains account and posting control.',
      painOrDesire:
          'Research, scripting, production, posting, measurement, and iteration consume more time than small operators can sustain.',
      audienceRationale:
          'Existing scheduling tools validate multi-channel operations, but policy-safe experiment allocation and profit attribution remain the differentiator hypothesis.',
      simplestProduct:
          'A human-approved seven-day experiment pack: niche thesis, seven scripts, captions, production briefs, and a measurement sheet.',
      moneyPath:
          'Sell the experiment pack or managed service first; pursue affiliate, product, sponsorship, or native rewards only after evidence and eligibility.',
      strongestRejection:
          'The autonomous promise conflicts with consent, audit, authenticity, spam, and regional monetization constraints.',
      proofState:
          'PLATFORM BOUNDARIES VERIFIED; BAHRAIN REWARDS AND DEMAND UNVERIFIED',
      traits: [
        'media portfolio engine',
        'short-form experiments',
        'human account gate',
        'managed-service wedge',
      ],
    ),
    evidence: const [
      ScanEvidenceReference(
        id: 'tiktok-integrity',
        source: 'TikTok Community Guidelines',
        reference:
            'https://www.tiktok.com/community-guidelines/en/integrity-authenticity/',
        observedFact:
            'TikTok requires realistic AIGC disclosure and prohibits spam, fake engagement, bulk account automation, and evasion.',
      ),
      ScanEvidenceReference(
        id: 'tiktok-direct-post',
        source: 'TikTok for Developers',
        reference:
            'https://developers.tiktok.com/doc/content-posting-api-reference-direct-post',
        observedFact:
            'Public direct posting requires an approved integration and user authorization; unaudited use is restricted.',
      ),
      ScanEvidenceReference(
        id: 'tiktok-creator-rewards',
        source: 'TikTok Newsroom',
        reference:
            'https://newsroom.tiktok.com/introducing-the-new-creator-rewards-program?lang=en',
        observedFact:
            'Creator Rewards uses age, follower, view, account-standing, and regional-availability gates.',
      ),
      ScanEvidenceReference(
        id: 'media-buffer',
        source: 'Buffer',
        reference: 'https://buffer.com/pricing',
        observedFact:
            'A current substitute manages multiple social channels with free and per-channel paid tiers.',
      ),
    ],
  );

  session = _record(
    session,
    packet: const ScanWorkPacket(
      id: 'attempt-youtube-01',
      hypothesis:
          'A governed original-video engine can sell a human-approved production package before automating a portfolio.',
      query:
          'Official YouTube YPP, inauthentic content, AI disclosure, API upload, and Bahrain eligibility evidence',
      filters: [
        ScanFilter('ownership', 'legitimate sponsor-owned channel'),
        ScanFilter('content', 'original and independently useful'),
      ],
      requestedSources: [
        'official YouTube policy',
        'official YouTube developer documentation',
      ],
    ),
    completedAtMs: 1786279320000,
    candidate: const ScanCandidateObservation(
      id: youtubeId,
      identity: 'Autonomous YouTube Studio',
      fingerprint: youtubeFingerprint,
      reviewWorthy: true,
      strong: true,
      evidenceReferenceIds: [
        'youtube-ypp-expanded',
        'youtube-monetization-policy',
        'youtube-ai-disclosure',
        'youtube-video-insert',
      ],
      oneSentenceIdea:
          'Operate a governed portfolio of legitimate sponsor-owned YouTube brands that produces original formats, measures attributable outcomes, and retires weak hypotheses.',
      intendedConsumer:
          'Initially, a niche expert or small business that wants an original evergreen video package while retaining channel and publishing control.',
      painOrDesire:
          'Research-to-video production and learning loops are too slow and costly for consistent execution.',
      audienceRationale:
          'YouTube supports creator businesses and Bahrain YPP access, but a high-value original-production wedge is required to avoid commoditized mass output.',
      simplestProduct:
          'One human-approved research-to-video package or a three-video launch blueprint, sold before any portfolio engine build.',
      moneyPath:
          'Sell production or blueprint packages first; add affiliates and owned products; treat YPP revenue as a later reviewed path.',
      strongestRejection:
          'Slow eligibility, review risk, high production burden, and inauthentic-content rules undermine cheap autonomous scale.',
      proofState:
          'PLATFORM/BAHRAIN ELIGIBILITY VERIFIED; DEMAND AND REVIEW OUTCOME UNVERIFIED',
      traits: [
        'media portfolio engine',
        'evergreen video',
        'human account gate',
        'managed-service wedge',
      ],
    ),
    evidence: const [
      ScanEvidenceReference(
        id: 'youtube-ypp-expanded',
        source: 'YouTube Help',
        reference: 'https://support.google.com/youtube/answer/13429240',
        observedFact:
            'Bahrain is eligible for expanded YPP, with threshold and review gates rather than automatic monetization.',
      ),
      ScanEvidenceReference(
        id: 'youtube-monetization-policy',
        source: 'YouTube Help',
        reference: 'https://support.google.com/youtube/answer/1311392',
        observedFact:
            'Repetitive, mass-produced inauthentic content and low-value reused content are not monetizable.',
      ),
      ScanEvidenceReference(
        id: 'youtube-ai-disclosure',
        source: 'YouTube Help',
        reference: 'https://support.google.com/youtube/answer/14328491',
        observedFact:
            'Realistic altered or synthetic content requires disclosure; ordinary production assistance is treated differently.',
      ),
      ScanEvidenceReference(
        id: 'youtube-video-insert',
        source: 'Google for Developers',
        reference:
            'https://developers.google.com/youtube/v3/docs/videos/insert',
        observedFact:
            'Uploads require authorized API access and unaudited projects are constrained to private visibility.',
      ),
    ],
  );

  for (final candidateId in [makeoverId, tiktokId, youtubeId]) {
    final vote = session.recordSponsorVote(
      candidateId,
      SponsorVote.yes,
      recordedAtMs: 1786279500000,
      sponsorReason: sponsorQuote,
    );
    if (!vote.accepted) throw StateError(vote.reason);
    session = vote.session;
  }
  return session;
}

FactoryScanSession _record(
  FactoryScanSession session, {
  required ScanWorkPacket packet,
  required int completedAtMs,
  required ScanCandidateObservation candidate,
  required List<ScanEvidenceReference> evidence,
}) {
  final mutation = session.recordCompletedAttempt(
    packet,
    ScanAttemptResult(
      attemptId: packet.id,
      executionState: ScanExecutionState.completed,
      completedAtMs: completedAtMs,
      resultCount: 1,
      evidence: evidence,
      candidates: [candidate],
      usage: const ProviderUsage(),
    ),
  );
  if (!mutation.accepted) throw StateError(mutation.reason);
  return mutation.session;
}

void main() {
  test('binds the exact direct sponsor YES to all three exact candidates', () {
    final session = buildSponsorThreeConceptScan();

    expect(session.factoryRunId, factoryRunId);
    expect(session.id, scanSessionId);
    expect(session.attempts, hasLength(3));
    expect(session.evidence, hasLength(12));
    expect(session.candidates.map((value) => value.id),
        [makeoverId, tiktokId, youtubeId]);
    expect(session.candidates.map((value) => value.fingerprint),
        [makeoverFingerprint, tiktokFingerprint, youtubeFingerprint]);
    expect(
        session.candidates.every(
            (candidate) => candidate.state == ScanCandidateState.yesShortlist),
        isTrue);
    expect(
        session.candidates
            .every((candidate) => candidate.sponsorVote == SponsorVote.yes),
        isTrue);
    expect(session.verdictHistory, hasLength(3));
    expect(
        session.verdictHistory.every((record) =>
            record.sessionId == scanSessionId &&
            record.sponsorReason == sponsorQuote &&
            !record.reconstructed),
        isTrue);
    expect(session.awaitingVotes, 0);
    expect(session.reviewBackpressure, isFalse);
    expect(session.audit.exactTokens, isNull);
    expect(session.audit.exactCredits, isNull);
    expect(session.audit.efficiency, ScanEfficiency.efficient);
    expect(session.audit.effectiveness, ScanEffectiveness.high);
  });

  test('YES votes do not authorize Blueprint or accept Find My Table authority',
      () {
    final session = buildSponsorThreeConceptScan();
    expect(
        session.candidates.any((candidate) =>
            candidate.state == ScanCandidateState.blueprintAuthorized),
        isFalse);

    final crossRun = session.checkBlueprintAuthorization(
      const SponsorBlueprintAuthorization(
        authorizationId: 'BPA-20260809-FSC-LEGACY-YES-001',
        factoryRunId: 'factory-run-legacy-recovery-20260809-tablefinder-01',
        sessionId: 'factory-scan-legacy-recovery-20260809-tablefinder-01',
        candidateId: makeoverId,
        approvedBy: 'sadeq',
        approvedAtMs: 1786279600000,
        sponsorEvidence: 'Find My Table legacy authorization',
      ),
      factoryRunId: factoryRunId,
    );
    expect(crossRun.accepted, isFalse);
    expect(crossRun.reason, contains('not transferable'));

    final serialized = jsonDecode(jsonEncode(session.toJson())) as Map;
    for (final candidate in serialized['candidates'] as List) {
      (candidate as Map)['state'] = 'blueprintAuthorized';
    }
    final restored = FactoryScanSession.fromJson(serialized);
    expect(
        restored.candidates.every(
            (candidate) => candidate.state == ScanCandidateState.yesShortlist),
        isTrue);
  });

  test('HUD reports three credible shortlisted candidates and honest usage',
      () {
    final session = buildSponsorThreeConceptScan();
    final hud = session.hudAt(session.deadlineAtMs);
    expect(hud, contains('Signal Scan complete'));
    expect(hud, contains('Attempts: 3'));
    expect(hud, contains('Credible candidates: 3'));
    expect(hud, contains('Awaiting votes: 0'));
    expect(hud, contains('Efficiency: EFFICIENT'));
    expect(hud, contains('Effectiveness: HIGH'));
    expect(hud, contains('Token usage: unavailable'));
    expect(hud, contains('await separate run-bound Blueprint authorization'));
  });
}
