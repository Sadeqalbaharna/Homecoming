import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('inner thoughts are ambient background, not presence ribbon content', () {
    final presence = File('lib/widgets/kai_presence.dart').readAsStringSync();
    final shell = File('lib/screens/kai_desktop_shell.dart').readAsStringSync();
    final monologue = File('lib/widgets/kai_inner_monologue.dart').readAsStringSync();

    expect(presence, contains('ambient background now'));
    expect(presence, isNot(contains('inner_monologue')));
    expect(shell, contains('Positioned.fill'));
    expect(shell, contains('KaiInnerMonologue('));
    expect(shell, contains('ambient: true'));
    final rowStart = shell.indexOf('Row(');
    expect(rowStart, isNonNegative);
    expect(
      shell.indexOf('KaiInnerMonologue('),
      lessThan(rowStart),
      reason: 'ambient thoughts should sit behind the main panels',
    );
    expect(monologue, contains('final bool ambient;'));
    expect(monologue, contains('AnimatedPositioned'));
    expect(monologue, contains('const _ambientLanes = <Offset>'));
    expect(monologue, contains('avoid the bottom composer'));
    expect(monologue, contains('avoid the bottom composer and the dead-center'));
  });

  test('presence card is mounted in the cortex rail and carries fun-stack sections', () {
    final shell = File('lib/screens/kai_desktop_shell.dart').readAsStringSync();
    final card = File('lib/widgets/kai_presence_card.dart').readAsStringSync();

    expect(shell, contains("import '../widgets/kai_presence_card.dart';"));
    expect(shell, contains('const KaiPresenceCard(personaId: _kPersona)'));
    expect(card, contains('KAI PRESENCE'));
    expect(card, contains("_line('Now'"));
    expect(card, contains("_line('Remembered'"));
    expect(card, contains("_line('Nudge'"));
    expect(card, contains("_line('Becoming'"));
    expect(card, contains("_state.moodStream(widget.personaId)"));
    expect(card, contains(r'focus $focus%'));
    expect(card, contains(r'energy $energy%'));
  });
}
