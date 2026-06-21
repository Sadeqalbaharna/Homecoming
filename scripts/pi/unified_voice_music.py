#!/usr/bin/env python3
"""
Unified Voice & Music Integration System
Consolidates all voice/music functionality
Replaces: intelligent_kai_music.py, kai_voice_integration.py, voice_enabled_home_automation.py, etc.
"""

import logging
import requests
from typing import Dict, Any, List, Optional, Tuple
import json
import re

logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
logger = logging.getLogger(__name__)


class UnifiedVoiceMusic:
    """Unified voice recognition and intelligent music selection system"""
    
    def __init__(self, firebase_url: str = None, device_id: str = "raspberry_pi"):
        self.firebase_url = firebase_url or "https://homecoming-74f73-default-rtdb.europe-west1.firebasedatabase.app"
        self.device_id = device_id
        
        # Music profiles indexed by context
        self.music_profiles = self._initialize_profiles()
        self.voice_context = {}
        self.last_command = None
    
    def _initialize_profiles(self) -> Dict:
        """Initialize music profiles for different contexts"""
        return {
            "relaxing": {
                "keywords": ["relax", "calm", "peaceful", "meditation", "sleep", "chill"],
                "genres": ["ambient", "lo-fi", "jazz", "classical"],
                "tempo": "slow",
                "volume": 0.5,
                "energy": "low"
            },
            "energetic": {
                "keywords": ["energy", "pump", "workout", "dance", "party", "upbeat", "hype"],
                "genres": ["electronic", "pop", "hip-hop", "rock"],
                "tempo": "fast",
                "volume": 0.8,
                "energy": "high"
            },
            "atmospheric": {
                "keywords": ["ambiance", "background", "ambient", "atmosphere", "scenic", "nature"],
                "genres": ["ambient", "atmospheric", "environmental"],
                "tempo": "varied",
                "volume": 0.3,
                "energy": "minimal"
            },
            "focus": {
                "keywords": ["focus", "work", "study", "concentrate", "productive"],
                "genres": ["lo-fi", "classical", "ambient", "electronic"],
                "tempo": "moderate",
                "volume": 0.4,
                "energy": "steady"
            },
            "gaming": {
                "keywords": ["game", "gaming", "play", "rpg", "adventure"],
                "genres": ["electronic", "orchestral", "intense"],
                "tempo": "fast",
                "volume": 0.7,
                "energy": "high"
            }
        }
    
    def analyze_voice_command(self, command: str) -> Dict[str, Any]:
        """Analyze voice command for intent and context"""
        command_lower = command.lower()
        
        # Detect intent
        analysis = {
            "raw": command,
            "lower": command_lower,
            "music_request": self._detect_music_request(command_lower),
            "context": self._detect_context(command_lower),
            "profile": None,
            "confidence": 0.0,
            "suggested_query": None,
            "home_automation": self._detect_home_automation(command_lower)
        }
        
        # Find matching profile
        best_match = self._find_best_profile(command_lower)
        if best_match:
            analysis["profile"] = best_match["name"]
            analysis["confidence"] = best_match["score"]
            analysis["suggested_query"] = self._generate_youtube_query(
                command_lower,
                best_match["name"]
            )
        
        self.last_command = analysis
        return analysis
    
    def _detect_music_request(self, command: str) -> bool:
        """Detect if command is requesting music"""
        music_keywords = [
            "play", "music", "song", "track", "beat", "sound",
            "spotify", "youtube", "playlist", "album", "artist"
        ]
        return any(kw in command for kw in music_keywords)
    
    def _detect_context(self, command: str) -> Optional[str]:
        """Detect contextual information"""
        contexts = {
            "time": self._detect_time_context(command),
            "location": self._detect_location_context(command),
            "activity": self._detect_activity_context(command)
        }
        return contexts
    
    def _detect_time_context(self, command: str) -> Optional[str]:
        """Detect time-based context"""
        time_keywords = {
            "morning": ["morning", "wake", "breakfast"],
            "afternoon": ["afternoon", "lunch", "midday"],
            "evening": ["evening", "dinner", "sunset"],
            "night": ["night", "sleep", "bedtime", "relax"]
        }
        
        for time_period, keywords in time_keywords.items():
            if any(kw in command for kw in keywords):
                return time_period
        return None
    
    def _detect_location_context(self, command: str) -> Optional[str]:
        """Detect location-based context"""
        location_keywords = {
            "bedroom": ["bed", "bedroom", "sleep"],
            "kitchen": ["kitchen", "cook", "breakfast"],
            "living_room": ["living", "relax", "tv"],
            "office": ["work", "office", "desk", "study"]
        }
        
        for location, keywords in location_keywords.items():
            if any(kw in command for kw in keywords):
                return location
        return None
    
    def _detect_activity_context(self, command: str) -> Optional[str]:
        """Detect activity context"""
        activity_keywords = {
            "workout": ["exercise", "workout", "gym", "run", "walk"],
            "gaming": ["game", "play", "rpg", "minecraft"],
            "reading": ["read", "book", "study"],
            "cooking": ["cook", "recipe", "kitchen"]
        }
        
        for activity, keywords in activity_keywords.items():
            if any(kw in command for kw in keywords):
                return activity
        return None
    
    def _find_best_profile(self, command: str) -> Optional[Dict]:
        """Find best matching music profile"""
        best_match = None
        best_score = 0.0
        
        for name, profile in self.music_profiles.items():
            score = 0.0
            for keyword in profile["keywords"]:
                if keyword in command:
                    score += 1.0
            
            # Normalize score
            score = score / len(profile["keywords"]) if profile["keywords"] else 0
            
            if score > best_score:
                best_score = score
                best_match = {"name": name, "profile": profile, "score": score}
        
        return best_match if best_score > 0 else None
    
    def _generate_youtube_query(self, command: str, profile: str) -> str:
        """Generate YouTube search query from voice command"""
        # Remove filler words
        filler_words = ["play", "music", "please", "can", "you", "i", "want", "like"]
        words = [w for w in command.split() if w not in filler_words]
        
        # Add profile-specific terms
        profile_data = self.music_profiles.get(profile, {})
        genres = profile_data.get("genres", [])
        
        query = " ".join(words)
        if genres:
            query += f" {genres[0]}"
        
        return query
    
    def _detect_home_automation(self, command: str) -> Dict:
        """Detect home automation commands"""
        automation = {
            "lights": None,
            "temperature": None,
            "scene": None
        }
        
        # Lights
        if any(w in command for w in ["light", "lights", "bright", "dim"]):
            if "on" in command or "bright" in command:
                automation["lights"] = "on"
            elif "off" in command or "dim" in command:
                automation["lights"] = "off"
        
        # Scene (from D&D context)
        if "scene" in command:
            # Extract scene name
            match = re.search(r"scene\s+(\w+)", command)
            if match:
                automation["scene"] = match.group(1)
        
        return automation
    
    def process_command(self, command: str) -> Dict[str, Any]:
        """Process complete voice command"""
        analysis = self.analyze_voice_command(command)
        
        response = {
            "command": command,
            "analysis": analysis,
            "music": None,
            "automation": None,
            "response_text": ""
        }
        
        # Generate music if requested
        if analysis["music_request"] and analysis["suggested_query"]:
            response["music"] = {
                "query": analysis["suggested_query"],
                "profile": analysis["profile"],
                "volume": self.music_profiles[analysis["profile"]]["volume"],
                "confidence": analysis["confidence"]
            }
            response["response_text"] = f"Playing {analysis['profile']} music..."
        
        # Handle home automation
        if analysis["home_automation"]:
            response["automation"] = analysis["home_automation"]
            if analysis["home_automation"]["lights"]:
                response["response_text"] += f" Lights {analysis['home_automation']['lights']}."
            if analysis["home_automation"]["scene"]:
                response["response_text"] += f" Loading {analysis['home_automation']['scene']} scene."
        
        return response
    
    def push_to_firebase(self, path: str, data: Dict) -> bool:
        """Push analysis result to Firebase"""
        try:
            url = f"{self.firebase_url}/{path}.json"
            response = requests.post(url, json=data)
            return response.status_code in [200, 201]
        except Exception as e:
            logger.error(f"Firebase push error: {e}")
            return False


def main():
    """CLI interface"""
    import argparse
    
    parser = argparse.ArgumentParser(description="Unified Voice & Music System")
    parser.add_argument("--test", action="store_true", help="Run test commands")
    parser.add_argument("--command", help="Process single command")
    
    args = parser.parse_args()
    
    system = UnifiedVoiceMusic()
    
    if args.test:
        test_commands = [
            "play relaxing meditation music",
            "i want energetic dance music for my workout",
            "ambient background music please",
            "can you play gaming music?",
            "play lo-fi beats for studying"
        ]
        
        for cmd in test_commands:
            logger.info(f"\n📝 Command: {cmd}")
            result = system.process_command(cmd)
            logger.info(f"   Profile: {result['analysis']['profile']}")
            logger.info(f"   Query: {result['music']['query'] if result['music'] else 'N/A'}")
            logger.info(f"   Response: {result['response_text']}")
    
    elif args.command:
        result = system.process_command(args.command)
        print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
