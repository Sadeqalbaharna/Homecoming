import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('desktop shell mounts the efficiency delta meter in the chat header', () {
    final source = File('lib/screens/kai_desktop_shell.dart').readAsStringSync();

    expect(source, contains("import '../widgets/kai_efficiency_delta_meter.dart';"));
    expect(source, contains('const KaiEfficiencyDeltaMeter()'));
    expect(source.indexOf('const KaiEfficiencyDeltaMeter()'),
        greaterThan(source.indexOf('child: KaiPresence(personaId: _kPersona)')));
    expect(source.indexOf('const KaiEfficiencyDeltaMeter()'),
        lessThan(source.indexOf('const KaiCostMeter()')));
  });

  test('usage_report includes rolling trace efficiency deltas', () {
    final source = File('lib/services/core/tool_executor_service.dart').readAsStringSync();

    expect(source, contains("case 'usage_report':"));
    expect(source, contains('TraceStoreService.instance.readAll(limit: 16)'));
    expect(source, contains('efficiencySummary(rows, window: 8).report()'));
  });
}
