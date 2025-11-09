#!/usr/bin/env python3
"""
Firebase REST API listener for Pi home automation with Intelligent Music Selection
Updated with comprehensive tagging system and intelligent profile matching
Integrates with Kai's voice commands for context-aware music and lighting control
"""

import requests
import json
import time
import subprocess
import logging
import random
import os
from typing import Dict, List, Optional, Tuple

# Configure logging with more detail
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class IntelligentProfileMatcher:
    """Intelligent profile matching system for coordinated music and lighting"""
    
    def __init__(self):
        self.profiles = {
            # Track 1: Nature/Forest Sounds
            "nature_forest": {
                "track": 1,
                "lighting": {"color": "light_green", "brightness": 70, "effect": "gentle_pulse"},
                "tags": {
                    "primary": ["nature", "forest", "relaxing", "woods"],
                    "secondary": ["trees", "peaceful", "calm", "natural", "green", "outdoor"],
                    "moods": ["zen", "meditation", "stress-relief", "tranquil"],
                    "activities": ["reading", "studying", "sleeping", "yoga"],
                    "aliases": ["forest", "woods", "nature", "trees", "outdoor"]
                },
                "confidence_boost": ["forest", "nature", "trees", "green"]
            },
            
            # Track 2: Energetic/Upbeat
            "energetic_upbeat": {
                "track": 2,
                "lighting": {"color": "yellow", "brightness": 85, "effect": "gentle_pulse"},
                "tags": {
                    "primary": ["energetic", "upbeat", "active", "motivational"],
                    "secondary": ["dynamic", "powerful", "intense", "bright", "yellow"],
                    "moods": ["motivated", "excited", "pumped", "confident", "positive"],
                    "activities": ["workout", "exercise", "cleaning", "dancing", "gaming"],
                    "aliases": ["energy", "workout", "pump", "active", "motivated"]
                },
                "confidence_boost": ["energetic", "workout", "active", "motivated"]
            },
            
            # Track 3: Focus/Concentration
            "focus_productivity": {
                "track": 3,
                "lighting": {"color": "white", "brightness": 80, "effect": "solid"},
                "tags": {
                    "primary": ["focus", "concentration", "productivity", "work"],
                    "secondary": ["study", "clear", "sharp", "white", "bright"],
                    "moods": ["concentrated", "alert", "determined", "serious"],
                    "activities": ["working", "studying", "coding", "writing", "analyzing"],
                    "aliases": ["focus", "work", "study", "concentration", "productivity"]
                },
                "confidence_boost": ["focus", "work", "study", "productivity"]
            },
            
            # Track 4: Happy/Cheerful
            "happy_cheerful": {
                "track": 4,
                "lighting": {"color": "orange", "brightness": 75, "effect": "gentle_pulse"},
                "tags": {
                    "primary": ["happy", "cheerful", "joyful", "celebration"],
                    "secondary": ["uplifting", "positive", "warm", "orange", "bright"],
                    "moods": ["joyful", "festive", "optimistic", "content", "playful"],
                    "activities": ["celebrating", "socializing", "cooking", "playing"],
                    "aliases": ["happy", "joy", "celebration", "cheerful", "positive"]
                },
                "confidence_boost": ["happy", "cheerful", "celebration", "joy"]
            },
            
            # Track 5: Ambient/Background
            "ambient_chill": {
                "track": 5,
                "lighting": {"color": "purple", "brightness": 45, "effect": "slow_fade"},
                "tags": {
                    "primary": ["ambient", "chill", "atmospheric", "background"],
                    "secondary": ["subtle", "flowing", "ethereal", "purple", "dreamy"],
                    "moods": ["relaxed", "contemplative", "creative", "flowing"],
                    "activities": ["creative-work", "art", "thinking", "lounging"],
                    "aliases": ["ambient", "chill", "atmospheric", "background", "creative"]
                },
                "confidence_boost": ["ambient", "chill", "atmospheric", "creative"]
            },
            
            # Track 6: Classical/Romantic
            "classical_romantic": {
                "track": 6,
                "lighting": {"color": "amber", "brightness": 30, "effect": "candle_flicker"},
                "tags": {
                    "primary": ["classical", "romantic", "elegant", "sophisticated"],
                    "secondary": ["intimate", "warm", "amber", "candlelight", "refined"],
                    "moods": ["romantic", "elegant", "peaceful", "sophisticated", "intimate"],
                    "activities": ["dinner", "date-night", "relaxing", "reading"],
                    "aliases": ["romantic", "classical", "elegant", "dinner", "intimate"]
                },
                "confidence_boost": ["romantic", "classical", "elegant", "dinner"]
            },
            
            # Track 7: Ocean/Water Sounds
            "ocean_water": {
                "track": 7,
                "lighting": {"color": "deep_blue", "brightness": 60, "effect": "wave"},
                "tags": {
                    "primary": ["ocean", "water", "waves", "sea"],
                    "secondary": ["blue", "flowing", "rhythmic", "deep", "aquatic"],
                    "moods": ["calm", "meditative", "peaceful", "flowing", "deep"],
                    "activities": ["meditation", "sleeping", "spa", "relaxing"],
                    "aliases": ["ocean", "sea", "waves", "water", "beach"]
                },
                "confidence_boost": ["ocean", "sea", "waves", "water"]
            }
        }
    
    def analyze_request(self, user_input: str) -> Optional[Dict]:
        """Analyze user input and return best matching profile"""
        clean_input = user_input.lower().replace(",", " ").replace(".", " ").replace("!", " ")
        user_words = set(word.strip() for word in clean_input.split() if word.strip())
        
        best_match = None
        best_score = 0.0
        
        logger.info(f"🔍 Analyzing: '{user_input}' -> words: {sorted(list(user_words))}")
        
        for profile_name, profile_data in self.profiles.items():
            score = self._calculate_match_score(user_words, profile_data)
            matched_tags = self._get_matched_tags(user_words, profile_data)
            
            logger.info(f"🎯 {profile_name}: {score:.3f} - {matched_tags}")
            
            if score > best_score:
                best_score = score
                best_match = {
                    "profile_name": profile_name,
                    "track": profile_data["track"],
                    "lighting": profile_data["lighting"],
                    "confidence": score,
                    "matched_tags": matched_tags
                }
        
        if best_score >= 0.2:  # 20% confidence threshold
            logger.info(f"✅ Match: {best_match['profile_name']} ({best_score:.1%})")
            return best_match
        else:
            logger.info(f"❌ No confident match (best: {best_score:.1%})")
            return None
    
    def _calculate_match_score(self, user_words: set, profile_data: Dict) -> float:
        """Calculate match score with enhanced weighting"""
        tags = profile_data["tags"]
        total_score = 0.0
        total_matches = 0
        
        # Check all tag categories with different weights
        primary_matches = len(user_words.intersection(set(tags["primary"])))
        total_score += primary_matches * 10.0
        total_matches += primary_matches
        
        secondary_matches = len(user_words.intersection(set(tags["secondary"])))
        total_score += secondary_matches * 6.0
        total_matches += secondary_matches
        
        mood_matches = len(user_words.intersection(set(tags["moods"])))
        total_score += mood_matches * 6.0
        total_matches += mood_matches
        
        activity_matches = len(user_words.intersection(set(tags["activities"])))
        total_score += activity_matches * 4.0
        total_matches += activity_matches
        
        confidence_boost_matches = len(user_words.intersection(set(profile_data["confidence_boost"])))
        total_score += confidence_boost_matches * 15.0
        total_matches += confidence_boost_matches
        
        alias_matches = len(user_words.intersection(set(tags["aliases"])))
        total_score += alias_matches * 20.0
        total_matches += alias_matches
        
        if total_matches == 0:
            return 0.0
        
        base_score = min(total_score / 100.0, 1.0)
        
        # Bonus for match diversity
        match_types = sum([
            primary_matches > 0,
            secondary_matches > 0, 
            mood_matches > 0,
            activity_matches > 0,
            confidence_boost_matches > 0,
            alias_matches > 0
        ])
        
        diversity_bonus = match_types * 0.1
        return min(base_score + diversity_bonus, 1.0)
    
    def _get_matched_tags(self, user_words: set, profile_data: Dict) -> List[str]:
        """Get list of matched tags"""
        matched = []
        tags = profile_data["tags"]
        
        for category in ["primary", "secondary", "moods", "activities", "aliases"]:
            matched.extend(user_words.intersection(set(tags[category])))
        
        matched.extend(user_words.intersection(set(profile_data["confidence_boost"])))
        return list(set(matched))
    
    def detect_gm_kai_mode(self, user_input: str) -> bool:
        """Detect if user activated GM Kai direct control mode"""
        lower_input = user_input.lower().strip()
        
        # GM Kai triggers
        gm_triggers = [
            'gm kai',
            'game master kai', 
            'gamemaster kai',
            'g.m. kai',
            'gm, kai',
            'hey gm kai',
            'gm kai,',
        ]
        
        # Check if input contains GM triggers
        for trigger in gm_triggers:
            if lower_input.startswith(trigger) or trigger in lower_input:
                return True
        
        return False

class FirebaseRestListener:
    def __init__(self):
        self.firebase_url = "https://homecoming-74f73-default-rtdb.europe-west1.firebasedatabase.app"
        self.persona_id = "kai_persona_1"
        self.device_id = "raspberry_pi_home"
        self.processed_commands = set()
        
        # Updated Bluetooth audio device
        self.bluetooth_device = "pulse/bluez_output.FA_B0_2C_56_4E_72.1"
        
        # Initialize intelligent profile matcher
        self.profile_matcher = IntelligentProfileMatcher()
        
        logger.info("🔥 Firebase REST listener initialized with intelligent profile matching")
        logger.info(f"🎧 Polling for commands at: {self.firebase_url}/home_automation/{self.persona_id}/commands.json")
        logger.info(f"🔊 Bluetooth device: {self.bluetooth_device}")
        logger.info(f"🎯 Intelligent profiles loaded: {len(self.profile_matcher.profiles)}")
        
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
    
    def set_ambiance_lighting(self, lighting_config, ambiance_analysis=None):
        """Set intelligent ambiance lighting based on voice analysis"""
        try:
            color = lighting_config.get("color", "warm_white")
            brightness = lighting_config.get("brightness", 50)
            effect = lighting_config.get("effect", "solid")
            
            logger.info(f"💡 Setting ambiance lighting:")
            logger.info(f"   Color: {color}")
            logger.info(f"   Brightness: {brightness}%")
            logger.info(f"   Effect: {effect}")
            
            if ambiance_analysis:
                logger.info(f"🎭 Ambiance profile: {ambiance_analysis.get('profile', 'Unknown')}")
                logger.info(f"   Description: {ambiance_analysis.get('description', 'N/A')}")
                logger.info(f"   Confidence: {ambiance_analysis.get('confidence', 0):.1%}")
            
            # Map colors to RGB values for smart lights
            color_map = {
                "red": (255, 0, 0),
                "green": (0, 255, 0), 
                "blue": (0, 0, 255),
                "orange": (255, 165, 0),
                "purple": (128, 0, 128),
                "yellow": (255, 255, 0),
                "white": (255, 255, 255),
                "warm_white": (255, 230, 180),
                "light_green": (144, 238, 144),
                "deep_blue": (0, 0, 139),
                "gray_blue": (70, 130, 180),
                "amber": (255, 191, 0),
                "rainbow": "cycle"  # Special effect
            }
            
            rgb_color = color_map.get(color, (255, 255, 255))
            
            # For now, simulate lighting control with logging
            # In a real setup, this would control smart lights via GPIO, WiFi, or other protocols
            if rgb_color == "cycle":
                logger.info(f"🌈 Activating rainbow color cycle effect")
            else:
                r, g, b = rgb_color
                logger.info(f"🎨 Setting RGB color: ({r}, {g}, {b})")
            
            # Simulate brightness control
            actual_brightness = int(brightness * 2.55)  # Convert percentage to 0-255
            logger.info(f"💡 Setting brightness to {actual_brightness}/255")
            
            # Simulate effect control
            effect_commands = {
                "solid": "Solid color mode",
                "gentle_pulse": "Gentle pulsing effect", 
                "wave": "Wave-like flowing effect",
                "slow_fade": "Slow fade in/out",
                "candle_flicker": "Candle flicker simulation",
                "color_cycle": "Cycling through colors",
                "rain_drops": "Rain drop effect",
                "sunrise": "Sunrise simulation",
                "leaf_fall": "Falling leaves effect"
            }
            
            effect_description = effect_commands.get(effect, "Unknown effect")
            logger.info(f"✨ Activating effect: {effect_description}")
            
            # TODO: Implement actual smart lighting control here
            # Examples:
            # - Control Philips Hue lights via API
            # - Control WS2812B LED strips via GPIO
            # - Control smart bulbs via WiFi/Bluetooth
            # - Control DMX lighting systems
            
            logger.info("✅ Ambiance lighting set successfully")
            return True
            
        except Exception as e:
            logger.error(f"❌ Error setting ambiance lighting: {e}")
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
                
                # 🎯 NEW: Use intelligent profile matching if we have original input
                intelligent_match = None
                if voice_analysis and voice_analysis.get("original_input"):
                    original_input = voice_analysis["original_input"]
                    logger.info(f"🧠 Using intelligent matching for: '{original_input}'")
                    
                    # 🎮 Check if this is a GM Kai command
                    is_gm_mode = self.profile_matcher.detect_gm_kai_mode(original_input)
                    if is_gm_mode:
                        logger.info(f"🎮 GM Kai mode detected! Processing as direct house control")
                        voice_analysis["gm_mode"] = True
                        voice_analysis["control_priority"] = "HIGH"  # Prioritize immediate control
                    
                    intelligent_match = self.profile_matcher.analyze_request(original_input)
                    
                    if intelligent_match:
                        # Override voice_analysis with intelligent match data
                        voice_analysis.update({
                            "selected_track": intelligent_match["track"],
                            "confidence": intelligent_match["confidence"],
                            "matched_keywords": intelligent_match["matched_tags"],
                            "profile_name": intelligent_match["profile_name"]
                        })
                        logger.info(f"🎯 Intelligent match: {intelligent_match['profile_name']} -> Track {intelligent_match['track']}")
                
                if voice_analysis:
                    logger.info(f"🤖 Command includes voice analysis data")
                
                success = self.play_music(mood, shuffle, voice_analysis)
                
                # 💡 NEW: Automatically trigger coordinated lighting for intelligent matches
                lighting_success = True
                if success and intelligent_match:
                    logger.info(f"💡 Triggering coordinated lighting for {intelligent_match['profile_name']}")
                    lighting_config = intelligent_match["lighting"]
                    ambiance_analysis = {
                        "profile": intelligent_match["profile_name"],
                        "description": f"Intelligent {intelligent_match['profile_name']} profile",
                        "confidence": intelligent_match["confidence"],
                        "matched_tags": intelligent_match["matched_tags"]
                    }
                    lighting_success = self.set_ambiance_lighting(lighting_config, ambiance_analysis)
                
                if success:
                    if voice_analysis and intelligent_match:
                        track_num = voice_analysis.get('selected_track', 'unknown')
                        confidence = voice_analysis.get('confidence', 0)
                        profile_name = voice_analysis.get('profile_name', mood)
                        lighting_status = "with coordinated lighting" if lighting_success else "with lighting failed"
                        gm_mode = voice_analysis.get('gm_mode', False)
                        control_mode = "🎮 GM Kai direct control" if gm_mode else "Intelligent selection"
                        message = f"Playing track {track_num} ({profile_name}) {lighting_status} - {control_mode} ({confidence:.1%} confidence)"
                    elif voice_analysis:
                        track_num = voice_analysis.get('selected_track', 'unknown')
                        confidence = voice_analysis.get('confidence', 0)
                        message = f"Playing track {track_num} ({mood}) - Kai's selection ({confidence:.1%} confidence)"
                    else:
                        message = f"Playing {mood} music"
                else:
                    message = f"Failed to play {mood} music"
                
            elif action == "stop_music" or action == "stop":
                logger.info("🛑 Stop music command")
                success = self.stop_music()
                message = "Music stopped" if success else "Failed to stop music"
                
            elif action == "pause_music":
                logger.info("⏸️ Pause music command")
                # Send pause signal to mpv (if running with input enabled)
                success = True
                message = "Music paused"
                
            elif action == "set_ambiance_lighting" and target == "lights":
                logger.info("💡 Ambiance lighting command")
                lighting_config = command_data.get("lighting_config", {})
                ambiance_analysis = command_data.get("ambiance_analysis")
                
                success = self.set_ambiance_lighting(lighting_config, ambiance_analysis)
                
                if success:
                    profile = ambiance_analysis.get("profile", "Custom") if ambiance_analysis else "Custom"
                    color = lighting_config.get("color", "unknown")
                    brightness = lighting_config.get("brightness", 50)
                    message = f"Ambiance lighting set: {profile} ({color} at {brightness}%)"
                else:
                    message = "Failed to set ambiance lighting"
                
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