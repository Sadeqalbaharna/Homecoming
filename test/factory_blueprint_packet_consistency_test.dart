import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const packetId = 'FSC-LEGACY-YES-001-BP-IC-v2';
const candidateId = 'FSC-LEGACY-YES-001';
const factoryRunId = 'factory-run-legacy-recovery-20260809-tablefinder-01';

String readDoc(String name) => File('docs/$name').readAsStringSync();

void main() {
  test('Find My Table Blueprint documents share one current packet', () {
    final blueprint = readDoc('FACTORY_BLUEPRINT_FSC_LEGACY_YES_001.md');
    final memo =
        readDoc('FACTORY_BLUEPRINT_INVESTMENT_MEMO_FSC_LEGACY_YES_001.md');
    final pilot = readDoc('FACTORY_BLUEPRINT_PILOT_SPEC_FSC_LEGACY_YES_001.md');
    final feedback =
        readDoc('FACTORY_BLUEPRINT_SHARK_FEEDBACK_FSC_LEGACY_YES_001.md');

    for (final document in [blueprint, memo, pilot, feedback]) {
      expect(document, contains(packetId));
      expect(document, contains(candidateId));
    }
    expect(blueprint, contains(factoryRunId));
    expect(pilot, contains(factoryRunId));

    expect(blueprint, isNot(contains('Pending sponsor choice')));
    expect(blueprint, isNot(contains('venue is the candidate payer')));
    expect(blueprint, contains('adult newcomer or lapsed'));
    expect(blueprint, contains('service—not an app'));
  });

  test('pilot freezes the paid wedge while preserving every authority gate',
      () {
    final pilot = readDoc('FACTORY_BLUEPRINT_PILOT_SPEC_FSC_LEGACY_YES_001.md');

    expect(pilot, contains('adult-only hosted TTRPG one-shot'));
    expect(pilot, contains('BHD5'));
    expect(pilot, contains('BHD7'));
    expect(pilot, contains('External settled payment'));
    expect(pilot, contains('at least four paid hosted sessions'));
    expect(pilot, contains('No app starts'));
    expect(pilot, contains('does not authorize Assembly'));
    expect(pilot, contains('venue or host contact'));
    expect(pilot, contains('accounts, credentials, spend, payment'));
    expect(pilot, contains('INVEST'));
    expect(pilot, contains('REVISE'));
    expect(pilot, contains('KILL'));
    expect(pilot, contains('PARK'));
  });
}
