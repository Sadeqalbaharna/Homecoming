#!/bin/bash
# Homecoming Pi Music System - Complete Deployment Script
# Run this script on your Raspberry Pi to set up the complete music system

set -e  # Exit on any error

echo "🎵 Homecoming Pi Music System Deployment"
echo "========================================"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

echo_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

echo_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

echo_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Step 1: Create directory structure
echo_status "Creating directory structure..."
mkdir -p ~/homecoming_pi/{music,logs,playlists,scripts}
cd ~/homecoming_pi
echo_success "Directory structure created"

# Step 2: System update
echo_status "Updating system packages..."
sudo apt update && sudo apt upgrade -y
echo_success "System updated"

# Step 3: Install required packages
echo_status "Installing required packages..."
sudo apt install -y \
    sox libsox-fmt-all \
    mpg123 alsa-utils \
    python3-pygame \
    ffmpeg \
    pulseaudio-module-bluetooth \
    bluetooth bluez bluez-tools \
    espeak-ng \
    python3-pip \
    git
echo_success "Packages installed"

# Step 4: Install Python packages
echo_status "Installing Python packages..."
pip3 install --user pygame pydub firebase-admin
echo_success "Python packages installed"

# Step 5: Configure Bluetooth and Audio
echo_status "Configuring Bluetooth and PulseAudio..."

# Enable Bluetooth service
sudo systemctl enable bluetooth
sudo systemctl start bluetooth

# Configure PulseAudio for Bluetooth
echo "load-module module-bluetooth-policy" | sudo tee -a /etc/pulse/system.pa
echo "load-module module-bluetooth-discover" | sudo tee -a /etc/pulse/system.pa

# Add pi user to bluetooth group
sudo usermod -a -G bluetooth pi

echo_success "Bluetooth and audio configured"

# Step 6: Create music player service
echo_status "Creating music player service..."
cat > ~/homecoming_pi/music_player_service.py << 'MUSIC_EOF'
#!/usr/bin/env python3
"""
Music Player Service for Homecoming Pi
Handles music playbook requests with Bluetooth audio output
"""

import os
import json
import time
import logging
import subprocess
import threading
from pathlib import Path
from typing import Dict, List, Optional, Any
import random

try:
    import pygame
    pygame.mixer.init()
    PYGAME_AVAILABLE = True
except ImportError:
    PYGAME_AVAILABLE = False
    print("Warning: pygame not available, using mpg123 fallback")

class MusicPlayerService:
    def __init__(self):
        self.logger = self._setup_logging()
        self.music_directory = Path("/home/pi/homecoming_pi/music")
        self.playlists_directory = Path("/home/pi/homecoming_pi/playlists")
        self.current_song = None
        self.is_playing = False
        self.is_paused = False
        self.current_playlist = []
        self.current_index = 0
        self.volume = 0.7
        
        # Create directories
        self.music_directory.mkdir(exist_ok=True)
        self.playlists_directory.mkdir(exist_ok=True)
        
        # Built-in song library
        self.song_library = {
            'electronic_beat': {
                'name': 'Electronic Beat',
                'genre': 'electronic',
                'mood': 'energetic',
                'file': 'electronic_beat.wav',
                'duration': 180,
                'description': 'Upbeat electronic music perfect for coding or working'
            },
            'synthwave_nights': {
                'name': 'Synthwave Nights',
                'genre': 'synthwave',
                'mood': 'cool',
                'file': 'synthwave_nights.wav',
                'duration': 240,
                'description': 'Retro synthwave with neon vibes'
            },
            'ambient_space': {
                'name': 'Ambient Space',
                'genre': 'ambient',
                'mood': 'relaxing',
                'file': 'ambient_space.wav',
                'duration': 300,
                'description': 'Peaceful ambient sounds for relaxation'
            },
            'nature_sounds': {
                'name': 'Nature Sounds',
                'genre': 'nature',
                'mood': 'peaceful',
                'file': 'nature_sounds.wav',
                'duration': 600,
                'description': 'Calming nature sounds with birds and water'
            },
            'piano_meditation': {
                'name': 'Piano Meditation',
                'genre': 'classical',
                'mood': 'meditative',
                'file': 'piano_meditation.wav',
                'duration': 280,
                'description': 'Gentle piano melodies for focus and calm'
            },
            'lofi_study': {
                'name': 'Lo-Fi Study',
                'genre': 'lofi',
                'mood': 'focused',
                'file': 'lofi_study.wav',
                'duration': 200,
                'description': 'Lo-fi hip hop beats for studying and concentration'
            },
            'chiptune_adventure': {
                'name': 'Chiptune Adventure',
                'genre': 'chiptune',
                'mood': 'playful',
                'file': 'chiptune_adventure.wav',
                'duration': 150,
                'description': 'Retro 8-bit style gaming music'
            }
        }
        
        # Mood-based playlists
        self.mood_playlists = {
            'energetic': ['electronic_beat', 'synthwave_nights', 'chiptune_adventure'],
            'relaxing': ['ambient_space', 'nature_sounds', 'piano_meditation'],
            'focused': ['lofi_study', 'piano_meditation', 'ambient_space'],
            'party': ['electronic_beat', 'synthwave_nights', 'chiptune_adventure'],
            'meditation': ['nature_sounds', 'ambient_space', 'piano_meditation'],
            'work': ['lofi_study', 'electronic_beat', 'piano_meditation'],
            'sleep': ['nature_sounds', 'ambient_space']
        }
        
    def _setup_logging(self):
        """Setup logging for the music service"""
        os.makedirs('/home/pi/homecoming_pi/logs', exist_ok=True)
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
            handlers=[
                logging.FileHandler('/home/pi/homecoming_pi/logs/music_player.log'),
                logging.StreamHandler()
            ]
        )
        return logging.getLogger('MusicPlayer')
    
    def generate_sample_music(self):
        """Generate sample music files using sox if they don't exist"""
        try:
            for song_id, info in self.song_library.items():
                file_path = self.music_directory / info['file']
                
                if not file_path.exists():
                    self.logger.info(f"Generating sample music: {info['name']}")
                    
                    if info['genre'] == 'electronic':
                        cmd = [
                            'sox', '-n', str(file_path), 'synth', str(info['duration']),
                            'sine', '440', 'sine', '880', 'sine', '1320',
                            'tremolo', '4', '40', 'reverb', 'vol', '0.3'
                        ]
                    elif info['genre'] == 'ambient':
                        cmd = [
                            'sox', '-n', str(file_path), 'synth', str(info['duration']),
                            'sine', '220', 'sine', '330', 'sine', '440',
                            'tremolo', '0.5', '20', 'reverb', '50', 'vol', '0.2'
                        ]
                    elif info['genre'] == 'nature':
                        cmd = [
                            'sox', '-n', str(file_path), 'synth', str(info['duration']),
                            'noise', 'highpass', '1000', 'lowpass', '8000',
                            'tremolo', '0.1', '5', 'vol', '0.1'
                        ]
                    elif info['genre'] == 'classical':
                        cmd = [
                            'sox', '-n', str(file_path), 'synth', str(info['duration']),
                            'pluck', 'C4', 'pluck', 'E4', 'pluck', 'G4',
                            'reverb', '30', 'vol', '0.4'
                        ]
                    elif info['genre'] == 'chiptune':
                        cmd = [
                            'sox', '-n', str(file_path), 'synth', str(info['duration']),
                            'square', '440', 'square', '660', 'square', '880',
                            'tremolo', '8', '50', 'vol', '0.3'
                        ]
                    else:
                        cmd = [
                            'sox', '-n', str(file_path), 'synth', str(info['duration']),
                            'sine', '440', 'sine', '550', 'noise', 'mix',
                            'lowpass', '5000', 'vol', '0.25'
                        ]
                    
                    result = subprocess.run(cmd, capture_output=True, text=True)
                    if result.returncode == 0:
                        self.logger.info(f"✅ Generated: {info['name']}")
                    else:
                        self.logger.error(f"❌ Failed to generate {info['name']}: {result.stderr}")
                        
        except Exception as e:
            self.logger.error(f"Error generating music samples: {e}")
    
    def play_song(self, song_id: str) -> Dict[str, Any]:
        """Play a specific song"""
        try:
            if song_id not in self.song_library:
                return {'success': False, 'message': f'Song {song_id} not found'}
            
            file_path = self.music_directory / self.song_library[song_id]['file']
            if not file_path.exists():
                return {'success': False, 'message': f'Music file not found: {file_path}'}
            
            # Stop current playback
            self.stop_music()
            
            # Play using aplay (ALSA)
            subprocess.Popen(['aplay', str(file_path)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            
            self.current_song = song_id
            self.is_playing = True
            
            song_info = self.song_library[song_id]
            return {
                'success': True,
                'message': f'Now playing: {song_info["name"]}',
                'song_info': song_info
            }
            
        except Exception as e:
            return {'success': False, 'message': f'Error playing song: {e}'}
    
    def play_mood_playlist(self, mood: str) -> Dict[str, Any]:
        """Play a mood-based playlist"""
        try:
            if mood not in self.mood_playlists:
                return {'success': False, 'message': f'Mood {mood} not found'}
            
            playlist = self.mood_playlists[mood].copy()
            random.shuffle(playlist)
            
            if not playlist:
                return {'success': False, 'message': f'No songs available for mood: {mood}'}
            
            # Play first song in playlist
            first_song = playlist[0]
            result = self.play_song(first_song)
            
            if result['success']:
                self.current_playlist = playlist
                self.current_index = 0
                return {
                    'success': True,
                    'message': f'Started {mood} playlist with {len(playlist)} songs',
                    'playlist_info': {
                        'mood': mood,
                        'total_songs': len(playlist),
                        'current_song': self.song_library[first_song]['name']
                    }
                }
            
            return result
            
        except Exception as e:
            return {'success': False, 'message': f'Error playing playlist: {e}'}
    
    def stop_music(self) -> Dict[str, Any]:
        """Stop music playback"""
        try:
            # Kill aplay processes
            subprocess.run(['pkill', '-f', 'aplay'], capture_output=True)
            
            self.is_playing = False
            self.current_song = None
            
            return {'success': True, 'message': 'Music stopped'}
            
        except Exception as e:
            return {'success': False, 'message': f'Error stopping music: {e}'}
    
    def get_available_songs(self) -> Dict[str, Any]:
        """Get list of available songs"""
        available = {}
        
        for song_id, info in self.song_library.items():
            file_path = self.music_directory / info['file']
            available[song_id] = {
                **info,
                'available': file_path.exists(),
                'file_path': str(file_path) if file_path.exists() else None
            }
        
        return available

if __name__ == "__main__":
    print("🎵 Homecoming Music Player Service")
    print("=================================")
    
    player = MusicPlayerService()
    
    # Generate music if not exists
    print("Generating sample music...")
    player.generate_sample_music()
    
    # Show available songs
    songs = player.get_available_songs()
    available_count = sum(1 for s in songs.values() if s['available'])
    print(f"\n📀 Available Songs: {available_count}/{len(songs)}")
    
    for song_id, info in songs.items():
        status = "✅" if info['available'] else "❌"
        print(f"  {status} {info['name']} ({info['genre']}, {info['mood']})")
    
    print(f"\n🎭 Available Moods: {', '.join(player.mood_playlists.keys())}")
    print("\n🎵 Music system ready!")
MUSIC_EOF

chmod +x ~/homecoming_pi/music_player_service.py
echo_success "Music player service created"

# Step 7: Test the music system
echo_status "Testing music generation..."
cd ~/homecoming_pi
python3 music_player_service.py

# Step 8: Create simple test script
echo_status "Creating test script..."
cat > ~/homecoming_pi/test_music.py << 'TEST_EOF'
#!/usr/bin/env python3
from music_player_service import MusicPlayerService

def main():
    print("🎵 Testing Homecoming Music System")
    print("=" * 40)
    
    player = MusicPlayerService()
    
    # Test song playback
    print("\n🎶 Testing song playback...")
    result = player.play_song('electronic_beat')
    print(f"Result: {result['message']}")
    
    import time
    time.sleep(3)
    
    # Test playlist
    print("\n🎭 Testing mood playlist...")
    result = player.play_mood_playlist('energetic')
    print(f"Result: {result['message']}")
    
    time.sleep(3)
    
    # Stop music
    print("\n🛑 Stopping music...")
    result = player.stop_music()
    print(f"Result: {result['message']}")
    
    print("\n✅ Music system test complete!")

if __name__ == "__main__":
    main()
TEST_EOF

chmod +x ~/homecoming_pi/test_music.py
echo_success "Test script created"

# Step 9: Create Bluetooth pairing helper
echo_status "Creating Bluetooth helper..."
cat > ~/homecoming_pi/pair_bluetooth.sh << 'BT_EOF'
#!/bin/bash
echo "🔵 Bluetooth Speaker Pairing Helper"
echo "=================================="
echo ""
echo "1. Turn on your Bluetooth speaker"
echo "2. Put it in pairing mode" 
echo "3. Run the following commands:"
echo ""
echo "bluetoothctl"
echo "scan on"
echo "# Wait for your speaker to appear, note MAC address"
echo "pair XX:XX:XX:XX:XX:XX"
echo "trust XX:XX:XX:XX:XX:XX"  
echo "connect XX:XX:XX:XX:XX:XX"
echo "exit"
echo ""
echo "4. Set as default audio output:"
echo "pacmd set-default-sink bluez_sink.XX_XX_XX_XX_XX_XX.a2dp_sink"
echo ""
echo "5. Test audio:"
echo "aplay /usr/share/sounds/alsa/Front_Left.wav"
BT_EOF

chmod +x ~/homecoming_pi/pair_bluetooth.sh
echo_success "Bluetooth helper created"

# Step 10: Final status
echo ""
echo_success "🎵 Homecoming Pi Music System Deployed Successfully!"
echo ""
echo "📁 Files created in ~/homecoming_pi/:"
echo "  • music_player_service.py - Main music system"
echo "  • test_music.py - Test script"  
echo "  • pair_bluetooth.sh - Bluetooth pairing helper"
echo "  • music/ - Generated music files"
echo "  • logs/ - System logs"
echo ""
echo "🎯 Next steps:"
echo "  1. Pair Bluetooth speaker: ./pair_bluetooth.sh"
echo "  2. Test system: python3 test_music.py"
echo "  3. Test mobile app music controls"
echo ""
echo "🎵 Your Pi music system is ready! 🔊"