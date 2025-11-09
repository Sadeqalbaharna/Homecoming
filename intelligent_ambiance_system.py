#!/usr/bin/env python3
"""
Intelligent Ambiance System for Kai
Processes voice commands to create coordinated music and lighting experiences
Integrates with Firebase for Pi home automation
"""

import re
import json
import time
from typing import Dict, List, Tuple, Optional
from dataclasses import dataclass
import requests

@dataclass
class AmbianceProfile:
    """Defines a complete ambiance experience"""
    name: str
    music_track: int
    mood: str
    light_color: str
    light_brightness: int
    light_effect: str = "solid"
    keywords: List[str] = None
    contexts: List[str] = None
    description: str = ""

class IntelligentAmbianceSystem:
    """Analyzes voice commands and creates coordinated music + lighting experiences"""
    
    def __init__(self, firebase_url: str, persona_id: str):
        self.firebase_url = firebase_url
        self.persona_id = persona_id
        
        # Define comprehensive ambiance profiles
        self.ambiance_profiles = {
            # Nature & Outdoor Ambiances
            "forest": AmbianceProfile(
                name="Forest",
                music_track=7,  # Nature sounds
                mood="peaceful",
                light_color="green",
                light_brightness=60,
                light_effect="gentle_pulse",
                keywords=["forest", "woods", "trees", "nature", "woodland", "jungle"],
                contexts=["relaxing", "natural", "outdoor", "meditation", "zen"],
                description="Deep forest with gentle green lighting and nature sounds"
            ),
            
            "ocean": AmbianceProfile(
                name="Ocean",
                music_track=7,  # Nature sounds (ocean variant)
                mood="calming",
                light_color="blue",
                light_brightness=55,
                light_effect="wave",
                keywords=["ocean", "sea", "beach", "waves", "water", "coastal", "marine"],
                contexts=["relaxing", "peaceful", "flowing", "meditation"],
                description="Ocean waves with flowing blue lighting"
            ),
            
            "sunset": AmbianceProfile(
                name="Sunset",
                music_track=5,  # Ambient
                mood="romantic",
                light_color="orange",
                light_brightness=45,
                light_effect="slow_fade",
                keywords=["sunset", "dusk", "evening", "twilight", "golden hour"],
                contexts=["romantic", "peaceful", "warm", "cozy"],
                description="Warm sunset glow with ambient music"
            ),
            
            "mountain": AmbianceProfile(
                name="Mountain",
                music_track=3,  # Focus music
                mood="focused",
                light_color="purple",
                light_brightness=70,
                light_effect="solid",
                keywords=["mountain", "peak", "highland", "elevation", "summit"],
                contexts=["focused", "clear", "elevated", "meditation"],
                description="Mountain clarity with focused purple lighting"
            ),
            
            # Indoor & Social Ambiances
            "cozy": AmbianceProfile(
                name="Cozy",
                music_track=1,  # Relaxing
                mood="warm",
                light_color="warm_white",
                light_brightness=40,
                light_effect="gentle_pulse",
                keywords=["cozy", "warm", "comfortable", "snug", "intimate"],
                contexts=["relaxing", "comfortable", "home", "quiet"],
                description="Cozy warm lighting with relaxing sounds"
            ),
            
            "party": AmbianceProfile(
                name="Party",
                music_track=2,  # Energetic
                mood="energetic",
                light_color="rainbow",
                light_brightness=90,
                light_effect="color_cycle",
                keywords=["party", "celebration", "festive", "dance", "fun"],
                contexts=["energetic", "social", "exciting", "upbeat"],
                description="Dynamic party lighting with energetic music"
            ),
            
            "romantic": AmbianceProfile(
                name="Romantic",
                music_track=6,  # Classical
                mood="romantic",
                light_color="red",
                light_brightness=30,
                light_effect="candle_flicker",
                keywords=["romantic", "love", "intimate", "date", "passion"],
                contexts=["intimate", "warm", "soft", "elegant"],
                description="Romantic red candlelight with classical music"
            ),
            
            "focus": AmbianceProfile(
                name="Focus",
                music_track=3,  # Focus music
                mood="focused",
                light_color="white",
                light_brightness=80,
                light_effect="solid",
                keywords=["focus", "work", "study", "concentrate", "productivity"],
                contexts=["focused", "clear", "productive", "alert"],
                description="Bright focused lighting with concentration music"
            ),
            
            # Weather & Time Ambiances
            "rainy": AmbianceProfile(
                name="Rainy Day",
                music_track=1,  # Relaxing
                mood="contemplative",
                light_color="gray_blue",
                light_brightness=50,
                light_effect="rain_drops",
                keywords=["rain", "rainy", "storm", "drizzle", "cloudy"],
                contexts=["contemplative", "peaceful", "indoor", "cozy"],
                description="Rainy day atmosphere with soft blue-gray lighting"
            ),
            
            "morning": AmbianceProfile(
                name="Morning Energy",
                music_track=2,  # Energetic
                mood="energetic",
                light_color="yellow",
                light_brightness=85,
                light_effect="sunrise",
                keywords=["morning", "sunrise", "dawn", "wake up", "energy"],
                contexts=["energetic", "fresh", "new", "bright"],
                description="Energizing sunrise lighting with upbeat music"
            ),
            
            "night": AmbianceProfile(
                name="Night Calm",
                music_track=1,  # Relaxing
                mood="sleepy",
                light_color="deep_blue",
                light_brightness=20,
                light_effect="gentle_pulse",
                keywords=["night", "sleep", "bedtime", "lunar", "moonlight"],
                contexts=["sleepy", "calm", "peaceful", "quiet"],
                description="Soft moonlight blue for nighttime relaxation"
            ),
            
            # Seasonal Ambiances  
            "spring": AmbianceProfile(
                name="Spring Fresh",
                music_track=4,  # Happy
                mood="cheerful",
                light_color="light_green",
                light_brightness=75,
                light_effect="gentle_pulse",
                keywords=["spring", "fresh", "bloom", "growth", "renewal"],
                contexts=["fresh", "cheerful", "growing", "optimistic"],
                description="Fresh spring greens with cheerful music"
            ),
            
            "autumn": AmbianceProfile(
                name="Autumn Warmth",
                music_track=5,  # Ambient
                mood="contemplative",
                light_color="amber",
                light_brightness=55,
                light_effect="leaf_fall",
                keywords=["autumn", "fall", "harvest", "golden", "cozy"],
                contexts=["contemplative", "warm", "cozy", "reflective"],
                description="Warm autumn amber with contemplative ambient music"
            )
        }
    
    def analyze_voice_command(self, voice_input: str) -> Dict:
        """
        Analyze voice command for ambiance requests
        Returns ambiance profile and confidence
        """
        voice_lower = voice_input.lower()
        
        # Remove common voice command prefixes
        voice_cleaned = re.sub(r'\b(hey kai|kai|please|give me|set|create|make)\b', '', voice_lower).strip()
        voice_cleaned = re.sub(r'\b(ambiance|ambience|atmosphere|mood|lighting|lights|music)\b', '', voice_cleaned).strip()
        
        best_match = None
        best_score = 0
        matched_keywords = []
        matched_contexts = []
        
        for profile_name, profile in self.ambiance_profiles.items():
            score = 0
            profile_keywords = []
            profile_contexts = []
            
            # Direct profile name match (highest priority)
            if profile_name in voice_cleaned:
                score += 100
                profile_keywords.append(profile_name)
            
            # Keyword matching
            if profile.keywords:
                for keyword in profile.keywords:
                    if keyword in voice_cleaned:
                        score += 50
                        profile_keywords.append(keyword)
            
            # Context matching  
            if profile.contexts:
                for context in profile.contexts:
                    if context in voice_cleaned:
                        score += 25
                        profile_contexts.append(context)
            
            # Bonus for multiple matches
            if len(profile_keywords) > 1:
                score += 20
            if len(profile_contexts) > 1:
                score += 10
            
            if score > best_score:
                best_score = score
                best_match = profile
                matched_keywords = profile_keywords
                matched_contexts = profile_contexts
        
        # Calculate confidence percentage
        max_possible_score = 100 + 50 * 3 + 25 * 2 + 30  # Estimate max score
        confidence = min(best_score / max_possible_score, 1.0)
        
        return {
            "original_input": voice_input,
            "cleaned_input": voice_cleaned,
            "selected_profile": best_match.name if best_match else None,
            "music_track": best_match.music_track if best_match else None,
            "mood": best_match.mood if best_match else "relaxing",
            "lighting": {
                "color": best_match.light_color if best_match else "warm_white",
                "brightness": best_match.light_brightness if best_match else 50,
                "effect": best_match.light_effect if best_match else "solid"
            } if best_match else None,
            "matched_keywords": matched_keywords,
            "matched_contexts": matched_contexts,
            "confidence": confidence,
            "description": best_match.description if best_match else "Default ambiance"
        }
    
    def is_ambiance_request(self, voice_input: str) -> bool:
        """Check if the voice input is requesting an ambiance change"""
        ambiance_indicators = [
            "ambiance", "ambience", "atmosphere", "mood", "lighting", "lights",
            "set the mood", "create atmosphere", "give me", "make it", "lighting",
            "forest", "ocean", "sea", "sunset", "cozy", "romantic", "party",
            "focus", "rain", "morning", "night", "spring", "autumn"
        ]
        
        voice_lower = voice_input.lower()
        return any(indicator in voice_lower for indicator in ambiance_indicators)
    
    def send_firebase_commands(self, analysis: Dict) -> bool:
        """Send both music and lighting commands to Firebase"""
        try:
            timestamp = int(time.time() * 1000)
            commands_sent = []
            
            # Send music command if track selected
            if analysis.get("music_track"):
                music_command = {
                    "action": "play_mood",
                    "target": "music", 
                    "device": "raspberry_pi_home",
                    "mood": analysis["mood"],
                    "shuffle": False,  # Don't shuffle for intelligent selection
                    "timestamp": timestamp,
                    "voice_analysis": {
                        "original_input": analysis["original_input"],
                        "selected_track": analysis["music_track"],
                        "matched_keywords": analysis["matched_keywords"],
                        "matched_contexts": analysis["matched_contexts"], 
                        "confidence": analysis["confidence"]
                    }
                }
                
                music_cmd_id = f"music_cmd_{timestamp}"
                music_url = f"{self.firebase_url}/home_automation/{self.persona_id}/commands/{music_cmd_id}.json"
                
                response = requests.put(music_url, json=music_command, timeout=10)
                if response.status_code == 200:
                    commands_sent.append("music")
            
            # Send lighting command if lighting config exists
            if analysis.get("lighting"):
                lighting_command = {
                    "action": "set_ambiance_lighting",
                    "target": "lights",
                    "device": "raspberry_pi_home", 
                    "timestamp": timestamp + 1,  # Slight delay to avoid conflicts
                    "lighting_config": analysis["lighting"],
                    "ambiance_analysis": {
                        "profile": analysis.get("selected_profile"),
                        "description": analysis.get("description"),
                        "confidence": analysis["confidence"]
                    }
                }
                
                lighting_cmd_id = f"lighting_cmd_{timestamp}"
                lighting_url = f"{self.firebase_url}/home_automation/{self.persona_id}/commands/{lighting_cmd_id}.json"
                
                response = requests.put(lighting_url, json=lighting_command, timeout=10)
                if response.status_code == 200:
                    commands_sent.append("lighting")
            
            return len(commands_sent) > 0
            
        except Exception as e:
            print(f"Error sending Firebase commands: {e}")
            return False
    
    def process_ambiance_request(self, voice_input: str) -> Dict:
        """Complete pipeline: analyze voice and send Firebase commands"""
        # Analyze the voice command
        analysis = self.analyze_voice_command(voice_input)
        
        # Send Firebase commands
        success = self.send_firebase_commands(analysis)
        
        # Return complete result
        analysis["commands_sent"] = success
        return analysis

# Example usage and testing
if __name__ == "__main__":
    # Initialize system
    firebase_url = "https://homecoming-74f73-default-rtdb.europe-west1.firebasedatabase.app"
    persona_id = "kai_persona_1"
    
    system = IntelligentAmbianceSystem(firebase_url, persona_id)
    
    # Test voice commands
    test_commands = [
        "Hey Kai, give me forest ambiance",
        "Create a sea atmosphere", 
        "Set romantic mood",
        "I want cozy lighting",
        "Make it feel like a party",
        "Give me focus lighting for work",
        "Create sunset ambiance",
        "Set rainy day mood"
    ]
    
    print("🎭 Testing Intelligent Ambiance System\n")
    
    for command in test_commands:
        print(f"🎤 Voice: '{command}'")
        result = system.process_ambiance_request(command)
        
        if result.get("selected_profile"):
            print(f"🎯 Profile: {result['selected_profile']} ({result['confidence']:.1%} confidence)")
            print(f"🎵 Music: Track {result['music_track']} ({result['mood']})")
            if result.get("lighting"):
                lighting = result["lighting"]
                print(f"💡 Lighting: {lighting['color']} at {lighting['brightness']}% with {lighting['effect']} effect")
            print(f"📤 Commands sent: {'✅' if result['commands_sent'] else '❌'}")
        else:
            print(f"❌ No profile matched")
        
        print("─" * 50)