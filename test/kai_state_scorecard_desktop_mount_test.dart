import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('desktop moves the scorecard behind the header efficiency meter', () {
    final source = File('lib/screens/kai_desktop_shell.dart').readAsStringSync();
    final meter = File('lib/widgets/kai_efficiency_delta_meter.dart')
        .readAsStringSync();

    expect(source,
        isNot(contains("import '../widgets/kai_state_scorecard_card.dart';")));
    expect(source, isNot(contains('const KaiStateScorecardCard(limit: 40)')));
    expect(source, contains('const KaiEfficiencyDeltaMeter()'));
    expect(meter, contains("import 'kai_state_scorecard_card.dart';"));
    expect(meter, contains("Key('kai-efficiency-scorecard-toggle')"));
    expect(meter, contains('KaiStateScorecardCard('));
  });

  test('desktop shell renders the live hands-state indicator', () {
    final source = File('lib/screens/kai_desktop_shell.dart').readAsStringSync();

    expect(source, contains('_HandsLight(state: _handsState)'));
    expect(source, contains("KaiHandsState.on => ('HANDS ON'"));
    expect(source, contains("KaiHandsState.activating => ('HANDS ACTIVATING'"));
    expect(source, contains("KaiHandsState.off => ('HANDS OFF'"));
    expect(source, contains('onHandsState: (state)'));
  });
}
