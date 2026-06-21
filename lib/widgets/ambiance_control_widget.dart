/// Ambiance Control Widget
/// Quick testing interface for the intelligent ambiance system
library;

import 'package:flutter/material.dart';
import '../services/media/ambiance_service.dart';

class AmbianceControlWidget extends StatefulWidget {
  const AmbianceControlWidget({super.key});

  @override
  State<AmbianceControlWidget> createState() => _AmbianceControlWidgetState();
}

class _AmbianceControlWidgetState extends State<AmbianceControlWidget> {
  final AmbianceService _ambianceService = AmbianceService();
  bool _isLoading = false;
  String? _lastResult;
  final TextEditingController _textController = TextEditingController();

  // Quick test buttons for common ambiances
  final List<Map<String, dynamic>> _quickTests = [
    {
      'label': '🌲 Forest',
      'input': 'give me forest ambiance',
      'color': Colors.green,
    },
    {
      'label': '🌊 Ocean',
      'input': 'create ocean mood',
      'color': Colors.blue,
    },
    {
      'label': '💕 Romantic',
      'input': 'set romantic atmosphere',
      'color': Colors.pink,
    },
    {
      'label': '🎉 Party',
      'input': 'activate party mode',
      'color': Colors.orange,
    },
    {
      'label': '💡 Focus',
      'input': 'help me focus',
      'color': Colors.purple,
    },
    {
      'label': '🌅 Sunset',
      'input': 'give me sunset ambiance',
      'color': Colors.deepOrange,
    },
  ];

  Future<void> _testAmbiance(String input) async {
    setState(() {
      _isLoading = true;
      _lastResult = null;
    });

    try {
      // Analyze the input
      final match = _ambianceService.analyzeVoiceCommand(input);
      
      if (match != null) {
        print('🎭 Detected: ${match.profile} (${(match.confidence * 100).toStringAsFixed(1)}% confidence)');
        
        // Set the ambiance
        final success = await _ambianceService.setAmbiance(
          profile: match.profile,
          originalInput: input,
          confidence: match.confidence,
        );
        
        if (success) {
          final response = _ambianceService.generateKaiResponse(match.profile, match.confidence);
          setState(() {
            _lastResult = '✅ ${match.profile} ambiance set!\n\n$response';
          });
        } else {
          setState(() {
            _lastResult = '❌ Failed to set ${match.profile} ambiance';
          });
        }
      } else {
        setState(() {
          _lastResult = '❓ No ambiance detected in: "$input"';
        });
      }
    } catch (e) {
      setState(() {
        _lastResult = '❌ Error: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _stopAmbiance() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final success = await _ambianceService.stopAmbiance();
      setState(() {
        _lastResult = success 
          ? '🛑 Ambiance stopped successfully'
          : '❌ Failed to stop ambiance';
      });
    } catch (e) {
      setState(() {
        _lastResult = '❌ Error stopping ambiance: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '🎭 Intelligent Ambiance Control',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            
            // Custom input
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _textController,
                    decoration: const InputDecoration(
                      hintText: 'Try: "give me forest ambiance"',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (value) {
                      if (value.isNotEmpty) {
                        _testAmbiance(value);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _isLoading || _textController.text.isEmpty
                      ? null
                      : () => _testAmbiance(_textController.text),
                  child: _isLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Test'),
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // Quick test buttons
            const Text(
              'Quick Tests:',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _quickTests.map((test) {
                return ElevatedButton(
                  onPressed: _isLoading ? null : () => _testAmbiance(test['input']),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: (test['color'] as Color).withOpacity(0.1),
                    foregroundColor: test['color'],
                    side: BorderSide(color: test['color']),
                  ),
                  child: Text(test['label']),
                );
              }).toList(),
            ),
            
            const SizedBox(height: 16),
            
            // Stop button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _stopAmbiance,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.withOpacity(0.1),
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                ),
                child: const Text('🛑 Stop All Ambiance'),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Results
            if (_lastResult != null) ...[
              const Divider(),
              const Text(
                'Result:',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.withOpacity(0.3)),
                ),
                child: Text(
                  _lastResult!,
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
              ),
            ],
            
            const SizedBox(height: 16),
            
            // Instructions
            const Divider(),
            const Text(
              'Instructions:',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            const Text(
              '1. Make sure your Pi is running firebase_rest_listener_debug.py\n'
              '2. Try voice commands like:\n'
              '   • "Kai, give me forest ambiance"\n'
              '   • "Create ocean mood"\n'
              '   • "Set romantic atmosphere"\n'
              '3. Check Pi logs for coordination between music and lights\n'
              '4. Use stop button to reset ambiance',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }
}