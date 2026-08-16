import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Windows runner rejects a second visible Desktop room', () {
    final source = File('windows/runner/main.cpp').readAsStringSync();

    expect(source, contains(r'Local\\KaiHomecomingDesktopRoom'));
    expect(source, contains('ERROR_ALREADY_EXISTS'));
    expect(source, contains('desktop_room_mutex'));
    expect(source, contains('return EXIT_SUCCESS'));
  });

  test('Desktop room mutex remains separate from the Core coordinator mutex',
      () {
    final source = File('windows/runner/main.cpp').readAsStringSync();

    expect(source, contains(r'Local\\KaiHomecomingCentralCoordinator'));
    expect(source, contains(r'Local\\KaiHomecomingDesktopRoom'));
  });
}
