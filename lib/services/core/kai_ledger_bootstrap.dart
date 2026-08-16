/// KaiLedgerBootstrap — the one place that starts the ledger pipeline.
///
/// Everything below it was built and tested in isolation and had no caller.
/// This is the caller: it loads the enrolment registry, pushes the filter to
/// the phone, drains the durable queue, and writes what comes back into the
/// cash ledger.
///
/// ── Seeding the registry ────────────────────────────────────────────────────
///
/// The default enrolment is `Alsalambank` and `Credimax` because Sadeq named
/// them. That is a recorded instruction, not a guess — the distinction that got
/// five invented Bahraini sender ids deleted earlier: a developer assuming a
/// trust boundary fails as silence, while writing down what the owner actually
/// said is the boundary working as designed.
///
/// It seeds ONCE. After that the stored registry wins, so removing a sender in
/// the app is not quietly undone on next launch — a revocation that a restart
/// reverses is not a revocation.
library;

import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../logic/capture_health.dart';
import '../../logic/ledger_ingest.dart';
import '../../logic/ledger_sources.dart';
import 'kai_ledger_pipeline.dart';

/// Sadeq's stated senders, applied on first run only.
const kKaiSeedLedgerSources = <KaiLedgerSource>[
  KaiLedgerSource(
    channel: KaiLedgerChannel.sms,
    identifier: 'Alsalambank',
    label: 'Al Salam Bank — account and signature card',
  ),
  KaiLedgerSource(
    channel: KaiLedgerChannel.sms,
    identifier: 'Credimax',
    label: 'CrediMax credit card',
  ),
];

class KaiLedgerBootstrap {
  KaiLedgerBootstrap({
    required this.invoke,
    required this.appendRows,
  });

  /// The platform channel, injected so every line here is testable without a
  /// phone. Returns null when the platform has no answer.
  final Future<Object?> Function(String method, [Map<String, Object?>? args])
      invoke;

  /// Writes rows into the cash ledger. Kept as a callback so this file does not
  /// depend on the 3,900-line card widget.
  final Future<void> Function(List<KaiLedgerRow> rows) appendRows;

  static const _sourcesKey = 'kai_ledger_sources_v1';
  static const _seededKey = 'kai_ledger_sources_seeded_v1';

  /// Load the registry, seeding Sadeq's stated senders exactly once.
  Future<KaiLedgerSources> loadSources() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_sourcesKey);
    if (raw != null) {
      try {
        return KaiLedgerSources.fromJson(
          (jsonDecode(raw) as List).cast<dynamic>(),
        );
      } catch (_) {
        // A corrupt registry must not silently become an empty one that reads
        // nothing, nor a seeded one that re-adds a sender Sadeq removed. Fail
        // to empty and let the health check report a pipe with no sources.
        return KaiLedgerSources();
      }
    }
    if (prefs.getBool(_seededKey) == true) return KaiLedgerSources();

    final seeded = KaiLedgerSources(kKaiSeedLedgerSources);
    await saveSources(seeded);
    await prefs.setBool(_seededKey, true);
    return seeded;
  }

  Future<void> saveSources(KaiLedgerSources sources) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sourcesKey, jsonEncode(sources.toJson()));
  }

  /// One pass: push the filter, drain, ingest, append.
  ///
  /// Safe to call on every app resume. The pipeline deduplicates, an empty
  /// queue is a no-op, and a platform that refuses reports a failure rather
  /// than an empty drain.
  Future<KaiLedgerRun> run({List<KaiAutoConfirmRule> rules = const []}) async {
    final sources = await loadSources();
    final pipeline = KaiLedgerPipeline(
      sources: sources,
      rules: rules,
      pushSenders: (senders) async =>
          invoke('setBankSenders', {'senders': senders}),
      drainAlerts: () async {
        final raw = await invoke('drainBankAlerts');
        if (raw is! List) return const [];
        return raw
            .whereType<Map>()
            .map((m) => m.map((k, v) => MapEntry(k.toString(), v)))
            .toList(growable: false);
      },
      append: appendRows,
    );
    return pipeline.runOnce();
  }

  /// Is the phone still listening, and what should be done if not?
  Future<KaiCaptureReport> checkHealth({
    DateTime? now,
    KaiCaptureMonitor monitor = const KaiCaptureMonitor(),
  }) async {
    final raw = await invoke('captureHealth');
    final map = raw is Map
        ? raw.map((k, v) => MapEntry(k.toString(), v))
        : const <String, Object?>{};

    final lastMillis = map['lastAnyNotification'];
    final health = monitor.evaluate(
      accessGranted: map['accessGranted'] == true,
      listenerConnected: map['listenerConnected'] == true,
      lastAnyNotification: lastMillis is num
          ? DateTime.fromMillisecondsSinceEpoch(lastMillis.toInt())
          : null,
      now: now ?? DateTime.now(),
      queued: (map['queued'] as num?)?.toInt() ?? 0,
    );

    if (health.ok || health.state == KaiCaptureState.neverStarted) {
      return KaiCaptureReport(health: health, repairs: const []);
    }

    // Only attempt repair when something is actually wrong. Rebinding a healthy
    // listener is churn, and churn in a recovery path is how a recovery path
    // becomes the fault.
    final repairRaw = await invoke('repairCapture');
    final repair = repairRaw is Map
        ? repairRaw.map((k, v) => MapEntry(k.toString(), v))
        : const <String, Object?>{};

    return KaiCaptureReport(
      health: health,
      repairs: kaiCaptureRepairs(
        accessGranted: repair['accessGranted'] == true,
        rebindRequested: repair['rebindRequested'] == true,
        batteryExempt: repair['batteryExempt'] as bool?,
        autoRevokeExempt: repair['autoRevokeExempt'] as bool?,
      ),
    );
  }
}

class KaiCaptureReport {
  const KaiCaptureReport({required this.health, required this.repairs});

  final KaiCaptureHealth health;
  final List<KaiCaptureRepair> repairs;

  bool get needsSadeq => repairs.any((r) => r != KaiCaptureRepair.rebindRequested);
}
