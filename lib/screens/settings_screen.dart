/// Settings Screen
/// Configure app behavior including proactive AI and voice activation
library;

import 'package:flutter/material.dart';
import '../services/ai/proactive_service.dart';
import '../services/voice/voice_activation_service.dart';
import '../widgets/voice_setup_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final ProactiveService _proactive = ProactiveService();
  final VoiceActivationService _voiceActivation = VoiceActivationService();
  bool _proactiveEnabled = true;
  bool _voiceActivationEnabled = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _proactiveEnabled = prefs.getBool('proactive_enabled') ?? true;
      _voiceActivationEnabled = prefs.getBool('voice_activation_enabled') ?? false;
      _isLoading = false;
    });
  }

  Future<void> _toggleProactive(bool value) async {
    setState(() {
      _proactiveEnabled = value;
    });
    await _proactive.setEnabled(value);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            value 
              ? '✨ Kai will now reach out proactively!'
              : '🔕 Kai will only respond when you initiate',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _toggleVoiceActivation(bool value) async {
    setState(() {
      _voiceActivationEnabled = value;
    });
    
    if (value) {
      final started = await _voiceActivation.start();
      if (!started && mounted) {
        setState(() {
          _voiceActivationEnabled = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ Failed to start voice activation. Check microphone permissions.'),
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }
    } else {
      await _voiceActivation.stop();
    }
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            value 
              ? '🎤 "Hey Kai" voice activation enabled!'
              : '🔕 Voice activation disabled',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF16213E),
        title: const Text(
          '⚙️ Settings',
          style: TextStyle(color: Colors.white),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                color: Color(0xFFFFE7B0),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildSectionTitle('🎤 Voice Controls'),
                const SizedBox(height: 8),
                _buildVoiceActivationToggle(),
                const SizedBox(height: 12),
                _buildVoiceTrainingOption(),
                const SizedBox(height: 24),
                
                _buildSectionTitle('🤖 AI Behavior'),
                const SizedBox(height: 8),
                _buildProactiveToggle(),
                const SizedBox(height: 24),
                
                _buildSectionTitle('📊 Stats'),
                const SizedBox(height: 8),
                _buildProactiveStats(),
              ],
            ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: Color(0xFFFFE7B0),
        fontSize: 18,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _buildVoiceActivationToggle() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF16213E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '"Hey Kai" Voice Activation',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Always listen for "Hey Kai" to start conversations',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _voiceActivationEnabled,
                onChanged: _toggleVoiceActivation,
                activeThumbColor: const Color(0xFFFFE7B0),
              ),
            ],
          ),
          if (_voiceActivationEnabled) ...[
            const SizedBox(height: 12),
            const Divider(color: Colors.white24),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A2E),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.mic, color: Color(0xFFFFE7B0), size: 20),
                      SizedBox(width: 8),
                      Text(
                        'How it works:',
                        style: TextStyle(
                          color: Color(0xFFFFE7B0),
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  Text(
                    '• Say "Hey Kai" to activate\n'
                    '• Continue speaking your message\n'
                    '• Or just say "Hey Kai" to start recording',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                  SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.battery_alert, color: Colors.orange, size: 16),
                      SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'May increase battery usage',
                          style: TextStyle(
                            color: Colors.orange,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildProactiveToggle() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF16213E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Proactive Conversations',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Kai will initiate conversations throughout the day',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _proactiveEnabled,
                onChanged: _toggleProactive,
                activeThumbColor: const Color(0xFFFFE7B0),
              ),
            ],
          ),
          if (_proactiveEnabled) ...[
            const SizedBox(height: 12),
            const Divider(color: Colors.white24),
            const SizedBox(height: 12),
            _buildTriggerInfo('☀️', 'Morning greeting', '7-9 AM'),
            _buildTriggerInfo('🍽️', 'Lunch reminder', '12-1 PM'),
            _buildTriggerInfo('🌙', 'Evening recap', '8-10 PM'),
            _buildTriggerInfo('💭', 'Check-ins', 'When idle 4+ hours'),
            _buildTriggerInfo('💪', 'Break reminders', 'Every 2 hours'),
            _buildTriggerInfo('🤓', 'Curiosity facts', 'Random'),
          ],
        ],
      ),
    );
  }

  Widget _buildTriggerInfo(String emoji, String title, String time) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(
            emoji,
            style: const TextStyle(fontSize: 16),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
              ),
            ),
          ),
          Text(
            time,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProactiveStats() {
    return FutureBuilder<Map<String, int>>(
      future: _getProactiveStats(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(
              color: Color(0xFFFFE7B0),
            ),
          );
        }

        final stats = snapshot.data!;
        final total = stats.values.fold(0, (sum, count) => sum + count);

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF16213E),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Total proactive messages: $total',
                style: const TextStyle(
                  color: Color(0xFFFFE7B0),
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              ...stats.entries.map((entry) {
                final name = entry.key
                    .replaceAll('proactive_', '')
                    .replaceAll('_count', '')
                    .replaceAll('_', ' ');
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        '${entry.value}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  Widget _buildVoiceTrainingOption() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2C4C),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFFFE7B0).withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFFFE7B0).withValues(alpha: 0.2),
            ),
            child: const Icon(
              Icons.record_voice_over,
              color: Color(0xFFFFE7B0),
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Voice Training',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  'Train Kai to recognize your voice',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: _openVoiceTraining,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFFFFE7B0).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: const Color(0xFFFFE7B0),
                ),
              ),
              child: const Text(
                'Setup',
                style: TextStyle(
                  color: Color(0xFFFFE7B0),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openVoiceTraining() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const VoiceSetupDialog(),
    );
  }

  Future<Map<String, int>> _getProactiveStats() async {
    final prefs = await SharedPreferences.getInstance();
    final stats = <String, int>{};
    
    for (var key in prefs.getKeys()) {
      if (key.startsWith('proactive_') && key.endsWith('_count')) {
        stats[key] = prefs.getInt(key) ?? 0;
      }
    }
    
    return stats;
  }
}
