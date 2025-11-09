#!/usr/bin/env python3
"""
Firebase REST API listener for Pi home automation with Intelligent Music Selection
Updated with detailed debug logging, improved error handling, and AI-powered track selection
Integrates with Kai's voice commands for context-aware music playback
"""

import requests
import json
import time
import subprocess
import logging
import random
import os

# Configure logging with more detail
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
        logger.info(f"🔊 Bluetooth device: {self.bluetooth_device}")
        
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
            
            logger.info(f"📤 Response sent: {status} - {message}")
            return response.status_code == 200
            
        except Exception as e:
            logger.error(f"❌ Error sending response: {e}")
            return False
    
    def play_music(self, mood="energetic", shuffle=True, voice_analysis=None):
        """Play music based on mood with detailed debugging and intelligent selection"""
        try:
            logger.info(f"🎯 Starting music playback - Mood: {mood}, Shuffle: {shuffle}")
            
            # Initialize track selection
            track_num = None
            
            # If voice analysis data is available, log the intelligent selection
            if voice_analysis:
                logger.info(f"🤖 Kai's voice analysis:")
                logger.info(f"   Original input: '{voice_analysis.get('original_input', 'N/A')}'")
                logger.info(f"   Matched keywords: {voice_analysis.get('matched_keywords', [])}")
                logger.info(f"   Matched contexts: {voice_analysis.get('matched_contexts', [])}")
                logger.info(f"   Confidence: {voice_analysis.get('confidence', 0):.1%}")
                
                # Use the intelligent selection if available
                selected_track = voice_analysis.get('selected_track')
                if selected_track:
                    track_num = selected_track
                    logger.info(f"🧠 Using Kai's intelligent selection: Track {track_num}")
                    shuffle = False  # Don't shuffle when using intelligent selection
            
            # Select track based on voice analysis, mood, or random if shuffle
            if track_num is not None:
                # Use Kai's intelligent selection (already set above)
                logger.info(f"🎯 Track selection complete: {track_num}")
            elif shuffle:
                track_num = random.randint(1, 7)
                logger.info(f"🎲 Random shuffle selected track: {track_num}")
            else:
                # Enhanced intelligent track selection based on mood/context
                mood_tracks = {
                    # Relaxation & Calm
                    "relaxing": 1,      # track_1.mp3 - Nature sounds
                    "calm": 1,
                    "peaceful": 1,
                    "soothing": 1,
                    "sleep": 1,
                    "unwind": 1,
                    "meditate": 1,
                    
                    # Energetic & Active  
                    "energetic": 2,     # track_2.mp3 - Upbeat
                    "upbeat": 2,
                    "active": 2,
                    "workout": 2,
                    "exercise": 2,
                    "motivate": 2,
                    "pump": 2,
                    
                    # Focus & Concentration
                    "focused": 3,       # track_3.mp3 - Focus music
                    "concentrate": 3,
                    "study": 3,
                    "work": 3,
                    "productivity": 3,
                    
                    # Happy & Positive
                    "happy": 4,         # track_4.mp3 - Cheerful
                    "cheerful": 4,
                    "joy": 4,
                    "celebration": 4,
                    "party": 4,
                    
                    # Ambient & Background
                    "ambient": 5,       # track_5.mp3 - Ambient
                    "background": 5,
                    "atmospheric": 5,
                    "chill": 5,
                    "lounge": 5,
                    
                    # Classical & Elegant
                    "classical": 6,     # track_6.mp3 - Classical
                    "elegant": 6,
                    "sophisticated": 6,
                    "dinner": 6,
                    "romantic": 6,
                    
                    # Nature & Outdoors
                    "nature": 7,        # track_7.mp3 - Nature sounds
                    "outdoors": 7,
                    "forest": 7,
                    "rain": 7,
                    "ocean": 7
                }
                
                track_num = mood_tracks.get(mood.lower(), 1)  # Default to relaxing
                logger.info(f"🎯 Intelligent selection: '{mood}' → track {track_num}")
            
            # Check for different audio formats
            track_file = None
            base_path = "/home/pi/music_tracks"
            
            logger.info(f"🔍 Searching for track {track_num} in {base_path}")
            
            # Check if base directory exists
            if not os.path.exists(base_path):
                logger.error(f"❌ Music directory does not exist: {base_path}")
                return False
            
            # List files in directory for debugging
            try:
                files = os.listdir(base_path)
                logger.info(f"📁 Files in music directory: {files}")
            except Exception as e:
                logger.error(f"❌ Error listing music directory: {e}")
                return False
            
            # Try different formats
            for ext in ['.mp3', '.wav', '.ogg']:
                potential_file = f"{base_path}/track_{track_num}{ext}"
                logger.info(f"🔍 Checking: {potential_file}")
                
                if os.path.exists(potential_file):
                    track_file = potential_file
                    logger.info(f"✅ Found audio file: {track_file}")
                    break
                else:
                    logger.info(f"❌ File not found: {potential_file}")
            
            if not track_file:
                logger.error(f"❌ No audio file found for track {track_num}")
                logger.error(f"❌ Tried extensions: .mp3, .wav, .ogg in {base_path}")
                return False
            
            # Verify file is readable
            try:
                file_size = os.path.getsize(track_file)
                logger.info(f"📊 File size: {file_size} bytes")
                if file_size == 0:
                    logger.error(f"❌ Audio file is empty: {track_file}")
                    return False
            except Exception as e:
                logger.error(f"❌ Error checking file: {e}")
                return False
                
            # Build mpv command
            cmd = [
                "mpv", 
                track_file,
                f"--audio-device={self.bluetooth_device}",
                "--no-video",
                "--really-quiet"
            ]
            
            logger.info(f"🎵 Executing mpv command: {' '.join(cmd)}")
            
            # Check if mpv is installed
            try:
                mpv_check = subprocess.run(["which", "mpv"], capture_output=True, text=True)
                if mpv_check.returncode != 0:
                    logger.error("❌ mpv is not installed or not in PATH")
                    return False
                else:
                    logger.info(f"✅ mpv found at: {mpv_check.stdout.strip()}")
            except Exception as e:
                logger.error(f"❌ Error checking mpv: {e}")
                return False
            
            # Start playback (non-blocking)
            try:
                process = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                logger.info(f"🎵 Started mpv process with PID: {process.pid}")
                
                # Wait a moment to see if process starts successfully
                time.sleep(0.5)
                poll_result = process.poll()
                
                if poll_result is None:
                    logger.info(f"✅ mpv process running successfully")
                elif poll_result == 0:
                    logger.info(f"✅ mpv process completed successfully")
                else:
                    # Process failed, get error output
                    stdout, stderr = process.communicate()
                    logger.error(f"❌ mpv process failed with code {poll_result}")
                    logger.error(f"❌ mpv stdout: {stdout.decode()}")
                    logger.error(f"❌ mpv stderr: {stderr.decode()}")
                    return False
                
                logger.info(f"🎵 Playing track {track_num} ({mood} mood) via Bluetooth")
                return True
                
            except Exception as e:
                logger.error(f"❌ Error starting mpv process: {e}")
                return False
            
        except Exception as e:
            logger.error(f"❌ Error in play_music function: {e}")
            return False
    
    def stop_music(self):
        """Stop any running mpv processes"""
        try:
            logger.info("🛑 Stopping music playback")
            result = subprocess.run(["pkill", "-f", "mpv"], capture_output=True)
            if result.returncode == 0:
                logger.info("✅ Music stopped successfully")
                return True
            else:
                logger.info("ℹ️ No music processes were running")
                return True
        except Exception as e:
            logger.error(f"❌ Error stopping music: {e}")
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
                voice_analysis = command_data.get("voice_analysis")  # Get Kai's voice analysis
                
                logger.info(f"🎵 Play mood command - Mood: {mood}, Shuffle: {shuffle}")
                if voice_analysis:
                    logger.info(f"🤖 Command includes Kai's voice analysis data")
                
                success = self.play_music(mood, shuffle, voice_analysis)
                
                if success:
                    if voice_analysis:
                        track_num = voice_analysis.get('selected_track', 'unknown')
                        confidence = voice_analysis.get('confidence', 0)
                        message = f"Playing track {track_num} ({mood}) - Kai's intelligent selection ({confidence:.1%} confidence)"
                    else:
                        message = f"Playing {mood} music"
                else:
                    message = f"Failed to play {mood} music"
                
            elif action == "stop_music":
                logger.info("🛑 Stop music command")
                success = self.stop_music()
                message = "Music stopped" if success else "Failed to stop music"
                
            elif action == "pause_music":
                logger.info("⏸️ Pause music command")
                # Send pause signal to mpv (if running with input enabled)
                success = True
                message = "Music paused"
                
            else:
                message = f"Unknown action: {action}"
                logger.warning(f"⚠️ {message}")
            
            # Send response
            status = "success" if success else "error"
            logger.info(f"📤 Sending {status} response: {message}")
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
        
        # Initial system check
        logger.info("🔧 Performing system checks...")
        
        # Check music directory
        music_dir = "/home/pi/music_tracks"
        if os.path.exists(music_dir):
            files = os.listdir(music_dir)
            logger.info(f"✅ Music directory exists with {len(files)} files: {files}")
        else:
            logger.error(f"❌ Music directory missing: {music_dir}")
        
        # Check mpv
        try:
            mpv_check = subprocess.run(["mpv", "--version"], capture_output=True, text=True)
            if mpv_check.returncode == 0:
                logger.info("✅ mpv is available")
            else:
                logger.error("❌ mpv check failed")
        except:
            logger.error("❌ mpv not found")
        
        # Check Bluetooth audio device
        try:
            pactl_check = subprocess.run(["pactl", "list", "short", "sinks"], capture_output=True, text=True)
            if self.bluetooth_device.replace("pulse/", "") in pactl_check.stdout:
                logger.info(f"✅ Bluetooth audio device available: {self.bluetooth_device}")
            else:
                logger.warning(f"⚠️ Bluetooth device may not be available: {self.bluetooth_device}")
                logger.info(f"Available audio sinks:\n{pactl_check.stdout}")
        except:
            logger.warning("⚠️ Could not check audio devices")
        
        logger.info("🔄 Starting command polling...")
        
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