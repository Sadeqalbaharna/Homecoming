import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const packetId = 'FSC-LEGACY-YES-001-BP-IC-v3';
const candidateId = 'FSC-LEGACY-YES-001';
const factoryRunId = 'factory-run-legacy-recovery-20260809-tablefinder-01';

String readDoc(String name) => File('docs/$name').readAsStringSync();

void main() {
  test('Find My Table current documents share the v3 scale packet', () {
    final blueprint = readDoc('FACTORY_BLUEPRINT_FSC_LEGACY_YES_001.md');
    final evidence =
        readDoc('FACTORY_BLUEPRINT_OPERATING_EVIDENCE_FSC_LEGACY_YES_001.md');
    final scale = readDoc('FACTORY_BLUEPRINT_SCALE_SPEC_FSC_LEGACY_YES_001.md');
    final feedback =
        readDoc('FACTORY_BLUEPRINT_SHARK_FEEDBACK_FSC_LEGACY_YES_001.md');

    for (final document in [blueprint, scale, feedback]) {
      expect(document, contains(packetId));
      expect(document, contains(candidateId));
    }
    expect(evidence, contains(candidateId));
    expect(blueprint, contains(factoryRunId));
    expect(scale, contains(factoryRunId));

    expect(blueprint, contains('two filled hosted tables per week'));
    expect(blueprint, contains('four players per table'));
    expect(blueprint, contains('BHD48'));
    expect(blueprint, contains('BHD96'));
    expect(blueprint, contains('finding players'));
    expect(blueprint, contains('finding DMs'));
    expect(blueprint, contains('matching schedule/fit'));
  });

  test('v3 freezes internal scale MVP and preserves live authority gates', () {
    final scale = readDoc('FACTORY_BLUEPRINT_SCALE_SPEC_FSC_LEGACY_YES_001.md');

    expect(scale, contains('internal operations MVP'));
    expect(scale, contains('four-player tables'));
    expect(scale, contains('BHD12 minimum'));
    expect(scale, contains('deterministic rules group'));
    expect(scale, contains('venue operator approves'));
    expect(scale, contains('using synthetic data'));
    expect(scale, contains('does not authorize Assembly'));
    expect(scale, contains('customer-data import'));
    expect(scale, contains('player/DM contact'));
    expect(scale, contains('public release'));
    expect(scale, contains('payment handling'));
    expect(scale, contains('INVEST'));
    expect(scale, contains('REVISE'));
    expect(scale, contains('KILL'));
    expect(scale, contains('PARK'));
  });

  test('superseded paid-seat thesis is visibly historical', () {
    final memo =
        readDoc('FACTORY_BLUEPRINT_INVESTMENT_MEMO_FSC_LEGACY_YES_001.md');
    final pilot = readDoc('FACTORY_BLUEPRINT_PILOT_SPEC_FSC_LEGACY_YES_001.md');

    expect(memo, contains('HISTORICAL'));
    expect(pilot, contains('HISTORICAL'));
    expect(memo, contains(packetId));
    expect(pilot, contains(packetId));
  });
}
