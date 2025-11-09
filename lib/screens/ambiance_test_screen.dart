/// Ambiance Test Screen
/// Testing interface for intelligent ambiance system integration
library;

import 'package:flutter/material.dart';
import '../widgets/ambiance_control_widget.dart';
import '../services/ambiance_service.dart';
import '../services/ai_service.dart';

class AmbianceTestScreen extends StatefulWidget {
  const AmbianceTestScreen({super.key});

  @override
  State<AmbianceTestScreen> createState() => _AmbianceTestScreenState();
}

class _AmbianceTestScreenState extends State<AmbianceTestScreen> {
  final AIService _aiService = AIService();
  final TextEditingController _chatController = TextEditingController();
  bool _isProcessing = false;
  String? _lastResponse;

  Future<void> _sendToKai(String message) async {
    if (message.isEmpty) return;

    setState(() {
      _isProcessing = true;
      _lastResponse = null;
    });

    try {
      print('🗣️ Sending to Kai: "$message"');
      
      final response = await _aiService.sendMessage(
        text: message,
        personaId: 'kai_persona_1', // Your persona ID
        useMemory: true,
        useWebSearch: false,
      );

      setState(() {
        _lastResponse = response.reply;
      });

      print('🤖 Kai responded: ${response.reply}');
      
      // Check if this was an ambiance bypass
      if (response.debugInfo?['bypassed_full_ai'] == true) {
        print('🎭 Ambiance was handled directly without full AI processing');
      }

    } catch (e) {
      setState(() {
        _lastResponse = 'Error: $e';
      });
      print('❌ Error sending message: $e');
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🎭 Intelligent Ambiance Test'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Direct Ambiance Control
            const AmbianceControlWidget(),
            
            const SizedBox(height: 16),
            
            // AI Integration Test
            Card(
              margin: const EdgeInsets.all(16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '🤖 Kai AI Integration Test',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    const Text(
                      'Test full AI integration with ambiance detection:',
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 12),
                    
                    // Chat input
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _chatController,
                            decoration: const InputDecoration(
                              hintText: 'Talk to Kai about ambiance...',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            onSubmitted: (value) {
                              _sendToKai(value);
                              _chatController.clear();
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: _isProcessing || _chatController.text.isEmpty
                              ? null
                              : () {
                                  _sendToKai(_chatController.text);
                                  _chatController.clear();
                                },
                          child: _isProcessing
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text('Send'),
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // Example messages
                    const Text(
                      'Try these with Kai:',
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 8),
                    
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        '"Kai, give me forest ambiance"',
                        '"Create a romantic mood"',
                        '"I need to focus"',
                        '"Let\'s party!"',
                        '"Make it cozy"',
                      ].map((example) {
                        return ActionChip(
                          label: Text(
                            example,
                            style: const TextStyle(fontSize: 12),
                          ),
                          onPressed: _isProcessing
                              ? null
                              : () {
                                  final text = example.replaceAll('"', '');
                                  _chatController.text = text;
                                  _sendToKai(text);
                                  _chatController.clear();
                                },
                        );
                      }).toList(),
                    ),
                    
                    // Response display
                    if (_lastResponse != null) ...[
                      const SizedBox(height: 16),
                      const Divider(),
                      const Text(
                        'Kai\'s Response:',
                        style: TextStyle(fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blue.withOpacity(0.3)),
                        ),
                        child: Text(_lastResponse!),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Status Card
            Card(
              margin: const EdgeInsets.all(16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '📊 System Status',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    _buildStatusItem(
                      '🔥 Firebase Connection',
                      'Connected to homecoming-74f73',
                      Colors.green,
                    ),
                    _buildStatusItem(
                      '🏠 Home Automation',
                      'Target: kai_persona_1 → raspberry_pi_home',
                      Colors.blue,
                    ),
                    _buildStatusItem(
                      '🎭 Ambiance Profiles',
                      '${AmbianceService.ambianceProfiles.length} profiles loaded',
                      Colors.purple,
                    ),
                    _buildStatusItem(
                      '🤖 AI Integration',
                      'Ambiance detection enabled in AI pipeline',
                      Colors.orange,
                    ),
                    
                    const SizedBox(height: 16),
                    
                    const Text(
                      'Expected Behavior:',
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 8),
                    
                    const Text(
                      '• Voice commands detected automatically\n'
                      '• Music and lighting coordinated via Pi\n'
                      '• Natural responses from Kai about ambiance\n'
                      '• Firebase commands logged on Pi\n'
                      '• Bypass full AI for ambiance requests',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusItem(String title, String subtitle, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _chatController.dispose();
    super.dispose();
  }
}