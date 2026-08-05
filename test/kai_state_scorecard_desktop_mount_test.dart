import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('desktop shell mounts the Kai State Scorecard card in its side rail', () {
    final source = File('lib/screens/kai_desktop_shell.dart').readAsStringSync();

    expect(source, contains("import '../widgets/kai_state_scorecard_card.dart';"));
    expect(source, contains('const KaiStateScorecardCard(limit: 40)'));
    expect(source.indexOf('const KaiStateScorecardCard(limit: 40)'),
        greaterThan(source.indexOf('KaiProjectService.sentienceId')));
    expect(source.indexOf('const KaiStateScorecardCard(limit: 40)'),
        lessThan(source.indexOf('_desktopWorkQueueCard()')));
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
