#!/usr/bin/env python3
"""
Intelligent Profile System for Music and Lighting Control
Creates a comprehensive tagging system that allows Kai to match user requests
to appropriate music tracks and lighting combinations based on contextual labels
"""

import json
import logging
from typing import Dict, List, Optional, Tuple

logger = logging.getLogger(__name__)

class IntelligentProfileMatcher:
    def __init__(self):
        """Initialize the intelligent profile matching system"""
        self.profiles = self._initialize_profiles()
        logger.info("🎯 Intelligent Profile Matcher initialized with comprehensive tagging system")
    
    def _initialize_profiles(self) -> Dict:
        """Define comprehensive profiles with rich tagging for intelligent matching"""
        return {
            # Track 1: Nature/Forest Sounds
            "nature_forest": {
                "track": 1,
                "lighting": {
                    "color": "light_green",
                    "brightness": 70,
                    "effect": "gentle_pulse"
                },
                "tags": {
                    "primary": ["nature", "forest", "relaxing", "woods"],
                    "secondary": ["trees", "peaceful", "calm", "natural", "green", "outdoor"],
                    "moods": ["zen", "meditation", "stress-relief", "tranquil"],
                    "activities": ["reading", "studying", "sleeping", "yoga"],
                    "times": ["morning", "evening", "bedtime"],
                    "weather": ["rainy", "cloudy", "spring"]
                },
                "description": "Peaceful forest ambiance with birds chirping and gentle nature sounds",
                "confidence_boost": ["forest", "nature", "trees", "green"],
                "aliases": ["forest", "woods", "nature", "trees", "outdoor"]
            },
            
            # Track 2: Energetic/Upbeat
            "energetic_upbeat": {
                "track": 2,
                "lighting": {
                    "color": "yellow",
                    "brightness": 85,
                    "effect": "gentle_pulse"
                },
                "tags": {
                    "primary": ["energetic", "upbeat", "active", "motivational"],
                    "secondary": ["dynamic", "powerful", "intense", "bright", "yellow"],
                    "moods": ["motivated", "excited", "pumped", "confident", "positive"],
                    "activities": ["workout", "exercise", "cleaning", "dancing", "gaming"],
                    "times": ["morning", "afternoon", "workout-time"],
                    "weather": ["sunny", "bright"]
                },
                "description": "High-energy music to boost motivation and activity levels",
                "confidence_boost": ["energetic", "workout", "active", "motivated"],
                "aliases": ["energy", "workout", "pump", "active", "motivated"]
            },
            
            # Track 3: Focus/Concentration
            "focus_productivity": {
                "track": 3,
                "lighting": {
                    "color": "white",
                    "brightness": 80,
                    "effect": "solid"
                },
                "tags": {
                    "primary": ["focus", "concentration", "productivity", "work"],
                    "secondary": ["study", "clear", "sharp", "white", "bright"],
                    "moods": ["concentrated", "alert", "determined", "serious"],
                    "activities": ["working", "studying", "coding", "writing", "analyzing"],
                    "times": ["morning", "afternoon", "work-hours"],
                    "weather": ["any"]
                },
                "description": "Clean, focused soundscape for maximum concentration and productivity",
                "confidence_boost": ["focus", "work", "study", "productivity"],
                "aliases": ["focus", "work", "study", "concentration", "productivity"]
            },
            
            # Track 4: Happy/Cheerful
            "happy_cheerful": {
                "track": 4,
                "lighting": {
                    "color": "orange",
                    "brightness": 75,
                    "effect": "gentle_pulse"
                },
                "tags": {
                    "primary": ["happy", "cheerful", "joyful", "celebration"],
                    "secondary": ["uplifting", "positive", "warm", "orange", "bright"],
                    "moods": ["joyful", "festive", "optimistic", "content", "playful"],
                    "activities": ["celebrating", "socializing", "cooking", "playing"],
                    "times": ["afternoon", "evening", "party-time"],
                    "weather": ["sunny", "warm"]
                },
                "description": "Uplifting and cheerful music to brighten your day",
                "confidence_boost": ["happy", "cheerful", "celebration", "joy"],
                "aliases": ["happy", "joy", "celebration", "cheerful", "positive"]
            },
            
            # Track 5: Ambient/Background
            "ambient_chill": {
                "track": 5,
                "lighting": {
                    "color": "purple",
                    "brightness": 45,
                    "effect": "slow_fade"
                },
                "tags": {
                    "primary": ["ambient", "chill", "atmospheric", "background"],
                    "secondary": ["subtle", "flowing", "ethereal", "purple", "dreamy"],
                    "moods": ["relaxed", "contemplative", "creative", "flowing"],
                    "activities": ["creative-work", "art", "thinking", "lounging"],
                    "times": ["evening", "late-night", "creative-time"],
                    "weather": ["twilight", "misty"]
                },
                "description": "Atmospheric ambient soundscape for creative and contemplative moments",
                "confidence_boost": ["ambient", "chill", "atmospheric", "creative"],
                "aliases": ["ambient", "chill", "atmospheric", "background", "creative"]
            },
            
            # Track 6: Classical/Romantic
            "classical_romantic": {
                "track": 6,
                "lighting": {
                    "color": "amber",
                    "brightness": 30,
                    "effect": "candle_flicker"
                },
                "tags": {
                    "primary": ["classical", "romantic", "elegant", "sophisticated"],
                    "secondary": ["intimate", "warm", "amber", "candlelight", "refined"],
                    "moods": ["romantic", "elegant", "peaceful", "sophisticated", "intimate"],
                    "activities": ["dinner", "date-night", "relaxing", "reading"],
                    "times": ["evening", "dinner-time", "date-night"],
                    "weather": ["cozy", "indoor"]
                },
                "description": "Elegant classical music creating an intimate, sophisticated atmosphere",
                "confidence_boost": ["romantic", "classical", "elegant", "dinner"],
                "aliases": ["romantic", "classical", "elegant", "dinner", "intimate"]
            },
            
            # Track 7: Ocean/Water Sounds
            "ocean_water": {
                "track": 7,
                "lighting": {
                    "color": "deep_blue",
                    "brightness": 60,
                    "effect": "wave"
                },
                "tags": {
                    "primary": ["ocean", "water", "waves", "sea"],
                    "secondary": ["blue", "flowing", "rhythmic", "deep", "aquatic"],
                    "moods": ["calm", "meditative", "peaceful", "flowing", "deep"],
                    "activities": ["meditation", "sleeping", "spa", "relaxing"],
                    "times": ["evening", "bedtime", "spa-time"],
                    "weather": ["any", "hot", "summer"]
                },
                "description": "Soothing ocean waves and water sounds for deep relaxation",
                "confidence_boost": ["ocean", "sea", "waves", "water"],
                "aliases": ["ocean", "sea", "waves", "water", "beach"]
            }
        }
    
    def analyze_request(self, user_input: str) -> Optional[Dict]:
        """
        Analyze user input and return the best matching profile with confidence score
        
        Args:
            user_input: The user's request text
            
        Returns:
            Dictionary with profile details and match confidence, or None if no good match
        """
        # Enhanced word extraction - handle punctuation and common stop words
        clean_input = user_input.lower().replace(",", " ").replace(".", " ").replace("!", " ")
        user_words = set(word.strip() for word in clean_input.split() if word.strip())
        
        best_match = None
        best_score = 0.0
        
        print(f"🔍 Analyzing request: '{user_input}'")
        print(f"📝 Extracted words: {sorted(list(user_words))}")
        
        for profile_name, profile_data in self.profiles.items():
            score = self._calculate_match_score(user_words, profile_data)
            matched_tags = self._get_matched_tags(user_words, profile_data)
            
            print(f"🎯 Profile '{profile_name}': score={score:.3f}, matched={matched_tags}")
            
            if score > best_score:
                best_score = score
                best_match = {
                    "profile_name": profile_name,
                    "track": profile_data["track"],
                    "lighting": profile_data["lighting"],
                    "description": profile_data["description"],
                    "confidence": score,
                    "matched_tags": matched_tags
                }
        
        # Lowered threshold to 20% for better matching
        if best_score >= 0.2:
            print(f"✅ Best match: {best_match['profile_name']} (confidence: {best_score:.1%})")
            return best_match
        else:
            print(f"❌ No confident match found (best: {best_score:.1%})")
            return None
    
    def _calculate_match_score(self, user_words: set, profile_data: Dict) -> float:
        """Calculate how well user words match a profile's tags"""
        tags = profile_data["tags"]
        total_score = 0.0
        total_matches = 0
        
        # Primary tags (highest weight)
        primary_matches = len(user_words.intersection(set(tags["primary"])))
        total_score += primary_matches * 10.0
        total_matches += primary_matches
        
        # Secondary tags (medium weight)
        secondary_matches = len(user_words.intersection(set(tags["secondary"])))
        total_score += secondary_matches * 6.0
        total_matches += secondary_matches
        
        # Mood tags (medium weight)
        mood_matches = len(user_words.intersection(set(tags["moods"])))
        total_score += mood_matches * 6.0
        total_matches += mood_matches
        
        # Activity tags (lower weight)
        activity_matches = len(user_words.intersection(set(tags["activities"])))
        total_score += activity_matches * 4.0
        total_matches += activity_matches
        
        # Time tags (lower weight)
        time_matches = len(user_words.intersection(set(tags["times"])))
        total_score += time_matches * 2.0
        total_matches += time_matches
        
        # Confidence boost for key terms (very high weight)
        confidence_boost_matches = len(user_words.intersection(set(profile_data["confidence_boost"])))
        total_score += confidence_boost_matches * 15.0
        total_matches += confidence_boost_matches
        
        # Alias matches (highest weight - these are direct profile names)
        alias_matches = len(user_words.intersection(set(profile_data["aliases"])))
        total_score += alias_matches * 20.0
        total_matches += alias_matches
        
        # If no matches at all, return 0
        if total_matches == 0:
            return 0.0
        
        # Simplified scoring: base score on matches with bonus for multiple matches
        base_score = min(total_score / 100.0, 1.0)  # Normalize to reasonable scale
        
        # Bonus for multiple different types of matches
        match_types = 0
        if primary_matches > 0: match_types += 1
        if secondary_matches > 0: match_types += 1
        if mood_matches > 0: match_types += 1
        if activity_matches > 0: match_types += 1
        if confidence_boost_matches > 0: match_types += 1
        if alias_matches > 0: match_types += 1
        
        diversity_bonus = match_types * 0.1  # 10% bonus per match type
        
        return min(base_score + diversity_bonus, 1.0)
    
    def _get_matched_tags(self, user_words: set, profile_data: Dict) -> List[str]:
        """Get list of tags that matched the user input"""
        matched = []
        tags = profile_data["tags"]
        
        for category in ["primary", "secondary", "moods", "activities", "times"]:
            matched.extend(user_words.intersection(set(tags[category])))
        
        matched.extend(user_words.intersection(set(profile_data["confidence_boost"])))
        matched.extend(user_words.intersection(set(profile_data["aliases"])))
        
        return list(set(matched))  # Remove duplicates
    
    def get_firebase_command_data(self, match_result: Dict, original_input: str) -> Dict:
        """
        Convert match result to Firebase command format for the Pi listener
        
        Args:
            match_result: Result from analyze_request()
            original_input: Original user input
            
        Returns:
            Dictionary formatted for Firebase home automation commands
        """
        return {
            "action": "play_mood",
            "target": "music", 
            "device": "raspberry_pi_home",
            "timestamp": int(time.time() * 1000),
            "mood": match_result["profile_name"],
            "shuffle": False,  # Don't shuffle when using intelligent selection
            "voice_analysis": {
                "original_input": original_input,
                "matched_keywords": match_result["matched_tags"],
                "matched_contexts": [match_result["profile_name"], "intelligent_profile"],
                "confidence": match_result["confidence"],
                "selected_track": match_result["track"],
                "profile_description": match_result["description"]
            },
            "lighting_command": {
                "action": "set_ambiance_lighting",
                "target": "lights",
                "lighting_config": match_result["lighting"],
                "ambiance_analysis": {
                    "profile": match_result["profile_name"],
                    "description": match_result["description"],
                    "confidence": match_result["confidence"],
                    "matched_tags": match_result["matched_tags"]
                }
            }
        }
    
    def list_all_profiles(self) -> Dict:
        """Return all available profiles with their descriptions"""
        return {
            name: {
                "track": data["track"],
                "description": data["description"],
                "primary_tags": data["tags"]["primary"],
                "aliases": data["aliases"],
                "lighting_color": data["lighting"]["color"]
            }
            for name, data in self.profiles.items()
        }

def test_intelligent_matching():
    """Test the intelligent matching system with various inputs"""
    matcher = IntelligentProfileMatcher()
    
    test_inputs = [
        "I want forest ambiance",
        "play some relaxing music", 
        "give me ocean vibes",
        "set romantic mood for dinner",
        "I need something for focus and work",
        "play energetic workout music",
        "something chill and ambient",
        "classical music for the evening",
        "nature sounds to help me sleep",
        "happy music for celebration"
    ]
    
    print("🧪 Testing Intelligent Profile Matching System")
    print("=" * 60)
    
    for test_input in test_inputs:
        print(f"\n🔍 Input: '{test_input}'")
        
        match = matcher.analyze_request(test_input)
        
        if match:
            print(f"✅ Match: {match['profile_name']}")
            print(f"   Track: {match['track']}")
            print(f"   Lighting: {match['lighting']['color']} at {match['lighting']['brightness']}%")
            print(f"   Confidence: {match['confidence']:.1%}")
            print(f"   Matched tags: {', '.join(match['matched_tags'])}")
        else:
            print("❌ No match found")
    
    print(f"\n📋 Available Profiles:")
    profiles = matcher.list_all_profiles()
    for name, info in profiles.items():
        print(f"   {name}: Track {info['track']} - {info['description'][:50]}...")

if __name__ == "__main__":
    import time
    test_intelligent_matching()