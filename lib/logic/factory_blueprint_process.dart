/// Reusable, deterministic evidence machinery for Factory Blueprint work.
///
/// This model deliberately cannot grant Signal Scan, Blueprint, Assembly, or
/// public authority. It only records sponsor-issued authority references and
/// produces decision evidence. Live adapters must verify their own exact gate.
library;

T _enumByName<T extends Enum>(List<T> values, Object? raw, T fallback) {
  final name = raw?.toString();
  return values.where((value) => value.name == name).firstOrNull ?? fallback;
}

enum FactoryAuthorityKind { yesShortlist, blueprint, assembly, publicAction }

enum BlueprintSearchOutcome {
  evidenceAdded,
  noEvidence,
  failed,
  duplicateSuppressed,
}

enum BlueprintInvestmentVerdict { none, invest, revise, kill, park }

class FactoryAuthorityReference {
  final FactoryAuthorityKind kind;
  final String factoryRunId;
  final String scanSessionId;
  final String candidateId;
  final String evidenceId;

  const FactoryAuthorityReference({
    required this.kind,
    required this.factoryRunId,
    required this.scanSessionId,
    required this.candidateId,
    required this.evidenceId,
  });

  Map<String, Object?> toJson() => {
        'kind': kind.name,
        'factoryRunId': factoryRunId,
        'scanSessionId': scanSessionId,
        'candidateId': candidateId,
        'evidenceId': evidenceId,
      };
}

class BlueprintSearchLogEntry {
  final String attemptId;
  final String hypothesis;
  final String query;
  final List<String> sourceRefs;
  final BlueprintSearchOutcome outcome;
  final String fingerprint;
  final int recordedAtMs;

  const BlueprintSearchLogEntry({
    required this.attemptId,
    required this.hypothesis,
    required this.query,
    required this.sourceRefs,
    required this.outcome,
    required this.fingerprint,
    required this.recordedAtMs,
  });
}

class BlueprintCalibrationChange {
  final int previousStrictness;
  final int nextStrictness;
  final String changedFilter;
  final String evidenceReason;

  const BlueprintCalibrationChange({
    required this.previousStrictness,
    required this.nextStrictness,
    required this.changedFilter,
    required this.evidenceReason,
  });
}

class BlueprintScenario {
  final String scenarioId;
  final String label;
  final Map<String, double> assumptions;
  final Map<String, double> outputs;
  final List<String> unverifiedInputs;

  const BlueprintScenario({
    required this.scenarioId,
    required this.label,
    required this.assumptions,
    required this.outputs,
    this.unverifiedInputs = const [],
  });
}

class FirstTenBuyerRoute {
  final String routeId;
  final String channel;
  final int allocationTarget;
  final String messageHypothesis;
  final String proofEvent;
  final String killCondition;
  final bool newBuyerRequired;

  const FirstTenBuyerRoute({
    required this.routeId,
    required this.channel,
    required this.allocationTarget,
    required this.messageHypothesis,
    required this.proofEvent,
    required this.killCondition,
    this.newBuyerRequired = true,
  });
}

class BlueprintSponsorVerdict {
  final BlueprintInvestmentVerdict verdict;
  final String packetId;
  final String candidateId;
  final String evidenceId;
  final String sponsorReason;
  final int recordedAtMs;

  const BlueprintSponsorVerdict({
    required this.verdict,
    required this.packetId,
    required this.candidateId,
    required this.evidenceId,
    required this.sponsorReason,
    required this.recordedAtMs,
  });
}

class BlueprintRiskChallenge {
  final String riskId;
  final String claimUnderChallenge;
  final String disconfirmingEvidence;
  final String mitigation;
  final String stopRule;

  const BlueprintRiskChallenge({
    required this.riskId,
    required this.claimUnderChallenge,
    required this.disconfirmingEvidence,
    required this.mitigation,
    required this.stopRule,
  });
}

class BlueprintEvidenceEntry {
  final String evidenceId;
  final String sourceRef;
  final String claimSupported;
  final String proofState;
  final int accessedAtMs;
  final String contradiction;

  const BlueprintEvidenceEntry({
    required this.evidenceId,
    required this.sourceRef,
    required this.claimSupported,
    required this.proofState,
    required this.accessedAtMs,
    this.contradiction = '',
  });
}

class BlueprintReworkEvent {
  final String eventId;
  final String causalFailure;
  final String changedStrategy;
  final int recordedAtMs;

  const BlueprintReworkEvent({
    required this.eventId,
    required this.causalFailure,
    required this.changedStrategy,
    required this.recordedAtMs,
  });
}

class BlueprintCycleMetrics {
  final int startedAtMs;
  final int? completedAtMs;
  final List<BlueprintReworkEvent> rework;

  const BlueprintCycleMetrics({
    required this.startedAtMs,
    this.completedAtMs,
    this.rework = const [],
  });

  int? get cycleTimeMs =>
      completedAtMs == null ? null : completedAtMs! - startedAtMs;

  int get reworkCount => rework.length;
}

class BlueprintPresentationSection {
  final String title;
  final List<String> bullets;

  const BlueprintPresentationSection(this.title, this.bullets);
}

class FactoryBlueprintProcess {
  final int schemaVersion;
  final String packetId;
  final String factoryRunId;
  final String scanSessionId;
  final String candidateId;
  final String conceptFingerprint;
  final String duplicateOfCandidateId;
  final List<FactoryAuthorityReference> authorityReferences;
  final List<BlueprintSearchLogEntry> searchLog;
  final int strictness;
  final List<BlueprintCalibrationChange> calibration;
  final List<BlueprintScenario> scenarios;
  final List<FirstTenBuyerRoute> firstTenRoutes;
  final List<BlueprintRiskChallenge> risks;
  final List<BlueprintEvidenceEntry> evidence;
  final List<BlueprintSponsorVerdict> sponsorVerdicts;
  final BlueprintCycleMetrics cycle;

  const FactoryBlueprintProcess({
    this.schemaVersion = 1,
    required this.packetId,
    required this.factoryRunId,
    required this.scanSessionId,
    required this.candidateId,
    required this.conceptFingerprint,
    this.duplicateOfCandidateId = '',
    required this.authorityReferences,
    this.searchLog = const [],
    this.strictness = 0,
    this.calibration = const [],
    this.scenarios = const [],
    this.firstTenRoutes = const [],
    this.risks = const [],
    this.evidence = const [],
    this.sponsorVerdicts = const [],
    required this.cycle,
  });

  Map<String, Object?> toJson() => {
        'schemaVersion': schemaVersion,
        'packetId': packetId,
        'factoryRunId': factoryRunId,
        'scanSessionId': scanSessionId,
        'candidateId': candidateId,
        'conceptFingerprint': conceptFingerprint,
        'duplicateOfCandidateId': duplicateOfCandidateId,
        'authorityReferences':
            authorityReferences.map((value) => value.toJson()).toList(),
        'searchLog': searchLog
            .map((value) => {
                  'attemptId': value.attemptId,
                  'hypothesis': value.hypothesis,
                  'query': value.query,
                  'sourceRefs': value.sourceRefs,
                  'outcome': value.outcome.name,
                  'fingerprint': value.fingerprint,
                  'recordedAtMs': value.recordedAtMs,
                })
            .toList(),
        'strictness': strictness,
        'calibration': calibration
            .map((value) => {
                  'previousStrictness': value.previousStrictness,
                  'nextStrictness': value.nextStrictness,
                  'changedFilter': value.changedFilter,
                  'evidenceReason': value.evidenceReason,
                })
            .toList(),
        'scenarios': scenarios
            .map((value) => {
                  'scenarioId': value.scenarioId,
                  'label': value.label,
                  'assumptions': value.assumptions,
                  'outputs': value.outputs,
                  'unverifiedInputs': value.unverifiedInputs,
                })
            .toList(),
        'firstTenRoutes': firstTenRoutes
            .map((value) => {
                  'routeId': value.routeId,
                  'channel': value.channel,
                  'allocationTarget': value.allocationTarget,
                  'messageHypothesis': value.messageHypothesis,
                  'proofEvent': value.proofEvent,
                  'killCondition': value.killCondition,
                  'newBuyerRequired': value.newBuyerRequired,
                })
            .toList(),
        'risks': risks
            .map((value) => {
                  'riskId': value.riskId,
                  'claimUnderChallenge': value.claimUnderChallenge,
                  'disconfirmingEvidence': value.disconfirmingEvidence,
                  'mitigation': value.mitigation,
                  'stopRule': value.stopRule,
                })
            .toList(),
        'evidence': evidence
            .map((value) => {
                  'evidenceId': value.evidenceId,
                  'sourceRef': value.sourceRef,
                  'claimSupported': value.claimSupported,
                  'proofState': value.proofState,
                  'accessedAtMs': value.accessedAtMs,
                  'contradiction': value.contradiction,
                })
            .toList(),
        'sponsorVerdicts': sponsorVerdicts
            .map((value) => {
                  'verdict': value.verdict.name,
                  'packetId': value.packetId,
                  'candidateId': value.candidateId,
                  'evidenceId': value.evidenceId,
                  'sponsorReason': value.sponsorReason,
                  'recordedAtMs': value.recordedAtMs,
                })
            .toList(),
        'cycle': {
          'startedAtMs': cycle.startedAtMs,
          'completedAtMs': cycle.completedAtMs,
          'rework': cycle.rework
              .map((value) => {
                    'eventId': value.eventId,
                    'causalFailure': value.causalFailure,
                    'changedStrategy': value.changedStrategy,
                    'recordedAtMs': value.recordedAtMs,
                  })
              .toList(),
        },
      };

  factory FactoryBlueprintProcess.fromJson(Map<String, Object?> json) {
    final authorities = (json['authorityReferences'] as List? ?? const [])
        .whereType<Map>()
        .map((raw) => raw.cast<String, Object?>())
        .map(
          (value) => FactoryAuthorityReference(
            kind: _enumByName(
              FactoryAuthorityKind.values,
              value['kind'],
              FactoryAuthorityKind.yesShortlist,
            ),
            factoryRunId: value['factoryRunId']?.toString() ?? '',
            scanSessionId: value['scanSessionId']?.toString() ?? '',
            candidateId: value['candidateId']?.toString() ?? '',
            evidenceId: value['evidenceId']?.toString() ?? '',
          ),
        )
        .toList();
    final searchLog = (json['searchLog'] as List? ?? const [])
        .whereType<Map>()
        .map((raw) => raw.cast<String, Object?>())
        .map(
          (value) => BlueprintSearchLogEntry(
            attemptId: value['attemptId']?.toString() ?? '',
            hypothesis: value['hypothesis']?.toString() ?? '',
            query: value['query']?.toString() ?? '',
            sourceRefs: (value['sourceRefs'] as List? ?? const [])
                .map((item) => item.toString())
                .toList(),
            outcome: _enumByName(
              BlueprintSearchOutcome.values,
              value['outcome'],
              BlueprintSearchOutcome.failed,
            ),
            fingerprint: value['fingerprint']?.toString() ?? '',
            recordedAtMs: (value['recordedAtMs'] as num?)?.toInt() ?? 0,
          ),
        )
        .toList();
    final calibration = (json['calibration'] as List? ?? const [])
        .whereType<Map>()
        .map((raw) => raw.cast<String, Object?>())
        .map(
          (value) => BlueprintCalibrationChange(
            previousStrictness:
                (value['previousStrictness'] as num?)?.toInt() ?? 0,
            nextStrictness: (value['nextStrictness'] as num?)?.toInt() ?? 0,
            changedFilter: value['changedFilter']?.toString() ?? '',
            evidenceReason: value['evidenceReason']?.toString() ?? '',
          ),
        )
        .toList();
    Map<String, double> doubles(Object? raw) => (raw as Map? ?? const {})
        .map((key, value) => MapEntry(key.toString(), (value as num).toDouble()));
    final scenarios = (json['scenarios'] as List? ?? const [])
        .whereType<Map>()
        .map((raw) => raw.cast<String, Object?>())
        .map(
          (value) => BlueprintScenario(
            scenarioId: value['scenarioId']?.toString() ?? '',
            label: value['label']?.toString() ?? '',
            assumptions: doubles(value['assumptions']),
            outputs: doubles(value['outputs']),
            unverifiedInputs: (value['unverifiedInputs'] as List? ?? const [])
                .map((item) => item.toString())
                .toList(),
          ),
        )
        .toList();
    final routes = (json['firstTenRoutes'] as List? ?? const [])
        .whereType<Map>()
        .map((raw) => raw.cast<String, Object?>())
        .map(
          (value) => FirstTenBuyerRoute(
            routeId: value['routeId']?.toString() ?? '',
            channel: value['channel']?.toString() ?? '',
            allocationTarget:
                (value['allocationTarget'] as num?)?.toInt() ?? 0,
            messageHypothesis: value['messageHypothesis']?.toString() ?? '',
            proofEvent: value['proofEvent']?.toString() ?? '',
            killCondition: value['killCondition']?.toString() ?? '',
            newBuyerRequired: value['newBuyerRequired'] != false,
          ),
        )
        .toList();
    final risks = (json['risks'] as List? ?? const [])
        .whereType<Map>()
        .map((raw) => raw.cast<String, Object?>())
        .map(
          (value) => BlueprintRiskChallenge(
            riskId: value['riskId']?.toString() ?? '',
            claimUnderChallenge:
                value['claimUnderChallenge']?.toString() ?? '',
            disconfirmingEvidence:
                value['disconfirmingEvidence']?.toString() ?? '',
            mitigation: value['mitigation']?.toString() ?? '',
            stopRule: value['stopRule']?.toString() ?? '',
          ),
        )
        .toList();
    final evidence = (json['evidence'] as List? ?? const [])
        .whereType<Map>()
        .map((raw) => raw.cast<String, Object?>())
        .map(
          (value) => BlueprintEvidenceEntry(
            evidenceId: value['evidenceId']?.toString() ?? '',
            sourceRef: value['sourceRef']?.toString() ?? '',
            claimSupported: value['claimSupported']?.toString() ?? '',
            proofState: value['proofState']?.toString() ?? '',
            accessedAtMs: (value['accessedAtMs'] as num?)?.toInt() ?? 0,
            contradiction: value['contradiction']?.toString() ?? '',
          ),
        )
        .toList();
    final verdicts = (json['sponsorVerdicts'] as List? ?? const [])
        .whereType<Map>()
        .map((raw) => raw.cast<String, Object?>())
        .map(
          (value) => BlueprintSponsorVerdict(
            verdict: _enumByName(
              BlueprintInvestmentVerdict.values,
              value['verdict'],
              BlueprintInvestmentVerdict.none,
            ),
            packetId: value['packetId']?.toString() ?? '',
            candidateId: value['candidateId']?.toString() ?? '',
            evidenceId: value['evidenceId']?.toString() ?? '',
            sponsorReason: value['sponsorReason']?.toString() ?? '',
            recordedAtMs: (value['recordedAtMs'] as num?)?.toInt() ?? 0,
          ),
        )
        .toList();
    final cycleJson = (json['cycle'] as Map? ?? const {}).cast<String, Object?>();
    final rework = (cycleJson['rework'] as List? ?? const [])
        .whereType<Map>()
        .map((raw) => raw.cast<String, Object?>())
        .map(
          (value) => BlueprintReworkEvent(
            eventId: value['eventId']?.toString() ?? '',
            causalFailure: value['causalFailure']?.toString() ?? '',
            changedStrategy: value['changedStrategy']?.toString() ?? '',
            recordedAtMs: (value['recordedAtMs'] as num?)?.toInt() ?? 0,
          ),
        )
        .toList();
    return FactoryBlueprintProcess(
      schemaVersion: (json['schemaVersion'] as num?)?.toInt() ?? 1,
      packetId: json['packetId']?.toString() ?? '',
      factoryRunId: json['factoryRunId']?.toString() ?? '',
      scanSessionId: json['scanSessionId']?.toString() ?? '',
      candidateId: json['candidateId']?.toString() ?? '',
      conceptFingerprint: json['conceptFingerprint']?.toString() ?? '',
      duplicateOfCandidateId: json['duplicateOfCandidateId']?.toString() ?? '',
      authorityReferences: authorities,
      searchLog: searchLog,
      strictness: (json['strictness'] as num?)?.toInt() ?? 0,
      calibration: calibration,
      scenarios: scenarios,
      firstTenRoutes: routes,
      risks: risks,
      evidence: evidence,
      sponsorVerdicts: verdicts,
      cycle: BlueprintCycleMetrics(
        startedAtMs: (cycleJson['startedAtMs'] as num?)?.toInt() ?? 0,
        completedAtMs: (cycleJson['completedAtMs'] as num?)?.toInt(),
        rework: rework,
      ),
    );
  }

  bool hasExactAuthority(FactoryAuthorityKind kind) => authorityReferences.any(
        (ref) =>
            ref.kind == kind &&
            ref.factoryRunId == factoryRunId &&
            ref.scanSessionId == scanSessionId &&
            ref.candidateId == candidateId &&
            ref.evidenceId.isNotEmpty,
      );

  bool get isBlueprintAuthorized =>
      hasExactAuthority(FactoryAuthorityKind.blueprint);

  bool get isAssemblyAuthorized =>
      hasExactAuthority(FactoryAuthorityKind.assembly);

  bool get isPublicActionAuthorized =>
      hasExactAuthority(FactoryAuthorityKind.publicAction);

  bool hasDuplicateConcept(Iterable<String> knownFingerprints) =>
      knownFingerprints.contains(conceptFingerprint);

  bool get isKnownDuplicate => duplicateOfCandidateId.isNotEmpty;

  List<String> get validationIssues {
    final issues = <String>[];
    final seenAttempts = <String>{};
    for (final attempt in searchLog) {
      final repeated = !seenAttempts.add(attempt.fingerprint);
      if (repeated &&
          attempt.outcome != BlueprintSearchOutcome.duplicateSuppressed) {
        issues.add(
          'Repeated attempt ${attempt.attemptId} is not duplicate-suppressed',
        );
      }
    }
    if (calibration.isNotEmpty) {
      for (var index = 1; index < calibration.length; index++) {
        if (calibration[index].previousStrictness !=
            calibration[index - 1].nextStrictness) {
          issues.add('Calibration chain is discontinuous at index $index');
        }
      }
      if (calibration.last.nextStrictness != strictness) {
        issues.add('Calibration chain does not terminate at strictness');
      }
    }
    for (final verdict in sponsorVerdicts) {
      if (verdict.packetId != packetId || verdict.candidateId != candidateId) {
        issues.add('Sponsor verdict is not bound to this packet and candidate');
      }
    }
    return issues;
  }

  List<BlueprintPresentationSection> buildPresentation() => [
        BlueprintPresentationSection('Decision', [
          'Packet $packetId for candidate $candidateId',
          'Blueprint authority: ${isBlueprintAuthorized ? 'verified reference' : 'locked'}',
          'Assembly authority: ${isAssemblyAuthorized ? 'verified reference' : 'locked'}',
          'Public authority: ${isPublicActionAuthorized ? 'verified reference' : 'locked'}',
          'Duplicate status: ${isKnownDuplicate ? 'related to $duplicateOfCandidateId' : 'not recorded as duplicate'}',
          'Sponsor verdict: ${sponsorVerdicts.isEmpty ? 'awaiting' : sponsorVerdicts.last.verdict.name}',
        ]),
        BlueprintPresentationSection('Evidence', [
          '${evidence.length} evidence entries',
          '${searchLog.length} retained search attempts',
          '${evidence.where((item) => item.contradiction.isNotEmpty).length} contradictions retained',
        ]),
        BlueprintPresentationSection('Commercial model', [
          '${scenarios.length} scenario cases',
          '${firstTenRoutes.fold<int>(0, (sum, route) => sum + route.allocationTarget)} first-buyer allocation targets',
        ]),
        BlueprintPresentationSection('Challenge and process', [
          '${risks.length} challenged risks',
          'cycle time: ${cycle.cycleTimeMs?.toString() ?? 'in progress'} ms',
          'rework events: ${cycle.reworkCount}',
          'validation issues: ${validationIssues.length}',
        ]),
      ];
}
