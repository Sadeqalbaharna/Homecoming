library;

enum KaiDeliveryBoxOwner { agent, sponsor }

enum KaiDeliveryRisk {
  localSafe,
  liveExternal,
  destructive,
  securitySensitive,
  costly,
  productDecision,
}

enum KaiDeliveryBoxState {
  queued,
  ready,
  active,
  repairing,
  evidenceReview,
  verified,
  awaitingSponsor,
  blocked,
  deferred;

  String get wireName => switch (this) {
        evidenceReview => 'evidence_review',
        awaitingSponsor => 'awaiting_sponsor',
        _ => name,
      };

  static KaiDeliveryBoxState parse(String? value) {
    return KaiDeliveryBoxState.values.firstWhere(
      (state) => state.wireName == value || state.name == value,
      orElse: () => KaiDeliveryBoxState.queued,
    );
  }
}

class KaiDeliveryAttempt {
  final String fingerprint;
  final String causalBlocker;
  final String outcome;
  final List<String> evidenceRefs;
  final int recordedAt;

  const KaiDeliveryAttempt({
    required this.fingerprint,
    required this.causalBlocker,
    required this.outcome,
    required this.recordedAt,
    this.evidenceRefs = const [],
  });

  factory KaiDeliveryAttempt.fromMap(Map<dynamic, dynamic> map) =>
      KaiDeliveryAttempt(
        fingerprint: (map['fingerprint'] ?? '').toString(),
        causalBlocker: (map['causalBlocker'] ?? '').toString(),
        outcome: (map['outcome'] ?? '').toString(),
        evidenceRefs: (map['evidenceRefs'] is List)
            ? (map['evidenceRefs'] as List).map((e) => e.toString()).toList()
            : const [],
        recordedAt: (map['recordedAt'] is int) ? map['recordedAt'] as int : 0,
      );

  Map<String, dynamic> toMap() => {
        'fingerprint': fingerprint,
        'causalBlocker': causalBlocker,
        'outcome': outcome,
        'evidenceRefs': evidenceRefs,
        'recordedAt': recordedAt,
      };
}

class KaiDeliveryBox {
  final String projectId;
  final int phase;
  final String boxId;
  final String outcome;
  final List<String> dependencies;
  final KaiDeliveryBoxOwner owner;
  final KaiDeliveryRisk risk;
  final List<String> requiredEvidence;
  final KaiDeliveryBoxState state;
  final List<KaiDeliveryAttempt> attempts;
  final String blocker;
  final String escalationReason;
  final String sourceOfTruthRef;
  final String? workRequestId;
  final String? activeLeaseId;
  final List<String> evidenceRefs;
  final String? verifiedBy;
  final int? verifiedAt;

  const KaiDeliveryBox({
    required this.projectId,
    required this.phase,
    required this.boxId,
    required this.outcome,
    required this.owner,
    required this.risk,
    required this.requiredEvidence,
    required this.state,
    required this.sourceOfTruthRef,
    this.dependencies = const [],
    this.attempts = const [],
    this.blocker = '',
    this.escalationReason = '',
    this.workRequestId,
    this.activeLeaseId,
    this.evidenceRefs = const [],
    this.verifiedBy,
    this.verifiedAt,
  });

  String get identity => '$projectId:p$phase:$boxId';

  bool get isSponsorBoundary =>
      owner == KaiDeliveryBoxOwner.sponsor || risk != KaiDeliveryRisk.localSafe;

  bool get hasCompleteVerification =>
      verifiedBy == 'northstar_pm' &&
      (verifiedAt ?? 0) > 0 &&
      requiredEvidence.every((requirement) => evidenceRefs.any((ref) {
            final prefix = '$requirement => ';
            return ref.startsWith(prefix) &&
                ref.substring(prefix.length).trim().isNotEmpty;
          }));

  factory KaiDeliveryBox.fromMap(Map<dynamic, dynamic> map) => KaiDeliveryBox(
        projectId: (map['projectId'] ?? '').toString(),
        phase: (map['phase'] is int) ? map['phase'] as int : -1,
        boxId: (map['boxId'] ?? '').toString(),
        outcome: (map['outcome'] ?? '').toString(),
        dependencies: (map['dependencies'] is List)
            ? (map['dependencies'] as List).map((e) => e.toString()).toList()
            : const [],
        owner: KaiDeliveryBoxOwner.values.firstWhere(
          (owner) => owner.name == map['owner'],
          orElse: () => KaiDeliveryBoxOwner.sponsor,
        ),
        risk: KaiDeliveryRisk.values.firstWhere(
          (risk) => risk.name == map['risk'],
          orElse: () => KaiDeliveryRisk.securitySensitive,
        ),
        requiredEvidence: (map['requiredEvidence'] is List)
            ? (map['requiredEvidence'] as List)
                .map((e) => e.toString())
                .toList()
            : const [],
        state: KaiDeliveryBoxState.parse(map['state']?.toString()),
        attempts: (map['attempts'] is List)
            ? (map['attempts'] as List)
                .whereType<Map>()
                .map(KaiDeliveryAttempt.fromMap)
                .toList()
            : const [],
        blocker: (map['blocker'] ?? '').toString(),
        escalationReason: (map['escalationReason'] ?? '').toString(),
        sourceOfTruthRef: (map['sourceOfTruthRef'] ?? '').toString(),
        workRequestId: map['workRequestId']?.toString(),
        activeLeaseId: map['activeLeaseId']?.toString(),
        evidenceRefs: (map['evidenceRefs'] is List)
            ? (map['evidenceRefs'] as List).map((e) => e.toString()).toList()
            : const [],
        verifiedBy: map['verifiedBy']?.toString(),
        verifiedAt:
            (map['verifiedAt'] is int) ? map['verifiedAt'] as int : null,
      );

  Map<String, dynamic> toMap() => {
        'projectId': projectId,
        'phase': phase,
        'boxId': boxId,
        'outcome': outcome,
        'dependencies': dependencies,
        'owner': owner.name,
        'risk': risk.name,
        'requiredEvidence': requiredEvidence,
        'state': state.wireName,
        'attempts': attempts.map((attempt) => attempt.toMap()).toList(),
        'blocker': blocker,
        'escalationReason': escalationReason,
        'sourceOfTruthRef': sourceOfTruthRef,
        if (workRequestId != null) 'workRequestId': workRequestId,
        if (activeLeaseId != null) 'activeLeaseId': activeLeaseId,
        'evidenceRefs': evidenceRefs,
        if (verifiedBy != null) 'verifiedBy': verifiedBy,
        if (verifiedAt != null) 'verifiedAt': verifiedAt,
      };

  KaiDeliveryBox copyWith({
    KaiDeliveryBoxState? state,
    List<KaiDeliveryAttempt>? attempts,
    String? blocker,
    String? escalationReason,
    Object? workRequestId = _unchanged,
    Object? activeLeaseId = _unchanged,
    List<String>? evidenceRefs,
    Object? verifiedBy = _unchanged,
    Object? verifiedAt = _unchanged,
  }) =>
      KaiDeliveryBox(
        projectId: projectId,
        phase: phase,
        boxId: boxId,
        outcome: outcome,
        dependencies: dependencies,
        owner: owner,
        risk: risk,
        requiredEvidence: requiredEvidence,
        state: state ?? this.state,
        attempts: attempts ?? this.attempts,
        blocker: blocker ?? this.blocker,
        escalationReason: escalationReason ?? this.escalationReason,
        sourceOfTruthRef: sourceOfTruthRef,
        workRequestId: identical(workRequestId, _unchanged)
            ? this.workRequestId
            : workRequestId as String?,
        activeLeaseId: identical(activeLeaseId, _unchanged)
            ? this.activeLeaseId
            : activeLeaseId as String?,
        evidenceRefs: evidenceRefs ?? this.evidenceRefs,
        verifiedBy: identical(verifiedBy, _unchanged)
            ? this.verifiedBy
            : verifiedBy as String?,
        verifiedAt: identical(verifiedAt, _unchanged)
            ? this.verifiedAt
            : verifiedAt as int?,
      );
}

const Object _unchanged = Object();

class KaiDeliveryWorkPacket {
  final String requestId;
  final String boxIdentity;
  final String text;
  final String attemptFingerprint;

  const KaiDeliveryWorkPacket({
    required this.requestId,
    required this.boxIdentity,
    required this.text,
    required this.attemptFingerprint,
  });
}

class KaiDeliveryDispatch {
  final KaiDeliveryBox box;
  final KaiDeliveryWorkPacket packet;
  final bool reused;

  const KaiDeliveryDispatch({
    required this.box,
    required this.packet,
    required this.reused,
  });
}

class KaiDeliveryController {
  const KaiDeliveryController._();

  static KaiDeliveryBox? selectNext({
    required String projectId,
    required int activePhase,
    required List<KaiDeliveryBox> boxes,
    Set<String> activeWorkRequestIds = const {},
    Set<String> activeLeaseIds = const {},
  }) {
    final verified = {
      for (final box in boxes)
        if (box.state == KaiDeliveryBoxState.verified) box.identity,
    };
    final candidates = boxes.where((box) {
      if (box.projectId != projectId || box.phase != activePhase) {
        return false;
      }
      if (box.owner != KaiDeliveryBoxOwner.agent ||
          box.risk != KaiDeliveryRisk.localSafe) {
        return false;
      }
      if (box.state != KaiDeliveryBoxState.queued &&
          box.state != KaiDeliveryBoxState.ready &&
          box.state != KaiDeliveryBoxState.repairing) {
        return false;
      }
      if (!box.dependencies.every(verified.contains)) {
        return false;
      }
      if (box.workRequestId != null &&
          activeWorkRequestIds.contains(box.workRequestId)) {
        return false;
      }
      if (box.activeLeaseId != null &&
          activeLeaseIds.contains(box.activeLeaseId)) {
        return false;
      }
      return true;
    }).toList()
      ..sort((a, b) {
        final phaseOrder = a.phase.compareTo(b.phase);
        return phaseOrder != 0 ? phaseOrder : a.boxId.compareTo(b.boxId);
      });
    return candidates.isEmpty ? null : candidates.first;
  }

  static KaiDeliveryWorkPacket packetFor(
    KaiDeliveryBox box, {
    required String attemptFingerprint,
  }) {
    final fingerprint = attemptFingerprint.trim();
    if (!RegExp(r'^[a-f0-9]{16,64}$').hasMatch(fingerprint)) {
      throw StateError('invalid_attempt_fingerprint');
    }
    if (box.attempts.any((attempt) => attempt.fingerprint == fingerprint)) {
      throw StateError('identical_failed_attempt');
    }
    final requestId =
        'delivery_${box.projectId}_p${box.phase}_${box.boxId}_$fingerprint'
            .replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final text = '''READY FOR AGENT
Box: ${box.identity}
Outcome: ${box.outcome}
Source: ${box.sourceOfTruthRef}
Required evidence:
${box.requiredEvidence.map((item) => '- $item').join('\n')}
Constraints: local repository work only; preserve unrelated work; do not cross live, external, destructive, credential, security, cost, publication, or sponsor-decision boundaries.
Stop with files changed, tests, evidence, risks, and rollback.''';
    return KaiDeliveryWorkPacket(
      requestId: requestId,
      boxIdentity: box.identity,
      text: text,
      attemptFingerprint: fingerprint,
    );
  }

  /// Select one safe box and cross only the honest dispatch seam.
  ///
  /// [ensureRequest] must durably create or reuse [packet.requestId]. Returning
  /// does not mean an agent executed anything; the box remains `ready`.
  static Future<KaiDeliveryDispatch?> dispatchNext({
    required String projectId,
    required int activePhase,
    required List<KaiDeliveryBox> boxes,
    required String attemptFingerprint,
    required Future<bool> Function(KaiDeliveryWorkPacket packet) ensureRequest,
    Set<String> activeWorkRequestIds = const {},
    Set<String> activeLeaseIds = const {},
  }) async {
    final selected = selectNext(
      projectId: projectId,
      activePhase: activePhase,
      boxes: boxes,
      activeWorkRequestIds: activeWorkRequestIds,
      activeLeaseIds: activeLeaseIds,
    );
    if (selected == null) return null;
    final packet = packetFor(
      selected,
      attemptFingerprint: attemptFingerprint,
    );
    final reused = await ensureRequest(packet);
    return KaiDeliveryDispatch(
      box: selected.copyWith(
        state: KaiDeliveryBoxState.ready,
        workRequestId: packet.requestId,
      ),
      packet: packet,
      reused: reused,
    );
  }

  static KaiDeliveryBox recordFailure(
    KaiDeliveryBox box, {
    required String fingerprint,
    required String causalBlocker,
    required List<String> evidenceRefs,
    required int recordedAt,
  }) {
    if (box.isSponsorBoundary) {
      return box.copyWith(
        state: KaiDeliveryBoxState.awaitingSponsor,
        blocker: causalBlocker,
        escalationReason: 'True sponsor/live authority boundary.',
      );
    }
    if (box.attempts.any((attempt) => attempt.fingerprint == fingerprint)) {
      throw StateError('identical_failed_attempt');
    }
    if (!RegExp(r'^[a-f0-9]{16,64}$').hasMatch(fingerprint)) {
      throw StateError('invalid_attempt_fingerprint');
    }
    final attempts = [
      ...box.attempts,
      KaiDeliveryAttempt(
        fingerprint: fingerprint,
        causalBlocker: causalBlocker,
        outcome: 'failed',
        evidenceRefs: evidenceRefs,
        recordedAt: recordedAt,
      ),
    ];
    final sameCause = attempts
        .where((attempt) => attempt.causalBlocker == causalBlocker)
        .length;
    return box.copyWith(
      attempts: attempts,
      blocker: causalBlocker,
      state: sameCause >= 3
          ? KaiDeliveryBoxState.blocked
          : KaiDeliveryBoxState.repairing,
      escalationReason: sameCause >= 3
          ? 'Same causal blocker survived three distinct safe repairs.'
          : '',
    );
  }

  static KaiDeliveryBox reconcileWorkRequest(
    KaiDeliveryBox box, {
    required String status,
    required String attemptFingerprint,
    String error = '',
    List<String> evidenceRefs = const [],
    required int recordedAt,
  }) {
    return switch (status) {
      'queued' => box.copyWith(state: KaiDeliveryBoxState.ready),
      'running' => box.copyWith(state: KaiDeliveryBoxState.active),
      'done' => evidenceRefs.isEmpty
          ? recordFailure(
              box,
              fingerprint: attemptFingerprint,
              causalBlocker: 'closed_without_evidence',
              evidenceRefs: const [],
              recordedAt: recordedAt,
            )
          : submitEvidence(box, evidenceRefs: evidenceRefs),
      'failed' => recordFailure(
          box,
          fingerprint: attemptFingerprint,
          causalBlocker:
              error.trim().isEmpty ? 'unknown_failure' : error.trim(),
          evidenceRefs: evidenceRefs,
          recordedAt: recordedAt,
        ),
      'cancelled' => recordFailure(
          box,
          fingerprint: attemptFingerprint,
          causalBlocker: 'cancelled_before_review',
          evidenceRefs: evidenceRefs,
          recordedAt: recordedAt,
        ),
      _ => box,
    };
  }

  static KaiDeliveryBox submitEvidence(
    KaiDeliveryBox box, {
    required List<String> evidenceRefs,
  }) {
    if (evidenceRefs.isEmpty || evidenceRefs.any((ref) => ref.trim().isEmpty)) {
      throw StateError('evidence_required');
    }
    return box.copyWith(
      state: KaiDeliveryBoxState.evidenceReview,
      evidenceRefs: evidenceRefs,
    );
  }

  static KaiDeliveryBox verify(
    KaiDeliveryBox box, {
    required bool independentlyReviewed,
    required String reviewedBy,
    required List<String> evidenceRefs,
    required int verifiedAt,
  }) {
    if (box.owner == KaiDeliveryBoxOwner.sponsor) {
      throw StateError('sponsor_acceptance_required');
    }
    if (box.state != KaiDeliveryBoxState.evidenceReview ||
        !independentlyReviewed ||
        reviewedBy != 'northstar_pm' ||
        verifiedAt <= 0 ||
        !box.requiredEvidence.every((requirement) => evidenceRefs.any((ref) {
              final prefix = '$requirement => ';
              return ref.startsWith(prefix) &&
                  ref.substring(prefix.length).trim().isNotEmpty;
            }))) {
      throw StateError('proof_gate_not_met');
    }
    return box.copyWith(
      state: KaiDeliveryBoxState.verified,
      blocker: '',
      escalationReason: '',
      evidenceRefs: evidenceRefs,
      verifiedBy: reviewedBy,
      verifiedAt: verifiedAt,
    );
  }
}
