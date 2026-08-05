import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('desktop shell ignores blank follow-up interrupts instead of echoing them', () {
    final source = File('lib/screens/kai_desktop_shell.dart').readAsStringSync();

    expect(source, contains('if (text.isEmpty) return;'));
    expect(source, isNot(contains("text.isEmpty ? '[follow-up]' : text")));
    expect(source, isNot(contains("_ChatMsg(true, '[follow-up]')")));
  });

  test('desktop shell clears queued blank follow-ups without sending them', () {
    final source = File('lib/screens/kai_desktop_shell.dart').readAsStringSync();

    expect(source, contains('if (followUp != null)'));
    expect(source, contains('_queuedFollowUp = null;'));
    expect(source, contains('if (followUp.trim().isNotEmpty && mounted)'));
    expect(source, isNot(contains('if (followUp != null && followUp.trim().isNotEmpty)')));
  });
}
