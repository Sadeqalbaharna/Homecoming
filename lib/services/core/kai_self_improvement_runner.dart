// KaiSelfImprovementRunner — bounded self-reliance, not feral autonomy.
//
// V1 deliberately does NOT edit files or run commands by itself. It chooses the
// next useful wound, opens a normal Kai job, and returns the proof gates that
// must be satisfied before the job can close. The hands already exist; this is
// the little adult leash that keeps them pointed at evidence instead of vibes.

import 'kai_job_service.dart';
import 'kai_noticed_service.dart';
import 'kai_project_service.dart';

typedef SelfImprovementNoticingLoader = Future<List<Noticed>> Function(String personaId);
typedef SelfImprovementProjectLoader = Future<List<KaiProject>> Function(String personaId);
typedef SelfImprovementJobStarter = Future<void> Function(
  String personaId,
  String goal, {
  String next,
});

class SelfImprovementBounds {
  final int maxJobs;
  final bool requiresApprovalForEdits;
  final bool requiresTests;
  final bool selfCheckLast;
  final bool stopOnFailure;
  final String mode;

  const SelfImprovementBounds({
    this.maxJobs = 1,
    this.requiresApprovalForEdits = true,
    this.requiresTests = true,
    this.selfCheckLast = true,
    this.stopOnFailure = true,
    this.mode = 'manual',
  });

  Map<String, dynamic> toMap() => {
        'mode': mode,
        'maxJobs': maxJobs,
        'requiresApprovalForEdits': requiresApprovalForEdits,
        'requiresTests': requiresTests,
        'selfCheckLast': selfCheckLast,
        'stopOnFailure': stopOnFailure,
      };
}

class SelfImprovementCandidate {
  final String id;
  final String title;
  final String source;
  final int priority;
  final String firstStep;
  final List<String> proofGates;

  const SelfImprovementCandidate({
    required this.id,
    required this.title,
    required this.source,
    required this.priority,
    required this.firstStep,
    required this.proofGates,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'source': source,
        'priority': priority,
        'firstStep': firstStep,
        'proofGates': proofGates,
      };
}

class SelfImprovementRunPlan {
  final SelfImprovementBounds bounds;
  final SelfImprovementCandidate? selected;
  final List<SelfImprovementCandidate> candidates;

  const SelfImprovementRunPlan({
    required this.bounds,
    required this.candidates,
    required this.selected,
  });

  bool get hasWork => selected != null;

  Map<String, dynamic> toMap() => {
        'bounds': bounds.toMap(),
        'selected': selected?.toMap(),
        'candidates': candidates.map((c) => c.toMap()).toList(),
      };
}

class KaiSelfImprovementRunner {
  KaiSelfImprovementRunner._();
  static final KaiSelfImprovementRunner instance = KaiSelfImprovementRunner._();

  static const defaultProofGates = <String>[
    'Investigate the real code/state before editing.',
    'Make the smallest reversible change.',
    'Add or update focused regression coverage when behaviour changes.',
    'Run the focused test or explain why none applies.',
    'Run full verification when the slice touches shared infrastructure.',
    'Run self_check last, after the final edit.',
    'Record evidence in the relevant project/checklist/noticing/job trail.',
  ];

  SelfImprovementRunPlan plan({
    required List<Noticed> noticings,
    required List<KaiProject> projects,
    SelfImprovementBounds bounds = const SelfImprovementBounds(),
  }) {
    final candidates = <SelfImprovementCandidate>[
      ..._fromNoticings(noticings),
      ..._fromChecklistGaps(projects),
    ]..sort((a, b) {
        final byPriority = b.priority.compareTo(a.priority);
        if (byPriority != 0) return byPriority;
        return a.title.compareTo(b.title);
      });

    return SelfImprovementRunPlan(
      bounds: bounds,
      candidates: candidates,
      selected: candidates.isEmpty ? null : candidates.first,
    );
  }

  Future<String> run({
    required String personaId,
    SelfImprovementBounds bounds = const SelfImprovementBounds(),
    SelfImprovementNoticingLoader? loadNoticings,
    SelfImprovementProjectLoader? loadProjects,
    SelfImprovementJobStarter? startJob,
  }) async {
    final noticings = await (loadNoticings ?? _loadOpenNoticings)(personaId);
    final projects = await (loadProjects ?? _loadCoreProjects)(personaId);
    final p = plan(noticings: noticings, projects: projects, bounds: bounds);

    if (!p.hasWork) {
      return 'Self-improvement loop found no safe queued job. Bounds: '
          '${bounds.toMap()}';
    }

    final c = p.selected!;
    await (startJob ?? KaiJobService.instance.start)(
      personaId,
      'Self-improvement loop: ${c.title}',
      next: c.firstStep,
    );

    final b = StringBuffer()
      ..writeln('Self-improvement loop started 1 bounded job.')
      ..writeln('Selected: ${c.title}')
      ..writeln('Source: ${c.source}')
      ..writeln('Priority: ${c.priority}')
      ..writeln('First step: ${c.firstStep}')
      ..writeln('Bounds: ${bounds.toMap()}')
      ..writeln('Proof gates:');
    for (final gate in c.proofGates) {
      b.writeln('- $gate');
    }
    if (p.candidates.length > 1) {
      b.writeln('Other queued candidates: ${p.candidates.length - 1}');
    }
    return b.toString().trimRight();
  }

  Future<List<Noticed>> _loadOpenNoticings(String personaId) =>
      KaiNoticedService.instance.open(personaId);

  Future<List<KaiProject>> _loadCoreProjects(String personaId) async {
    await KaiProjectService.instance.ensureSmarterProject(personaId);
    await KaiProjectService.instance.ensureSentienceProject(personaId);
    return [
      await KaiProjectService.instance.get(personaId, KaiProjectService.smarterId),
      await KaiProjectService.instance.get(personaId, KaiProjectService.sentienceId),
    ].nonNulls.toList();
  }

  Iterable<SelfImprovementCandidate> _fromNoticings(List<Noticed> noticings) {
    return noticings.map((n) {
      final text = n.text.trim();
      final lower = text.toLowerCase();
      var priority = 60 + n.carried.clamp(0, 25);
      if (_blocksHands(lower)) priority += 35;
      if (_mentionsFailure(lower)) priority += 25;
      if (_mentionsLiveProof(lower)) priority += 20;

      return SelfImprovementCandidate(
        id: 'noticed:${n.id}',
        title: text,
        source: n.context.isEmpty ? 'noticed' : 'noticed:${n.context}',
        priority: priority.clamp(0, 100),
        firstStep: 'Inspect the code/state behind this noticing and confirm the wound is still real.',
        proofGates: defaultProofGates,
      );
    });
  }

  Iterable<SelfImprovementCandidate> _fromChecklistGaps(List<KaiProject> projects) sync* {
    for (final project in projects) {
      for (final layer in project.layers) {
        if (layer.checklist.isEmpty) continue;
        for (final item in layer.checklist) {
          final status = layer.checklistStatus[item] ?? ChecklistStatus.pending;
          if (status == ChecklistStatus.trusted) continue;
          final itemLower = item.toLowerCase();
          var priority = project.id == KaiProjectService.sentienceId ? 55 : 45;
          priority += (100 - layer.honestProgress) ~/ 4;
          if (status == ChecklistStatus.pending) priority += 12;
          if (_blocksHands(itemLower)) priority += 25;
          if (_mentionsLiveProof(itemLower)) priority += 15;

          yield SelfImprovementCandidate(
            id: 'checklist:${project.id}:L${layer.n}:$item',
            title: '${project.name} L${layer.n}: $item',
            source: 'checklist:${status.label}',
            priority: priority.clamp(0, 100),
            firstStep: 'Find the code or trace that would move this checklist item from ${status.label} with evidence.',
            proofGates: defaultProofGates,
          );
        }
      }
    }
  }

  bool _blocksHands(String text) =>
      text.contains('tool') ||
      text.contains('schema') ||
      text.contains('bridge') ||
      text.contains('manifest') ||
      text.contains('hands') ||
      text.contains('blocked');

  bool _mentionsFailure(String text) =>
      text.contains('fail') ||
      text.contains('error') ||
      text.contains('broken') ||
      text.contains('warning') ||
      text.contains('regress');

  bool _mentionsLiveProof(String text) =>
      text.contains('live') || text.contains('proof') || text.contains('reload');
}
