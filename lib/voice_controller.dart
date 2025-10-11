import 'dart:convert';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';

class VoiceController {
  final _player = AudioPlayer()..setReleaseMode(ReleaseMode.stop);

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
