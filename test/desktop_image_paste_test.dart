import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/screens/kai_desktop_shell.dart';
import 'package:image/image.dart' as image_lib;

void main() {
  group('desktop image paste normalization', () {
    test('keeps supported PNG bytes unchanged', () {
      final png = Uint8List.fromList(image_lib.encodePng(
        image_lib.Image(width: 1, height: 1)..setPixelRgb(0, 0, 255, 0, 0),
      ));

      final normalized = normalizeDesktopVisionImageForTest(png);

      expect(normalized, same(png));
      expect(normalized!.take(8), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
    });

    test('re-encodes Windows clipboard BMP bytes into PNG', () {
      final bmp = Uint8List.fromList(image_lib.encodeBmp(
        image_lib.Image(width: 1, height: 1)..setPixelRgb(0, 0, 0, 255, 0),
      ));

      final normalized = normalizeDesktopVisionImageForTest(bmp);

      expect(normalized, isNotNull);
      expect(normalized!.take(8), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
      expect(normalized.take(2), isNot([0x42, 0x4D]));
    });

    test('rejects non-image clipboard bytes', () {
      final normalized = normalizeDesktopVisionImageForTest(
        Uint8List.fromList('not an image'.codeUnits),
      );

      expect(normalized, isNull);
    });
  });
}
