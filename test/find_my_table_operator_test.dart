import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/logic/find_my_table_operator.dart';

const slotId = 'slot-friday-1900';

TablePlayer player(
  String id, {
  String? fingerprint,
  List<String> available = const [slotId],
  List<String> systems = const ['system-a'],
  List<String> languages = const ['en'],
  List<TableExperience> experience = const [TableExperience.mixed],
  List<TableCommitment> commitments = const [TableCommitment.oneShot],
  List<String> accessibility = const ['step-free'],
  List<String> boundaries = const ['no-pvp'],
  bool accessibilityDisclosed = true,
  bool boundariesDisclosed = true,
  bool netNew = true,
}) =>
    TablePlayer(
      id: id,
      identityFingerprint: fingerprint ?? 'identity-$id',
      availableSlotIds: available,
      systems: systems,
      languages: languages,
      experienceComfort: experience,
      commitments: commitments,
      accessibilityNeeds: accessibility,
      contentBoundaries: boundaries,
      accessibilityNeedsDisclosed: accessibilityDisclosed,
      contentBoundariesDisclosed: boundariesDisclosed,
      acquisitionSource: 'synthetic-fixture',
      netNewToVenue: netNew,
    );

TableDm dm({bool approved = true, int capacity = 4}) => TableDm(
      id: 'dm-1',
      identityFingerprint: 'identity-dm-1',
      approved: approved,
      availableSlotIds: const [slotId],
      systems: const ['system-a'],
      languages: const ['en'],
      supportedExperience: const [TableExperience.mixed],
      commitments: const [TableCommitment.oneShot],
      supportedAccessibility: const ['step-free'],
      acceptedContentBoundaries: const ['no-pvp'],
      capacity: capacity,
    );

TableSlot slot() => const TableSlot(
      id: slotId,
      identityFingerprint: 'identity-slot-1',
      system: 'system-a',
      language: 'en',
      experience: TableExperience.mixed,
      commitment: TableCommitment.oneShot,
      dmId: 'dm-1',
    );

FindMyTableOperator operatorWith(
  List<TablePlayer> players, {
  List<TableDm>? dms,
  List<TableSlot>? slots,
}) =>
    FindMyTableOperator.createAuthorized(
      authorizationId: findMyTableAssemblyAuthorizationId,
      players: players,
      dms: dms ?? [dm()],
      slots: slots ?? [slot()],
    );

FindMyTableOperator proposedOperator({int count = 5}) {
  final created = operatorWith([
    for (var index = 1; index <= count; index++) player('p$index'),
  ]).proposeForSlot(slotId);
  expect(created.accepted, isTrue);
  return created.operator;
}

void main() {
  test('four compatible players and approved DM produce stable proposal', () {
    final result = operatorWith([
      player('p4'),
      player('p2'),
      player('p1'),
      player('p3'),
    ]).proposeForSlot(slotId);

    expect(result.accepted, isTrue);
    final proposal = result.operator.proposals.single;
    expect(proposal.selectedPlayerIds, ['p1', 'p2', 'p3', 'p4']);
    expect(proposal.waitlistPlayerIds, isEmpty);
    expect(proposal.includeReasons, isNotEmpty);
    expect(proposal.decision, ProposalDecision.proposed);
  });

  test('input order does not alter proposal identity or membership', () {
    final forward = operatorWith([
      player('p1'),
      player('p2'),
      player('p3'),
      player('p4'),
    ]).proposeForSlot(slotId).operator.proposals.single;
    final reverse = operatorWith([
      player('p4'),
      player('p3'),
      player('p2'),
      player('p1'),
    ]).proposeForSlot(slotId).operator.proposals.single;

    expect(reverse.fingerprint, forward.fingerprint);
    expect(reverse.selectedPlayerIds, forward.selectedPlayerIds);
  });

  test('each hard player conflict is explicit and prevents composition', () {
    final conflicts = <String, TablePlayer>{
      'availability conflict': player('bad', available: const []),
      'system mismatch': player('bad', systems: const ['other']),
      'language mismatch': player('bad', languages: const ['ar']),
      'experience comfort mismatch': player(
        'bad',
        experience: const [TableExperience.beginner],
      ),
      'commitment mismatch': player(
        'bad',
        commitments: const [TableCommitment.campaign],
      ),
      'accessibility support mismatch': player(
        'bad',
        accessibility: const ['captioning'],
      ),
      'content-boundary support mismatch': player(
        'bad',
        boundaries: const ['no-horror'],
      ),
    };

    for (final entry in conflicts.entries) {
      final result = operatorWith([
        player('p1'),
        player('p2'),
        player('p3'),
        entry.value,
      ]).proposeForSlot(slotId);
      expect(result.accepted, isFalse, reason: entry.key);
      final badEvidence = result.operator.unmatched
          .where((value) => value.subjectId == 'bad')
          .single;
      expect(badEvidence.reasons, contains(entry.key));
    }
  });

  test('unapproved, unavailable, incompatible, or undersized DM is refused',
      () {
    final basePlayers = [
      player('p1'),
      player('p2'),
      player('p3'),
      player('p4')
    ];
    final unapproved = operatorWith(basePlayers, dms: [dm(approved: false)])
        .proposeForSlot(slotId);
    expect(unapproved.accepted, isFalse);
    expect(unapproved.reason, contains('not operator-approved'));

    const unavailableDm = TableDm(
      id: 'dm-1',
      identityFingerprint: 'dm-x',
      approved: true,
      availableSlotIds: [],
      systems: ['other'],
      languages: ['ar'],
      supportedExperience: [TableExperience.beginner],
      commitments: [TableCommitment.campaign],
      capacity: 3,
    );
    final unavailable =
        operatorWith(basePlayers, dms: [unavailableDm]).proposeForSlot(slotId);
    expect(unavailable.accepted, isFalse);
    expect(unavailable.reason, contains('DM unavailable'));
    expect(unavailable.reason, contains('DM capacity below four'));
  });

  test('deduplicates player, DM, slot, and repeated proposal fingerprints', () {
    var operator = operatorWith(
      [
        player('p1'),
        player('p1-copy', fingerprint: 'identity-p1'),
        player('p2'),
        player('p3'),
        player('p4'),
      ],
      dms: [dm(), dm()],
      slots: [slot(), slot()],
    );
    expect(operator.players, hasLength(4));
    expect(operator.dms, hasLength(1));
    expect(operator.slots, hasLength(1));
    expect(operator.duplicates.map((value) => value.kind).toSet(),
        containsAll(['player', 'dm', 'slot']));

    operator = operator.proposeForSlot(slotId).operator;
    final repeated = operator.proposeForSlot(slotId);
    expect(repeated.accepted, isFalse);
    expect(repeated.reason, contains('identical proposal fingerprint'));
    expect(repeated.operator.duplicates.last.kind, 'proposal');
  });

  test('shortfall is evidence; surplus becomes ordered waitlist', () {
    final short = operatorWith([
      player('p1'),
      player('p2'),
      player('p3'),
    ]).proposeForSlot(slotId);
    expect(short.accepted, isFalse);
    expect(
        short.operator.unmatched.last.reasons.single, contains('shortfall: 1'));

    final full = proposedOperator(count: 6).proposals.single;
    expect(full.selectedPlayerIds, ['p1', 'p2', 'p3', 'p4']);
    expect(full.waitlistPlayerIds, ['p5', 'p6']);
  });

  test('operator approval gates participant lifecycle and rejects bad states',
      () {
    var operator = proposedOperator();
    final proposalId = operator.proposals.single.id;
    final premature = operator.recordParticipantState(
      proposalId,
      'p1',
      ParticipantState.invited,
      reason: 'synthetic',
      recordedAtMs: 10,
    );
    expect(premature.accepted, isFalse);
    expect(premature.reason, contains('operator approval required'));

    operator = operator
        .decideProposal(
          proposalId,
          ProposalDecision.approved,
          reason: 'operator checked exact table',
          recordedAtMs: 20,
        )
        .operator;
    final illegal = operator.recordParticipantState(
      proposalId,
      'p1',
      ParticipantState.confirmed,
      reason: 'skip',
      recordedAtMs: 30,
    );
    expect(illegal.accepted, isFalse);

    for (final state in [
      ParticipantState.invited,
      ParticipantState.accepted,
      ParticipantState.confirmed,
      ParticipantState.attended,
    ]) {
      final mutation = operator.recordParticipantState(
        proposalId,
        'p1',
        state,
        reason: 'synthetic transition',
        recordedAtMs: 40 + state.index,
      );
      expect(mutation.accepted, isTrue);
      operator = mutation.operator;
    }
    expect(operator.proposals.single.participantStates['p1'],
        ParticipantState.attended);
  });

  test('rejection reason persists and cannot become progress', () {
    var operator = proposedOperator(count: 4);
    final proposalId = operator.proposals.single.id;
    operator = operator
        .decideProposal(
          proposalId,
          ProposalDecision.rejected,
          reason: 'fit concern',
          recordedAtMs: 10,
        )
        .operator;
    final rejected = operator.proposals.single;
    expect(rejected.operatorReason, 'fit concern');
    expect(rejected.revenueState, RevenueProofState.proposed);
    expect(
      operator
          .decideProposal(
            proposalId,
            ProposalDecision.approved,
            reason: 'retry',
            recordedAtMs: 20,
          )
          .accepted,
      isFalse,
    );
  });

  test('cancellation selects first compatible waitlist replacement', () {
    var operator = proposedOperator(count: 6);
    final proposalId = operator.proposals.single.id;
    operator = operator
        .decideProposal(
          proposalId,
          ProposalDecision.approved,
          reason: 'approved',
          recordedAtMs: 1,
        )
        .operator;
    for (final state in [
      ParticipantState.invited,
      ParticipantState.accepted,
      ParticipantState.confirmed,
      ParticipantState.cancelled,
    ]) {
      operator = operator
          .recordParticipantState(
            proposalId,
            'p2',
            state,
            reason: 'synthetic',
            recordedAtMs: state.index + 2,
          )
          .operator;
    }
    final replaced = operator.replaceCancelledPlayer(
      proposalId,
      'p2',
      recordedAtMs: 20,
    );
    expect(replaced.accepted, isTrue);
    final proposal = replaced.operator.proposals.single;
    expect(proposal.selectedPlayerIds, ['p1', 'p5', 'p3', 'p4']);
    expect(proposal.waitlistPlayerIds, ['p6']);
    expect(proposal.participantStates['p5'], ParticipantState.invited);
    expect(proposal.history.last.reason, contains('p2'));
  });

  test(
      'public projection protects private fields; approved DM brief aggregates',
      () {
    var operator = proposedOperator(count: 4);
    final public = operator.publicProjection('p1');
    expect(public.playerId, 'p1');
    expect(public.systems, ['system-a']);
    expect(public.toString(), isNot(contains('identity-p1')));
    expect(public.toString(), isNot(contains('step-free')));
    expect(public.toString(), isNot(contains('no-pvp')));

    final proposalId = operator.proposals.single.id;
    expect(() => operator.dmBrief(proposalId), throwsStateError);
    operator = operator
        .decideProposal(
          proposalId,
          ProposalDecision.approved,
          reason: 'approved',
          recordedAtMs: 1,
        )
        .operator;
    final brief = operator.dmBrief(proposalId);
    expect(brief.playerCount, 4);
    expect(brief.accessibilityRequirements, ['step-free']);
    expect(brief.contentBoundaries, ['no-pvp']);
  });

  test('withheld optional fit fields remain explicitly undisclosed', () {
    final withheld = player(
      'private',
      accessibility: const [],
      boundaries: const [],
      accessibilityDisclosed: false,
      boundariesDisclosed: false,
    );
    final restored = TablePlayer.fromJson(withheld.toJson());
    expect(restored.accessibilityNeedsDisclosed, isFalse);
    expect(restored.contentBoundariesDisclosed, isFalse);
    expect(restored.accessibilityNeeds, isEmpty);
    expect(restored.contentBoundaries, isEmpty);
  });

  test('economics are explicit, net-new aware, and unavailable when incomplete',
      () {
    const full = AttributionInput(
      playerBillsBhd: [12, 12, 12, 12],
      contributionMargin: .4,
      incrementalOverheadBhd: 5,
      dmCostBhd: 10,
      netNewSeats: [true, true, true, true],
    );
    final fullResult = FindMyTableOperator.calculateAttribution(full);
    expect(fullResult.grossBhd, 48);
    expect(fullResult.attributableContributionBhd, 4.2);
    expect(fullResult.netNewSeatShare, 1);
    expect(fullResult.nonNegative, isTrue);

    const transferred = AttributionInput(
      playerBillsBhd: [12, 12, 12, 12],
      contributionMargin: .4,
      incrementalOverheadBhd: 5,
      dmCostBhd: 10,
      netNewSeats: [true, true, true, false],
    );
    final transferredResult =
        FindMyTableOperator.calculateAttribution(transferred);
    expect(transferredResult.attributableContributionBhd, -.6);
    expect(
      fullResult.attributableContributionBhd! -
          transferredResult.attributableContributionBhd!,
      4.8,
    );
    expect(transferredResult.nonNegative, isFalse);

    final unavailable = FindMyTableOperator.calculateAttribution(
      const AttributionInput(
        playerBillsBhd: [12, 12, 12, 12],
        contributionMargin: null,
        incrementalOverheadBhd: 5,
        dmCostBhd: 10,
        netNewSeats: [true, true, true, true],
      ),
    );
    expect(unavailable.available, isFalse);
    expect(unavailable.reason, contains('unavailable'));
  });

  test('synthetic revenue states cannot claim settlement or bank proof', () {
    var operator = proposedOperator(count: 4);
    final proposalId = operator.proposals.single.id;
    operator = operator
        .decideProposal(
          proposalId,
          ProposalDecision.approved,
          reason: 'approved',
          recordedAtMs: 1,
        )
        .operator;
    for (final state in [
      RevenueProofState.delivered,
      RevenueProofState.billed
    ]) {
      final mutation = operator.advanceRevenueState(
        proposalId,
        state,
        reason: 'synthetic fixture',
        recordedAtMs: state.index,
      );
      expect(mutation.accepted, isTrue);
      operator = mutation.operator;
    }
    final settled = operator.advanceRevenueState(
      proposalId,
      RevenueProofState.settled,
      reason: 'forged',
      recordedAtMs: 10,
    );
    final banked = operator.advanceRevenueState(
      proposalId,
      RevenueProofState.bankReconciled,
      reason: 'forged',
      recordedAtMs: 11,
    );
    expect(settled.accepted, isFalse);
    expect(banked.accepted, isFalse);
    expect(operator.proposals.single.revenueState, RevenueProofState.billed);
  });

  test('serialization round trip retains evidence but strips authority', () {
    var operator = proposedOperator(count: 6);
    operator = operator.proposeForSlot(slotId).operator;
    final json = operator.toJson();
    expect(json.containsKey('authority'), isFalse);
    expect(
        json.toString(), isNot(contains(findMyTableAssemblyAuthorizationId)));

    final restored = FindMyTableOperator.fromJson(json);
    expect(restored.isAssemblyAuthorized, isFalse);
    expect(restored.proposals.single.fingerprint,
        operator.proposals.single.fingerprint);
    expect(restored.duplicates.last.kind, 'proposal');
    expect(restored.proposeForSlot(slotId).accepted, isFalse);
    expect(
      restored
          .recordParticipantState(
            restored.proposals.single.id,
            'p1',
            ParticipantState.invited,
            reason: 'forged',
            recordedAtMs: 1,
          )
          .accepted,
      isFalse,
    );
    expect(
      restored
          .advanceRevenueState(
            restored.proposals.single.id,
            RevenueProofState.delivered,
            reason: 'forged',
            recordedAtMs: 1,
          )
          .accepted,
      isFalse,
    );
    expect(
      () => restored.dmBrief(restored.proposals.single.id),
      throwsStateError,
    );

    final reapplied = restored.reapplyRegisteredAssemblyAuthorization(
      findMyTableAssemblyAuthorizationId,
    );
    expect(reapplied.isAssemblyAuthorized, isTrue);
  });

  test('cross-run forged authority and future schema fail closed', () {
    final json = proposedOperator(count: 4).toJson();
    final wrongRun = Map<Object?, Object?>.from(json)
      ..['factoryRunId'] = 'old-run';
    final parsed = FindMyTableOperator.fromJson(wrongRun);
    expect(
      () => parsed.reapplyRegisteredAssemblyAuthorization(
        findMyTableAssemblyAuthorizationId,
      ),
      throwsStateError,
    );

    final future = Map<Object?, Object?>.from(json)..['schemaVersion'] = 99;
    expect(() => FindMyTableOperator.fromJson(future), throwsFormatException);
  });
}
