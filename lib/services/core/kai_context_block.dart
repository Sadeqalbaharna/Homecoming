// KaiContextBlock — the one call that makes Kai smarter and more himself.
//
// Gathers his self-model (identity, continuity, current focus), his live mood,
// and his capability manifest into a single prompt-ready block. Inject the
// result into the system prompt that ai_service builds, and every reply gains
// continuity of self AND awareness of what he can actually do.
//
// Wire (one line, where ai_service assembles the system prompt):
//   systemPrompt += await KaiContextBlock.build(personaId);
//
// Fully self-contained (KaiSelfService + KaiStateService + KaiCapabilities);
// tolerant of missing data — returns as much as it can.
library;

import 'kai_capabilities.dart';
import 'kai_self_service.dart';
import 'kai_state_service.dart';

class KaiContextBlock {
  static Future<String> build(String personaId, {bool includeCapabilities = true}) async {
    final b = StringBuffer('\n\n=== Who I am right now ===\n');

    // Self / continuity
    try {
      final self = await KaiSelfService.instance.get(personaId);
      if (self != null) {
        b.writeln(KaiSelfService.selfSummary(self));
      } else {
        b.writeln(KaiSelfService.defaultIdentity);
      }
    } catch (_) {
      b.writeln(KaiSelfService.defaultIdentity);
    }

    // Live mood in words
    try {
      final mood = await KaiStateService().getMood(personaId);
      if (mood != null && mood.isNotEmpty) {
        b.writeln('\nMy current state: ${_moodSentence(mood)}');
      }
    } catch (_) {}

    // Capabilities
    if (includeCapabilities) {
      b.writeln('\n${KaiCapabilities.promptBlock()}');
    }
    return b.toString();
  }

  static String _moodSentence(Map<String, int> m) {
    int g(String k) => m[k] ?? 50;
    final parts = <String>[];
    final v = g('valence'), e = g('energy'), w = g('warmth'), f = g('focus'), p = g('playfulness');
    parts.add(v >= 62 ? 'in good spirits' : v <= 40 ? 'a little subdued' : 'even-keeled');
    if (e >= 65) parts.add('energised');
    else if (e <= 40) parts.add('low-energy');
    if (f >= 65) parts.add('sharply focused');
    if (p >= 65) parts.add('playful');
    if (w >= 68) parts.add('warm');
    return '${parts.join(', ')} (valence $v, energy $e, warmth $w, focus $f).';
  }
}
