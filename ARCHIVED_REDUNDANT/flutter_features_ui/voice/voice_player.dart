// lib/src/features/voice/voice_player.dart

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:just_audio/just_audio.dart';

final mouthOpenProvider = StateProvider<double>((_) => 0.0);

Future<void> playBytes(WidgetRef ref, Uint8List mp3Bytes) async {
  final session = await AudioSession.instance;
  await session.configure(const AudioSessionConfiguration.speech());

  final player = AudioPlayer();
  final dataUri = Uri.dataFromBytes(mp3Bytes, mimeType: 'audio/mpeg').toString();
  await player.setUrl(dataUri);
  await player.play();

  final notifier = ref.read(mouthOpenProvider.notifier);
  Timer? t;
  const tick = Duration(milliseconds: 45);
  var phase = 0.0;

  void stopAnim() {
    t?.cancel();
    notifier.state = 0.0;
    player.dispose();
  }

  t = Timer.periodic(tick, (_) {
    if (!player.playing) return;
    phase += 0.55 + (DateTime.now().millisecond % 3) * 0.02;
    final v = (0.5 * (1 + math.cos(phase))) * 0.85;
    notifier.state = v.clamp(0.0, 1.0);
  });

  late final StreamSubscription<PlayerState> sub;
  sub = player.playerStateStream.listen((s) {
    if (s.processingState == ProcessingState.completed ||
        (s.processingState == ProcessingState.idle && !s.playing)) {
      stopAnim();
      sub.cancel();
    }
  });

  unawaited(player.processingStateStream.firstWhere(
    (st) => st == ProcessingState.completed,
  ).then((_) {
    stopAnim();
    sub.cancel();
  }));
}
