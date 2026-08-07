library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Durable, content-free operational telemetry for Central Kai.
///
/// Conversation text and model replies deliberately never belong here. The
/// journal records lifecycle, timing, routing and errors so a hidden worker can
/// be diagnosed after a crash without turning private chat into a debug file.
class KaiOperationsJournal {
  KaiOperationsJournal({
    Directory? directory,
    this.maxBytes = 2 * 1024 * 1024,
    this.generations = 5,
  }) : directory = directory ?? defaultDirectory();

  final Directory directory;
  final int maxBytes;
  final int generations;
  Future<void> _tail = Future<void>.value();

  File get currentFile => File(
        '${directory.path}${Platform.pathSeparator}kai-operations.jsonl',
      );

  static Directory defaultDirectory() {
    final local = Platform.environment['LOCALAPPDATA'];
    final root =
        local == null || local.trim().isEmpty ? Directory.current.path : local;
    return Directory(
      '$root${Platform.pathSeparator}Homecoming${Platform.pathSeparator}'
      'KaiCore${Platform.pathSeparator}operations',
    );
  }

  Future<void> record(
    String event, {
    String component = 'coordinator',
    String severity = 'info',
    String? requestId,
    String? surface,
    Duration? duration,
    Map<String, Object?> details = const {},
  }) {
    final safeDetails = <String, Object?>{};
    for (final entry in details.entries) {
      safeDetails[entry.key] = _safeValue(entry.value);
    }
    final line = jsonEncode({
      'at': DateTime.now().toUtc().toIso8601String(),
      'event': event,
      'component': component,
      'severity': severity,
      if (requestId != null) 'requestId': requestId,
      if (surface != null) 'surface': surface,
      if (duration != null) 'durationMs': duration.inMilliseconds,
      if (safeDetails.isNotEmpty) 'details': safeDetails,
    });

    final operation = _tail.then((_) => _append(line));
    _tail = operation.catchError((_) {});
    return operation;
  }

  Future<void> flush() => _tail;

  Future<List<Map<String, dynamic>>> readRecent({int limit = 100}) async {
    await flush();
    if (!await currentFile.exists()) return const [];
    final lines = await currentFile.readAsLines();
    final selected =
        lines.length <= limit ? lines : lines.sublist(lines.length - limit);
    return selected
        .map((line) {
          try {
            final value = jsonDecode(line);
            return value is Map
                ? Map<String, dynamic>.from(value)
                : <String, dynamic>{};
          } catch (_) {
            return <String, dynamic>{};
          }
        })
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  Future<void> _append(String line) async {
    await directory.create(recursive: true);
    final file = currentFile;
    final nextBytes = utf8.encode('$line\n').length;
    if (await file.exists() && await file.length() + nextBytes > maxBytes) {
      await _rotate();
    }
    await file.writeAsString('$line\n', mode: FileMode.append, flush: true);
  }

  Future<void> _rotate() async {
    if (generations <= 0) {
      if (await currentFile.exists()) await currentFile.delete();
      return;
    }
    final oldest = _generation(generations);
    if (await oldest.exists()) await oldest.delete();
    for (var i = generations - 1; i >= 1; i--) {
      final source = _generation(i);
      if (!await source.exists()) continue;
      await source.rename(_generation(i + 1).path);
    }
    if (await currentFile.exists()) {
      await currentFile.rename(_generation(1).path);
    }
  }

  File _generation(int index) => File(
        '${directory.path}${Platform.pathSeparator}'
        'kai-operations.$index.jsonl',
      );

  static Object? _safeValue(Object? value) {
    if (value == null || value is num || value is bool) return value;
    if (value is DateTime) return value.toUtc().toIso8601String();
    if (value is Duration) return value.inMilliseconds;
    if (value is Iterable) {
      return value.take(30).map(_safeValue).toList(growable: false);
    }
    if (value is Map) {
      return value.map(
        (key, item) => MapEntry(key.toString(), _safeValue(item)),
      );
    }
    final text = value.toString();
    return text.length <= 1000 ? text : '${text.substring(0, 1000)}…';
  }
}
