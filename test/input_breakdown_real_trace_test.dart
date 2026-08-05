import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/services/core/trace_store_service.dart';
import 'package:homecoming_app/tools/replay.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('prints focused input breakdown for real trace corpus when enabled', () async {
    const enabledFromDefine = String.fromEnvironment('KAI_REAL_TRACE_BREAKDOWN');
    final enabledFromEnv = Platform.environment['KAI_REAL_TRACE_BREAKDOWN'];
    final enabled = enabledFromDefine == '1' || enabledFromEnv == '1';
    if (!enabled) {
      print('Skipping real trace breakdown. Set KAI_REAL_TRACE_BREAKDOWN=1 '
          'or pass --dart-define KAI_REAL_TRACE_BREAKDOWN=1 to run.');
      return;
    }

    const traceDirFromDefine = String.fromEnvironment('KAI_TRACE_DIR');
    final traceDirPath = traceDirFromDefine.isNotEmpty
        ? traceDirFromDefine
        : Platform.environment['KAI_TRACE_DIR'];
    if (traceDirPath != null && traceDirPath.isNotEmpty) {
      TraceStoreService.instance.debugOverrideDir = Directory(traceDirPath);
    }

    const routeFromDefine = String.fromEnvironment('KAI_TRACE_ROUTE');
    final route = routeFromDefine.isNotEmpty
        ? routeFromDefine
        : Platform.environment['KAI_TRACE_ROUTE'] ?? 'coding';
    const limitFromDefine = String.fromEnvironment('KAI_TRACE_LIMIT');
    final limit = int.tryParse(limitFromDefine.isNotEmpty
            ? limitFromDefine
            : Platform.environment['KAI_TRACE_LIMIT'] ?? '') ??
        4;
    const readLimitFromDefine = String.fromEnvironment('KAI_TRACE_READ_LIMIT');
    final readLimit = int.tryParse(readLimitFromDefine.isNotEmpty
            ? readLimitFromDefine
            : Platform.environment['KAI_TRACE_READ_LIMIT'] ?? '') ??
        100;

    final rows = await TraceStoreService.instance.readAll(limit: readLimit);
    final report = inputBreakdownReport(rows, route: route, limit: limit);

    print(report);
    expect(report, isNotEmpty);
  });
}
