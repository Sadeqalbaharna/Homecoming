import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('helper binds path hash PID watchdog and port before requesting exit',
      () {
    final source = File(
      'scripts/tools/request_kai_graceful_shutdown.ps1',
    ).readAsStringSync();

    expect(source, contains('ExpectedExecutablePath'));
    expect(source, contains('ExpectedExecutableSha256'));
    expect(source, contains('Get-FileHash'));
    expect(source, contains('Get-CimInstance Win32_Process'));
    expect(source, contains('--coordinator-worker'));
    expect(source, contains('--watchdog\\s+--watch-pid='));
    expect(
        source, contains('Get-NetTCPConnection -State Listen -LocalPort 8790'));
    expect(source, contains('/v1/shutdown'));
  });

  test('helper has no force-kill fallback and never returns the capability',
      () {
    final source = File(
      'scripts/tools/request_kai_graceful_shutdown.ps1',
    ).readAsStringSync();

    expect(source, isNot(contains('Stop-Process')));
    expect(source.toLowerCase(), isNot(contains('taskkill')));
    expect(source, isNot(contains('TerminateProcess')));
    expect(source, contains(r'$control.capability = $null'));
    expect(
      source,
      isNot(contains(r'capability = [string]$control.capability')),
    );
  });
}
