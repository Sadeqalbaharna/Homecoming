import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/services/core/trace_store_service.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('kai_trace_store_test_');
    TraceStoreService.instance.debugOverrideDir = dir;
  });

  tearDown(() async {
    TraceStoreService.instance.debugOverrideDir = null;
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  });

  test('readAll(limit) returns the newest rows, still ordered oldest to newest', () async {
    final file = File('${dir.path}/2026-07-18.jsonl');
    final rows = List.generate(5, (i) => {'id': 'turn_$i', 'n': i});
    await file.writeAsString(rows.map(jsonEncode).join('\n'));

    final limited = await TraceStoreService.instance.readAll(limit: 3);

    expect(limited.map((r) => r['id']), ['turn_2', 'turn_3', 'turn_4']);
  });
}
