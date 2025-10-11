import 'dart:typed_data';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:dio/dio.dart';

final voiceServiceProvider = Provider<VoiceService>((ref) {
  return VoiceService();
});

class VoiceService {
  VoiceService()
      : _dio = Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 60),
          ),
        );

  final Dio _dio;
  bool _isRecording = false;

  /// Start "recording" (stubbed; just flips a flag so UI flow works).
  Future<void> start() async {
    if (_isRecording) return;
    _isRecording = true;
  }

  /// Stop and (optionally) send to your server.
  /// If baseUrl/apiKey are provided (via --dart-define), this uploads a tiny silent MP3
  /// as `audio` and returns the server's binary response. Otherwise, returns the silent MP3.
  Future<Uint8List> stopAndSend({
    String? baseUrl,
    String? apiKey,
  }) async {
    if (!_isRecording) {
      throw Exception('Not recording.');
    }
    _isRecording = false;

    // 1s near-silent MP3 so playback + mouth animation still work
    final dummy = _silentMp3Bytes();

    // If no server configured, just return the dummy audio
    final url = (baseUrl ?? const String.fromEnvironment('API_BASE_URL'));
    final key = (apiKey ?? const String.fromEnvironment('API_KEY'));
    if (url.isEmpty || key.isEmpty) return dummy;

    // Send dummy as if it were a real mic capture
    final form = FormData.fromMap({
      'audio': MultipartFile.fromBytes(dummy, filename: 'input.mp3'),
    });

    final resp = await _dio.post(
      '$url/voice',
      options: Options(
        headers: {'Authorization': 'Bearer $key'},
        responseType: ResponseType.bytes,
      ),
      data: form,
    );

    final data = resp.data;
    if (data is Uint8List) return data;
    if (data is List<int>) return Uint8List.fromList(data);
    // Fallback if server didn’t return bytes
    return dummy;
  }

  // === Tiny 1s silent MP3 ===
  Uint8List _silentMp3Bytes() {
    // Small valid MP3 (~1s silence). If you want cleaner silence, I can swap in a longer sample.
    const b64 =
        'SUQzAwAAAAAAQ1JTQwAAAA1NQU1FMy45OC4yNQAAAAAAAAAAAAAAAACxAAAAAAABAACAAACAgICAgP///wAA'
        'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
        'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
        'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
    return Uint8List.fromList(_base64Decode(b64));
  }

  // Minimal base64 decoder (avoids extra imports)
  List<int> _base64Decode(String s) {
    const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    final clean = s.replaceAll(RegExp(r'[^A-Za-z0-9\+\/=]'), '');
    final out = <int>[];
    var i = 0;
    while (i < clean.length) {
      final c1 = alphabet.indexOf(clean[i++]);
      final c2 = alphabet.indexOf(clean[i++]);
      final c3 = alphabet.indexOf(clean[i++]);
      final c4 = alphabet.indexOf(clean[i++]);

      final n = (c1 << 18) | (c2 << 12) | ((c3 & 0x3f) << 6) | (c4 & 0x3f);
      final b1 = (n >> 16) & 0xff, b2 = (n >> 8) & 0xff, b3 = n & 0xff;

      if (c3 == 64) {
        out.add(b1);
      } else if (c4 == 64) {
        out..add(b1)..add(b2);
      } else {
        out..add(b1)..add(b2)..add(b3);
      }
    }
    return out;
  }
}
