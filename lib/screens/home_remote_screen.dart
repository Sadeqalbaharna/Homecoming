import 'package:flutter/material.dart';
import '../services/automation/home_automation_service.dart';

class HomeRemoteScreen extends StatefulWidget {
  const HomeRemoteScreen({super.key});

  @override
  State<HomeRemoteScreen> createState() => _HomeRemoteScreenState();
}

class _HomeRemoteScreenState extends State<HomeRemoteScreen> {
  bool _isLoading = false;
  String _statusMessage = '';

  // Pi Music System Controls
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

  Future<void> _playSpecificSong(String songId, String songName) async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Playing $songName...';
    });
    
    try {
      final success = await HomeAutomationService().sendCommand(
        personaId: 'truekai',
        deviceId: 'raspberry_pi_home',
        target: 'music',
        action: 'play_song',
        params: {'song': songId},
      );
      
      if (mounted) {
        setState(() {
          _statusMessage = success 
            ? '🎵 $songName is now playing! 🔊'
            : '❌ Failed to play $songName';
        });
        
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('🎵 $songName started!'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
        }
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
      }
    }
  }

  Future<void> _playMoodPlaylist(String mood, String moodName) async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Starting $moodName playlist...';
    });
    
    try {
      final success = await HomeAutomationService().sendCommand(
        personaId: 'truekai',
        deviceId: 'raspberry_pi_home',
        target: 'music',
        action: 'play_mood',
        params: {'mood': mood, 'shuffle': true},
      );
      
      if (mounted) {
        setState(() {
          _statusMessage = success 
            ? '🎭 $moodName playlist started! 🔊'
            : '❌ Failed to start $moodName playlist';
        });
        
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('🎭 $moodName playlist started!'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
        }
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
      }
    }
  }

  Future<void> _stopMusic() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Stopping music...';
    });
    
    try {
      final success = await HomeAutomationService().sendCommand(
        personaId: 'truekai',
        deviceId: 'raspberry_pi_home',
        target: 'music',
        action: 'stop',
        params: {},
      );
      
      if (mounted) {
        setState(() {
          _statusMessage = success 
            ? '🛑 Music stopped'
            : '❌ Failed to stop music';
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? '🛑 Music stopped' : '❌ Stop failed'),
            backgroundColor: success ? Colors.orange : Colors.red,
            duration: const Duration(seconds: 2),
          ),
        );
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
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Header
          Row(
            children: [
              const Icon(
                Icons.home_outlined,
                color: Color(0xFFD4AF37),
                size: 28,
              ),
              const SizedBox(width: 12),
              const Text(
                '🏠 Home Remote Control',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(
                  Icons.close,
                  color: Colors.white70,
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 20),
          
          // Status Display
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFFD4AF37).withOpacity(0.3),
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
                    _statusMessage.isEmpty 
                      ? '🎧 Pi Bluetooth Audio Ready' 
                      : _statusMessage,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 20),
          
          // Main Content
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Quick Controls
                  Row(
                    children: [
                      Expanded(
                        child: _QuickControlButton(
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
                        child: _QuickControlButton(
                          icon: Icons.stop,
                          label: 'Stop',
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
                      return _MoodTile(
                        mood: mood,
                        onTap: _isLoading 
                          ? null 
                          : () => _playMoodPlaylist(mood['id']!, mood['name']!),
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
                      child: _SongTile(
                        song: song,
                        onTap: _isLoading 
                          ? null 
                          : () => _playSpecificSong(song['id']!, song['name']!),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onPressed;

  const _QuickControlButton({
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
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}

class _MoodTile extends StatelessWidget {
  final Map<String, String> mood;
  final VoidCallback? onTap;

  const _MoodTile({
    required this.mood,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
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
              style: const TextStyle(fontSize: 20),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                mood['name']!,
                style: const TextStyle(
                  color: Colors.white,
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

class _SongTile extends StatelessWidget {
  final Map<String, String> song;
  final VoidCallback? onTap;

  const _SongTile({
    required this.song,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
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
            const Icon(
              Icons.music_note,
              color: Color(0xFFD4AF37),
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                song['name']!,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                ),
              ),
            ),
            const Icon(
              Icons.play_arrow,
              color: Colors.white70,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
