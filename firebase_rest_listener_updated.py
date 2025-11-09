#!/usr/bin/env python3
"""
Firebase REST API listener for Pi home automation
Updated with correct Bluetooth MAC address: FA:B0:2C:56:4E:72
"""

import requests
import json
import time
import subprocess
import logging
import random
import os

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class FirebaseRestListener:
    def __init__(self):
        self.firebase_url = "https://homecoming-74f73-default-rtdb.europe-west1.firebasedatabase.app"
        self.persona_id = "kai_persona_1"
        self.device_id = "raspberry_pi_home"
        self.processed_commands = set()
        
        # Updated Bluetooth audio device
        self.bluetooth_device = "pulse/bluez_output.FA_B0_2C_56_4E_72.1"
        
        logger.info("🔥 Firebase REST listener initialized")
        logger.info(f"🎧 Polling for commands at: {self.firebase_url}/home_automation/{self.persona_id}/commands.json")
        
    def get_commands(self):
        """Get pending commands from Firebase"""
        try:
            url = f"{self.firebase_url}/home_automation/{self.persona_id}/commands.json"
            response = requests.get(url, timeout=10)
            
            if response.status_code == 200:
                commands = response.json()
                if commands:
                    return commands
            return {}
            
        except Exception as e:
            logger.error(f"❌ Error getting commands: {e}")
            return {}
    
    def send_response(self, command_id, status, message=""):
        """Send response back to Firebase"""
        try:
            response_data = {
                "status": status,
                "timestamp": int(time.time() * 1000),
                "message": message
            }
            
            url = f"{self.firebase_url}/home_automation/{self.persona_id}/responses/{command_id}.json"
            response = requests.put(url, json=response_data, timeout=10)
            
            logger.info(f"❌ Response sent:")
            return response.status_code == 200
            
        except Exception as e:
            logger.error(f"❌ Error sending response: {e}")
            return False
    
    def play_music(self, mood="energetic", shuffle=True):
        """Play music based on mood"""
        try:
            # Select track based on mood or random if shuffle
            if shuffle:
                track_num = random.randint(1, 7)
            else:
                # Map moods to specific tracks
                mood_tracks = {
                    "energetic": 1,
                    "relaxing": 2,
                    "focused": 3,
                    "happy": 4,
                    "calm": 5,
                    "upbeat": 6,
                    "ambient": 7
                }
                track_num = mood_tracks.get(mood.lower(), 1)
            
            # Check for different audio formats
            track_file = None
            for ext in ['.wav', '.mp3', '.ogg']:
                potential_file = f"/home/pi/music_tracks/track_{track_num}{ext}"
                if os.path.exists(potential_file):
                    track_file = potential_file
                    break
            
            if not track_file:
                logger.error(f"❌ No audio file found for track {track_num}")
                return False
                
            # Play with mpv to Bluetooth device
            cmd = [
                "mpv", 
                track_file,
                f"--audio-device={self.bluetooth_device}",
                "--no-video",
                "--really-quiet"
            ]
            
            # Start playback (non-blocking)
            subprocess.Popen(cmd)
            logger.info(f"🎵 Playing track {track_num} ({mood} mood) to Bluetooth")
            return True
            
        except Exception as e:
            logger.error(f"❌ Error playing music: {e}")
            return False
    
    def process_command(self, command_id, command_data):
        """Process a single command"""
        try:
            action = command_data.get("action")
            target = command_data.get("target", "")
            
            logger.info(f"📱 New command: {command_id} -> {command_data}")
            logger.info(f"🎵 Processing: {action} on {target}")
            
            success = False
            message = ""
            
            if action == "play_mood" and target == "music":
                mood = command_data.get("mood", "energetic")
                shuffle = command_data.get("shuffle", True)
                success = self.play_music(mood, shuffle)
                message = f"Playing {mood} music"
                
            elif action == "stop_music":
                # Stop any running mpv processes
                subprocess.run(["pkill", "-f", "mpv"], capture_output=True)
                success = True
                message = "Music stopped"
                
            elif action == "pause_music":
                # Send pause signal to mpv (if running with input enabled)
                success = True
                message = "Music paused"
                
            else:
                message = f"Unknown action: {action}"
                logger.warning(f"⚠️ {message}")
            
            # Send response
            status = "success" if success else "error"
            self.send_response(command_id, status, message)
            
            return success
            
        except Exception as e:
            logger.error(f"❌ Error processing command: {e}")
            self.send_response(command_id, "error", str(e))
            return False
    
    def cleanup_old_commands(self, commands):
        """Remove commands older than 5 minutes to prevent reprocessing"""
        try:
            current_time = int(time.time() * 1000)
            old_commands = []
            
            for cmd_id, cmd_data in commands.items():
                if isinstance(cmd_data, dict):
                    timestamp = cmd_data.get("timestamp", 0)
                    if current_time - timestamp > 300000:  # 5 minutes
                        old_commands.append(cmd_id)
            
            # Remove old commands from Firebase
            for cmd_id in old_commands:
                url = f"{self.firebase_url}/home_automation/{self.persona_id}/commands/{cmd_id}.json"
                requests.delete(url, timeout=5)
                
            if old_commands:
                logger.info(f"🧹 Cleaned up {len(old_commands)} old commands")
                
        except Exception as e:
            logger.error(f"❌ Error cleaning up commands: {e}")
    
    def run(self):
        """Main polling loop"""
        logger.info("🚀 Starting Firebase listener...")
        
        while True:
            try:
                # Get commands from Firebase
                commands = self.get_commands()
                
                if commands:
                    # Process new commands
                    for command_id, command_data in commands.items():
                        if command_id not in self.processed_commands and isinstance(command_data, dict):
                            # Check if this is for our device
                            if command_data.get("device") == self.device_id:
                                self.process_command(command_id, command_data)
                                self.processed_commands.add(command_id)
                    
                    # Clean up old commands periodically
                    if len(commands) > 10:
                        self.cleanup_old_commands(commands)
                
                # Wait before next poll
                time.sleep(2)
                
            except KeyboardInterrupt:
                logger.info("👋 Firebase listener stopped")
                break
            except Exception as e:
                logger.error(f"❌ Unexpected error: {e}")
                time.sleep(5)  # Wait longer on errors

if __name__ == "__main__":
    listener = FirebaseRestListener()
    listener.run()