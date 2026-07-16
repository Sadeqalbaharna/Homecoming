import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Homecoming desktop shell source contains the real Kai project surface', () {
    final source = File('lib/screens/kai_desktop_shell.dart').readAsStringSync();

    expect(source, contains('KaiDesktopShell'));
    expect(source, contains('KAI SMARTER PROJECT'));
    expect(source, contains('_smartProjectCard'));
  });
}
