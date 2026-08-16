/// KaiLedgerRunner — the last mile: gives the pipeline real hands and runs it.
///
/// `KaiLedgerPipeline` is pure policy with three seams — push the enrolment
/// list, drain the phone, append the rows. This supplies the real
/// implementations and drives it.
///
/// ── What runs where ─────────────────────────────────────────────────────────
///
/// Android only. The capture filter, the durable queue and the notification
/// listener all live on the phone; on desktop there is nothing to drain and
/// [runOnce] returns an idle result rather than pretending.
///
/// ── The enrolment list is the trust boundary and Dart owns it ───────────────
///
/// Sadeq types a sender id here; it is persisted here; and it is pushed to the
/// phone before every drain rather than once at startup. The phone's copy is
/// persisted too and could be stale from an older build — and re-pushing is
/// also how a REVOCATION reaches the capture filter. A revocation that only
/// applies at next launch is not a revocation.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../logic/ledger_ingest.dart';
import '../../logic/ledger_sources.dart';
import 'kai_ledger_pipeline.dart';

class KaiLedgerRunner {
  KaiLedgerRunner._();
  static final KaiLedgerRunner instance = KaiLedgerRunner._();

  static const _channel = MethodChannel('com.homecoming.app/kai_tools');
  static const _sourcesKey = 'kai_ledger_sources_v1';
  static const _rowsKey = 'kai_ledger_rows_v1';

  Timer? _timer;
  bool _busy = false;

  /// The last run, for the UI to show. Never carries message text.
  KaiLedgerRun? lastRun;

  // ── Enrolment ─────────────────────────────────────────────────────────────

  static Future<KaiLedgerSources> loadSources() async {
    final raw = (await SharedPreferences.getInstance()).getString(_sourcesKey);
    if (raw == null || raw.isEmpty) return KaiLedgerSources();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return KaiLedgerSources();
      return KaiLedgerSources.fromJson(decoded);
    } catch (_) {
      // A corrupt list must read as EMPTY, not as whatever survived parsing.
      // Empty captures nothing, which is loud; a half-read allowlist would be
      // a trust boundary nobody chose.
      return KaiLedgerSources();
    }
  }

  static Future<void> saveSources(KaiLedgerSources sources) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sourcesKey, jsonEncode(sources.toJson()));
  }

  static Future<void> enrolSms(String senderId, {String label = ''}) async {
    final sources = await loadSources();
    sources.add(KaiLedgerSource(
      channel: KaiLedgerChannel.sms,
      identifier: senderId.trim(),
      label: label,
    ));
    await saveSources(sources);
  }

  static Future<void> revokeSms(String senderId) async {
    final sources = await loadSources();
    sources.remove(KaiLedgerChannel.sms, senderId);
    await saveSources(sources);
  }

  // ── Platform hands ────────────────────────────────────────────────────────

  static Future<void> _pushSenders(List<String> senders) async {
    await _channel.invokeMethod<int>('setBankSenders', {'senders': senders});
  }

  static Future<List<Map<String, Object?>>> _drain() async {
    final raw = await _channel.invokeListMethod<Object?>('drainBankAlerts');
    return (raw ?? const [])
        .whereType<Map>()
        .map((m) => m.map((k, v) => MapEntry(k.toString(), v)))
        .toList(growable: false);
  }

  /// Appends rows to the ledger store.
  ///
  /// Read-modify-write in one step, because two drains overlapping would
  /// otherwise lose whichever wrote first. [_busy] already serialises runs;
  /// this is the second lock, since a lost row is invisible.
  static Future<void> _append(List<KaiLedgerRow> rows) async {
    if (rows.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getStringList(_rowsKey) ?? <String>[];
    for (final row in rows) {
      existing.add(jsonEncode({
        'date': row.candidate.date,
        'description': row.candidate.description,
        'amount': row.candidate.amount,
        'direction': row.candidate.direction.name,
        'source': row.candidate.source,
        'category': row.candidate.category,
        // `approved` is the confirmation flag. Pending rows are stored too —
        // dropping them would make an incomplete ledger look complete.
        'approved': row.approved,
        'fingerprint': row.candidate.fingerprint,
        if (row.balance != null) 'balanceAfter': row.balance!.balance,
        if (row.balance != null) 'account': row.balance!.account,
      }));
    }
    await prefs.setStringList(_rowsKey, existing);
  }

  /// Everything captured so far, newest last. Pending rows included.
  static Future<List<Map<String, dynamic>>> loadRows() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_rowsKey) ?? const <String>[];
    final out = <Map<String, dynamic>>[];
    for (final line in raw) {
      try {
        final decoded = jsonDecode(line);
        if (decoded is Map<String, dynamic>) out.add(decoded);
      } catch (_) {
        // One unreadable row must not lose the ledger.
      }
    }
    return out;
  }

  // ── Running ───────────────────────────────────────────────────────────────

  /// Auto-confirm rules. Empty until Sadeq writes one, on purpose: everything
  /// lands pending until a rule exists, which is the safe default and also the
  /// honest one for a system that has never seen a real transaction.
  static const rules = <KaiAutoConfirmRule>[];

  Future<KaiLedgerRun> runOnce() async {
    if (_busy) {
      return const KaiLedgerRun(
        drained: 0, appended: 0, autoApproved: 0, duplicates: 0,
        unreadable: 0, reasons: {'skipped_busy': 1},
      );
    }
    _busy = true;
    try {
      final pipeline = KaiLedgerPipeline(
        sources: await loadSources(),
        rules: rules,
        pushSenders: _pushSenders,
        drainAlerts: _drain,
        append: _append,
      );
      final run = await pipeline.runOnce();
      lastRun = run;
      return run;
    } finally {
      _busy = false;
    }
  }

  /// Start the drain loop.
  ///
  /// The listener captures at arrival into a durable queue, so this interval
  /// only decides how quickly a captured transaction REACHES the ledger — not
  /// whether it is captured. Two minutes is unremarkable for money and keeps
  /// the platform channel quiet.
  void start({Duration every = const Duration(minutes: 2)}) {
    if (_timer != null) return;
    unawaited(runOnce());
    _timer = Timer.periodic(every, (_) => unawaited(runOnce()));
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}
