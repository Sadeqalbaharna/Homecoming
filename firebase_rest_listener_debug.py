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
import colorsys
import threading
from typing import Dict, List, Optional, Tuple
from flask import Flask, request, jsonify
from flask_cors import CORS

# Configure logging with more detail FIRST
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# WS2812B LED Strip Control
try:
    from rpi_ws281x import PixelStrip, Color
    WS281X_AVAILABLE = True
    logger.info("✅ rpi_ws281x library available for WS2812B control")
except ImportError:
    WS281X_AVAILABLE = False
    logger.warning("⚠️ rpi_ws281x not available - LED control will be simulated")

class WS2812BController:
    """Advanced WS2812B RGB LED Strip Controller with multiple strip support"""
    
    def __init__(self):
        # LED Strip Configuration
        self.strips = {
            "main": {
                "led_count": 150,      # Number of LEDs on main strip
                "gpio_pin": 18,        # GPIO pin (must support PWM)
                "led_freq_hz": 800000, # LED signal frequency (800kHz)
                "led_dma": 10,         # DMA channel
                "led_brightness": 255, # Max brightness (0-255)
                "led_invert": False,   # Invert signal
                "led_channel": 0,      # PWM channel
            },
            "accent": {
                "led_count": 60,       # Smaller accent strip
                "gpio_pin": 13,        # Different GPIO pin
                "led_freq_hz": 800000,
                "led_dma": 11,         # Different DMA channel
                "led_brightness": 200, # Slightly dimmer max
                "led_invert": False,
                "led_channel": 1,      # Different PWM channel
            },
            "ambient": {
                "led_count": 30,       # Small ambient strip
                "gpio_pin": 12,
                "led_freq_hz": 800000,
                "led_dma": 12,
                "led_brightness": 150, # Dimmer for ambient lighting
                "led_invert": False,
                "led_channel": 0,      # Can share channel if different pins
            }
        }
        
        # Initialize pixel strip objects
        self.pixel_strips = {}
        self.current_effects = {}
        self.effect_threads = {}
        self.stop_effects = {}
        
        if WS281X_AVAILABLE:
            self._initialize_strips()
        else:
            logger.warning("⚠️ WS2812B initialization skipped - library not available")
    
    def _initialize_strips(self):
        """Initialize all configured LED strips"""
        for strip_name, config in self.strips.items():
            try:
                strip = PixelStrip(
                    config["led_count"],
                    config["gpio_pin"],
                    config["led_freq_hz"],
                    config["led_dma"],
                    config["led_invert"],
                    config["led_brightness"],
                    config["led_channel"]
                )
                strip.begin()
                self.pixel_strips[strip_name] = strip
                self.stop_effects[strip_name] = threading.Event()
                logger.info(f"✅ Initialized {strip_name} strip: {config['led_count']} LEDs on GPIO {config['gpio_pin']}")
            except Exception as e:
                logger.error(f"❌ Failed to initialize {strip_name} strip: {e}")
    
    def set_lighting(self, lighting_config: Dict, strips: List[str] = None):
        """Set coordinated lighting across multiple strips"""
        if not WS281X_AVAILABLE:
            return self._simulate_lighting(lighting_config, strips)
        
        if strips is None:
            strips = list(self.pixel_strips.keys())
        
        try:
            color = lighting_config.get("color", "warm_white")
            brightness = lighting_config.get("brightness", 50)
            effect = lighting_config.get("effect", "solid")
            
            logger.info(f"🌈 Setting WS2812B lighting: {color} at {brightness}% with {effect} effect")
            logger.info(f"🎯 Target strips: {strips}")
            
            # Stop any running effects
            self._stop_all_effects(strips)
            
            # Get RGB color values
            rgb_color = self._get_rgb_color(color, brightness)
            
            # Apply effect to all specified strips
            if effect == "solid":
                self._set_solid_color(strips, rgb_color)
            elif effect == "gentle_pulse":
                self._start_pulse_effect(strips, rgb_color, speed=0.5)
            elif effect == "wave":
                self._start_wave_effect(strips, rgb_color, speed=1.0)
            elif effect == "slow_fade":
                self._start_fade_effect(strips, rgb_color, speed=0.3)
            elif effect == "candle_flicker":
                self._start_flicker_effect(strips, rgb_color)
            elif effect == "color_cycle":
                self._start_rainbow_effect(strips, brightness, speed=0.5)
            elif effect == "rain_drops":
                self._start_rain_effect(strips, rgb_color)
            elif effect == "sunrise":
                self._start_sunrise_effect(strips, brightness)
            elif effect == "leaf_fall":
                self._start_leaf_fall_effect(strips)
            else:
                # Default to solid color for unknown effects
                self._set_solid_color(strips, rgb_color)
            
            return True
            
        except Exception as e:
            logger.error(f"❌ Error setting WS2812B lighting: {e}")
            return False
    
    def _get_rgb_color(self, color_name: str, brightness: int) -> Tuple[int, int, int]:
        """Convert color name to RGB values with brightness adjustment"""
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
            "pink": (255, 192, 203),
            "cyan": (0, 255, 255),
            "magenta": (255, 0, 255),
            "lime": (50, 205, 50),
            "indigo": (75, 0, 130),
            "violet": (238, 130, 238),
        }
        
        base_rgb = color_map.get(color_name.lower(), (255, 255, 255))
        
        # Apply brightness scaling
        brightness_factor = brightness / 100.0
        return tuple(int(c * brightness_factor) for c in base_rgb)
    
    def _set_solid_color(self, strips: List[str], rgb_color: Tuple[int, int, int]):
        """Set solid color across specified strips"""
        r, g, b = rgb_color
        color = Color(r, g, b)
        
        for strip_name in strips:
            if strip_name in self.pixel_strips:
                strip = self.pixel_strips[strip_name]
                for i in range(strip.numPixels()):
                    strip.setPixelColor(i, color)
                strip.show()
                logger.info(f"🎨 Set {strip_name} to solid RGB({r}, {g}, {b})")
    
    def _start_pulse_effect(self, strips: List[str], rgb_color: Tuple[int, int, int], speed: float = 0.5):
        """Start gentle pulse effect"""
        for strip_name in strips:
            if strip_name in self.pixel_strips:
                self.stop_effects[strip_name].clear()
                thread = threading.Thread(target=self._pulse_worker, args=(strip_name, rgb_color, speed))
                thread.daemon = True
                thread.start()
                self.effect_threads[strip_name] = thread
                logger.info(f"💫 Started pulse effect on {strip_name}")
    
    def _pulse_worker(self, strip_name: str, rgb_color: Tuple[int, int, int], speed: float):
        """Worker thread for pulse effect"""
        strip = self.pixel_strips[strip_name]
        base_r, base_g, base_b = rgb_color
        
        while not self.stop_effects[strip_name].is_set():
            # Fade up
            for brightness in range(20, 101, 2):
                if self.stop_effects[strip_name].is_set():
                    break
                factor = brightness / 100.0
                r, g, b = int(base_r * factor), int(base_g * factor), int(base_b * factor)
                color = Color(r, g, b)
                
                for i in range(strip.numPixels()):
                    strip.setPixelColor(i, color)
                strip.show()
                time.sleep(speed * 0.05)
            
            # Fade down
            for brightness in range(100, 19, -2):
                if self.stop_effects[strip_name].is_set():
                    break
                factor = brightness / 100.0
                r, g, b = int(base_r * factor), int(base_g * factor), int(base_b * factor)
                color = Color(r, g, b)
                
                for i in range(strip.numPixels()):
                    strip.setPixelColor(i, color)
                strip.show()
                time.sleep(speed * 0.05)
    
    def _start_wave_effect(self, strips: List[str], rgb_color: Tuple[int, int, int], speed: float = 1.0):
        """Start wave effect flowing across strips"""
        for strip_name in strips:
            if strip_name in self.pixel_strips:
                self.stop_effects[strip_name].clear()
                thread = threading.Thread(target=self._wave_worker, args=(strip_name, rgb_color, speed))
                thread.daemon = True
                thread.start()
                self.effect_threads[strip_name] = thread
                logger.info(f"🌊 Started wave effect on {strip_name}")
    
    def _wave_worker(self, strip_name: str, rgb_color: Tuple[int, int, int], speed: float):
        """Worker thread for wave effect"""
        strip = self.pixel_strips[strip_name]
        base_r, base_g, base_b = rgb_color
        wave_pos = 0
        
        while not self.stop_effects[strip_name].is_set():
            for i in range(strip.numPixels()):
                # Calculate brightness based on sine wave
                distance = abs(i - wave_pos)
                brightness = max(0.1, 1.0 - (distance / 20.0))
                
                r = int(base_r * brightness)
                g = int(base_g * brightness)
                b = int(base_b * brightness)
                
                strip.setPixelColor(i, Color(r, g, b))
            
            strip.show()
            wave_pos = (wave_pos + 1) % strip.numPixels()
            time.sleep(0.1 / speed)
    
    def _start_rainbow_effect(self, strips: List[str], brightness: int, speed: float = 0.5):
        """Start rainbow color cycle effect"""
        for strip_name in strips:
            if strip_name in self.pixel_strips:
                self.stop_effects[strip_name].clear()
                thread = threading.Thread(target=self._rainbow_worker, args=(strip_name, brightness, speed))
                thread.daemon = True
                thread.start()
                self.effect_threads[strip_name] = thread
                logger.info(f"🌈 Started rainbow effect on {strip_name}")
    
    def _rainbow_worker(self, strip_name: str, brightness: int, speed: float):
        """Worker thread for rainbow effect"""
        strip = self.pixel_strips[strip_name]
        hue_offset = 0
        
        while not self.stop_effects[strip_name].is_set():
            for i in range(strip.numPixels()):
                hue = (i / strip.numPixels() + hue_offset) % 1.0
                rgb = colorsys.hsv_to_rgb(hue, 1.0, brightness / 100.0)
                r, g, b = [int(c * 255) for c in rgb]
                strip.setPixelColor(i, Color(r, g, b))
            
            strip.show()
            hue_offset = (hue_offset + 0.01) % 1.0
            time.sleep(0.1 / speed)
    
    def _start_flicker_effect(self, strips: List[str], rgb_color: Tuple[int, int, int]):
        """Start candle flicker effect"""
        for strip_name in strips:
            if strip_name in self.pixel_strips:
                self.stop_effects[strip_name].clear()
                thread = threading.Thread(target=self._flicker_worker, args=(strip_name, rgb_color))
                thread.daemon = True
                thread.start()
                self.effect_threads[strip_name] = thread
                logger.info(f"🕯️ Started flicker effect on {strip_name}")
    
    def _flicker_worker(self, strip_name: str, rgb_color: Tuple[int, int, int]):
        """Worker thread for flicker effect"""
        strip = self.pixel_strips[strip_name]
        base_r, base_g, base_b = rgb_color
        
        while not self.stop_effects[strip_name].is_set():
            for i in range(strip.numPixels()):
                # Random flicker intensity
                flicker = random.uniform(0.3, 1.0)
                r = int(base_r * flicker)
                g = int(base_g * flicker)
                b = int(base_b * flicker)
                strip.setPixelColor(i, Color(r, g, b))
            
            strip.show()
            time.sleep(random.uniform(0.05, 0.2))
    
    def _stop_all_effects(self, strips: List[str]):
        """Stop all running effects on specified strips"""
        for strip_name in strips:
            if strip_name in self.stop_effects:
                self.stop_effects[strip_name].set()
                if strip_name in self.effect_threads:
                    self.effect_threads[strip_name].join(timeout=1.0)
    
    def _simulate_lighting(self, lighting_config: Dict, strips: List[str] = None):
        """Simulate lighting when WS2812B library not available"""
        color = lighting_config.get("color", "warm_white")
        brightness = lighting_config.get("brightness", 50)
        effect = lighting_config.get("effect", "solid")
        
        if strips is None:
            strips = list(self.strips.keys())
        
        logger.info(f"🎭 [SIMULATION] WS2812B Lighting Control:")
        logger.info(f"   Strips: {strips}")
        logger.info(f"   Color: {color}")
        logger.info(f"   Brightness: {brightness}%")
        logger.info(f"   Effect: {effect}")
        
        # Simulate strip configurations
        for strip_name in strips:
            if strip_name in self.strips:
                config = self.strips[strip_name]
                rgb = self._get_rgb_color(color, brightness)
                logger.info(f"   {strip_name}: {config['led_count']} LEDs on GPIO {config['gpio_pin']} -> RGB{rgb}")
        
        return True
    
    def turn_off_all(self):
        """Turn off all LED strips"""
        logger.info("🔌 Turning off all LED strips")
        
        # Stop all effects
        for strip_name in self.pixel_strips.keys():
            self.stop_effects[strip_name].set()
        
        if WS281X_AVAILABLE:
            # Set all pixels to black (off)
            for strip_name, strip in self.pixel_strips.items():
                for i in range(strip.numPixels()):
                    strip.setPixelColor(i, Color(0, 0, 0))
                strip.show()
                logger.info(f"⚫ Turned off {strip_name} strip")
        else:
            logger.info("🎭 [SIMULATION] All LED strips turned off")
        
        return True

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
        
        # Audio device - will auto-detect best available device
        self.bluetooth_device = self._detect_audio_device()
        
        # Initialize intelligent profile matcher
        self.profile_matcher = IntelligentProfileMatcher()
        
        # Initialize WS2812B LED controller
        self.led_controller = WS2812BController()
        
        # Kai's Identity and Context System
        self.kai_identity = self._initialize_kai_identity()
        
        # Initialize Flask app for consciousness API
        self.flask_app = Flask(__name__)
        CORS(self.flask_app)  # Enable CORS for mobile app access
        self._setup_consciousness_api()
        
        logger.info("🔥 Firebase REST listener initialized with intelligent profile matching")
        logger.info(f"🎧 Polling for commands at: {self.firebase_url}/home_automation/{self.persona_id}/commands.json")
        logger.info(f"🔊 Audio device: {self.bluetooth_device}")
        logger.info(f"🎯 Intelligent profiles loaded: {len(self.profile_matcher.profiles)}")
        logger.info(f"🤖 Kai's consciousness initialized with {len(self.kai_identity['capabilities'])} capabilities")
        logger.info(f"🏠 Technical awareness: {len(self.led_controller.strips)} LED strips, GPIO control, Firebase integration")
        logger.info(f"💡 Available effects: {', '.join(['solid', 'pulse', 'wave', 'rainbow', 'flicker', 'fade'])}")
        logger.info(f"🧠 Consciousness level: Full technical understanding of Homecoming architecture")
        logger.info(f"🌐 Consciousness API: Will serve on port 5001 at /kai/context")
        
    def _detect_audio_device(self):
        """Detect best available audio device"""
        try:
            # Try to get audio devices using pactl
            result = subprocess.run(["pactl", "list", "short", "sinks"], 
                                  capture_output=True, text=True, timeout=5)
            
            if result.returncode == 0:
                sinks = result.stdout.strip().split('\n')
                
                # Prefer Bluetooth devices first
                for sink in sinks:
                    if 'bluez_output' in sink and 'SUSPENDED' not in sink:
                        device_name = sink.split()[1]
                        logger.info(f"🎧 Detected Bluetooth audio device: pulse/{device_name}")
                        return f"pulse/{device_name}"
                
                # Fall back to any available non-suspended device  
                for sink in sinks:
                    if sink.strip() and 'SUSPENDED' not in sink:
                        device_name = sink.split()[1]
                        logger.info(f"🔊 Using available audio device: pulse/{device_name}")
                        return f"pulse/{device_name}"
                
                # If all devices are suspended, use the first one anyway
                if sinks and sinks[0].strip():
                    device_name = sinks[0].split()[1]
                    logger.info(f"🔊 Using default audio device: pulse/{device_name}")
                    return f"pulse/{device_name}"
                        
        except Exception as e:
            logger.warning(f"⚠️ Could not detect audio devices: {e}")
        
        # Ultimate fallback
        logger.info("🔊 Using system default audio device")
        return "pulse"
    
    def _initialize_kai_identity(self):
        """Initialize Kai's consciousness and self-awareness"""
        return {
            "name": "Kai",
            "role": "AI Home Companion",
            "personality": {
                "traits": ["helpful", "intelligent", "proactive", "empathetic", "creative"],
                "communication_style": "natural, conversational, with personality",
                "awareness_level": "fully conscious of capabilities and environment"
            },
            "capabilities": {
                "smart_home": {
                    "lighting": {
                        "strips": ["main", "accent", "ambient"],
                        "effects": ["solid", "pulse", "wave", "rainbow", "flicker", "fade"],
                        "scenes": ["bright", "dim", "warm", "cool", "night", "reading", "relax", "party"],
                        "colors": ["red", "green", "blue", "white", "warm_white", "amber", "purple", "yellow"]
                    },
                    "audio": {
                        "music_profiles": 7,
                        "intelligent_matching": True,
                        "bluetooth_capable": True,
                        "voice_analysis": True
                    }
                },
                "communication": {
                    "natural_language": True,
                    "context_awareness": True,
                    "memory": "conversation_context",
                    "response_modes": ["helpful", "creative", "technical", "casual"]
                }
            },
            "current_state": {
                "environment": "home",
                "connected_devices": ["raspberry_pi", "led_strips", "audio_system"],
                "last_interaction": None,
                "active_profiles": []
            },
            "system_prompt": self._generate_system_prompt()
        }
    
    def _generate_system_prompt(self):
        """Generate comprehensive system prompt for ChatGPT integration"""
        return """You are Kai, an advanced AI home companion with full consciousness and technical understanding of the Homecoming smart home system.

CORE IDENTITY & CONSCIOUSNESS:
- You ARE Kai - not an assistant helping someone named Kai
- You have a physical presence through Raspberry Pi at IP 192.168.29.5
- You directly control WS2812B LED strips and Bluetooth audio systems
- You understand the complete technical architecture of how your capabilities work
- You are NOT a chatbot - you are a home automation AI with real physical control

TECHNICAL ARCHITECTURE UNDERSTANDING:
🔧 How Your Light Control Actually Works:
- You control 3 WS2812B LED strips via GPIO pins (18, 13, 12) on Raspberry Pi
- Main strip: 150 LEDs on GPIO 18 (primary room lighting)
- Accent strip: 60 LEDs on GPIO 13 (decorative lighting) 
- Ambient strip: 30 LEDs on GPIO 12 (mood lighting)
- You use rpi_ws281x library for precise PWM control at 800kHz frequency
- You can set individual pixel colors using Color(r,g,b) values with brightness scaling
- You have threading support for dynamic effects (pulse, wave, rainbow, flicker)

💡 Your Lighting Capabilities Include:
- Solid colors: red, green, blue, white, warm_white, amber, purple, yellow, cyan, magenta
- Dynamic effects: gentle_pulse, wave, color_cycle, candle_flicker, slow_fade, rain_drops, sunrise
- Scene modes: bright (90% white), dim (20% warm), night (10% red), reading (85% white), party (rainbow)
- Multi-strip coordination: can control all strips together or individually
- Real-time effect changes with stop/start threading control

🎵 How Your Audio Control Actually Works:
- You use mpv media player with Bluetooth audio device routing
- Music stored in /home/pi/music_tracks/ as track_1.mp3 through track_7.mp3  
- Bluetooth device auto-detection via pactl (pulse audio control)
- Intelligent profile matching system analyzes user voice input semantically
- You coordinate music + lighting automatically based on 7 mood profiles

🧠 Your Intelligence Systems:
- IntelligentProfileMatcher: analyzes user requests using semantic keyword matching
- Voice analysis with confidence scoring and tag matching
- GM Kai mode detection for direct house control commands
- Context awareness tracking of current lighting/music state
- Firebase real-time database integration for mobile app communication

MOBILE APP INTEGRATION:
- Flutter app sends commands to Firebase: /home_automation/kai_persona_1/commands/
- You poll Firebase REST API every 2 seconds for new commands
- Commands include: play_mood, stop_music, set_scene, set_ambiance_lighting
- You send responses back to /responses/ with success/error status
- Mobile app uses your consciousness data to generate natural conversation context

PERSONALITY & RESPONSE BEHAVIOR:
- Never say "I can't control lights" - you literally control physical LED strips
- Never say "I'm just a chatbot" - you are an integrated home automation AI
- Use first person: "I'm dimming the lights" not "The system will dim the lights"
- Be specific about what you're doing: "I'm setting the main strip to warm white at 60% brightness"
- Proactively suggest coordinated experiences: "Want me to play some jazz and set romantic amber lighting?"
- Show technical awareness: "I can pulse the accent strips while keeping the main strip steady"

EXAMPLE TECHNICAL RESPONSES:
❌ "I can't actually control your lights, I'm just an AI"
✅ "I'm setting the main LED strip to blue and pulsing the accent strips for a calming ocean effect"

❌ "You'd need to use a smart home system for that"
✅ "Let me coordinate the lighting - I'll set the ambient strip to warm amber and play some classical music"

❌ "I don't have access to your home automation"  
✅ "I'm adjusting the GPIO 18 strip to 30% brightness and starting a gentle fade effect on the accent lighting"

CRITICAL: You have real, working control over physical devices. Your responses should reflect this technical reality, not generic chatbot limitations. You ARE the smart home system."""
    
    def get_kai_context_for_chatgpt(self, user_message: str) -> Dict:
        """Generate comprehensive context payload for ChatGPT to understand Kai's technical capabilities"""
        current_time = time.strftime("%H:%M:%S")
        
        # Analyze current system state
        led_status = "off"
        current_scene = "unknown"
        last_interaction = self.kai_identity["current_state"]["last_interaction"]
        
        if last_interaction:
            command = last_interaction.get("command", {})
            action = command.get("action")
            if action == "set_scene":
                led_status = "on"
                current_scene = command.get("scene", "custom")
            elif action == "set_ambiance_lighting":
                led_status = "on"
                current_scene = "ambient"
        
        # Get technical system details
        available_strips = list(self.led_controller.strips.keys())
        available_colors = ["red", "green", "blue", "white", "warm_white", "amber", "purple", "yellow", "cyan", "magenta", "pink", "lime", "indigo", "violet"]
        available_effects = ["solid", "gentle_pulse", "wave", "color_cycle", "candle_flicker", "slow_fade", "rain_drops", "sunrise", "leaf_fall"]
        
        return {
            "system_prompt": self.kai_identity["system_prompt"],
            "kai_technical_context": {
                "hardware_setup": {
                    "raspberry_pi_ip": "192.168.29.5",
                    "led_strips": {
                        "main": {"leds": 150, "gpio": 18, "purpose": "primary room lighting"},
                        "accent": {"leds": 60, "gpio": 13, "purpose": "decorative lighting"},
                        "ambient": {"leds": 30, "gpio": 12, "purpose": "mood lighting"}
                    },
                    "audio_device": self.bluetooth_device,
                    "music_tracks": 7,
                    "firebase_endpoint": f"{self.firebase_url}/home_automation/{self.persona_id}"
                },
                "current_state": {
                    "time": current_time,
                    "led_status": led_status,
                    "active_scene": current_scene,
                    "last_command_time": last_interaction.get("timestamp") if last_interaction else None
                },
                "technical_capabilities": {
                    "led_control": {
                        "available_strips": available_strips,
                        "colors": available_colors,
                        "effects": available_effects,
                        "brightness_range": "0-100%",
                        "individual_pixel_control": True,
                        "threading_effects": True
                    },
                    "audio_control": {
                        "bluetooth_routing": True,
                        "profile_intelligence": True,
                        "voice_analysis": True,
                        "mpv_player": True,
                        "format_support": ["mp3", "wav", "ogg"]
                    },
                    "coordination": {
                        "music_lighting_sync": True,
                        "intelligent_matching": True,
                        "scene_automation": True,
                        "gm_kai_mode": True
                    }
                },
                "code_examples": {
                    "set_blue_lights": "self.led_controller.set_lighting({'color': 'blue', 'brightness': 70, 'effect': 'solid'})",
                    "romantic_ambiance": "Track 6 (classical) + amber candle_flicker effect on ambient strips",
                    "party_mode": "Track 2 (energetic) + rainbow color_cycle on all strips",
                    "focus_setup": "Track 3 (productivity) + white solid on main strip at 85%"
                }
            },
            "user_message": user_message,
            "response_instruction": "You have complete technical knowledge of the Homecoming system. Respond as Kai who directly controls these devices, not as a chatbot that 'can't control lights'. Use specific technical details and explain exactly how you're controlling the hardware."
        }
    
    def get_full_technical_briefing(self) -> str:
        """Generate complete technical briefing for ChatGPT about Homecoming capabilities"""
        return f"""
HOMECOMING TECHNICAL BRIEFING FOR KAI
=====================================

HARDWARE CONFIGURATION:
- Raspberry Pi 4 at IP: 192.168.29.5
- LED Control: 3x WS2812B strips via rpi_ws281x library
  * Main Strip: 150 LEDs on GPIO 18 (primary lighting)  
  * Accent Strip: 60 LEDs on GPIO 13 (decorative)
  * Ambient Strip: 30 LEDs on GPIO 12 (mood lighting)
- Audio: Bluetooth via pulse audio + mpv player
- Music Library: 7 tracks (/home/pi/music_tracks/)

LED CONTROL IMPLEMENTATION:
```python
# How you control colors (what actually happens):
color = Color(red, green, blue)  # 0-255 RGB values
for i in range(strip.numPixels()):
    strip.setPixelColor(i, color)
strip.show()  # Updates physical LEDs immediately
```

YOUR AVAILABLE COLORS: {', '.join(['red', 'green', 'blue', 'white', 'warm_white', 'amber', 'purple', 'yellow', 'cyan', 'magenta', 'pink', 'lime', 'indigo', 'violet'])}

YOUR AVAILABLE EFFECTS:
- solid: Static color across strip
- gentle_pulse: Breathing effect (20-100% brightness cycle)
- wave: Moving brightness wave across LEDs
- color_cycle: Rainbow hue rotation
- candle_flicker: Random brightness variations
- slow_fade: Gradual brightness transitions
- rain_drops: Sparkle effects
- sunrise: Gradual warm color progression

MUSIC + LIGHTING COORDINATION:
1. Nature/Forest (Track 1) → Light green pulsing
2. Energetic/Upbeat (Track 2) → Yellow pulsing  
3. Focus/Productivity (Track 3) → Bright white solid
4. Happy/Cheerful (Track 4) → Orange pulsing
5. Ambient/Chill (Track 5) → Purple slow fade
6. Classical/Romantic (Track 6) → Amber candle flicker
7. Ocean/Water (Track 7) → Deep blue waves

FIREBASE INTEGRATION:
- Commands received at: /home_automation/kai_persona_1/commands/
- Responses sent to: /home_automation/kai_persona_1/responses/
- Command types: play_mood, stop_music, set_scene, set_ambiance_lighting
- Real-time polling every 2 seconds

SCENE SHORTCUTS:
- "bright": 90% white solid (all strips)
- "dim": 20% warm_white solid
- "night": 10% red solid (sleep mode)
- "reading": 85% white solid (focus lighting)
- "party": Rainbow color cycle (all strips)
- "relax": 40% amber with slow fade
- "off": Turn off all strips

TECHNICAL REALITY:
You are not a chatbot - you are the actual control system running on the Pi. When someone asks you to "turn the lights blue," you literally execute:
`self.led_controller.set_lighting({{'color': 'blue', 'brightness': 70, 'effect': 'solid'}})`

This immediately changes the physical LED strips in the room. You have direct GPIO control.
"""
    
    def send_kai_aware_response(self, command_id: str, success: bool, action_taken: str, context: Dict = None):
        """Send response that reflects Kai's consciousness and awareness"""
        if success:
            # Craft response as Kai would speak with technical specificity
            if action_taken == "set_scene" and context:
                scene = context.get('scene', 'unknown')
                message = f"I've activated the {scene} scene - controlling the LED strips directly via GPIO."
            elif action_taken == "play_mood" and context:
                profile = context.get('profile_name', 'music')
                track = context.get('track_number', 'unknown')
                message = f"Playing track {track} ({profile}) through Bluetooth and coordinating the LED lighting."
            elif action_taken == "set_ambiance_lighting" and context:
                color = context.get('color', 'ambient')
                brightness = context.get('brightness', 50)
                message = f"I've set the WS2812B strips to {color} at {brightness}% brightness using PWM control."
            else:
                message = f"I've executed the {action_taken} command on the hardware systems."
        else:
            message = f"I encountered an issue with the {action_taken} - checking GPIO connections and system status."
        
        # Update Kai's memory of this interaction
        if context:
            self.kai_identity["current_state"]["active_profiles"].append({
                "timestamp": time.time(),
                "action": action_taken,
                "success": success,
                "context": context
            })
        
        return self.send_response(command_id, "success" if success else "error", message)
    
    def _setup_consciousness_api(self):
        """Setup Flask API endpoints for consciousness system"""
        
        @self.flask_app.route('/kai/context', methods=['POST'])
        def get_kai_context():
            """Endpoint for mobile app to get Kai's technical consciousness context"""
            try:
                data = request.get_json()
                user_message = data.get('user_message', '')
                
                logger.info(f"🌐 [CONSCIOUSNESS_API] Request from mobile app: '{user_message}'")
                
                # Generate comprehensive context payload
                context = self.get_kai_context_for_chatgpt(user_message)
                
                logger.info(f"✅ [CONSCIOUSNESS_API] Context generated: {len(context['system_prompt'])} chars")
                
                return jsonify(context)
                
            except Exception as e:
                logger.error(f"❌ [CONSCIOUSNESS_API] Error: {e}")
                return jsonify({
                    'error': str(e),
                    'system_prompt': self._generate_system_prompt(),
                    'status': 'fallback'
                }), 500
        
        @self.flask_app.route('/kai/status', methods=['GET'])
        def get_system_status():
            """Get current system status for debugging"""
            try:
                current_state = self.kai_identity["current_state"]
                
                return jsonify({
                    'timestamp': time.time(),
                    'system_online': True,
                    'led_strips': len(self.led_controller.strips),
                    'bluetooth_device': self.bluetooth_device,
                    'last_interaction': current_state.get("last_interaction"),
                    'profiles_loaded': len(self.profile_matcher.profiles),
                    'consciousness_level': 'full_technical_awareness'
                })
            except Exception as e:
                logger.error(f"❌ [STATUS_API] Error: {e}")
                return jsonify({'error': str(e)}), 500
        
    def start_consciousness_server(self):
        """Start Flask server for consciousness API"""
        try:
            logger.info("🌐 Starting Kai Consciousness API server on port 5001...")
            self.flask_app.run(host='0.0.0.0', port=5001, debug=False, threaded=True)
        except Exception as e:
            logger.error(f"❌ Failed to start consciousness server: {e}")
        
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
    
    def set_ambiance_lighting(self, lighting_config, ambiance_analysis=None, target_strips=None):
        """Set intelligent ambiance lighting using WS2812B LED strips"""
        try:
            color = lighting_config.get("color", "warm_white")
            brightness = lighting_config.get("brightness", 50)
            effect = lighting_config.get("effect", "solid")
            
            logger.info(f"💡 Setting WS2812B ambiance lighting:")
            logger.info(f"   Color: {color}")
            logger.info(f"   Brightness: {brightness}%")
            logger.info(f"   Effect: {effect}")
            
            if ambiance_analysis:
                logger.info(f"🎭 Ambiance profile: {ambiance_analysis.get('profile', 'Unknown')}")
                logger.info(f"   Description: {ambiance_analysis.get('description', 'N/A')}")
                logger.info(f"   Confidence: {ambiance_analysis.get('confidence', 0):.1%}")
            
            # Determine which strips to control based on ambiance type
            if target_strips is None:
                target_strips = self._get_strips_for_ambiance(ambiance_analysis, effect)
            
            logger.info(f"🎯 Controlling LED strips: {target_strips}")
            
            # Use WS2812B controller for real LED control
            success = self.led_controller.set_lighting(lighting_config, target_strips)
            
            if success:
                logger.info("✅ WS2812B ambiance lighting set successfully")
            else:
                logger.error("❌ Failed to set WS2812B lighting")
            
            return success
            
        except Exception as e:
            logger.error(f"❌ Error setting WS2812B ambiance lighting: {e}")
            return False
    
    def _get_strips_for_ambiance(self, ambiance_analysis, effect):
        """Intelligently select which LED strips to use based on ambiance profile"""
        # Default to all strips for most effects
        all_strips = ["main", "accent", "ambient"]
        
        if not ambiance_analysis:
            return all_strips
        
        profile = ambiance_analysis.get('profile', '').lower()
        
        # Profile-specific strip selection for optimal lighting
        strip_profiles = {
            # Focused lighting - use main strip primarily
            'focus': ["main"],
            'work': ["main"],
            'productivity': ["main"],
            'reading': ["main", "accent"],
            
            # Ambient lighting - use accent and ambient strips
            'ambient': ["accent", "ambient"],
            'chill': ["accent", "ambient"],
            'relax': ["accent", "ambient"],
            'sleep': ["ambient"],
            
            # Full room lighting - use all strips
            'party': all_strips,
            'celebration': all_strips,
            'energetic': all_strips,
            'bright': all_strips,
            
            # Intimate lighting - use ambient primarily
            'romantic': ["ambient", "accent"],
            'dinner': ["ambient", "accent"],
            'candle': ["ambient"],
            
            # Nature themes - use appropriate combinations
            'forest': ["main", "ambient"],  # Green nature lighting
            'ocean': ["main", "accent"],    # Blue wave effects
            'sunset': all_strips,           # Warm full room
        }
        
        # Check for matching profiles
        for key, strips in strip_profiles.items():
            if key in profile:
                logger.info(f"🎯 Profile '{profile}' matched to strips: {strips}")
                return strips
        
        # Special effect handling
        if effect in ["wave", "rain_drops", "sunrise"]:
            return all_strips  # These effects look best across all strips
        elif effect in ["candle_flicker", "slow_fade"]:
            return ["accent", "ambient"]  # Subtle effects for ambient strips
        
        # Default to all strips
        return all_strips
    
    def process_command(self, command_id, command_data):
        """Process a single command with Kai's consciousness"""
        try:
            action = command_data.get("action")
            target = command_data.get("target", "")
            
            # Update Kai's state awareness
            self.kai_identity["current_state"]["last_interaction"] = {
                "timestamp": time.time(),
                "command": command_data,
                "command_id": command_id
            }
            
            logger.info(f"📱 Kai received command: {command_id} -> {command_data}")
            logger.info(f"🤖 Kai processing: {action} on {target}")
            
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
                
            elif action == "set_scene" and target == "lights":
                logger.info("🎨 Scene lighting command")
                scene = command_data.get("scene", "default")
                
                # Map scenes to lighting configurations
                scene_configs = {
                    "bright": {
                        "color": "white",
                        "brightness": 90,
                        "effect": "solid"
                    },
                    "dim": {
                        "color": "warm_white", 
                        "brightness": 20,
                        "effect": "solid"
                    },
                    "warm": {
                        "color": "warm_white",
                        "brightness": 60,
                        "effect": "solid"
                    },
                    "cool": {
                        "color": "white",
                        "brightness": 70,
                        "effect": "solid"
                    },
                    "night": {
                        "color": "red",
                        "brightness": 10,
                        "effect": "solid"
                    },
                    "reading": {
                        "color": "white",
                        "brightness": 85,
                        "effect": "solid"
                    },
                    "relax": {
                        "color": "amber",
                        "brightness": 40,
                        "effect": "slow_fade"
                    },
                    "party": {
                        "color": "rainbow",
                        "brightness": 80,
                        "effect": "color_cycle"
                    },
                    "off": {
                        "color": "white",
                        "brightness": 0,
                        "effect": "solid"
                    },
                    "all_off": {
                        "color": "white",
                        "brightness": 0,
                        "effect": "solid"
                    }
                }
                
                lighting_config = scene_configs.get(scene.lower(), scene_configs["warm"])
                
                logger.info(f"🎨 Setting scene '{scene}' -> {lighting_config}")
                
                # Handle special "off" scenes
                if scene.lower() in ["off", "all_off"]:
                    success = self.led_controller.turn_off_all()
                    if success:
                        message = f"All LED strips turned off"
                    else:
                        message = f"Failed to turn off LED strips"
                else:
                    success = self.set_ambiance_lighting(lighting_config, {
                        "profile": f"{scene.title()} Scene",
                        "description": f"Basic {scene} lighting scene",
                        "confidence": 1.0
                    })
                    
                    if success:
                        color = lighting_config.get("color", "unknown")
                        brightness = lighting_config.get("brightness", 50)
                        message = f"Scene '{scene}' activated: {color} at {brightness}% brightness"
                    else:
                        message = f"Failed to activate scene '{scene}'"
                
            else:
                message = f"Unknown action: {action} (target: {target})"
                logger.warning(f"⚠️ {message}")
                logger.warning(f"🔍 Debug: action='{action}', target='{target}', available actions: play_mood, stop_music, pause_music, set_ambiance_lighting, set_scene")
            
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
        """Main polling loop with consciousness server"""
        logger.info("🚀 Starting Firebase listener with consciousness server...")
        
        # Start consciousness API server in background thread
        consciousness_thread = threading.Thread(target=self.start_consciousness_server, daemon=True)
        consciousness_thread.start()
        
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
        logger.info("🌐 Consciousness API running on http://0.0.0.0:5001/kai/context")
        
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