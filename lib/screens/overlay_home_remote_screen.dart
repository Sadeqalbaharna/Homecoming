import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/automation/home_automation_service.dart';
import 'gm_kai_audio_screen.dart';

class OverlayHomeRemoteScreen extends StatefulWidget {
  const OverlayHomeRemoteScreen({super.key});

  @override
  State<OverlayHomeRemoteScreen> createState() =>
      _OverlayHomeRemoteScreenState();
}

class _OverlayHomeRemoteScreenState extends State<OverlayHomeRemoteScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = false;
  String _statusMessage = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _statusMessage = '🏠 Home automation ready';
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // Audio Controls Data
  final List<Map<String, String>> _songs = [
    {'id': 'electronic_beat', 'name': '🎵 Electronic Beat'},
    {'id': 'ambient_space', 'name': '🌌 Ambient Space'},
    {'id': 'chiptune_adventure', 'name': '🎮 Chiptune Adventure'},
    {'id': 'nature_sounds', 'name': '🌿 Nature Sounds'},
    {'id': 'piano_meditation', 'name': '🎹 Piano Meditation'},
    {'id': 'lofi_study', 'name': '📚 Lo-Fi Study'},
    {'id': 'upbeat_energy', 'name': '⚡ Upbeat Energy'},
  ];

  final List<Map<String, String>> _moods = [
    {'id': 'energetic', 'name': '⚡ Energetic', 'icon': '🔥'},
    {'id': 'relaxing', 'name': '🧘 Relaxing', 'icon': '🌊'},
    {'id': 'focused', 'name': '🎯 Focused', 'icon': '💎'},
    {'id': 'party', 'name': '🎉 Party', 'icon': '🪩'},
    {'id': 'sleep', 'name': '😴 Sleep', 'icon': '🌙'},
    {'id': 'creative', 'name': '🎨 Creative', 'icon': '✨'},
    {'id': 'workout', 'name': '💪 Workout', 'icon': '🏃'},
  ];

  // Light Controls Data
  final List<Map<String, dynamic>> _lightScenes = [
    {'id': 'bright', 'name': '☀️ Bright', 'color': Colors.yellow, 'icon': '💡'},
    {'id': 'dim', 'name': '🌅 Dim', 'color': Colors.orange, 'icon': '🕯️'},
    {'id': 'red', 'name': '🔴 Red', 'color': Colors.red, 'icon': '❤️'},
    {'id': 'blue', 'name': '🔵 Blue', 'color': Colors.blue, 'icon': '💙'},
    {'id': 'green', 'name': '🟢 Green', 'color': Colors.green, 'icon': '💚'},
    {'id': 'purple', 'name': '🟣 Purple', 'color': Colors.purple, 'icon': '💜'},
    {'id': 'rainbow', 'name': '🌈 Rainbow', 'color': Colors.pink, 'icon': '🎨'},
    {'id': 'off', 'name': '⚫ Off', 'color': Colors.grey, 'icon': '🌑'},
  ];

  Future<void> _sendCommand(
      String target, String action, Map<String, dynamic> params) async {
    setState(() => _isLoading = true);

    try {
      final success = await HomeAutomationService().sendCommand(
        personaId: 'kai_persona_1',
        deviceId: 'raspberry_pi_home',
        target: target,
        action: action,
        params: params,
      );

      if (mounted) {
        setState(() {
          _statusMessage =
              success ? '✅ Command sent successfully!' : '❌ Command failed';
        });

        HapticFeedback.lightImpact();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusMessage = '❌ Error: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
        // Clear status after 3 seconds
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) {
            setState(() => _statusMessage = '🏠 Home automation ready');
          }
        });
      }
    }
  }

  Future<void> _playSpecificSong(String songId, String songName) async {
    await _sendCommand('music', 'play_song', {'song': songId});
  }

  Future<void> _playMoodPlaylist(String mood, String moodName) async {
    await _sendCommand('music', 'play_mood', {'mood': mood, 'shuffle': true});
  }

  Future<void> _stopMusic() async {
    await _sendCommand('music', 'stop', {});
  }

  Future<void> _setLightScene(String scene, String sceneName) async {
    await _sendCommand('lights', 'set_scene', {'scene': scene});
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF0D0A07),
            Color(0xFF1A1611),
          ],
        ),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.3),
              border: Border(
                bottom: BorderSide(
                  color: const Color(0xFFD4AF37).withOpacity(0.3),
                ),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.home,
                  color: Color(0xFFD4AF37),
                  size: 28,
                ),
                const SizedBox(width: 12),
                const Text(
                  '🏠 Home Remote Control',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(
                    Icons.close,
                    color: Colors.white70,
                    size: 24,
                  ),
                ),
              ],
            ),
          ),

          // Status Bar
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              border: Border(
                bottom: BorderSide(
                  color: const Color(0xFFD4AF37).withOpacity(0.2),
                ),
              ),
            ),
            child: Row(
              children: [
                if (_isLoading) ...[
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      color: Color(0xFFD4AF37),
                      strokeWidth: 2,
                    ),
                  ),
                  const SizedBox(width: 12),
                ] else ...[
                  const Icon(
                    Icons.bluetooth,
                    color: Colors.blue,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    _statusMessage,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Tab Bar
          Container(
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.2),
              border: Border(
                bottom: BorderSide(
                  color: const Color(0xFFD4AF37).withOpacity(0.2),
                ),
              ),
            ),
            child: TabBar(
              controller: _tabController,
              labelColor: const Color(0xFFD4AF37),
              unselectedLabelColor: Colors.white54,
              indicatorColor: const Color(0xFFD4AF37),
              tabs: const [
                Tab(
                  icon: Icon(Icons.music_note),
                  text: 'Audio',
                ),
                Tab(
                  icon: Icon(Icons.lightbulb),
                  text: 'Lights',
                ),
                Tab(
                  icon: Icon(Icons.more_horiz),
                  text: 'More',
                ),
              ],
            ),
          ),

          // Tab Content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildAudioTab(),
                _buildLightsTab(),
                _buildMoreTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAudioTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Quick Controls
          Row(
            children: [
              Expanded(
                child: _QuickButton(
                  icon: Icons.bolt,
                  label: 'Energetic',
                  color: Colors.orange,
                  onPressed: _isLoading
                      ? null
                      : () => _playMoodPlaylist('energetic', 'Energetic'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _QuickButton(
                  icon: Icons.stop,
                  label: 'Stop All',
                  color: Colors.red,
                  onPressed: _isLoading ? null : _stopMusic,
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Mood Playlists Section
          const Text(
            '🎭 Mood Playlists',
            style: TextStyle(
              color: Color(0xFFD4AF37),
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),

          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 2.5,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: _moods.length,
            itemBuilder: (context, index) {
              final mood = _moods[index];
              return _MoodCard(
                mood: mood,
                isLoading: _isLoading,
                onTap: () => _playMoodPlaylist(mood['id']!, mood['name']!),
              );
            },
          ),

          const SizedBox(height: 24),

          // Individual Songs Section
          const Text(
            '🎶 Individual Songs',
            style: TextStyle(
              color: Color(0xFFD4AF37),
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),

          ...List.generate(_songs.length, (index) {
            final song = _songs[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _SongCard(
                song: song,
                isLoading: _isLoading,
                onTap: () => _playSpecificSong(song['id']!, song['name']!),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildLightsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Quick Controls
          Row(
            children: [
              Expanded(
                child: _QuickButton(
                  icon: Icons.lightbulb,
                  label: 'All On',
                  color: Colors.yellow,
                  onPressed: _isLoading
                      ? null
                      : () => _setLightScene('bright', 'Bright'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _QuickButton(
                  icon: Icons.lightbulb_outline,
                  label: 'All Off',
                  color: Colors.grey,
                  onPressed:
                      _isLoading ? null : () => _setLightScene('off', 'Off'),
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Light Scenes Section
          const Text(
            '💡 Light Scenes',
            style: TextStyle(
              color: Color(0xFFD4AF37),
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),

          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: _lightScenes.length,
            itemBuilder: (context, index) {
              final scene = _lightScenes[index];
              return _LightSceneCard(
                scene: scene,
                isLoading: _isLoading,
                onTap: () => _setLightScene(scene['id']!, scene['name']!),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMoreTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // GM Kai Audio Control
          _FeatureCard(
            icon: Icons.gamepad,
            title: 'GM Kai Audio Control',
            subtitle: 'Direct text input for YouTube music',
            isEnabled: true,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const GMKaiAudioScreen(),
                ),
              );
            },
          ),
          const SizedBox(height: 20),
          const Text(
            '🔧 Coming Soon',
            style: TextStyle(
              color: Color(0xFFD4AF37),
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 20),
          const _FeatureCard(
            icon: Icons.thermostat,
            title: 'Climate Control',
            subtitle: 'Temperature & humidity controls',
            isEnabled: false,
          ),
          const SizedBox(height: 12),
          const _FeatureCard(
            icon: Icons.security,
            title: 'Security System',
            subtitle: 'Cameras & sensors monitoring',
            isEnabled: false,
          ),
          const SizedBox(height: 12),
          const _FeatureCard(
            icon: Icons.tv,
            title: 'Media Center',
            subtitle: 'TV & streaming controls',
            isEnabled: false,
          ),
          const SizedBox(height: 12),
          const _FeatureCard(
            icon: Icons.power,
            title: 'Smart Outlets',
            subtitle: 'Power control for devices',
            isEnabled: false,
          ),
        ],
      ),
    );
  }
}

// Quick Action Button Widget
class _QuickButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onPressed;

  const _QuickButton({
    required this.icon,
    required this.label,
    required this.color,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        disabledBackgroundColor: color.withOpacity(0.3),
      ),
    );
  }
}

// Mood Card Widget
class _MoodCard extends StatelessWidget {
  final Map<String, String> mood;
  final bool isLoading;
  final VoidCallback onTap;

  const _MoodCard({
    required this.mood,
    required this.isLoading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.blue.withOpacity(0.3),
          ),
        ),
        child: Row(
          children: [
            Text(
              mood['icon']!,
              style: const TextStyle(fontSize: 24),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                mood['name']!,
                style: TextStyle(
                  color: isLoading ? Colors.white30 : Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Song Card Widget
class _SongCard extends StatelessWidget {
  final Map<String, String> song;
  final bool isLoading;
  final VoidCallback onTap;

  const _SongCard({
    required this.song,
    required this.isLoading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.grey.withOpacity(0.3),
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.music_note,
              color: isLoading
                  ? const Color(0xFFD4AF37).withOpacity(0.3)
                  : const Color(0xFFD4AF37),
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                song['name']!,
                style: TextStyle(
                  color: isLoading ? Colors.white30 : Colors.white,
                  fontSize: 15,
                ),
              ),
            ),
            Icon(
              Icons.play_arrow,
              color: isLoading ? Colors.white30 : Colors.white70,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

// Light Scene Card Widget
class _LightSceneCard extends StatelessWidget {
  final Map<String, dynamic> scene;
  final bool isLoading;
  final VoidCallback onTap;

  const _LightSceneCard({
    required this.scene,
    required this.isLoading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: (scene['color'] as Color).withOpacity(0.5),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              scene['icon']!,
              style: const TextStyle(fontSize: 32),
            ),
            const SizedBox(height: 8),
            Text(
              scene['name']!,
              style: TextStyle(
                color: isLoading ? Colors.white30 : Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// Feature Card Widget (for coming soon features)
class _FeatureCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool isEnabled;
  final VoidCallback? onTap;

  const _FeatureCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isEnabled,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isEnabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A).withOpacity(isEnabled ? 1.0 : 0.5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.grey.withOpacity(isEnabled ? 0.3 : 0.1),
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isEnabled
                  ? const Color(0xFFD4AF37)
                  : Colors.grey.withOpacity(0.5),
              size: 24,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: isEnabled ? Colors.white : Colors.white38,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: isEnabled ? Colors.white70 : Colors.white24,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            if (!isEnabled)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Soon',
                  style: TextStyle(
                    color: Colors.orange,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

