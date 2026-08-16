import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:homecoming_app/logic/find_my_table_operator.dart';
import 'package:test/test.dart';

import '../scripts/tools/generate_find_my_table_private_pilot_packet.dart';

Archive _decodeWorkbook(Uint8List bytes) =>
    ZipDecoder().decodeBytes(bytes, verify: true);

String _entryText(Archive archive, String name) {
  final file = archive.files.where((entry) => entry.name == name).single;
  final content = file.content;
  if (content is Uint8List) return utf8.decode(content);
  return utf8.decode(List<int>.from(content as Iterable));
}

String _hash(List<int> bytes) => sha256.convert(bytes).toString();

void main() {
  test(
      'oracle fixture retains 4/3/3 routes, duplicate, mismatches, and lifecycle',
      () {
    final assembly = runSyntheticPilotAssembly();

    expect(assembly.routeCounts, pilotExpectedRouteCounts);
    expect(assembly.reviewRows, hasLength(10));
    expect(assembly.initialSelectedPlayerIds, ['p001', 'p002', 'p003', 'p004']);
    expect(assembly.initialWaitlistPlayerIds, ['p005', 'p006', 'p010']);
    expect(assembly.duplicateRecordId, 'p008');
    expect(assembly.duplicateOfId, 'p002');
    expect(assembly.ledger, hasLength(11));
    expect(
      assembly.ledger.map((event) => event.reason),
      containsAll([
        'language mismatch',
        'system mismatch',
        'synthetic decline retained',
        'synthetic cancellation retained',
        'ordered compatible replacement for p003',
      ]),
    );
    expect(assembly.finalSelectedPlayerIds, ['p001', 'p002', 'p005', 'p004']);
    expect(assembly.finalWaitlistPlayerIds, ['p006', 'p010']);
    expect(assembly.proposal.revenueState, RevenueProofState.approved);
  });

  test('recipient-specific invitation is physically gated by approval', () {
    final proposed =
        buildSyntheticPilotOperator().proposeForSlot(pilotSlotId).operator;
    expect(
      () => buildRecipientInvitationDraft(proposed, pilotProposalId, 'p001'),
      throwsStateError,
    );

    final approved = runSyntheticPilotAssembly();
    final draft = buildRecipientInvitationDraft(
      approved.operator,
      approved.proposal.id,
      'p001',
    );
    expect(draft, contains('UNSENT; no channel authorized'));
    expect(draft, contains('BHD12 minimum food/drink bill'));
    expect(draft, contains('UNAVAILABLE'));
  });

  test('economics match oracle and every blank required input stays honest',
      () {
    expect(evaluateAttributionCells(centralAttributionCase), {
      'gross': 48.0,
      'netNewShare': 1.0,
      'attributableContribution': 4.2,
      'nonNegative': true,
    });
    expect(evaluateAttributionCells(transferredSeatAttributionCase), {
      'gross': 48.0,
      'netNewShare': 0.75,
      'attributableContribution': -0.6,
      'nonNegative': false,
    });

    for (final cell in [
      ...centralBillCells,
      ...centralNetNewCells,
      ...centralInputCells,
    ]) {
      final result =
          evaluateAttributionCells(blankCentralAttributionCase(cell));
      expect(result['attributableContribution'], unavailable, reason: cell);
      expect(result['nonNegative'], unavailable, reason: cell);
      if (centralBillCells.contains(cell)) {
        expect(result['gross'], unavailable, reason: cell);
      }
      if (centralNetNewCells.contains(cell)) {
        expect(result['netNewShare'], unavailable, reason: cell);
      }
    }
  });

  test('artifact set, bytes, and manifest hashes are deterministic', () {
    final first = buildFindMyTablePrivatePilotArtifacts();
    final second = buildFindMyTablePrivatePilotArtifacts();

    expect(first.keys.toList(), findMyTablePilotArtifacts);
    expect(second.keys.toList(), findMyTablePilotArtifacts);
    for (final name in findMyTablePilotArtifacts) {
      expect(_hash(second[name]!), _hash(first[name]!), reason: name);
    }

    final manifest = utf8.decode(first[findMyTablePilotManifestArtifact]!);
    for (final name in findMyTablePilotPayloadArtifacts) {
      expect(manifest, contains('| $name | ${_hash(first[name]!)} |'));
    }
    expect(manifest, contains('Generated deterministically: YES'));
    expect(manifest, contains('Every box must remain unchecked'));
  });

  test('two clean directory generations contain the same eleven files', () {
    final root = Directory.systemTemp.createTempSync('fmt-pilot-packet-test-');
    addTearDown(() => root.deleteSync(recursive: true));
    final one = Directory('${root.path}/one');
    final two = Directory('${root.path}/two');

    final first = generateFindMyTablePrivatePilotPacket(
      outputDirectoryPath: one.path,
    );
    final second = generateFindMyTablePrivatePilotPacket(
      outputDirectoryPath: two.path,
    );
    expect(first.artifactNames, findMyTablePilotArtifacts);
    expect(second.sha256ByArtifact, first.sha256ByArtifact);
    expect(
      one
          .listSync()
          .whereType<File>()
          .map((file) => file.uri.pathSegments.last)
          .toSet(),
      findMyTablePilotArtifacts.toSet(),
    );
  });

  test('match workbook is valid, exact, formula-driven, and inert', () {
    final bytes = buildFindMyTablePrivatePilotArtifacts()[
        '03_match_review_workbook.xlsx']!;
    final archive = _decodeWorkbook(bytes);
    final names = archive.files.map((file) => file.name).toSet();
    final workbook = _entryText(archive, 'xl/workbook.xml');
    final review = _entryText(archive, 'xl/worksheets/sheet1.xml');
    final ledger = _entryText(archive, 'xl/worksheets/sheet2.xml');

    expect(workbook, contains('name="Review Queue"'));
    expect(workbook, contains('name="Evidence Ledger"'));
    expect(workbook, contains('calcMode="auto"'));
    expect(workbook, isNot(contains('state="hidden"')));
    expect(review, contains('COUNTIF(B2:B11,P2)'));
    expect(review, contains('existing_player_referral'));
    expect(review, contains('duplicate identity fingerprint suppressed'));
    expect(ledger, contains('ordered compatible replacement for p003'));
    expect(names.where((name) => name.contains('externalLink')), isEmpty);
    expect(names.where((name) => name.contains('connections')), isEmpty);
    expect(names.where((name) => name.endsWith('.bin')), isEmpty);
  });

  test(
      'revenue workbook carries exact formulas, cached values, and proof locks',
      () {
    final bytes =
        buildFindMyTablePrivatePilotArtifacts()['07_revenue_attribution.xlsx']!;
    final archive = _decodeWorkbook(bytes);
    final workbook = _entryText(archive, 'xl/workbook.xml');
    final attribution = _entryText(archive, 'xl/worksheets/sheet1.xml');
    final proof = _entryText(archive, 'xl/worksheets/sheet2.xml');

    expect(workbook, contains('name="Attribution"'));
    expect(workbook, contains('name="Proof States"'));
    expect(attribution, contains('SUMPRODUCT(B3:B6,--C3:C6)'));
    expect(attribution, contains('SUMPRODUCT(F3:F6,--G3:G6)'));
    expect(attribution, contains('SUMPRODUCT(--C3:C6)/ROWS(C3:C6)'));
    expect(attribution, contains('SUMPRODUCT(--G3:G6)/ROWS(G3:G6)'));
    expect(attribution, contains('<c r="B18" s="3"><f>'));
    expect(attribution, contains('<v>4.2</v>'));
    expect(attribution, contains('<v>-0.6</v>'));
    expect(proof, contains('bank-reconciled'));
    expect(proof, contains('UNAVAILABLE'));
    expect(
        proof, isNot(contains('May satisfy money gate</t></is></c><c r="D')));
  });

  test('Markdown projections retain privacy and every live lock', () {
    final artifacts = buildFindMyTablePrivatePilotArtifacts();
    final intake = utf8.decode(artifacts['01_player_intake.md']!);
    final dmBrief = utf8.decode(artifacts['05_dm_table_brief.md']!);
    final checklist = utf8.decode(artifacts['10_launch_checklist.md']!);
    final decision = utf8.decode(artifacts['09_pilot_decision_card.md']!);

    expect(intake, contains('DO NOT COLLECT REAL RESPONSES'));
    expect(intake, contains('No name, phone number, email, home address'));
    expect(dmBrief, isNot(contains('identityFingerprint')));
    expect(dmBrief, isNot(contains('existing_player_referral')));
    expect(dmBrief, contains('Aggregated operational accessibility'));
    for (final lock in [
      'LAUNCH AUTHORIZED: NO',
      'LIVE DATA AUTHORIZED: NO',
      'CONTACT AUTHORIZED: NO',
      'PAYMENT AUTHORIZED: NO',
      'PUBLICATION AUTHORIZED: NO',
      'LATER FACTORY STATION AUTHORIZED: NO',
    ]) {
      expect(checklist, contains(lock));
    }
    expect(decision, contains('Decision: UNAVAILABLE'));
    expect(decision, contains('does not authorize another Factory station'));
  });

  test('generator source has no live integration or messaging dependency', () {
    final source = File(
      'scripts/tools/generate_find_my_table_private_pilot_packet.dart',
    ).readAsStringSync();
    for (final forbidden in [
      "import 'package:http/",
      "import 'package:dio/",
      "import 'package:firebase_",
      'Socket.connect',
      'HttpClient(',
      'Process.run',
      'Process.start',
      'KaiFactoryService',
      'FindMyTableOperatorRepository',
    ]) {
      expect(source, isNot(contains(forbidden)), reason: forbidden);
    }
  });
}
