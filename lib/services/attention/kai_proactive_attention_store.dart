// Durable state for the proactive attention queue.
//
// Brief 007 left the queue in memory: a coordinator crash erased everything Kai
// was waiting to say and handed him six fresh nudges. This makes that state
// survive a restart without duplicate delivery, a reset budget, reordered
// events, or a lost retry instant.
//
// Deliberately narrow. It reads and writes one JSON document and knows nothing
// about attention policy — expiry, quiet hours, budget and routing stay
// decisions of KaiAttentionEngine, evaluated normally after restore.
//
// The atomic pattern is lifted from KaiCoreServer._persist(), which is proven
// in production: serialize through a future tail, write a temp file, rotate the
// current file to .bak, then rename temp into place. Two things make it work
// and both are easy to lose in a rewrite — the payload is encoded BEFORE
// chaining, so each caller captures its own snapshot, and every filesystem step
// happens inside the tail, so overlapping callers can never interleave.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// What [KaiProactiveAttentionStore.load] actually found.
///
/// Five outcomes rather than a nullable map, because "nothing to restore" has
/// very different meanings. A first run is normal; an unsupported version is a
/// build/state mismatch someone needs to see; corrupt bytes are a fault. Brief
/// 008 collapsed all three into null and then journalled the result as a
/// successful load.
enum KaiAttentionLoadStatus {
  /// Nothing stored yet. Normal on a first run.
  absent,

  /// Read from the primary file.
  loaded,

  /// The primary was unreadable; the last good backup was used.
  recoveredFromBackup,

  /// Neither file could be parsed. Evidence is retained.
  corrupt,

  /// Valid JSON, but a schema this build does not understand. Deliberately not
  /// treated as an empty version-1 queue — half-understanding future state is
  /// how a resumed process quietly loses what it was holding.
  unsupportedVersion,
}

class KaiProactiveAttentionStore {
  KaiProactiveAttentionStore({Directory? directory})
      : directory = directory ?? defaultDirectory();

  final Directory directory;

  Future<void> _writeTail = Future<void>.value();

  /// What the last [load] found. See [KaiAttentionLoadStatus].
  KaiAttentionLoadStatus lastLoadStatus = KaiAttentionLoadStatus.absent;

  /// True when the last [load] could not use the state it found.
  bool get lastLoadDegraded =>
      lastLoadStatus == KaiAttentionLoadStatus.corrupt ||
      lastLoadStatus == KaiAttentionLoadStatus.unsupportedVersion;

  /// True when [load] recovered from the backup rather than the primary.
  bool get lastLoadUsedBackup =>
      lastLoadStatus == KaiAttentionLoadStatus.recoveredFromBackup;

  // ── Recovery state ─────────────────────────────────────────────────────────
  //
  // Set by [load], consumed by the FIRST successful [save] afterwards.
  //
  // Brief 009 keyed these on CORRUPTION, which was the wrong question. An
  // ABSENT primary is not corrupt, so both flags stayed false and the normal
  // rotation ran — and its first step is `delete .bak`. A crash between
  // rotating the primary into .bak and installing the temp file legitimately
  // leaves exactly that state: no primary, one readable backup. The next save
  // deleted the only copy that survived the crash.
  //
  // The question that actually matters is not "was this corrupt" but "is this
  // the last readable copy". Hence three independent facts rather than two.

  /// The primary exists and could not be parsed. Quarantine it.
  bool _quarantinePrimary = false;

  /// The backup exists and could not be parsed. Quarantine it — a known-corrupt
  /// backup is evidence, and must never leave via ordinary rotation.
  bool _quarantineBackup = false;

  /// The backup is READABLE and is currently the only readable copy. Leave it
  /// completely alone until a new primary is installed.
  bool _preserveBackup = false;

  static Directory defaultDirectory() {
    final local = Platform.environment['LOCALAPPDATA'];
    final root =
        local == null || local.trim().isEmpty ? Directory.current.path : local;
    return Directory(
      '$root${Platform.pathSeparator}Homecoming${Platform.pathSeparator}KaiCore',
    );
  }

  File get _stateFile =>
      File('${directory.path}${Platform.pathSeparator}attention.json');
  File get _backupFile => File('${_stateFile.path}.bak');

  /// Returns the stored snapshot, the backup if the primary is unreadable, or
  /// null when there is nothing usable.
  ///
  /// Never throws, and never deletes or overwrites either file. Corrupt state
  /// is EVIDENCE — startup reports it, and a human decides. Repairing it here
  /// would destroy the only copy of whatever went wrong.
  Future<Map<String, dynamic>?> load() async {
    _quarantinePrimary = false;
    _quarantineBackup = false;
    _preserveBackup = false;

    final primary = await _read(_stateFile);
    if (primary.unsupported) {
      // Parsed cleanly, but this build cannot understand it. Not corrupt, and
      // emphatically not an empty queue — report it and restore nothing.
      lastLoadStatus = KaiAttentionLoadStatus.unsupportedVersion;
      return null;
    }
    if (primary.value != null) {
      lastLoadStatus = KaiAttentionLoadStatus.loaded;
      return primary.value;
    }
    // Unreadable is quarantinable; simply absent is not.
    _quarantinePrimary = primary.corrupt;

    final backup = await _read(_backupFile);
    if (backup.value != null) {
      // The backup is the last readable copy, whether the primary was corrupt
      // or was never installed. Either way it survives the next save.
      _preserveBackup = true;
      lastLoadStatus = KaiAttentionLoadStatus.recoveredFromBackup;
      return backup.value;
    }
    _quarantineBackup = backup.corrupt || backup.unsupported;

    // Nothing usable. Distinguish "first run" from "the copies are broken":
    // one is normal, the other is a fault someone needs to see.
    lastLoadStatus = (_quarantinePrimary || _quarantineBackup)
        ? KaiAttentionLoadStatus.corrupt
        : KaiAttentionLoadStatus.absent;
    return null;
  }

  static Future<_ReadResult> _read(File file) async {
    try {
      if (!await file.exists()) return const _ReadResult();
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return const _ReadResult(corrupt: true);
      final map = Map<String, dynamic>.from(decoded);
      if (map['version'] != _supportedVersion) {
        return const _ReadResult(unsupported: true);
      }
      return _ReadResult(value: map);
    } catch (_) {
      // Present but unparseable.
      return const _ReadResult(corrupt: true);
    }
  }

  /// The only schema this build understands. Kept here so [load] can classify
  /// an unsupported file without depending on queue policy.
  static const _supportedVersion = 1;

  /// Persist a snapshot. Safe to call concurrently.
  ///
  /// The returned future carries THIS save's outcome. A failure completes it
  /// with an error while leaving the internal tail healthy, so a later save can
  /// still succeed.
  ///
  /// Brief 008 used `.catchError` on the tail itself, which meant two things at
  /// once: the caller's future always completed successfully — making the
  /// coordinator's persistence-failure journal unreachable — and the swallow
  /// was the only thing keeping the tail alive. Splitting them separates
  /// "report to the caller" from "keep the chain usable", which were never the
  /// same requirement.
  Future<void> save(Map<String, dynamic> snapshot) {
    // Encoded HERE, synchronously, before joining the tail. Two overlapping
    // callers therefore each capture their own state and the later write wins
    // in chain order — rather than both serializing whatever the queue happens
    // to hold by the time the tail reaches them.
    final payload = jsonEncode(snapshot);
    final result = Completer<void>();
    _writeTail = _writeTail.then((_) async {
      try {
        await _write(payload);
        result.complete();
      } catch (error, stack) {
        // The tail absorbs so the chain stays usable; the caller still gets it.
        stderr.writeln('[KaiAttentionStore] persist failed: $error');
        result.completeError(error, stack);
      }
    });
    return result.future;
  }

  Future<void> _write(String payload) async {
    await directory.create(recursive: true);
    final temp = File('${_stateFile.path}.tmp');
    await temp.writeAsString(payload, flush: true);

    final recovering =
        _quarantinePrimary || _quarantineBackup || _preserveBackup;

    if (recovering) {
      // ── First save after a degraded load ─────────────────────────────────
      //
      // Nothing readable is deleted, and nothing corrupt is deleted either.
      // Unreadable files move sideways into quarantine; a readable backup is
      // not touched at all until the new primary is in place.
      if (_quarantinePrimary && await _stateFile.exists()) {
        await _stateFile.rename(await _quarantinePath(_stateFile));
      }
      if (_quarantineBackup && await _backupFile.exists()) {
        await _backupFile.rename(await _quarantinePath(_backupFile));
      }

      // Install last. Until this line lands, the readable backup is still the
      // only copy — so a failure above leaves it exactly where it was and a
      // later retry can still succeed.
      await temp.rename(_stateFile.path);

      // Cleared only on success. A save that threw earlier must arrive here
      // again with the same obligations.
      _quarantinePrimary = false;
      _quarantineBackup = false;
      _preserveBackup = false;
      return;
    }

    // Normal rotation, unchanged.
    if (await _backupFile.exists()) await _backupFile.delete();
    if (await _stateFile.exists()) await _stateFile.rename(_backupFile.path);
    await temp.rename(_stateFile.path);
  }

  /// A free quarantine path for [file], never colliding with earlier evidence.
  ///
  /// `attention.json.corrupt`, then `.corrupt.1`, `.corrupt.2`, … Lowest free
  /// index, so it is deterministic and reproducible rather than timestamped.
  ///
  /// Renaming onto an existing path throws on Windows, so without this a second
  /// incident would make every subsequent save fail permanently — turning a
  /// diagnostic file into a persistent outage. Overwriting instead would
  /// destroy the first incident's evidence, which is the thing quarantine
  /// exists to keep.
  static Future<String> _quarantinePath(File file) async {
    final base = '${file.path}.corrupt';
    if (!await File(base).exists()) return base;
    for (var i = 1;; i++) {
      final candidate = '$base.$i';
      if (!await File(candidate).exists()) return candidate;
    }
  }

  /// Await any in-flight write. For shutdown and for tests.
  Future<void> flush() => _writeTail;
}

class _ReadResult {
  const _ReadResult(
      {this.value, this.corrupt = false, this.unsupported = false});

  final Map<String, dynamic>? value;

  /// Present but unparseable.
  final bool corrupt;

  /// Parsed, but a schema version this build does not support.
  final bool unsupported;
}
