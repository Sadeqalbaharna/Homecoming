import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/services/core/kai_operations_journal.dart';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('kai_ops_test_');
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('writes structured request telemetry without conversation content',
      () async {
    final journal = KaiOperationsJournal(directory: directory);
    await journal.record(
      'request_completed',
      requestId: 'request-1',
      surface: 'messenger',
      duration: const Duration(milliseconds: 321),
      details: const {'status': 'done', 'attempt': 1},
    );

    final records = await journal.readRecent();
    expect(records, hasLength(1));
    expect(records.single['event'], 'request_completed');
    expect(records.single['requestId'], 'request-1');
    expect(records.single['durationMs'], 321);
    expect(await journal.currentFile.readAsString(), isNot(contains('hello')));
  });

  test('serializes concurrent writes and rotates bounded generations',
      () async {
    final journal = KaiOperationsJournal(
      directory: directory,
      maxBytes: 180,
      generations: 2,
    );
    await Future.wait([
      for (var i = 0; i < 12; i++)
        journal.record('beat', details: {'sequence': i, 'padding': 'x' * 40}),
    ]);
    await journal.flush();

    expect(await journal.currentFile.exists(), isTrue);
    expect(
      await File('${directory.path}${Platform.pathSeparator}'
              'kai-operations.1.jsonl')
          .exists(),
      isTrue,
    );
    expect(
      await File('${directory.path}${Platform.pathSeparator}'
              'kai-operations.3.jsonl')
          .exists(),
      isFalse,
    );
  });

  test('redacts credentials from keys, authenticated URLs, and error text',
      () async {
    final journal = KaiOperationsJournal(directory: directory);
    const fakeJwt =
        'eyJhbGciOiJSUzI1NiJ9.eyJzdWIiOiJrYWkifQ.fake-signature-value';
    const fakeGoogleKey = 'AIzaSyabcdefghijklmnopqrstuvwxyz123456';
    const fakeProviderKey = 'sk-ant-abcdefghijklmnopqrstuvwxyz123456';
    await journal.record(
      'request_stream_unavailable',
      requestId: 'safe-correlation-id',
      details: const {
        'error': 'GET https://example.test/data.json?auth=$fakeJwt&key='
            '$fakeGoogleKey Authorization: Bearer $fakeJwt '
            'provider=$fakeProviderKey',
        'apiKey': fakeGoogleKey,
        'nested': {
          'refresh_token': 'refresh-secret-value',
          'status': 'offline',
        },
      },
    );

    final raw = await journal.currentFile.readAsString();
    expect(raw, isNot(contains(fakeJwt)));
    expect(raw, isNot(contains(fakeGoogleKey)));
    expect(raw, isNot(contains(fakeProviderKey)));
    expect(raw, isNot(contains('refresh-secret-value')));
    expect(raw, contains('[REDACTED]'));
    expect(raw, contains('safe-correlation-id'));
    expect(raw, contains('offline'));
  });
}
