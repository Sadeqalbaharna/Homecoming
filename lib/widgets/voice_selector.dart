import 'package:flutter/material.dart';
import '../services/ai_service.dart';

/// Voice selector widget for choosing ElevenLabs voice
class VoiceSelector extends StatefulWidget {
  const VoiceSelector({super.key});

  @override
  State<VoiceSelector> createState() => _VoiceSelectorState();
}

class _VoiceSelectorState extends State<VoiceSelector> {
  String? _selectedVoiceId;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSelectedVoice();
  }

  Future<void> _loadSelectedVoice() async {
    final voiceId = await AIConfig.getSelectedVoiceId();
    setState(() {
      _selectedVoiceId = voiceId;
      _isLoading = false;
    });
  }

  Future<void> _selectVoice(String voiceId) async {
    await AIConfig.setSelectedVoiceId(voiceId);
    setState(() {
      _selectedVoiceId = voiceId;
    });
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '🎤 Voice changed to ${AIConfig.availableVoices.values.firstWhere((v) => v['id'] == voiceId)['name']}',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            'Voice Selection',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        ...AIConfig.availableVoices.entries.map((entry) {
          final voiceData = entry.value;
          final voiceId = voiceData['id']!;
          final voiceName = voiceData['name']!;
          final voiceDescription = voiceData['description']!;
          final isSelected = _selectedVoiceId == voiceId;

          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            elevation: isSelected ? 4 : 1,
            color: isSelected 
                ? Theme.of(context).colorScheme.primaryContainer 
                : null,
            child: InkWell(
              onTap: () => _selectVoice(voiceId),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    // Voice icon
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.surfaceVariant,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isSelected ? Icons.check_circle : Icons.mic,
                        color: isSelected
                            ? Theme.of(context).colorScheme.onPrimary
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Voice info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            voiceName,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            voiceDescription,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Selection indicator
                    if (isSelected)
                      Icon(
                        Icons.radio_button_checked,
                        color: Theme.of(context).colorScheme.primary,
                      )
                    else
                      Icon(
                        Icons.radio_button_unchecked,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Text(
            '💡 Tip: Voice changes will take effect on the next message',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      ],
    );
  }
}
