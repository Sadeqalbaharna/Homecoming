/// Settings Screen
/// Configure app behavior including proactive AI
library;

import 'package:flutter/material.dart';
import '../services/proactive_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final ProactiveService _proactive = ProactiveService();
  bool _proactiveEnabled = true;
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
                activeColor: const Color(0xFFFFE7B0),
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
