import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'voice_controller.dart';

final voiceControllerProvider = Provider<VoiceController>((ref) {
  final vc = VoiceController();
  ref.onDispose(vc.dispose);
  return vc;
});
