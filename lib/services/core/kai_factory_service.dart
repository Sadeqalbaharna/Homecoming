// KaiFactoryService — persistence and the perimeter for factory mode.
//
// The gate logic lives in lib/logic/product_factory.dart (pure, provable). The
// scoring lives in lib/logic/product_scout.dart. This file is the part that
// touches the world: it stores runs, reads Sadeq's approval, and renders the
// current state into Kai's prompt so he knows where he is without being told.
//
// ── The one rule that shapes this whole file ────────────────────────────────
//
// THERE IS NO METHOD HERE THAT MINTS AN APPROVAL.
//
// `advance()` refuses to cross into `published` without a HumanApproval, so the
// only way that safety means anything is if Kai cannot manufacture one. So this
// service READS approvals and never writes them. Sadeq writes the approval node
// himself, from the UI. If a future edit adds a `writeApproval()` here, the
// perimeter is gone and the gate becomes decoration — which is exactly how
// "check with me first" directives have failed before.
//
// Stored at kai/{persona}/factory/current and kai/{persona}/factory/history.
library;

import 'dart:async';
import 'kai_db.dart';
import '../../logic/product_factory.dart';
import '../../logic/scout_calibration.dart';
import '../../logic/scout_learning.dart';

class KaiFactoryService {
  KaiFactoryService._();
  static final KaiFactoryService instance = KaiFactoryService._();

  String _persona = 'truekai';
  String get _root => 'kai/$_persona/factory';
  String get _currentPath => '$_root/current';
  String get _historyPath => '$_root/history';

  /// Sadeq's master switch, stored where he controls it — not a field Kai can
  /// flip mid-turn.
  String get _modePath => '$_root/mode_on';

  /// Where Sadeq writes approvals. READ-ONLY from this service, by design.
  String _approvalPath(String runId) => '$_root/approvals/$runId';

  // ── Reads ─────────────────────────────────────────────────────────────────

  Future<bool> isFactoryModeOn(String personaId) async {
    _persona = personaId;
    try {
      final snap = await KaiDb.instance.ref(_modePath).get();
      return snap.value == true;
    } catch (_) {
      return false; // fail closed — the safe direction
    }
  }

  /// Sadeq's master switch. Note what this does NOT do: it never grants
  /// permission to publish. Factory mode on means "he may work"; publishing
  /// still requires a per-run approval that only Sadeq writes.
  ///
  /// Lifecycle contract:
  /// * OFF stops and persists the current run.
  /// * ON resumes that stopped run if one exists.
  /// * App startup must call [parkRunAfterStartup] so a stale active run cannot
  ///   silently continue just because the old mode flag was true.
  Future<void> setFactoryMode(String personaId, bool on) async {
    _persona = personaId;
    try {
      if (on) {
        await KaiDb.instance.ref(_modePath).set(true);
        final run = await _rawCurrent();
        if (run == null) {
          await _write(FactoryRun(
            id: 'run-${DateTime.now().millisecondsSinceEpoch}',
            factoryModeOn: true,
          ));
        } else if (run.isStopped) {
          await _write(run.copyWith(
            factoryModeOn: true,
            stoppedAt: null,
            stoppedReason: null,
          ));
        } else if (!run.factoryModeOn) {
          await _write(run.copyWith(factoryModeOn: true));
        }
      } else {
        final run = await _rawCurrent();
        if (run != null && !run.isStopped) {
          await _write(run.copyWith(
            factoryModeOn: false,
            stoppedAt: DateTime.now().millisecondsSinceEpoch,
            stoppedReason: 'factory mode toggled off',
          ));
        }
        await KaiDb.instance.ref(_modePath).set(false);
      }
      print('🏭 [Factory] mode ${on ? 'ON' : 'OFF'}');
    } catch (e) {
      print('❌ [Factory] could not set mode: $e');
    }
  }

  /// Called once on app boot/reload. Saved state remains, but no run is allowed
  /// to keep executing across a restart unless Sadeq actively starts factory
  /// mode again.
  Future<void> parkRunAfterStartup(String personaId) async {
    _persona = personaId;
    try {
      final run = await _rawCurrent();
      if (run != null && !run.isStopped) {
        await _write(run.copyWith(
          factoryModeOn: false,
          stoppedAt: DateTime.now().millisecondsSinceEpoch,
          stoppedReason: 'app restarted before factory mode was re-enabled',
        ));
      }
      await KaiDb.instance.ref(_modePath).set(false);
    } catch (e) {
      print('❌ [Factory] could not park run after startup: $e');
    }
  }

  Future<FactoryRun?> current(String personaId) async {
    _persona = personaId;
    try {
      final run = await _rawCurrent();
      if (run == null) return null;
      final on = await isFactoryModeOn(personaId);
      return run.copyWith(factoryModeOn: on && !run.isStopped);
    } catch (_) {
      return null;
    }
  }

  /// Read Sadeq's approval for a run, if he has granted one.
  Future<HumanApproval?> approvalFor(String personaId, String runId) async {
    _persona = personaId;
    try {
      final snap = await KaiDb.instance.ref(_approvalPath(runId)).get();
      final v = snap.value;
      if (v is! Map) return null;
      final by = (v['approvedBy'] as String?)?.trim() ?? '';
      final at = (v['approvedAt'] as num?)?.toInt() ?? 0;
      final rid = (v['runId'] as String?)?.trim() ?? '';
      if (by.isEmpty || at <= 0 || rid.isEmpty) return null;
      return HumanApproval(
        approvedBy: by,
        approvedAt: at,
        runId: rid,
        approvedPrice: v['approvedPrice'] as num?,
      );
    } catch (_) {
      return null;
    }
  }

  // ── Writes (runs and evidence only — never approvals) ─────────────────────

  Future<FactoryRun> startRun(String personaId, {required String id}) async {
    _persona = personaId;
    final existing = await _rawCurrent();
    await KaiDb.instance.ref(_modePath).set(true);
    if (existing != null) {
      final resumed = existing.copyWith(
        factoryModeOn: true,
        stoppedAt: null,
        stoppedReason: null,
      );
      await _write(resumed);
      return resumed;
    }
    final run = FactoryRun(id: id, factoryModeOn: true);
    await _write(run);
    return run;
  }

  /// Record evidence as it is EARNED. Callers pass facts (a path, a passing
  /// test run, a live URL) — never "I finished this stage".
  Future<FactoryRun?> recordEvidence(
    String personaId, {
    bool? hasSurvivingCandidate,
    bool? specComplete,
    String? artifactPath,
    bool? testsPassed,
    bool? buildPassed,
    bool? listingPrepared,
    String? liveUrl,
    int? views,
    int? sales,
    int? observedDays,
    Map<String, int>? predictedScores,
  }) async {
    final run = await current(personaId);
    if (run == null) return null;
    final e = run.evidence;
    // Predictions are write-ONCE. Once a run has recorded what it expected,
    // that number is frozen — otherwise a run that sold badly could quietly
    // revise what it "predicted" and calibration would learn nothing.
    final frozenPrediction = e.predictedScores ?? predictedScores;
    final merged = RunEvidence(
      predictedScores: frozenPrediction,
      hasSurvivingCandidate: hasSurvivingCandidate ?? e.hasSurvivingCandidate,
      specComplete: specComplete ?? e.specComplete,
      artifactPath: artifactPath ?? e.artifactPath,
      testsPassed: testsPassed ?? e.testsPassed,
      buildPassed: buildPassed ?? e.buildPassed,
      listingPrepared: listingPrepared ?? e.listingPrepared,
      liveUrl: liveUrl ?? e.liveUrl,
      views: views ?? e.views,
      sales: sales ?? e.sales,
      observedDays: observedDays ?? e.observedDays,
    );
    final updated = run.copyWith(evidence: merged);
    await _write(updated);
    return updated;
  }

  /// Try to advance. Pulls Sadeq's approval from the DB rather than accepting
  /// one from the caller, so a tool argument can never stand in for consent.
  Future<AdvanceResult> tryAdvance(String personaId) async {
    final run = await current(personaId);
    if (run == null) {
      return const AdvanceResult.refused(
          GateRefusal(FactoryStage.scouting, 'no active run — start one first'));
    }
    final approval = await approvalFor(personaId, run.id);
    final result = advance(run, approval: approval);
    if (result.advanced) {
      await _write(result.run!);
      if (result.run!.stage == FactoryStage.learned) {
        await _archive(result.run!);
      }
    }
    return result;
  }

  /// Close a run that found nothing.
  ///
  /// Archived rather than deleted: the record of ground already covered is what
  /// stops the next run re-walking the same dead markets. A scout with no
  /// memory of its failures repeats them at full price.
  Future<void> abandonRun(String personaId, {required String reason}) async {
    final run = await current(personaId);
    if (run == null) return;
    try {
      await KaiDb.instance.ref('$_historyPath/${run.id}').set({
        ..._runToMap(run),
        'abandoned': true,
        'reason': reason,
        'closedAt': DateTime.now().millisecondsSinceEpoch,
      });
      await KaiDb.instance.ref(_currentPath).remove();
    } catch (_) {}
  }

  Future<void> restartRun(String personaId) async {
    final run = await current(personaId);
    if (run == null) return;
    await _write(restart(run));
  }

  // ── Prompt surface ────────────────────────────────────────────────────────

  /// What he should know about the factory without asking. Silent when there's
  /// no run — an idle factory shouldn't take up room in his head.
  Future<String> promptBlock(String personaId) async {
    try {
      final on = await isFactoryModeOn(personaId);
      final run = await current(personaId);
      if (!on && run == null) return '';
      if (!on) {
        return '\n=== FACTORY ===\nFactory mode is OFF. Run "${run!.id}" is '
            'parked at ${run.stage.name}. Nothing advances until Sadeq turns it on.';
      }
      if (run == null) {
        return '\n=== FACTORY ===\nFactory mode is ON, no active run. '
            'I can start one by scouting for a gap.';
      }
      final b = StringBuffer('\n=== FACTORY ===\n');
      b.write('Run "${run.id}" is at ${run.stage.name}.');
      final probe = advance(run, approval: await approvalFor(personaId, run.id));
      if (probe.advanced) {
        b.write(' Ready to move to ${probe.run!.stage.name}.');
      } else if (probe.refusal != null) {
        b.write(' Next gate is blocked — ${probe.refusal!.reason}');
      }
      return b.toString();
    } catch (_) {
      return '';
    }
  }

  // ── Internals ─────────────────────────────────────────────────────────────

  Future<void> _write(FactoryRun run) async {
    try {
      await KaiDb.instance.ref(_currentPath).set(_runToMap(run));
    } catch (_) {/* never let bookkeeping break a turn */}
  }

  Future<FactoryRun?> _rawCurrent() async {
    final snap = await KaiDb.instance.ref(_currentPath).get();
    final v = snap.value;
    if (v is! Map) return null;
    return _runFromMap(v);
  }

  Future<void> _archive(FactoryRun run) async {
    try {
      await KaiDb.instance.ref('$_historyPath/${run.id}').set(_runToMap(run));
    } catch (_) {}
  }

  Map<String, dynamic> _runToMap(FactoryRun r) => {
        'id': r.id,
        'stage': r.stage.name,
        'factoryModeOn': r.factoryModeOn,
        if (r.stoppedAt != null) 'stoppedAt': r.stoppedAt,
        if (r.stoppedReason != null) 'stoppedReason': r.stoppedReason,
        'evidence': {
          'hasSurvivingCandidate': r.evidence.hasSurvivingCandidate,
          'specComplete': r.evidence.specComplete,
          if (r.evidence.artifactPath != null) 'artifactPath': r.evidence.artifactPath,
          'testsPassed': r.evidence.testsPassed,
          'buildPassed': r.evidence.buildPassed,
          'listingPrepared': r.evidence.listingPrepared,
          if (r.evidence.liveUrl != null) 'liveUrl': r.evidence.liveUrl,
          if (r.evidence.views != null) 'views': r.evidence.views,
          if (r.evidence.sales != null) 'sales': r.evidence.sales,
          'observedDays': r.evidence.observedDays,
          if (r.evidence.predictedScores != null)
            'predictedScores': r.evidence.predictedScores,
        },
      };

  /// Every archived run, for calibration. Only runs that actually reached the
  /// end carry usable lessons.
  Future<List<Outcome>> history(String personaId) async {
    _persona = personaId;
    try {
      final snap = await KaiDb.instance.ref(_historyPath).get();
      final v = snap.value;
      if (v is! Map) return const [];
      final out = <Outcome>[];
      v.forEach((key, val) {
        if (val is! Map) return;
        final em = val['evidence'];
        if (em is! Map) return;
        final pred = em['predictedScores'];
        if (pred is! Map) return; // no prediction = nothing to grade
        final scores = <String, int>{};
        pred.forEach((k, pv) {
          final n = (pv as num?)?.toInt();
          if (n != null) scores[k.toString()] = n;
        });
        if (scores.isEmpty) return;
        out.add(Outcome(
          runId: (val['id'] as String?) ?? key.toString(),
          predicted: scores,
          views: (em['views'] as num?)?.toInt() ?? 0,
          sales: (em['sales'] as num?)?.toInt() ?? 0,
          observedDays: (em['observedDays'] as num?)?.toInt() ?? 0,
        ));
      });
      return out;
    } catch (_) {
      return const [];
    }
  }

  /// Grade the scout's past predictions against what the market actually did.
  Future<Calibration> calibration(String personaId) async =>
      calibrate(await history(personaId));

  // ── The learning policy: memory between attempts ──────────────────────────
  //
  // Without this the bandit is amnesiac and every pass starts from zero, which
  // is the exact failure mode Sadeq was worried about: expensive repetition
  // wearing the costume of learning. The arms live in RTDB so they survive the
  // app closing, and so a run stopped mid-search resumes knowing what it knew.

  String get _learnPath => '$_root/learning/markets';
  String get _learnLogPath => '$_root/learning/log';

  Future<List<MarketArm>> arms(String personaId) async {
    _persona = personaId;
    try {
      final snap = await KaiDb.instance.ref(_learnPath).get();
      final v = snap.value;
      if (v is! Map) return const [];
      final out = <MarketArm>[];
      v.forEach((k, val) {
        if (val is! Map) return;
        final kills = <KillCause, int>{};
        final km = val['kills'];
        if (km is Map) {
          km.forEach((ck, cv) {
            final cause = KillCause.values.firstWhere(
              (c) => c.name == ck.toString(),
              orElse: () => KillCause.other,
            );
            kills[cause] = (cv as num?)?.toInt() ?? 0;
          });
        }
        out.add(MarketArm(
          market: k.toString(),
          attempts: (val['attempts'] as num?)?.toInt() ?? 0,
          survivals: (val['survivals'] as num?)?.toInt() ?? 0,
          sales: (val['sales'] as num?)?.toInt() ?? 0,
          kills: kills,
        ));
      });
      return out;
    } catch (_) {
      return const [];
    }
  }

  /// Record one scouting attempt. This is the training example.
  Future<void> recordScoutAttempt(
    String personaId, {
    required String market,
    required bool survived,
    bool sold = false,
    KillCause? killedBy,
  }) async {
    _persona = personaId;
    final key = market.trim().toLowerCase().replaceAll(RegExp(r'[.#$/\[\]]'), '_');
    if (key.isEmpty) return;
    try {
      final existing = (await arms(personaId))
          .where((a) => a.market == key)
          .cast<MarketArm?>()
          .firstWhere((_) => true, orElse: () => null);
      final updated = (existing ?? MarketArm(market: key))
          .recordAttempt(survived: survived, sold: sold, killedBy: killedBy);
      await KaiDb.instance.ref('$_learnPath/$key').set({
        'attempts': updated.attempts,
        'survivals': updated.survivals,
        'sales': updated.sales,
        'kills': {
          for (final e in updated.kills.entries) e.key.name: e.value,
        },
      });
      await KaiDb.instance.ref(_learnLogPath).push().set({
        'market': key,
        'survived': survived,
        'ts': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (_) {}
  }

  /// The ordered attempt log, oldest first — used to measure convergence.
  Future<List<bool>> attemptLog(String personaId) async {
    _persona = personaId;
    try {
      final snap = await KaiDb.instance.ref(_learnLogPath).get();
      final v = snap.value;
      if (v is! Map) return const [];
      final entries = <MapEntry<int, bool>>[];
      v.forEach((_, val) {
        if (val is! Map) return;
        entries.add(MapEntry(
          (val['ts'] as num?)?.toInt() ?? 0,
          val['survived'] == true,
        ));
      });
      entries.sort((a, b) => a.key.compareTo(b.key));
      return entries.map((e) => e.value).toList();
    } catch (_) {
      return const [];
    }
  }

  /// What the policy currently recommends — injected into every factory pass so
  /// each attempt starts knowing what the last ones cost.
  Future<String> policyBlock(String personaId) async {
    try {
      final a = await arms(personaId);
      if (a.isEmpty) {
        return '\n=== SCOUT POLICY ===\nNo scouting history yet. Anything you '
            'try is pure exploration — pick a boring market and record the '
            'outcome with scout_record_attempt so the next pass is not blind.';
      }
      final ranked = rankMarkets(a);
      final order = checkOrder(a);
      final conv = measureConvergence(await attemptLog(personaId));

      final b = StringBuffer('\n=== SCOUT POLICY (learned, not guessed) ===\n');
      b.writeln('Try next, best first:');
      for (final c in ranked.take(5)) {
        b.writeln('  • ${c.market} — ${c.rationale}');
      }
      b.writeln('Check gates in this order (cheapest rejection first): '
          '${order.take(3).map((c) => c.name).join(' → ')}');
      final verdict = conv.verdict;
      if (verdict != null) b.writeln(verdict);
      b.writeln('Markets already scouted are NOT forbidden — a thin history '
          'still carries an exploration bonus. But do not re-run an identical '
          'search and expect a different answer.');
      return b.toString();
    } catch (_) {
      return '';
    }
  }

  FactoryRun? _runFromMap(Map v) {
    final id = (v['id'] as String?)?.trim() ?? '';
    if (id.isEmpty) return null;
    final stageName = (v['stage'] as String?)?.trim() ?? 'scouting';
    final stage = FactoryStage.values.firstWhere(
      (s) => s.name == stageName,
      orElse: () => FactoryStage.scouting,
    );
    final em = v['evidence'];
    final e = em is Map
        ? RunEvidence(
            hasSurvivingCandidate: em['hasSurvivingCandidate'] == true,
            specComplete: em['specComplete'] == true,
            artifactPath: em['artifactPath'] as String?,
            testsPassed: em['testsPassed'] == true,
            buildPassed: em['buildPassed'] == true,
            listingPrepared: em['listingPrepared'] == true,
            liveUrl: em['liveUrl'] as String?,
            views: (em['views'] as num?)?.toInt(),
            sales: (em['sales'] as num?)?.toInt(),
            observedDays: (em['observedDays'] as num?)?.toInt() ?? 0,
            predictedScores: () {
              final p = em['predictedScores'];
              if (p is! Map) return null;
              final s = <String, int>{};
              p.forEach((k, pv) {
                final n = (pv as num?)?.toInt();
                if (n != null) s[k.toString()] = n;
              });
              return s.isEmpty ? null : s;
            }(),
          )
        : const RunEvidence();
    return FactoryRun(
      id: id,
      stage: stage,
      evidence: e,
      factoryModeOn: v['factoryModeOn'] == true,
      stoppedAt: (v['stoppedAt'] as num?)?.toInt(),
      stoppedReason: v['stoppedReason'] as String?,
    );
  }
}
