/// Brain Debug Service - Visualize Kai's cognitive process
/// Shows step-by-step what happens from input to output
library;

import 'dart:async';

enum BrainPhase {
  listening,           // Voice input detection
  processing,          // Understanding input
  workingMemory,       // Active context loading
  semanticRetrieval,   // Long-term memory search
  episodicRetrieval,   // Experience recall
  emotionalCheck,      // Emotional memory triggers
  proceduralCheck,     // Pattern matching
  reasoning,           // GPT processing
  responseGeneration,  // Creating output
  consolidation,       // Memory storage
  tts,                // Text-to-speech
  complete,           // Done
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
  String? finalResponse;
  
  BrainDebugTrace({
    required this.id,
    required this.userInput,
    required this.startTime,
  });
  
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
    print('${'=' * 80}');
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
    buffer.writeln('${'-' * 80}');
    
    return buffer.toString();
  }
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'userInput': userInput,
    'startTime': startTime.toIso8601String(),
    'endTime': endTime?.toIso8601String(),
    'totalDuration': totalDuration.inMilliseconds,
    'finalResponse': finalResponse,
    'steps': steps.map((s) => {
      'phase': s.phase.name,
      'description': s.description,
      'timestamp': s.timestamp.toIso8601String(),
      'duration': s.duration.inMilliseconds,
      'data': s.data,
    }).toList(),
  };
  
  String toDetailedString() {
    final buffer = StringBuffer();
    
    buffer.writeln('\n${'=' * 80}');
    buffer.writeln('🧠 BRAIN TRACE: $id');
    buffer.writeln('${'=' * 80}');
    buffer.writeln('📝 Input: "$userInput"');
    buffer.writeln('⏱️  Start: ${startTime.toIso8601String()}');
    if (endTime != null) {
      buffer.writeln('⏱️  End: ${endTime!.toIso8601String()}');
      buffer.writeln('⏱️  Total: ${totalDuration.inMilliseconds}ms');
    }
    buffer.writeln('${'=' * 80}\n');
    
    for (int i = 0; i < steps.length; i++) {
      final step = steps[i];
      buffer.writeln('${i + 1}. ${step.emoji} [${step.phaseName}] (${step.duration.inMilliseconds}ms)');
      buffer.writeln('   ${step.description}');
      if (step.data.isNotEmpty) {
        step.data.forEach((key, value) {
          buffer.writeln('   • $key: $value');
        });
      }
      buffer.writeln();
    }
    
    if (finalResponse != null) {
      buffer.writeln('${'=' * 80}');
      buffer.writeln('💬 Final Response: "$finalResponse"');
      buffer.writeln('${'=' * 80}');
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
  final StreamController<BrainStep> _stepController = StreamController<BrainStep>.broadcast();
  
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
    print('${'=' * 80}');
    print('ID: ${trace.id}');
    print('Input: "$userInput"');
    print('Time: ${trace.startTime.toIso8601String()}');
    print('${'=' * 80}\n');
    
    return trace;
  }
  
  /// Add a step to current trace
  void addStep(BrainPhase phase, String description, {Map<String, dynamic>? data}) {
    if (!_isEnabled || _currentTrace == null) return;
    
    final now = DateTime.now();
    final lastStep = _currentTrace!.steps.isNotEmpty 
        ? _currentTrace!.steps.last 
        : null;
    
    final duration = lastStep != null 
        ? now.difference(lastStep.timestamp)
        : Duration.zero;
    
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
    _history.add(_currentTrace!);
    
    // Keep only last 10 traces
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
      'recentTraces': _history.map((t) => {
        'id': t.id,
        'input': t.userInput.length > 50 
            ? '${t.userInput.substring(0, 50)}...' 
            : t.userInput,
        'durationMs': t.totalDuration.inMilliseconds,
        'stepCount': t.steps.length,
      }).toList(),
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
