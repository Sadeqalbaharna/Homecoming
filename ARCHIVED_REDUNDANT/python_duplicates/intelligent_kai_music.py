#!/usr/bin/env python3
"""
Intelligent Kai Voice Music System
Analyzes voice commands to select the most appropriate music track
"""

import requests
import time
import logging
import random
import re
from typing import Dict, Any, List, Tuple

class IntelligentKaiMusicSystem:
    """
    Intelligent music selection system for Kai voice commands
    Analyzes voice input context to choose the best track
    """
    
    def __init__(self):
        self.logger = self._setup_logging()
        
        # Firebase configuration
        self.firebase_url = "https://homecoming-74f73-default-rtdb.europe-west1.firebasedatabase.app"
        self.persona_id = "kai_persona_1"
        self.device_id = "raspberry_pi_home"
        
        # Track definitions with contexts and keywords
        self.track_profiles = {
            1: {
                "name": "Nature Relaxation",
                "mood": "relaxing",
                "description": "Peaceful nature sounds, perfect for unwinding",
                "keywords": ["relax", "calm", "peaceful", "nature", "unwind", "stress", "sleep", "meditate", "soothe"],
                "contexts": ["after work", "bedtime", "meditation", "stress relief", "quiet time"],
                "energy_level": 1,  # 1-10 scale
                "response_phrases": [
                    "Playing peaceful nature sounds to help you relax",
                    "Starting your relaxing track - time to unwind",
                    "I've selected calming nature sounds for you",
                    "Perfect for relaxation - playing track 1"
                ]
            },
            2: {
                "name": "Energetic Motivation",
                "mood": "energetic", 
                "description": "Upbeat music to boost energy and motivation",
                "keywords": ["energy", "upbeat", "motivate", "pump", "active", "workout", "exercise", "boost", "power"],
                "contexts": ["morning", "workout", "cleaning", "motivation", "productivity"],
                "energy_level": 9,
                "response_phrases": [
                    "Pumping up the energy with motivational music!",
                    "Time to get energized - playing upbeat track 2",
                    "Boosting your energy with powerful music",
                    "Let's get motivated with some high-energy tunes!"
                ]
            },
            3: {
                "name": "Focus & Concentration",
                "mood": "focused",
                "description": "Concentration music for work and study",
                "keywords": ["focus", "concentrate", "study", "work", "productivity", "think", "brain", "deep work"],
                "contexts": ["studying", "working", "reading", "writing", "problem solving"],
                "energy_level": 5,
                "response_phrases": [
                    "Playing focus music to enhance your concentration",
                    "Perfect for deep work - starting concentration track",
                    "I've selected music to help you focus better",
                    "Time for productive focus with track 3"
                ]
            },
            4: {
                "name": "Happy & Cheerful",
                "mood": "happy",
                "description": "Uplifting music to brighten your mood",
                "keywords": ["happy", "cheerful", "joy", "bright", "positive", "smile", "celebrate", "good mood"],
                "contexts": ["celebration", "good news", "socializing", "cooking", "creative time"],
                "energy_level": 7,
                "response_phrases": [
                    "Brightening your day with cheerful music!",
                    "Playing happy tunes to boost your mood",
                    "Time for some joyful music - track 4 coming up",
                    "Spreading positivity with uplifting sounds"
                ]
            },
            5: {
                "name": "Ambient Background",
                "mood": "ambient",
                "description": "Atmospheric background music for any activity",
                "keywords": ["ambient", "background", "atmospheric", "chill", "lounge", "subtle", "atmosphere"],
                "contexts": ["background", "reading", "browsing", "casual", "ambient"],
                "energy_level": 3,
                "response_phrases": [
                    "Creating perfect ambient atmosphere with track 5",
                    "Playing subtle background music for you",
                    "Setting atmospheric mood with ambient sounds",
                    "Perfect background music coming up"
                ]
            },
            6: {
                "name": "Classical Elegance",
                "mood": "classical",
                "description": "Sophisticated classical music for refined moments",
                "keywords": ["classical", "elegant", "sophisticated", "refined", "dinner", "romantic", "classy"],
                "contexts": ["dinner", "romantic", "elegant", "sophisticated", "classical"],
                "energy_level": 4,
                "response_phrases": [
                    "Playing elegant classical music for a refined atmosphere",
                    "Creating sophisticated ambiance with classical track",
                    "Time for some cultured classical sounds",
                    "Elevating the mood with beautiful classical music"
                ]
            },
            7: {
                "name": "Pure Nature",
                "mood": "nature",
                "description": "Natural soundscapes from forests, rain, and oceans",
                "keywords": ["nature", "forest", "rain", "ocean", "outdoors", "natural", "wilderness", "birds"],
                "contexts": ["nature", "outdoors", "environmental", "natural", "organic"],
                "energy_level": 2,
                "response_phrases": [
                    "Bringing nature indoors with authentic soundscapes",
                    "Playing beautiful natural sounds from track 7",
                    "Connecting you with nature through pure sounds",
                    "Immersing you in natural wilderness audio"
                ]
            }
        }
        
        self.logger.info("🎵 Intelligent Kai Music System initialized")
        self.logger.info(f"🎯 {len(self.track_profiles)} track profiles loaded")
    
    def _setup_logging(self):
        """Setup logging"""
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
        )
        return logging.getLogger('IntelligentKaiMusic')
    
    def analyze_voice_command(self, voice_input: str) -> Dict[str, Any]:
        """
        Intelligently analyze voice command to determine best track
        Returns analysis with track selection and confidence
        """
        
        voice_lower = voice_input.lower()
        self.logger.info(f"🎤 Analyzing voice command: '{voice_input}'")
        
        # Track scoring system
        track_scores = {}
        
        for track_id, profile in self.track_profiles.items():
            score = 0
            matched_keywords = []
            matched_contexts = []
            
            # Score based on keyword matches
            for keyword in profile["keywords"]:
                if keyword in voice_lower:
                    score += 10
                    matched_keywords.append(keyword)
                    self.logger.debug(f"🎯 Track {track_id}: Keyword '{keyword}' matched (+10)")
            
            # Score based on context matches
            for context in profile["contexts"]:
                if context in voice_lower:
                    score += 15  # Contexts are more specific, higher score
                    matched_contexts.append(context)
                    self.logger.debug(f"🎯 Track {track_id}: Context '{context}' matched (+15)")
            
            # Bonus scoring for exact mood matches
            if profile["mood"] in voice_lower:
                score += 20
                self.logger.debug(f"🎯 Track {track_id}: Exact mood '{profile['mood']}' matched (+20)")
            
            # Store score and details
            if score > 0:
                track_scores[track_id] = {
                    "score": score,
                    "profile": profile,
                    "matched_keywords": matched_keywords,
                    "matched_contexts": matched_contexts
                }
        
        # Determine best track
        if track_scores:
            # Get track with highest score
            best_track_id = max(track_scores.keys(), key=lambda x: track_scores[x]["score"])
            best_match = track_scores[best_track_id]
            
            self.logger.info(f"🎯 Best match: Track {best_track_id} (Score: {best_match['score']})")
            self.logger.info(f"📝 Matched keywords: {best_match['matched_keywords']}")
            self.logger.info(f"🎭 Matched contexts: {best_match['matched_contexts']}")
            
            return {
                "success": True,
                "selected_track": best_track_id,
                "confidence": min(best_match["score"] / 30.0, 1.0),  # Normalize to 0-1
                "track_profile": best_match["profile"],
                "matched_keywords": best_match["matched_keywords"],
                "matched_contexts": best_match["matched_contexts"],
                "all_scores": track_scores
            }
        else:
            # No specific matches found, default to relaxing
            self.logger.info("🤔 No specific matches found, defaulting to relaxing track")
            
            return {
                "success": True,
                "selected_track": 1,  # Default to relaxing
                "confidence": 0.3,    # Low confidence for default
                "track_profile": self.track_profiles[1],
                "matched_keywords": [],
                "matched_contexts": [],
                "default_selection": True
            }
    
    def send_intelligent_music_command(self, voice_input: str) -> Dict[str, Any]:
        """
        Analyze voice input and send intelligent Firebase command
        """
        
        # Analyze the voice command
        analysis = self.analyze_voice_command(voice_input)
        
        if not analysis["success"]:
            return {
                "success": False,
                "message": "Failed to analyze voice command",
                "kai_response": "I'm having trouble understanding your music request."
            }
        
        selected_track = analysis["selected_track"]
        track_profile = analysis["track_profile"]
        confidence = analysis["confidence"]
        
        try:
            # Generate command ID
            command_id = f"kai_voice_{int(time.time() * 1000)}"
            
            # Build Firebase command with intelligent selection
            command_data = {
                "device": self.device_id,
                "action": "play_mood",
                "target": "music",
                "mood": track_profile["mood"],
                "shuffle": False,  # Use specific intelligent selection
                "timestamp": int(time.time() * 1000),
                "voice_analysis": {
                    "original_input": voice_input,
                    "selected_track": selected_track,
                    "confidence": confidence,
                    "matched_keywords": analysis["matched_keywords"],
                    "matched_contexts": analysis["matched_contexts"]
                }
            }
            
            # Send to Firebase
            url = f"{self.firebase_url}/home_automation/{self.persona_id}/commands/{command_id}.json"
            
            self.logger.info(f"📤 Sending intelligent music command...")
            self.logger.info(f"🎵 Selected: Track {selected_track} - {track_profile['name']}")
            self.logger.info(f"🎯 Confidence: {confidence:.1%}")
            
            response = requests.put(url, json=command_data, timeout=10)
            
            if response.status_code == 200:
                # Generate Kai's response
                kai_response = random.choice(track_profile["response_phrases"])
                
                # Add confidence context if low
                if confidence < 0.5:
                    kai_response += " Let me know if this isn't quite what you had in mind."
                
                self.logger.info(f"✅ Command sent successfully: {command_id}")
                
                return {
                    "success": True,
                    "command_id": command_id,
                    "selected_track": selected_track,
                    "track_name": track_profile["name"],
                    "confidence": confidence,
                    "kai_response": kai_response,
                    "analysis": analysis,
                    "firebase_sent": True
                }
            else:
                self.logger.error(f"❌ Firebase command failed: {response.status_code}")
                return {
                    "success": False,
                    "message": f"Firebase error: {response.status_code}",
                    "kai_response": "I'm having trouble connecting to the music system right now."
                }
                
        except Exception as e:
            self.logger.error(f"❌ Error sending command: {e}")
            return {
                "success": False,
                "message": str(e),
                "kai_response": "Something went wrong with the music system. Let me try again."
            }
    
    def handle_kai_voice_command(self, voice_input: str) -> Dict[str, Any]:
        """
        Main entry point for Kai voice commands
        Determines if it's a music command and processes intelligently
        """
        
        voice_lower = voice_input.lower()
        
        # Check if this is a music-related command
        music_indicators = [
            "music", "track", "play", "song", "sound", "audio", "tune",
            "relax", "energetic", "focus", "happy", "ambient", "classical", "nature"
        ]
        
        is_music_command = any(indicator in voice_lower for indicator in music_indicators)
        
        if is_music_command:
            self.logger.info(f"🎵 Music command detected in: '{voice_input}'")
            return self.send_intelligent_music_command(voice_input)
        else:
            self.logger.info(f"ℹ️ Not a music command: '{voice_input}'")
            return {
                "success": False,
                "message": "Not a music command",
                "is_music_command": False,
                "kai_response": f"I heard '{voice_input}'. For music, try asking me to play something relaxing, energetic, or focused!"
            }

def main():
    """Test the intelligent music system"""
    
    print("🤖 Kai Intelligent Music System Test")
    print("=" * 45)
    
    kai_music = IntelligentKaiMusicSystem()
    
    # Test various voice commands
    test_commands = [
        # Relaxing commands
        "I need to relax and unwind after work",
        "Play something peaceful to help me sleep", 
        "I'm stressed, can you play calming music?",
        
        # Energetic commands
        "I need energy for my workout",
        "Play something to motivate me",
        "I want upbeat music to pump me up",
        
        # Focus commands
        "I need to concentrate on work",
        "Play focus music for studying",
        "Something for deep work please",
        
        # Happy commands
        "I'm in a great mood, play something cheerful",
        "Celebrate with happy music",
        "Brighten my day with joyful sounds",
        
        # Ambient commands
        "Play background music while I read",
        "Something atmospheric for ambiance",
        "Subtle music for the background",
        
        # Nature commands
        "Play natural forest sounds",
        "I want to hear ocean waves",
        "Nature sounds please",
        
        # Classical commands
        "Play elegant classical music for dinner",
        "Something sophisticated and refined",
        "Classical music for a romantic evening",
        
        # Vague commands (should default intelligently)
        "Play some music",
        "I want to listen to something",
        
        # Non-music commands
        "What time is it?",
        "Turn on the lights"
    ]
    
    for i, command in enumerate(test_commands, 1):
        print(f"\n{i:2d}. 👤 User: \"{command}\"")
        
        result = kai_music.handle_kai_voice_command(command)
        
        if result["success"]:
            print(f"    🎵 Selected: Track {result['selected_track']} - {result['track_name']}")
            print(f"    🎯 Confidence: {result['confidence']:.1%}")
            print(f"    🤖 Kai: \"{result['kai_response']}\"")
            
            if "analysis" in result:
                analysis = result["analysis"]
                if analysis["matched_keywords"]:
                    print(f"    🔍 Keywords: {', '.join(analysis['matched_keywords'])}")
                if analysis["matched_contexts"]:
                    print(f"    🎭 Contexts: {', '.join(analysis['matched_contexts'])}")
        else:
            if result.get("is_music_command") == False:
                print(f"    ℹ️  Not a music command")
            else:
                print(f"    ❌ Error: {result['message']}")
            
            if "kai_response" in result:
                print(f"    🤖 Kai: \"{result['kai_response']}\"")
        
        time.sleep(0.5)

if __name__ == "__main__":
    main()