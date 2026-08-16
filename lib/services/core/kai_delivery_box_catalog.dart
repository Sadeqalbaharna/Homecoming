import 'kai_delivery_box.dart';

class _BoxSpec {
  final String id;
  final String outcome;
  final KaiDeliveryBoxOwner owner;
  final KaiDeliveryRisk risk;
  final KaiDeliveryBoxState state;
  final List<String> evidence;
  final List<String>? dependencies;

  const _BoxSpec(
    this.id,
    this.outcome, {
    this.owner = KaiDeliveryBoxOwner.agent,
    this.risk = KaiDeliveryRisk.localSafe,
    this.state = KaiDeliveryBoxState.deferred,
    this.dependencies,
    this.evidence = const [
      'Focused tests and an evidence-backed review report'
    ],
  });
}

class KaiDeliveryBoxCatalog {
  const KaiDeliveryBoxCatalog._();

  static List<KaiDeliveryBox> forPhase(
    String projectId,
    int phase,
    String sourceRef,
  ) {
    final specs = _catalog[projectId]?[phase] ?? const <_BoxSpec>[];
    final boxes = <KaiDeliveryBox>[];
    for (var index = 0; index < specs.length; index++) {
      final spec = specs[index];
      boxes.add(KaiDeliveryBox(
        projectId: projectId,
        phase: phase,
        boxId: spec.id,
        outcome: spec.outcome,
        dependencies: spec.dependencies ??
            (index == 0
                ? const []
                : [
                    specs[index - 1].id.contains('.')
                        ? specs[index - 1].id
                        : '$projectId:p$phase:${specs[index - 1].id}'
                  ]),
        owner: spec.owner,
        risk: spec.risk,
        requiredEvidence: spec.evidence,
        state: spec.state,
        sourceOfTruthRef: sourceRef,
        evidenceRefs: spec.state == KaiDeliveryBoxState.verified
            ? [
                for (final requirement in spec.evidence)
                  '$requirement => accepted governing evidence at $sourceRef',
              ]
            : const [],
        verifiedBy:
            spec.state == KaiDeliveryBoxState.verified ? 'northstar_pm' : null,
        verifiedAt:
            spec.state == KaiDeliveryBoxState.verified ? 1786233600000 : null,
      ));
    }
    return boxes;
  }

  static const _catalog = <String, Map<int, List<_BoxSpec>>>{
    'homecoming_northstar': {
      0: [
        _BoxSpec(
            'governing_map', 'Freeze the governing map and proof vocabulary',
            state: KaiDeliveryBoxState.verified),
        _BoxSpec('contradiction_audit',
            'Represent every known architecture contradiction',
            state: KaiDeliveryBoxState.verified),
        _BoxSpec(
            'baseline_review', 'Independently accept the baseline document',
            state: KaiDeliveryBoxState.verified),
      ],
      1: [
        _BoxSpec('coexistence_harness',
            'Prove four distinct body sessions can coexist'),
        _BoxSpec('editor_exact_body',
            'Prove one exact body receives one Central outbound'),
        _BoxSpec('tethered_quest_privacy',
            'Observe tethered Quest delivery with no transcript or technical leakage',
            owner: KaiDeliveryBoxOwner.sponsor,
            risk: KaiDeliveryRisk.liveExternal),
      ],
      2: [
        _BoxSpec('transport_contract',
            'Freeze authenticated untethered device transport and revocation'),
        _BoxSpec('transport_implementation',
            'Implement the bounded transport without client secrets'),
        _BoxSpec('device_reconnect_proof',
            'Observe heartbeat, turn, ack, reconnect, and revocation on device',
            owner: KaiDeliveryBoxOwner.sponsor,
            risk: KaiDeliveryRisk.liveExternal),
      ],
      3: [
        _BoxSpec('attention_contracts',
            'Prove intake, pacing, quiet hours, routing, and durable retry',
            state: KaiDeliveryBoxState.verified),
        _BoxSpec('reminder_local_gate',
            'Prove reminder identity, restart durability, and read-only acceptance tooling locally',
            state: KaiDeliveryBoxState.verified),
        _BoxSpec('attended_reminder_restart',
            'Observe one exact desktop reminder survive restart and restore once',
            owner: KaiDeliveryBoxOwner.sponsor,
            risk: KaiDeliveryRisk.liveExternal,
            state: KaiDeliveryBoxState.awaitingSponsor),
        _BoxSpec('seven_day_attention_run',
            'Observe seven days without spam or dropped commitments',
            owner: KaiDeliveryBoxOwner.sponsor,
            risk: KaiDeliveryRisk.liveExternal,
            state: KaiDeliveryBoxState.deferred),
      ],
      4: [
        _BoxSpec('continuity_corpus',
            'Assemble a privacy-scoped cold-start continuity corpus'),
        _BoxSpec('restart_resume',
            'Prove identity, relationship, memory, and work resume after restart'),
        _BoxSpec('cross_device_privacy',
            'Observe cross-device continuity with provenance and no room leakage',
            owner: KaiDeliveryBoxOwner.sponsor,
            risk: KaiDeliveryRisk.liveExternal),
      ],
      5: [
        _BoxSpec('capability_contracts',
            'Freeze permission, cost, idempotency, and failure contracts'),
        _BoxSpec('completed_work_route',
            'Implement one exact completed-work return route'),
        _BoxSpec('capability_recovery',
            'Prove recovery and bounded cost for every enabled capability'),
      ],
      6: [
        _BoxSpec('improvement_sandbox',
            'Isolate one bounded self-improvement candidate'),
        _BoxSpec('independent_evaluation',
            'Run an independent before/after evaluation'),
        _BoxSpec('canary_rollback',
            'Prove canary promotion, audit, and automatic rollback'),
        _BoxSpec('promotion_approval',
            'Approve the exact promotion without goal rewriting',
            owner: KaiDeliveryBoxOwner.sponsor,
            risk: KaiDeliveryRisk.productDecision),
      ],
      7: [
        _BoxSpec('deployment_design',
            'Freeze a multi-host or server continuity design'),
        _BoxSpec('failover_monitoring',
            'Implement failover, backups, and monitoring'),
        _BoxSpec(
            'restore_drill', 'Observe a full restore and laptop-absence drill',
            owner: KaiDeliveryBoxOwner.sponsor,
            risk: KaiDeliveryRisk.liveExternal),
      ],
      8: [
        _BoxSpec('ten_condition_audit',
            'Audit all ten Northstar conditions against primary evidence'),
        _BoxSpec('causal_gap_repairs',
            'Repair every causal acceptance gap without weakening gates'),
        _BoxSpec('northstar_acceptance',
            'Accept continuous usefulness and one recognizable companion',
            owner: KaiDeliveryBoxOwner.sponsor,
            risk: KaiDeliveryRisk.productDecision),
      ],
    },
    'hoard_northstar': {
      0: [
        _BoxSpec('hoard.p0.b01',
            'Prove the complete Firestore venue authorization matrix',
            state: KaiDeliveryBoxState.verified,
            evidence: ['130/130 accepted Firestore authorization tests']),
        _BoxSpec('hoard.p0.b02',
            'Bind venue assignments and the idempotent backfill inventory',
            owner: KaiDeliveryBoxOwner.sponsor,
            risk: KaiDeliveryRisk.liveExternal,
            state: KaiDeliveryBoxState.verified,
            dependencies: ['hoard.p0.b01']),
        _BoxSpec('hoard.p0.b03',
            'Reconcile Storage authorization for the field-test boundary',
            owner: KaiDeliveryBoxOwner.sponsor,
            risk: KaiDeliveryRisk.securitySensitive,
            state: KaiDeliveryBoxState.verified,
            dependencies: ['hoard.p0.b01']),
        _BoxSpec('hoard.p0.b04',
            'Accept Phase 0 without converting deferred probes into proof',
            owner: KaiDeliveryBoxOwner.sponsor,
            risk: KaiDeliveryRisk.productDecision,
            state: KaiDeliveryBoxState.verified,
            dependencies: [
              'hoard.p0.b01',
              'hoard.p0.b02',
              'hoard.p0.b03',
            ]),
      ],
      1: [
        _BoxSpec('hoard.p1.b01',
            'Bind backup, restore, and atomic reset safety locally',
            state: KaiDeliveryBoxState.verified,
            dependencies: ['hoard.p0.b04']),
        _BoxSpec('hoard.p1.b02',
            'Observe one attended same-scope recovery with protected parity',
            owner: KaiDeliveryBoxOwner.sponsor,
            risk: KaiDeliveryRisk.destructive,
            state: KaiDeliveryBoxState.awaitingSponsor,
            dependencies: ['hoard.p1.b01', 'hoard.p1.b03']),
        _BoxSpec(
            'hoard.p1.b03', 'Pin the staging release and rollback checklist',
            state: KaiDeliveryBoxState.verified,
            dependencies: ['hoard.p1.b01']),
        _BoxSpec(
            'hoard.p1.b04a', 'Inventory every critical Function trust boundary',
            state: KaiDeliveryBoxState.verified,
            dependencies: [
              'hoard.p1.b01',
              'hoard.p1.b03'
            ],
            evidence: [
              'Commit e1c7863; functions inventory and validators PASS'
            ]),
        _BoxSpec('hoard.p1.b04b',
            'Prove critical Functions fail closed at accepted boundaries',
            risk: KaiDeliveryRisk.securitySensitive,
            state: KaiDeliveryBoxState.verified,
            dependencies: ['hoard.p1.b04a'],
            evidence: ['Commit e1c7863; combined local suite 48/48 PASS']),
        _BoxSpec('hoard.p1.b04c',
            'Accept the hardened Functions candidate in an authorized live surface',
            owner: KaiDeliveryBoxOwner.sponsor,
            risk: KaiDeliveryRisk.liveExternal,
            state: KaiDeliveryBoxState.awaitingSponsor,
            dependencies: ['hoard.p1.b02', 'hoard.p1.b04b']),
        _BoxSpec('hoard.p1.b05a',
            'Freeze local recovery signal, redaction, threshold, and response contracts',
            state: KaiDeliveryBoxState.verified,
            dependencies: ['hoard.p1.b01', 'hoard.p1.b03'],
            evidence: ['Commit 4f22a3a; three deterministic validators PASS']),
        _BoxSpec('hoard.p1.b05b',
            'Emit deterministic redacted recovery and ingestion signals locally',
            state: KaiDeliveryBoxState.verified,
            dependencies: [
              'hoard.p1.b05a',
              'hoard.p1.b04b'
            ],
            evidence: [
              'Commit 4f22a3a; reset/inventory 23/23 and signal 5/5 PASS'
            ]),
        _BoxSpec('hoard.p1.b05c',
            'Deliver approved signals through external monitoring',
            owner: KaiDeliveryBoxOwner.sponsor,
            risk: KaiDeliveryRisk.liveExternal,
            state: KaiDeliveryBoxState.awaitingSponsor,
            dependencies: [
              'hoard.p1.b02',
              'hoard.p1.b04b',
              'hoard.p1.b05b',
            ]),
        _BoxSpec('hoard.p1.b06', 'Accept the complete pilot safety baseline',
            owner: KaiDeliveryBoxOwner.sponsor,
            risk: KaiDeliveryRisk.liveExternal,
            state: KaiDeliveryBoxState.awaitingSponsor,
            dependencies: [
              'hoard.p1.b02',
              'hoard.p1.b04a',
              'hoard.p1.b04b',
              'hoard.p1.b04c',
              'hoard.p1.b05a',
              'hoard.p1.b05b',
              'hoard.p1.b05c',
            ]),
      ],
      2: [
        _BoxSpec('hoard.p2.b01',
            'Approve the pilot venue, operator, period, and privacy boundary',
            owner: KaiDeliveryBoxOwner.sponsor,
            risk: KaiDeliveryRisk.productDecision,
            dependencies: ['hoard.p1.b06']),
        _BoxSpec('hoard.p2.b02',
            'Expose ingestion provenance, freshness, coverage, and rejects',
            dependencies: ['hoard.p2.b01']),
        _BoxSpec('hoard.p2.b03',
            'Bind the authoritative external POS or settlement close',
            dependencies: ['hoard.p2.b02']),
        _BoxSpec('hoard.p2.b04',
            'Prevent double counting and expose unexplained gaps',
            dependencies: ['hoard.p2.b02', 'hoard.p2.b03']),
        _BoxSpec('hoard.p2.b05',
            'Close one real explainable baseline without duplicates',
            owner: KaiDeliveryBoxOwner.sponsor,
            risk: KaiDeliveryRisk.liveExternal,
            dependencies: [
              'hoard.p2.b01',
              'hoard.p2.b02',
              'hoard.p2.b03',
              'hoard.p2.b04',
            ]),
      ],
      3: [
        _BoxSpec('hoard.p3.b01',
            'Bind findings to owned actions and measured outcomes'),
        _BoxSpec('hoard.p3.b02',
            'Run the finding-to-outcome loop without engineer repair',
            dependencies: ['hoard.p3.b01']),
        _BoxSpec(
            'hoard.p3.b03', 'Run the pilot cadence with named action owners',
            owner: KaiDeliveryBoxOwner.sponsor,
            risk: KaiDeliveryRisk.liveExternal,
            dependencies: ['hoard.p3.b02']),
        _BoxSpec('hoard.p3.b04',
            'Verify at least BD 500 per month without estimate leakage',
            owner: KaiDeliveryBoxOwner.sponsor,
            risk: KaiDeliveryRisk.productDecision,
            dependencies: [
              'hoard.p3.b01',
              'hoard.p3.b02',
              'hoard.p3.b03',
            ]),
      ],
      4: [
        _BoxSpec(
            'hoard.p4.b01', 'Initialize a repeat run from a versioned playbook',
            dependencies: ['hoard.p3.b04']),
        _BoxSpec('hoard.p4.b02',
            'Make support and recovery executable by a named operator',
            dependencies: ['hoard.p4.b01']),
        _BoxSpec('hoard.p4.b03',
            'Observe a second operator complete and explain the loop',
            owner: KaiDeliveryBoxOwner.sponsor,
            risk: KaiDeliveryRisk.liveExternal,
            dependencies: ['hoard.p4.b01', 'hoard.p4.b02']),
        _BoxSpec(
            'hoard.p4.b04', 'Accept repeatability with bounded support load',
            owner: KaiDeliveryBoxOwner.sponsor,
            risk: KaiDeliveryRisk.productDecision,
            dependencies: [
              'hoard.p4.b01',
              'hoard.p4.b02',
              'hoard.p4.b03',
            ]),
      ],
      5: [
        _BoxSpec('hoard.p5.b01',
            'Prove tenant-safe self-service organization lifecycle',
            risk: KaiDeliveryRisk.securitySensitive,
            dependencies: ['hoard.p4.b04']),
        _BoxSpec('hoard.p5.b02',
            'Approve fail-closed entitlements and commercial limits',
            owner: KaiDeliveryBoxOwner.sponsor,
            risk: KaiDeliveryRisk.productDecision,
            dependencies: ['hoard.p5.b01']),
        _BoxSpec('hoard.p5.b03',
            'Make operational support and recovery launch-ready',
            dependencies: ['hoard.p5.b01']),
        _BoxSpec(
            'hoard.p5.b04', 'Bound growth experiments behind financial trust',
            owner: KaiDeliveryBoxOwner.sponsor,
            risk: KaiDeliveryRisk.productDecision,
            dependencies: ['hoard.p5.b02', 'hoard.p5.b03']),
        _BoxSpec('hoard.p5.b05',
            'Accept every commercial and operational launch gate',
            owner: KaiDeliveryBoxOwner.sponsor,
            risk: KaiDeliveryRisk.liveExternal,
            dependencies: [
              'hoard.p5.b01',
              'hoard.p5.b02',
              'hoard.p5.b03',
              'hoard.p5.b04',
            ]),
      ],
    },
    'kingdom_northstar': {
      0: [
        _BoxSpec('loyalty_loop_contract',
            'Freeze one loyalty loop and actor authority map',
            state: KaiDeliveryBoxState.evidenceReview,
            evidence: [
              'K1.1 disposable package is Tested; authoritative adoption remains UNVERIFIED'
            ]),
        _BoxSpec('pilot_target', 'Choose the pilot cohort and return target',
            owner: KaiDeliveryBoxOwner.sponsor,
            risk: KaiDeliveryRisk.productDecision),
        _BoxSpec('schema_command_map',
            'Map every economic command to one authority'),
      ],
      1: [
        _BoxSpec('server_ledger',
            'Move points, tiles, vouchers, and redemption to server authority',
            state: KaiDeliveryBoxState.active,
            evidence: [
              'K1.6-M1 is Tested in isolated commit 64997ad: 10/10 static safeguards and 15/15 emulator behaviors pass; authoritative adoption remains UNVERIFIED, as do registration and live proof'
            ]),
        _BoxSpec('emulator_matrix',
            'Prove roles, ownership, idempotency, and conservation'),
        _BoxSpec('failure_recovery', 'Prove replay-safe failure and recovery'),
      ],
      2: [
        _BoxSpec('staging_loop', 'Build the staging onboard-to-redeem loop'),
        _BoxSpec(
            'guest_walkthrough', 'Observe one real guest complete the loop',
            owner: KaiDeliveryBoxOwner.sponsor,
            risk: KaiDeliveryRisk.liveExternal),
        _BoxSpec('ledger_reconciliation',
            'Reconcile the staging ledger without manual repair'),
      ],
      3: [
        _BoxSpec('release_monitoring',
            'Prove release, monitoring, privacy, and support'),
        _BoxSpec('backup_rollback', 'Prove backup and rollback behavior'),
        _BoxSpec('operator_playbook', 'Accept the Tavern operator playbook',
            owner: KaiDeliveryBoxOwner.sponsor,
            risk: KaiDeliveryRisk.productDecision),
      ],
      4: [
        _BoxSpec('pilot_authorization', 'Authorize a named 30-day cohort',
            owner: KaiDeliveryBoxOwner.sponsor,
            risk: KaiDeliveryRisk.productDecision),
        _BoxSpec('thirty_day_run',
            'Observe activation, earning, spending, return, fraud, and support',
            owner: KaiDeliveryBoxOwner.sponsor,
            risk: KaiDeliveryRisk.liveExternal),
        _BoxSpec('pilot_evidence_audit',
            'Audit pilot evidence for completeness and drift'),
      ],
      5: [
        _BoxSpec('retention_analysis',
            'Measure the accepted repeat-engagement target'),
        _BoxSpec('second_cohort', 'Repeat with a second cohort or period',
            owner: KaiDeliveryBoxOwner.sponsor,
            risk: KaiDeliveryRisk.liveExternal),
        _BoxSpec(
            'scale_acceptance', 'Accept retention proof and scale readiness',
            owner: KaiDeliveryBoxOwner.sponsor,
            risk: KaiDeliveryRisk.productDecision),
      ],
    },
    'factory_northstar': {
      0: [
        _BoxSpec('scan_evidence',
            'Record buyer, painful job, demand signal, and rejected alternatives',
            state: KaiDeliveryBoxState.verified),
        _BoxSpec('candidate_votes', 'Record Sadeq\'s Yes/Maybe/Close/No votes',
            owner: KaiDeliveryBoxOwner.sponsor,
            risk: KaiDeliveryRisk.productDecision,
            state: KaiDeliveryBoxState.verified,
            evidence: [
              'Run-bound Find My Table YES reconstruction bound in Factory packet FSC-LEGACY-YES-001-BP-IC-v3 at commit 76dd3ade'
            ]),
        _BoxSpec('blueprint_authority',
            'Authorize one named YES candidate to enter Blueprint',
            owner: KaiDeliveryBoxOwner.sponsor,
            risk: KaiDeliveryRisk.productDecision,
            state: KaiDeliveryBoxState.verified,
            evidence: [
              'Authorization BPA-20260809-FSC-LEGACY-YES-001 is bound only to the Find My Table Blueprint packet; it does not authorize Assembly'
            ]),
      ],
      1: [
        _BoxSpec('offer_scope',
            'Freeze the smallest sellable offer and explicit cuts',
            state: KaiDeliveryBoxState.active,
            evidence: [
              'Find My Table packet FSC-LEGACY-YES-001-BP-IC-v3 is Tested by 8/8 operating-evidence checks at commit 76dd3ade; Blueprint remains active'
            ]),
        _BoxSpec('commercial_terms',
            'Choose price, channel, fulfilment, refunds, and margin',
            owner: KaiDeliveryBoxOwner.sponsor,
            risk: KaiDeliveryRisk.productDecision,
            state: KaiDeliveryBoxState.awaitingSponsor),
        _BoxSpec('blueprint_acceptance', 'Accept the run-bound Blueprint',
            owner: KaiDeliveryBoxOwner.sponsor,
            risk: KaiDeliveryRisk.productDecision,
            state: KaiDeliveryBoxState.awaitingSponsor),
      ],
      2: [
        _BoxSpec('artifact_build', 'Produce the exact sellable artifact'),
        _BoxSpec(
            'artifact_durability', 'Prove the artifact path and offer match'),
      ],
      3: [
        _BoxSpec('quality_suite', 'Run build and focused product tests'),
        _BoxSpec('delivery_simulation',
            'Prove purchase-to-delivery locally without publishing'),
        _BoxSpec('support_refund', 'Accept support and refund handling',
            owner: KaiDeliveryBoxOwner.sponsor,
            risk: KaiDeliveryRisk.productDecision),
      ],
      4: [
        _BoxSpec('listing_assets',
            'Prepare truthful listing copy, assets, and files'),
        _BoxSpec('price_route', 'Approve price and payment route',
            owner: KaiDeliveryBoxOwner.sponsor, risk: KaiDeliveryRisk.costly),
        _BoxSpec('package_review', 'Review the exact customer package'),
      ],
      5: [
        _BoxSpec('release_packet',
            'Assemble the immutable run-bound public release packet'),
        _BoxSpec('public_approval',
            'Approve the exact public offer and release terms',
            owner: KaiDeliveryBoxOwner.sponsor,
            risk: KaiDeliveryRisk.productDecision),
      ],
      6: [
        _BoxSpec('dispatch_preflight',
            'Prove the approved package is ready to publish'),
        _BoxSpec('public_dispatch',
            'Publish the approved offer and verify its live URL',
            owner: KaiDeliveryBoxOwner.sponsor,
            risk: KaiDeliveryRisk.liveExternal),
      ],
      7: [
        _BoxSpec('telemetry_contract',
            'Bind views, sales, delivery, and refunds to the prediction'),
        _BoxSpec('seven_day_observation', 'Observe at least seven real days',
            owner: KaiDeliveryBoxOwner.sponsor,
            risk: KaiDeliveryRisk.liveExternal),
      ],
      8: [
        _BoxSpec('settlement_observation',
            'Observe genuine customer funds settle in the bank',
            owner: KaiDeliveryBoxOwner.sponsor,
            risk: KaiDeliveryRisk.liveExternal),
        _BoxSpec('order_reconciliation',
            'Reconcile settlement reference to the order'),
        _BoxSpec('money_in_bank_acceptance',
            'Accept actual spendable banked revenue',
            owner: KaiDeliveryBoxOwner.sponsor,
            risk: KaiDeliveryRisk.productDecision),
      ],
    },
  };
}
