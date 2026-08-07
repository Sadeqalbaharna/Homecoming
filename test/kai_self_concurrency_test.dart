import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('awakening is an atomic increment and never a whole-self rewrite', () {
    final source =
        File('lib/services/core/kai_self_service.dart').readAsStringSync();
    final awaken = source.substring(
      source.indexOf('Future<KaiSelf> awaken'),
      source.indexOf('Future<void> setFocus'),
    );
    expect(awaken, contains("'.sv': {'increment': 1}"));
    expect(awaken, isNot(contains("'awakenings': current.awakenings + 1")));
    expect(awaken, contains('final fresh = await ref.get()'));
  });
}
