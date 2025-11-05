import 'dart:convert';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'services/voice_activation_service.dart';

class VoiceController {
  final _player = AudioPlayer()..setReleaseMode(ReleaseMode.stop);

  VoiceController() {
    // Listen for player state changes to pause voice activation
    _player.onPlayerStateChanged.listen((state) {
      if (state == PlayerState.playing) {
        print('🔇 [VoiceController] Audio playing - PAUSING voice activation');
        VoiceActivationService().pause();
      } else if (state == PlayerState.stopped || state == PlayerState.completed) {
        print('🔊 [VoiceController] Audio stopped - RESUMING voice activation');
        VoiceActivationService().resume();
      }
    });
  }

  Future<void> playBase64(String b64, {double volume = 1.0, double rate = 1.0}) async {
    if (b64.isEmpty) return;
    final Uint8List bytes = base64Decode(b64);
    await _player.stop();
    await _player.setVolume(volume);
    await _player.setPlaybackRate(rate);
    await _player.play(BytesSource(bytes)); // plays from memory
  }

  Future<void> stop() => _player.stop();
  Future<void> dispose() => _player.dispose();
}
