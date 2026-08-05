// scout_seed.dart — what the scout has already learned, as data rather than prose.
//
// ── Why this file exists ────────────────────────────────────────────────────
//
// Sadeq: "we will share this whole chat with the factory later so it can learn
// from it."
//
// A transcript in the context window is advice, not learning. Kai's weights are
// frozen; nothing he reads updates a parameter, and this codebase already has
// scar tissue proving that advice is the thing an optimiser talks itself out of
// — it is why the rubric, the gates and the frozen list are code and not a
// directive.
//
// What DOES change behaviour is history in the shape the policy already reads.
// Ten markets were scouted across 19–21 July 2026 and the outcomes were written
// down in products/SCOUTED_CANDIDATES.md as English. Transcribed here, the same
// facts pick the next market, order the cheapest kill first, and stop the scout
// paying full price for answers it already has.
//
// Every entry below is traceable to that register. Nothing is invented to round
// the picture out.
//
// ── What is deliberately NOT seeded, and why ────────────────────────────────
//
// 1. COSTS. `scout_economics.dart` ranks markets by survivals-per-pound, and
//    nobody metered what these ten attempts cost — the spend governor did not
//    exist yet. Back-filling plausible figures would produce a confident
//    ranking built on numbers nobody measured, which is precisely the failure
//    the unit-error detector catches in a spreadsheet. Economics starts empty
//    and fills from the first governed run.
//
// 2. PREDICTIONS. `prediction_ledger.dart` refuses any prediction locked at or
//    after the evidence arrived. Every verdict here was reached WITH the
//    evidence in hand, so writing them as predictions would be inadmissible by
//    the ledger's own rule — and seeding them anyway would teach a calibration
//    that was never earned. The ledger starting empty is the correct state, not
//    a gap.
//
// That asymmetry is the point: seed what was actually observed, refuse to seed
// what was not.
//
// Pure: imports only sibling logic modules. No I/O.
library;

import 'evidence_ledger.dart';
import 'scout_learning.dart';

/// The scouting runs happened on 2026-07-19 (unix seconds, UTC midnight).
const int _run1 = 1784419200;


/// Every market attempt on record, with the citation that killed or carried it.
///
/// `evidence_ledger` decays these on a per-cause shelf life, so a saturation
/// finding from July stops counting in November while "nobody pays for this"
/// survives two years. That is the behaviour prose could never have.
const List<ScoutRecord> kSeedScoutRecords = [
  // ── Developer tools ──
  ScoutRecord(
    market: 'flutter/dart developer tools',
    killedBy: KillKind.saturated,
    at: _run1,
    citations: [
      'https://codecanyon.net/category/mobile/flutter',
      'https://www.etsy.com/market/flutter_template',
    ],
    note: '3,800+ Flutter items listed on CodeCanyon; 900+ templates. Top '
        'sellers priced 39–79 with single-digit weekly sales. Demand is real '
        'and entirely served.',
  ),
  ScoutRecord(
    market: 'flutter/dart developer tools',
    killedBy: KillKind.operatorFit,
    at: _run1,
    citations: ['products/agent_guardrails/'],
    note: 'Agent Guardrails scored STRONG on all four original axes. Killed by '
        'the operator: "I don\'t understand it, and I feel weird selling '
        'something I don\'t understand." The operatorFit axis exists because of '
        'this run. Code is built and shelved, not deleted — viable if he ever '
        'learns it well enough to defend it.',
  ),

  // ── LLM infrastructure ──
  ScoutRecord(
    market: 'llm infrastructure',
    killedBy: KillKind.noMonetization,
    at: _run1,
    citations: [
      'https://www.helicone.ai/llm-cost',
      'https://livechatai.com/llm-pricing-calculator',
    ],
    note: 'Cost calculators: 10+ free tools, several pulling live pricing '
        'across 300+ models with CSV export and no signup. Squeezed from below '
        'by free and above by funded observability. operatorFit was 5/5 — he '
        'lived that bill — and it changed nothing. A structural kill is '
        'structural.',
  ),
  ScoutRecord(
    market: 'llm infrastructure',
    killedBy: KillKind.saturated,
    at: _run1,
    citations: [
      'https://www.helicone.ai/',
      'https://langfuse.com/',
      'https://www.langchain.com/langsmith',
    ],
    note: 'Observability SaaS: Helicone, Langfuse, LangSmith, Braintrust, '
        'Laminar, Cekura — all active, funded, and already segmented by '
        'customer spend tier. Bad solo entry.',
  ),

  // ── Restaurant documents and templates ──
  ScoutRecord(
    market: 'restaurant documents and templates',
    killedBy: KillKind.noMonetization,
    at: _run1,
    citations: [
      'https://www.restaurantowner.com/',
      'https://squareup.com/us/en/townsquare/restaurant-inventory-templates',
    ],
    note: 'THE LEAD-MAGNET FLOOR. Food cost and waste templates are given away '
        'free by Square, 7shifts, Supy, Jotform, RestaurantOwner, Restroworks '
        '— not as products but as bait for their SaaS. That free tier is '
        'subsidised by a different business model, so it will never get worse '
        'and never start charging.',
  ),

  // ── Consumer fintech ──
  ScoutRecord(
    market: 'consumer fintech',
    killedBy: KillKind.saturated,
    at: _run1,
    citations: ['https://www.ynab.com/', 'https://www.acorns.com/'],
    note: 'Gamified budget tracker: 20+ named competitors including Mint, '
        'YNAB, Acorns, Cleo, Qapital, PocketGuard. Retained nugget — most '
        'budgeting apps are abandoned inside 90 days.',
  ),

  // ── Print-on-demand / AI printables ──
  ScoutRecord(
    market: 'etsy ai printables',
    killedBy: KillKind.saturated,
    at: _run1,
    citations: ['https://www.etsy.com/market/ai_printables'],
    note: 'Saturated with AI-generated listings. The "AndrooAGI lane" — a '
        'strategy that works for whoever got there first and for nobody after.',
  ),

  // ── Restaurant training ──
  ScoutRecord(
    market: 'restaurant training saas',
    killedBy: KillKind.noChannel,
    at: _run1,
    citations: [
      'https://www.opus.so/blog/best-hospitality-lms',
      'https://www.1huddle.co/',
    ],
    note: 'No channel AND market served. Trainual ~1,000/mo, Wisetail custom, '
        'and 1Huddle is already gamification-first with 3,000+ pre-built '
        'games. Enterprise sales motion the operator does not have.',
  ),
];

/// The bandit arms, matching the record above.
///
/// `restaurant operations software` is the one arm with a survival, and how it
/// got there is the single most useful thing the machine can learn from this
/// register: it was never scouted. It came out of the operator's own workbook
/// while the scout was busy killing eight markets it found by searching.
///
/// UCB1 will rank untried markets first, then this one. That ordering is
/// correct and it is not sentiment — it is the only arm with a non-zero reward.
const List<MarketArm> kSeedMarketArms = [
  MarketArm(
    market: 'restaurant operations software',
    attempts: 1,
    survivals: 1,
    kills: {},
  ),
  MarketArm(
    market: 'restaurant documents and templates',
    attempts: 2,
    survivals: 1, // gamified staff onboarding survived, contested on headroom
    kills: {KillCause.noMonetization: 1},
  ),
  MarketArm(
    market: 'flutter/dart developer tools',
    attempts: 2,
    kills: {KillCause.saturated: 1, KillCause.operatorFit: 1},
  ),
  MarketArm(
    market: 'llm infrastructure',
    attempts: 2,
    kills: {KillCause.noMonetization: 1, KillCause.saturated: 1},
  ),
  MarketArm(
    market: 'consumer fintech',
    attempts: 1,
    kills: {KillCause.saturated: 1},
  ),
  MarketArm(
    market: 'etsy ai printables',
    attempts: 1,
    kills: {KillCause.saturated: 1},
  ),
  MarketArm(
    market: 'restaurant training saas',
    attempts: 1,
    kills: {KillCause.noChannel: 1},
  ),
];

/// Survival outcomes in run order, oldest first — the input to
/// `measureConvergence()`. Eight searched markets died; the ninth and tenth
/// attempts, both in restaurant operations, survived.
///
/// This deliberately reads as a flat line that turns at the end, because that
/// is what happened. A seed that showed steady improvement would be a nicer
/// story and a false one.
const List<bool> kSeedAttemptLog = [
  false, // flutter templates — saturated
  false, // llm cost calculator — no monetization
  false, // llm observability — saturated
  false, // consumer fintech — saturated
  false, // etsy ai printables — saturated
  false, // restaurant training saas — no channel
  false, // restaurant food cost templates — no monetization
  false, // agent guardrails — operator fit
  true, // gamified staff onboarding — survived, contested
  true, // F&B costing console — survived, and shipped something usable
];

/// The one-line lesson, kept next to the data it came from.
///
/// Not a directive — the modules above already enforce their own behaviour.
/// This is here so that anyone reading the seed knows what it is evidence OF.
const String kSeedLesson =
    'Ten markets, two survivors. Eight were found by searching and all eight '
    'died. Both survivors came from the operator\'s own working life — a '
    'workbook he already kept and a venue he already runs. The scout was not '
    'wrong to kill the eight; it was right, and the register proves it. But '
    'the harvest step was looking in the wrong place. Markets where the '
    'operator already has data, domain and credibility outrank markets that '
    'merely look open from the outside — and operatorFit is the axis that '
    'measures the difference.';

/// When the seed was written, so its own staleness can be judged.
const int kSeedWrittenAt = 1784592000; // 2026-07-21
