import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/services/attention/kai_proactive_attention_queue.dart';
import 'package:homecoming_app/services/attention/kai_proactive_attention_store.dart';

Directory _tempDir(String name) {
  final dir = Directory.systemTemp.createTempSync('kai_attn_edge_$name');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  return dir;
}

String _path(Directory directory, String name) =>
    '${directory.path}${Platform.pathSeparator}$name';

void main() {
  test('backup-only recovery preserves the last readable copy on next save',
      () async {
    final directory = _tempDir('backup_only');
    final original = KaiProactiveAttentionQueue().snapshot();
    final backup = File(_path(directory, 'attention.json.bak'))
      ..writeAsStringSync(jsonEncode(original));

    final store = KaiProactiveAttentionStore(directory: directory);
    expect(await store.load(), isNotNull);
    expect(store.lastLoadStatus, KaiAttentionLoadStatus.recoveredFromBackup);

    await store.save(KaiProactiveAttentionQueue().snapshot());

    expect(backup.existsSync(), isTrue,
        reason: 'a crash between primary rotation and final rename can leave '
            'only the backup; the first resumed save must not delete it');
    expect(jsonDecode(backup.readAsStringSync()), isA<Map>());
  });

  test('backup-only corruption is quarantined rather than deleted', () async {
    final directory = _tempDir('backup_corrupt_only');
    final backup = File(_path(directory, 'attention.json.bak'))
      ..writeAsStringSync('{ broken backup only');

    final store = KaiProactiveAttentionStore(directory: directory);
    expect(await store.load(), isNull);
    expect(store.lastLoadStatus, KaiAttentionLoadStatus.corrupt);

    await store.save(KaiProactiveAttentionQueue().snapshot());

    expect(backup.existsSync(), isFalse);
    final quarantine = File(_path(directory, 'attention.json.bak.corrupt'));
    expect(quarantine.existsSync(), isTrue,
        reason: 'degraded startup must retain the corrupt evidence');
    expect(quarantine.readAsStringSync(), '{ broken backup only');
  });

  test('a pre-existing quarantine is preserved and the save still succeeds',
      () async {
    // Renaming onto an existing path throws on Windows, so a second incident
    // would otherwise make every later save fail permanently — a diagnostic
    // file becoming an outage. Overwriting instead would destroy the first
    // incident's evidence, which is the whole point of keeping it.
    final directory = _tempDir('quarantine_collision');

    final earlier = File(_path(directory, 'attention.json.corrupt'))
      ..writeAsStringSync('{ first incident');
    File(_path(directory, 'attention.json'))
        .writeAsStringSync('{ second incident');

    final store = KaiProactiveAttentionStore(directory: directory);
    expect(await store.load(), isNull);
    expect(store.lastLoadStatus, KaiAttentionLoadStatus.corrupt);

    await store.save(KaiProactiveAttentionQueue().snapshot());

    // The earlier evidence is byte-for-byte intact.
    expect(earlier.readAsStringSync(), '{ first incident');

    // The new incident took a distinct deterministic path.
    final next = File(_path(directory, 'attention.json.corrupt.1'));
    expect(next.existsSync(), isTrue);
    expect(next.readAsStringSync(), '{ second incident');

    // And the save actually landed.
    final primary = File(_path(directory, 'attention.json'));
    expect(jsonDecode(primary.readAsStringSync()), isA<Map>());
  });

  test('a failed save leaves the recovered backup untouched for a retry',
      () async {
    final root = _tempDir('retry_after_failure');
    final directory = Directory(_path(root, 'state'))..createSync();

    final backup = File(_path(directory, 'attention.json.bak'))
      ..writeAsStringSync(jsonEncode(KaiProactiveAttentionQueue().snapshot()));

    final store = KaiProactiveAttentionStore(directory: directory);
    expect(await store.load(), isNotNull);
    expect(store.lastLoadStatus, KaiAttentionLoadStatus.recoveredFromBackup);

    // Make the directory unwritable by replacing it with a file.
    directory.deleteSync(recursive: true);
    final blocker = File(directory.path)..writeAsStringSync('blocking');

    await expectLater(
      store.save(KaiProactiveAttentionQueue().snapshot()),
      throwsA(anything),
    );

    // Restore the directory and the backup, then retry.
    blocker.deleteSync();
    directory.createSync();
    backup
        .writeAsStringSync(jsonEncode(KaiProactiveAttentionQueue().snapshot()));

    await store.save(KaiProactiveAttentionQueue().snapshot());

    expect(backup.existsSync(), isTrue,
        reason: 'the obligation to preserve survives a failed attempt');
    expect(jsonDecode(backup.readAsStringSync()), isA<Map>());
    expect(
      jsonDecode(File(_path(directory, 'attention.json')).readAsStringSync()),
      isA<Map>(),
    );
  });
}
