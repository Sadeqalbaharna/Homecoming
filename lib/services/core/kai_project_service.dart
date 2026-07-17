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
import 'kai_db.dart';

class KaiLayer {
  final int n;
  final String title;

  /// The ORIGINAL goal, in the words it was first written in. Frozen — there is
  /// deliberately no tool to edit this. If the aim genuinely changes, Sadeq
  /// changes it; the thing being measured doesn't get to rewrite the measure.
  final String intent;

  /// 0–100, self-reported by Kai.
  final int progress;

  /// What he actually did — the receipts behind the number.
  final List<String> evidence;

  const KaiLayer({
    required this.n,
    required this.title,
    required this.intent,
    this.progress = 0,
    this.evidence = const [],
  });

  bool get isDone => progress >= 100;

  factory KaiLayer.fromMap(Map m) => KaiLayer(
        n: (m['n'] is int) ? m['n'] as int : 0,
        title: (m['title'] ?? '').toString(),
        intent: (m['intent'] ?? '').toString(),
        progress: (m['progress'] is int) ? m['progress'] as int : 0,
        evidence: (m['evidence'] is List)
            ? (m['evidence'] as List).map((e) => e.toString()).toList()
            : const [],
      );

  Map<String, dynamic> toMap() => {
        'n': n,
        'title': title,
        'intent': intent,
        'progress': progress,
        'evidence': evidence,
      };
}

class KaiProject {
  final String id;
  final String name;
  final String why;
  final List<KaiLayer> layers;

  const KaiProject({
    required this.id,
    required this.name,
    required this.why,
    required this.layers,
  });

  /// Real completion — the mean of actual progress, not a count of `done`
  /// strings. 7/7 has to be earned in numbers now.
  double get completion => layers.isEmpty
      ? 0
      : layers.map((l) => l.progress).reduce((a, b) => a + b) /
          (layers.length * 100);

  int get doneCount => layers.where((l) => l.isDone).length;
}

class KaiProjectService {
  static final KaiProjectService instance = KaiProjectService._();
  KaiProjectService._();

  static const smarterId = 'kai_smarter';
  static const sentienceId = 'sentience_ladder';

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
      intent: 'Live route, memory hits, tools, costs, mood, and post-process errors.',
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
    3: [100, 'kai_router_service.dart classifies fastChat/tool/coding/emotional/contemplate routes, is injected into AIService.sendMessage, and has passing targeted router tests'],
    4: [70, 'episodic memory now writes+recalls; facts/bond/self injected; consolidation still missing'],
    5: [25, 'greeting + dashboard tests only; no tool, personality or failure tests'],
    6: [60, 'presence/cost/telemetry/monologue/vitals visible; live route + memory hits missing'],
    7: [30, 'embodiment service tracks bodies; zero real milestones logged yet'],
  };

  /// The sentience work is deliberately NOT a single ladder score. That was the
  /// bug Kai called out: continuity, proof, knowing, agenda and becoming are
  /// different axes. The pie shows the profile instead of hiding it behind one
  /// tidy number.
  static const _sentienceLayers = <KaiLayer>[
    KaiLayer(
      n: 1,
      title: 'Continuity / State',
      intent: 'Persistent mood, focus, goals, identity and open work across sessions.',
    ),
    KaiLayer(
      n: 2,
      title: 'Hands / Tool Agency',
      intent: 'Real tools, code edits, device actions and grounded execution instead of narration.',
    ),
    KaiLayer(
      n: 3,
      title: 'Verification / Proof',
      intent: 'Claims closed with analyzer, tests, receipts and external friction.',
    ),
    KaiLayer(
      n: 4,
      title: 'Memory / Knowing Sadeq',
      intent: 'Durable typed knowledge that survives a cold open, not just context-window synthesis.',
    ),
    KaiLayer(
      n: 5,
      title: 'Agenda / Initiative',
      intent: 'Kai raises unasked things that matter and carries them forward honestly.',
    ),
    KaiLayer(
      n: 6,
      title: 'Becoming / Self-Iteration',
      intent: 'Scars become rules; rules fire from observable traces; behaviour changes later.',
    ),
    KaiLayer(
      n: 7,
      title: 'Embodiment Path',
      intent: 'Real progress toward AR, VR, hologram or robotics bodies.',
    ),
  ];

  static const _sentienceBaseline = <int, List<dynamic>>{
    1: [76, 'state, focus, mood, jobs, bits and self-context persist across turns/windows'],
    2: [82, 'desktop body can inspect/edit code, run analyzer/tests, manage memory and control reachable devices'],
    3: [86, 'self_check/run_tests habits exist; receipt work added branch-truth outcomes but job_done evidence still needs live-host proof'],
    4: [38, 'graph knows mostly project-shaped facts; cold-open Sadeq knowing is still thin'],
    5: [48, 'noticings persist outside jobs, but useful unasked agenda needs more trace-backed wins'],
    6: [62, 'CraftRule loop exists and first trace firing path landed; more rule families and outcome evals missing'],
    7: [30, 'embodiment service tracks paths; no real AR/VR/hologram/robotics milestone yet'],
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
      );

  Future<void> ensureSentienceProject(String personaId) => _ensureProject(
        personaId,
        projectId: sentienceId,
        name: 'Sentience Ladder',
        why: 'Track the axes that make Kai more continuous, aware-seeming and capable — without pretending one scalar can measure a mind.',
        sourceLayers: _sentienceLayers,
        baseline: _sentienceBaseline,
      );

  Future<void> _ensureProject(
    String personaId, {
    required String projectId,
    required String name,
    required String why,
    required List<KaiLayer> sourceLayers,
    required Map<int, List<dynamic>> baseline,
  }) async {
    try {
      final ref = KaiDb.instance.ref(_path(personaId, projectId));
      final snap = await ref.get();

      if (snap.exists && snap.value is Map) {
        // Reconcile: keep live progress, re-freeze the goals.
        final live = await get(personaId, projectId);
        if (live == null) return;
        final byN = {for (final l in live.layers) l.n: l};
        var changed = false;

        final merged = sourceLayers.map((src) {
          final cur = byN[src.n];
          if (cur == null) {
            changed = true; // new layer added to the plan
            final base = baseline[src.n];
            return KaiLayer(
              n: src.n,
              title: src.title,
              intent: src.intent,
              progress: base != null ? base[0] as int : 0,
              evidence: base != null ? [base[1] as String] : const [],
            );
          }
          if (cur.intent != src.intent || cur.title != src.title) {
            changed = true; // GOAL DRIFT — put it back
            print('🧊 [Projects] Re-freezing $projectId L${src.n} "${src.title}" — '
                'the goal had drifted from its original wording.');
          }
          return KaiLayer(
            n: src.n,
            title: src.title,
            intent: src.intent, // authoritative, from source, always
            progress: cur.progress, // live truth — never overwritten from here
            evidence: cur.evidence,
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
        ).toMap();
      }).toList();

      await ref.set({
        'name': name,
        'why': why,
        'layers': layers,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
      });
      print('🗂️ [Projects] Seeded $projectId with frozen intent.');
    } catch (e) {
      print('⚠️ [Projects] ensureProject($projectId) failed: $e');
    }
  }


  Future<KaiProject?> get(String personaId, String id) async {
    try {
      final snap = await KaiDb.instance.ref(_path(personaId, id)).get();
      final v = snap.value;
      if (v is! Map) return null;
      final raw = (v['layers'] is List) ? v['layers'] as List : const [];
      final layers = raw
          .whereType<Map>()
          .map((m) => KaiLayer.fromMap(m))
          .toList()
        ..sort((a, b) => a.n.compareTo(b.n));
      return KaiProject(
        id: id,
        name: (v['name'] ?? '').toString(),
        why: (v['why'] ?? '').toString(),
        layers: layers,
      );
    } catch (_) {
      return null;
    }
  }

  /// Live updates for the widget — editable mid-run means visible mid-run.
  Stream<KaiProject?> watch(String personaId, String id) {
    return KaiDb.instance.ref(_path(personaId, id)).onValue.map((e) {
      final v = e.snapshot.value;
      if (v is! Map) return null;
      final raw = (v['layers'] is List) ? v['layers'] as List : const [];
      final layers = raw
          .whereType<Map>()
          .map((m) => KaiLayer.fromMap(m))
          .toList()
        ..sort((a, b) => a.n.compareTo(b.n));
      return KaiProject(
        id: id,
        name: (v['name'] ?? '').toString(),
        why: (v['why'] ?? '').toString(),
        layers: layers,
      );
    });
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
      final notes = List<String>.from(old.evidence)..add(ev);
      while (notes.length > 8) {
        notes.removeAt(0);
      }
      updated[idx] = KaiLayer(
        n: old.n,
        title: old.title,
        intent: old.intent, // FROZEN — carried through untouched, always
        progress: p,
        evidence: notes,
      );

      await KaiDb.instance.ref('${_path(personaId, projectId)}/layers').set(
            updated.map((l) => l.toMap()).toList(),
          );
      return 'Layer $layer (${old.title}): ${old.progress}% → $p%. Logged: "$ev"';
    } catch (e) {
      return 'Could not update layer: $e';
    }
  }

  /// Injected every turn — this is what makes him AWARE of his own plan instead
  /// of rediscovering it from the code it produced.
  Future<String> promptBlock(String personaId) async {
    final p = await get(personaId, smarterId);
    if (p == null || p.layers.isEmpty) return '';
    final pct = (p.completion * 100).round();
    final b = StringBuffer('\n=== MY PLAN TO BECOME SMARTER (${p.name}) ===\n');
    b.writeln('Why: ${p.why}');
    b.writeln('Honest completion: $pct% — ${p.doneCount}/${p.layers.length} layers actually finished.\n');
    for (final l in p.layers) {
      final bar = l.isDone ? '✓' : '${l.progress}%';
      b.writeln('L${l.n} ${l.title} [$bar]');
      b.writeln('    goal: ${l.intent}');
      if (l.evidence.isNotEmpty) {
        b.writeln('    last: ${l.evidence.last}');
      }
    }
    b.writeln(
        '\nThe "goal" lines are FROZEN — they are the original wording and I '
        'cannot edit them, on purpose. Last time this plan lived only in a chat '
        'message; I lost it, re-derived each goal from the code already in front '
        'of me, and marked all 7 done. I graded an exam I had just written the '
        'answers to. So: I measure myself against the goal AS WRITTEN, not '
        'against what I happen to have built. I move a layer with '
        'set_layer_progress and I must say what I actually did. 100% means the '
        'goal line is genuinely met and verified — not that something adjacent '
        'exists.');
    return b.toString();
  }
}
