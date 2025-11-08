#!/usr/bin/env python3
"""
Music Setup and Test Suite for Homecoming Pi
Comprehensive testing for music playback capabilities
"""

import os
import time
import json
import subprocess
from pathlib import Path
from music_player_service import MusicPlayerService
from voice_enabled_home_automation import VoiceEnabledHomeAutomation

def setup_music_dependencies():
    """Install required dependencies for music playback"""
    print("🎵 Setting up Music Dependencies...")
    
    dependencies = [
        'sox',           # Audio processing
        'libsox-fmt-all', # Sox format support
        'mpg123',        # MP3 playback
        'alsa-utils',    # Audio utilities
        'python3-pygame', # Python audio library
        'ffmpeg'         # Audio conversion
    ]
    
    for dep in dependencies:
        print(f"📦 Installing {dep}...")
        try:
            result = subprocess.run(['sudo', 'apt', 'install', '-y', dep], 
                                  capture_output=True, text=True)
            if result.returncode == 0:
                print(f"✅ {dep} installed")
            else:
                print(f"❌ {dep} failed: {result.stderr}")
        except Exception as e:
            print(f"❌ Error installing {dep}: {e}")

def test_music_generation():
    """Test music file generation"""
    print("\n🎼 Testing Music File Generation...")
    
    music_player = MusicPlayerService()
    music_player.generate_sample_music()
    
    songs = music_player.get_available_songs()
    available_count = sum(1 for s in songs.values() if s['available'])
    
    print(f"📀 Generated {available_count}/{len(songs)} music files")
    
    for song_id, info in songs.items():
        status = "✅" if info['available'] else "❌"
        print(f"  {status} {info['name']} ({info['genre']}, {info['mood']})")
    
    return available_count > 0

def test_music_playback():
    """Test individual song playback"""
    print("\n🎵 Testing Music Playback...")
    
    music_player = MusicPlayerService()
    
    # Test playing different songs
    test_songs = ['electronic_beat', 'ambient_space', 'chiptune_adventure']
    
    for song_id in test_songs:
        if song_id in music_player.song_library:
            print(f"🎶 Testing: {music_player.song_library[song_id]['name']}")
            result = music_player.play_song(song_id)
            
            if result['success']:
                print(f"✅ Playing: {result['message']}")
                time.sleep(3)  # Let it play for a bit
                music_player.stop_music()
                time.sleep(1)
            else:
                print(f"❌ Failed: {result['message']}")

def test_mood_playlists():
    """Test mood-based playlists"""
    print("\n🎭 Testing Mood Playlists...")
    
    music_player = MusicPlayerService()
    
    test_moods = ['energetic', 'relaxing', 'focused']
    
    for mood in test_moods:
        print(f"🎵 Testing {mood} mood playlist...")
        result = music_player.play_mood_playlist(mood)
        
        if result['success']:
            print(f"✅ {mood.title()} playlist: {result['message']}")
            if 'playlist_info' in result:
                info = result['playlist_info']
                print(f"   📋 {info['total_songs']} songs in playlist")
            
            time.sleep(3)  # Let it play
            
            # Test next song
            print("   ⏭️ Testing next song...")
            next_result = music_player.next_song()
            if next_result['success']:
                print("   ✅ Next song working")
            
            music_player.stop_music()
            time.sleep(1)
        else:
            print(f"❌ {mood.title()} playlist failed: {result['message']}")

def test_voice_commands():
    """Test voice commands for music"""
    print("\n🎤 Testing Voice Commands...")
    
    automation = VoiceEnabledHomeAutomation()
    
    voice_commands = [
        "Play some energetic music",
        "Play relaxing playlist", 
        "Play electronic music",
        "Play something random",
        "Stop the music",
        "Play chiptune adventure",
        "Play focused mood",
    ]
    
    for command in voice_commands:
        print(f"🎤 Command: '{command}'")
        result = automation.handle_voice_command(command)
        
        if result['success']:
            print(f"✅ Response: {result['message']}")
        else:
            print(f"❌ Failed: {result['message']}")
        
        time.sleep(2)

def test_mobile_integration():
    """Test integration with mobile app commands"""
    print("\n📱 Testing Mobile App Integration...")
    
    # Simulate Firebase commands that mobile app would send
    test_commands = [
        {
            'target': 'music',
            'action': 'play_mood',
            'params': {'mood': 'energetic'}
        },
        {
            'target': 'music', 
            'action': 'play_song',
            'params': {'song': 'ambient_space'}
        },
        {
            'target': 'music',
            'action': 'stop'
        }
    ]
    
    music_player = MusicPlayerService()
    
    for i, cmd in enumerate(test_commands, 1):
        print(f"📱 Mobile Command {i}: {cmd['action']}")
        
        if cmd['action'] == 'play_mood':
            result = music_player.play_mood_playlist(cmd['params']['mood'])
        elif cmd['action'] == 'play_song':
            result = music_player.play_song(cmd['params']['song'])
        elif cmd['action'] == 'stop':
            result = music_player.stop_music()
        
        print(f"   {'✅' if result['success'] else '❌'} {result['message']}")
        time.sleep(2)

def interactive_music_test():
    """Interactive music testing"""
    print("\n🎮 Interactive Music Test")
    print("=" * 40)
    print("Commands: play <song/mood>, stop, next, prev, list, quit")
    
    music_player = MusicPlayerService()
    
    while True:
        try:
            command = input("\n🎵 Music command: ").strip().lower()
            
            if command == 'quit':
                music_player.stop_music()
                print("👋 Music test ended")
                break
            
            elif command == 'list':
                songs = music_player.get_available_songs()
                print("\n🎶 Available Songs:")
                for song_id, info in songs.items():
                    status = "✅" if info['available'] else "❌"
                    print(f"  {status} {song_id}: {info['name']} ({info['genre']}, {info['mood']})")
                
                print(f"\n🎭 Available Moods: {', '.join(music_player.mood_playlists.keys())}")
            
            elif command == 'stop':
                result = music_player.stop_music()
                print(f"🛑 {result['message']}")
            
            elif command == 'next':
                result = music_player.next_song()
                print(f"⏭️ {result['message']}")
            
            elif command in ['prev', 'previous']:
                result = music_player.previous_song()
                print(f"⏮️ {result['message']}")
            
            elif command.startswith('play '):
                query = command[5:]  # Remove 'play '
                
                # Try as mood first
                if query in music_player.mood_playlists:
                    result = music_player.play_mood_playlist(query)
                else:
                    # Try to find song
                    song_id = music_player.find_song(query)
                    if song_id:
                        result = music_player.play_song(song_id)
                    else:
                        result = {'success': False, 'message': f'Song/mood "{query}" not found'}
                
                print(f"🎵 {result['message']}")
            
            else:
                result = music_player.handle_voice_command(command)
                print(f"🎵 {result['message']}")
                
        except KeyboardInterrupt:
            print("\n🛑 Stopping music...")
            music_player.stop_music()
            break

def main():
    """Main test runner"""
    print("🎵 Homecoming Pi Music System Test Suite")
    print("=" * 50)
    
    # Setup
    print("🔧 Setting up music system...")
    setup_music_dependencies()
    
    # Run tests
    tests = [
        ("Music File Generation", test_music_generation),
        ("Music Playback", test_music_playback),
        ("Mood Playlists", test_mood_playlists),
        ("Voice Commands", test_voice_commands),
        ("Mobile Integration", test_mobile_integration)
    ]
    
    for test_name, test_func in tests:
        print(f"\n🧪 Running: {test_name}")
        try:
            result = test_func()
            print(f"{'✅' if result != False else '❌'} {test_name} completed")
        except Exception as e:
            print(f"❌ {test_name} failed: {e}")
        
        time.sleep(1)
    
    # Interactive test
    print(f"\n🎮 Starting Interactive Music Test...")
    interactive_music_test()

if __name__ == "__main__":
    main()