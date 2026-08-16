import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/logic/product_factory.dart';
import 'package:homecoming_app/services/core/kai_project_service.dart';
import 'package:homecoming_app/widgets/kai_project_portfolio.dart';

/// A record exactly as it was written before the portfolio existed.
Map<String, Object?> _legacyRecord() => {
      'name': 'Kai Smarter Project',
      'why': 'Make me genuinely smarter.',
      'layers': [
        {
          'n': 1,
          'title': 'Reply Spine',
          'intent': 'Preserve the useful answer.',
          'progress': 100,
          'evidence': ['recoveredReply preserves the answer'],
          'state': 'usedLive',
        },
      ],
      'createdAt': 1,
    };

KaiProject _portfolioProject({
  required String id,
  required String name,
  String repositoryPath = '',
  int activePhase = 0,
  List<String> blockers = const [],
  ProjectProofState proof = ProjectProofState.unverified,
}) =>
    KaiProject(
      id: id,
      name: name,
      why: 'why',
      layers: const [],
      repositoryPath: repositoryPath,
      activePhase: activePhase,
      blockers: blockers,
      portfolioVisible: true,
      proofState: proof,
    );

void main() {
  group('backward compatibility', () {
    test('a record written before the portfolio still deserializes', () {
      final project = KaiProjectService.parseProject(
        'kai_smarter',
        _legacyRecord(),
      );

      expect(project, isNotNull);
      expect(project!.name, 'Kai Smarter Project');
      expect(project.layers.single.title, 'Reply Spine');

      // And it is simply not in the portfolio, rather than being broken by it.
      expect(project.portfolioVisible, isFalse);
      expect(project.activePhase, -1);
      expect(project.blockers, isEmpty);
      expect(project.sourceOfTruthPath, isEmpty);
      expect(project.governedAcceptedPhases, isEmpty);
      expect(project.evidencePhases, isEmpty);
      expect(project.latestAdvance, isEmpty);
      expect(
        project.proofState,
        ProjectProofState.unverified,
        reason: 'absent metadata means unproven, never assumed good',
      );
    });

    test('malformed or empty data yields nothing, not invented progress', () {
      expect(KaiProjectService.parseProject('x', null), isNull);
      expect(KaiProjectService.parseProject('x', 'not a map'), isNull);

      final empty = KaiProjectService.parseProject('x', <String, Object?>{});
      expect(empty!.layers, isEmpty);
      expect(empty.acceptedPhases, 0);
      expect(empty.proofState, ProjectProofState.unverified);
    });
  });

  group('portfolio filtering and ordering', () {
    test('the local workspace sorts first, then by name', () {
      final projects = [
        _portfolioProject(id: 'z', name: 'Zebra'),
        _portfolioProject(
          id: 'hoard',
          name: 'Hoard',
          repositoryPath: r'C:\code\Hoard',
        ),
        _portfolioProject(
          id: 'hc',
          name: 'Homecoming',
          repositoryPath: r'C:\code\homecoming_app',
        ),
      ];

      final sorted = KaiProjectService.sortPortfolio(
        projects,
        workspaceRoot: r'C:\code\homecoming_app',
      );
      expect(sorted.map((p) => p.id), ['hc', 'hoard', 'z']);
    });

    test('ordering is deterministic when nothing matches the workspace', () {
      final projects = [
        _portfolioProject(id: 'b', name: 'Beta'),
        _portfolioProject(id: 'a', name: 'Alpha'),
      ];

      expect(
        KaiProjectService.sortPortfolio(
          projects,
          workspaceRoot: null,
        ).map((p) => p.id),
        ['a', 'b'],
      );
      // Same answer regardless of input order.
      expect(
        KaiProjectService.sortPortfolio(
          projects.reversed.toList(),
        ).map((p) => p.id),
        ['a', 'b'],
      );
    });

    test('a subdirectory of a repository still matches it', () {
      final sorted = KaiProjectService.sortPortfolio([
        _portfolioProject(id: 'other', name: 'Alpha'),
        _portfolioProject(
          id: 'hc',
          name: 'Zebra',
          repositoryPath: r'C:\code\homecoming_app',
        ),
      ], workspaceRoot: r'C:\code\homecoming_app\lib\services');
      expect(sorted.first.id, 'hc');
    });

    test('a partial path prefix is not a match', () {
      // C:\code\homecoming_app_old must not count as being inside
      // C:\code\homecoming_app.
      final sorted = KaiProjectService.sortPortfolio([
        _portfolioProject(id: 'alpha', name: 'Alpha'),
        _portfolioProject(
          id: 'hc',
          name: 'Zebra',
          repositoryPath: r'C:\code\homecoming_app',
        ),
      ], workspaceRoot: r'C:\code\homecoming_app_old');
      expect(sorted.first.id, 'alpha', reason: 'no false workspace match');
    });
  });

  group('governed phase definitions', () {
    test('Homecoming has exactly the nine governed phases in order', () {
      final layers = KaiProjectService.homecomingPhasesForTest;
      expect(layers.length, 9);
      expect(layers.map((l) => l.n), [0, 1, 2, 3, 4, 5, 6, 7, 8]);
      expect(layers.map((l) => l.title), [
        'Baseline',
        'Embodiment Foundation',
        'Device Transport',
        'Central Attention',
        'Durable Continuity',
        'Capability Fabric',
        'Self-Improvement',
        'Always-On Deployment',
        'Northstar Acceptance',
      ]);
      // Every phase carries its exit gate, so a card can show what closes it.
      for (final layer in layers) {
        expect(layer.checklist, isNotEmpty, reason: 'phase ${layer.n}');
        expect(layer.intent, isNotEmpty);
      }
    });

    test('Hoard has exactly the six governed phases in order', () {
      final layers = KaiProjectService.hoardPhasesForTest;
      expect(layers.length, 6);
      expect(layers.map((l) => l.n), [0, 1, 2, 3, 4, 5]);
      expect(layers.map((l) => l.title), [
        'Authorization contract',
        'Pilot safety baseline',
        'Real venue close',
        'Verified savings pilot',
        'Repeatability',
        'Self-service and growth',
      ]);
      for (final layer in layers) {
        expect(layer.checklist, isNotEmpty, reason: 'phase ${layer.n}');
      }
    });

    test('Kingdom has exactly the six governed phases in order', () {
      final layers = KaiProjectService.kingdomPhasesForTest;
      expect(layers.length, 6);
      expect(layers.map((l) => l.n), [0, 1, 2, 3, 4, 5]);
      expect(layers.map((l) => l.title), [
        'Product and authority contract',
        'Ledger safety',
        'Trusted core loop',
        'Pilot readiness',
        'Tavern pilot',
        'Retention proof and scale',
      ]);
      for (final layer in layers) {
        expect(layer.checklist, isNotEmpty, reason: 'phase ${layer.n}');
        expect(layer.intent, isNotEmpty);
      }
    });

    test('Factory has nine commercial gates ending in money in bank', () {
      final layers = KaiProjectService.factoryPhasesForTest;
      expect(layers.length, 9);
      expect(layers.map((l) => l.n), [0, 1, 2, 3, 4, 5, 6, 7, 8]);
      expect(layers.map((l) => l.title), [
        'Signal Scan',
        'Blueprint',
        'Assembly',
        'QA Gate',
        'Packaging',
        'Approval',
        'Dispatch',
        'Telemetry',
        'Money in Bank',
      ]);
      expect(layers.last.intent.toLowerCase(), contains('banked revenue'));
      expect(
        layers.last.checklist.single.toLowerCase(),
        contains('bank account'),
      );
    });

    test('Factory advancement follows the real run stage', () {
      const awaitingApproval = FactoryRun(
        id: 'run-1',
        stage: FactoryStage.awaitingApproval,
      );
      expect(KaiProjectService.factoryAcceptedPhasesForRun(awaitingApproval), [
        0,
        1,
        2,
        3,
        4,
      ]);
      expect(
        KaiProjectService.factoryProofStateForRun(awaitingApproval),
        ProjectProofState.tested,
      );

      const banked = FactoryRun(
        id: 'run-1',
        stage: FactoryStage.learned,
        evidence: RunEvidence(
          bankedRevenue: 49,
          bankSettlementReference: 'settlement-1',
        ),
      );
      expect(KaiProjectService.factoryAcceptedPhasesForRun(banked), [
        0,
        1,
        2,
        3,
        4,
        5,
        6,
        7,
        8,
      ]);
      expect(
        KaiProjectService.factoryProofStateForRun(banked),
        ProjectProofState.verifiedLive,
      );
    });

    test(
      'governed acceptance and partial evidence match current decisions',
      () {
        final homecoming = KaiProjectService.homecomingBaselineForTest;
        expect(homecoming[0]![0], 100);
        for (var phase = 1; phase <= 8; phase++) {
          expect(
            homecoming[phase]![0],
            0,
            reason: 'phase $phase is not accepted by its governing document',
          );
        }

        expect(KaiProjectService.homecomingGovernedAcceptedPhasesForTest, [0]);
        expect(KaiProjectService.homecomingEvidencePhasesForTest, [3]);
        expect(KaiProjectService.hoardGovernedAcceptedPhasesForTest, [0]);
        expect(KaiProjectService.hoardBaselineForTest[0]![0], 100);
        expect(KaiProjectService.hoardBaselineForTest[1]![2], 'tested');
      },
    );

    test('tested attention work does not mark Central Attention live', () {
      // Briefs 013-015 advanced real reminder infrastructure, but the
      // coordinator and observed seven-day run are still open.
      final phase3 = KaiProjectService.homecomingBaselineForTest[3]!;
      expect(phase3[0], 0);
      expect(phase3[2], 'wired');
      expect((phase3[1] as String).toLowerCase(), contains('coordinator'));
      expect(KaiProjectService.homecomingEvidencePhasesForTest, contains(3));
    });

    test('Kingdom has no accepted phase and does not claim live proof', () {
      final kingdom = KaiProjectService.kingdomBaselineForTest;
      for (var phase = 0; phase <= 5; phase++) {
        expect(
          kingdom[phase]![0],
          0,
          reason: 'Kingdom phase $phase has no accepted exit-gate evidence',
        );
      }
      expect(kingdom[0]![2], 'wired');
      expect(
        (kingdom[0]![1] as String).toLowerCase(),
        contains('no accepted pilot target'),
      );
    });

    test('Factory accepts Signal Scan while Blueprint remains evidence-only',
        () {
      final scan = KaiProjectService.factoryBaselineForTest[0]!;
      final blueprint = KaiProjectService.factoryBaselineForTest[1]!;
      expect(scan[0], 100);
      expect(scan[2], 'trusted');
      expect((scan[1] as String), contains('FSC-LEGACY-YES-001-BP-IC-v3'));
      expect(blueprint[0], 0);
      expect(blueprint[2], 'tested');
      expect((blueprint[3] as String), contains('Assembly'));
      expect(KaiProjectService.factoryPacketAcceptedPhasesForTest, [0]);
      expect(KaiProjectService.factoryBlueprintEvidencePhasesForTest, [1]);
    });
  });

  group('honest defaults for a future project', () {
    test('no approved phases means UNVERIFIED and zero accepted', () {
      const fresh = KaiProject(
        id: 'future_thing',
        name: 'Future Thing',
        why: 'not yet governed',
        layers: [],
        portfolioVisible: true,
      );

      expect(fresh.proofState, ProjectProofState.unverified);
      expect(fresh.acceptedPhases, 0);
      expect(fresh.activePhaseLayer, isNull);
      expect(fresh.completion, 0);
    });

    test('acceptedPhases counts evidence, never layer count', () {
      const project = KaiProject(
        id: 'p',
        name: 'P',
        why: 'w',
        portfolioVisible: true,
        layers: [
          KaiLayer(n: 0, title: 'done', intent: 'i', progress: 100),
          KaiLayer(n: 1, title: 'active', intent: 'i', progress: 40),
          KaiLayer(n: 2, title: 'untouched', intent: 'i'),
        ],
      );

      expect(project.acceptedPhases, 1);
    });

    test('governed acceptance and partial evidence remain distinct', () {
      const project = KaiProject(
        id: 'p',
        name: 'P',
        why: 'w',
        portfolioVisible: true,
        governedAcceptedPhases: [0],
        evidencePhases: [1],
        layers: [
          KaiLayer(n: 0, title: 'accepted', intent: 'i'),
          KaiLayer(n: 1, title: 'advanced', intent: 'i'),
          KaiLayer(n: 2, title: 'future', intent: 'i'),
        ],
      );

      expect(project.acceptedPhases, 1);
      expect(project.isPhaseAccepted(project.layers[0]), isTrue);
      expect(project.phaseHasEvidence(project.layers[1]), isTrue);
      expect(project.isPhaseAccepted(project.layers[1]), isFalse);
    });
  });

  group('legacy trackers stay out of the rail but stay alive', () {
    test('the two fixed project ids are still addressable', () {
      // Their data, services, tools and prompt context are unchanged; they are
      // only unmounted from the portfolio.
      expect(KaiProjectService.smarterId, 'kai_smarter');
      expect(KaiProjectService.sentienceId, 'sentience_ladder');
      expect(KaiProjectService.homecomingId, 'homecoming_northstar');
      expect(KaiProjectService.hoardId, 'hoard_northstar');
      expect(KaiProjectService.kingdomId, 'kingdom_northstar');
      expect(KaiProjectService.factoryId, 'factory_northstar');
    });
  });

  group('project sector hit mapping', () {
    const size = Size.square(320);
    const center = Offset(160, 160);
    const phaseCounts = [9, 6, 6];

    test('top project maps to its exact radial phase band', () {
      // Geometry uses radii 43.2..123.2. Homecoming has nine equal bands;
      // this point is centered in its second band.
      final hit = projectSectorHitTest(
        size: size,
        position: center + const Offset(0, -56.5),
        phaseCounts: phaseCounts,
      );
      expect(hit, const ProjectSectorHit(0, 1));
    });

    test('lower-right and lower-left sectors stay independent', () {
      Offset polar(double radius, double angle) =>
          center + Offset(math.cos(angle), math.sin(angle)) * radius;

      final kingdom = projectSectorHitTest(
        size: size,
        position: polar(76.5, math.pi / 6),
        phaseCounts: phaseCounts,
      );
      final hoard = projectSectorHitTest(
        size: size,
        position: polar(103.0, math.pi * 5 / 6),
        phaseCounts: phaseCounts,
      );

      expect(kingdom, const ProjectSectorHit(1, 2));
      expect(hoard, const ProjectSectorHit(2, 4));
    });

    test('core and project-name rail are not reveal targets', () {
      expect(
        projectSectorHitTest(
          size: size,
          position: center,
          phaseCounts: phaseCounts,
        ),
        isNull,
      );
      expect(
        projectSectorHitTest(
          size: size,
          position: center + const Offset(0, -146),
          phaseCounts: phaseCounts,
        ),
        isNull,
      );
    });
  });
}
