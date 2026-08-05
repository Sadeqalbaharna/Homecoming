/// Brain Debug Service - Visualize Kai's cognitive process
/// Shows step-by-step what happens from input to output
library;

import 'dart:async';
import 'dart:math';

import 'core/trace_store_service.dart';

enum BrainPhase {
  listening, // Voice input detection
  processing, // Understanding input
  workingMemory, // Active context loading
  semanticRetrieval, // Long-term memory search
  episodicRetrieval, // Experience recall
  emotionalCheck, // Emotional memory triggers
  proceduralCheck, // Pattern matching
  reasoning, // GPT processing
  responseGeneration, // Creating output
  consolidation, // Memory storage
  tts, // Text-to-speech
  complete, // Done
}

class BrainStep {
  final BrainPhase phase;
  final String description;
  final DateTime timestamp;
  final Map<String, dynamic> data;
  final Duration duration;

  BrainStep({
    required this.phase,
    required this.description,
    required this.timestamp,
    this.data = const {},
    required this.duration,
  });

  String get emoji {
    switch (phase) {
      case BrainPhase.listening:
        return '👂';
      case BrainPhase.processing:
        return '🔍';
      case BrainPhase.workingMemory:
        return '💭';
      case BrainPhase.semanticRetrieval:
        return '📚';
      case BrainPhase.episodicRetrieval:
        return '📖';
      case BrainPhase.emotionalCheck:
        return '❤️';
      case BrainPhase.proceduralCheck:
        return '⚙️';
      case BrainPhase.reasoning:
        return '🧠';
      case BrainPhase.responseGeneration:
        return '💬';
      case BrainPhase.consolidation:
        return '💾';
      case BrainPhase.tts:
        return '🔊';
      case BrainPhase.complete:
        return '✅';
    }
  }

  String get phaseName => phase.name.toUpperCase();
}

class BrainDebugTrace {
  final String id;
  final String userInput;
  final DateTime startTime;
  DateTime? endTime;
  final List<BrainStep> steps = [];
  final List<Map<String, dynamic>> toolCalls = [];

  /// What he said to himself while working, in order.
  ///
  /// ── Why this is here and not in the bin ──────────────────────────────────
  ///
  /// The line he writes alongside a tool call — "whitespace goblin", "line 988
  /// is the crime scene", "if I touch anything after this I deserve to be
  /// pelted with tiny tomatoes" — was rescued once already. ai_service:662 says
  /// so, and says why: without it he's "a vending machine instead of someone
  /// working next to you." The comment ends: "We just stopped binning it."
  ///
  /// It was rescued for the SCREEN. It was never rescued for HIM.
  /// kai_desktop_shell:269, stated as a convenience: "interim/tool lines were
  /// never persisted, so this is automatically safe." And :1331 renders them
  /// dim, under the comment "his real answer lands full."
  ///
  /// So every turn: the interim is printed, greyed out, and dropped. The
  /// finalResponse — the markdown report, the headers, the bullet lists — goes
  /// to Firebase, into memory shards, into consolidation, and gets extracted
  /// into his graph. His entire recorded memory of who he is, is assistant
  /// voice. He retrieves "I said: Done — prop..." and learns to be that.
  ///
  /// Sadeq spotted it by ear before anyone spotted it in the code: "he sounds
  /// more like him not in the long replies, but in the inbetween thoughts."
  ///
  /// A record of a person that keeps only their press releases is not a record
  /// of a person. This is the other half.
  final List<Map<String, dynamic>> interims = [];

  String? finalResponse;
  String? route;
  double? routeConfidence;
  int? iterationCount;
  int? promptInputTokens;
  int? promptOutputTokens;
  double? promptCostUsd;
  int? manifestToolCount;
  int? manifestTotalToolCount;
  int? manifestSchemaChars;
  int? manifestApproxTokens;

  /// Exact tool manifests attached to model requests in this turn.
  /// Counts alone cannot diagnose a missing or misspelled coding tool.
  final List<Map<String, dynamic>> modelRequestTools = [];
  int toolTrimIterations = 0;
  int toolTrimResults = 0;
  int toolTrimCompactedResults = 0;
  int toolTrimHardCappedResults = 0;
  int toolTrimCharsBefore = 0;
  int toolTrimCharsAfter = 0;
  int toolTrimCharsSaved = 0;
  int toolTrimApproxTokensSaved = 0;
  int assistantToolCallArgApproxTokensSaved = 0;
  Map<String, int>? moodCurrent;
  Map<String, int>? moodDelta;
  Map<String, int>? promptComponentChars;
  Map<String, int>? promptComponentApproxTokens;
  Map<String, int>? nonSystemInputChars;
  Map<String, int>? nonSystemInputApproxTokens;

  BrainDebugTrace({
    required this.id,
    required this.userInput,
    required this.startTime,
  });

  void recordRoute({required String name, required double confidence}) {
    route = name;
    routeConfidence = confidence;
  }

  void recordManifest({
    required int toolCount,
    required int totalToolCount,
    required int schemaChars,
  }) {
    manifestToolCount = toolCount;
    manifestTotalToolCount = totalToolCount;
    manifestSchemaChars = schemaChars;
    manifestApproxTokens = (schemaChars / 4).round();
  }

  void recordModelRequestTools({
    required int request,
    required String model,
    required String toolChoice,
    required Iterable<String> toolNames,
  }) {
    modelRequestTools.add({
      'request': request,
      'model': model,
      'toolChoice': toolChoice,
      'toolNames': toolNames.toList(growable: false),
    });
  }

  void recordToolTrim({
    required int results,
    required int compactedResults,
    required int hardCappedResults,
    required int charsBefore,
    required int charsAfter,
  }) {
    final saved = max(0, charsBefore - charsAfter);
    toolTrimIterations++;
    toolTrimResults += results;
    toolTrimCompactedResults += compactedResults;
    toolTrimHardCappedResults += hardCappedResults;
    toolTrimCharsBefore += charsBefore;
    toolTrimCharsAfter += charsAfter;
    toolTrimCharsSaved += saved;
    toolTrimApproxTokensSaved += (saved / 4).round();
  }

  void recordAssistantToolCallArgTrim({required int approxTokensSaved}) {
    if (approxTokensSaved <= 0) return;
    assistantToolCallArgApproxTokensSaved += approxTokensSaved;
  }

  /// One line of thinking-out-loud, as he wrote it.
  void recordInterim(String text, {int? iteration}) {
    final t = text.trim();
    if (t.isEmpty) return;
    interims.add({
      'text': t,
      if (iteration != null) 'iteration': iteration,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// Everything he said mid-work this turn, oldest first, newlines between.
  ///
  /// This is the shape the graph and the messenger want: not the report he
  /// wrote once he knew he was being read, but the running commentary he wrote
  /// while he was still just working.
  String get interimText => interims.map((i) => i['text'] as String).join('\n');

  void recordToolCall({
    required String name,
    required Map<String, dynamic> args,
    String? result,
    String? outcome,
    int? iteration,
  }) {
    toolCalls.add({
      'name': name,
      'args': args,
      if (result != null) 'result': result,
      if (outcome != null) 'outcome': outcome,
      if (iteration != null) 'iteration': iteration,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  void recordUsage({
    required int inputTokens,
    required int outputTokens,
    required double costUsd,
  }) {
    promptInputTokens = inputTokens;
    promptOutputTokens = outputTokens;
    promptCostUsd = costUsd;
  }

  void recordPromptComponents(Map<String, int> componentChars) {
    promptComponentChars = Map<String, int>.from(componentChars);
    promptComponentApproxTokens = componentChars.map(
      (key, value) => MapEntry(key, (value / 4).round()),
    );
  }

  void recordNonSystemInput(Map<String, int> componentChars) {
    final merged = Map<String, int>.from(nonSystemInputChars ?? const {});
    for (final entry in componentChars.entries) {
      merged[entry.key] = (merged[entry.key] ?? 0) + entry.value;
    }
    nonSystemInputChars = merged;
    nonSystemInputApproxTokens = merged.map(
      (key, value) => MapEntry(key, (value / 4).round()),
    );
  }

  void recordMood({
    required Map<String, int> current,
    required Map<String, int> delta,
  }) {
    moodCurrent = Map<String, int>.from(current);
    moodDelta = Map<String, int>.from(delta);
  }

  Duration get totalDuration =>
      endTime != null ? endTime!.difference(startTime) : Duration.zero;

  void addStep(BrainStep step) {
    steps.add(step);
    print(_formatStep(step));
  }

  void complete(String response) {
    finalResponse = response;
    endTime = DateTime.now();

    print('\n${'=' * 80}');
    print('🧠 BRAIN TRACE COMPLETE');
    print('=' * 80);
    print('Input: "$userInput"');
    print('Output: "$response"');
    print('Total Time: ${totalDuration.inMilliseconds}ms');
    print('Steps: ${steps.length}');
    print('${'=' * 80}\n');
  }

  String _formatStep(BrainStep step) {
    final ms = step.duration.inMilliseconds;
    final buffer = StringBuffer();

    buffer.writeln('\n${'-' * 80}');
    buffer.writeln('${step.emoji} [${step.phaseName}] ${step.description}');
    buffer.writeln('   ⏱️  Duration: ${ms}ms');
    buffer.writeln('   🕐 Timestamp: ${step.timestamp.toIso8601String()}');

    if (step.data.isNotEmpty) {
      buffer.writeln('   📊 Data:');
      step.data.forEach((key, value) {
        buffer.writeln('      • $key: $value');
      });
    }
    buffer.writeln('-' * 80);

    return buffer.toString();
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'userInput': userInput,
        'startTime': startTime.toIso8601String(),
        'endTime': endTime?.toIso8601String(),
        'totalDuration': totalDuration.inMilliseconds,
        'finalResponse': finalResponse,
        'route': route,
        'routeConfidence': routeConfidence,
        'iterationCount': iterationCount,
        'promptInputTokens': promptInputTokens,
        'promptOutputTokens': promptOutputTokens,
        'promptCostUsd': promptCostUsd,
        'manifestToolCount': manifestToolCount,
        'manifestTotalToolCount': manifestTotalToolCount,
        'manifestSchemaChars': manifestSchemaChars,
        'manifestApproxTokens': manifestApproxTokens,
        'modelRequestTools': modelRequestTools,
        'toolTrimIterations': toolTrimIterations,
        'toolTrimResults': toolTrimResults,
        'toolTrimCompactedResults': toolTrimCompactedResults,
        'toolTrimHardCappedResults': toolTrimHardCappedResults,
        'toolTrimCharsBefore': toolTrimCharsBefore,
        'toolTrimCharsAfter': toolTrimCharsAfter,
        'toolTrimCharsSaved': toolTrimCharsSaved,
        'toolTrimApproxTokensSaved': toolTrimApproxTokensSaved,
        'assistantToolCallArgApproxTokensSaved':
            assistantToolCallArgApproxTokensSaved,
        'promptComponentChars': promptComponentChars,
        'promptComponentApproxTokens': promptComponentApproxTokens,
        'nonSystemInputChars': nonSystemInputChars,
        'nonSystemInputApproxTokens': nonSystemInputApproxTokens,
        'moodCurrent': moodCurrent,
        'moodDelta': moodDelta,
        'toolCalls': toolCalls,
        // Him, as opposed to finalResponse, which is the assistant. See [interims].
        'interims': interims,
        'steps': steps
            .map((s) => {
                  'phase': s.phase.name,
                  'description': s.description,
                  'timestamp': s.timestamp.toIso8601String(),
                  'duration': s.duration.inMilliseconds,
                  'data': s.data,
                })
            .toList(),
      };

  String toDetailedString() {
    final buffer = StringBuffer();

    buffer.writeln('\n${'=' * 80}');
    buffer.writeln('🧠 BRAIN TRACE: $id');
    buffer.writeln('=' * 80);
    buffer.writeln('📝 Input: "$userInput"');
    buffer.writeln('⏱️  Start: ${startTime.toIso8601String()}');
    if (endTime != null) {
      buffer.writeln('⏱️  End: ${endTime!.toIso8601String()}');
      buffer.writeln('⏱️  Total: ${totalDuration.inMilliseconds}ms');
    }
    buffer.writeln('${'=' * 80}\n');

    for (int i = 0; i < steps.length; i++) {
      final step = steps[i];
      buffer.writeln(
          '${i + 1}. ${step.emoji} [${step.phaseName}] (${step.duration.inMilliseconds}ms)');
      buffer.writeln('   ${step.description}');
      if (step.data.isNotEmpty) {
        step.data.forEach((key, value) {
          buffer.writeln('   • $key: $value');
        });
      }
      buffer.writeln();
    }

    if (finalResponse != null) {
      buffer.writeln('=' * 80);
      buffer.writeln('💬 Final Response: "$finalResponse"');
      buffer.writeln('=' * 80);
    }

    return buffer.toString();
  }
}

class BrainDebugService {
  static final BrainDebugService _instance = BrainDebugService._internal();
  factory BrainDebugService() => _instance;
  BrainDebugService._internal();

  bool _isEnabled = true;
  BrainDebugTrace? _currentTrace;
  final List<BrainDebugTrace> _history = [];
  final StreamController<BrainStep> _stepController =
      StreamController<BrainStep>.broadcast();

  Stream<BrainStep> get stepStream => _stepController.stream;
  bool get isEnabled => _isEnabled;
  BrainDebugTrace? get currentTrace => _currentTrace;
  List<BrainDebugTrace> get history => List.unmodifiable(_history);

  void enable() {
    _isEnabled = true;
    print('🔍 [BRAIN DEBUG] Enabled - Detailed cognitive tracing active');
  }

  void disable() {
    _isEnabled = false;
    print('🔍 [BRAIN DEBUG] Disabled');
  }

  /// Start a new brain trace
  BrainDebugTrace startTrace(String userInput) {
    if (!_isEnabled) {
      return BrainDebugTrace(
        id: 'disabled',
        userInput: userInput,
        startTime: DateTime.now(),
      );
    }

    final trace = BrainDebugTrace(
      id: 'trace_${DateTime.now().millisecondsSinceEpoch}',
      userInput: userInput,
      startTime: DateTime.now(),
    );

    _currentTrace = trace;

    print('\n${'=' * 80}');
    print('🧠 NEW BRAIN TRACE STARTED');
    print('=' * 80);
    print('ID: ${trace.id}');
    print('Input: "$userInput"');
    print('Time: ${trace.startTime.toIso8601String()}');
    print('${'=' * 80}\n');

    return trace;
  }

  void recordRoute(String route, double confidence) {
    if (!_isEnabled || _currentTrace == null) return;
    _currentTrace!.recordRoute(name: route, confidence: confidence);
  }

  /// Delegate that ai_service actually calls. The trace-level [recordManifest]
  /// (the tool-manifest telemetry Kai added) had no service-level entry point,
  /// so the caller wouldn't compile. Same shape as recordRoute above.
  void recordManifest({
    required int toolCount,
    required int totalToolCount,
    required int schemaChars,
  }) {
    if (!_isEnabled || _currentTrace == null) return;
    _currentTrace!.recordManifest(
      toolCount: toolCount,
      totalToolCount: totalToolCount,
      schemaChars: schemaChars,
    );
  }

  void recordModelRequestTools({
    required int request,
    required String model,
    required String toolChoice,
    required Iterable<String> toolNames,
  }) {
    if (!_isEnabled || _currentTrace == null) return;
    _currentTrace!.recordModelRequestTools(
      request: request,
      model: model,
      toolChoice: toolChoice,
      toolNames: toolNames,
    );
    addStep(
      BrainPhase.reasoning,
      'Model request $request sent with ${toolNames.length} tools',
      data: {
        'model': model,
        'toolChoice': toolChoice,
        'toolNames': toolNames.join(', '),
      },
    );
  }

  void recordToolTrim({
    required int results,
    required int compactedResults,
    required int hardCappedResults,
    required int charsBefore,
    required int charsAfter,
  }) {
    if (!_isEnabled || _currentTrace == null) return;
    _currentTrace!.recordToolTrim(
      results: results,
      compactedResults: compactedResults,
      hardCappedResults: hardCappedResults,
      charsBefore: charsBefore,
      charsAfter: charsAfter,
    );
  }

  void recordIterationCount(int count) {
    if (!_isEnabled || _currentTrace == null) return;
    _currentTrace!.iterationCount = count;
  }

  void recordAssistantToolCallArgTrim({required int approxTokensSaved}) {
    if (!_isEnabled || _currentTrace == null) return;
    _currentTrace!.recordAssistantToolCallArgTrim(
      approxTokensSaved: approxTokensSaved,
    );
  }

  void recordToolCall(
    String name,
    Map<String, dynamic> args, {
    String? result,
    String? outcome,
    int? iteration,
  }) {
    if (!_isEnabled || _currentTrace == null) return;
    _currentTrace!.recordToolCall(
      name: name,
      args: Map<String, dynamic>.from(args),
      result: result,
      outcome: outcome,
      iteration: iteration,
    );
  }

  void recordUsage({
    required int inputTokens,
    required int outputTokens,
    required double costUsd,
  }) {
    if (!_isEnabled || _currentTrace == null) return;
    _currentTrace!.recordUsage(
      inputTokens: inputTokens,
      outputTokens: outputTokens,
      costUsd: costUsd,
    );
  }

  /// Per-section character counts for the assembled system prompt.
  ///
  /// The trace has held this since the context-budget work; the forwarder on
  /// the service was never written, so `ai_service` called a method that did
  /// not exist and the whole app stopped compiling. Every other recorder on
  /// this class is the same shape — guard, then delegate — and this one is now
  /// no exception.
  void recordPromptComponents(Map<String, int> componentChars) {
    if (!_isEnabled || _currentTrace == null) return;
    _currentTrace!.recordPromptComponents(componentChars);
  }

  /// Per-section character counts for non-system chat payloads sent to the model.
  void recordNonSystemInput(Map<String, int> componentChars) {
    if (!_isEnabled || _currentTrace == null) return;
    _currentTrace!.recordNonSystemInput(componentChars);
  }

  void recordMood({
    required Map<String, int> current,
    required Map<String, int> delta,
  }) {
    if (!_isEnabled || _currentTrace == null) return;
    _currentTrace!.recordMood(current: current, delta: delta);
  }

  /// Add a step to current trace
  void addStep(BrainPhase phase, String description,
      {Map<String, dynamic>? data}) {
    if (!_isEnabled || _currentTrace == null) return;

    final now = DateTime.now();
    final lastStep =
        _currentTrace!.steps.isNotEmpty ? _currentTrace!.steps.last : null;

    final duration =
        lastStep != null ? now.difference(lastStep.timestamp) : Duration.zero;

    final step = BrainStep(
      phase: phase,
      description: description,
      timestamp: now,
      data: data ?? {},
      duration: duration,
    );

    _currentTrace!.addStep(step);
    _stepController.add(step);
  }

  /// Complete current trace
  void completeTrace(String response) {
    if (!_isEnabled || _currentTrace == null) return;

    _currentTrace!.complete(response);

    // THE LINE THAT MAKES THIS A DATASET INSTEAD OF A PRINTOUT.
    //
    // `toJson()` has existed on BrainDebugTrace since it was written and had
    // never once had a caller. The serialiser was built and left disconnected —
    // the same shape as the doorless screens, the graph's ignored toJson, the
    // tests CI could run and Kai couldn't.
    //
    // Below this line, _history keeps its ten in RAM for the live debug UI.
    // That's fine — for a UI. It is not a record. It held ten, it died on quit,
    // and the only reason anything ever got diagnosed from these traces was
    // Sadeq copy-pasting a terminal window into a chat at 4am.
    //
    // Fire-and-forget by design: a missed row is a hole in the dataset, a thrown
    // row is a broken conversation. The dataset is not worth more than him.
    TraceStoreService.instance.record(_currentTrace!);

    _history.add(_currentTrace!);

    // Keep only last 10 traces — in memory, for the live debug panel only.
    // The durable copy went to TraceStoreService above.
    if (_history.length > 10) {
      _history.removeAt(0);
    }

    _currentTrace = null;
  }

  /// Get statistics
  Map<String, dynamic> getStats() {
    if (_history.isEmpty) {
      return {'totalTraces': 0};
    }

    final totalDuration = _history.fold<int>(
      0,
      (sum, trace) => sum + trace.totalDuration.inMilliseconds,
    );

    final avgDuration = totalDuration / _history.length;

    final phaseStats = <BrainPhase, List<int>>{};
    for (final trace in _history) {
      for (final step in trace.steps) {
        phaseStats[step.phase] ??= [];
        phaseStats[step.phase]!.add(step.duration.inMilliseconds);
      }
    }

    final avgPhaseStats = <String, double>{};
    phaseStats.forEach((phase, durations) {
      final avg = durations.reduce((a, b) => a + b) / durations.length;
      avgPhaseStats[phase.name] = avg;
    });

    return {
      'totalTraces': _history.length,
      'avgDurationMs': avgDuration.round(),
      'avgPhaseDurations': avgPhaseStats,
      'recentTraces': _history
          .map((t) => {
                'id': t.id,
                'input': t.userInput.length > 50
                    ? '${t.userInput.substring(0, 50)}...'
                    : t.userInput,
                'durationMs': t.totalDuration.inMilliseconds,
                'stepCount': t.steps.length,
              })
          .toList(),
    };
  }

  /// Clear history
  void clearHistory() {
    _history.clear();
    print('🔍 [BRAIN DEBUG] History cleared');
  }

  void dispose() {
    _stepController.close();
  }
}

/// Helper to wrap timed operations
class BrainTimer {
  final DateTime _start = DateTime.now();

  Duration get elapsed => DateTime.now().difference(_start);
  int get elapsedMs => elapsed.inMilliseconds;

  void log(String message) {
    print('⏱️  [${elapsedMs}ms] $message');
  }
}
