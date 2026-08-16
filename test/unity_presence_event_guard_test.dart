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

    expect(source, contains('useWebSearch: false'));
    expect(source, contains('KaiContinuityTurnRequest.fromJson'));

    // The surface must come from the CHANNEL, never from the payload.
    //
    // This deliberately does not name the variable holding it. The earlier
    // version asserted `turn.surfaceContext.isPresenceEvent` and
    // `availableCapabilitiesFor(turn.surfaceContext)` — pinning the payload-
    // supplied surface by name. When the gateway was hardened to derive the
    // surface itself, those assertions failed on the fix and pointed back at
    // the weaker form. A tripwire that resists a security improvement is worse
    // than no tripwire. So: require the clamp, and forbid the payload surface
    // being consulted for permissions.
    expect(source, contains('authoritativeSurface: _channelSurface'));
    expect(source,
        isNot(contains('availableCapabilitiesFor(turn.surfaceContext)')),
        reason:
            'capabilities follow the channel-derived surface, not the payload');

    // A presence event now short-circuits and returns BEFORE sendMessage is
    // reached at all, so there is no model call to disable memory on.
    //
    // This used to assert `useMemory: !isPresenceEvent`, which was the old
    // mechanism rather than the invariant — and when that mechanism was
    // replaced by a stronger one, the test failed on an improvement. Which is
    // precisely what the header of this file warns against. Assert the
    // guarantee (nothing durable happens on a presence event), not the
    // particular flag that happened to deliver it.
    final normalized = source.replaceAll(RegExp(r'\s+'), ' ');
    final shortCircuit = normalized.indexOf('if (isPresenceEvent) {');
    final sendMessage = normalized.indexOf('_ai!.sendMessage(');
    expect(shortCircuit, greaterThan(-1));
    expect(sendMessage, greaterThan(-1));
    expect(
      shortCircuit,
      lessThan(sendMessage),
      reason: 'a presence greeting must never reach the model call',
    );

    // And the branch must actually leave the handler, not merely be entered.
    final returnAfter = normalized.indexOf('return; }', shortCircuit);
    expect(returnAfter, greaterThan(-1));
    expect(returnAfter, lessThan(sendMessage),
        reason: 'the presence branch must return before any model call');
  });

  test('the headset transport clamps which bodies it will host', () {
    final source = File(
      'lib/services/embodiment/kai_embodiment_gateway_service.dart',
    ).readAsStringSync();

    // The surface decides the permission set, so an unclamped parser lets the
    // payload choose its own tools. Behaviour is covered for real in
    // kai_continuity_contract_test.dart; this only guards the wiring.
    expect(source, contains('allowedSurfaces: kEmbodimentSurfaces'));
    expect(source, contains('authoritativeSurface: _channelSurface'));
    expect(source, contains('allowUnauthenticatedLoopback = false'));
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
