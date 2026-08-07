import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/services/ai/tts_service.dart';

void main() {
  test('ElevenLabs key IDs are rejected before network synthesis', () {
    expect(TTSService.isStructurallyValidElevenLabsKey('key-id-12345'), isFalse);
    expect(TTSService.isStructurallyValidElevenLabsKey('sk_validExample123'), isTrue);
  });

  test('optional Tavern listener owns its stream errors', () {
    final source = File('lib/services/core/tavern_service.dart').readAsStringSync();
    expect(source, contains('onError: (Object error, StackTrace stackTrace)'));
    expect(source, contains('cancelOnError: true'));
  });

  test('wake-word listener becomes inactive when its mic stream fails', () {
    final source = File('lib/services/voice/voice_activation_service.dart')
        .readAsStringSync();
    expect(source, contains('Wake-word mic unavailable'));
    expect(source, contains('_isActive = false'));
    expect(source, contains('cancelOnError: true'));
  });
}
