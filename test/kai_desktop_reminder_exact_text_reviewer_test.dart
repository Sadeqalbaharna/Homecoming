import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/services/core/kai_core_client.dart';
import 'package:homecoming_app/services/core/kai_core_server.dart';
import 'package:homecoming_app/services/core/kai_desktop_reminder_tool.dart';

void main() {
  test('desktop reminder stores the exact message including outer whitespace',
      () async {
    final directory =
        Directory.systemTemp.createTempSync('kai_reminder_exact_reviewer');
    final now = DateTime.utc(2026, 8, 8, 12);
    final server = KaiCoreServer(
      dataDirectory: directory,
      port: 0,
      clock: () => now,
    );
    await server.start();
    final client = KaiCoreClient(endpoint: server.endpoint!);
    addTearDown(() async {
      client.close();
      await server.stop();
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });

    const exact = '  Ring Ahmed\nabout the gas line — 2× before 9:00  ';
    final result = await KaiDesktopReminderTool(
      client: client,
      now: () => now,
    ).create(const {
      'message': exact,
      'year': 2026,
      'month': 9,
      'day': 1,
      'hour': 9,
      'minute': 0,
    });

    expect(result.ok, isTrue);
    final record = (await client.commitments()).single;
    expect(
      record['text'],
      exact,
      reason: 'Briefs 012 and 017 require byte-for-byte stored and delivered '
          'text; trim may validate emptiness but may not rewrite the promise',
    );
  });
}
