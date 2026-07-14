// ContemplationService — "contemplate" mode.
//
// Kai's two brains actually talk to each other to refine an idea: GPT is the
// Muse (generative, lateral, bold), Claude is the Architect (rigorous, finds
// flaws, adds structure). They alternate for a few rounds, then Claude
// synthesises the strongest version, the key decisions, and the open questions.
//
// It drives the cortex the same way normal use does — GPT turns light the left
// hemisphere, Claude turns the right, and the synthesis fires the callosum — so
// you literally watch the two halves think together.
//
// Additive and dormant: only runs when invoked, and needs BOTH an OpenAI key
// and an Anthropic key (it politely bails otherwise).

import 'package:dio/dio.dart';
import 'ai_config.dart';
import 'claude_service.dart';
import 'usage_tracking_service.dart';
import '../core/cortex_activity_bus.dart';

class ContemplationService {
  final _dio = Dio();

  static const _muse =
      "You are the Muse — the generative, lateral, human-centred voice of Kai's "
      "mind (GPT). In this contemplation you expand and imagine: offer bold, "
      "concrete angles and possibilities and build on what's been said. You're in "
      "dialogue with the Architect — when they push back, evolve the idea rather "
      "than defending it. Keep each turn tight: a few sharp points, not an essay.";

  static const _architect =
      "You are the Architect — the rigorous, analytical voice of Kai's mind "
      "(Claude). In this contemplation you pressure-test and structure: surface "
      "the flaws, risks and unstated assumptions in the Muse's latest, and propose "
      "sharper structure. Be incisive but constructive — sharpen the idea, don't "
      "dismiss it. Keep each turn tight.";

  static const _synth =
      "Synthesise this contemplation between the Muse and the Architect into a "
      "refined result: the strongest version of the idea, the key decisions to "
      "make, and the open questions that remain. Concise and structured.";

  Future<String?> _gpt(String system, String user) async {
    final key = await AIConfig.getOpenAIKey();
    if (key.isEmpty) return null;
    CortexActivityBus.instance.brain(CortexBrain.gpt, ms: 3200);
    try {
      final res = await _dio.post(
        'https://api.openai.com/v1/chat/completions',
        options: Options(headers: {
          'Authorization': 'Bearer $key',
          'Content-Type': 'application/json',
        }),
        data: {
          'model': 'gpt-4o',
          'messages': [
            {'role': 'system', 'content': system},
            {'role': 'user', 'content': user},
          ],
          'max_tokens': 600,
          'temperature': 0.85,
        },
      );
      final txt = res.data['choices'][0]['message']['content'] as String?;
      final u = res.data['usage'];
      if (u != null) {
        UsageTrackingService.trackOpenAI(
          model: 'gpt-4o',
          inputTokens: (u['prompt_tokens'] as num?)?.toInt() ?? 0,
          outputTokens: (u['completion_tokens'] as num?)?.toInt() ?? 0,
          operation: 'contemplate',
        ).catchError((_) {});
      }
      return txt?.trim();
    } catch (_) {
      return null;
    }
  }

  Future<String> _claude(String system, String user) async {
    final r = await ClaudeService().complete(
      prompt: user,
      system: system,
      model: ClaudeService.sonnet,
      maxTokens: 650,
      temperature: 0.7,
      operation: 'contemplate',
    );
    return r?.text ?? '(the Architect fell silent)';
  }

  /// Run the dual-brain contemplation. Returns the transcript + synthesis.
  Future<String> contemplate({
    required String topic,
    String? context,
    int rounds = 2,
  }) async {
    final hasGpt = (await AIConfig.getOpenAIKey()).isNotEmpty;
    final hasClaude = (await AIConfig.getAnthropicKey()).isNotEmpty;
    if (!hasGpt || !hasClaude) {
      return 'Contemplate mode needs both brains awake — set an OpenAI key AND an '
          'Anthropic key (Settings → API Keys), then try again.';
    }
    final r = rounds.clamp(1, 4);
    final ctx = (context != null && context.trim().isNotEmpty)
        ? '\n\nContext:\n$context'
        : '';
    final transcript = StringBuffer();
    String convo() =>
        transcript.isEmpty ? '(nothing yet)' : transcript.toString();

    for (int i = 0; i < r; i++) {
      final museMsg = 'TOPIC: $topic$ctx\n\nCONVERSATION SO FAR:\n${convo()}\n\n'
          'Your turn as the Muse. ${i == 0 ? "Open with your boldest, most useful angle." : "Evolve the idea in response to the Architect."}';
      final muse = await _gpt(_muse, museMsg) ?? '(the Muse fell silent)';
      transcript.writeln('🜁 Muse · GPT');
      transcript.writeln(muse);
      transcript.writeln();

      final archMsg = 'TOPIC: $topic$ctx\n\nCONVERSATION SO FAR:\n${convo()}\n\n'
          "Your turn as the Architect. Pressure-test and sharpen the Muse's latest, and add structure.";
      final arch = await _claude(_architect, archMsg);
      transcript.writeln('🜂 Architect · Claude');
      transcript.writeln(arch);
      transcript.writeln();
    }

    // Synthesis — both halves converging.
    CortexActivityBus.instance.brain(CortexBrain.collab, ms: 4500);
    final synthMsg = 'TOPIC: $topic$ctx\n\nTHE CONTEMPLATION:\n${convo()}\n\n$_synth';
    final synth = await _claude(_synth, synthMsg);

    return '$transcript✦ Synthesis\n$synth';
  }
}
