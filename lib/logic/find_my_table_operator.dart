/// Pure, synthetic-only internal operator for Find My Table.
///
/// No network, credentials, messaging, payment, customer-data, or public action
/// dependency exists in this domain. Persisted JSON never carries authority.
library;

const int findMyTableOperatorSchemaVersion = 1;
const String findMyTablePacketId = 'FSC-LEGACY-YES-001-BP-IC-v3';
const String findMyTableFactoryRunId =
    'factory-run-legacy-recovery-20260809-tablefinder-01';
const String findMyTableScanSessionId =
    'factory-scan-legacy-recovery-20260809-tablefinder-01';
const String findMyTableCandidateId = 'FSC-LEGACY-YES-001';
const String findMyTableAssemblyAuthorizationId =
    'FAA-20260809-FSC-LEGACY-YES-001-ASSEMBLY-01';

enum TableCommitment { oneShot, campaign }

enum TableExperience { beginner, mixed, experienced }

enum ProposalDecision { proposed, approved, rejected }

enum ParticipantState {
  selected,
  waitlisted,
  invited,
  accepted,
  declined,
  confirmed,
  attended,
  noShow,
  cancelled,
}

enum RevenueProofState {
  proposed,
  approved,
  delivered,
  billed,
  settled,
  bankReconciled,
}

String _enumName(Enum value) => value.name;

T _enumOr<T extends Enum>(List<T> values, Object? raw, T fallback) {
  for (final value in values) {
    if (value.name == raw?.toString()) return value;
  }
  return fallback;
}

String _canonical(Iterable<String> parts) => parts
    .map((part) => part.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' '))
    .where((part) => part.isNotEmpty)
    .join('|');

List<String> _sortedStrings(Iterable<String> values) => values
    .map((value) => value.trim())
    .where((value) => value.isNotEmpty)
    .toSet()
    .toList()
  ..sort();

class FindMyTableAssemblyAuthorization {
  final String authorizationId;
  final String packetId;
  final String factoryRunId;
  final String scanSessionId;
  final String candidateId;
  final String approvedBy;
  final String sponsorEvidence;

  const FindMyTableAssemblyAuthorization({
    required this.authorizationId,
    required this.packetId,
    required this.factoryRunId,
    required this.scanSessionId,
    required this.candidateId,
    required this.approvedBy,
    required this.sponsorEvidence,
  });
}

const registeredFindMyTableAssemblyAuthorization =
    FindMyTableAssemblyAuthorization(
  authorizationId: findMyTableAssemblyAuthorizationId,
  packetId: findMyTablePacketId,
  factoryRunId: findMyTableFactoryRunId,
  scanSessionId: findMyTableScanSessionId,
  candidateId: findMyTableCandidateId,
  approvedBy: 'sadeq',
  sponsorEvidence:
      'Direct sponsor reply "I authorize" to the immediately preceding exact Assembly and Codex-fallback request naming this packet, run, and candidate.',
);

class TablePlayer {
  final String id;
  final String identityFingerprint;
  final List<String> availableSlotIds;
  final List<String> systems;
  final List<String> languages;
  final List<TableExperience> experienceComfort;
  final List<TableCommitment> commitments;
  final List<String> accessibilityNeeds;
  final List<String> contentBoundaries;
  final bool accessibilityNeedsDisclosed;
  final bool contentBoundariesDisclosed;
  final String acquisitionSource;
  final bool netNewToVenue;

  const TablePlayer({
    required this.id,
    required this.identityFingerprint,
    required this.availableSlotIds,
    required this.systems,
    required this.languages,
    required this.experienceComfort,
    required this.commitments,
    this.accessibilityNeeds = const [],
    this.contentBoundaries = const [],
    this.accessibilityNeedsDisclosed = false,
    this.contentBoundariesDisclosed = false,
    required this.acquisitionSource,
    required this.netNewToVenue,
  });

  Map<String, Object?> toJson() => {
        'id': id,
        'identityFingerprint': identityFingerprint,
        'availableSlotIds': availableSlotIds,
        'systems': systems,
        'languages': languages,
        'experienceComfort': experienceComfort.map(_enumName).toList(),
        'commitments': commitments.map(_enumName).toList(),
        'accessibilityNeeds': accessibilityNeeds,
        'contentBoundaries': contentBoundaries,
        'accessibilityNeedsDisclosed': accessibilityNeedsDisclosed,
        'contentBoundariesDisclosed': contentBoundariesDisclosed,
        'acquisitionSource': acquisitionSource,
        'netNewToVenue': netNewToVenue,
      };

  factory TablePlayer.fromJson(Map<Object?, Object?> json) => TablePlayer(
        id: json['id']?.toString() ?? '',
        identityFingerprint: json['identityFingerprint']?.toString() ?? '',
        availableSlotIds: _stringList(json['availableSlotIds']),
        systems: _stringList(json['systems']),
        languages: _stringList(json['languages']),
        experienceComfort: (json['experienceComfort'] as List? ?? const [])
            .map((value) => _enumOr(
                  TableExperience.values,
                  value,
                  TableExperience.mixed,
                ))
            .toList(),
        commitments: (json['commitments'] as List? ?? const [])
            .map((value) => _enumOr(
                  TableCommitment.values,
                  value,
                  TableCommitment.oneShot,
                ))
            .toList(),
        accessibilityNeeds: _stringList(json['accessibilityNeeds']),
        contentBoundaries: _stringList(json['contentBoundaries']),
        accessibilityNeedsDisclosed:
            json['accessibilityNeedsDisclosed'] == true,
        contentBoundariesDisclosed: json['contentBoundariesDisclosed'] == true,
        acquisitionSource: json['acquisitionSource']?.toString() ?? '',
        netNewToVenue: json['netNewToVenue'] == true,
      );
}

class TableDm {
  final String id;
  final String identityFingerprint;
  final bool approved;
  final List<String> availableSlotIds;
  final List<String> systems;
  final List<String> languages;
  final List<TableExperience> supportedExperience;
  final List<TableCommitment> commitments;
  final List<String> supportedAccessibility;
  final List<String> acceptedContentBoundaries;
  final int capacity;

  const TableDm({
    required this.id,
    required this.identityFingerprint,
    required this.approved,
    required this.availableSlotIds,
    required this.systems,
    required this.languages,
    required this.supportedExperience,
    required this.commitments,
    this.supportedAccessibility = const [],
    this.acceptedContentBoundaries = const [],
    this.capacity = 4,
  });

  Map<String, Object?> toJson() => {
        'id': id,
        'identityFingerprint': identityFingerprint,
        'approved': approved,
        'availableSlotIds': availableSlotIds,
        'systems': systems,
        'languages': languages,
        'supportedExperience': supportedExperience.map(_enumName).toList(),
        'commitments': commitments.map(_enumName).toList(),
        'supportedAccessibility': supportedAccessibility,
        'acceptedContentBoundaries': acceptedContentBoundaries,
        'capacity': capacity,
      };

  factory TableDm.fromJson(Map<Object?, Object?> json) => TableDm(
        id: json['id']?.toString() ?? '',
        identityFingerprint: json['identityFingerprint']?.toString() ?? '',
        approved: json['approved'] == true,
        availableSlotIds: _stringList(json['availableSlotIds']),
        systems: _stringList(json['systems']),
        languages: _stringList(json['languages']),
        supportedExperience: (json['supportedExperience'] as List? ?? const [])
            .map((value) => _enumOr(
                  TableExperience.values,
                  value,
                  TableExperience.mixed,
                ))
            .toList(),
        commitments: (json['commitments'] as List? ?? const [])
            .map((value) => _enumOr(
                  TableCommitment.values,
                  value,
                  TableCommitment.oneShot,
                ))
            .toList(),
        supportedAccessibility: _stringList(json['supportedAccessibility']),
        acceptedContentBoundaries:
            _stringList(json['acceptedContentBoundaries']),
        capacity: (json['capacity'] as num?)?.toInt() ?? 4,
      );
}

class TableSlot {
  final String id;
  final String identityFingerprint;
  final String system;
  final String language;
  final TableExperience experience;
  final TableCommitment commitment;
  final String dmId;
  final int targetPlayers;

  const TableSlot({
    required this.id,
    required this.identityFingerprint,
    required this.system,
    required this.language,
    required this.experience,
    required this.commitment,
    required this.dmId,
    this.targetPlayers = 4,
  });

  Map<String, Object?> toJson() => {
        'id': id,
        'identityFingerprint': identityFingerprint,
        'system': system,
        'language': language,
        'experience': _enumName(experience),
        'commitment': _enumName(commitment),
        'dmId': dmId,
        'targetPlayers': targetPlayers,
      };

  factory TableSlot.fromJson(Map<Object?, Object?> json) => TableSlot(
        id: json['id']?.toString() ?? '',
        identityFingerprint: json['identityFingerprint']?.toString() ?? '',
        system: json['system']?.toString() ?? '',
        language: json['language']?.toString() ?? '',
        experience: _enumOr(
          TableExperience.values,
          json['experience'],
          TableExperience.mixed,
        ),
        commitment: _enumOr(
          TableCommitment.values,
          json['commitment'],
          TableCommitment.oneShot,
        ),
        dmId: json['dmId']?.toString() ?? '',
        targetPlayers: (json['targetPlayers'] as num?)?.toInt() ?? 4,
      );
}

class DuplicateEvidence {
  final String kind;
  final String recordId;
  final String fingerprint;
  final String duplicateOfId;
  final String reason;

  const DuplicateEvidence({
    required this.kind,
    required this.recordId,
    required this.fingerprint,
    required this.duplicateOfId,
    required this.reason,
  });

  Map<String, Object?> toJson() => {
        'kind': kind,
        'recordId': recordId,
        'fingerprint': fingerprint,
        'duplicateOfId': duplicateOfId,
        'reason': reason,
      };

  factory DuplicateEvidence.fromJson(Map<Object?, Object?> json) =>
      DuplicateEvidence(
        kind: json['kind']?.toString() ?? '',
        recordId: json['recordId']?.toString() ?? '',
        fingerprint: json['fingerprint']?.toString() ?? '',
        duplicateOfId: json['duplicateOfId']?.toString() ?? '',
        reason: json['reason']?.toString() ?? '',
      );
}

class UnmatchedEvidence {
  final String subjectId;
  final String slotId;
  final List<String> reasons;

  const UnmatchedEvidence({
    required this.subjectId,
    required this.slotId,
    required this.reasons,
  });

  Map<String, Object?> toJson() => {
        'subjectId': subjectId,
        'slotId': slotId,
        'reasons': reasons,
      };

  factory UnmatchedEvidence.fromJson(Map<Object?, Object?> json) =>
      UnmatchedEvidence(
        subjectId: json['subjectId']?.toString() ?? '',
        slotId: json['slotId']?.toString() ?? '',
        reasons: _stringList(json['reasons']),
      );
}

class ProposalStateEvent {
  final String subjectId;
  final String fromState;
  final String toState;
  final String reason;
  final int recordedAtMs;

  const ProposalStateEvent({
    required this.subjectId,
    required this.fromState,
    required this.toState,
    required this.reason,
    required this.recordedAtMs,
  });

  Map<String, Object?> toJson() => {
        'subjectId': subjectId,
        'fromState': fromState,
        'toState': toState,
        'reason': reason,
        'recordedAtMs': recordedAtMs,
      };

  factory ProposalStateEvent.fromJson(Map<Object?, Object?> json) =>
      ProposalStateEvent(
        subjectId: json['subjectId']?.toString() ?? '',
        fromState: json['fromState']?.toString() ?? '',
        toState: json['toState']?.toString() ?? '',
        reason: json['reason']?.toString() ?? '',
        recordedAtMs: (json['recordedAtMs'] as num?)?.toInt() ?? 0,
      );
}

class TableProposal {
  final String id;
  final String fingerprint;
  final String slotId;
  final String dmId;
  final List<String> selectedPlayerIds;
  final List<String> waitlistPlayerIds;
  final List<String> includeReasons;
  final ProposalDecision decision;
  final String operatorReason;
  final Map<String, ParticipantState> participantStates;
  final RevenueProofState revenueState;
  final List<ProposalStateEvent> history;

  const TableProposal({
    required this.id,
    required this.fingerprint,
    required this.slotId,
    required this.dmId,
    required this.selectedPlayerIds,
    required this.waitlistPlayerIds,
    required this.includeReasons,
    this.decision = ProposalDecision.proposed,
    this.operatorReason = '',
    required this.participantStates,
    this.revenueState = RevenueProofState.proposed,
    this.history = const [],
  });

  TableProposal copyWith({
    List<String>? selectedPlayerIds,
    List<String>? waitlistPlayerIds,
    ProposalDecision? decision,
    String? operatorReason,
    Map<String, ParticipantState>? participantStates,
    RevenueProofState? revenueState,
    List<ProposalStateEvent>? history,
  }) =>
      TableProposal(
        id: id,
        fingerprint: fingerprint,
        slotId: slotId,
        dmId: dmId,
        selectedPlayerIds: selectedPlayerIds ?? this.selectedPlayerIds,
        waitlistPlayerIds: waitlistPlayerIds ?? this.waitlistPlayerIds,
        includeReasons: includeReasons,
        decision: decision ?? this.decision,
        operatorReason: operatorReason ?? this.operatorReason,
        participantStates: participantStates ?? this.participantStates,
        revenueState: revenueState ?? this.revenueState,
        history: history ?? this.history,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'fingerprint': fingerprint,
        'slotId': slotId,
        'dmId': dmId,
        'selectedPlayerIds': selectedPlayerIds,
        'waitlistPlayerIds': waitlistPlayerIds,
        'includeReasons': includeReasons,
        'decision': _enumName(decision),
        'operatorReason': operatorReason,
        'participantStates': participantStates.map(
          (key, value) => MapEntry(key, _enumName(value)),
        ),
        'revenueState': _enumName(revenueState),
        'history': history.map((event) => event.toJson()).toList(),
      };

  factory TableProposal.fromJson(Map<Object?, Object?> json) {
    final states = <String, ParticipantState>{};
    final rawStates = json['participantStates'];
    if (rawStates is Map) {
      for (final entry in rawStates.entries) {
        states[entry.key.toString()] = _enumOr(
          ParticipantState.values,
          entry.value,
          ParticipantState.selected,
        );
      }
    }
    return TableProposal(
      id: json['id']?.toString() ?? '',
      fingerprint: json['fingerprint']?.toString() ?? '',
      slotId: json['slotId']?.toString() ?? '',
      dmId: json['dmId']?.toString() ?? '',
      selectedPlayerIds: _stringList(json['selectedPlayerIds']),
      waitlistPlayerIds: _stringList(json['waitlistPlayerIds']),
      includeReasons: _stringList(json['includeReasons']),
      decision: _enumOr(
        ProposalDecision.values,
        json['decision'],
        ProposalDecision.proposed,
      ),
      operatorReason: json['operatorReason']?.toString() ?? '',
      participantStates: states,
      revenueState: _enumOr(
        RevenueProofState.values,
        json['revenueState'],
        RevenueProofState.proposed,
      ),
      history: (json['history'] as List? ?? const [])
          .whereType<Map>()
          .map((value) => ProposalStateEvent.fromJson(value))
          .toList(),
    );
  }
}

class PublicPlayerProjection {
  final String playerId;
  final List<String> systems;
  final List<String> languages;
  final List<TableCommitment> commitments;

  const PublicPlayerProjection({
    required this.playerId,
    required this.systems,
    required this.languages,
    required this.commitments,
  });
}

class DmTableBrief {
  final String proposalId;
  final String system;
  final String language;
  final TableExperience experience;
  final TableCommitment commitment;
  final int playerCount;
  final List<String> accessibilityRequirements;
  final List<String> contentBoundaries;

  const DmTableBrief({
    required this.proposalId,
    required this.system,
    required this.language,
    required this.experience,
    required this.commitment,
    required this.playerCount,
    required this.accessibilityRequirements,
    required this.contentBoundaries,
  });
}

class AttributionInput {
  final List<double>? playerBillsBhd;
  final double? contributionMargin;
  final double? incrementalOverheadBhd;
  final double? dmCostBhd;
  final List<bool>? netNewSeats;

  const AttributionInput({
    required this.playerBillsBhd,
    required this.contributionMargin,
    required this.incrementalOverheadBhd,
    required this.dmCostBhd,
    required this.netNewSeats,
  });
}

class AttributionResult {
  final bool available;
  final String reason;
  final double? grossBhd;
  final double? attributableContributionBhd;
  final double? netNewSeatShare;
  final bool? nonNegative;

  const AttributionResult({
    required this.available,
    required this.reason,
    this.grossBhd,
    this.attributableContributionBhd,
    this.netNewSeatShare,
    this.nonNegative,
  });
}

class OperatorMutation {
  final FindMyTableOperator operator;
  final bool accepted;
  final String reason;

  const OperatorMutation(this.operator, this.accepted, this.reason);
}

class FindMyTableOperator {
  final int schemaVersion;
  final String packetId;
  final String factoryRunId;
  final String scanSessionId;
  final String candidateId;
  final String? _trustedAssemblyAuthorizationId;
  final bool syntheticOnly;
  final List<TablePlayer> players;
  final List<TableDm> dms;
  final List<TableSlot> slots;
  final List<TableProposal> proposals;
  final List<DuplicateEvidence> duplicates;
  final List<UnmatchedEvidence> unmatched;

  const FindMyTableOperator._({
    this.schemaVersion = findMyTableOperatorSchemaVersion,
    required this.packetId,
    required this.factoryRunId,
    required this.scanSessionId,
    required this.candidateId,
    String? trustedAssemblyAuthorizationId,
    this.syntheticOnly = true,
    required this.players,
    required this.dms,
    required this.slots,
    this.proposals = const [],
    this.duplicates = const [],
    this.unmatched = const [],
  }) : _trustedAssemblyAuthorizationId = trustedAssemblyAuthorizationId;

  bool get isAssemblyAuthorized =>
      _trustedAssemblyAuthorizationId == findMyTableAssemblyAuthorizationId &&
      packetId == findMyTablePacketId &&
      factoryRunId == findMyTableFactoryRunId &&
      scanSessionId == findMyTableScanSessionId &&
      candidateId == findMyTableCandidateId;

  static FindMyTableOperator createAuthorized({
    required String authorizationId,
    required List<TablePlayer> players,
    required List<TableDm> dms,
    required List<TableSlot> slots,
  }) {
    if (authorizationId !=
        registeredFindMyTableAssemblyAuthorization.authorizationId) {
      throw StateError('Assembly authorization is not registered');
    }
    final normalizedPlayers = _dedupePlayers(players);
    final normalizedDms = _dedupeDms(dms);
    final normalizedSlots = _dedupeSlots(slots);
    return FindMyTableOperator._(
      packetId: findMyTablePacketId,
      factoryRunId: findMyTableFactoryRunId,
      scanSessionId: findMyTableScanSessionId,
      candidateId: findMyTableCandidateId,
      trustedAssemblyAuthorizationId: authorizationId,
      players: normalizedPlayers.records,
      dms: normalizedDms.records,
      slots: normalizedSlots.records,
      duplicates: [
        ...normalizedPlayers.duplicates,
        ...normalizedDms.duplicates,
        ...normalizedSlots.duplicates,
      ],
    );
  }

  FindMyTableOperator _copyWith({
    String? trustedAssemblyAuthorizationId,
    bool preserveTrustedAuthorization = true,
    List<TableProposal>? proposals,
    List<DuplicateEvidence>? duplicates,
    List<UnmatchedEvidence>? unmatched,
  }) =>
      FindMyTableOperator._(
        schemaVersion: schemaVersion,
        packetId: packetId,
        factoryRunId: factoryRunId,
        scanSessionId: scanSessionId,
        candidateId: candidateId,
        trustedAssemblyAuthorizationId: preserveTrustedAuthorization
            ? trustedAssemblyAuthorizationId ?? _trustedAssemblyAuthorizationId
            : null,
        syntheticOnly: syntheticOnly,
        players: players,
        dms: dms,
        slots: slots,
        proposals: proposals ?? this.proposals,
        duplicates: duplicates ?? this.duplicates,
        unmatched: unmatched ?? this.unmatched,
      );

  OperatorMutation proposeForSlot(String slotId) {
    if (!isAssemblyAuthorized) {
      return OperatorMutation(this, false, 'exact Assembly authority required');
    }
    final slot = _firstWhereOrNull(slots, (value) => value.id == slotId);
    if (slot == null) {
      return OperatorMutation(this, false, 'slot not found');
    }
    if (slot.targetPlayers != 4) {
      return OperatorMutation(
          this, false, 'only four-player tables are in scope');
    }
    final dm = _firstWhereOrNull(dms, (value) => value.id == slot.dmId);
    final dmReasons = _dmIneligibility(dm, slot);
    if (dmReasons.isNotEmpty) {
      final evidence = UnmatchedEvidence(
        subjectId: slot.dmId,
        slotId: slot.id,
        reasons: dmReasons,
      );
      return OperatorMutation(
        _copyWith(unmatched: [...unmatched, evidence]),
        false,
        dmReasons.join('; '),
      );
    }
    final eligibleDm = dm!;

    final eligible = <TablePlayer>[];
    final evidence = <UnmatchedEvidence>[];
    for (final player in players) {
      final reasons = _playerIneligibility(player, eligibleDm, slot);
      if (reasons.isEmpty) {
        eligible.add(player);
      } else {
        evidence.add(UnmatchedEvidence(
          subjectId: player.id,
          slotId: slot.id,
          reasons: reasons,
        ));
      }
    }
    eligible.sort((left, right) => left.id.compareTo(right.id));
    if (eligible.length < 4) {
      evidence.add(UnmatchedEvidence(
        subjectId: 'table:${slot.id}',
        slotId: slot.id,
        reasons: ['shortfall: ${4 - eligible.length} compatible player(s)'],
      ));
      return OperatorMutation(
        _copyWith(unmatched: [...unmatched, ...evidence]),
        false,
        'fewer than four compatible players',
      );
    }

    final selected = eligible.take(4).map((value) => value.id).toList();
    final waitlist = eligible.skip(4).map((value) => value.id).toList();
    final fingerprint = _canonical([
      packetId,
      factoryRunId,
      candidateId,
      slot.id,
      eligibleDm.id,
      ...selected,
    ]);
    final existing = _firstWhereOrNull(
      proposals,
      (value) => value.fingerprint == fingerprint,
    );
    if (existing != null) {
      final duplicate = DuplicateEvidence(
        kind: 'proposal',
        recordId: 'repeat:${slot.id}',
        fingerprint: fingerprint,
        duplicateOfId: existing.id,
        reason: 'identical proposal fingerprint suppressed',
      );
      return OperatorMutation(
        _copyWith(duplicates: [...duplicates, duplicate]),
        false,
        duplicate.reason,
      );
    }
    final participantStates = <String, ParticipantState>{
      for (final id in selected) id: ParticipantState.selected,
      for (final id in waitlist) id: ParticipantState.waitlisted,
    };
    final proposal = TableProposal(
      id: 'proposal-${proposals.length + 1}-${slot.id}',
      fingerprint: fingerprint,
      slotId: slot.id,
      dmId: eligibleDm.id,
      selectedPlayerIds: selected,
      waitlistPlayerIds: waitlist,
      includeReasons: const [
        'availability, system, language, experience, commitment, accessibility, and boundaries satisfied',
        'approved external DM has capacity for four players',
      ],
      participantStates: participantStates,
    );
    return OperatorMutation(
      _copyWith(
        proposals: [...proposals, proposal],
        unmatched: [...unmatched, ...evidence],
      ),
      true,
      'four-player proposal created for operator review',
    );
  }

  OperatorMutation decideProposal(
    String proposalId,
    ProposalDecision decision, {
    required String reason,
    required int recordedAtMs,
  }) {
    if (!isAssemblyAuthorized) {
      return OperatorMutation(this, false, 'exact Assembly authority required');
    }
    if (decision == ProposalDecision.proposed) {
      return OperatorMutation(this, false, 'operator must approve or reject');
    }
    final index = proposals.indexWhere((value) => value.id == proposalId);
    if (index < 0) return OperatorMutation(this, false, 'proposal not found');
    final proposal = proposals[index];
    if (proposal.decision != ProposalDecision.proposed) {
      return OperatorMutation(this, false, 'proposal already decided');
    }
    if (reason.trim().isEmpty) {
      return OperatorMutation(this, false, 'operator reason required');
    }
    final updated = [...proposals];
    updated[index] = proposal.copyWith(
      decision: decision,
      operatorReason: reason.trim(),
      revenueState: decision == ProposalDecision.approved
          ? RevenueProofState.approved
          : RevenueProofState.proposed,
      history: [
        ...proposal.history,
        ProposalStateEvent(
          subjectId: proposal.id,
          fromState: ProposalDecision.proposed.name,
          toState: decision.name,
          reason: reason.trim(),
          recordedAtMs: recordedAtMs,
        ),
      ],
    );
    return OperatorMutation(
      _copyWith(proposals: updated),
      true,
      'operator decision recorded',
    );
  }

  OperatorMutation recordParticipantState(
    String proposalId,
    String playerId,
    ParticipantState next, {
    required String reason,
    required int recordedAtMs,
  }) {
    if (!isAssemblyAuthorized) {
      return OperatorMutation(this, false, 'exact Assembly authority required');
    }
    final index = proposals.indexWhere((value) => value.id == proposalId);
    if (index < 0) return OperatorMutation(this, false, 'proposal not found');
    final proposal = proposals[index];
    if (proposal.decision != ProposalDecision.approved) {
      return OperatorMutation(
          this, false, 'operator approval required before invitation');
    }
    final current = proposal.participantStates[playerId];
    if (current == null) {
      return OperatorMutation(this, false, 'player is not in proposal');
    }
    if (!_allowedParticipantTransition(current, next)) {
      return OperatorMutation(
        this,
        false,
        'illegal participant transition ${current.name} -> ${next.name}',
      );
    }
    final states = {...proposal.participantStates, playerId: next};
    final updated = [...proposals];
    updated[index] = proposal.copyWith(
      participantStates: states,
      history: [
        ...proposal.history,
        ProposalStateEvent(
          subjectId: playerId,
          fromState: current.name,
          toState: next.name,
          reason: reason.trim(),
          recordedAtMs: recordedAtMs,
        ),
      ],
    );
    return OperatorMutation(
      _copyWith(proposals: updated),
      true,
      'participant state recorded; no message sent',
    );
  }

  OperatorMutation replaceCancelledPlayer(
    String proposalId,
    String cancelledPlayerId, {
    required int recordedAtMs,
  }) {
    if (!isAssemblyAuthorized) {
      return OperatorMutation(this, false, 'exact Assembly authority required');
    }
    final index = proposals.indexWhere((value) => value.id == proposalId);
    if (index < 0) return OperatorMutation(this, false, 'proposal not found');
    final proposal = proposals[index];
    if (proposal.decision != ProposalDecision.approved) {
      return OperatorMutation(this, false, 'operator approval required');
    }
    if (proposal.participantStates[cancelledPlayerId] !=
        ParticipantState.cancelled) {
      return OperatorMutation(
          this, false, 'selected player must be cancelled first');
    }
    if (proposal.waitlistPlayerIds.isEmpty) {
      return OperatorMutation(this, false, 'no compatible waitlisted player');
    }
    final replacement = proposal.waitlistPlayerIds.first;
    final selected = [...proposal.selectedPlayerIds];
    final selectedIndex = selected.indexOf(cancelledPlayerId);
    if (selectedIndex < 0) {
      return OperatorMutation(this, false, 'cancelled player was not selected');
    }
    selected[selectedIndex] = replacement;
    final waitlist = proposal.waitlistPlayerIds.skip(1).toList();
    final states = {
      ...proposal.participantStates,
      replacement: ParticipantState.invited,
    };
    final updated = [...proposals];
    updated[index] = proposal.copyWith(
      selectedPlayerIds: selected,
      waitlistPlayerIds: waitlist,
      participantStates: states,
      history: [
        ...proposal.history,
        ProposalStateEvent(
          subjectId: replacement,
          fromState: ParticipantState.waitlisted.name,
          toState: ParticipantState.invited.name,
          reason:
              'ordered compatible waitlist replacement for $cancelledPlayerId',
          recordedAtMs: recordedAtMs,
        ),
      ],
    );
    return OperatorMutation(
      _copyWith(proposals: updated),
      true,
      'compatible replacement recorded; no message sent',
    );
  }

  OperatorMutation advanceRevenueState(
    String proposalId,
    RevenueProofState next, {
    required String reason,
    required int recordedAtMs,
  }) {
    if (!isAssemblyAuthorized) {
      return OperatorMutation(this, false, 'exact Assembly authority required');
    }
    final index = proposals.indexWhere((value) => value.id == proposalId);
    if (index < 0) return OperatorMutation(this, false, 'proposal not found');
    final proposal = proposals[index];
    if (next == RevenueProofState.settled ||
        next == RevenueProofState.bankReconciled) {
      return OperatorMutation(
        this,
        false,
        'synthetic Assembly cannot record settled or bank-reconciled revenue',
      );
    }
    final allowed = {
      RevenueProofState.approved: RevenueProofState.delivered,
      RevenueProofState.delivered: RevenueProofState.billed,
    };
    if (allowed[proposal.revenueState] != next) {
      return OperatorMutation(
        this,
        false,
        'illegal revenue transition ${proposal.revenueState.name} -> ${next.name}',
      );
    }
    final updated = [...proposals];
    updated[index] = proposal.copyWith(
      revenueState: next,
      history: [
        ...proposal.history,
        ProposalStateEvent(
          subjectId: proposal.id,
          fromState: proposal.revenueState.name,
          toState: next.name,
          reason: reason.trim(),
          recordedAtMs: recordedAtMs,
        ),
      ],
    );
    return OperatorMutation(
      _copyWith(proposals: updated),
      true,
      'synthetic revenue proof state recorded',
    );
  }

  PublicPlayerProjection publicProjection(String playerId) {
    final player = _firstWhereOrNull(players, (value) => value.id == playerId);
    if (player == null) throw ArgumentError.value(playerId, 'playerId');
    return PublicPlayerProjection(
      playerId: player.id,
      systems: _sortedStrings(player.systems),
      languages: _sortedStrings(player.languages),
      commitments: [...player.commitments]..sort(
          (left, right) => left.name.compareTo(right.name),
        ),
    );
  }

  DmTableBrief dmBrief(String proposalId) {
    if (!isAssemblyAuthorized) {
      throw StateError('exact Assembly authority required for DM brief');
    }
    final proposal = _firstWhereOrNull(
      proposals,
      (value) => value.id == proposalId,
    );
    if (proposal == null) throw ArgumentError.value(proposalId, 'proposalId');
    if (proposal.decision != ProposalDecision.approved) {
      throw StateError('operator approval required for DM brief');
    }
    final slot =
        _firstWhereOrNull(slots, (value) => value.id == proposal.slotId)!;
    final selected = players
        .where((value) => proposal.selectedPlayerIds.contains(value.id))
        .toList();
    return DmTableBrief(
      proposalId: proposal.id,
      system: slot.system,
      language: slot.language,
      experience: slot.experience,
      commitment: slot.commitment,
      playerCount: selected.length,
      accessibilityRequirements: _sortedStrings(selected
          .where((value) => value.accessibilityNeedsDisclosed)
          .expand((value) => value.accessibilityNeeds)),
      contentBoundaries: _sortedStrings(selected
          .where((value) => value.contentBoundariesDisclosed)
          .expand((value) => value.contentBoundaries)),
    );
  }

  static AttributionResult calculateAttribution(AttributionInput input) {
    final bills = input.playerBillsBhd;
    final seats = input.netNewSeats;
    if (bills == null ||
        input.contributionMargin == null ||
        input.incrementalOverheadBhd == null ||
        input.dmCostBhd == null ||
        seats == null) {
      return const AttributionResult(
        available: false,
        reason: 'required economics or seat-source input unavailable',
      );
    }
    if (bills.isEmpty || bills.length != seats.length) {
      return const AttributionResult(
        available: false,
        reason: 'bill and seat-source counts must match',
      );
    }
    if (input.contributionMargin! < 0 || input.contributionMargin! > 1) {
      return const AttributionResult(
        available: false,
        reason: 'contribution margin must be between zero and one',
      );
    }
    final gross = bills.fold<double>(0, (sum, value) => sum + value);
    var attributableGross = 0.0;
    for (var index = 0; index < bills.length; index++) {
      if (seats[index]) attributableGross += bills[index];
    }
    final contribution = attributableGross * input.contributionMargin! -
        input.incrementalOverheadBhd! -
        input.dmCostBhd!;
    return AttributionResult(
      available: true,
      reason: 'modeled from explicit inputs; not settled revenue',
      grossBhd: _roundMoney(gross),
      attributableContributionBhd: _roundMoney(contribution),
      netNewSeatShare: seats.where((value) => value).length / seats.length,
      nonNegative: contribution >= 0,
    );
  }

  Map<String, Object?> toJson() => {
        'schemaVersion': schemaVersion,
        'packetId': packetId,
        'factoryRunId': factoryRunId,
        'scanSessionId': scanSessionId,
        'candidateId': candidateId,
        'syntheticOnly': syntheticOnly,
        'players': players.map((value) => value.toJson()).toList(),
        'dms': dms.map((value) => value.toJson()).toList(),
        'slots': slots.map((value) => value.toJson()).toList(),
        'proposals': proposals.map((value) => value.toJson()).toList(),
        'duplicates': duplicates.map((value) => value.toJson()).toList(),
        'unmatched': unmatched.map((value) => value.toJson()).toList(),
        // Authority is deliberately absent.
      };

  factory FindMyTableOperator.fromJson(Map<Object?, Object?> json) {
    final version = (json['schemaVersion'] as num?)?.toInt() ?? 0;
    if (version != findMyTableOperatorSchemaVersion) {
      throw FormatException('unsupported Find My Table schema $version');
    }
    return FindMyTableOperator._(
      schemaVersion: version,
      packetId: json['packetId']?.toString() ?? '',
      factoryRunId: json['factoryRunId']?.toString() ?? '',
      scanSessionId: json['scanSessionId']?.toString() ?? '',
      candidateId: json['candidateId']?.toString() ?? '',
      trustedAssemblyAuthorizationId: null,
      syntheticOnly: json['syntheticOnly'] != false,
      players: _objectList(json['players']).map(TablePlayer.fromJson).toList(),
      dms: _objectList(json['dms']).map(TableDm.fromJson).toList(),
      slots: _objectList(json['slots']).map(TableSlot.fromJson).toList(),
      proposals:
          _objectList(json['proposals']).map(TableProposal.fromJson).toList(),
      duplicates: _objectList(json['duplicates'])
          .map(DuplicateEvidence.fromJson)
          .toList(),
      unmatched: _objectList(json['unmatched'])
          .map(UnmatchedEvidence.fromJson)
          .toList(),
    );
  }

  FindMyTableOperator reapplyRegisteredAssemblyAuthorization(
    String authorizationId,
  ) {
    if (authorizationId != findMyTableAssemblyAuthorizationId ||
        packetId != findMyTablePacketId ||
        factoryRunId != findMyTableFactoryRunId ||
        scanSessionId != findMyTableScanSessionId ||
        candidateId != findMyTableCandidateId ||
        !syntheticOnly) {
      throw StateError('exact registered Assembly authorization refused');
    }
    return _copyWith(trustedAssemblyAuthorizationId: authorizationId);
  }
}

class _DedupeResult<T> {
  final List<T> records;
  final List<DuplicateEvidence> duplicates;
  const _DedupeResult(this.records, this.duplicates);
}

_DedupeResult<TablePlayer> _dedupePlayers(List<TablePlayer> input) =>
    _dedupe<TablePlayer>(
      input,
      kind: 'player',
      idOf: (value) => value.id,
      fingerprintOf: (value) => value.identityFingerprint,
    );

_DedupeResult<TableDm> _dedupeDms(List<TableDm> input) => _dedupe<TableDm>(
      input,
      kind: 'dm',
      idOf: (value) => value.id,
      fingerprintOf: (value) => value.identityFingerprint,
    );

_DedupeResult<TableSlot> _dedupeSlots(List<TableSlot> input) =>
    _dedupe<TableSlot>(
      input,
      kind: 'slot',
      idOf: (value) => value.id,
      fingerprintOf: (value) => value.identityFingerprint,
    );

_DedupeResult<T> _dedupe<T>(
  List<T> input, {
  required String kind,
  required String Function(T) idOf,
  required String Function(T) fingerprintOf,
}) {
  final sorted = [...input]
    ..sort((left, right) => idOf(left).compareTo(idOf(right)));
  final records = <T>[];
  final duplicates = <DuplicateEvidence>[];
  final fingerprints = <String, String>{};
  final ids = <String>{};
  for (final value in sorted) {
    final id = idOf(value).trim();
    final fingerprint = fingerprintOf(value).trim();
    final duplicateOf = fingerprints[fingerprint];
    if (id.isEmpty || fingerprint.isEmpty) {
      throw ArgumentError('$kind id and identity fingerprint are required');
    }
    if (ids.contains(id) || duplicateOf != null) {
      duplicates.add(DuplicateEvidence(
        kind: kind,
        recordId: id,
        fingerprint: fingerprint,
        duplicateOfId: duplicateOf ?? id,
        reason: 'duplicate $kind identity retained and suppressed',
      ));
      continue;
    }
    ids.add(id);
    fingerprints[fingerprint] = id;
    records.add(value);
  }
  return _DedupeResult(records, duplicates);
}

List<String> _dmIneligibility(TableDm? dm, TableSlot slot) {
  if (dm == null) return ['assigned DM not found'];
  final reasons = <String>[];
  if (!dm.approved) reasons.add('DM is not operator-approved');
  if (!dm.availableSlotIds.contains(slot.id)) reasons.add('DM unavailable');
  if (!dm.systems.contains(slot.system)) reasons.add('DM system mismatch');
  if (!dm.languages.contains(slot.language)) {
    reasons.add('DM language mismatch');
  }
  if (!dm.supportedExperience.contains(slot.experience)) {
    reasons.add('DM experience-format mismatch');
  }
  if (!dm.commitments.contains(slot.commitment)) {
    reasons.add('DM commitment mismatch');
  }
  if (dm.capacity < 4) reasons.add('DM capacity below four');
  return reasons;
}

List<String> _playerIneligibility(
    TablePlayer player, TableDm dm, TableSlot slot) {
  final reasons = <String>[];
  if (!player.availableSlotIds.contains(slot.id)) {
    reasons.add('availability conflict');
  }
  if (!player.systems.contains(slot.system)) reasons.add('system mismatch');
  if (!player.languages.contains(slot.language)) {
    reasons.add('language mismatch');
  }
  if (!player.experienceComfort.contains(slot.experience)) {
    reasons.add('experience comfort mismatch');
  }
  if (!player.commitments.contains(slot.commitment)) {
    reasons.add('commitment mismatch');
  }
  if (player.accessibilityNeedsDisclosed &&
      !player.accessibilityNeeds.every(dm.supportedAccessibility.contains)) {
    reasons.add('accessibility support mismatch');
  }
  if (player.contentBoundariesDisclosed &&
      !player.contentBoundaries.every(dm.acceptedContentBoundaries.contains)) {
    reasons.add('content-boundary support mismatch');
  }
  return reasons;
}

bool _allowedParticipantTransition(
  ParticipantState current,
  ParticipantState next,
) {
  const allowed = <ParticipantState, Set<ParticipantState>>{
    ParticipantState.selected: {ParticipantState.invited},
    ParticipantState.waitlisted: {},
    ParticipantState.invited: {
      ParticipantState.accepted,
      ParticipantState.declined,
    },
    ParticipantState.accepted: {
      ParticipantState.confirmed,
      ParticipantState.declined,
    },
    ParticipantState.confirmed: {
      ParticipantState.attended,
      ParticipantState.noShow,
      ParticipantState.cancelled,
    },
    ParticipantState.declined: {},
    ParticipantState.attended: {},
    ParticipantState.noShow: {},
    ParticipantState.cancelled: {},
  };
  return allowed[current]?.contains(next) ?? false;
}

List<String> _stringList(Object? raw) =>
    (raw as List? ?? const []).map((value) => value.toString()).toList();

List<Map<Object?, Object?>> _objectList(Object? raw) =>
    (raw as List? ?? const [])
        .whereType<Map>()
        .map(Map<Object?, Object?>.from)
        .toList();

T? _firstWhereOrNull<T>(Iterable<T> values, bool Function(T) predicate) {
  for (final value in values) {
    if (predicate(value)) return value;
  }
  return null;
}

double _roundMoney(double value) => (value * 100).roundToDouble() / 100;
