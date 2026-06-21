import 'package:flutter/material.dart';
import '../../../../widgets/voice_selector.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const SizedBox(height: 8),
          // Voice Selection Section
          const VoiceSelector(),
          const SizedBox(height: 24),
          const Divider(height: 1, thickness: 2),
          const SizedBox(height: 8),
          ListTile(
            leading: Icon(Icons.color_lens, color: cs.primary),
            title: const Text('Theme'),
            subtitle: const Text('Uses system light/dark by default'),
          ),
          const Divider(height: 1),
          ListTile(
            leading: Icon(Icons.info_outline, color: cs.secondary),
            title: const Text('About'),
            subtitle: const Text('Homecoming UI starter • GoRouter + Riverpod'),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              'Ready for Firebase & voice hooks when you are.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}