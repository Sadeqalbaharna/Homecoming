import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String methodBody(String source, String signature, String nextSignature) {
  final start = source.indexOf(signature);
  final end = source.indexOf(nextSignature, start + signature.length);
  expect(start, isNonNegative, reason: 'missing $signature');
  expect(end, greaterThan(start), reason: 'missing $nextSignature');
  return source.substring(start, end);
}

void main() {
  final source = File('lib/screens/kai_desktop_shell.dart').readAsStringSync();

  test('local Core heartbeat owns the Core indicator', () {
    expect(source, contains('onStatus: _applyCoreHeartbeatStatus'));

    final body = methodBody(
      source,
      'void _applyCoreHeartbeatStatus(KaiCoreHeartbeatStatus status)',
      'void _applyGlobalPresence(KaiGlobalPresenceSnapshot snapshot)',
    );
    expect(body, contains('_coreHeartbeatStatus = status'));
    expect(body, contains('KaiTaskbarHeartbeat.setStatus(status)'));
  });

  test('global presence updates bodies without overriding Core health', () {
    final body = methodBody(
      source,
      'void _applyGlobalPresence(KaiGlobalPresenceSnapshot snapshot)',
      'Future<void> _showPairingCode()',
    );
    expect(body, contains('_globalBodyCount = snapshot.bodyCount'));
    expect(body, contains('_globalBodies = snapshot.bodies'));
    expect(body, contains('_globalPresenceAwake = snapshot.isAwake'));
    expect(body, isNot(contains('_coreHeartbeatStatus')));
    expect(body, isNot(contains('KaiTaskbarHeartbeat.setStatus')));
  });

  test('body constellation still fails closed on global presence', () {
    expect(source, contains('awake: _globalPresenceAwake'));
    expect(
      source,
      isNot(contains(
        'awake: _coreHeartbeatStatus.phase == KaiCoreHeartbeatPhase.healthy',
      )),
    );
  });
}
