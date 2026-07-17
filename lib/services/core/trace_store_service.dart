// TraceStoreService — the dataset that was being thrown away.
//
// ── What was happening ───────────────────────────────────────────────────────
//
// brain_debug_service.dart:261, verbatim:
//
//     _history.add(_currentTrace!);
//     // Keep only last 10 traces
//     if (_history.length > 10) {
//       _history.removeAt(0);
//     }
//
// An in-memory list. Holds ten. Dies on app close.
//
// Every turn Kai takes produces the richest structured record of his cognition
// that exists anywhere — the input, every retrieval score, the mood vector, the
// route and its confidence, every tool call, iteration counts, per-phase
// timings, and the reply. All of it, printed to stdout and dropped.
//
// `BrainDebugTrace.toJson()` has existed this whole time at line 125 and has
// never had a caller. The serialiser was written and then not connected to
// anything — the same disease as the doorless screens, `toJson()` ignored by
// `_saveGraph`, the 20 EdgeTypes never written, the tests CI could run and Kai
// couldn't.
//
// And the consequence was not abstract. The only way anything got diagnosed on
// 2026-07-16 was Sadeq copy-pasting a terminal window into a chat at 4am. That
// was the data pipeline: a human with a mouse. Every conclusion drawn that night
// came through it, which is also why several of them were wrong.
//
// ── Why JSONL, append-only ───────────────────────────────────────────────────
//
// n will always be small — one person, a few dozen turns a day. You will never
// have statistics here. What works at small n is REPLAY: re-run history through
// a changed decision and diff the outcomes. That needs a census, not a sample,
// and it needs the record to be immutable.
//
// So: one file per day, one JSON object per line, appended, never rewritten.
// A row that's written is written. If a later version of this code disagrees
// with a row, the row wins — that's the entire point of having one.
//
// ── Kai gets read access and no write access ─────────────────────────────────
//
// Deliberate, and the reason is in his own repo. `_smartProjectCard` rendered
// "7 / 7 layers complete — FULL STACK ONLINE" while the truth was 3/7. That card
// wasn't lying exactly; it was a metric authored by the thing being measured.
//
// Every number that grades him has to come from something he cannot edit. This
// file is one of those things. There is no public write method that takes
// arbitrary content, and there never should be.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../brain_debug_service.dart';

class TraceStoreService {
  TraceStoreService._();
  static final TraceStoreService instance = TraceStoreService._();

  Directory? _dir;
  bool _failedOnce = false;

  /// Where the corpus lives. Outside the repo on purpose: it's data, not source,
  /// and it must never end up in a commit or be rewritten by a checkout.
  Future<Directory?> _traceDir() async {
    if (_dir != null) return _dir;
    if (_failedOnce) return null;
    try {
      final base = await getApplicationDocumentsDirectory();
      final d = Directory('${base.path}/kai_traces');
      if (!await d.exists()) await d.create(recursive: true);
      _dir = d;
      return d;
    } catch (e) {
      // Mobile/desktop path differences, permissions, a read-only volume — any
      // of it. Say so ONCE and then stay quiet: a warning printed on every turn
      // is a warning nobody reads.
      _failedOnce = true;
      print('⚠️ [TraceStore] Cannot open trace directory — traces will not be '
          'recorded this session: $e');
      return null;
    }
  }

  String _fileFor(DateTime t) =>
      '${t.year}-${t.month.toString().padLeft(2, '0')}-'
      '${t.day.toString().padLeft(2, '0')}.jsonl';

  /// Append one completed trace. Fire-and-forget — see [record].
  Future<void> _append(BrainDebugTrace trace) async {
    final d = await _traceDir();
    if (d == null) return;
    final f = File('${d.path}/${_fileFor(trace.startTime)}');

    // One line, no newlines inside. jsonEncode escapes them, but a trace whose
    // reply contains a literal \n would otherwise split into two rows and
    // silently corrupt every future replay — and it would look fine until the
    // day it mattered.
    final line = jsonEncode(trace.toJson());
    assert(!line.contains('\n'), 'JSONL row must be one line');

    await f.writeAsString('$line\n',
        mode: FileMode.append, flush: false);
  }

  /// Called by BrainDebugService when a trace completes.
  ///
  /// Never awaited by the reply path and never allowed to throw into it. A
  /// missed row is a hole in the dataset; a thrown row is a broken conversation.
  /// The dataset is not worth more than the person.
  void record(BrainDebugTrace trace) {
    unawaited(_append(trace).catchError((Object e) {
      print('⚠️ [TraceStore] Failed to record trace ${trace.id}: $e');
    }));
  }

  // ── Reading. This is what the replay harness and the scorecard use. ────────

  /// Every trace file, oldest first.
  Future<List<File>> files() async {
    final d = await _traceDir();
    if (d == null) return const [];
    try {
      final out = d
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.jsonl'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      return out;
    } catch (_) {
      return const [];
    }
  }

  /// Read the corpus back as decoded maps, oldest first.
  ///
  /// A single malformed row is SKIPPED, not fatal. These files are appended to
  /// by a process that can be killed mid-write, so a torn last line is normal
  /// and losing the whole day's history to it would be absurd.
  Future<List<Map<String, dynamic>>> readAll({int? limit}) async {
    final out = <Map<String, dynamic>>[];
    for (final f in await files()) {
      late final List<String> lines;
      try {
        lines = await f.readAsLines();
      } catch (_) {
        continue;
      }
      for (final l in lines) {
        if (l.trim().isEmpty) continue;
        try {
          final v = jsonDecode(l);
          if (v is Map<String, dynamic>) out.add(v);
        } catch (_) {
          // Torn row. Skip it and keep going.
        }
      }
    }
    if (limit != null && out.length > limit) {
      return out.sublist(out.length - limit); // newest N
    }
    return out;
  }

  /// How much corpus exists. Cheap — for a status line, not for analysis.
  Future<({int days, int turns})> size() async {
    final fs = await files();
    var turns = 0;
    for (final f in fs) {
      try {
        turns += (await f.readAsLines()).where((l) => l.trim().isNotEmpty).length;
      } catch (_) {}
    }
    return (days: fs.length, turns: turns);
  }
}
