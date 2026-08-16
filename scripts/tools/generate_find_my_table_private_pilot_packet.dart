/// Deterministic generator for the Find My Table private pilot packet.
///
/// Brief 022 synthetic Assembly only. This tool reads nothing from a network,
/// account, credential, receipt, or live repository, sends no message, and
/// performs no public action. Its only side effect is writing eleven local
/// files under the requested output directory.
///
/// Matching, lifecycle, privacy projection, and economics are delegated to the
/// accepted operator in `lib/logic/find_my_table_operator.dart`; this file adds
/// no second matcher. It projects that operator's own records into packet
/// vocabulary and renders them as Markdown and OOXML.
///
/// The OOXML namespace strings below are inert XML identifiers required by the
/// spreadsheet format. They are never dereferenced, resolved, or requested.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:homecoming_app/logic/find_my_table_operator.dart';

// ---------------------------------------------------------------------------
// Packet identity
// ---------------------------------------------------------------------------

const String findMyTablePilotGeneratorVersion =
    'find-my-table-private-pilot-packet-generator-v1';
const String findMyTablePilotContentVersion =
    'find-my-table-private-pilot-content-v1';
const String findMyTablePilotOracleId = 'FMT-PILOT-V1-ORACLE-001';
const String findMyTablePilotWorkbookOracleId =
    'FMT-PILOT-V1-WORKBOOK-ORACLE-001';
const String defaultFindMyTablePilotOutputPath =
    'output/find_my_table_private_pilot_v1';

const String findMyTablePilotManifestArtifact = '00_manifest.md';

const List<String> findMyTablePilotPayloadArtifacts = <String>[
  '01_player_intake.md',
  '02_dm_intake_and_approval.md',
  '03_match_review_workbook.xlsx',
  '04_private_message_templates.md',
  '05_dm_table_brief.md',
  '06_session_run_sheet.md',
  '07_revenue_attribution.xlsx',
  '08_privacy_safety_incident_runbook.md',
  '09_pilot_decision_card.md',
  '10_launch_checklist.md',
];

const List<String> findMyTablePilotArtifacts = <String>[
  findMyTablePilotManifestArtifact,
  ...findMyTablePilotPayloadArtifacts,
];

// ---------------------------------------------------------------------------
// Frozen synthetic fixture identity
// ---------------------------------------------------------------------------

const String pilotSlotId = 'slot-pilot-friday-1900';
const String pilotDmId = 'dm-pilot-001';
const String pilotSystem = 'system-a';
const String pilotLanguage = 'en';
const String pilotAccessibilityNeed = 'step-free';
const String pilotContentBoundary = 'no-pvp';
const String pilotExperimentId = 'experiment-p0-synthetic-001';
const String pilotSyntheticOperatorId = 'SYNTHETIC';
const String pilotProposalId = 'proposal-1-$pilotSlotId';

const String pilotRouteReferral = 'existing_player_referral';
const String pilotRouteVenueInbound = 'venue_inbound';
const String pilotRouteCommunity = 'approved_community_channel';

const List<String> pilotRouteOrder = <String>[
  pilotRouteReferral,
  pilotRouteVenueInbound,
  pilotRouteCommunity,
];

const Map<String, int> pilotExpectedRouteCounts = <String, int>{
  pilotRouteReferral: 4,
  pilotRouteVenueInbound: 3,
  pilotRouteCommunity: 3,
};

/// Synthetic clock marks. The packet carries no wall-clock time.
const int pilotApprovalMs = 1000;
const int pilotEvidenceMs = 0;

const String pilotAuthorityState = 'assembly_only';
const String pilotProofState = 'synthetic';
const String unavailable = 'UNAVAILABLE';

// ---------------------------------------------------------------------------
// Synthetic prospect fixture
// ---------------------------------------------------------------------------

class PilotProspectFixture {
  final String id;
  final String identityFingerprint;
  final String route;
  final List<String> systems;
  final List<String> languages;

  const PilotProspectFixture({
    required this.id,
    required this.identityFingerprint,
    required this.route,
    this.systems = const <String>[pilotSystem],
    this.languages = const <String>[pilotLanguage],
  });

  TablePlayer toPlayer() => TablePlayer(
        id: id,
        identityFingerprint: identityFingerprint,
        availableSlotIds: const <String>[pilotSlotId],
        systems: systems,
        languages: languages,
        experienceComfort: const <TableExperience>[TableExperience.mixed],
        commitments: const <TableCommitment>[TableCommitment.oneShot],
        accessibilityNeeds: const <String>[pilotAccessibilityNeed],
        contentBoundaries: const <String>[pilotContentBoundary],
        accessibilityNeedsDisclosed: true,
        contentBoundariesDisclosed: true,
        acquisitionSource: route,
        netNewToVenue: true,
      );
}

const List<PilotProspectFixture> pilotProspects = <PilotProspectFixture>[
  PilotProspectFixture(
    id: 'p001',
    identityFingerprint: 'fixture-person-001',
    route: pilotRouteReferral,
  ),
  PilotProspectFixture(
    id: 'p002',
    identityFingerprint: 'fixture-person-002',
    route: pilotRouteVenueInbound,
  ),
  PilotProspectFixture(
    id: 'p003',
    identityFingerprint: 'fixture-person-003',
    route: pilotRouteCommunity,
  ),
  PilotProspectFixture(
    id: 'p004',
    identityFingerprint: 'fixture-person-004',
    route: pilotRouteReferral,
  ),
  PilotProspectFixture(
    id: 'p005',
    identityFingerprint: 'fixture-person-005',
    route: pilotRouteVenueInbound,
  ),
  PilotProspectFixture(
    id: 'p006',
    identityFingerprint: 'fixture-person-006',
    route: pilotRouteCommunity,
  ),
  PilotProspectFixture(
    id: 'p007',
    identityFingerprint: 'fixture-person-007',
    route: pilotRouteReferral,
    languages: <String>['ar'],
  ),
  // Deliberate duplicate identity of p002; retained as suppressed evidence.
  PilotProspectFixture(
    id: 'p008',
    identityFingerprint: 'fixture-person-002',
    route: pilotRouteReferral,
  ),
  PilotProspectFixture(
    id: 'p009',
    identityFingerprint: 'fixture-person-009',
    route: pilotRouteVenueInbound,
    systems: <String>['system-b'],
  ),
  PilotProspectFixture(
    id: 'p010',
    identityFingerprint: 'fixture-person-010',
    route: pilotRouteCommunity,
  ),
];

const TableDm pilotDm = TableDm(
  id: pilotDmId,
  identityFingerprint: 'fixture-dm-pilot-001',
  approved: true,
  availableSlotIds: <String>[pilotSlotId],
  systems: <String>[pilotSystem],
  languages: <String>[pilotLanguage],
  supportedExperience: <TableExperience>[TableExperience.mixed],
  commitments: <TableCommitment>[TableCommitment.oneShot],
  supportedAccessibility: <String>[pilotAccessibilityNeed],
  acceptedContentBoundaries: <String>[pilotContentBoundary],
  capacity: 4,
);

const TableSlot pilotSlot = TableSlot(
  id: pilotSlotId,
  identityFingerprint: 'fixture-slot-pilot-friday-1900',
  system: pilotSystem,
  language: pilotLanguage,
  experience: TableExperience.mixed,
  commitment: TableCommitment.oneShot,
  dmId: pilotDmId,
  targetPlayers: 4,
);

/// Loads the synthetic fixture into the accepted operator. No proposal exists
/// yet, so no invitation draft can be produced from this state.
FindMyTableOperator buildSyntheticPilotOperator() =>
    FindMyTableOperator.createAuthorized(
      authorizationId: findMyTableAssemblyAuthorizationId,
      players: pilotProspects.map((value) => value.toPlayer()).toList(),
      dms: const <TableDm>[pilotDm],
      slots: const <TableSlot>[pilotSlot],
    );

// ---------------------------------------------------------------------------
// Packet projections of operator records
// ---------------------------------------------------------------------------

/// One row of the `Review Queue` sheet, derived only from operator output.
class PilotReviewRow {
  final String prospectId;
  final String route;
  final String netNewProof;
  final String slotFit;
  final String systemFit;
  final String languageFit;
  final String experienceFit;
  final String commitmentFit;
  final String optionalDisclosed;
  final String eligibility;
  final String proposalRole;
  final String retainedReason;
  final String operatorDecision;
  final String proofState;

  const PilotReviewRow({
    required this.prospectId,
    required this.route,
    required this.netNewProof,
    required this.slotFit,
    required this.systemFit,
    required this.languageFit,
    required this.experienceFit,
    required this.commitmentFit,
    required this.optionalDisclosed,
    required this.eligibility,
    required this.proposalRole,
    required this.retainedReason,
    required this.operatorDecision,
    required this.proofState,
  });

  List<Object> get values => <Object>[
        prospectId,
        route,
        netNewProof,
        slotFit,
        systemFit,
        languageFit,
        experienceFit,
        commitmentFit,
        optionalDisclosed,
        eligibility,
        proposalRole,
        retainedReason,
        operatorDecision,
        proofState,
      ];
}

/// One row of the `Evidence Ledger` sheet.
class PilotLedgerEvent {
  final int sequence;
  final String subjectId;
  final String eventType;
  final String fromState;
  final String toState;
  final String reason;
  final int syntheticTimeMs;
  final String authorityState;

  const PilotLedgerEvent({
    required this.sequence,
    required this.subjectId,
    required this.eventType,
    required this.fromState,
    required this.toState,
    required this.reason,
    required this.syntheticTimeMs,
    this.authorityState = pilotAuthorityState,
  });

  List<Object> get values => <Object>[
        sequence,
        subjectId,
        eventType,
        fromState,
        toState,
        reason,
        syntheticTimeMs,
        authorityState,
      ];
}

class _LifecycleStep {
  final String subjectId;
  final String eventType;
  final String fromState;
  final String toState;
  final String reason;
  final int recordedAtMs;
  final OperatorMutation Function(FindMyTableOperator) apply;

  const _LifecycleStep({
    required this.subjectId,
    required this.eventType,
    required this.fromState,
    required this.toState,
    required this.reason,
    required this.recordedAtMs,
    required this.apply,
  });
}

/// The complete synthetic dry run: matching, approval, lifecycle, evidence.
class SyntheticPilotAssembly {
  final FindMyTableOperator operator;
  final TableProposal proposal;
  final List<String> initialSelectedPlayerIds;
  final List<String> initialWaitlistPlayerIds;
  final List<PilotReviewRow> reviewRows;
  final List<PilotLedgerEvent> ledger;
  final Map<String, int> routeCounts;
  final DmTableBrief dmBrief;
  final String cancelledPlayerId;
  final String replacementPlayerId;
  final String duplicateRecordId;
  final String duplicateOfId;

  const SyntheticPilotAssembly({
    required this.operator,
    required this.proposal,
    required this.initialSelectedPlayerIds,
    required this.initialWaitlistPlayerIds,
    required this.reviewRows,
    required this.ledger,
    required this.routeCounts,
    required this.dmBrief,
    required this.cancelledPlayerId,
    required this.replacementPlayerId,
    required this.duplicateRecordId,
    required this.duplicateOfId,
  });

  List<String> get finalSelectedPlayerIds => proposal.selectedPlayerIds;

  List<String> get finalWaitlistPlayerIds => proposal.waitlistPlayerIds;
}

const String _reasonApproval = 'synthetic operator approved exact table';
const String _reasonInvitation = 'synthetic invitation after approval';
const String _reasonAcceptance = 'synthetic acceptance retained';
const String _reasonConfirmation = 'synthetic confirmation retained';
const String _reasonCancellation = 'synthetic cancellation retained';
const String _reasonDecline = 'synthetic decline retained';
const String _reasonAllConstraints = 'all hard constraints satisfied';
const String _reasonReplacementRetained = 'ordered replacement retained';
const String _reasonDeclineRetained = 'decline retained';
const String _reasonSurplus = 'ordered surplus';
const String _reasonDuplicatePrefix =
    'duplicate identity fingerprint suppressed';

String _replacementReason(String cancelledPlayerId) =>
    'ordered compatible replacement for $cancelledPlayerId';

/// Runs the frozen synthetic dry run and fails closed if the accepted operator
/// refuses any step. Nothing here can invent an outcome the operator rejected.
SyntheticPilotAssembly runSyntheticPilotAssembly() {
  var operator = buildSyntheticPilotOperator();

  final duplicates = operator.duplicates
      .where((value) => value.kind == 'player')
      .toList(growable: false);
  if (duplicates.length != 1) {
    throw StateError('expected exactly one retained duplicate prospect');
  }
  final duplicate = duplicates.single;

  final proposed = operator.proposeForSlot(pilotSlotId);
  if (!proposed.accepted) {
    throw StateError('synthetic proposal refused: ${proposed.reason}');
  }
  operator = proposed.operator;
  final created = operator.proposals.single;
  final initialSelected = List<String>.unmodifiable(created.selectedPlayerIds);
  final initialWaitlist = List<String>.unmodifiable(created.waitlistPlayerIds);
  if (created.id != pilotProposalId) {
    throw StateError('unexpected proposal id ${created.id}');
  }

  const cancelledPlayerId = 'p003';
  const declinedPlayerId = 'p004';
  const replacementPlayerId = 'p005';

  final steps = <_LifecycleStep>[
    _LifecycleStep(
      subjectId: pilotProposalId,
      eventType: 'operator_decision',
      fromState: 'proposed',
      toState: 'approved',
      reason: _reasonApproval,
      recordedAtMs: pilotApprovalMs,
      apply: (value) => value.decideProposal(
        pilotProposalId,
        ProposalDecision.approved,
        reason: _reasonApproval,
        recordedAtMs: pilotApprovalMs,
      ),
    ),
    _LifecycleStep(
      subjectId: cancelledPlayerId,
      eventType: 'participant_state',
      fromState: 'selected',
      toState: 'invited',
      reason: _reasonInvitation,
      recordedAtMs: 1100,
      apply: (value) => value.recordParticipantState(
        pilotProposalId,
        cancelledPlayerId,
        ParticipantState.invited,
        reason: _reasonInvitation,
        recordedAtMs: 1100,
      ),
    ),
    _LifecycleStep(
      subjectId: cancelledPlayerId,
      eventType: 'participant_state',
      fromState: 'invited',
      toState: 'accepted',
      reason: _reasonAcceptance,
      recordedAtMs: 1200,
      apply: (value) => value.recordParticipantState(
        pilotProposalId,
        cancelledPlayerId,
        ParticipantState.accepted,
        reason: _reasonAcceptance,
        recordedAtMs: 1200,
      ),
    ),
    _LifecycleStep(
      subjectId: cancelledPlayerId,
      eventType: 'participant_state',
      fromState: 'accepted',
      toState: 'confirmed',
      reason: _reasonConfirmation,
      recordedAtMs: 1300,
      apply: (value) => value.recordParticipantState(
        pilotProposalId,
        cancelledPlayerId,
        ParticipantState.confirmed,
        reason: _reasonConfirmation,
        recordedAtMs: 1300,
      ),
    ),
    _LifecycleStep(
      subjectId: cancelledPlayerId,
      eventType: 'participant_state',
      fromState: 'confirmed',
      toState: 'cancelled',
      reason: _reasonCancellation,
      recordedAtMs: 1400,
      apply: (value) => value.recordParticipantState(
        pilotProposalId,
        cancelledPlayerId,
        ParticipantState.cancelled,
        reason: _reasonCancellation,
        recordedAtMs: 1400,
      ),
    ),
    _LifecycleStep(
      subjectId: replacementPlayerId,
      eventType: 'replacement',
      fromState: 'waitlisted',
      toState: 'selected',
      reason: _replacementReason(cancelledPlayerId),
      recordedAtMs: 1500,
      apply: (value) => value.replaceCancelledPlayer(
        pilotProposalId,
        cancelledPlayerId,
        recordedAtMs: 1500,
      ),
    ),
    _LifecycleStep(
      subjectId: declinedPlayerId,
      eventType: 'participant_state',
      fromState: 'selected',
      toState: 'invited',
      reason: _reasonInvitation,
      recordedAtMs: 1600,
      apply: (value) => value.recordParticipantState(
        pilotProposalId,
        declinedPlayerId,
        ParticipantState.invited,
        reason: _reasonInvitation,
        recordedAtMs: 1600,
      ),
    ),
    _LifecycleStep(
      subjectId: declinedPlayerId,
      eventType: 'participant_state',
      fromState: 'invited',
      toState: 'declined',
      reason: _reasonDecline,
      recordedAtMs: 1700,
      apply: (value) => value.recordParticipantState(
        pilotProposalId,
        declinedPlayerId,
        ParticipantState.declined,
        reason: _reasonDecline,
        recordedAtMs: 1700,
      ),
    ),
  ];

  final ledger = <PilotLedgerEvent>[
    PilotLedgerEvent(
      sequence: 1,
      subjectId: duplicate.recordId,
      eventType: 'duplicate',
      fromState: 'discovered',
      toState: 'suppressed',
      reason:
          '$_reasonDuplicatePrefix; duplicate of ${duplicate.duplicateOfId}',
      syntheticTimeMs: pilotEvidenceMs,
    ),
  ];
  for (final evidence in operator.unmatched) {
    ledger.add(PilotLedgerEvent(
      sequence: ledger.length + 1,
      subjectId: evidence.subjectId,
      eventType: 'unmatched',
      fromState: 'evaluated',
      toState: 'rejected',
      reason: evidence.reasons.join('; '),
      syntheticTimeMs: pilotEvidenceMs,
    ));
  }

  for (final step in steps) {
    final mutation = step.apply(operator);
    if (!mutation.accepted) {
      throw StateError(
          'operator refused ${step.eventType}: ${mutation.reason}');
    }
    operator = mutation.operator;
    final recorded = operator.proposals.single.history.last;
    if (recorded.subjectId != step.subjectId ||
        recorded.recordedAtMs != step.recordedAtMs) {
      throw StateError('ledger step is not bound to an operator record');
    }
    ledger.add(PilotLedgerEvent(
      sequence: ledger.length + 1,
      subjectId: step.subjectId,
      eventType: step.eventType,
      fromState: step.fromState,
      toState: step.toState,
      reason: step.reason,
      syntheticTimeMs: step.recordedAtMs,
    ));
  }

  final proposal = operator.proposals.single;
  final rows = _buildReviewRows(
    operator: operator,
    proposal: proposal,
    initialSelected: initialSelected,
    duplicate: duplicate,
    cancelledPlayerId: cancelledPlayerId,
  );

  final routeCounts = <String, int>{
    for (final route in pilotRouteOrder) route: 0
  };
  for (final prospect in pilotProspects) {
    routeCounts[prospect.route] = (routeCounts[prospect.route] ?? 0) + 1;
  }
  for (final route in pilotRouteOrder) {
    if (routeCounts[route] != pilotExpectedRouteCounts[route]) {
      throw StateError('route allocation drifted for $route');
    }
  }

  return SyntheticPilotAssembly(
    operator: operator,
    proposal: proposal,
    initialSelectedPlayerIds: initialSelected,
    initialWaitlistPlayerIds: initialWaitlist,
    reviewRows: rows,
    ledger: List<PilotLedgerEvent>.unmodifiable(ledger),
    routeCounts: Map<String, int>.unmodifiable(routeCounts),
    dmBrief: operator.dmBrief(pilotProposalId),
    cancelledPlayerId: cancelledPlayerId,
    replacementPlayerId: replacementPlayerId,
    duplicateRecordId: duplicate.recordId,
    duplicateOfId: duplicate.duplicateOfId,
  );
}

/// Maps one operator ineligibility reason onto the workbook's fit column.
const Map<String, String> _fitReasonByColumn = <String, String>{
  'slot': 'availability conflict',
  'system': 'system mismatch',
  'language': 'language mismatch',
  'experience': 'experience comfort mismatch',
  'commitment': 'commitment mismatch',
};

List<PilotReviewRow> _buildReviewRows({
  required FindMyTableOperator operator,
  required TableProposal proposal,
  required List<String> initialSelected,
  required DuplicateEvidence duplicate,
  required String cancelledPlayerId,
}) {
  final unmatchedReasons = <String, List<String>>{
    for (final value in operator.unmatched) value.subjectId: value.reasons,
  };
  final rows = <PilotReviewRow>[];
  for (final prospect in pilotProspects) {
    final isDuplicate = prospect.id == duplicate.recordId;
    final reasons = unmatchedReasons[prospect.id];
    final isUnmatched = reasons != null;

    String fit(String column) {
      if (isDuplicate) return 'not_evaluated';
      final reason = _fitReasonByColumn[column]!;
      return (reasons?.contains(reason) ?? false) ? 'fail' : 'pass';
    }

    final String role;
    final String retainedReason;
    if (isDuplicate) {
      role = 'duplicate';
      retainedReason =
          '$_reasonDuplicatePrefix; duplicate of ${duplicate.duplicateOfId}';
    } else if (isUnmatched) {
      role = 'unmatched';
      retainedReason = reasons.join('; ');
    } else {
      final state = proposal.participantStates[prospect.id];
      final inFinalSelected = proposal.selectedPlayerIds.contains(prospect.id);
      if (state == ParticipantState.cancelled) {
        role = 'selected_then_cancelled';
        retainedReason = _reasonReplacementRetained;
      } else if (state == ParticipantState.declined) {
        role = 'selected_then_declined';
        retainedReason = _reasonDeclineRetained;
      } else if (inFinalSelected && !initialSelected.contains(prospect.id)) {
        role = 'waitlist_then_replacement';
        retainedReason = _replacementReason(cancelledPlayerId);
      } else if (inFinalSelected) {
        role = 'selected';
        retainedReason = _reasonAllConstraints;
      } else {
        role = 'waitlist';
        retainedReason = _reasonSurplus;
      }
    }

    rows.add(PilotReviewRow(
      prospectId: prospect.id,
      route: prospect.route,
      netNewProof: 'synthetic_net_new',
      slotFit: fit('slot'),
      systemFit: fit('system'),
      languageFit: fit('language'),
      experienceFit: fit('experience'),
      commitmentFit: fit('commitment'),
      optionalDisclosed: isDuplicate ? 'not_evaluated' : 'yes',
      eligibility: isDuplicate
          ? 'duplicate'
          : isUnmatched
              ? 'ineligible'
              : 'eligible',
      proposalRole: role,
      retainedReason: retainedReason,
      operatorDecision:
          isDuplicate || isUnmatched ? 'not proposed' : 'approved proposal',
      proofState: pilotProofState,
    ));
  }
  return List<PilotReviewRow>.unmodifiable(rows);
}

// ---------------------------------------------------------------------------
// Approval-gated recipient draft
// ---------------------------------------------------------------------------

/// Builds one recipient-specific invitation draft.
///
/// Refuses unless the exact proposal carries a recorded operator approval and
/// the recipient is a selected participant. The draft is never sent, carries no
/// contact channel, and leaves every unknown live field `UNAVAILABLE`.
String buildRecipientInvitationDraft(
  FindMyTableOperator operator,
  String proposalId,
  String playerId,
) {
  TableProposal? found;
  for (final proposal in operator.proposals) {
    if (proposal.id == proposalId) found = proposal;
  }
  if (found == null) {
    throw StateError('proposal not found; no recipient draft may exist');
  }
  if (found.decision != ProposalDecision.approved) {
    throw StateError(
      'operator approval required before a recipient-specific invitation draft',
    );
  }
  if (!found.selectedPlayerIds.contains(playerId)) {
    throw StateError('recipient is not a selected participant');
  }
  final slot = pilotSlot;
  return 'Draft for operator ID $playerId (UNSENT; no channel authorized)\n'
      '\n'
      'Hi $playerId — we are privately testing one hosted ${slot.system} table\n'
      'for adults on $unavailable at $unavailable. We checked the schedule and\n'
      'fit preferences you chose, and we would like to offer you one of four\n'
      'places. The venue\'s normal BHD12 minimum food/drink bill applies; there\n'
      'is no separate matching fee for this pilot. Please reply [ACCEPT] or\n'
      '[DECLINE] by $unavailable. This is an invitation, not a guaranteed\n'
      'booking, until confirmed.\n';
}

// ---------------------------------------------------------------------------
// Attribution cell semantics
// ---------------------------------------------------------------------------

/// Inputs for the `Attribution` sheet, where `null` models a blank cell.
class AttributionCellInput {
  final List<double?> playerBillsBhd;
  final List<bool?> netNewSeats;
  final double? contributionMargin;
  final double? incrementalOverheadBhd;
  final double? dmCostBhd;
  final double? discountsBhd;
  final double? refundsBhd;
  final double? feesBhd;
  final double? supportLaborBhd;

  const AttributionCellInput({
    required this.playerBillsBhd,
    required this.netNewSeats,
    required this.contributionMargin,
    required this.incrementalOverheadBhd,
    required this.dmCostBhd,
    required this.discountsBhd,
    required this.refundsBhd,
    required this.feesBhd,
    required this.supportLaborBhd,
  });

  List<double?> get adjustmentInputs => <double?>[
        contributionMargin,
        incrementalOverheadBhd,
        dmCostBhd,
        discountsBhd,
        refundsBhd,
        feesBhd,
        supportLaborBhd,
      ];
}

const AttributionCellInput centralAttributionCase = AttributionCellInput(
  playerBillsBhd: <double?>[12.0, 12.0, 12.0, 12.0],
  netNewSeats: <bool?>[true, true, true, true],
  contributionMargin: 0.4,
  incrementalOverheadBhd: 5.0,
  dmCostBhd: 10.0,
  discountsBhd: 0.0,
  refundsBhd: 0.0,
  feesBhd: 0.0,
  supportLaborBhd: 0.0,
);

const AttributionCellInput transferredSeatAttributionCase =
    AttributionCellInput(
  playerBillsBhd: <double?>[12.0, 12.0, 12.0, 12.0],
  netNewSeats: <bool?>[true, true, true, false],
  contributionMargin: 0.4,
  incrementalOverheadBhd: 5.0,
  dmCostBhd: 10.0,
  discountsBhd: 0.0,
  refundsBhd: 0.0,
  feesBhd: 0.0,
  supportLaborBhd: 0.0,
);

/// Cell references of the central case, in the order used by the workbook.
const List<String> centralBillCells = <String>['B3', 'B4', 'B5', 'B6'];
const List<String> centralNetNewCells = <String>['C3', 'C4', 'C5', 'C6'];
const List<String> centralInputCells = <String>[
  'B8',
  'B9',
  'B10',
  'B11',
  'B12',
  'B13',
  'B14',
];

/// Returns the central case with one required input cell left blank.
AttributionCellInput blankCentralAttributionCase(String cellReference) {
  const base = centralAttributionCase;
  final bills = List<double?>.from(base.playerBillsBhd);
  final seats = List<bool?>.from(base.netNewSeats);
  final billIndex = centralBillCells.indexOf(cellReference);
  if (billIndex >= 0) bills[billIndex] = null;
  final seatIndex = centralNetNewCells.indexOf(cellReference);
  if (seatIndex >= 0) seats[seatIndex] = null;
  final inputIndex = centralInputCells.indexOf(cellReference);
  if (billIndex < 0 && seatIndex < 0 && inputIndex < 0) {
    throw ArgumentError.value(cellReference, 'cellReference', 'not an input');
  }
  return AttributionCellInput(
    playerBillsBhd: bills,
    netNewSeats: seats,
    contributionMargin: inputIndex == 0 ? null : base.contributionMargin,
    incrementalOverheadBhd:
        inputIndex == 1 ? null : base.incrementalOverheadBhd,
    dmCostBhd: inputIndex == 2 ? null : base.dmCostBhd,
    discountsBhd: inputIndex == 3 ? null : base.discountsBhd,
    refundsBhd: inputIndex == 4 ? null : base.refundsBhd,
    feesBhd: inputIndex == 5 ? null : base.feesBhd,
    supportLaborBhd: inputIndex == 6 ? null : base.supportLaborBhd,
  );
}

/// Evaluates the guarded workbook formulas.
///
/// The gross, net-new share, overhead, and DM-cost arithmetic is delegated to
/// `FindMyTableOperator.calculateAttribution`; only the blank-cell guards and
/// the discount/refund/fee/support adjustments are modeled here, exactly as the
/// spreadsheet formulas express them. Any missing required input yields
/// `UNAVAILABLE` with no numeric derived result.
Map<String, Object> evaluateAttributionCells(AttributionCellInput input) {
  final billsComplete = !input.playerBillsBhd.contains(null);
  final seatsComplete = !input.netNewSeats.contains(null);
  final inputsComplete = !input.adjustmentInputs.contains(null);

  final Object gross = billsComplete
      ? _roundBhd(input.playerBillsBhd.fold<double>(0, (sum, v) => sum + v!))
      : unavailable;
  final Object share = seatsComplete
      ? input.netNewSeats.where((value) => value == true).length /
          input.netNewSeats.length
      : unavailable;

  Object contribution = unavailable;
  if (billsComplete && seatsComplete && inputsComplete) {
    final modeled = FindMyTableOperator.calculateAttribution(AttributionInput(
      playerBillsBhd: input.playerBillsBhd.cast<double>(),
      contributionMargin: input.contributionMargin,
      incrementalOverheadBhd: input.incrementalOverheadBhd,
      dmCostBhd: input.dmCostBhd,
      netNewSeats: input.netNewSeats.cast<bool>(),
    ));
    if (modeled.available) {
      contribution = _roundBhd(
        modeled.attributableContributionBhd! -
            input.discountsBhd! -
            input.refundsBhd! -
            input.feesBhd! -
            input.supportLaborBhd!,
      );
    }
  }
  final Object nonNegative =
      contribution is num ? contribution >= 0 : unavailable;

  return <String, Object>{
    'gross': gross,
    'netNewShare': share,
    'attributableContribution': contribution,
    'nonNegative': nonNegative,
  };
}

double _roundBhd(double value) => (value * 100).roundToDouble() / 100;

// ---------------------------------------------------------------------------
// Minimal deterministic OOXML writer
// ---------------------------------------------------------------------------

const String _xmlDeclaration =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n';
const String _spreadsheetNs =
    'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
const String _officeRelNs =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
const String _packageRelNs =
    'http://schemas.openxmlformats.org/package/2006/relationships';
const String _contentTypeNs =
    'http://schemas.openxmlformats.org/package/2006/content-types';

/// A fixed UTC instant so every ZIP entry carries identical, timezone
/// independent metadata. Byte determinism depends on this being constant.
final DateTime fixedPacketZipTimestamp = DateTime.utc(2026, 8, 9);

class XlsxCell {
  final String reference;
  final Object? value;
  final String? formula;
  final int style;

  const XlsxCell(this.reference, this.value, {this.style = 0}) : formula = null;

  /// [formulaWithEquals] is stored as written in the workbook oracle; the
  /// leading `=` is stripped when the cell is serialized.
  XlsxCell.formula(
    this.reference,
    String formulaWithEquals,
    this.value, {
    this.style = 0,
  }) : formula = formulaWithEquals.startsWith('=')
            ? formulaWithEquals.substring(1)
            : formulaWithEquals;
}

const int _xlsxStyleHeader = 1;
const int _xlsxStyleTitle = 2;
const int _xlsxStyleDecimal = 3;
const int _xlsxStylePercent = 4;
const int _xlsxStyleBody = 5;

class XlsxSheet {
  final String name;
  final List<XlsxCell> cells;
  final List<double> columnWidths;

  const XlsxSheet(
    this.name,
    this.cells, {
    this.columnWidths = const <double>[],
  });
}

Uint8List buildWorkbookBytes(List<XlsxSheet> sheets) {
  final parts = <String, String>{
    '[Content_Types].xml': _contentTypesXml(sheets.length),
    '_rels/.rels': _rootRelsXml(),
    'xl/workbook.xml': _workbookXml(sheets),
    'xl/_rels/workbook.xml.rels': _workbookRelsXml(sheets.length),
    'xl/styles.xml': _stylesXml(),
    for (var index = 0; index < sheets.length; index++)
      'xl/worksheets/sheet${index + 1}.xml': _sheetXml(sheets[index]),
  };

  final archive = Archive();
  for (final entry in parts.entries) {
    final bytes = utf8.encode(entry.value);
    final file = ArchiveFile(entry.key, bytes.length, bytes)
      ..mode = 420
      ..ownerId = 0
      ..groupId = 0;
    archive.addFile(file);
  }
  final encoded = ZipEncoder().encode(
    archive,
    level: Deflate.BEST_COMPRESSION,
    modified: fixedPacketZipTimestamp,
  );
  if (encoded == null) throw StateError('workbook encoding produced no bytes');
  return Uint8List.fromList(encoded);
}

String _contentTypesXml(int sheetCount) {
  final buffer = StringBuffer()
    ..write(_xmlDeclaration)
    ..write('<Types xmlns="$_contentTypeNs">')
    ..write('<Default Extension="rels" ContentType="application/'
        'vnd.openxmlformats-package.relationships+xml"/>')
    ..write('<Default Extension="xml" ContentType="application/xml"/>')
    ..write('<Override PartName="/xl/workbook.xml" ContentType="application/'
        'vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>');
  for (var index = 1; index <= sheetCount; index++) {
    buffer.write('<Override PartName="/xl/worksheets/sheet$index.xml" '
        'ContentType="application/vnd.openxmlformats-officedocument.'
        'spreadsheetml.worksheet+xml"/>');
  }
  buffer
    ..write('<Override PartName="/xl/styles.xml" ContentType="application/'
        'vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>')
    ..write('</Types>\n');
  return buffer.toString();
}

String _rootRelsXml() => '$_xmlDeclaration'
    '<Relationships xmlns="$_packageRelNs">'
    '<Relationship Id="rId1" Type="$_officeRelNs/officeDocument" '
    'Target="xl/workbook.xml"/>'
    '</Relationships>\n';

String _workbookRelsXml(int sheetCount) {
  final buffer = StringBuffer()
    ..write(_xmlDeclaration)
    ..write('<Relationships xmlns="$_packageRelNs">');
  for (var index = 1; index <= sheetCount; index++) {
    buffer.write('<Relationship Id="rId$index" Type="$_officeRelNs/worksheet" '
        'Target="worksheets/sheet$index.xml"/>');
  }
  buffer
    ..write('<Relationship Id="rId${sheetCount + 1}" '
        'Type="$_officeRelNs/styles" Target="styles.xml"/>')
    ..write('</Relationships>\n');
  return buffer.toString();
}

String _workbookXml(List<XlsxSheet> sheets) {
  final buffer = StringBuffer()
    ..write(_xmlDeclaration)
    ..write('<workbook xmlns="$_spreadsheetNs" xmlns:r="$_officeRelNs">')
    ..write('<workbookPr date1904="false"/>')
    ..write('<sheets>');
  for (var index = 0; index < sheets.length; index++) {
    buffer.write('<sheet name="${_escapeXmlAttribute(sheets[index].name)}" '
        'sheetId="${index + 1}" r:id="rId${index + 1}"/>');
  }
  buffer
    ..write('</sheets>')
    ..write('<calcPr calcId="0" calcMode="auto" fullCalcOnLoad="1"/>')
    ..write('</workbook>\n');
  return buffer.toString();
}

String _stylesXml() => '$_xmlDeclaration'
    '<styleSheet xmlns="$_spreadsheetNs">'
    '<numFmts count="1"><numFmt numFmtId="164" formatCode="0.00"/></numFmts>'
    '<fonts count="2"><font><sz val="11"/><name val="Calibri"/></font>'
    '<font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Calibri"/>'
    '</font></fonts>'
    '<fills count="4"><fill><patternFill patternType="none"/></fill>'
    '<fill><patternFill patternType="gray125"/></fill>'
    '<fill><patternFill patternType="solid"><fgColor rgb="FF1F4E78"/>'
    '<bgColor indexed="64"/></patternFill></fill>'
    '<fill><patternFill patternType="solid"><fgColor rgb="FF5B9BD5"/>'
    '<bgColor indexed="64"/></patternFill></fill></fills>'
    '<borders count="2"><border><left/><right/><top/><bottom/><diagonal/>'
    '</border><border><left style="thin"><color rgb="FFD9E2F3"/></left>'
    '<right style="thin"><color rgb="FFD9E2F3"/></right>'
    '<top style="thin"><color rgb="FFD9E2F3"/></top>'
    '<bottom style="thin"><color rgb="FFD9E2F3"/></bottom><diagonal/>'
    '</border></borders>'
    '<cellStyleXfs count="1">'
    '<xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
    '<cellXfs count="6">'
    '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
    '<xf numFmtId="0" fontId="1" fillId="2" borderId="1" xfId="0" '
    'applyFont="1" applyFill="1" applyBorder="1"/>'
    '<xf numFmtId="0" fontId="1" fillId="3" borderId="1" xfId="0" '
    'applyFont="1" applyFill="1" applyBorder="1"/>'
    '<xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0" '
    'applyNumberFormat="1"/>'
    '<xf numFmtId="10" fontId="0" fillId="0" borderId="0" xfId="0" '
    'applyNumberFormat="1"/>'
    '<xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" '
    'applyBorder="1"/></cellXfs>'
    '</styleSheet>\n';

String _sheetXml(XlsxSheet sheet) {
  final byRow = <int, List<XlsxCell>>{};
  for (final cell in sheet.cells) {
    byRow.putIfAbsent(_cellRow(cell.reference), () => <XlsxCell>[]).add(cell);
  }
  final rowNumbers = byRow.keys.toList()..sort();
  final buffer = StringBuffer()
    ..write(_xmlDeclaration)
    ..write('<worksheet xmlns="$_spreadsheetNs">')
    ..write('<sheetViews><sheetView workbookViewId="0" '
        'showGridLines="0"/></sheetViews>');
  if (sheet.columnWidths.isNotEmpty) {
    buffer.write('<cols>');
    for (var index = 0; index < sheet.columnWidths.length; index++) {
      buffer.write('<col min="${index + 1}" max="${index + 1}" '
          'width="${sheet.columnWidths[index]}" customWidth="1"/>');
    }
    buffer.write('</cols>');
  }
  buffer.write('<sheetData>');
  for (final rowNumber in rowNumbers) {
    final cells = byRow[rowNumber]!
      ..sort((left, right) =>
          _cellColumn(left.reference).compareTo(_cellColumn(right.reference)));
    buffer.write('<row r="$rowNumber">');
    for (final cell in cells) {
      buffer.write(_cellXml(cell));
    }
    buffer.write('</row>');
  }
  buffer.write('</sheetData></worksheet>\n');
  return buffer.toString();
}

String _cellXml(XlsxCell cell) {
  final reference = cell.reference;
  final value = cell.value;
  final formula = cell.formula;
  final style = cell.style == 0 ? '' : ' s="${cell.style}"';
  if (formula != null) {
    final rendered = '<f>${_escapeXmlText(formula)}</f>';
    if (value is String) {
      return '<c r="$reference"$style t="str">$rendered'
          '<v>${_escapeXmlText(value)}</v></c>';
    }
    if (value is bool) {
      return '<c r="$reference"$style t="b">$rendered<v>${value ? 1 : 0}</v></c>';
    }
    if (value is num) {
      return '<c r="$reference"$style>$rendered<v>${_numberText(value)}</v></c>';
    }
    return '<c r="$reference"$style>$rendered</c>';
  }
  if (value is String) {
    return '<c r="$reference"$style t="inlineStr"><is>'
        '<t>${_escapeXmlText(value)}</t></is></c>';
  }
  if (value is bool) {
    return '<c r="$reference"$style t="b"><v>${value ? 1 : 0}</v></c>';
  }
  if (value is num) {
    return '<c r="$reference"$style><v>${_numberText(value)}</v></c>';
  }
  return '<c r="$reference"$style/>';
}

int _cellColumn(String reference) {
  var index = 0;
  for (final code in reference.codeUnits) {
    if (code < 0x41 || code > 0x5a) break;
    index = index * 26 + (code - 0x40);
  }
  return index;
}

int _cellRow(String reference) =>
    int.parse(reference.replaceAll(RegExp('[A-Z]'), ''));

String _numberText(num value) {
  if (value is int) return value.toString();
  final doubleValue = value.toDouble();
  if (doubleValue == doubleValue.roundToDouble() && doubleValue.abs() < 1e15) {
    return doubleValue.toInt().toString();
  }
  return doubleValue.toString();
}

String _escapeXmlText(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

String _escapeXmlAttribute(String value) =>
    _escapeXmlText(value).replaceAll('"', '&quot;');

// ---------------------------------------------------------------------------
// Workbook content
// ---------------------------------------------------------------------------

const List<String> reviewQueueHeaders = <String>[
  'Prospect ID',
  'Route',
  'Net-new proof',
  'Slot fit',
  'System fit',
  'Language fit',
  'Experience fit',
  'Commitment fit',
  'Optional requirements disclosed',
  'Eligibility',
  'Proposal role',
  'Retained reason',
  'Operator decision',
  'Proof state',
];

const List<String> evidenceLedgerHeaders = <String>[
  'Sequence',
  'Subject ID',
  'Event type',
  'From',
  'To',
  'Reason',
  'Synthetic time ms',
  'Authority state',
];

const List<String> proofStateHeaders = <String>[
  'State',
  'Synthetic evidence',
  'Live evidence',
  'May satisfy money gate',
];

const List<String> _columnLetters = <String>[
  'A',
  'B',
  'C',
  'D',
  'E',
  'F',
  'G',
  'H',
  'I',
  'J',
  'K',
  'L',
  'M',
  'N',
];

Uint8List buildMatchReviewWorkbook(SyntheticPilotAssembly assembly) {
  final reviewCells = <XlsxCell>[];
  for (var index = 0; index < reviewQueueHeaders.length; index++) {
    reviewCells.add(XlsxCell(
      '${_columnLetters[index]}1',
      reviewQueueHeaders[index],
      style: _xlsxStyleHeader,
    ));
  }
  for (var row = 0; row < assembly.reviewRows.length; row++) {
    final values = assembly.reviewRows[row].values;
    for (var column = 0; column < values.length; column++) {
      reviewCells.add(XlsxCell(
        '${_columnLetters[column]}${row + 2}',
        values[column],
        style: _xlsxStyleBody,
      ));
    }
  }
  reviewCells.addAll(<XlsxCell>[
    const XlsxCell('P1', 'Route', style: _xlsxStyleHeader),
    const XlsxCell('Q1', 'Expected count', style: _xlsxStyleHeader),
    const XlsxCell('R1', 'Counted from column B', style: _xlsxStyleHeader),
  ]);
  for (var index = 0; index < pilotRouteOrder.length; index++) {
    final route = pilotRouteOrder[index];
    final row = index + 2;
    reviewCells
      ..add(XlsxCell('P$row', route, style: _xlsxStyleBody))
      ..add(XlsxCell('Q$row', assembly.routeCounts[route]!,
          style: _xlsxStyleBody))
      ..add(XlsxCell.formula(
        'R$row',
        '=COUNTIF(B2:B11,P$row)',
        assembly.routeCounts[route]!,
        style: _xlsxStyleBody,
      ));
  }

  final ledgerCells = <XlsxCell>[];
  for (var index = 0; index < evidenceLedgerHeaders.length; index++) {
    ledgerCells.add(XlsxCell(
      '${_columnLetters[index]}1',
      evidenceLedgerHeaders[index],
      style: _xlsxStyleHeader,
    ));
  }
  for (var row = 0; row < assembly.ledger.length; row++) {
    final values = assembly.ledger[row].values;
    for (var column = 0; column < values.length; column++) {
      ledgerCells.add(XlsxCell(
        '${_columnLetters[column]}${row + 2}',
        values[column],
        style: _xlsxStyleBody,
      ));
    }
  }

  return buildWorkbookBytes(<XlsxSheet>[
    XlsxSheet(
      'Review Queue',
      reviewCells,
      columnWidths: const <double>[
        12,
        29,
        19,
        12,
        13,
        14,
        16,
        16,
        27,
        14,
        25,
        44,
        21,
        14,
        3,
        29,
        15,
        22,
      ],
    ),
    XlsxSheet(
      'Evidence Ledger',
      ledgerCells,
      columnWidths: const <double>[10, 38, 20, 16, 16, 45, 19, 18],
    ),
  ]);
}

const List<String> _attributionInputLabels = <String>[
  'Contribution margin',
  'Incremental overhead BHD',
  'DM cost BHD',
  'Discounts BHD',
  'Refunds BHD',
  'Fees BHD',
  'Support labor BHD',
];

const List<String> _attributionResultLabels = <String>[
  'Gross BHD',
  'Net-new seat share',
  'Attributable contribution BHD',
  'Non-negative',
];

Uint8List buildRevenueAttributionWorkbook(SyntheticPilotAssembly assembly) {
  final central = evaluateAttributionCells(centralAttributionCase);
  final transferred = evaluateAttributionCells(transferredSeatAttributionCase);
  _assertOperatorEconomics(central, transferred);

  final billPlayerIds = assembly.initialSelectedPlayerIds;
  final cells = <XlsxCell>[
    const XlsxCell('A1', 'Central P0 synthetic fixture',
        style: _xlsxStyleTitle),
    const XlsxCell('E1', 'One transferred seat synthetic failure',
        style: _xlsxStyleTitle),
    const XlsxCell('A2', 'Player ID', style: _xlsxStyleHeader),
    const XlsxCell('B2', 'Bill BHD', style: _xlsxStyleHeader),
    const XlsxCell('C2', 'Net-new', style: _xlsxStyleHeader),
    const XlsxCell('D2', 'Source proof', style: _xlsxStyleHeader),
    const XlsxCell('E2', 'Player ID', style: _xlsxStyleHeader),
    const XlsxCell('F2', 'Bill BHD', style: _xlsxStyleHeader),
    const XlsxCell('G2', 'Net-new', style: _xlsxStyleHeader),
  ];

  for (var index = 0; index < billPlayerIds.length; index++) {
    final row = index + 3;
    cells
      ..add(XlsxCell('A$row', billPlayerIds[index], style: _xlsxStyleBody))
      ..add(XlsxCell('B$row', centralAttributionCase.playerBillsBhd[index]!,
          style: _xlsxStyleDecimal))
      ..add(XlsxCell('C$row', centralAttributionCase.netNewSeats[index]!,
          style: _xlsxStyleBody))
      ..add(XlsxCell('D$row', 'synthetic_net_new', style: _xlsxStyleBody))
      ..add(XlsxCell('E$row', billPlayerIds[index], style: _xlsxStyleBody))
      ..add(XlsxCell(
          'F$row', transferredSeatAttributionCase.playerBillsBhd[index]!,
          style: _xlsxStyleDecimal))
      ..add(XlsxCell(
          'G$row', transferredSeatAttributionCase.netNewSeats[index]!,
          style: _xlsxStyleBody));
  }

  final centralInputs = centralAttributionCase.adjustmentInputs;
  final transferredInputs = transferredSeatAttributionCase.adjustmentInputs;
  for (var index = 0; index < _attributionInputLabels.length; index++) {
    final row = index + 8;
    cells
      ..add(XlsxCell('A$row', _attributionInputLabels[index],
          style: _xlsxStyleBody))
      ..add(XlsxCell('B$row', centralInputs[index]!,
          style: index == 0 ? _xlsxStylePercent : _xlsxStyleDecimal))
      ..add(XlsxCell('F$row', transferredInputs[index]!,
          style: index == 0 ? _xlsxStylePercent : _xlsxStyleDecimal));
  }

  for (var index = 0; index < _attributionResultLabels.length; index++) {
    cells.add(XlsxCell('A${index + 16}', _attributionResultLabels[index],
        style: _xlsxStyleBody));
  }

  cells.addAll(<XlsxCell>[
    XlsxCell.formula(
      'B16',
      '=IF(COUNT(B3:B6)<>4,"UNAVAILABLE",SUM(B3:B6))',
      central['gross'],
      style: _xlsxStyleDecimal,
    ),
    XlsxCell.formula(
      'B17',
      '=IF(COUNTA(C3:C6)<>4,"UNAVAILABLE",SUMPRODUCT(--C3:C6)/ROWS(C3:C6))',
      central['netNewShare'],
      style: _xlsxStylePercent,
    ),
    XlsxCell.formula(
      'B18',
      '=IF(OR(COUNT(B3:B6)<>4,COUNTA(C3:C6)<>4,COUNT(B8:B14)<>7),'
          '"UNAVAILABLE",SUMPRODUCT(B3:B6,--C3:C6)*B8-B9-B10-B11-B12-B13-B14)',
      central['attributableContribution'],
      style: _xlsxStyleDecimal,
    ),
    XlsxCell.formula(
      'B19',
      '=IF(NOT(ISNUMBER(B18)),"UNAVAILABLE",B18>=0)',
      central['nonNegative'],
      style: _xlsxStyleBody,
    ),
    XlsxCell.formula(
      'F16',
      '=IF(COUNT(F3:F6)<>4,"UNAVAILABLE",SUM(F3:F6))',
      transferred['gross'],
      style: _xlsxStyleDecimal,
    ),
    XlsxCell.formula(
      'F17',
      '=IF(COUNTA(G3:G6)<>4,"UNAVAILABLE",SUMPRODUCT(--G3:G6)/ROWS(G3:G6))',
      transferred['netNewShare'],
      style: _xlsxStylePercent,
    ),
    XlsxCell.formula(
      'F18',
      '=IF(OR(COUNT(F3:F6)<>4,COUNTA(G3:G6)<>4,COUNT(F8:F14)<>7),'
          '"UNAVAILABLE",SUMPRODUCT(F3:F6,--G3:G6)*F8-F9-F10-F11-F12-F13-F14)',
      transferred['attributableContribution'],
      style: _xlsxStyleDecimal,
    ),
    XlsxCell.formula(
      'F19',
      '=IF(NOT(ISNUMBER(F18)),"UNAVAILABLE",F18>=0)',
      transferred['nonNegative'],
      style: _xlsxStyleBody,
    ),
  ]);

  final proofCells = <XlsxCell>[];
  for (var index = 0; index < proofStateHeaders.length; index++) {
    proofCells.add(XlsxCell(
      '${_columnLetters[index]}1',
      proofStateHeaders[index],
      style: _xlsxStyleHeader,
    ));
  }
  final proofRows = <List<Object>>[
    <Object>['proposed', 'SYNTHETIC', unavailable, false],
    <Object>['approved', 'SYNTHETIC', unavailable, false],
    <Object>['delivered', unavailable, unavailable, false],
    <Object>['billed', unavailable, unavailable, false],
    <Object>['settled', unavailable, unavailable, false],
    <Object>['bank-reconciled', unavailable, unavailable, false],
  ];
  _assertProofStates(assembly, proofRows);
  for (var row = 0; row < proofRows.length; row++) {
    for (var column = 0; column < proofRows[row].length; column++) {
      proofCells.add(XlsxCell(
        '${_columnLetters[column]}${row + 2}',
        proofRows[row][column],
        style: _xlsxStyleBody,
      ));
    }
  }

  return buildWorkbookBytes(<XlsxSheet>[
    XlsxSheet(
      'Attribution',
      cells,
      columnWidths: const <double>[34, 14, 12, 20, 39, 14, 12],
    ),
    XlsxSheet(
      'Proof States',
      proofCells,
      columnWidths: const <double>[21, 21, 21, 26],
    ),
  ]);
}

void _assertOperatorEconomics(
  Map<String, Object> central,
  Map<String, Object> transferred,
) {
  if (central['gross'] != 48.0 ||
      central['netNewShare'] != 1.0 ||
      central['attributableContribution'] != 4.2 ||
      central['nonNegative'] != true) {
    throw StateError('central economics fixture drifted: $central');
  }
  if (transferred['gross'] != 48.0 ||
      transferred['netNewShare'] != 0.75 ||
      transferred['attributableContribution'] != -0.6 ||
      transferred['nonNegative'] != false) {
    throw StateError('transferred-seat fixture drifted: $transferred');
  }
}

void _assertProofStates(
  SyntheticPilotAssembly assembly,
  List<List<Object>> rows,
) {
  if (assembly.proposal.revenueState != RevenueProofState.approved) {
    throw StateError('synthetic packet may only claim an approved proposal');
  }
  for (final row in rows) {
    final state = row.first as String;
    final live = row[2];
    if (live != unavailable) {
      throw StateError('live proof state $state must remain unavailable');
    }
    if (row[3] != false) {
      throw StateError('no synthetic state may satisfy the money gate');
    }
  }
}

// ---------------------------------------------------------------------------
// Markdown artifacts
// ---------------------------------------------------------------------------

String _joinIds(List<String> ids) => ids.isEmpty ? 'NONE' : ids.join(', ');

String buildPlayerIntake() => '''
# Private Hosted Table — Player Fit Intake

Status: SYNTHETIC TEMPLATE / DO NOT COLLECT REAL RESPONSES

This short intake helps an operator check schedule and table fit before making
an invitation. Completing it does not guarantee a match or a seat.

## Eligibility

- [ ] I am 18 or older.
- [ ] I understand this pilot covers a hosted venue table, not a home game.
- [ ] I understand an operator reviews every proposed match.

## Required fit fields

- Operator-assigned player ID: [SYNTHETIC ID]
- Available approved venue slot IDs: [SELECT ONE OR MORE]
- Game systems or categories I would play: [SELECT/LIST]
- Preferred table language(s): [SELECT/LIST]
- Experience comfort: [BEGINNER / MIXED / EXPERIENCED]
- Commitment: [ONE-SHOT / CAMPAIGN]

## Optional accessibility disclosure

Choose exactly one:

- [ ] I prefer not to disclose.
- [ ] I have no requirements to record for matching.
- [ ] I choose to disclose these operational requirements: [TEXT]

Do not enter a diagnosis or medical history. Record only what the venue or DM
must do for participation.

## Optional content-boundary disclosure

Choose exactly one:

- [ ] I prefer not to disclose.
- [ ] I have no boundaries to record for matching.
- [ ] I choose to disclose these table boundaries: [TEXT]

## Pilot understanding

- [ ] I understand the table has a BHD12 minimum food/drink bill per person.
- [ ] I understand there is no separate matching surcharge in pilot cell P0.
- [ ] I understand fit information is not shown to other players.
- [ ] I understand consent and retention terms are UNAVAILABLE until separately
      approved for live use.

Consent for real collection: UNAVAILABLE
Retention period: UNAVAILABLE
Data access owner: UNAVAILABLE

## Excluded fields

No name, phone number, email, home address, live location, payment identifier,
diagnosis, or open-ended biography belongs in this intake. Any future contact
list must be a separately authorized, access-controlled record outside the
matching operator.
''';

String buildDmIntakeAndApproval(SyntheticPilotAssembly assembly) => '''
# Private Hosted Table — DM Review

Status: SYNTHETIC TEMPLATE / NO OFFER MADE

## Capability

- Operator-assigned DM ID: ${pilotDm.id} (SYNTHETIC)
- Approved venue slot IDs: ${_joinIds(pilotDm.availableSlotIds)}
- Systems or formats supported: ${_joinIds(pilotDm.systems)}
- Table language(s): ${_joinIds(pilotDm.languages)}
- Player experience supported: MIXED
- Commitment supported: ONE-SHOT
- Maximum player capacity: ${pilotDm.capacity}
- Operational accessibility supported: ${_joinIds(pilotDm.supportedAccessibility)}
- Content boundaries accepted: ${_joinIds(pilotDm.acceptedContentBoundaries)}

## Evidence and safety review

- Relevant hosted-table evidence reviewed: SYNTHETIC
- Venue conduct expectations acknowledged: SYNTHETIC
- Stop/escalation procedure acknowledged: SYNTHETIC
- No private player details requested: YES

## Commercial term

- P0 fixture: BHD10 fixed for one approved, delivered session.
- Actual offer authority: LOCKED
- DM acceptance: UNAVAILABLE
- Requested alternative term: UNAVAILABLE
- Expected session duration: UNAVAILABLE
- Implied hourly rate: UNAVAILABLE

The fixture is not an offer or evidence that a qualified DM will accept.

## Operator decision

- Decision: APPROVE (SYNTHETIC FIXTURE STATE)
- Exact slot/system/format: ${pilotSlot.id} / ${pilotSlot.system} / one-shot
- Reason: synthetic DM capability matches the exact slot on availability,
  system, language, experience, commitment, accessibility support, and capacity
- Decision time: UNAVAILABLE
- Operator ID: $pilotSyntheticOperatorId

The approved synthetic table proposal recorded against this DM is
${assembly.proposal.id}. DM payment details, government identity, credentials,
private contact data, and tax information are outside this packet.
''';

String buildPrivateMessageTemplates(SyntheticPilotAssembly assembly) {
  final drafts = StringBuffer();
  for (final playerId in assembly.finalSelectedPlayerIds) {
    drafts
      ..writeln('### $playerId')
      ..writeln()
      ..writeln('```text')
      ..write(buildRecipientInvitationDraft(
        assembly.operator,
        assembly.proposal.id,
        playerId,
      ))
      ..writeln('```')
      ..writeln();
  }
  return '''
# Private Pilot Message Templates

Status: COPY-READY DRAFTS / ALL UNSENT

These templates require separate approval of the exact recipients, message,
slot, DM term, and outreach channel. Bracketed fields must never be inferred.

## Invitation — only after operator approval

Hi [FIRST NAME OR APPROVED HANDLE] — we are privately testing one hosted
[SYSTEM/FORMAT] table for adults on [DATE] at [TIME]. We checked the schedule
and fit preferences you chose, and we would like to offer you one of four
places. The venue's normal BHD12 minimum food/drink bill applies; there is no
separate matching fee for this pilot. Please reply [ACCEPT] or [DECLINE] by
[DEADLINE]. This is an invitation, not a guaranteed booking, until confirmed.

## Confirmation

Your place is confirmed for the hosted [SYSTEM/FORMAT] table on [DATE] at
[TIME]. Please arrive by [ARRIVAL TIME]. The normal BHD12 minimum food/drink
bill applies. If your availability changes, tell us by [CANCELLATION METHOD] so
we can offer the place to the next compatible person.

## Decline acknowledgement

Thanks for letting us know. We have recorded the decline for this table only.
We will not treat it as a rejection of future tables.

## Waitlist

This table is currently full. With your permission, we can keep you on the
ordered waitlist for this exact slot until [EXPIRY]. A place is not guaranteed.
Reply [REMOVE] at any time to leave this waitlist.

## Replacement offer

A place has opened for the hosted [SYSTEM/FORMAT] table on [DATE] at [TIME].
Because your recorded fit matches this exact table, we are offering it to you
next. Reply [ACCEPT] or [DECLINE] by [DEADLINE]. No response is not acceptance.

## Reminder

Reminder: your hosted [SYSTEM/FORMAT] table is [DATE] at [TIME]. Please arrive
by [ARRIVAL TIME]. The venue's normal BHD12 minimum food/drink bill applies.
Reply [CANCEL] if you can no longer attend.

## Venue cancellation

This table will not run on [DATE/TIME]. We are sorry for the change. No charge
or fee is created by this message. Any separately authorized payment or refund
process would be handled under its own terms; none is part of pilot cell P0.

## Recipient-specific synthetic drafts

These drafts exist only because proposal ${assembly.proposal.id} carries a
recorded synthetic operator approval. They address opaque operator IDs, name no
channel, and remain UNSENT. Outreach authority is LOCKED.

${drafts.toString().trimRight()}

Do not add urgency, scarcity, testimonials, partnership claims, venue marks,
game-publisher marks, guaranteed fit, guaranteed attendance, or revenue claims.
''';
}

String buildDmTableBrief(SyntheticPilotAssembly assembly) {
  final brief = assembly.dmBrief;
  final accessibility = brief.accessibilityRequirements.isEmpty
      ? 'NONE RECORDED'
      : brief.accessibilityRequirements.join(', ');
  final boundaries = brief.contentBoundaries.isEmpty
      ? 'NONE RECORDED'
      : brief.contentBoundaries.join(', ');
  return '''
# DM Table Brief

Status: SYNTHETIC / GENERATED ONLY AFTER OPERATOR APPROVAL

- Proposal ID: ${brief.proposalId}
- Approved slot: $pilotSlotId / UNAVAILABLE / UNAVAILABLE
- System or format: ${brief.system}
- Table language: ${brief.language}
- Experience level: ${brief.experience.name}
- Commitment: ONE-SHOT
- Player count: ${brief.playerCount}
- Aggregated operational accessibility requirements: $accessibility
- Aggregated content boundaries: $boundaries
- Venue arrival and table procedure: UNAVAILABLE
- Incident contact: UNAVAILABLE

This brief intentionally omits player identities, acquisition sources,
fingerprints, individual attribution, contact details, diagnoses, and payment
information. "None recorded" is different from "players disclosed none."
''';
}

String buildSessionRunSheet(SyntheticPilotAssembly assembly) {
  final ledgerRows = StringBuffer();
  for (final playerId in assembly.finalSelectedPlayerIds) {
    ledgerRows.writeln('| $playerId | UNAVAILABLE | UNAVAILABLE | UNAVAILABLE '
        '| UNAVAILABLE | UNAVAILABLE | UNAVAILABLE |');
  }
  return '''
# Hosted Table Session Run Sheet

Status: SYNTHETIC DRY RUN / LIVE RESULTS UNAVAILABLE

## Frozen table

- Experiment ID: $pilotExperimentId
- Proposal ID: ${assembly.proposal.id}
- Slot: $pilotSlotId / UNAVAILABLE / UNAVAILABLE
- System or format: ${pilotSlot.system}
- Approved DM ID: ${assembly.proposal.dmId}
- Player IDs: ${_joinIds(assembly.finalSelectedPlayerIds)}
- Ordered waitlist IDs: ${_joinIds(assembly.finalWaitlistPlayerIds)}

## Confirmation ledger

| Player ID | Invited | Accepted | Declined | Confirmed | Cancelled | Replacement reason |
|---|---|---|---|---|---|---|
${ledgerRows.toString().trimRight()}

Synthetic invitation, acceptance, decline, cancellation, and ordered
replacement evidence is retained in `03_match_review_workbook.xlsx`. This sheet
records live results only, so every cell above stays UNAVAILABLE.

## Delivery evidence

- DM arrived and delivered without Sadeq co-DMing: UNAVAILABLE
- Confirmed players: UNAVAILABLE
- Attended players: UNAVAILABLE
- No-shows: UNAVAILABLE
- Attendance rate: UNAVAILABLE
- Owner rescue minutes: UNAVAILABLE
- Matching minutes: UNAVAILABLE
- Confirmation/support minutes: UNAVAILABLE
- Material fit issue: UNAVAILABLE
- Safety/privacy incident: UNAVAILABLE
- Incident reference: UNAVAILABLE

## Operator close

- Delivered proof state: UNAVAILABLE
- Notes restricted to operational facts: UNAVAILABLE
- Stop condition triggered: UNAVAILABLE

Do not record narrative judgments about a person's personality, health, or
protected characteristics.
''';
}

String buildPrivacySafetyRunbook() => '''
# Privacy and Safety Runbook

Status: SYNTHETIC TEMPLATE / LIVE OWNERS UNAVAILABLE

## Minimize

- Use opaque operator IDs in the matcher and packet.
- Keep any separately authorized contact list outside the matching record.
- Collect only schedule, system, language, experience, commitment, and optional
  operational accessibility/content-boundary inputs.
- Never collect a diagnosis, home address, live location, payment credential,
  government ID, or open-ended personality profile in this pilot.

## Access and retention

- Data access owner: UNAVAILABLE
- Approved operators: UNAVAILABLE
- Retention period: UNAVAILABLE
- Deletion deadline: UNAVAILABLE
- Consent text/version: UNAVAILABLE

No real collection may begin while any item above is unavailable.

## Immediate stop conditions

Stop matching/contact/session preparation if any of these occurs:

- disclosure reaches an unauthorized person;
- consent, access owner, or retention rule is missing;
- a participant is a minor or age is unresolved;
- a material accessibility or content-boundary requirement cannot be met;
- harassment, threat, discrimination, coercion, or unsafe conduct is reported;
- the DM or exact table lacks operator approval;
- contact, venue, payment, receipt, or public authority is absent;
- someone is pressured to disclose optional information;
- a live result would otherwise be estimated or invented.

## Incident procedure

1. Stop the affected workflow; do not send another message.
2. Preserve the minimum evidence needed to explain what happened.
3. Restrict access and prevent further disclosure.
4. Notify the named incident owner through an approved private channel.
5. Record facts, affected record IDs, time, scope, action, and unresolved risk.
6. Delete or correct data only under the approved retention/deletion process.
7. Resume only after the incident owner records a safe, scoped decision.

Incident owner: UNAVAILABLE
Approved notification channel: UNAVAILABLE
Resume authority: UNAVAILABLE
''';

String buildPilotDecisionCard(SyntheticPilotAssembly assembly) {
  final counts = pilotRouteOrder
      .map((route) => assembly.routeCounts[route].toString())
      .join('/');
  return '''
# Private Pilot Decision Card

Status: SYNTHETIC DRY RUN

Decision: UNAVAILABLE

## Commercial proof

- Four of four seats verified net-new: UNAVAILABLE
- External DM accepted declared term: UNAVAILABLE
- External DM delivered without Sadeq rescue: UNAVAILABLE
- Attendance at least 80%: UNAVAILABLE
- Bills settled and tied to exact added table: UNAVAILABLE
- Incremental contribution after all measured costs: UNAVAILABLE
- Bank reconciliation: UNAVAILABLE

## Operational proof

- Acquisition route counts: SYNTHETIC $counts
- Duplicate/mismatch evidence retained: SYNTHETIC PASS
- Operator approval before invitation: SYNTHETIC PASS
- Matching minutes: UNAVAILABLE
- Confirmation/support minutes: UNAVAILABLE
- Owner rescue minutes: UNAVAILABLE
- Unresolved safety/privacy/material-fit issue: UNAVAILABLE

## Decision rule

PASS requires every declared live commercial, operational, safety, and
settlement criterion to pass. Missing evidence is UNVERIFIED. A proposal,
compliment, form completion, attendance intention, gross bill, or synthetic
result is not settled external profit.

## Exact next gate

One scoped action: sponsor inspection of this synthetic packet. Owner: Sadeq.
Authority: standing repository-local safe-work authority only. Evidence: the
manifest hashes, both workbooks, and the deterministic packet test. Stop point:
before any real data, contact, DM offer, venue booking, receipt access,
payment, or publication.

This decision does not authorize another Factory station.
''';
}

String buildLaunchChecklist() => '''
# Private Pilot Launch Checklist

Status: NOT LAUNCHABLE / ALL LIVE GATES LOCKED

## Synthetic packet acceptance

- [ ] All eleven artifacts exist and hashes verify
- [ ] Two generations are byte-identical
- [ ] Match and revenue workbooks pass formula/structure checks
- [ ] Every page and sheet is visually inspected
- [ ] Synthetic operator regressions pass

## Real-data gate

- [ ] Exact fields approved
- [ ] Consent text/version approved
- [ ] Access owner approved
- [ ] Retention and deletion period approved

## Contact gate

- [ ] Exact recipients approved
- [ ] Exact private channel approved
- [ ] Exact message/version approved
- [ ] Contact stop rule approved

## DM gate

- [ ] Exact DM approved
- [ ] Exact compensation term approved
- [ ] Maximum exposure approved
- [ ] Delivery and cancellation terms approved

## Venue and safety gate

- [ ] Exact slot/table approved
- [ ] Incident owner and channel approved
- [ ] Accessibility/boundary capability confirmed
- [ ] No existing-table seat will be reclassified as net-new

## Money and evidence gate

- [ ] Receipt access approved
- [ ] Margin definition and source frozen
- [ ] Incremental costs and support time capture frozen
- [ ] Any payment/deposit/refund authority approved separately

## Public gate

- [ ] Public copy or listing approved
- [ ] Public channel/account approved
- [ ] Marks and affiliation claims approved

## Final status

LAUNCH AUTHORIZED: NO
LIVE DATA AUTHORIZED: NO
CONTACT AUTHORIZED: NO
PAYMENT AUTHORIZED: NO
PUBLICATION AUTHORIZED: NO
LATER FACTORY STATION AUTHORIZED: NO
''';

String buildManifest(Map<String, String> payloadHashes) {
  final table = StringBuffer()
    ..writeln('| Artifact | SHA-256 |')
    ..writeln('|---|---|');
  for (final name in findMyTablePilotPayloadArtifacts) {
    final hash = payloadHashes[name];
    if (hash == null) throw StateError('missing payload hash for $name');
    table.writeln('| $name | $hash |');
  }
  return '''
# Find My Table — Private Pilot Packet v1

Proof state: SYNTHETIC / NOT LIVE
Packet: $findMyTablePacketId
Factory run: $findMyTableFactoryRunId
Scan session: $findMyTableScanSessionId
Candidate: $findMyTableCandidateId
Oracle: $findMyTablePilotOracleId
Workbook oracle: $findMyTablePilotWorkbookOracleId
Content version: $findMyTablePilotContentVersion
Generator version: $findMyTablePilotGeneratorVersion
Generated deterministically: YES

## Purpose

This packet rehearses one private four-player, externally DM-run table using
synthetic records. It is not permission to contact anyone or run the table.

## Authority locks

- [ ] Real player or DM data authorized
- [ ] Private outreach authorized
- [ ] Exact DM offer authorized
- [ ] Live venue session authorized
- [ ] Receipt or revenue access authorized
- [ ] Deposit, payment, or refund authorized
- [ ] Public post or listing authorized
- [ ] Later Factory station authorized

Every box must remain unchecked in the synthetic packet.

## File integrity

${table.toString().trimRight()}

The manifest's own SHA-256 is reported outside this self-referential table in
the completion report.

## Rollback

Delete or revert only `output/find_my_table_private_pilot_v1/`. No external
cleanup is required because no live action or real data is permitted.
''';
}

// ---------------------------------------------------------------------------
// Packet generation
// ---------------------------------------------------------------------------

class FindMyTablePilotPacket {
  final String outputDirectoryPath;
  final List<String> artifactNames;
  final Map<String, String> sha256ByArtifact;
  final String manifestSha256;

  const FindMyTablePilotPacket({
    required this.outputDirectoryPath,
    required this.artifactNames,
    required this.sha256ByArtifact,
    required this.manifestSha256,
  });

  Map<String, String> get payloadSha256ByArtifact => <String, String>{
        for (final name in findMyTablePilotPayloadArtifacts)
          name: sha256ByArtifact[name]!,
      };
}

/// Builds every artifact in memory. Deterministic: identical inputs always
/// produce identical bytes.
Map<String, Uint8List> buildFindMyTablePrivatePilotArtifacts() {
  final assembly = runSyntheticPilotAssembly();
  final payloads = <String, Uint8List>{
    '01_player_intake.md': _utf8Bytes(buildPlayerIntake()),
    '02_dm_intake_and_approval.md':
        _utf8Bytes(buildDmIntakeAndApproval(assembly)),
    '03_match_review_workbook.xlsx': buildMatchReviewWorkbook(assembly),
    '04_private_message_templates.md':
        _utf8Bytes(buildPrivateMessageTemplates(assembly)),
    '05_dm_table_brief.md': _utf8Bytes(buildDmTableBrief(assembly)),
    '06_session_run_sheet.md': _utf8Bytes(buildSessionRunSheet(assembly)),
    '07_revenue_attribution.xlsx': buildRevenueAttributionWorkbook(assembly),
    '08_privacy_safety_incident_runbook.md':
        _utf8Bytes(buildPrivacySafetyRunbook()),
    '09_pilot_decision_card.md': _utf8Bytes(buildPilotDecisionCard(assembly)),
    '10_launch_checklist.md': _utf8Bytes(buildLaunchChecklist()),
  };
  if (payloads.length != findMyTablePilotPayloadArtifacts.length) {
    throw StateError('payload artifact count drifted');
  }
  final hashes = <String, String>{
    for (final name in findMyTablePilotPayloadArtifacts)
      name: sha256.convert(payloads[name]!).toString(),
  };
  return <String, Uint8List>{
    findMyTablePilotManifestArtifact: _utf8Bytes(buildManifest(hashes)),
    ...payloads,
  };
}

/// Writes the eleven packet artifacts and returns their hashes.
FindMyTablePilotPacket generateFindMyTablePrivatePilotPacket({
  String outputDirectoryPath = defaultFindMyTablePilotOutputPath,
}) {
  final artifacts = buildFindMyTablePrivatePilotArtifacts();
  final directory = Directory(outputDirectoryPath);
  directory.createSync(recursive: true);
  final hashes = <String, String>{};
  for (final name in findMyTablePilotArtifacts) {
    final bytes = artifacts[name];
    if (bytes == null) throw StateError('artifact $name was not built');
    File('$outputDirectoryPath/$name').writeAsBytesSync(bytes, flush: true);
    hashes[name] = sha256.convert(bytes).toString();
  }
  return FindMyTablePilotPacket(
    outputDirectoryPath: outputDirectoryPath,
    artifactNames: List<String>.unmodifiable(findMyTablePilotArtifacts),
    sha256ByArtifact: Map<String, String>.unmodifiable(hashes),
    manifestSha256: hashes[findMyTablePilotManifestArtifact]!,
  );
}

Uint8List _utf8Bytes(String value) => Uint8List.fromList(utf8.encode(value));

void main(List<String> arguments) {
  if (arguments.length > 1) {
    stderr.writeln('usage: generate_find_my_table_private_pilot_packet.dart '
        '[output-directory]');
    exitCode = 64;
    return;
  }
  final target =
      arguments.isEmpty ? defaultFindMyTablePilotOutputPath : arguments.single;
  final packet = generateFindMyTablePrivatePilotPacket(
    outputDirectoryPath: target,
  );
  stdout
    ..writeln('Find My Table private pilot packet — SYNTHETIC / NOT LIVE')
    ..writeln('generator: $findMyTablePilotGeneratorVersion')
    ..writeln('output: ${packet.outputDirectoryPath}')
    ..writeln('artifacts: ${packet.artifactNames.length}')
    ..writeln('');
  for (final name in findMyTablePilotPayloadArtifacts) {
    stdout.writeln('${packet.sha256ByArtifact[name]}  $name');
  }
  stdout
    ..writeln('')
    ..writeln('manifest sha256 (reported separately): '
        '${packet.manifestSha256}  $findMyTablePilotManifestArtifact');
}
