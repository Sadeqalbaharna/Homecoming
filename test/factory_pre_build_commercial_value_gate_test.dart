import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  late Map<String, dynamic> gate;

  setUpAll(() {
    gate = jsonDecode(
      File('docs/fixtures/factory_pre_build_commercial_value_gate_v1.json')
          .readAsStringSync(),
    ) as Map<String, dynamic>;
  });

  test('gate sits inside Blueprint and cannot authorize later stations', () {
    expect(gate['station'], 'Blueprint');
    expect(gate['appliesBefore'], 'Assembly');
    final authority = gate['authority'] as Map<String, dynamic>;
    expect(authority['sponsorOwnsSampleReview'], isTrue);
    expect(authority['technicalTestsCanSatisfyGate'], isFalse);
    expect(authority['passDoesNotAuthorizeAssembly'], isTrue);
    expect(authority['passDoesNotAuthorizePublishing'], isTrue);
  });

  test('all six commercial checks are required and machine addressable', () {
    final checks = (gate['requiredChecks'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    expect(
      checks.map((check) => check['id']),
      containsAllInOrder(<String>[
        'paid_transformation',
        'competitor_depth',
        'representative_sample',
        'adversarial_buyer_value',
        'sponsor_sample_review',
        'thin_wrapper_kill',
      ]),
    );
    expect(checks.every((check) => check['required'] == true), isTrue);
    final competitor = checks.singleWhere(
      (check) => check['id'] == 'competitor_depth',
    );
    expect(competitor['minimumCurrentProducts'], 3);
    expect(competitor['liveExternalEvidenceRequired'], isTrue);
    final sample = checks.singleWhere(
      (check) => check['id'] == 'representative_sample',
    );
    expect(sample['evidenceFields'], contains('artifactSha256'));
    final sponsor = checks.singleWhere(
      (check) => check['id'] == 'sponsor_sample_review',
    );
    expect(sponsor['requiredSponsorVerdict'], 'PASS');
    expect(sponsor['evidenceFields'], contains('sampleArtifactSha256'));
  });

  test('thin wrapper is an unconditional KILL before missing-evidence rules', () {
    final rules = (gate['decisionRules'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    expect(rules.first['priority'], 1);
    expect(rules.first['verdict'], 'KILL');
    expect(rules.first['when'], contains('thinWrapperOrRandomizer == true'));
    expect(
      rules.singleWhere((rule) => rule['verdict'] == 'UNVERIFIED')['reason'],
      contains('Technical completeness cannot substitute'),
    );
  });

  test('blank record starts unverified with no inferred authority', () {
    final template = gate['recordTemplate'] as Map<String, dynamic>;
    expect(template['gateVerdict'], 'UNVERIFIED');
    expect(template['assemblyAuthorityId'], isNull);
    expect(template['publicAuthorityId'], isNull);
    final checks = template['checks'] as Map<String, dynamic>;
    expect(checks.keys, hasLength(6));
    expect(checks.values.every((value) => (value as Map).isEmpty), isTrue);
  });

  test('methodology binds the machine gate before Assembly', () {
    final source = File('docs/FACTORY_PROJECT_SOURCE_OF_TRUTH.md')
        .readAsStringSync();
    final scout = File('KAI_PRODUCT_SCOUT_METHOD.md').readAsStringSync();
    expect(source, contains('factory-pre-build-commercial-value-v1'));
    expect(source, contains('Technical tests cannot pass this value gate'));
    expect(scout, contains('PRE-BUILD COMMERCIAL VALUE GATE'));
    expect(scout, contains('thin wrapper or randomizer'));
  });
}
