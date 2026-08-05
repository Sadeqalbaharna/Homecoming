import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// These read source text, so they are TRIPWIRES, not behaviour tests: they
// prove a line exists, not that it runs. They guard wiring inside a network-
// bound handler that cannot be invoked offline.
//
// Rule for adding to this file: assert on wiring that SHOULD be permanent.
// Never assert that something is still unimplemented — a test pinning
// `memoryCandidates: const []` fails the day candidates are correctly built,
// which teaches the next person to delete tests to make progress.
void main() {
  test(
      'Unity presence greetings are ephemeral and do not use memory/web ballast',
      () {
    final source = File(
      'lib/services/embodiment/kai_embodiment_gateway_service.dart',
    ).readAsStringSync();

    expect(source, contains('turn.surfaceContext.isPresenceEvent'));
    expect(source, contains('useMemory: !isPresenceEvent'));
    expect(source, contains('useWebSearch: false'));
    expect(source, contains('saveUserMessage: !isPresenceEvent'));
    expect(
      source,
      contains('surfaceContext: turn.surfaceContext'),
    );
    expect(source, contains('KaiContinuityTurnRequest.fromJson'));
    expect(source, contains('availableCapabilitiesFor(turn.surfaceContext)'));
  });

  test('the headset transport clamps which bodies it will host', () {
    final source = File(
      'lib/services/embodiment/kai_embodiment_gateway_service.dart',
    ).readAsStringSync();

    // The surface decides the permission set, so an unclamped parser lets the
    // payload choose its own tools. Behaviour is covered for real in
    // kai_continuity_contract_test.dart; this only guards the wiring.
    expect(source, contains('allowedSurfaces: kEmbodimentSurfaces'));
  });

  test(
      'AI prompt gives Unity presence events a no-internal-context speech guard',
      () {
    final source = File('lib/services/ai/ai_service.dart').readAsStringSync();

    expect(source, contains("activeSource == 'unity_presence'"));
    expect(source, contains('UNITY PRESENCE EVENT GUARD'));
    expect(
      source,
      contains(
          'Reply only to the immediate presence event in one brief natural line'),
    );
    expect(
      source,
      contains('Do not mention files, tests, git status, memories, noticings'),
    );
  });
}
