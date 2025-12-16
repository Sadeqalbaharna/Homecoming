/// GM Kai Audio Control Screen
/// Direct text input interface for YouTube music search and playback
library;

import 'package:flutter/material.dart';
import 'dart:async';
import '../services/ai_service.dart';
import '../services/home_automation_service.dart';

class GMKaiAudioScreen extends StatefulWidget {
  const GMKaiAudioScreen({super.key});

  @override
  State<GMKaiAudioScreen> createState() => _GMKaiAudioScreenState();
}

class _GMKaiAudioScreenState extends State<GMKaiAudioScreen> {
  final TextEditingController _inputController = TextEditingController();
  final AIService _aiService = AIService();
  final HomeAutomationService _homeService = HomeAutomationService();
  
  bool _isProcessing = false;
  String? _lastPrompt;
  String? _lastResponse;
  List<String> _history = [];
  bool _showDebug = false;
  Map<String, dynamic>? _debugInfo;

  Future<void> _sendPrompt(String prompt) async {
    if (prompt.isEmpty) return;

    setState(() {
      _isProcessing = true;
      _lastPrompt = prompt;
      _lastResponse = null;
      _debugInfo = null;
    });

    try {
      print('🎮 [GM KAI AUDIO] Sending prompt: "$prompt"');
      
      // Send to Kai with GM Kai mode context
      final response = await _aiService.sendMessage(
        text: 'GM Kai: $prompt',
        personaId: 'kai_persona_1',
        useMemory: true,
        useWebSearch: false,
      );

      setState(() {
        _lastResponse = response.reply;
        _debugInfo = response.debugInfo;
        _history.insert(0, '> $prompt\n< ${response.reply}');
      });

      print('🤖 [GM KAI AUDIO] Response: ${response.reply}');
      
      // Check if audio was triggered
      if (_debugInfo?['ambiance_triggered'] == true) {
        print('✅ [GM KAI AUDIO] Audio playback triggered!');
        _showSuccessSnackbar('🎵 Playing audio from: ${_debugInfo?['music_query'] ?? 'YouTube'}');
      } else if (_debugInfo?['gm_mode'] == true) {
        print('🎮 [GM KAI AUDIO] GM Kai mode activated');
        _showSuccessSnackbar('🎮 GM Kai mode activated');
      }

    } catch (e) {
      setState(() {
        _lastResponse = '❌ Error: $e';
        _history.insert(0, '> $prompt\n❌ $e');
      });
      print('❌ [GM KAI AUDIO] Error: $e');
      _showErrorSnackbar('Error: $e');
    } finally {
      _inputController.clear();
      setState(() {
        _isProcessing = false;
      });
    }
  }

  void _showSuccessSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showErrorSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🎮 GM Kai Audio Control'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.bug_report),
            onPressed: () => setState(() => _showDebug = !_showDebug),
            tooltip: 'Toggle Debug Info',
          ),
        ],
      ),
      body: Column(
        children: [
          // Main Input Area
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Instructions
                  Card(
                    margin: const EdgeInsets.all(16),
                    color: Colors.blue.withAlpha(200),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '🎮 GM Kai Mode - Direct Audio Control',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Enter any text prompt and Kai will search YouTube for matching audio and play it on your Bluetooth speaker.',
                            style: TextStyle(
                              color: Colors.white,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Examples:',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            '• "tavern medieval music ambient"\n'
                            '• "epic battle orchestral music"\n'
                            '• "peaceful healing ambient magic"\n'
                            '• "lofi hip hop beats to relax"\n'
                            '• "thunderstorm sounds with dramatic music"',
                            style: TextStyle(
                              color: Colors.white70,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Last Response
                  if (_lastResponse != null) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'Response:',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    Card(
                      margin: const EdgeInsets.all(16),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(_lastResponse!),
                      ),
                    ),
                  ],

                  // Debug Info
                  if (_showDebug && _debugInfo != null) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'Debug Info:',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    Card(
                      margin: const EdgeInsets.all(16),
                      color: Colors.grey[900],
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          _formatDebugInfo(_debugInfo!),
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            color: Colors.green,
                          ),
                        ),
                      ),
                    ),
                  ],

                  // History
                  if (_history.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Text(
                        'History:',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            _history.join('\n\n'),
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),

          // Input Area
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border(
                top: BorderSide(
                  color: Theme.of(context).dividerColor,
                ),
              ),
            ),
            child: Column(
              children: [
                // Text Input
                TextField(
                  controller: _inputController,
                  enabled: !_isProcessing,
                  maxLines: 3,
                  minLines: 1,
                  decoration: InputDecoration(
                    hintText: 'Enter audio prompt...',
                    hintStyle: TextStyle(color: Colors.grey[500]),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.all(12),
                    suffixIcon: _isProcessing
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : null,
                  ),
                  onSubmitted: _isProcessing ? null : _sendPrompt,
                ),
                const SizedBox(height: 12),

                // Send Button + Quick Actions
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      // Send Button
                      ElevatedButton.icon(
                        onPressed: _isProcessing
                            ? null
                            : () => _sendPrompt(_inputController.text),
                        icon: const Icon(Icons.send),
                        label: const Text('Send'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              Theme.of(context).colorScheme.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 16,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Quick Action Buttons
                      ..._buildQuickActionButtons(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildQuickActionButtons() {
    final quickPrompts = [
      ('🏛️ Tavern', 'tavern medieval music ambient'),
      ('👻 Haunted', 'haunted mansion spooky atmosphere'),
      ('⚔️ Battle', 'epic battle orchestral dramatic'),
      ('🌊 Ocean', 'ocean waves relaxing ambient'),
      ('🎵 Lofi', 'lofi hip hop beats to relax'),
      ('⛈️ Storm', 'thunderstorm dramatic music'),
    ];

    return quickPrompts.map((label, prompt) {
      return label[0];
    }).map((item) {
      final label = item as String;
      final prompt = (item as List)[1] as String;
      
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: OutlinedButton(
          onPressed: _isProcessing ? null : () => _sendPrompt(prompt),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12),
          ),
          child: Text(
            label,
            style: const TextStyle(fontSize: 12),
          ),
        ),
      );
    }).toList();
  }

  String _formatDebugInfo(Map<String, dynamic> info) {
    final buffer = StringBuffer();
    buffer.writeln('=== DEBUG INFO ===');
    info.forEach((key, value) {
      if (value is Map) {
        buffer.writeln('$key:');
        (value as Map).forEach((k, v) {
          buffer.writeln('  $k: $v');
        });
      } else {
        buffer.writeln('$key: $value');
      }
    });
    return buffer.toString();
  }

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }
}
