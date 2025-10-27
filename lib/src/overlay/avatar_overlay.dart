import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class AvatarOverlay extends ConsumerStatefulWidget {
  const AvatarOverlay({super.key});
  @override
  ConsumerState<AvatarOverlay> createState() => _AvatarOverlayState();
}

class _AvatarOverlayState extends ConsumerState<AvatarOverlay> {
  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.bottomRight,
      children: [
        // Idle animation GIF
        SizedBox(
          width: 220, // adjust size
          height: 220,
          child: Image.asset(
            'assets/avatar/idle.gif',
            fit: BoxFit.contain,
          ),
        ),
      ],
    );
  }
}
