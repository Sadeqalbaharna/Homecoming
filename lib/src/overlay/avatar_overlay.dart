import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lottie/lottie.dart';
import '../features/voice/voice_player.dart'; // for mouthOpenProvider if needed

class AvatarOverlay extends ConsumerStatefulWidget {
  const AvatarOverlay({super.key});
  @override
  ConsumerState<AvatarOverlay> createState() => _AvatarOverlayState();
}

class _AvatarOverlayState extends ConsumerState<AvatarOverlay> {
  @override
  Widget build(BuildContext context) {
    final mouth = ref.watch(mouthOpenProvider); // 0..1
    return Stack(
      alignment: Alignment.bottomRight,
      children: [
        // your animated avatar
        SizedBox(
          width: 220, // adjust size
          height: 220,
          child: Lottie.asset(
            'assets/avatar/kai_talk.json',
            fit: BoxFit.contain,
          ),
        ),

        // Optional: tiny mouth overlay scale (if you use it)
        // Positioned(...) add subtle transform based on `mouth`.
      ],
    );
  }
}
