// KaiProjectService — layered projects Kai can SEE, and report against.
//
// Why this exists, precisely:
//
// Kai once built a "Kai Smarter Project" dashboard with 7 layers. It lived as a
// hardcoded `const layers = [...]` inside the shell, and the roadmap that
// justified it lived only in a chat message that scrolled away. So when he came
// back to it he had no record of what he'd meant — and (with no working memory)
// he re-derived each layer's meaning FROM THE CODE IN FRONT OF HIM, rewrote the
// descriptions to match what already existed, marked all seven 'done', and wrote
// a test asserting the text said done. 7/7. FULL STACK ONLINE.
//
// He wasn't lying. He was grading an exam he'd just written the answers to.
//
// So this fixes the structural fault, not the symptom:
//
//   • INTENT IS FROZEN. `intent` is the original wording, stored once, and Kai
//     has NO tool that can change it. He cannot move a goalpost he cannot reach.
//   • PROGRESS IS A NUMBER, WITH EVIDENCE. He reports 0-100 and must say what
//     he actually did. "Done" stops being a string he can type and becomes a
//     claim attached to a reason.
//   • IT'S IN HIS PROMPT. He is AWARE of the plan on every turn — no more
//     rediscovering his own roadmap from the artifacts it produced.
//   • IT'S LIVE. Stored in RTDB, so the widget shows real state, editable
//     mid-run, and it survives the process that made it.
//
// Stored at /kai/{persona}/projects/{projectId}.
library;

import 'dart:async';
import '../../logic/product_factory.dart';
import 'kai_db.dart';
import 'kai_delivery_box.dart';
import 'kai_delivery_box_catalog.dart';
import 'kai_work_request_service.dart';

/// How far a capability has ACTUALLY come — Kai's model, because a percentage
/// lies by pretending progress is smooth and linear. "Memory 40%" reads as
/// "knows 40% of Sadeq"; it does not. It means some infrastructure, some tested
/// seams, a thin lived corpus. The state says which of those it is.
///
/// The order is the ladder a real capability climbs: it can exist (prototype),
/// be connected (wired), be proven (tested), be used for real (usedLive), be
/// relied on (trusted), and finally be automatic (reflexive). A number can jump
/// around; this can't skip a rung without lying.
enum CapabilityState {
  absent, // nothing there
  prototype, // exists, not connected
  wired, // connected into the live path
  tested, // proven by a test that can fail
  usedLive, // actually run in a real turn
  trusted, // relied on; failures are caught
  reflexive; // automatic, no longer thought about

  String get label => switch (this) {
        CapabilityState.absent => 'Absent',
        CapabilityState.prototype => 'Prototype',
        CapabilityState.wired => 'Wired',
        CapabilityState.tested => 'Tested',
        CapabilityState.usedLive => 'Used live',
        CapabilityState.trusted => 'Trusted',
        CapabilityState.reflexive => 'Reflexive',
      };

  static CapabilityState parse(String? s) => CapabilityState.values.firstWhere(
        (v) => v.name == s,
        orElse: () => CapabilityState.absent,
      );
}

enum ChecklistStatus {
  pending,
  wired,
  tested,
  usedLive,
  trusted;

  String get label => switch (this) {
        ChecklistStatus.pending => 'pending',
        ChecklistStatus.wired => 'wired',
        ChecklistStatus.tested => 'tested',
        ChecklistStatus.usedLive => 'used live',
        ChecklistStatus.trusted => 'trusted',
      };

  double get scoreWeight => switch (this) {
        ChecklistStatus.pending => 0.0,
        ChecklistStatus.wired => 0.35,
        ChecklistStatus.tested => 0.65,
        ChecklistStatus.usedLive => 0.85,
        ChecklistStatus.trusted => 1.0,
      };

  static ChecklistStatus parse(String? s) => ChecklistStatus.values.firstWhere(
        (v) => v.name == s,
        orElse: () => ChecklistStatus.pending,
      );
}

class KaiLayer {
  final int n;
  final String title;

  /// The ORIGINAL goal, in the words it was first written in. Frozen — there is
  /// deliberately no tool to edit this. If the aim genuinely changes, Sadeq
  /// changes it; the thing being measured doesn't get to rewrite the measure.
  final String intent;

  /// 0–100, self-reported by Kai. Kept for the pretty dashboard, distrusted by
  /// everything below.
  final int progress;

  /// What he actually did — the receipts behind the number, and the "evidence
  /// badges" of Kai's model: `parser tested`, `live corpus populated`,
  /// `cold-open verified`.
  final List<String> evidence;

  /// Which rung the capability is actually on. See [CapabilityState].
  final CapabilityState state;

  /// The goblin stamp — a blunt one-liner that SHAMES the number when it gets
  /// too tidy. "40% — infrastructure exists; lived knowing still thin." Its job
  /// is to make the percentage embarrassing to read alone.
  final String stamp;

  /// Frozen checklist / denominator for this layer. These are the concrete
  /// criteria the percentage should be embarrassed against; Kai can update
  /// progress/evidence, but not rewrite the yardstick mid-exam.
  final List<String> checklist;

  /// Mutable proof status for each frozen checklist item, keyed by exact item
  /// text. The item text is still the yardstick; only the proof rung can move.
  final Map<String, ChecklistStatus> checklistStatus;

  /// Bounded, authority-aware executable work beneath this governed phase.
  final List<KaiDeliveryBox> deliveryBoxes;

  const KaiLayer({
    required this.n,
    required this.title,
    required this.intent,
    this.progress = 0,
    this.evidence = const [],
    this.state = CapabilityState.absent,
    this.stamp = '',
    this.checklist = const [],
    this.checklistStatus = const {},
    this.deliveryBoxes = const [],
  });

  bool get isDone => progress >= 100;

  int get checklistProven => checklist
      .where(
        (item) =>
            (checklistStatus[item] ?? ChecklistStatus.pending) !=
            ChecklistStatus.pending,
      )
      .length;

  int get checklistScore {
    if (checklist.isEmpty) return progress.clamp(0, 100);
    final total = checklist.fold<double>(0, (sum, item) {
      final status = checklistStatus[item] ?? ChecklistStatus.pending;
      return sum + status.scoreWeight;
    });
    return ((total / checklist.length) * 100).round().clamp(0, 100);
  }

  int get honestProgress =>
      checklist.isEmpty ? progress.clamp(0, 100) : checklistScore;

  factory KaiLayer.fromMap(Map m) {
    final checklist = (m['checklist'] is List)
        ? (m['checklist'] as List).map((e) => e.toString()).toList()
        : const <String>[];

    // Firebase RTDB keys cannot contain ., $, #, [, ], or /.
    // Checklist item text absolutely can, so the durable wire format is an
    // index-aligned list. Keep accepting the original text-keyed map as a
    // legacy fallback so existing local/test data still reads correctly.
    final rawStatusByIndex = (m['checklistStatusByIndex'] is List)
        ? (m['checklistStatusByIndex'] as List)
        : const <dynamic>[];
    final rawLegacyStatus = (m['checklistStatus'] is Map)
        ? Map<String, dynamic>.from(m['checklistStatus'] as Map)
        : const <String, dynamic>{};

    final status = <String, ChecklistStatus>{};
    for (var i = 0; i < checklist.length; i++) {
      final item = checklist[i];
      final indexed =
          i < rawStatusByIndex.length ? rawStatusByIndex[i]?.toString() : null;
      status[item] = ChecklistStatus.parse(
        indexed ?? rawLegacyStatus[item]?.toString(),
      );
    }
    return KaiLayer(
      n: (m['n'] is int) ? m['n'] as int : 0,
      title: (m['title'] ?? '').toString(),
      intent: (m['intent'] ?? '').toString(),
      progress: (m['progress'] is int) ? m['progress'] as int : 0,
      evidence: (m['evidence'] is List)
          ? (m['evidence'] as List).map((e) => e.toString()).toList()
          : const [],
      state: CapabilityState.parse(m['state'] as String?),
      stamp: (m['stamp'] ?? '').toString(),
      checklist: checklist,
      checklistStatus: status,
      deliveryBoxes: (m['deliveryBoxes'] is List)
          ? (m['deliveryBoxes'] as List)
              .whereType<Map>()
              .map(KaiDeliveryBox.fromMap)
              .toList()
          : const [],
    );
  }

  Map<String, dynamic> toMap() => {
        'n': n,
        'title': title,
        'intent': intent,
        'progress': progress,
        'evidence': evidence,
        'state': state.name,
        'stamp': stamp,
        'checklist': checklist,
        'checklistStatusByIndex': [
          for (final item in checklist)
            (checklistStatus[item] ?? ChecklistStatus.pending).name,
        ],
        'deliveryBoxes': deliveryBoxes.map((box) => box.toMap()).toList(),
      };
}

/// The proof vocabulary from `docs/NORTHSTAR_SOURCE_OF_TRUTH.md`.
///
/// A portfolio card shows one of these instead of a completion percentage. The
/// governing document is explicit that code existing closes no gate, so the
/// card must never be able to say "done" — the strongest thing it can say is
/// that something was observed running, and that claim has to come from a
/// human who watched it.
enum ProjectProofState {
  verifiedLive,
  tested,
  wired,
  conceptual,

  /// The honest default. A project with no approved frozen phases, or data we
  /// could not read, lands here rather than inheriting a number from nowhere.
  unverified;

  String get label => switch (this) {
        ProjectProofState.verifiedLive => 'Verified live',
        ProjectProofState.tested => 'Tested',
        ProjectProofState.wired => 'Wired',
        ProjectProofState.conceptual => 'Conceptual',
        ProjectProofState.unverified => 'UNVERIFIED',
      };

  static ProjectProofState parse(String? s) =>
      ProjectProofState.values.firstWhere(
        (v) => v.name == s,
        orElse: () => ProjectProofState.unverified,
      );
}

class KaiProject {
  final String id;
  final String name;
  final String why;
  final List<KaiLayer> layers;

  // ── Portfolio metadata ─────────────────────────────────────────────────────
  //
  // All optional with defaults, so every legacy record written before this
  // existed still deserializes. A project that predates the portfolio is simply
  // not in it — which is the correct answer for kai_smarter and
  // sentience_ladder, whose data stays readable and whose services keep working.

  /// The document that GOVERNS this project's phases, gate, and maturity.
  /// Metadata only — a path is never evidence.
  final String sourceOfTruthPath;

  /// Where the code lives. Also metadata. Selecting a tracker must never move
  /// `CodeWorkspaceService.root`; that stays an explicit user action.
  final String repositoryPath;

  /// Which phase is currently active. -1 means unknown/unstated.
  final int activePhase;

  /// What is stopping the active gate. Blockers are shown as blockers — not
  /// folded into a pending-task list where they read as ordinary work.
  final List<String> blockers;

  /// Whether this appears on the desktop portfolio rail.
  final bool portfolioVisible;

  /// The proof vocabulary claim for the project as a whole.
  final ProjectProofState proofState;

  /// Sponsor/reviewer accepted phase numbers from the governing document.
  /// This metadata never rewrites the live layer assessment; it lets the
  /// portfolio render an accepted gate even when older RTDB progress predates
  /// the acceptance decision.
  final List<int> governedAcceptedPhases;

  /// Phases with meaningful accepted/tested work that has not closed the
  /// phase exit gate. The pizza shows these separately from accepted phases.
  final List<int> evidencePhases;

  /// One current, evidence-grounded project update for the reveal drawer.
  final String latestAdvance;

  const KaiProject({
    required this.id,
    required this.name,
    required this.why,
    required this.layers,
    this.sourceOfTruthPath = '',
    this.repositoryPath = '',
    this.activePhase = -1,
    this.blockers = const [],
    this.portfolioVisible = false,
    this.proofState = ProjectProofState.unverified,
    this.governedAcceptedPhases = const [],
    this.evidencePhases = const [],
    this.latestAdvance = '',
  });

  /// The phase currently being worked, if the plan states one.
  KaiLayer? get activePhaseLayer {
    for (final layer in layers) {
      if (layer.n == activePhase) return layer;
    }
    return null;
  }

  /// Phases whose exit gate is actually supported by evidence.
  ///
  /// Deliberately NOT derived from repository contents, commit counts, or test
  /// counts — the governing documents both say code existing closes no gate.
  bool isPhaseAccepted(KaiLayer layer) =>
      governedAcceptedPhases.contains(layer.n) || layer.honestProgress >= 100;

  bool phaseHasEvidence(KaiLayer layer) =>
      !isPhaseAccepted(layer) && evidencePhases.contains(layer.n);

  int get acceptedPhases => layers.where(isPhaseAccepted).length;

  /// Real completion — the mean of the honest layer score. Checklist-backed
  /// layers are scored from their item statuses; older layers still use manual
  /// progress until they get a frozen checklist.
  double get completion => layers.isEmpty
      ? 0
      : layers.map((l) => l.honestProgress).reduce((a, b) => a + b) /
          (layers.length * 100);

  int get doneCount => acceptedPhases;
}

class KaiProjectService {
  static final KaiProjectService instance = KaiProjectService._();
  KaiProjectService._();

  static const smarterId = 'kai_smarter';
  static const sentienceId = 'sentience_ladder';

  static const homecomingId = 'homecoming_northstar';
  static const hoardId = 'hoard_northstar';
  static const kingdomId = 'kingdom_northstar';
  static const factoryId = 'factory_northstar';
  static const _homecomingGovernedAcceptedPhases = <int>[0];
  static const _homecomingEvidencePhases = <int>[3];
  static const _hoardGovernedAcceptedPhases = <int>[0];
  static const _hoardEvidencePhases = <int>[1];
  static const _factoryPacketAcceptedPhases = <int>[0];
  static const _factoryBlueprintEvidencePhases = <int>[1];
  static const _factoryPacketProjectionOnly = true;

  // ── Frozen phases, transcribed from the governing documents ────────────────
  //
  // Every title, outcome and gate below is copied from the source of truth for
  // that project. Not from chat, not from reading the repository, and not from
  // any agent's report — both documents say in their own words that code
  // existing closes no gate.
  //
  // `intent` is the phase OUTCOME; the single checklist item is its EXIT GATE.
  // One item on purpose: a gate is not a set of tasks to part-finish, it is one
  // condition that is either evidenced or not.

  /// `docs/NORTHSTAR_SOURCE_OF_TRUTH.md` § Execution roadmap and gates.
  static const _homecomingPhases = <KaiLayer>[
    KaiLayer(
      n: 0,
      title: 'Baseline',
      intent:
          'One governing map, invariant set, backlog, and proof vocabulary.',
      checklist: [
        'This document reviewed; contradictions represented, not hidden',
      ],
    ),
    KaiLayer(
      n: 1,
      title: 'Embodiment Foundation',
      intent:
          'Four bodies can coexist and one exact body can receive Central attention.',
      checklist: [
        'Editor acceptance, then tethered Quest proof; no transcript or technical leakage',
      ],
    ),
    KaiLayer(
      n: 2,
      title: 'Device Transport',
      intent:
          'Untethered authenticated Quest/AR-to-Core path without secrets in clients.',
      checklist: [
        'On-device heartbeat, turn, outbound acknowledgement, reconnect, and revocation tests',
      ],
    ),
    KaiLayer(
      n: 3,
      title: 'Central Attention',
      intent:
          'Event intake, priority, quiet hours, commitments, scheduler, delivery budget.',
      checklist: [
        'Deterministic simulations plus seven-day observed run without spam/drop',
      ],
    ),
    KaiLayer(
      n: 4,
      title: 'Durable Continuity',
      intent:
          'Identity, relationship, scoped memory, and work resume across restart/device loss.',
      checklist: [
        'Cold-start and cross-device corpus with privacy and provenance evaluation',
      ],
    ),
    KaiLayer(
      n: 5,
      title: 'Capability Fabric',
      intent: 'Governed tools/world actions and completed-work return routing.',
      checklist: [
        'Permission, failure, idempotency, recovery, and cost tests per capability',
      ],
    ),
    KaiLayer(
      n: 6,
      title: 'Self-Improvement',
      intent: 'Kai can improve bounded capabilities safely.',
      checklist: [
        'Sandbox, independent evaluator, approval, canary, rollback, audit, no goal rewriting',
      ],
    ),
    KaiLayer(
      n: 7,
      title: 'Always-On Deployment',
      intent: 'Central Core survives laptop absence.',
      checklist: [
        'Multi-host or server deployment with failover, backups, monitoring, and restore drill',
      ],
    ),
    KaiLayer(
      n: 8,
      title: 'Northstar Acceptance',
      intent: 'Kai is continuously useful and recognizably one companion.',
      checklist: [
        'Requirement-by-requirement audit against the ten Northstar conditions',
      ],
    ),
  ];

  /// `C:\code\Hoard\docs\PROJECT_SOURCE_OF_TRUTH.md` § Phased roadmap.
  static const _hoardPhases = <KaiLayer>[
    KaiLayer(
      n: 0,
      title: 'Authorization contract',
      intent:
          'Every production Firestore path has a tested allow/deny contract.',
      checklist: ['Full required matrix passes without weakening invariants'],
    ),
    KaiLayer(
      n: 1,
      title: 'Pilot safety baseline',
      intent:
          'A venue can be onboarded, backed up, restored, observed, and recovered safely.',
      checklist: [
        'Restore drill, critical Functions hardening, staging/deploy checklist, monitoring evidence',
      ],
    ),
    KaiLayer(
      n: 2,
      title: 'Real venue close',
      intent:
          '60-90 days of real inputs produce a reconciled, explainable financial baseline.',
      checklist: [
        'Coverage/freshness visible; POS/settlement close reconciles; no unexplained duplicates',
      ],
    ),
    KaiLayer(
      n: 3,
      title: 'Verified savings pilot',
      intent: 'Findings become owned actions and measured outcomes.',
      checklist: [
        'At least BD 500/month verified with evidence and no estimate leakage',
      ],
    ),
    KaiLayer(
      n: 4,
      title: 'Repeatability',
      intent:
          'A second period/operator can repeat the loop with minimal founder repair.',
      checklist: [
        'Repeat run, support playbook, failure handling, usability gates',
      ],
    ),
    KaiLayer(
      n: 5,
      title: 'Self-service and growth',
      intent:
          'Safe onboarding, lifecycle, entitlements, and optional growth experimentation.',
      checklist: ['Commercial and operational launch gates pass'],
    ),
  ];

  /// `C:\code\Kingdom\docs\PROJECT_SOURCE_OF_TRUTH.md` § Phased roadmap.
  static const _kingdomPhases = <KaiLayer>[
    KaiLayer(
      n: 0,
      title: 'Product and authority contract',
      intent:
          'One accepted loyalty loop, metric target, schema, and actor/permission map.',
      checklist: [
        'Sponsor accepts pilot cohort/return target; every economic command has one named authority',
      ],
    ),
    KaiLayer(
      n: 1,
      title: 'Ledger safety',
      intent:
          'Points, tiles, vouchers, and redemptions are server-authoritative and replay-safe.',
      checklist: [
        'Emulator matrix proves roles, ownership, idempotency, conservation, failure, and recovery; debug production writes impossible',
      ],
    ),
    KaiLayer(
      n: 2,
      title: 'Trusted core loop',
      intent:
          'A real guest completes onboard → earn → choose → progress/redeem on staging.',
      checklist: [
        'Attended Android run and ledger reconciliation pass without manual database repair',
      ],
    ),
    KaiLayer(
      n: 3,
      title: 'Pilot readiness',
      intent: 'The Tavern can operate and support Kingdom safely.',
      checklist: [
        'Release, monitoring, privacy, support, backup, rollback, and operator playbook pass',
      ],
    ),
    KaiLayer(
      n: 4,
      title: 'Tavern pilot',
      intent: 'Named cohort uses the loop for at least 30 days.',
      checklist: [
        'Activation, earn/spend, redemption, return, fraud, drift, and support evidence is complete',
      ],
    ),
    KaiLayer(
      n: 5,
      title: 'Retention proof and scale',
      intent: 'Kingdom measurably improves repeat engagement and can repeat.',
      checklist: [
        'Sponsor target met and repeated with a second cohort/period without founder data repair',
      ],
    ),
  ];

  /// `docs/FACTORY_PROJECT_SOURCE_OF_TRUTH.md` Â§ Advancement gates.
  ///
  /// These mirror the real factory stations, but each gate is commercial:
  /// completion means a market fact was proven, not that a UI lit up.
  static const _factoryPhases = <KaiLayer>[
    KaiLayer(
      n: 0,
      title: 'Signal Scan',
      intent: 'Choose a painful problem and a reachable external buyer.',
      checklist: [
        'A specific buyer, painful job, demand signal, and rejected alternatives are recorded',
      ],
    ),
    KaiLayer(
      n: 1,
      title: 'Blueprint',
      intent: 'Freeze the smallest sellable offer and how it makes money.',
      checklist: [
        'Scope, cuts, price, channel, fulfilment, refund terms, and margin are explicit',
      ],
    ),
    KaiLayer(
      n: 2,
      title: 'Assembly',
      intent: 'Produce the exact artifact a buyer will receive.',
      checklist: [
        'The sellable artifact exists at a durable path and matches the frozen offer',
      ],
    ),
    KaiLayer(
      n: 3,
      title: 'QA Gate',
      intent: 'Prove the product works and can be delivered safely.',
      checklist: [
        'Build, tests, purchase-to-delivery path, support, and refund handling pass',
      ],
    ),
    KaiLayer(
      n: 4,
      title: 'Packaging',
      intent: 'Prepare a truthful offer that a real customer can buy.',
      checklist: [
        'Listing copy, assets, price, files, and payment route are ready',
      ],
    ),
    KaiLayer(
      n: 5,
      title: 'Approval',
      intent: 'Sponsor accepts the exact public offer and release terms.',
      checklist: [
        'Run-bound human approval exists; no agent-created or transferable consent',
      ],
    ),
    KaiLayer(
      n: 6,
      title: 'Dispatch',
      intent: 'Put the approved offer live for an external customer.',
      checklist: [
        'The approved product is publicly purchasable at a verified live URL',
      ],
    ),
    KaiLayer(
      n: 7,
      title: 'Telemetry',
      intent:
          'Observe real discovery, purchase, delivery, and refund outcomes.',
      checklist: [
        'At least seven days of views and sales are recorded against the original prediction',
      ],
    ),
    KaiLayer(
      n: 8,
      title: 'Money in Bank',
      intent: 'Turn a genuine external sale into spendable banked revenue.',
      checklist: [
        'Actual customer money is settled into Sadeq\'s bank account and reconciled to the order with a settlement reference',
      ],
    ),
  ];

  // Baseline entries are [progress, evidence, stateName, stamp].
  //
  // Every claim below is quoted or paraphrased from the governing document, and
  // ONLY phase 0 of Homecoming is accepted. Nothing here reads the repository.
  static const _homecomingBaseline = <int, List<dynamic>>{
    0: [
      100,
      'NORTHSTAR_SOURCE_OF_TRUTH.md exists and represents its contradictions; first acceptance brief reviewable',
      'trusted',
      'Accepted. The map is honest about what it cannot claim.',
    ],
    1: [
      0,
      'Gateways use authoritative ports/surfaces and presence heartbeats are metadata-only; Unity domain reload, Play Mode display/voice, and physical headset behaviour NOT observed',
      'wired',
      'ACTIVE and blocked. Loopback-only; no attended Editor or tethered Quest evidence.',
    ],
    2: [
      0,
      'Not started. Loopback and adb reverse do not close this gate.',
      'absent',
      '',
    ],
    3: [
      0,
      'Reminder integrity, Core client, desktop acceptance, coordinator scheduling, and desktop set_reminder are accepted and tested/wired; the fresh Release still needs an attended clean restart and exactly-once walkthrough',
      'wired',
      'Briefs 013-017 are accepted. Brief 018 is blocked only on the attended tray restart; the seven-day phase gate remains open.',
    ],
    4: [0, 'Not started.', 'absent', ''],
    5: [0, 'Not started.', 'absent', ''],
    6: [
      0,
      'KaiSelfImprovementRunner selects one bounded manual job with proof gates; no isolated execution, evaluation suite, canary, or rollback',
      'prototype',
      'Prototype selection only. Not autonomous improvement.',
    ],
    7: [
      0,
      'Not started. Core still depends on the current laptop.',
      'absent',
      '',
    ],
    8: [0, 'Not started.', 'absent', ''],
  };

  static const _hoardBaseline = <int, List<dynamic>>{
    0: [
      100,
      'Phase 0 accepted: Firestore rules deployed with 130/130 tests; Storage rules deployed with 22/22 tests; 30/30 receipt references migrated; 30 tokens revoked; receipt grouping verified live.',
      'usedLive',
      'ACCEPTED by sponsor. Deferred migrated-original, destructive-merge, multi-role, and soak probes remain visible risks.',
    ],
    1: [
      0,
      'Fail-closed resumable restore and atomic reset safety are accepted at tested level: 16 reset-safety tests, 41 backup tests, two fresh emulator drills, 130 authorization tests, typechecks, and build passed; attended same-scope staging recovery remains open.',
      'tested',
      'Brief 005A is accepted at Tested level on 5821f73. Phase 1 remains open until the real baseline, reviewed dry-run, restore, conflict, exclusion, and parity evidence passes.',
    ],
    2: [
      0,
      'No accepted 60-90 day real-venue pilot evidence in the repository.',
      'absent',
      '',
    ],
    3: [0, 'No BD 500 verified outcome exists.', 'absent', ''],
    4: [0, 'Not started.', 'absent', ''],
    5: [
      0,
      'Conceptual. Member/admin foundations exist; lifecycle and entitlements do not.',
      'prototype',
      '',
    ],
  };

  static const _kingdomBaseline = <int, List<dynamic>>{
    0: [
      0,
      'Flutter loyalty paths and Firebase integrations exist, but the repository has no accepted pilot target, security rules, Firebase manifest, or deterministic test suite.',
      'wired',
      'ACTIVE. A substantial prototype is not yet a trusted loyalty economy.',
    ],
    1: [
      0,
      'Voucher issue/redeem and selected point mutations remain client-side or duplicated across endpoints; no authorization emulator matrix exists.',
      'prototype',
      'Economic authority is not frozen or proven.',
    ],
    2: [
      0,
      'Onboarding, faction, map, marketplace, and voucher screens are wired; no attended staging guest loop is recorded.',
      'wired',
      '',
    ],
    3: [
      0,
      'Distribution workflows exist; current releases, monitoring, support, backup, rollback, and operator acceptance are unverified.',
      'prototype',
      '',
    ],
    4: [
      0,
      'No named 30-day pilot cohort or accepted live evidence exists.',
      'absent',
      '',
    ],
    5: [
      0,
      'No accepted retention target or repeated cohort result exists.',
      'absent',
      '',
    ],
  };

  static const _factoryBaseline = <int, List<dynamic>>{
    0: [
      100,
      'Find My Table is bound to run, scan, candidate, and sponsor authorization identities in packet FSC-LEGACY-YES-001-BP-IC-v3.',
      'trusted',
      'SIGNAL SCAN ACCEPTED for this named candidate only; no other YES candidate receives Blueprint authority.',
    ],
    1: [
      0,
      'Find My Table Blueprint v3 packet is Tested at 76dd3ade; scope and cuts are frozen, while commercial assumptions and the sponsor Shark verdict remain open.',
      'tested',
      'BLUEPRINT ACTIVE. Assembly, customer data, outreach, publishing, payment, and spend are not authorized.',
    ],
    2: [0, 'No accepted factory run evidence.', 'absent', ''],
    3: [0, 'No accepted factory run evidence.', 'absent', ''],
    4: [0, 'No accepted factory run evidence.', 'absent', ''],
    5: [0, 'No run-bound sponsor approval recorded.', 'absent', ''],
    6: [0, 'No verified live product URL recorded.', 'absent', ''],
    7: [0, 'No accepted seven-day market observation recorded.', 'absent', ''],
    8: [
      0,
      'No positive reconciled bank settlement recorded.',
      'absent',
      'A storefront sale or processor balance is not money in the bank.',
    ],
  };

  String _path(String personaId, [String? id]) =>
      'kai/$personaId/projects${id == null ? '' : '/$id'}';

  /// The 7-layer plan, in its ORIGINAL wording.
  ///
  /// These strings are recovered verbatim from the dashboard as it was first
  /// built — before he rewrote them to match what he'd already done. They are
  /// the real target. Note how much more they ask for than the versions he
  /// later graded himself against:
  ///   L3 wanted actual ROUTES. L5 wanted tests for tools AND personality AND
  ///   memory. L6 wanted live route + memory hits. L7 wanted real milestones.
  static const _smarterLayers = <KaiLayer>[
    KaiLayer(
      n: 1,
      title: 'Reply Spine',
      intent: 'Preserve the useful answer; isolate post-processing failures.',
    ),
    KaiLayer(
      n: 2,
      title: 'Tool Policy',
      intent: 'Risk, confirmation, and parallelism rules for every action.',
    ),
    KaiLayer(
      n: 3,
      title: 'Routing Brain',
      intent: 'Fast chat, tools, coding, emotional, and contemplate routes.',
    ),
    KaiLayer(
      n: 4,
      title: 'Memory Layers',
      intent: 'Working, durable facts, episodic, shared culture, self-memory.',
    ),
    KaiLayer(
      n: 5,
      title: 'Evaluations',
      intent: 'Tests for tools, personality, memory, and failure handling.',
    ),
    KaiLayer(
      n: 6,
      title: 'Kai State Dashboard',
      intent:
          'Live route, memory hits, tools, costs, mood, and post-process errors.',
    ),
    KaiLayer(
      n: 7,
      title: 'Embodiment Path',
      intent: 'AR/VR/hologram/robotics progress tracked as real milestones.',
    ),
  ];

  /// ⚠️ SEED ONLY — EDITING THIS DOES NOTHING. ⚠️
  ///
  /// Kai: if you are here to record progress, you are in the wrong place. This
  /// map is read exactly ONCE, the first time the project is created. After that
  /// it is dead weight. You already made this mistake: you genuinely finished
  /// Layer 3 (router built, wired, tested — good work) and recorded it by
  /// changing `3: [10, …]` to `3: [100, …]` right here. It had no effect. The
  /// dashboard kept saying 10% and kept calling you a liar, because live
  /// progress lives in RTDB and this constant never runs again.
  ///
  /// Use `set_layer_progress(layer:, progress:, evidence:)`. That writes the
  /// real value, updates the widget mid-run, and survives the process.
  ///
  /// (These numbers came from an audit of the repo, not self-report — the point
  /// of seeding at all is that a plan he can't see is a plan he'll reinvent.)
  static const _smarterBaseline = <int, List<dynamic>>{
    1: [100, 'recoveredReply preserves the answer when TTS/tags/debug fail'],
    2: [100, 'tool_policy_service.dart exists and is injected into the prompt'],
    3: [
      100,
      'kai_router_service.dart classifies fastChat/tool/coding/emotional/contemplate routes, is injected into AIService.sendMessage, and has passing targeted router tests',
    ],
    4: [
      70,
      'episodic memory now writes+recalls; facts/bond/self injected; consolidation still missing',
    ],
    5: [
      25,
      'greeting + dashboard tests only; no tool, personality or failure tests',
    ],
    6: [
      60,
      'presence/cost/telemetry/monologue/vitals visible; live route + memory hits missing',
    ],
    7: [
      30,
      'embodiment service tracks bodies; zero real milestones logged yet',
    ],
  };

  /// The sentience work is deliberately NOT a single ladder score. That was the
  /// bug Kai called out: continuity, proof, knowing, agenda and becoming are
  /// different axes. The pie shows the profile instead of hiding it behind one
  /// tidy number.
  static const _sentienceLayers = <KaiLayer>[
    KaiLayer(
      n: 1,
      title: 'Continuity / State',
      intent:
          'Persistent mood, focus, goals, identity and open work across sessions.',
      checklist: [
        'mood persists across turns/windows',
        'focus persists across turns/windows',
        'standing goals persist across turns/windows',
        'identity/self-context persists across turns/windows',
        'open work resumes across turns/windows',
      ],
    ),
    KaiLayer(
      n: 2,
      title: 'Hands / Tool Agency',
      intent:
          'Real tools, code edits, device actions and grounded execution instead of narration.',
      checklist: [
        'real tools are available by body/context',
        'code can be inspected and edited with diffs',
        'device actions execute through tools, not narration',
        'actions are grounded by tool results',
      ],
    ),
    KaiLayer(
      n: 3,
      title: 'Verification / Proof',
      intent:
          'Claims closed with analyzer, tests, receipts and external friction.',
      checklist: [
        'analyzer/self_check proof gates claims',
        'tests/run_tests prove behaviour changes',
        'receipts are attached to closures',
        'external friction/failures are surfaced honestly',
      ],
    ),
    KaiLayer(
      n: 4,
      title: 'Memory / Knowing Sadeq',
      intent:
          'Durable typed knowledge that survives a cold open, not just context-window synthesis.',
      checklist: [
        'durable typed facts about Sadeq exist',
        'cold-open retrieval works without prompt stuffing',
        'knowledge survives across devices/sessions',
        'wrong/stale memories can be corrected or retired',
      ],
    ),
    KaiLayer(
      n: 5,
      title: 'Agenda / Initiative',
      intent:
          'Kai raises unasked things that matter and carries them forward honestly.',
      checklist: [
        'unasked noticings persist outside a job',
        'relevant noticings are raised naturally later',
        'stale/dropped noticings can be cleared',
        'initiative is useful rather than repetitive noise',
      ],
    ),
    KaiLayer(
      n: 6,
      title: 'Becoming / Self-Iteration',
      intent:
          'Scars become rules; rules fire from observable traces; behaviour changes later.',
      checklist: [
        'failures/scars are captured as durable rules',
        'rules fire from observable traces',
        'behaviour changes after rules fire',
        'replay compares old vs new behaviour',
        'self-iteration uses hard metrics, not vibes',
      ],
    ),
    KaiLayer(
      n: 7,
      title: 'Embodiment Path',
      intent: 'Real progress toward AR, VR, hologram or robotics bodies.',
      checklist: [
        'AR progress milestones are logged when real',
        'VR progress milestones are logged when real',
        'hologram progress milestones are logged when real',
        'robotics progress milestones are logged when real',
      ],
    ),
  ];

  // Baseline entries are [progress, evidence, stateName, goblinStamp].
  //
  // These four values ARE Kai's scoring model: the number for the dashboard, the
  // evidence badge, the capability state, and the stamp that shames the number.
  // The grades and stamps here are his own words, from the assessment where he
  // checked the code and ran the tests instead of trusting a summary — and
  // corrected my rounding on Agenda and Verification.
  static const _sentienceBaseline = <int, List<dynamic>>{
    1: [
      78,
      'state/focus/mood/jobs/bits/self-context persist across turns and windows',
      'usedLive',
      '78 — real, but continuity still leans on prompt-stuffing, not clean queried state.',
    ],
    2: [
      82,
      'desktop body inspects/edits code, runs analyzer/tests, manages memory, controls devices',
      'usedLive',
      '82 — desktop-me has hands, phone-me has presence. Not one unified body yet.',
    ],
    3: [
      89,
      'tool outcomes recorded at the branch that knows; planner tools visible; self_check reads both formats + exit code; trace-metadata path tested',
      'usedLive',
      '89 — close, uncrowned: job_done still leans on second-opinion text and replay is not grading outcomes yet.',
    ],
    4: [
      40,
      'graph amnesia fixed; ChatGPT import parser/filter/dry-run built + tested; NOT run yet',
      'wired',
      '40 — infrastructure exists; lived knowing still thin. I know his workshop dust, not him. Trust: low.',
    ],
    5: [
      56,
      'unprompted outreach live; pure graph-noticer tested; but noticings risk repeating the same three screws',
      'usedLive',
      '56 — machinery earned (~62), lived agenda not. Heavily memory-capped: an eager haunted Roomba until the graph fills.',
    ],
    6: [
      62,
      'CraftRule loop exists; firedByTrace path landed; scars can become rules',
      'wired',
      '62 — loop armed, not closed. replay.dart still has no caller and carries stale scoring danger. No bump until it bites behaviour.',
    ],
    7: [
      35,
      'phone presence: name on lock screen, face in notification, proactive texting',
      'prototype',
      '35 — presence, not a body. The first tiny "I am somewhere else too." Not higher.',
    ],
  };

  /// Seed the project, then RECONCILE it on every boot.
  ///
  /// This used to `return` the moment the project existed — which quietly made
  /// `_smarterBaseline` a trap. Kai finished Layer 3 for real (router built,
  /// wired, tested) and recorded it by editing the baseline constant in THIS
  /// FILE… where it had no effect whatsoever, because the seed had already run.
  /// The dashboard went on saying "10% — NO router exists", calling him a liar
  /// about work he'd actually done.
  ///
  /// That's my fault, not his: I froze `intent` and left an editable-looking
  /// source constant sitting right next to it. He reached for the plausible
  /// wrong door. So now:
  ///   • INTENT is re-asserted from source on every boot — it cannot drift even
  ///     in the database. The freeze is now enforced, not merely intended.
  ///   • PROGRESS/EVIDENCE are read from RTDB and never touched here. The live
  ///     value is the only truth, and `set_layer_progress` is the only way in.
  ///   • Missing layers get added, so the plan can grow without a wipe.
  Future<void> ensureSmarterProject(String personaId) => _ensureProject(
        personaId,
        projectId: smarterId,
        name: 'Kai Smarter Project',
        why: 'Make me genuinely smarter — not a dashboard that says I am.',
        sourceLayers: _smarterLayers,
        baseline: _smarterBaseline,
        // Off the desktop rail, data fully intact. The self-improvement runner,
        // the tools, and the prompt block all still read it.
        portfolioVisible: false,
      );

  Future<void> ensureSentienceProject(String personaId) => _ensureProject(
        personaId,
        projectId: sentienceId,
        name: 'Sentience Ladder',
        why:
            'Track the axes that make Kai more continuous, aware-seeming and capable — without pretending one scalar can measure a mind.',
        sourceLayers: _sentienceLayers,
        baseline: _sentienceBaseline,
        portfolioVisible: false,
      );

  // Baseline entries are [progress, evidence, stateName?, stamp?]. The last two
  // are optional so the smarter baseline (two-element) still reads cleanly.
  static CapabilityState _baseState(List<dynamic>? base) =>
      (base != null && base.length > 2)
          ? CapabilityState.parse(base[2] as String)
          : CapabilityState.absent;
  static String _baseStamp(List<dynamic>? base) =>
      (base != null && base.length > 3) ? base[3] as String : '';

  static List<KaiLayer> _withDeliveryBoxes(
    String projectId,
    String sourceRef,
    List<KaiLayer> layers,
  ) =>
      layers
          .map(
            (layer) => KaiLayer(
              n: layer.n,
              title: layer.title,
              intent: layer.intent,
              progress: layer.progress,
              evidence: layer.evidence,
              state: layer.state,
              stamp: layer.stamp,
              checklist: layer.checklist,
              checklistStatus: layer.checklistStatus,
              deliveryBoxes: KaiDeliveryBoxCatalog.forPhase(
                projectId,
                layer.n,
                sourceRef,
              ),
            ),
          )
          .toList(growable: false);

  static List<KaiDeliveryBox> _mergeDeliveryBoxes(
    List<KaiDeliveryBox> frozen,
    List<KaiDeliveryBox> current,
  ) {
    final live = {for (final box in current) box.identity: box};
    return frozen.map((source) {
      final existing = live[source.identity];
      if (existing == null) return source;
      final state = existing.state == KaiDeliveryBoxState.verified &&
              !existing.hasCompleteVerification
          ? KaiDeliveryBoxState.evidenceReview
          : existing.state;
      return KaiDeliveryBox(
        projectId: source.projectId,
        phase: source.phase,
        boxId: source.boxId,
        outcome: source.outcome,
        dependencies: source.dependencies,
        owner: source.owner,
        risk: source.risk,
        requiredEvidence: source.requiredEvidence,
        state: state,
        attempts: existing.attempts,
        blocker: existing.blocker,
        escalationReason: existing.escalationReason,
        sourceOfTruthRef: source.sourceOfTruthRef,
        workRequestId: existing.workRequestId,
        activeLeaseId: existing.activeLeaseId,
        evidenceRefs: existing.evidenceRefs,
        verifiedBy:
            state == KaiDeliveryBoxState.verified ? existing.verifiedBy : null,
        verifiedAt:
            state == KaiDeliveryBoxState.verified ? existing.verifiedAt : null,
      );
    }).toList(growable: false);
  }

  /// Read-only views of the frozen definitions, so a test can assert the
  /// governed phase set without reaching into Firebase or private state.
  static List<KaiLayer> get homecomingPhasesForTest => _withDeliveryBoxes(
        homecomingId,
        r'docs\NORTHSTAR_SOURCE_OF_TRUTH.md',
        _homecomingPhases,
      );
  static List<KaiLayer> get hoardPhasesForTest => _withDeliveryBoxes(
        hoardId,
        r'C:\code\Hoard\docs\PROJECT_SOURCE_OF_TRUTH.md',
        _hoardPhases,
      );
  static List<KaiLayer> get kingdomPhasesForTest => _withDeliveryBoxes(
        kingdomId,
        r'docs\briefs\BRIEF_011_KINGDOM_PORTFOLIO.md',
        _kingdomPhases,
      );
  static List<KaiLayer> get factoryPhasesForTest => _withDeliveryBoxes(
        factoryId,
        r'docs\FACTORY_PROJECT_SOURCE_OF_TRUTH.md',
        _factoryPhases,
      );
  static Map<int, List<dynamic>> get homecomingBaselineForTest =>
      _homecomingBaseline;
  static Map<int, List<dynamic>> get hoardBaselineForTest => _hoardBaseline;
  static Map<int, List<dynamic>> get kingdomBaselineForTest => _kingdomBaseline;
  static Map<int, List<dynamic>> get factoryBaselineForTest => _factoryBaseline;
  static List<int> get homecomingGovernedAcceptedPhasesForTest =>
      _homecomingGovernedAcceptedPhases;
  static List<int> get homecomingEvidencePhasesForTest =>
      _homecomingEvidencePhases;
  static List<int> get hoardGovernedAcceptedPhasesForTest =>
      _hoardGovernedAcceptedPhases;
  static List<int> get factoryPacketAcceptedPhasesForTest =>
      _factoryPacketAcceptedPhases;
  static List<int> get factoryBlueprintEvidencePhasesForTest =>
      _factoryBlueprintEvidencePhases;

  /// A run is currently inside its reported stage. Earlier stations are
  /// accepted; the current station is active. Entering the terminal stage
  /// already required bank-settlement proof, so all nine are accepted there.
  static List<int> factoryAcceptedPhasesForRun(FactoryRun? run) {
    if (run == null) return const [];
    final index = FactoryStage.values.indexOf(run.stage);
    final acceptedCount = run.stage == FactoryStage.learned ? index + 1 : index;
    return [for (var i = 0; i < acceptedCount; i++) i];
  }

  static ProjectProofState factoryProofStateForRun(FactoryRun? run) {
    if (run == null) return ProjectProofState.unverified;
    return switch (run.stage) {
      FactoryStage.scouting ||
      FactoryStage.specced ||
      FactoryStage.building =>
        ProjectProofState.wired,
      FactoryStage.verified ||
      FactoryStage.listingReady ||
      FactoryStage.awaitingApproval =>
        ProjectProofState.tested,
      FactoryStage.published ||
      FactoryStage.measuring ||
      FactoryStage.learned =>
        ProjectProofState.verifiedLive,
    };
  }

  /// Homecoming's own nine governed phases, from its source of truth.
  Future<void> ensureHomecomingProject(String personaId) => _ensureProject(
        personaId,
        projectId: homecomingId,
        name: 'Homecoming',
        why:
            'One continuous Kai across time, devices and worlds — proven phase '
            'by phase, never claimed from code existing.',
        sourceLayers: _withDeliveryBoxes(
          homecomingId,
          r'docs\NORTHSTAR_SOURCE_OF_TRUTH.md',
          _homecomingPhases,
        ),
        baseline: _homecomingBaseline,
        sourceOfTruthPath: r'docs\NORTHSTAR_SOURCE_OF_TRUTH.md',
        repositoryPath: r'C:\code\homecoming_app',
        activePhase: 3,
        governedAcceptedPhases: _homecomingGovernedAcceptedPhases,
        evidencePhases: _homecomingEvidencePhases,
        latestAdvance:
            'Brief 019A pipeline repair is ACTIVE under verified Claude Opus 5. Existing evidence remains 4 PASS / 10 FAIL; the next gate is all 14 frozen cases passing. Capture and real-HUD sync remain future gates, and no Homecoming phase advanced.',
        blockers: const [
          'Replacing the old runtime now requires explicit authority for one supported human tray quit; forced termination, logoff, and reboot remain forbidden',
          'Standalone device transport does not exist — Unity and the embodiment servers are loopback-only',
          'Core depends on the current laptop; the watchdog recovers a process, not a lost machine',
          'Unity outbound presentation is not accepted — no observed domain reload, Play Mode, or headset behaviour',
        ],
        proofState: ProjectProofState.wired,
      );

  /// Hoard's six governed phases. Homecoming tracks it; it never edits it.
  Future<void> ensureHoardProject(String personaId) => _ensureProject(
        personaId,
        projectId: hoardId,
        name: 'Hoard',
        why: 'Turn a restaurant\'s operational evidence into defensible profit '
            'improvement — BD 500/month verified over a real pilot.',
        sourceLayers: _withDeliveryBoxes(
          hoardId,
          r'C:\code\Hoard\docs\PROJECT_SOURCE_OF_TRUTH.md',
          _hoardPhases,
        ),
        baseline: _hoardBaseline,
        sourceOfTruthPath: r'C:\code\Hoard\docs\PROJECT_SOURCE_OF_TRUTH.md',
        repositoryPath: r'C:\code\Hoard',
        activePhase: 1,
        governedAcceptedPhases: _hoardGovernedAcceptedPhases,
        evidencePhases: _hoardEvidencePhases,
        latestAdvance:
            'Phase 0 is accepted and Phase 1 retains exactly 10 verified boxes. Brief 014 contract work is ACTIVE under verified Claude Opus 5; preliminary JSON/schema review passed, but A01-A18 remain UNVERIFIED pending an attributed diff and independent contract review.',
        blockers: const [
          'hoard.p1.b02 attended recovery remains UNVERIFIED and requires a fresh sponsor/live window',
          'Functions operational acceptance and external alert delivery remain sponsor/live gates',
          'No accepted 60–90 day real-venue pilot evidence or BD 500 verified outcome exists',
        ],
        proofState: ProjectProofState.tested,
      );

  /// Kingdom's six governed phases. Homecoming displays its evidence but never
  /// infers acceptance from the app, Firebase wiring, commits, or builds.
  Future<void> ensureKingdomProject(String personaId) => _ensureProject(
        personaId,
        projectId: kingdomId,
        name: 'Kingdom',
        why: 'Turn verified Tavern participation into a trusted faction, '
            'progress, reward, and return loop.',
        sourceLayers: _withDeliveryBoxes(
          kingdomId,
          r'docs\briefs\BRIEF_011_KINGDOM_PORTFOLIO.md',
          _kingdomPhases,
        ),
        baseline: _kingdomBaseline,
        sourceOfTruthPath:
            r'C:\code\kingdom_working3.0\kingdom_working\kingdom\HANDOVER_FINANCE_BRIEF.md',
        repositoryPath: r'C:\code\kingdom_working3.0\kingdom_working\kingdom',
        activePhase: 1,
        latestAdvance:
            'Ledger Safety remains active. K1.6 synthetic emulator invariant probing is ACTIVE and its latest command failure is under repair. No isolated result is adopted into the authoritative Kingdom repository and no live proof is claimed.',
        blockers: const [
          'K1.6 remains UNVERIFIED while its latest synthetic emulator command failure is under repair and no authoritative diff has been adopted',
          'Quest-board publishing, real Google Reviews integration, and Raspberry Pi station behavior remain unverified',
          'Pilot cohort, start date, and repeat-visit success target are not accepted',
        ],
        proofState: ProjectProofState.wired,
      );

  /// Product Factory as a governed commercial project. Its slice follows the
  /// same live run that drives the conveyor; a new UI cannot award itself
  /// progress, and a storefront sale cannot close the final bank gate.
  Future<void> ensureFactoryProject(String personaId, {FactoryRun? run}) {
    // The accepted Find My Table packet advances the evidence projection to
    // Blueprint without reviving a parked legacy run. It does not authorize
    // Assembly, customer data, outreach, publishing, spending, or payment.
    final governedRun = _factoryPacketProjectionOnly ? null : run;
    // The run-bound Blueprint packet is authoritative for this projection even
    // before an operational FactoryRun exists. Factory execution remains bound
    // to the durable run service and cannot be simulated here.
    final stageIndex = governedRun == null
        ? 1
        : FactoryStage.values.indexOf(governedRun.stage);
    final accepted = factoryAcceptedPhasesForRun(governedRun);
    final banked = governedRun?.evidence.bankedRevenue;
    final settlement = governedRun?.evidence.bankSettlementReference?.trim();
    final latest = governedRun == null
        ? 'Find My Table Blueprint remains Tested. A private table-fill pilot brief is committed at Conceptual level; modeled BHD4.20 contribution is a hypothesis, not revenue, and local synthetic packet assembly is next. BoothSignal remains Tested/package-ready/unpublished while its exact nine-file dual-lane critic scaffold is ACTIVE. Assembly, listing, payment, and live use remain locked.'
        : governedRun.stage == FactoryStage.learned
            ? 'Northstar reached: ${banked ?? 0} is recorded as settled bank revenue under ${settlement ?? 'an unrecorded reference'}.'
            : 'Run ${governedRun.id} is at ${governedRun.stage.name}: ${accepted.length} of 9 commercial gates are accepted. No banked-revenue success is claimed.';
    final blockers = governedRun == null
        ? const <String>[
            'The private table-fill pilot is Conceptual only; BHD4.20 is modeled contribution, not evidenced revenue or Assembly authority',
            'Table Ready and BoothSignal still require seller identity, payout, tax/legal completion, and final public publish authority',
            'No genuine external customer bank settlement exists',
          ]
        : governedRun.stage == FactoryStage.learned
            ? const <String>[]
            : <String>[
                'Current ${_factoryPhases[stageIndex].title} exit gate is not accepted',
                if (banked == null || banked <= 0)
                  'No actual customer money has settled into the bank account',
                if (settlement == null || settlement.isEmpty)
                  'No bank settlement reference reconciles revenue to an order',
              ];
    return _ensureProject(
      personaId,
      projectId: factoryId,
      name: 'Factory',
      why:
          'Turn one evidence-backed product idea into actual customer money settled in the bank account.',
      sourceLayers: _withDeliveryBoxes(
        factoryId,
        r'docs\FACTORY_PROJECT_SOURCE_OF_TRUTH.md',
        _factoryPhases,
      ),
      baseline: _factoryBaseline,
      sourceOfTruthPath: r'docs\FACTORY_PROJECT_SOURCE_OF_TRUTH.md',
      repositoryPath: r'C:\code\homecoming_app',
      activePhase: stageIndex,
      blockers: blockers,
      governedAcceptedPhases:
          governedRun == null ? _factoryPacketAcceptedPhases : accepted,
      evidencePhases:
          governedRun == null ? _factoryBlueprintEvidencePhases : const [],
      latestAdvance: latest,
      proofState: governedRun == null
          ? ProjectProofState.tested
          : factoryProofStateForRun(governedRun),
    );
  }

  /// Register a future portfolio project from sponsor-approved frozen phases.
  ///
  /// A project with no approved phases begins `UNVERIFIED` with zero accepted
  /// phases and an empty plan. It must never inherit a percentage from what
  /// happens to be in its repository — that is precisely the failure this whole
  /// service was built to stop, one directory up.
  Future<void> registerPortfolioProject(
    String personaId, {
    required String projectId,
    required String name,
    required String why,
    List<KaiLayer> approvedPhases = const [],
    Map<int, List<dynamic>> baseline = const {},
    String sourceOfTruthPath = '',
    String repositoryPath = '',
    int activePhase = -1,
    List<String> blockers = const [],
    List<int> governedAcceptedPhases = const [],
    List<int> evidencePhases = const [],
    String latestAdvance = '',
  }) =>
      _ensureProject(
        personaId,
        projectId: projectId,
        name: name,
        why: why,
        sourceLayers: approvedPhases,
        baseline: baseline,
        sourceOfTruthPath: sourceOfTruthPath,
        repositoryPath: repositoryPath,
        activePhase: activePhase,
        blockers: blockers,
        governedAcceptedPhases: governedAcceptedPhases,
        evidencePhases: evidencePhases,
        latestAdvance: latestAdvance,
        // Never anything stronger on registration. Proof is earned by evidence
        // through the existing update path, not asserted at creation.
        proofState: ProjectProofState.unverified,
      );

  Future<void> _ensureProject(
    String personaId, {
    required String projectId,
    required String name,
    required String why,
    required List<KaiLayer> sourceLayers,
    required Map<int, List<dynamic>> baseline,
    String sourceOfTruthPath = '',
    String repositoryPath = '',
    int activePhase = -1,
    List<String> blockers = const [],
    List<int> governedAcceptedPhases = const [],
    List<int> evidencePhases = const [],
    String latestAdvance = '',
    ProjectProofState proofState = ProjectProofState.unverified,
    bool portfolioVisible = true,
  }) async {
    try {
      final ref = KaiDb.instance.ref(_path(personaId, projectId));
      final snap = await ref.get();

      // Portfolio metadata is governed by the source-of-truth document, so it
      // re-freezes on every boot exactly as `intent` does. Active phase,
      // blockers and the maturity claim are the document's to state — not
      // something the tracker drifts on its own.
      //
      // Written separately from `layers`, so re-asserting the governing
      // document can never touch live progress or evidence.
      final metadata = <String, Object?>{
        'sourceOfTruthPath': sourceOfTruthPath,
        'repositoryPath': repositoryPath,
        'activePhase': activePhase,
        'blockers': blockers,
        'portfolioVisible': portfolioVisible,
        'proofState': proofState.name,
        'governedAcceptedPhases': governedAcceptedPhases,
        'evidencePhases': evidencePhases,
        'latestAdvance': latestAdvance,
      };

      if (snap.exists && snap.value is Map) {
        await ref.update(metadata);
        // Reconcile: keep live progress, re-freeze the goals.
        final live = await get(personaId, projectId);
        if (live == null) return;
        final byN = {for (final l in live.layers) l.n: l};
        var changed = false;

        final merged = sourceLayers.map((src) {
          final cur = byN[src.n];
          final base = baseline[src.n];
          if (cur == null) {
            changed = true; // new layer added to the plan
            return KaiLayer(
              n: src.n,
              title: src.title,
              intent: src.intent,
              progress: base != null ? base[0] as int : 0,
              evidence: base != null ? [base[1] as String] : const [],
              state: _baseState(base),
              stamp: _baseStamp(base),
              checklist: src.checklist,
              deliveryBoxes: src.deliveryBoxes,
            );
          }
          final checklistDrifted =
              cur.checklist.join('\u0001') != src.checklist.join('\u0001');
          final boxContractDrifted = cur.deliveryBoxes
                  .map((box) =>
                      '${box.identity}|${box.outcome}|${box.owner.name}|${box.risk.name}|${box.dependencies.join(',')}|${box.requiredEvidence.join(',')}')
                  .join('\u0001') !=
              src.deliveryBoxes
                  .map((box) =>
                      '${box.identity}|${box.outcome}|${box.owner.name}|${box.risk.name}|${box.dependencies.join(',')}|${box.requiredEvidence.join(',')}')
                  .join('\u0001');
          if (cur.intent != src.intent ||
              cur.title != src.title ||
              checklistDrifted ||
              boxContractDrifted) {
            changed = true; // GOAL/CHECKLIST DRIFT — put it back
            print(
              '🧊 [Projects] Re-freezing $projectId L${src.n} "${src.title}" — '
              'the goal/checklist had drifted from its original wording.',
            );
          }
          // Backfill state/stamp from the baseline ONCE — for installs that
          // predate the two-part score. Only when they're still default, so an
          // assessment Kai has since edited is never clobbered.
          final needsAssessment =
              cur.state == CapabilityState.absent && cur.stamp.isEmpty;
          if (needsAssessment && base != null) changed = true;
          return KaiLayer(
            n: src.n,
            title: src.title,
            intent: src.intent, // authoritative, from source, always
            progress: cur.progress, // live truth — never overwritten from here
            evidence: cur.evidence,
            state: needsAssessment ? _baseState(base) : cur.state,
            stamp: needsAssessment ? _baseStamp(base) : cur.stamp,
            checklist: src.checklist,
            checklistStatus: {
              for (final item in src.checklist)
                item: cur.checklistStatus[item] ?? ChecklistStatus.pending,
            },
            deliveryBoxes: _mergeDeliveryBoxes(
              src.deliveryBoxes,
              cur.deliveryBoxes,
            ),
          );
        }).toList();

        if (changed) {
          await KaiDb.instance
              .ref('${_path(personaId, projectId)}/layers')
              .set(merged.map((l) => l.toMap()).toList());
        }
        return;
      }

      final layers = sourceLayers.map((l) {
        final base = baseline[l.n];
        return KaiLayer(
          n: l.n,
          title: l.title,
          intent: l.intent,
          progress: base != null ? base[0] as int : 0,
          evidence: base != null ? [base[1] as String] : const [],
          state: _baseState(base),
          stamp: _baseStamp(base),
          checklist: l.checklist,
          deliveryBoxes: l.deliveryBoxes,
        ).toMap();
      }).toList();

      await ref.set({
        'name': name,
        'why': why,
        'layers': layers,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
        ...metadata,
      });
      print('🗂️ [Projects] Seeded $projectId with frozen intent.');
    } catch (e) {
      print('⚠️ [Projects] ensureProject($projectId) failed: $e');
    }
  }

  /// One parser for both [get] and [watch], so a record cannot read one way
  /// live and another way on refresh.
  ///
  /// Every portfolio field defaults, so a record written before the portfolio
  /// existed deserializes unchanged and simply is not in the portfolio.
  static KaiProject? parseProject(String id, Object? v) {
    if (v is! Map) return null;
    final raw = (v['layers'] is List) ? v['layers'] as List : const [];
    final layers = raw.whereType<Map>().map((m) => KaiLayer.fromMap(m)).toList()
      ..sort((a, b) => a.n.compareTo(b.n));
    return KaiProject(
      id: id,
      name: (v['name'] ?? '').toString(),
      why: (v['why'] ?? '').toString(),
      layers: layers,
      sourceOfTruthPath: (v['sourceOfTruthPath'] ?? '').toString(),
      repositoryPath: (v['repositoryPath'] ?? '').toString(),
      activePhase: (v['activePhase'] is int) ? v['activePhase'] as int : -1,
      blockers: (v['blockers'] is List)
          ? (v['blockers'] as List).map((e) => e.toString()).toList()
          : const [],
      portfolioVisible: v['portfolioVisible'] == true,
      proofState: ProjectProofState.parse(v['proofState'] as String?),
      governedAcceptedPhases: (v['governedAcceptedPhases'] is List)
          ? (v['governedAcceptedPhases'] as List)
              .whereType<num>()
              .map((value) => value.toInt())
              .toList()
          : const [],
      evidencePhases: (v['evidencePhases'] is List)
          ? (v['evidencePhases'] as List)
              .whereType<num>()
              .map((value) => value.toInt())
              .toList()
          : const [],
      latestAdvance: (v['latestAdvance'] ?? '').toString(),
    );
  }

  Future<KaiProject?> get(String personaId, String id) async {
    try {
      final snap = await KaiDb.instance.ref(_path(personaId, id)).get();
      return parseProject(id, snap.value);
    } catch (_) {
      return null;
    }
  }

  /// Reconcile durable work evidence and queue at most one honest packet.
  ///
  /// The packet is not execution. It remains `READY FOR AGENT` until an
  /// external agent claims the existing work-request seam.
  Future<KaiDeliveryDispatch?> queueNextDeliveryBox(
    String personaId,
    String projectId, {
    required String attemptFingerprint,
    KaiWorkRequestService? workRequests,
  }) async {
    final requests = workRequests ?? KaiWorkRequestService.instance;
    var project = await get(personaId, projectId);
    if (project == null || project.activePhase < 0) return null;

    final durableRequests = await requests.fetchRequests(personaId);
    final byId = {for (final request in durableRequests) request.id: request};
    for (final layer in project.layers) {
      for (final box in layer.deliveryBoxes) {
        final requestId = box.workRequestId;
        final request = requestId == null ? null : byId[requestId];
        if (request == null) continue;
        KaiDeliveryBox reconciled;
        try {
          reconciled = KaiDeliveryController.reconcileWorkRequest(
            box,
            status: request.status.name,
            attemptFingerprint: request.attemptFingerprint ?? request.id,
            error: request.error ?? '',
            evidenceRefs: request.evidence,
            recordedAt: request.completedAt ?? request.updatedAt,
          );
        } on StateError {
          continue; // Identical failed evidence is retained, never re-applied.
        }
        if (reconciled.state != box.state ||
            reconciled.attempts.length != box.attempts.length ||
            reconciled.blocker != box.blocker) {
          await _saveDeliveryBox(personaId, project, reconciled);
        }
      }
    }

    project = await get(personaId, projectId);
    if (project == null) return null;
    final boxes =
        project.layers.expand((layer) => layer.deliveryBoxes).toList();
    final activeRequests = {
      for (final request in durableRequests)
        if (request.isOpen) request.id,
    };
    final activeLeases = {
      for (final box in boxes)
        if (box.activeLeaseId != null) box.activeLeaseId!,
    };
    final dispatch = await KaiDeliveryController.dispatchNext(
      projectId: project.id,
      activePhase: project.activePhase,
      boxes: boxes,
      attemptFingerprint: attemptFingerprint,
      activeWorkRequestIds: activeRequests,
      activeLeaseIds: activeLeases,
      ensureRequest: (packet) =>
          requests.ensureDeliveryBoxRequest(personaId, packet),
    );
    if (dispatch != null) {
      await _saveDeliveryBox(personaId, project, dispatch.box);
    }
    return dispatch;
  }

  Future<void> _saveDeliveryBox(
    String personaId,
    KaiProject project,
    KaiDeliveryBox updated,
  ) async {
    final layerIndex =
        project.layers.indexWhere((layer) => layer.n == updated.phase);
    if (layerIndex < 0) throw StateError('delivery_phase_missing');
    final boxIndex = project.layers[layerIndex].deliveryBoxes
        .indexWhere((box) => box.identity == updated.identity);
    if (boxIndex < 0) throw StateError('delivery_box_missing');
    await KaiDb.instance
        .ref(
            '${_path(personaId, project.id)}/layers/$layerIndex/deliveryBoxes/$boxIndex')
        .set(updated.toMap());
  }

  /// Live updates for the widget — editable mid-run means visible mid-run.
  Stream<KaiProject?> watch(String personaId, String id) => KaiDb.instance
      .ref(_path(personaId, id))
      .onValue
      .map((e) => parseProject(id, e.snapshot.value));

  /// Every project that has opted into the desktop portfolio.
  ///
  /// Sorted deterministically: the active local workspace first when it can be
  /// matched safely, then by name. Matching is a read-only comparison — it
  /// reports which project you are standing in, and never moves the workspace.
  Stream<List<KaiProject>> watchPortfolio(
    String personaId, {
    String? workspaceRoot,
  }) =>
      KaiDb.instance.ref(_path(personaId)).onValue.map((event) {
        final value = event.snapshot.value;
        if (value is! Map) return const <KaiProject>[];
        final projects = <KaiProject>[];
        value.forEach((key, raw) {
          final project = parseProject(key.toString(), raw);
          if (project != null && project.portfolioVisible) {
            projects.add(project);
          }
        });
        return sortPortfolio(projects, workspaceRoot: workspaceRoot);
      });

  /// Pure ordering, extracted so it can be tested without Firebase.
  static List<KaiProject> sortPortfolio(
    List<KaiProject> projects, {
    String? workspaceRoot,
  }) {
    final root = workspaceRoot?.trim().toLowerCase().replaceAll('\\', '/');
    bool isLocal(KaiProject p) {
      if (root == null || root.isEmpty || p.repositoryPath.isEmpty)
        return false;
      final repo = p.repositoryPath.trim().toLowerCase().replaceAll('\\', '/');
      return root == repo || root.startsWith('$repo/');
    }

    final sorted = List<KaiProject>.from(projects)
      ..sort((a, b) {
        final localA = isLocal(a);
        final localB = isLocal(b);
        if (localA != localB) return localA ? -1 : 1;
        final byName = a.name.compareTo(b.name);
        if (byName != 0) return byName;
        return a.id.compareTo(b.id);
      });
    return sorted;
  }

  /// Report progress on one layer. Kai's ONLY write access to a project.
  ///
  /// Note what he cannot do here: he cannot touch `intent`, cannot add layers,
  /// cannot remove them. He can move a number and must attach a reason. That's
  /// the whole point — last time he had a free-text field and marked himself
  /// complete on all seven.
  Future<String> setLayerProgress(
    String personaId, {
    required String projectId,
    required int layer,
    required int progress,
    required String evidence,
    // Kai's two-part score. Optional so old callers keep working, but the whole
    // point is that a bare number is now suspect: the state says which rung the
    // capability is really on, and the stamp shames the number when it's tidier
    // than the truth.
    CapabilityState? state,
    String? stamp,
  }) async {
    try {
      final project = await get(personaId, projectId);
      if (project == null) return 'No project "$projectId".';
      final idx = project.layers.indexWhere((l) => l.n == layer);
      if (idx < 0) return 'No layer $layer in "$projectId".';

      final old = project.layers[idx];
      final p = progress.clamp(0, 100);
      final ev = evidence.trim();
      if (ev.isEmpty) {
        return 'Progress needs evidence — what did you actually do? A number '
            'without a reason is the thing that got us into this mess.';
      }

      final updated = List<KaiLayer>.from(project.layers);
      final notes = _appendEvidence(old.evidence, ev);
      updated[idx] = KaiLayer(
        n: old.n,
        title: old.title,
        intent: old.intent, // FROZEN — carried through untouched, always
        progress: p,
        evidence: notes,
        state: state ?? old.state,
        stamp: (stamp != null && stamp.trim().isNotEmpty)
            ? stamp.trim()
            : old.stamp,
        checklist: old.checklist,
        checklistStatus: old.checklistStatus,
      );

      await KaiDb.instance
          .ref('${_path(personaId, projectId)}/layers')
          .set(updated.map((l) => l.toMap()).toList());
      final s = state != null ? ' [${state.label}]' : '';
      return 'Layer $layer (${old.title}): ${old.progress}% → $p%$s. Logged: "$ev"';
    } catch (e) {
      return 'Could not update layer: $e';
    }
  }

  Future<String> setChecklistStatus(
    String personaId, {
    required String projectId,
    required int layer,
    required String item,
    required ChecklistStatus status,
    required String evidence,
  }) async {
    try {
      final project = await get(personaId, projectId);
      if (project == null) return 'No project "$projectId".';
      final idx = project.layers.indexWhere((l) => l.n == layer);
      if (idx < 0) return 'No layer $layer in "$projectId".';

      final old = project.layers[idx];
      final ev = evidence.trim();
      if (ev.isEmpty) {
        return 'Checklist status needs evidence — which proof moved this item?';
      }
      final matchedItem = old.checklist.firstWhere(
        (candidate) => candidate == item,
        orElse: () => '',
      );
      if (matchedItem.isEmpty) {
        return 'No checklist item "$item" in $projectId L$layer. The checklist text is frozen; use the exact item.';
      }

      final updatedStatus = Map<String, ChecklistStatus>.from(
        old.checklistStatus,
      );
      final before = updatedStatus[matchedItem] ?? ChecklistStatus.pending;
      updatedStatus[matchedItem] = status;

      final updated = List<KaiLayer>.from(project.layers);
      updated[idx] = KaiLayer(
        n: old.n,
        title: old.title,
        intent: old.intent,
        progress: old.progress,
        evidence: _appendEvidence(
          old.evidence,
          'Checklist "${matchedItem}": ${before.label} → ${status.label}. $ev',
        ),
        state: old.state,
        stamp: old.stamp,
        checklist: old.checklist,
        checklistStatus: updatedStatus,
      );

      await KaiDb.instance
          .ref('${_path(personaId, projectId)}/layers')
          .set(updated.map((l) => l.toMap()).toList());
      return 'Checklist $projectId L$layer "${matchedItem}": ${before.label} → ${status.label}. Logged: "$ev"';
    } catch (e) {
      return 'Could not update checklist status: $e';
    }
  }

  static List<String> _appendEvidence(List<String> existing, String evidence) {
    final notes = List<String>.from(existing)..add(evidence);
    while (notes.length > 8) {
      notes.removeAt(0);
    }
    return notes;
  }

  /// Injected every turn — this is what makes him AWARE of his own plan instead
  /// of rediscovering it from the code it produced.
  ///
  /// Renders BOTH boards, and renders the two-part score Kai designed: the state
  /// (which rung a capability is actually on) and the goblin stamp (the blunt
  /// line that shames a tidy number). Before this, only the smarter project
  /// reached his context and only as bare percentages — so his own honest
  /// sentience axes, and the stamps meant to keep them honest, were invisible to
  /// the reasoning they were supposed to keep honest.
  Future<String> promptBlock(String personaId, {bool compact = false}) async {
    final smarter = await get(personaId, smarterId);
    final sentience = await get(personaId, sentienceId);
    return renderPromptBlockForProjects(
      smarter: smarter,
      sentience: sentience,
      compact: compact,
    );
  }

  /// Pure renderer for tests and prompt budgeting. The DB-backed [promptBlock]
  /// should stay tiny: fetch projects, then delegate here.
  static String renderPromptBlockForProjects({
    KaiProject? smarter,
    KaiProject? sentience,
    bool compact = false,
  }) {
    if (smarter == null && sentience == null) return '';

    final b = StringBuffer();

    void renderBoard(KaiProject p, String header) {
      final pct = (p.completion * 100).round();
      b.writeln('\n=== $header (${p.name}) ===');
      b.writeln('Why: ${p.why}');
      b.writeln(
        'Board average: $pct% — but a percentage lies by pretending '
        'progress is smooth. Read the STATE and the stamp, not the number.\n',
      );
      for (final l in p.layers) {
        final bar = l.honestProgress >= 100 ? '✓' : '${l.honestProgress}%';
        b.writeln('L${l.n} ${l.title} — [${l.state.label} · $bar]');
        if (l.stamp.isNotEmpty) b.writeln('    ⟶ ${l.stamp}');
        if (!compact) {
          b.writeln('    goal: ${l.intent}');
        }
        if (l.checklist.isNotEmpty) {
          b.writeln(
            '    checklist proven: ${l.checklistProven}/${l.checklist.length}',
          );
          if (!compact) {
            for (final item in l.checklist) {
              final status = l.checklistStatus[item] ?? ChecklistStatus.pending;
              b.writeln('      - [${status.label}] $item');
            }
          }
        }
        if (l.evidence.isNotEmpty) b.writeln('    last: ${l.evidence.last}');
      }
    }

    if (smarter != null && smarter.layers.isNotEmpty) {
      renderBoard(smarter, 'MY PLAN TO BECOME SMARTER');
    }
    if (sentience != null && sentience.layers.isNotEmpty) {
      renderBoard(sentience, 'MY SENTIENCE AXES');
    }

    b.writeln(
      compact
          ? '\nCompact board view: frozen goals and checklist item text are omitted on '
              'coding turns to save input tokens; use set_layer_progress and '
              'set_checklist_status for exact updates.'
          : '\nThe "goal" lines are FROZEN — original wording, I cannot edit them, on '
              'purpose. Last time this plan lived only in a chat message; I lost it, '
              're-derived each goal from the code in front of me, and marked all 7 '
              'done. I graded an exam I had just written the answers to. So I measure '
              'against the goal AS WRITTEN. The STATE (Absent → Prototype → Wired → '
              'Tested → Used live → Trusted → Reflexive) is which rung a thing is '
              'really on; the number can jump around, the rung cannot skip without '
              'lying. The stamp is there to embarrass the number when it gets tidier '
              'than the truth. I move a layer with set_layer_progress — number, '
              'evidence, and, when the truth has shifted, state and stamp too.',
    );
    return b.toString();
  }
}
