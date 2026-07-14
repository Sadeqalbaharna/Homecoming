#!/usr/bin/env python3
"""
Music Player Service for Homecoming Pi
Handles music playback requests with Bluetooth audio output
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

# Try importing required audio libraries
try:
    import pygame
    pygame.mixer.init()
    PYGAME_AVAILABLE = True
except ImportError:
    PYGAME_AVAILABLE = False
    print("Warning: pygame not available, using mpg123 fallback")

try:
    from bluetooth_audio_manager import BluetoothAudioManager
except ImportError:
    print("Warning: BluetoothAudioManager not available")
    BluetoothAudioManager = None

class MusicPlayerService:
    def __init__(self):
        self.logger = self._setup_logging()
        self.audio_manager = BluetoothAudioManager() if BluetoothAudioManager else None
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
        
        # Built-in song library with YouTube/streaming alternatives
        self.song_library = {
            # Upbeat/Electronic
            'electronic_beat': {
                'name': 'Electronic Beat',
                'genre': 'electronic',
                'mood': 'energetic',
                'file': 'electronic_beat.mp3',
                'duration': 180,
                'description': 'Upbeat electronic music perfect for coding or working'
            },
            'synthwave_nights': {
                'name': 'Synthwave Nights',
                'genre': 'synthwave',
                'mood': 'cool',
                'file': 'synthwave_nights.mp3',
                'duration': 240,
                'description': 'Retro synthwave with neon vibes'
            },
            
            # Relaxing/Ambient
            'ambient_space': {
                'name': 'Ambient Space',
                'genre': 'ambient',
                'mood': 'relaxing',
                'file': 'ambient_space.mp3',
                'duration': 300,
                'description': 'Peaceful ambient sounds for relaxation'
            },
            'nature_sounds': {
                'name': 'Nature Sounds',
                'genre': 'nature',
                'mood': 'peaceful',
                'file': 'nature_sounds.mp3',
                'duration': 600,
                'description': 'Calming nature sounds with birds and water'
            },
            
            # Classical/Instrumental
            'piano_meditation': {
                'name': 'Piano Meditation',
                'genre': 'classical',
                'mood': 'meditative',
                'file': 'piano_meditation.mp3',
                'duration': 280,
                'description': 'Gentle piano melodies for focus and calm'
            },
            
            # Lo-fi/Chill
            'lofi_study': {
                'name': 'Lo-Fi Study',
                'genre': 'lofi',
                'mood': 'focused',
                'file': 'lofi_study.mp3',
                'duration': 200,
                'description': 'Lo-fi hip hop beats for studying and concentration'
            },
            
            # Gaming/Chiptune
            'chiptune_adventure': {
                'name': 'Chiptune Adventure',
                'genre': 'chiptune',
                'mood': 'playful',
                'file': 'chiptune_adventure.mp3',
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
                        # Electronic beat
                        cmd = [
                            'sox', '-n', str(file_path), 'synth', str(info['duration']),
                            'sine', '440', 'sine', '880', 'sine', '1320',
                            'tremolo', '4', '40', 'reverb', 'vol', '0.3'
                        ]
                    elif info['genre'] == 'ambient':
                        # Ambient sounds
                        cmd = [
                            'sox', '-n', str(file_path), 'synth', str(info['duration']),
                            'sine', '220', 'sine', '330', 'sine', '440',
                            'tremolo', '0.5', '20', 'reverb', '50', 'vol', '0.2'
                        ]
                    elif info['genre'] == 'nature':
                        # Nature sounds simulation
                        cmd = [
                            'sox', '-n', str(file_path), 'synth', str(info['duration']),
                            'noise', 'highpass', '1000', 'lowpass', '8000',
                            'tremolo', '0.1', '5', 'vol', '0.1'
                        ]
                    elif info['genre'] == 'classical':
                        # Piano-like tones
                        cmd = [
                            'sox', '-n', str(file_path), 'synth', str(info['duration']),
                            'pluck', 'C4', 'pluck', 'E4', 'pluck', 'G4',
                            'reverb', '30', 'vol', '0.4'
                        ]
                    elif info['genre'] == 'chiptune':
                        # 8-bit style
                        cmd = [
                            'sox', '-n', str(file_path), 'synth', str(info['duration']),
                            'square', '440', 'square', '660', 'square', '880',
                            'tremolo', '8', '50', 'vol', '0.3'
                        ]
                    else:
                        # Default lo-fi style
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
    
    def get_available_songs(self) -> Dict[str, Any]:
        """Get list of available songs"""
        available = {}
        
        for song_id, info in self.song_library.items():
            file_path = self.music_directory / info['file']
            if file_path.exists():
                available[song_id] = {
                    **info,
                    'available': True,
                    'file_path': str(file_path)
                }
            else:
                available[song_id] = {
                    **info,
                    'available': False,
                    'file_path': None
                }
        
        return available
    
    def find_song(self, query: str) -> Optional[str]:
        """Find a song by name, genre, or mood"""
        query_lower = query.lower()
        
        # Direct name match
        for song_id, info in self.song_library.items():
            if query_lower in info['name'].lower():
                return song_id
        
        # Genre match
        for song_id, info in self.song_library.items():
            if query_lower in info['genre'].lower():
                return song_id
        
        # Mood match
        for song_id, info in self.song_library.items():
            if query_lower in info['mood'].lower():
                return song_id
        
        # Description match
        for song_id, info in self.song_library.items():
            if query_lower in info['description'].lower():
                return song_id
        
        return None
    
    def play_song(self, song_id: str) -> Dict[str, Any]:
        """Play a specific song"""
        try:
            if song_id not in self.song_library:
                return {'success': False, 'message': f'Song "{song_id}" not found'}
            
            song_info = self.song_library[song_id]
            file_path = self.music_directory / song_info['file']
            
            if not file_path.exists():
                return {'success': False, 'message': f'Audio file for "{song_info["name"]}" not found'}
            
            # Stop current playback
            self.stop_music()
            
            # Play via Bluetooth audio
            if self.audio_manager:
                success = self.audio_manager.play_audio_file(str(file_path))
                if success:
                    self.current_song = song_id
                    self.is_playing = True
                    self.is_paused = False
                    
                    # Announce what's playing
                    announcement = f"Now playing {song_info['name']}, {song_info['description']}"
                    self.audio_manager.play_text_to_speech(announcement)
                    
                    self.logger.info(f"🎵 Playing: {song_info['name']}")
                    return {
                        'success': True,
                        'message': announcement,
                        'song': song_info,
                        'song_id': song_id
                    }
            
            return {'success': False, 'message': 'Audio playback failed'}
            
        except Exception as e:
            self.logger.error(f"Error playing song: {e}")
            return {'success': False, 'message': str(e)}
    
    def play_mood_playlist(self, mood: str) -> Dict[str, Any]:
        """Play a playlist based on mood"""
        try:
            mood_lower = mood.lower()
            
            if mood_lower not in self.mood_playlists:
                available_moods = ', '.join(self.mood_playlists.keys())
                return {
                    'success': False, 
                    'message': f'Mood "{mood}" not recognized. Available moods: {available_moods}'
                }
            
            playlist = self.mood_playlists[mood_lower]
            if not playlist:
                return {'success': False, 'message': f'No songs available for {mood} mood'}
            
            # Start playlist
            self.current_playlist = playlist.copy()
            self.current_index = 0
            random.shuffle(self.current_playlist)  # Shuffle for variety
            
            # Play first song
            first_song = self.current_playlist[0]
            result = self.play_song(first_song)
            
            if result['success']:
                announcement = f"Playing {mood} mood playlist. {len(playlist)} songs queued."
                if self.audio_manager:
                    self.audio_manager.play_text_to_speech(announcement)
                
                result['playlist_info'] = {
                    'mood': mood,
                    'total_songs': len(playlist),
                    'current_index': 0,
                    'playlist': self.current_playlist
                }
            
            return result
            
        except Exception as e:
            self.logger.error(f"Error playing mood playlist: {e}")
            return {'success': False, 'message': str(e)}
    
    def next_song(self) -> Dict[str, Any]:
        """Play next song in playlist"""
        try:
            if not self.current_playlist:
                return {'success': False, 'message': 'No playlist active'}
            
            self.current_index = (self.current_index + 1) % len(self.current_playlist)
            next_song_id = self.current_playlist[self.current_index]
            
            return self.play_song(next_song_id)
            
        except Exception as e:
            return {'success': False, 'message': str(e)}
    
    def previous_song(self) -> Dict[str, Any]:
        """Play previous song in playlist"""
        try:
            if not self.current_playlist:
                return {'success': False, 'message': 'No playlist active'}
            
            self.current_index = (self.current_index - 1) % len(self.current_playlist)
            prev_song_id = self.current_playlist[self.current_index]
            
            return self.play_song(prev_song_id)
            
        except Exception as e:
            return {'success': False, 'message': str(e)}
    
    def stop_music(self) -> Dict[str, Any]:
        """Stop music playback"""
        try:
            if PYGAME_AVAILABLE:
                pygame.mixer.music.stop()
            
            # Stop any audio pipeline
            if self.audio_manager and hasattr(self.audio_manager, 'pipeline'):
                if self.audio_manager.pipeline:
                    self.audio_manager.pipeline.set_state(0)  # GST_STATE_NULL
            
            self.is_playing = False
            self.is_paused = False
            self.current_song = None
            
            return {'success': True, 'message': 'Music stopped'}
            
        except Exception as e:
            return {'success': False, 'message': str(e)}
    
    def handle_voice_command(self, command: str) -> Dict[str, Any]:
        """Handle voice commands for music control"""
        command_lower = command.lower()
        
        # Play commands
        if any(word in command_lower for word in ['play', 'music', 'song']):
            
            # Stop music
            if any(word in command_lower for word in ['stop', 'pause', 'quit']):
                result = self.stop_music()
                if self.audio_manager:
                    self.audio_manager.play_text_to_speech("Music stopped.")
                return result
            
            # Next/Previous
            elif 'next' in command_lower:
                result = self.next_song()
                return result
            elif any(word in command_lower for word in ['previous', 'prev', 'back']):
                result = self.previous_song() 
                return result
            
            # Mood-based requests
            elif any(mood in command_lower for mood in self.mood_playlists.keys()):
                for mood in self.mood_playlists.keys():
                    if mood in command_lower:
                        return self.play_mood_playlist(mood)
            
            # Genre-based requests  
            elif any(word in command_lower for word in ['electronic', 'ambient', 'classical', 'lofi', 'chiptune']):
                for song_id, info in self.song_library.items():
                    if info['genre'].lower() in command_lower:
                        return self.play_song(song_id)
            
            # Random song
            elif any(word in command_lower for word in ['random', 'surprise', 'anything']):
                available = [sid for sid, info in self.song_library.items() 
                           if (self.music_directory / info['file']).exists()]
                if available:
                    song_id = random.choice(available)
                    return self.play_song(song_id)
                else:
                    return {'success': False, 'message': 'No music files available'}
            
            # Default: play first available song
            else:
                available = [sid for sid, info in self.song_library.items() 
                           if (self.music_directory / info['file']).exists()]
                if available:
                    return self.play_song(available[0])
        
        return {'success': False, 'message': 'Music command not recognized'}

def main():
    """Test the music player service"""
    print("🎵 Homecoming Pi Music Player Test")
    print("=" * 40)
    
    music_player = MusicPlayerService()
    
    # Generate sample music if needed
    print("📀 Generating sample music files...")
    music_player.generate_sample_music()
    
    # Show available songs
    print("\n🎶 Available Songs:")
    songs = music_player.get_available_songs()
    for song_id, info in songs.items():
        status = "✅" if info['available'] else "❌"
        print(f"  {status} {info['name']} ({info['genre']}) - {info['mood']}")
    
    print("\n🧪 Testing Voice Commands:")
    test_commands = [
        "Play some energetic music",
        "Play relaxing mood playlist", 
        "Play electronic music",
        "Play something random",
        "Next song",
        "Stop music"
    ]
    
    for command in test_commands:
        print(f"\n🎤 Command: '{command}'")
        result = music_player.handle_voice_command(command)
        print(f"   Result: {result['message']}")
        time.sleep(2)

if __name__ == "__main__":
    main()