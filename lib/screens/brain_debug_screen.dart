import 'package:flutter/material.dart';
import '../services/brain_debug_service.dart';

/// Screen to visualize Kai's cognitive process in real-time
/// Shows all brain phases from listening → processing → memory → reasoning → response
class BrainDebugScreen extends StatefulWidget {
  const BrainDebugScreen({Key? key}) : super(key: key);

  @override
  State<BrainDebugScreen> createState() => _BrainDebugScreenState();
}

class _BrainDebugScreenState extends State<BrainDebugScreen> {
  final _debugService = BrainDebugService();
  BrainDebugTrace? _currentTrace;
  List<BrainDebugTrace> _history = [];

  @override
  void initState() {
    super.initState();
    _loadHistory();
    
    // Listen to real-time brain steps
    _debugService.stepStream.listen((step) {
      setState(() {
        // Update current trace display
      });
    });
  }

  void _loadHistory() {
    setState(() {
      _history = _debugService.history;
      if (_history.isNotEmpty) {
        _currentTrace = _history.first;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🧠 Brain Debug'),
        actions: [
          IconButton(
            icon: Icon(_debugService.isEnabled ? Icons.pause : Icons.play_arrow),
            onPressed: () {
              setState(() {
                if (_debugService.isEnabled) {
                  _debugService.disable();
                } else {
                  _debugService.enable();
                }
              });
            },
            tooltip: _debugService.isEnabled ? 'Disable Debug' : 'Enable Debug',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadHistory,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _debugService.isEnabled
          ? Column(
              children: [
                // Statistics card
                _buildStatsCard(),
                const SizedBox(height: 8),
                // Trace history selector
                _buildHistorySelector(),
                const SizedBox(height: 8),
                // Current trace details
                Expanded(
                  child: _currentTrace != null
                      ? _buildTraceDetails(_currentTrace!)
                      : const Center(
                          child: Text(
                            'No traces yet\nSend a message to Kai to see brain activity',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                ),
              ],
            )
          : Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.psychology_outlined, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text(
                    'Brain Debug Disabled',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Enable to see Kai\'s cognitive process',
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () {
                      setState(() {
                        _debugService.enable();
                      });
                    },
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Enable Debug'),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildStatsCard() {
    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildStatItem('Total Traces', '${_history.length}'),
            _buildStatItem('Current Trace', _currentTrace != null ? '${_currentTrace!.steps.length} steps' : 'None'),
            _buildStatItem('Last Duration', _currentTrace != null 
                ? '${_currentTrace!.totalDuration.inMilliseconds / 1000}s' 
                : 'N/A'),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ],
    );
  }

  Widget _buildHistorySelector() {
    if (_history.isEmpty) return const SizedBox.shrink();
    
    return Container(
      height: 60,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemCount: _history.length,
        itemBuilder: (context, index) {
          final trace = _history[index];
          final isSelected = trace == _currentTrace;
          return GestureDetector(
            onTap: () {
              setState(() {
                _currentTrace = trace;
              });
            },
            child: Container(
              width: 120,
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isSelected ? Colors.blue : Colors.grey[200],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    trace.userInput.length > 20 
                        ? '${trace.userInput.substring(0, 20)}...' 
                        : trace.userInput,
                    style: TextStyle(
                      fontSize: 12,
                      color: isSelected ? Colors.white : Colors.black87,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${trace.totalDuration.inMilliseconds / 1000}s',
                    style: TextStyle(
                      fontSize: 10,
                      color: isSelected ? Colors.white70 : Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTraceDetails(BrainDebugTrace trace) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Trace header
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.input, size: 16),
                      const SizedBox(width: 8),
                      const Text('Input:', style: TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  Text(trace.userInput, style: const TextStyle(fontSize: 14)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.output, size: 16),
                      const SizedBox(width: 8),
                      const Text('Output:', style: TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  Text(trace.finalResponse ?? 'Processing...', style: const TextStyle(fontSize: 14)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.timer, size: 16),
                      const SizedBox(width: 8),
                      Text(
                        'Duration: ${trace.totalDuration.inMilliseconds / 1000}s',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Phase timeline
          const Padding(
            padding: EdgeInsets.all(8.0),
            child: Text(
              'Cognitive Process Timeline',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          ...trace.steps.asMap().entries.map((entry) {
            final index = entry.key;
            final step = entry.value;
            final isLast = index == trace.steps.length - 1;
            return _buildStepItem(step, isLast);
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildStepItem(BrainStep step, bool isLast) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Timeline indicator
        Column(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: _getPhaseColor(step.phase),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  step.emoji,
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 40,
                color: Colors.grey[300],
              ),
          ],
        ),
        const SizedBox(width: 12),
        // Step details
        Expanded(
          child: Card(
            margin: const EdgeInsets.only(bottom: 8, right: 8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _getPhaseLabel(step.phase),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.grey[200],
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${step.duration.inMilliseconds}ms',
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    step.description,
                    style: const TextStyle(fontSize: 12, color: Colors.black87),
                  ),
                  if (step.data.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _formatData(step.data),
                        style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Color _getPhaseColor(BrainPhase phase) {
    switch (phase) {
      case BrainPhase.listening:
        return Colors.blue[300]!;
      case BrainPhase.processing:
        return Colors.purple[300]!;
      case BrainPhase.workingMemory:
        return Colors.orange[300]!;
      case BrainPhase.semanticRetrieval:
        return Colors.green[300]!;
      case BrainPhase.episodicRetrieval:
        return Colors.teal[300]!;
      case BrainPhase.emotionalCheck:
        return Colors.pink[300]!;
      case BrainPhase.proceduralCheck:
        return Colors.indigo[300]!;
      case BrainPhase.reasoning:
        return Colors.deepPurple[300]!;
      case BrainPhase.responseGeneration:
        return Colors.amber[300]!;
      case BrainPhase.consolidation:
        return Colors.lightGreen[300]!;
      case BrainPhase.tts:
        return Colors.cyan[300]!;
      case BrainPhase.complete:
        return Colors.green[400]!;
    }
  }

  String _getPhaseLabel(BrainPhase phase) {
    switch (phase) {
      case BrainPhase.listening:
        return 'Listening';
      case BrainPhase.processing:
        return 'Processing Input';
      case BrainPhase.workingMemory:
        return 'Working Memory';
      case BrainPhase.semanticRetrieval:
        return 'Semantic Retrieval';
      case BrainPhase.episodicRetrieval:
        return 'Episodic Retrieval';
      case BrainPhase.emotionalCheck:
        return 'Emotional Check';
      case BrainPhase.proceduralCheck:
        return 'Procedural Check';
      case BrainPhase.reasoning:
        return 'Reasoning (GPT)';
      case BrainPhase.responseGeneration:
        return 'Response Generation';
      case BrainPhase.consolidation:
        return 'Memory Consolidation';
      case BrainPhase.tts:
        return 'Text-to-Speech';
      case BrainPhase.complete:
        return 'Complete';
    }
  }

  String _formatData(Map<String, dynamic> data) {
    final buffer = StringBuffer();
    data.forEach((key, value) {
      buffer.writeln('$key: $value');
    });
    return buffer.toString().trim();
  }
}

