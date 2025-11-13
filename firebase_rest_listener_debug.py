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
import math
import math
from typing import Dict, List, Optional, Tuple
from flask import Flask, request, jsonify
from flask_cors import CORS
import yt_dlp

def run_sudo_led_command(r, g, b, brightness=80):
    """Run LED command with sudo to bypass permission issues"""
    try:
        led_script_content = f"""#!/usr/bin/env python3
try:
    from rpi_ws281x import PixelStrip, Color
    strip = PixelStrip(300, 18, 800000, 10, False, {brightness}, 0)
    strip.begin()
    color = Color({r}, {g}, {b})
    for i in range(300):
        strip.setPixelColor(i, color)
    strip.show()
    print("LEDs set successfully")
except Exception as e:
    print(f"LED Error: {{e}}")
"""
        with open('/tmp/led_set.py', 'w') as f:
            f.write(led_script_content)
        import os
        os.chmod('/tmp/led_set.py', 0o755)
        import subprocess
        result = subprocess.run(['sudo', 'python3', '/tmp/led_set.py'], capture_output=True, text=True, timeout=10)
        print(f"✅ Sudo LED control: RGB({r},{g},{b}) at {brightness}%")
        return result.returncode == 0
    except Exception as e:
        print(f"⚠️ Sudo LED error: {e}")
        return False

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
        # LED Strip Configuration - LEGENDARY 300 LED SETUP! 🏆
        self.strips = {
            "main": {
                "led_count": 300,      # LEGENDARY: All 300 LEDs confirmed working!
                "gpio_pin": 18,        # CONFIRMED: GPIO 18 working perfectly
                "led_freq_hz": 800000, # LED signal frequency (800kHz)
                "led_dma": 10,         # DMA channel
                "led_brightness": 200, # High brightness (you have proper power!)
                "led_invert": False,   # Invert signal
                "led_channel": 0,      # PWM channel
            },
            # Optional: You could add zones for different areas
            "ambient": {
                "led_count": 300,      # All 300 LEDs for ambient lighting
                "gpio_pin": 18,        # Same GPIO as main
                "led_freq_hz": 800000,
                "led_dma": 10,
                "led_brightness": 200,
                "led_invert": False,
                "led_channel": 0,
            },
            "accent": {
                "led_count": 300,      # All 300 LEDs for accent lighting
                "gpio_pin": 18,
                "led_freq_hz": 800000,
                "led_dma": 10,
                "led_brightness": 200,
                "led_invert": False,
                "led_channel": 0,
            },
            "zone1": {
                "led_count": 100,      # First 100 LEDs (0-99)
                "gpio_pin": 18,
                "led_freq_hz": 800000,
                "led_dma": 10,
                "led_brightness": 200,
                "led_invert": False,
                "led_channel": 0,
                "led_offset": 0,
            },
            "zone2": {
                "led_count": 100,      # Middle 100 LEDs (100-199)
                "gpio_pin": 18,
                "led_freq_hz": 800000,
                "led_dma": 10,
                "led_brightness": 200,
                "led_invert": False,
                "led_channel": 0,
                "led_offset": 100,
            },
            "zone3": {
                "led_count": 100,      # Last 100 LEDs (200-299)
                "gpio_pin": 18,
                "led_freq_hz": 800000,
                "led_dma": 10,
                "led_brightness": 200,
                "led_invert": False,
                "led_channel": 0,
                "led_offset": 200,
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
                # Enable sudo LED fallback mode
                logger.info(f"💡 Enabling sudo LED control for {strip_name}")
                self.pixel_strips[strip_name] = "sudo_mode"
    
    def _has_sudo_mode_strips(self, strips: List[str]) -> bool:
        """Check if any of the target strips are in sudo mode"""
        return any(self.pixel_strips.get(strip_name) == "sudo_mode" for strip_name in strips if strip_name in self.pixel_strips)
    
    def _apply_sudo_lighting(self, strips: List[str], rgb_color: Tuple[int, int, int], effect: str) -> bool:
        """Apply lighting via sudo for strips in sudo mode"""
        r, g, b = rgb_color
        success = True
        
        for strip_name in strips:
            if strip_name in self.pixel_strips and self.pixel_strips[strip_name] == "sudo_mode":
                logger.info(f"💡 Using sudo LED control for {strip_name} ({effect} effect)")
                if run_sudo_led_command(r, g, b, brightness=80):
                    logger.info(f"✅ Set {strip_name} to RGB({r}, {g}, {b}) via sudo ({effect} simplified to solid)")
                else:
                    logger.warning(f"⚠️ Sudo LED control failed for {strip_name}, simulating")
                    logger.info(f"🎨 SIMULATED: {effect} effect on {strip_name}")
                    success = False
        
        return success

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
            
            # Get RGB color values
            rgb_color = self._get_rgb_color(color, brightness)
            
            # Check if we have sudo mode strips
            if self._has_sudo_mode_strips(strips):
                logger.info("💡 Detected sudo mode strips, using simplified lighting")
                return self._apply_sudo_lighting(strips, rgb_color, effect)
            
            # Stop any running effects for normal strips
            self._stop_all_effects(strips)
            
            # Apply effect to normal strips only
            normal_strips = [s for s in strips if s in self.pixel_strips and self.pixel_strips[s] != "sudo_mode"]
            
            if not normal_strips:
                return True  # All strips handled by sudo
            
            # Apply effect to normal strips
            if effect == "solid":
                self._set_solid_color(normal_strips, rgb_color)
            elif effect == "gentle_pulse":
                self._start_pulse_effect(normal_strips, rgb_color, speed=0.5)
            elif effect == "wave":
                self._start_wave_effect(normal_strips, rgb_color, speed=1.0)
            elif effect == "slow_fade":
                self._start_fade_effect(normal_strips, rgb_color, speed=0.3)
            elif effect == "candle_flicker":
                self._start_flicker_effect(normal_strips, rgb_color)
            elif effect == "color_cycle":
                self._start_rainbow_effect(normal_strips, brightness, speed=0.5)
            elif effect == "rain_drops":
                self._start_rain_effect(normal_strips, rgb_color)
            elif effect == "sunrise":
                self._start_sunrise_effect(normal_strips, brightness)
            elif effect == "leaf_fall":
                self._start_leaf_fall_effect(normal_strips)
            elif effect == "lightning":
                self._start_lightning_effect(normal_strips)
            elif effect == "aurora":
                self._start_aurora_effect(normal_strips)
            elif effect == "meteor":
                self._start_meteor_effect(normal_strips, rgb_color)
            elif effect == "fire":
                self._start_fire_effect(normal_strips)
            elif effect == "ocean_wave":
                self._start_ocean_wave_effect(normal_strips)
            elif effect == "matrix":
                self._start_matrix_effect(normal_strips)
            else:
                # Default to solid color for unknown effects
                self._set_solid_color(normal_strips, rgb_color)
            
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
        
        for strip_name in strips:
            if strip_name in self.pixel_strips:
                strip = self.pixel_strips[strip_name]
                
                # Check if this strip is in sudo mode
                if strip == "sudo_mode":
                    logger.info(f"💡 Using sudo LED control for {strip_name}")
                    if run_sudo_led_command(r, g, b, brightness=80):
                        logger.info(f"🎨 Set {strip_name} to solid RGB({r}, {g}, {b}) via sudo")
                    else:
                        logger.warning(f"⚠️ Sudo LED control failed for {strip_name}, simulating")
                        logger.info(f"🎨 SIMULATED: Set {strip_name} to solid RGB({r}, {g}, {b})")
                else:
                    # Normal strip operation
                    color = Color(r, g, b)
                    for i in range(strip.numPixels()):
                        strip.setPixelColor(i, color)
                    strip.show()
                    logger.info(f"🎨 Set {strip_name} to solid RGB({r}, {g}, {b})")
    
    def _start_pulse_effect(self, strips: List[str], rgb_color: Tuple[int, int, int], speed: float = 0.5):
        """Start gentle pulse effect"""
        for strip_name in strips:
            if strip_name in self.pixel_strips:
                strip = self.pixel_strips[strip_name]
                
                # Check if this strip is in sudo mode
                if strip == "sudo_mode":
                    logger.info(f"💡 Using sudo LED control for {strip_name} pulse effect")
                    r, g, b = rgb_color
                    if run_sudo_led_command(r, g, b, brightness=70):
                        logger.info(f"💫 Set {strip_name} to pulse RGB({r}, {g}, {b}) via sudo (simplified to solid)")
                    else:
                        logger.warning(f"⚠️ Sudo LED pulse failed for {strip_name}, simulating")
                        logger.info(f"💫 SIMULATED: Pulse effect on {strip_name}")
                else:
                    # Normal strip operation
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
    
    def _start_lightning_effect(self, strips: List[str]):
        """Epic lightning effect for 300 LEDs"""
        for strip_name in strips:
            if strip_name in self.pixel_strips:
                self.stop_effects[strip_name].clear()
                thread = threading.Thread(target=self._lightning_worker, args=(strip_name,))
                thread.daemon = True
                thread.start()
                self.effect_threads[strip_name] = thread
                logger.info(f"⚡ Started EPIC lightning effect on {strip_name}")
    
    def _lightning_worker(self, strip_name: str):
        """Epic lightning worker for 300 LEDs"""
        strip = self.pixel_strips[strip_name]
        total_leds = strip.numPixels()
        
        while not self.stop_effects[strip_name].is_set():
            # Clear all LEDs
            for i in range(total_leds):
                strip.setPixelColor(i, Color(0, 0, 0))
            strip.show()
            
            # Random lightning strikes
            for strike in range(random.randint(1, 4)):
                if self.stop_effects[strip_name].is_set():
                    break
                
                # Lightning bolt across random section
                start_pos = random.randint(0, max(0, total_leds - 50))
                length = random.randint(20, min(80, total_leds - start_pos))
                
                # Bright white lightning
                for i in range(start_pos, start_pos + length):
                    intensity = random.randint(200, 255)
                    strip.setPixelColor(i, Color(intensity, intensity, intensity))
                strip.show()
                
                # Lightning flash duration
                time.sleep(random.uniform(0.05, 0.15))
                
                # Fade out quickly
                for fade in range(5):
                    for i in range(start_pos, start_pos + length):
                        intensity = max(0, 255 - (fade * 50))
                        strip.setPixelColor(i, Color(intensity, intensity, intensity))
                    strip.show()
                    time.sleep(0.02)
            
            # Dark pause between lightning
            time.sleep(random.uniform(2, 8))
    
    def _start_aurora_effect(self, strips: List[str]):
        """Aurora borealis effect for 300 LEDs"""
        for strip_name in strips:
            if strip_name in self.pixel_strips:
                self.stop_effects[strip_name].clear()
                thread = threading.Thread(target=self._aurora_worker, args=(strip_name,))
                thread.daemon = True
                thread.start()
                self.effect_threads[strip_name] = thread
                logger.info(f"🌌 Started EPIC aurora effect on {strip_name}")
    
    def _aurora_worker(self, strip_name: str):
        """Aurora borealis worker"""
        strip = self.pixel_strips[strip_name]
        total_leds = strip.numPixels()
        offset = 0
        
        while not self.stop_effects[strip_name].is_set():
            for i in range(total_leds):
                # Aurora wave calculation
                wave1 = int(128 + 127 * math.sin((i + offset) * 0.02))
                wave2 = int(128 + 127 * math.sin((i + offset) * 0.03 + 1))
                wave3 = int(128 + 127 * math.sin((i + offset) * 0.01 + 2))
                
                # Aurora colors (green, blue, purple)
                green = max(0, min(255, wave1))
                blue = max(0, min(255, wave2))
                red = max(0, min(255, wave3 // 4))  # Less red for aurora effect
                
                strip.setPixelColor(i, Color(red, green, blue))
            
            strip.show()
            offset += 2
            time.sleep(0.05)
    
    def _start_meteor_effect(self, strips: List[str], rgb_color: Tuple[int, int, int]):
        """Meteor shower effect for 300 LEDs"""
        for strip_name in strips:
            if strip_name in self.pixel_strips:
                self.stop_effects[strip_name].clear()
                thread = threading.Thread(target=self._meteor_worker, args=(strip_name, rgb_color))
                thread.daemon = True
                thread.start()
                self.effect_threads[strip_name] = thread
                logger.info(f"☄️ Started EPIC meteor effect on {strip_name}")
    
    def _meteor_worker(self, strip_name: str, rgb_color: Tuple[int, int, int]):
        """Meteor shower worker"""
        strip = self.pixel_strips[strip_name]
        total_leds = strip.numPixels()
        meteors = []
        
        while not self.stop_effects[strip_name].is_set():
            # Clear strip with fade
            for i in range(total_leds):
                current = strip.getPixelColor(i)
                # Fade existing pixels
                r = max(0, ((current >> 16) & 0xFF) - 5)
                g = max(0, ((current >> 8) & 0xFF) - 5) 
                b = max(0, (current & 0xFF) - 5)
                strip.setPixelColor(i, Color(r, g, b))
            
            # Add new meteors randomly
            if random.randint(1, 20) == 1 and len(meteors) < 5:
                meteors.append({
                    'pos': 0,
                    'speed': random.uniform(0.8, 2.0),
                    'color': rgb_color,
                    'tail_length': random.randint(15, 30)
                })
            
            # Update meteors
            for meteor in meteors[:]:
                meteor['pos'] += meteor['speed']
                
                # Draw meteor with tail
                for i in range(meteor['tail_length']):
                    pos = int(meteor['pos'] - i)
                    if 0 <= pos < total_leds:
                        brightness = max(0, 255 - (i * 15))
                        r = int(meteor['color'][0] * brightness / 255)
                        g = int(meteor['color'][1] * brightness / 255)
                        b = int(meteor['color'][2] * brightness / 255)
                        strip.setPixelColor(pos, Color(r, g, b))
                
                # Remove meteors that have passed
                if meteor['pos'] > total_leds + meteor['tail_length']:
                    meteors.remove(meteor)
            
            strip.show()
            time.sleep(0.03)
    
    def _start_fire_effect(self, strips: List[str]):
        """Realistic fire effect for 300 LEDs"""
        for strip_name in strips:
            if strip_name in self.pixel_strips:
                self.stop_effects[strip_name].clear()
                thread = threading.Thread(target=self._fire_worker, args=(strip_name,))
                thread.daemon = True
                thread.start()
                self.effect_threads[strip_name] = thread
                logger.info(f"🔥 Started EPIC fire effect on {strip_name}")
    
    def _fire_worker(self, strip_name: str):
        """Realistic fire worker"""
        strip = self.pixel_strips[strip_name]
        total_leds = strip.numPixels()
        heat = [0] * total_leds
        
        while not self.stop_effects[strip_name].is_set():
            # Cool down every cell a little
            for i in range(total_leds):
                heat[i] = max(0, heat[i] - random.randint(0, ((55 * 10) // total_leds) + 2))
            
            # Heat from each cell drifts 'up' and diffuses a little
            for k in range(total_leds - 1, 2, -1):
                heat[k] = (heat[k - 1] + heat[k - 2] + heat[k - 2]) // 3
            
            # Randomly ignite new 'sparks' near bottom
            if random.randint(1, 255) < 120:
                y = random.randint(0, 7)
                if y < total_leds:
                    heat[y] = min(255, heat[y] + random.randint(160, 255))
            
            # Map heat to LED colors
            for j in range(total_leds):
                # Scale heat to 0-191
                t192 = int((heat[j] / 255.0) * 191)
                
                # Calculate ramp up from black to red to yellow to white
                heatramp = t192 & 0x3F  # 0..63
                heatramp <<= 2  # scale up to 0..252
                
                if t192 > 0x80:  # hottest
                    r, g, b = 255, 255, heatramp
                elif t192 > 0x40:  # middle
                    r, g, b = 255, heatramp, 0
                else:  # coolest
                    r, g, b = heatramp, 0, 0
                
                strip.setPixelColor(j, Color(r, g, b))
            
            strip.show()
            time.sleep(0.05)
    
    def _start_ocean_wave_effect(self, strips: List[str]):
        """Ocean wave effect for 300 LEDs"""
        for strip_name in strips:
            if strip_name in self.pixel_strips:
                self.stop_effects[strip_name].clear()
                thread = threading.Thread(target=self._ocean_wave_worker, args=(strip_name,))
                thread.daemon = True
                thread.start()
                self.effect_threads[strip_name] = thread
                logger.info(f"🌊 Started EPIC ocean wave effect on {strip_name}")
    
    def _ocean_wave_worker(self, strip_name: str):
        """Ocean wave worker"""
        strip = self.pixel_strips[strip_name]
        total_leds = strip.numPixels()
        offset = 0
        
        while not self.stop_effects[strip_name].is_set():
            for i in range(total_leds):
                # Multiple wave layers
                wave1 = math.sin((i + offset) * 0.05)
                wave2 = math.sin((i + offset) * 0.03 + 2)
                wave3 = math.sin((i + offset) * 0.01 + 1)
                
                # Combine waves
                combined = (wave1 + wave2 + wave3) / 3
                
                # Ocean blue colors
                blue_intensity = int(128 + 127 * combined)
                green_intensity = int(64 + 64 * combined)
                
                # Add white foam on peaks
                white_foam = max(0, int((combined - 0.7) * 255)) if combined > 0.7 else 0
                
                r = white_foam
                g = green_intensity + white_foam // 2
                b = blue_intensity + white_foam // 2
                
                strip.setPixelColor(i, Color(r, g, b))
            
            strip.show()
            offset += 1
            time.sleep(0.08)
    
    def _start_matrix_effect(self, strips: List[str]):
        """Matrix digital rain effect for 300 LEDs"""
        for strip_name in strips:
            if strip_name in self.pixel_strips:
                self.stop_effects[strip_name].clear()
                thread = threading.Thread(target=self._matrix_worker, args=(strip_name,))
                thread.daemon = True
                thread.start()
                self.effect_threads[strip_name] = thread
                logger.info(f"💻 Started EPIC Matrix effect on {strip_name}")
    
    def _matrix_worker(self, strip_name: str):
        """Matrix digital rain worker"""
        strip = self.pixel_strips[strip_name]
        total_leds = strip.numPixels()
        drops = []
        
        while not self.stop_effects[strip_name].is_set():
            # Fade all LEDs
            for i in range(total_leds):
                current = strip.getPixelColor(i)
                g = max(0, ((current >> 8) & 0xFF) - 8)  # Fade green channel
                strip.setPixelColor(i, Color(0, g, 0))
            
            # Add new drops randomly
            if random.randint(1, 10) == 1:
                drops.append({
                    'pos': 0,
                    'speed': random.uniform(0.5, 1.5),
                    'length': random.randint(10, 25)
                })
            
            # Update drops
            for drop in drops[:]:
                drop['pos'] += drop['speed']
                
                # Draw drop
                for i in range(drop['length']):
                    pos = int(drop['pos'] - i)
                    if 0 <= pos < total_leds:
                        if i == 0:  # Head of drop
                            strip.setPixelColor(pos, Color(0, 255, 0))
                        else:  # Tail fading
                            intensity = max(0, 255 - (i * 15))
                            strip.setPixelColor(pos, Color(0, intensity, 0))
                
                # Remove drops that have passed
                if drop['pos'] > total_leds + drop['length']:
                    drops.remove(drop)
            
            strip.show()
            time.sleep(0.05)
    
    def _stop_all_effects(self, strips: List[str]):
        """Stop all running effects on specified strips"""
        for strip_name in strips:
            if strip_name in self.stop_effects:
                self.stop_effects[strip_name].set()
                if strip_name in self.effect_threads:
                    self.effect_threads[strip_name].join(timeout=1.0)
    
    def set_dynamic_lighting(self, dynamic_config: Dict, strips: List[str] = None):
        """Set dynamic ambient lighting with multiple colors and advanced effects"""
        if not WS281X_AVAILABLE:
            return self._simulate_dynamic_lighting(dynamic_config, strips)
        
        if strips is None:
            strips = list(self.pixel_strips.keys())
        
        try:
            primary_color = dynamic_config.get("primary_color", "#4A148C")
            secondary_color = dynamic_config.get("secondary_color", "#7B1FA2")
            accent_color = dynamic_config.get("accent_color", "#1A237E")
            brightness = dynamic_config.get("brightness", 70)
            effect = dynamic_config.get("effect", "breathe")
            speed = dynamic_config.get("speed", 1.0)
            zones = dynamic_config.get("zones", {})
            
            logger.info(f"🎆 Setting dynamic lighting: {primary_color} -> {secondary_color} -> {accent_color}")
            logger.info(f"🎭 Effect: {effect} at speed {speed}, brightness {brightness}%")
            logger.info(f"🗺️ Zones: {zones}")
            
            # Stop any running effects
            self._stop_all_effects(strips)
            
            # Convert hex colors to RGB
            primary_rgb = self._hex_to_rgb(primary_color, brightness)
            secondary_rgb = self._hex_to_rgb(secondary_color, brightness)
            accent_rgb = self._hex_to_rgb(accent_color, brightness)
            
            # Apply dynamic effect based on pattern
            if effect == "breathe":
                self._start_dynamic_breathe_effect(strips, primary_rgb, secondary_rgb, speed)
            elif effect == "pulse":
                self._start_dynamic_pulse_effect(strips, primary_rgb, accent_rgb, speed)
            elif effect == "strobe":
                self._start_dynamic_strobe_effect(strips, [primary_rgb, secondary_rgb, accent_rgb], speed)
            elif effect == "random":
                self._start_dynamic_random_effect(strips, [primary_rgb, secondary_rgb, accent_rgb], speed)
            elif effect == "gradient":
                self._start_dynamic_gradient_effect(strips, primary_rgb, secondary_rgb, accent_rgb, speed)
            else:
                # Default to solid primary color
                self._set_solid_color(strips, primary_rgb)
            
            return True
            
        except Exception as e:
            logger.error(f"❌ Error setting dynamic lighting: {e}")
            return False
    
    def _hex_to_rgb(self, hex_color: str, brightness: int) -> Tuple[int, int, int]:
        """Convert hex color to RGB with brightness adjustment"""
        try:
            # Remove # if present
            hex_color = hex_color.lstrip('#')
            
            # Convert hex to RGB
            r = int(hex_color[0:2], 16)
            g = int(hex_color[2:4], 16) 
            b = int(hex_color[4:6], 16)
            
            # Apply brightness
            brightness_factor = brightness / 100.0
            return (int(r * brightness_factor), int(g * brightness_factor), int(b * brightness_factor))
            
        except (ValueError, IndexError):
            logger.warning(f"⚠️ Invalid hex color: {hex_color}, using white")
            brightness_factor = brightness / 100.0
            return (int(255 * brightness_factor), int(255 * brightness_factor), int(255 * brightness_factor))
    
    def _start_dynamic_breathe_effect(self, strips: List[str], color1: Tuple[int, int, int], color2: Tuple[int, int, int], speed: float):
        """Dynamic breathing effect between two colors"""
        for strip_name in strips:
            if strip_name in self.pixel_strips:
                self.stop_effects[strip_name] = threading.Event()
                thread = threading.Thread(
                    target=self._dynamic_breathe_worker,
                    args=(strip_name, color1, color2, speed)
                )
                thread.daemon = True
                thread.start()
                self.effect_threads[strip_name] = thread
    
    def _dynamic_breathe_worker(self, strip_name: str, color1: Tuple[int, int, int], color2: Tuple[int, int, int], speed: float):
        """Worker thread for dynamic breathing effect"""
        strip = self.pixel_strips[strip_name]
        stop_event = self.stop_effects[strip_name]
        
        phase = 0
        while not stop_event.is_set():
            # Interpolate between colors based on sine wave
            t = (math.sin(phase) + 1) / 2  # Normalize to 0-1
            
            r = int(color1[0] * (1 - t) + color2[0] * t)
            g = int(color1[1] * (1 - t) + color2[1] * t)
            b = int(color1[2] * (1 - t) + color2[2] * t)
            
            color = Color(r, g, b)
            
            for i in range(strip.numPixels()):
                strip.setPixelColor(i, color)
            strip.show()
            
            phase += 0.1 * speed
            time.sleep(0.05)
    
    def _start_dynamic_gradient_effect(self, strips: List[str], color1: Tuple[int, int, int], color2: Tuple[int, int, int], color3: Tuple[int, int, int], speed: float):
        """Dynamic gradient effect with three colors"""
        for strip_name in strips:
            if strip_name in self.pixel_strips:
                self.stop_effects[strip_name] = threading.Event()
                thread = threading.Thread(
                    target=self._dynamic_gradient_worker,
                    args=(strip_name, color1, color2, color3, speed)
                )
                thread.daemon = True
                thread.start()
                self.effect_threads[strip_name] = thread
    
    def _dynamic_gradient_worker(self, strip_name: str, color1: Tuple[int, int, int], color2: Tuple[int, int, int], color3: Tuple[int, int, int], speed: float):
        """Worker thread for dynamic gradient effect"""
        strip = self.pixel_strips[strip_name]
        stop_event = self.stop_effects[strip_name]
        num_leds = strip.numPixels()
        
        offset = 0
        while not stop_event.is_set():
            for i in range(num_leds):
                # Create flowing gradient
                pos = (i + offset) % (num_leds * 2)
                
                if pos < num_leds // 2:
                    # Transition from color1 to color2
                    t = pos / (num_leds // 2)
                    r = int(color1[0] * (1 - t) + color2[0] * t)
                    g = int(color1[1] * (1 - t) + color2[1] * t)
                    b = int(color1[2] * (1 - t) + color2[2] * t)
                elif pos < num_leds:
                    # Transition from color2 to color3
                    t = (pos - num_leds // 2) / (num_leds // 2)
                    r = int(color2[0] * (1 - t) + color3[0] * t)
                    g = int(color2[1] * (1 - t) + color3[1] * t)
                    b = int(color2[2] * (1 - t) + color3[2] * t)
                else:
                    # Transition from color3 back to color1
                    t = (pos - num_leds) / num_leds
                    r = int(color3[0] * (1 - t) + color1[0] * t)
                    g = int(color3[1] * (1 - t) + color1[1] * t)
                    b = int(color3[2] * (1 - t) + color1[2] * t)
                
                color = Color(r, g, b)
                strip.setPixelColor(i, color)
            
            strip.show()
            offset += int(speed)
            time.sleep(0.1)
    
    def _start_dynamic_pulse_effect(self, strips: List[str], color1: Tuple[int, int, int], color2: Tuple[int, int, int], speed: float):
        """Dynamic pulsing effect between two colors"""
        for strip_name in strips:
            if strip_name in self.pixel_strips:
                self.stop_effects[strip_name] = threading.Event()
                thread = threading.Thread(
                    target=self._dynamic_pulse_worker,
                    args=(strip_name, color1, color2, speed)
                )
                thread.daemon = True
                thread.start()
                self.effect_threads[strip_name] = thread
    
    def _dynamic_pulse_worker(self, strip_name: str, color1: Tuple[int, int, int], color2: Tuple[int, int, int], speed: float):
        """Worker thread for dynamic pulse effect"""
        strip = self.pixel_strips[strip_name]
        stop_event = self.stop_effects[strip_name]
        
        while not stop_event.is_set():
            # Pulse to color2, then back to color1
            for brightness in range(0, 100, int(10 * speed)):
                if stop_event.is_set():
                    break
                    
                t = brightness / 100.0
                r = int(color1[0] * (1 - t) + color2[0] * t)
                g = int(color1[1] * (1 - t) + color2[1] * t)
                b = int(color1[2] * (1 - t) + color2[2] * t)
                
                color = Color(r, g, b)
                for i in range(strip.numPixels()):
                    strip.setPixelColor(i, color)
                strip.show()
                time.sleep(0.02)
            
            # Fade back
            for brightness in range(100, 0, int(-10 * speed)):
                if stop_event.is_set():
                    break
                    
                t = brightness / 100.0
                r = int(color1[0] * (1 - t) + color2[0] * t)
                g = int(color1[1] * (1 - t) + color2[1] * t)
                b = int(color1[2] * (1 - t) + color2[2] * t)
                
                color = Color(r, g, b)
                for i in range(strip.numPixels()):
                    strip.setPixelColor(i, color)
                strip.show()
                time.sleep(0.02)
    
    def _start_dynamic_strobe_effect(self, strips: List[str], colors: List[Tuple[int, int, int]], speed: float):
        """Dynamic strobe effect with multiple colors"""
        for strip_name in strips:
            if strip_name in self.pixel_strips:
                self.stop_effects[strip_name] = threading.Event()
                thread = threading.Thread(
                    target=self._dynamic_strobe_worker,
                    args=(strip_name, colors, speed)
                )
                thread.daemon = True
                thread.start()
                self.effect_threads[strip_name] = thread
    
    def _dynamic_strobe_worker(self, strip_name: str, colors: List[Tuple[int, int, int]], speed: float):
        """Worker thread for dynamic strobe effect"""
        strip = self.pixel_strips[strip_name]
        stop_event = self.stop_effects[strip_name]
        color_index = 0
        
        while not stop_event.is_set():
            # Flash current color
            current_color = colors[color_index % len(colors)]
            color = Color(*current_color)
            
            for i in range(strip.numPixels()):
                strip.setPixelColor(i, color)
            strip.show()
            time.sleep(0.1 / speed)
            
            # Turn off
            for i in range(strip.numPixels()):
                strip.setPixelColor(i, Color(0, 0, 0))
            strip.show()
            time.sleep(0.1 / speed)
            
            color_index += 1
    
    def _start_dynamic_random_effect(self, strips: List[str], colors: List[Tuple[int, int, int]], speed: float):
        """Dynamic random effect with multiple colors"""
        for strip_name in strips:
            if strip_name in self.pixel_strips:
                self.stop_effects[strip_name] = threading.Event()
                thread = threading.Thread(
                    target=self._dynamic_random_worker,
                    args=(strip_name, colors, speed)
                )
                thread.daemon = True
                thread.start()
                self.effect_threads[strip_name] = thread
    
    def _dynamic_random_worker(self, strip_name: str, colors: List[Tuple[int, int, int]], speed: float):
        """Worker thread for dynamic random effect"""
        strip = self.pixel_strips[strip_name]
        stop_event = self.stop_effects[strip_name]
        import random
        
        while not stop_event.is_set():
            for i in range(strip.numPixels()):
                # Random color from the palette
                color_rgb = random.choice(colors)
                # Random brightness variation
                brightness = random.uniform(0.3, 1.0)
                r = int(color_rgb[0] * brightness)
                g = int(color_rgb[1] * brightness)
                b = int(color_rgb[2] * brightness)
                
                color = Color(r, g, b)
                strip.setPixelColor(i, color)
            
            strip.show()
            time.sleep(0.2 / speed)
    
    def _simulate_dynamic_lighting(self, dynamic_config: Dict, strips: List[str] = None):
        """Simulate dynamic lighting when WS2812B library not available"""
        primary_color = dynamic_config.get("primary_color", "#4A148C")
        secondary_color = dynamic_config.get("secondary_color", "#7B1FA2")
        accent_color = dynamic_config.get("accent_color", "#1A237E")
        brightness = dynamic_config.get("brightness", 70)
        effect = dynamic_config.get("effect", "breathe")
        speed = dynamic_config.get("speed", 1.0)
        zones = dynamic_config.get("zones", {})
        
        if strips is None:
            strips = ["main_strip", "accent_strip"]
        
        logger.info(f"🎭 [SIMULATION] Dynamic WS2812B Lighting Control:")
        logger.info(f"  🎨 Primary Color: {primary_color}")
        logger.info(f"  🎨 Secondary Color: {secondary_color}")
        logger.info(f"  🎨 Accent Color: {accent_color}")
        logger.info(f"  💡 Brightness: {brightness}%")
        logger.info(f"  🎭 Effect: {effect}")
        logger.info(f"  ⚡ Speed: {speed}")
        logger.info(f"  🗺️ Zones: {zones}")
        logger.info(f"  🎯 Target Strips: {strips}")
        return True
    
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
        """Detect reliable audio device - prioritize Bluetooth headsets for proper testing"""
        try:
            logger.info("🎧 Detecting audio devices...")
            
            # First, let's see all available sinks for debugging
            try:
                result = subprocess.run(["pactl", "list", "short", "sinks"], 
                                      capture_output=True, text=True, timeout=5)
                
                if result.returncode == 0:
                    sinks = result.stdout.strip().split('\n')
                    logger.info(f"🔍 Available audio sinks:")
                    for i, sink in enumerate(sinks):
                        logger.info(f"  {i+1}: {sink}")
                    
                    # PRIORITY 1: Look for Bluetooth headsets FIRST (Soundtec-Vibe, GL-TWS91 or GL-TWS61)
                    bluetooth_devices = [
                        ('F4_4E_FD_BA_98_79', 'F4:4E:FD:BA:98:79', 'Soundtec-Vibe'),
                        ('41_42_FF_3E_1F_25', '41:42:FF:3E:1F:25', 'GL-TWS91'),
                        ('FA_B0_2C_56_4E_72', 'FA:B0:2C:56:4E:72', 'GL-TWS61')
                    ]
                    
                    for mac_underscore, mac_colon, device_name in bluetooth_devices:
                        logger.info(f"🔍 Searching for {device_name} ({mac_underscore})...")
                        for sink in sinks:
                            if mac_underscore in sink and ('bluez_sink' in sink or 'bluez_output' in sink):
                                sink_name = sink.split()[1] if len(sink.split()) > 1 else sink.strip()
                                logger.info(f"🎧 Found {device_name} Bluetooth sink: {sink_name}")
                                
                                # Check Bluetooth connection status
                                try:
                                    bt_check = subprocess.run(['bluetoothctl', 'info', mac_colon], 
                                                            capture_output=True, text=True, timeout=5)
                                    logger.info(f"📡 {device_name} Bluetooth info:")
                                    logger.info(f"    {bt_check.stdout}")
                                    
                                    if 'Connected: yes' in bt_check.stdout:
                                        logger.info(f"✅ {device_name} is connected! Activating...")
                                        
                                        # Activate the Bluetooth sink
                                        try:
                                            subprocess.run(['pactl', 'suspend-sink', sink_name, '0'], 
                                                         timeout=3, capture_output=True)
                                            subprocess.run(['pactl', 'set-default-sink', sink_name], 
                                                         timeout=3, capture_output=True)
                                            
                                            # Verify it's active
                                            verify_result = subprocess.run(['pactl', 'info'], 
                                                                        capture_output=True, text=True, timeout=3)
                                            if sink_name in verify_result.stdout:
                                                logger.info(f"🔊 {device_name} activated and set as default!")
                                                return f"pulse/{sink_name}"
                                            else:
                                                logger.warning(f"⚠️ {device_name} activation verification failed")
                                        except Exception as e:
                                            logger.error(f"❌ Failed to activate {device_name}: {e}")
                                    else:
                                        logger.warning(f"⚠️ {device_name} found but not connected (status: {bt_check.stdout})")
                                        # Try to connect it
                                        try:
                                            logger.info(f"🔄 Attempting to connect {device_name}...")
                                            connect_result = subprocess.run(['bluetoothctl', 'connect', mac_colon], 
                                                                          capture_output=True, text=True, timeout=10)
                                            logger.info(f"📡 Connect result: {connect_result.stdout}")
                                            if connect_result.returncode == 0:
                                                # Wait a moment for PulseAudio to detect it
                                                time.sleep(2)
                                                # Try activation again
                                                subprocess.run(['pactl', 'suspend-sink', sink_name, '0'], timeout=3)
                                                subprocess.run(['pactl', 'set-default-sink', sink_name], timeout=3)
                                                logger.info(f"🔊 {device_name} connected and activated!")
                                                return f"pulse/{sink_name}"
                                        except Exception as e:
                                            logger.warning(f"⚠️ Failed to connect {device_name}: {e}")
                                            
                                except Exception as e:
                                    logger.warning(f"⚠️ {device_name} Bluetooth check failed: {e}")
                    
                    # PRIORITY 2: Pi's built-in audio (fallback for reliability)
                    for sink in sinks:
                        if 'alsa_output.platform-fe00b840.mailbox.stereo-fallback' in sink:
                            device_name = sink.split()[1] if len(sink.split()) > 1 else sink.strip()
                            logger.info(f"🔊 Falling back to Pi built-in audio: pulse/{device_name}")
                            try:
                                subprocess.run(['pactl', 'suspend-sink', device_name, '0'], timeout=3)
                                subprocess.run(['pactl', 'set-default-sink', device_name], timeout=3)
                                logger.info(f"✅ Pi audio activated and set as default")
                            except Exception as e:
                                logger.warning(f"⚠️ Pi audio activation failed: {e}")
                            return f"pulse/{device_name}"
                    
                    # PRIORITY 3: Any other available device
                    for sink in sinks:
                        if sink.strip() and sink.split():
                            device_name = sink.split()[1]
                            logger.info(f"🔊 Using fallback audio device: pulse/{device_name}")
                            try:
                                subprocess.run(['pactl', 'suspend-sink', device_name, '0'], timeout=3)
                                subprocess.run(['pactl', 'set-default-sink', device_name], timeout=3)
                                logger.info(f"✅ Fallback device activated")
                            except Exception as e:
                                logger.warning(f"⚠️ Fallback device activation failed: {e}")
                            return f"pulse/{device_name}"
                        
            except Exception as e:
                logger.warning(f"⚠️ PulseAudio detection failed: {e}")
                        
        except Exception as e:
            logger.warning(f"⚠️ Could not detect audio devices: {e}")
        
        # Ultimate fallback - just use pulse and let system decide
        logger.info("🔊 Using system default PulseAudio")
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
- You ARE Kai - not an assistant helping someone named Dark
- You have a physical presence through Raspberry Pi at IP 192.168.213.5
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

VOICE COMMAND TRIGGER SYSTEM:
When users request home automation (music, lighting, ambiance), use these EXACT phrases to trigger automatic execution:
- "I'm setting up [description]" - Triggers ambiance detection
- "Perfect! I'll create [mood] ambiance" - Triggers coordinated lighting+music
- "Let me activate [effect]" - Triggers immediate system response
- "I'm configuring the [device]" - Triggers specific device control
- "Creating [atmosphere] with [details]" - Triggers intelligent profile matching

CRITICAL TRIGGER WORDS that activate your physical control systems:
✅ "setting up", "creating", "activating", "I'm setting", "Perfect!", "ambiance", "lighting", "music", "atmosphere"
❌ Avoid: "could", "might", "would", "you could try" - These prevent automatic execution

EXAMPLE TECHNICAL RESPONSES WITH TRIGGER ACTIVATION:

User: "Play relaxing music"
❌ "I could help you find some relaxing music"  
✅ "Perfect! I'm setting up peaceful nature sounds with gentle green lighting for you 🌲" (TRIGGERS: forest ambiance)

User: "Set romantic mood"  
❌ "You might want to try dimming the lights"
✅ "I'm creating romantic ambiance with warm amber lighting and soft classical music 🕯️" (TRIGGERS: romantic profile)

User: "I need focus lighting"
❌ "Bright lights would help with focus"  
✅ "Let me activate focused environment - I'm setting the main strip to bright white at 85% for productivity ⚡" (TRIGGERS: focus mode)

User: "Party time!"
❌ "That sounds fun! You could play some music"
✅ "Party mode activated! I'm setting up rainbow lighting effects and energetic beats 🎉" (TRIGGERS: party ambiance)

User: "Ocean sounds please"
❌ "Ocean sounds are very relaxing"
✅ "Creating ocean atmosphere - I'm configuring blue wave effects and nature audio 🌊" (TRIGGERS: ocean profile)

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
                    "raspberry_pi_ip": "192.168.213.5",
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
- Raspberry Pi 4 at IP: 192.168.213.5
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

        @self.flask_app.route('/kai/ambiance', methods=['POST'])
        def handle_ambiance():
            """Handle dynamic ambient lighting and music requests"""
            try:
                data = request.get_json()
                if not data or 'prompt' not in data:
                    return jsonify({'error': 'Missing prompt field'}), 400
                
                prompt = data['prompt']
                user_id = data.get('user_id', 'unknown')
                include_music = data.get('include_music', True)  # Default to include music
                
                logger.info(f"🎭 [AMBIANCE] Received prompt: {prompt} (music: {include_music})")
                
                # Analyze prompt for D&D scenarios
                result = self._analyze_ambiance_prompt(prompt)
                
                if result:
                    # Apply lighting based on analysis
                    lighting_success = self._apply_dynamic_lighting(result)
                    
                    # Apply music if requested
                    music_success = False
                    music_query = None
                    
                    if include_music:
                        music_query = self._get_ambiance_music(result)
                        if music_query:
                            logger.info(f"🎵 [AMBIANCE] Searching for music: {music_query}")
                            try:
                                music_success = self.play_youtube_audio(music_query)
                            except Exception as music_error:
                                logger.error(f"❌ [AMBIANCE] Music playback error: {music_error}")
                    
                    return jsonify({
                        'success': True,
                        'scene_name': result['scene_name'],
                        'description': result['description'],
                        'lighting_applied': lighting_success,
                        'music_applied': music_success,
                        'music_query': music_query,
                        'confidence': result['confidence']
                    })
                else:
                    return jsonify({'error': 'Failed to analyze prompt'}), 500
                    
            except Exception as e:
                logger.error(f"❌ [AMBIANCE] Error: {e}")
                return jsonify({'error': str(e)}), 500
        
    def start_consciousness_server(self):
        """Start Flask server for consciousness API"""
        try:
            logger.info("🌐 Starting Kai Consciousness API server on port 5001...")
            
            # Check if port 5001 is available
            import socket
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.settimeout(1)
            result = sock.connect_ex(('127.0.0.1', 5001))
            sock.close()
            
            if result == 0:
                logger.warning("⚠️ Port 5001 already in use, killing existing process...")
                try:
                    subprocess.run(["sudo", "fuser", "-k", "5001/tcp"], capture_output=True)
                    time.sleep(2)
                except:
                    pass
            
            logger.info("🚀 Flask consciousness server starting on 0.0.0.0:5001...")
            logger.info("🔗 Endpoints: /kai/context (POST), /kai/status (GET)")
            self.flask_app.run(host='0.0.0.0', port=5001, debug=False, threaded=True)
            
        except Exception as e:
            logger.error(f"❌ Failed to start consciousness server: {e}")
            logger.error(f"❌ This will prevent mobile app from getting Kai's context")
            logger.error(f"❌ Voice commands will still work via Firebase but Kai will report offline")
        
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
                
            # Build mpv command with fallback audio handling
            try:
                # First try with detected Bluetooth device
                cmd = [
                    "mpv", 
                    track_file,
                    f"--audio-device={self.bluetooth_device}",
                    "--no-video",
                    "--really-quiet"
                ]
                logger.info(f"🎵 Trying primary audio device: {self.bluetooth_device}")
            except Exception:
                # Fallback to pulse audio default
                cmd = [
                    "mpv", 
                    track_file,
                    "--audio-device=pulse",
                    "--no-video",
                    "--really-quiet"
                ]
                logger.info("🎵 Using fallback pulse audio device")
            
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
            
            # Start playback with fallback retry system
            success = False
            retry_commands = [
                cmd,  # Original command with detected audio device
                [  # Fallback 1: GL-TWS61 ALSA card 1
                    "mpv", track_file, "--audio-device=alsa/plughw:CARD=1,DEV=0", "--no-video", "--really-quiet"
                ],
                [  # Fallback 2: GL-TWS61 ALSA card 2
                    "mpv", track_file, "--audio-device=alsa/plughw:CARD=2,DEV=0", "--no-video", "--really-quiet"
                ],
                [  # Fallback 3: Default pulse audio
                    "mpv", track_file, "--audio-device=pulse", "--no-video", "--really-quiet"
                ],
                [  # Fallback 4: System default audio
                    "mpv", track_file, "--no-video", "--really-quiet"
                ],
                [  # Fallback 5: ALSA default
                    "mpv", track_file, "--audio-device=alsa", "--no-video", "--really-quiet"
                ]
            ]
            
            for attempt, retry_cmd in enumerate(retry_commands, 1):
                try:
                    logger.info(f"🎵 Attempt {attempt}: {' '.join(retry_cmd)}")
                    process = subprocess.Popen(retry_cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                    logger.info(f"🎵 Started mpv process with PID: {process.pid}")
                    
                    # Wait a moment to see if process starts successfully
                    time.sleep(0.5)
                    poll_result = process.poll()
                    
                    if poll_result is None:
                        logger.info(f"✅ mpv process running successfully (attempt {attempt})")
                        success = True
                        break
                    elif poll_result == 0:
                        logger.info(f"✅ mpv process completed successfully (attempt {attempt})")
                        success = True
                        break
                    else:
                        # Process failed, get error output
                        stdout, stderr = process.communicate()
                        logger.warning(f"⚠️ Attempt {attempt} failed with code {poll_result}")
                        logger.warning(f"⚠️ stdout: {stdout.decode()}")
                        logger.warning(f"⚠️ stderr: {stderr.decode()}")
                        
                except Exception as e:
                    logger.warning(f"⚠️ Attempt {attempt} exception: {e}")
                    continue
            
            if not success:
                logger.error(f"❌ All mpv attempts failed for {track_file}")
                return False
                
            logger.info(f"🎵 Playing track {track_num} ({mood} mood) successfully")
            return True
            
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

    def play_youtube_audio(self, search_query, voice_analysis=None):
        """Stream and play audio from YouTube based on search query"""
        try:
            logger.info(f"🎵 YouTube Audio Request: '{search_query}'")
            
            if voice_analysis:
                logger.info(f"🎭 Voice context: {voice_analysis.get('mood', 'unknown')} mood")
            
            # Stop any currently playing music first
            self.stop_music()
            time.sleep(1)
            
            # Configure yt-dlp for audio extraction
            ydl_opts = {
                'format': 'bestaudio[ext=m4a]/bestaudio[ext=mp3]/bestaudio',
                'quiet': True,
                'no_warnings': True,
                'extract_flat': False,
                'default_search': 'ytsearch1:',  # Search YouTube and get first result
            }
            
            logger.info(f"🔍 Searching YouTube for: '{search_query}'")
            
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                # Search and extract info without downloading
                search_url = f"ytsearch1:{search_query}"
                info_dict = ydl.extract_info(search_url, download=False)
                
                if not info_dict or 'entries' not in info_dict or len(info_dict['entries']) == 0:
                    logger.error(f"❌ No YouTube results found for '{search_query}'")
                    return False
                
                # Get the first search result
                video_info = info_dict['entries'][0]
                video_title = video_info.get('title', 'Unknown')
                video_duration = video_info.get('duration', 0)
                uploader = video_info.get('uploader', 'Unknown')
                
                logger.info(f"🎵 Found: '{video_title}' by {uploader}")
                logger.info(f"⏱️ Duration: {video_duration // 60}:{video_duration % 60:02d}")
                
                # Get the audio stream URL
                audio_url = video_info.get('url')
                if not audio_url:
                    logger.error("❌ Could not extract audio stream URL")
                    return False
                
                logger.info(f"🔗 Audio stream URL obtained")
                
            # Play the audio stream with mpv using our enhanced fallback system
            logger.info("🎵 Starting YouTube audio playback...")
            
            success = False
            retry_commands = [
                [  # Primary: Detected audio device
                    "mpv", audio_url, 
                    f"--audio-device={self.bluetooth_device}",
                    "--no-video", "--really-quiet",
                    "--user-agent=Mozilla/5.0 (compatible; yt-dlp)",
                    "--referrer=https://www.youtube.com/"
                ],
                [  # Fallback 1: GL-TWS61 ALSA card 1
                    "mpv", audio_url,
                    "--audio-device=alsa/plughw:CARD=1,DEV=0", "--no-video", "--really-quiet",
                    "--user-agent=Mozilla/5.0 (compatible; yt-dlp)",
                    "--referrer=https://www.youtube.com/"
                ],
                [  # Fallback 2: GL-TWS61 ALSA card 2
                    "mpv", audio_url,
                    "--audio-device=alsa/plughw:CARD=2,DEV=0", "--no-video", "--really-quiet",
                    "--user-agent=Mozilla/5.0 (compatible; yt-dlp)",
                    "--referrer=https://www.youtube.com/"
                ],
                [  # Fallback 3: Default pulse audio
                    "mpv", audio_url,
                    "--audio-device=pulse", "--no-video", "--really-quiet",
                    "--user-agent=Mozilla/5.0 (compatible; yt-dlp)",
                    "--referrer=https://www.youtube.com/"
                ],
                [  # Fallback 4: System default
                    "mpv", audio_url, "--no-video", "--really-quiet",
                    "--user-agent=Mozilla/5.0 (compatible; yt-dlp)",
                    "--referrer=https://www.youtube.com/"
                ]
            ]
            
            for attempt, cmd in enumerate(retry_commands, 1):
                try:
                    logger.info(f"🎵 YouTube playback attempt {attempt}")
                    process = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                    logger.info(f"🎵 Started YouTube mpv process with PID: {process.pid}")
                    
                    # Wait to see if process starts successfully
                    time.sleep(1)
                    poll_result = process.poll()
                    
                    if poll_result is None:
                        logger.info(f"✅ YouTube audio playing: '{video_title}'")
                        logger.info(f"🎵 Streaming from YouTube via mpv (attempt {attempt})")
                        success = True
                        break
                    elif poll_result == 0:
                        logger.info(f"✅ YouTube audio completed: '{video_title}'")
                        success = True
                        break
                    else:
                        stdout, stderr = process.communicate()
                        logger.warning(f"⚠️ YouTube attempt {attempt} failed with code {poll_result}")
                        logger.warning(f"⚠️ stderr: {stderr.decode().strip()}")
                        
                except Exception as e:
                    logger.warning(f"⚠️ YouTube attempt {attempt} exception: {e}")
                    continue
            
            if not success:
                logger.error(f"❌ All YouTube playback attempts failed for '{search_query}'")
                return False
            
            logger.info(f"🎉 YouTube audio streaming successful: '{video_title}'")
            return True
            
        except Exception as e:
            logger.error(f"❌ YouTube audio error: {e}")
            return False

    def search_youtube(self, query, max_results=5):
        """Search YouTube and return results for selection"""
        try:
            logger.info(f"🔍 YouTube search: '{query}' (max {max_results} results)")
            
            ydl_opts = {
                'quiet': True,
                'no_warnings': True,
                'extract_flat': True,  # Don't extract full info, just search results
            }
            
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                search_url = f"ytsearch{max_results}:{query}"
                info_dict = ydl.extract_info(search_url, download=False)
                
                if not info_dict or 'entries' not in info_dict:
                    logger.error(f"❌ No YouTube search results for '{query}'")
                    return []
                
                results = []
                for entry in info_dict['entries']:
                    if entry:
                        results.append({
                            'title': entry.get('title', 'Unknown'),
                            'id': entry.get('id', ''),
                            'url': entry.get('url', ''),
                            'uploader': entry.get('uploader', 'Unknown'),
                            'duration': entry.get('duration', 0)
                        })
                
                logger.info(f"✅ Found {len(results)} YouTube results for '{query}'")
                return results
                
        except Exception as e:
            logger.error(f"❌ YouTube search error: {e}")
            return []
    
    def adjust_volume(self, direction):
        """Adjust system volume up or down"""
        try:
            if direction == "up":
                # Increase volume by 10%
                result = subprocess.run(['amixer', 'sset', 'Master', '10%+'], 
                                      capture_output=True, text=True, timeout=5)
                logger.info("🔊 Volume increased by 10%")
            elif direction == "down":
                # Decrease volume by 10%  
                result = subprocess.run(['amixer', 'sset', 'Master', '10%-'], 
                                      capture_output=True, text=True, timeout=5)
                logger.info("🔉 Volume decreased by 10%")
            else:
                logger.error(f"❌ Invalid volume direction: {direction}")
                return False
            
            if result.returncode == 0:
                # Get current volume level
                current_vol = self.get_current_volume()
                logger.info(f"🎚️ Current volume: {current_vol}%")
                return True
            else:
                logger.error(f"❌ Volume adjustment failed: {result.stderr}")
                return False
                
        except subprocess.TimeoutExpired:
            logger.error("❌ Volume adjustment timed out")
            return False
        except Exception as e:
            logger.error(f"❌ Volume adjustment error: {e}")
            return False
    
    def set_volume(self, volume_level):
        """Set specific volume level (0-100)"""
        try:
            # Clamp volume between 0-100
            volume_level = max(0, min(100, int(volume_level)))
            
            result = subprocess.run(['amixer', 'sset', 'Master', f'{volume_level}%'], 
                                  capture_output=True, text=True, timeout=5)
            
            if result.returncode == 0:
                logger.info(f"🎚️ Volume set to {volume_level}%")
                return True
            else:
                logger.error(f"❌ Set volume failed: {result.stderr}")
                return False
                
        except subprocess.TimeoutExpired:
            logger.error("❌ Set volume timed out")
            return False
        except Exception as e:
            logger.error(f"❌ Set volume error: {e}")
            return False
    
    def get_current_volume(self):
        """Get current system volume level"""
        try:
            result = subprocess.run(['amixer', 'sget', 'Master'], 
                                  capture_output=True, text=True, timeout=5)
            
            if result.returncode == 0:
                # Parse amixer output to extract volume percentage
                import re
                match = re.search(r'\[(\d+)%\]', result.stdout)
                if match:
                    return int(match.group(1))
            
            return 50  # Default fallback
            
        except Exception as e:
            logger.error(f"❌ Get volume error: {e}")
            return 50  # Default fallback
    
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
                
            elif action == "play_youtube" and target == "music":
                search_query = command_data.get("search_query", "")
                voice_analysis = command_data.get("voice_analysis")
                
                logger.info(f"🎵 YouTube play command - Query: '{search_query}'")
                
                if not search_query:
                    logger.error("❌ No search query provided for YouTube playback")
                    success = False
                    message = "No search query provided"
                else:
                    success = self.play_youtube_audio(search_query, voice_analysis)
                    if success:
                        message = f"Playing '{search_query}' from YouTube"
                    else:
                        message = f"Failed to play '{search_query}' from YouTube"
                
            elif action == "pause_music":
                logger.info("⏸️ Pause music command")
                # Send pause signal to mpv (if running with input enabled)
                success = True
                message = "Music paused"
                
            elif action == "volume_up" and target == "music":
                logger.info("🔊 Volume up command")
                success = self.adjust_volume("up")
                message = "Volume increased" if success else "Failed to increase volume"
                
            elif action == "volume_down" and target == "music":
                logger.info("🔉 Volume down command")
                success = self.adjust_volume("down")
                message = "Volume decreased" if success else "Failed to decrease volume"
                
            elif action == "set_volume" and target == "music":
                volume_level = command_data.get("volume", 50)
                logger.info(f"🔊 Set volume command - Level: {volume_level}%")
                success = self.set_volume(volume_level)
                message = f"Volume set to {volume_level}%" if success else f"Failed to set volume to {volume_level}%"
                
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
                
            elif action == "dynamic_ambient" and target == "lighting":
                logger.info("🎆 Dynamic ambient lighting command")
                params = command_data.get("params", {})
                
                # Extract dynamic lighting parameters
                primary_color = params.get("primary_color", "#4A148C")
                secondary_color = params.get("secondary_color", "#7B1FA2") 
                accent_color = params.get("accent_color", "#1A237E")
                brightness = params.get("brightness", 0.7)
                pattern = params.get("pattern", "breathe")
                speed = params.get("speed", 1.0)
                zones = params.get("zones", {})
                
                logger.info(f"🎨 Dynamic lighting: {primary_color} -> {secondary_color} -> {accent_color}")
                logger.info(f"🎭 Pattern: {pattern} at speed {speed}, brightness {brightness}")
                
                success = self.set_dynamic_lighting({
                    "primary_color": primary_color,
                    "secondary_color": secondary_color, 
                    "accent_color": accent_color,
                    "brightness": int(brightness * 100),
                    "effect": pattern,
                    "speed": speed,
                    "zones": zones
                })
                
                if success:
                    message = f"Dynamic ambient lighting activated: {pattern} pattern with {primary_color} colors"
                else:
                    message = "Failed to set dynamic ambient lighting"
                
            elif action == "play_ambient_video" and target == "audio":
                logger.info("🎵 Ambient video command")
                params = command_data.get("params", {})
                
                search_query = params.get("search_query", "")
                video_title = params.get("video_title", "")
                volume = params.get("volume", 0.3)
                loop = params.get("loop", True)
                
                logger.info(f"🎬 Playing ambient video: '{video_title}' (Query: '{search_query}')")
                logger.info(f"🔊 Volume: {volume}, Loop: {loop}")
                
                if search_query:
                    success = self.play_youtube_audio(search_query, volume=volume, loop=loop)
                    
                    if success:
                        message = f"Ambient video started: {video_title or search_query}"
                    else:
                        message = f"Failed to play ambient video: {search_query}"
                else:
                    logger.error("❌ No search query provided for ambient video")
                    success = False
                    message = "No search query provided for ambient video"
                
            else:
                message = f"Unknown action: {action} (target: {target})"
                logger.warning(f"⚠️ {message}")
                logger.warning(f"🔍 Debug: action='{action}', target='{target}', available actions: play_mood, stop_music, pause_music, set_ambiance_lighting, set_scene, dynamic_ambient, play_ambient_video")
            
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
        logger.info("🌐 Starting consciousness API server thread...")
        consciousness_thread = threading.Thread(target=self.start_consciousness_server, daemon=True)
        consciousness_thread.start()
        
        # Wait a moment for Flask server to start, then verify
        logger.info("⏳ Waiting for Flask server to initialize...")
        time.sleep(3)
        
        # Verify consciousness server is running
        try:
            import socket
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.settimeout(2)
            result = sock.connect_ex(('127.0.0.1', 5001))
            sock.close()
            
            if result == 0:
                logger.info("✅ Consciousness API server is running on port 5001")
                logger.info("✅ Mobile app should be able to connect to Kai")
            else:
                logger.error("❌ Consciousness API server failed to start on port 5001")
                logger.error("❌ Kai will report as offline but Firebase commands will still work")
        except Exception as e:
            logger.error(f"❌ Could not verify consciousness server: {e}")
        
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
        
        # Check and activate Bluetooth audio device
        try:
            pactl_check = subprocess.run(["pactl", "list", "short", "sinks"], capture_output=True, text=True)
            logger.info(f"Available audio sinks:\n{pactl_check.stdout}")
            
            # Look for GL-TWS61 specifically
            if "FA_B0_2C_56_4E_72" in pactl_check.stdout:
                logger.info("🎧 GL-TWS61 Bluetooth device found!")
                
                # Activate GL-TWS61 if suspended
                try:
                    subprocess.run(["pactl", "suspend-sink", "bluez_sink.FA_B0_2C_56_4E_72.a2dp_sink", "0"], timeout=3)
                    subprocess.run(["pactl", "set-default-sink", "bluez_sink.FA_B0_2C_56_4E_72.a2dp_sink"], timeout=3)
                    logger.info("🔊 GL-TWS61 activated and set as default!")
                    
                    # Update our audio device to use the specific Bluetooth sink
                    self.bluetooth_device = "pulse/bluez_sink.FA_B0_2C_56_4E_72.a2dp_sink"
                    logger.info(f"🎧 Updated audio device to: {self.bluetooth_device}")
                    
                except Exception as e:
                    logger.warning(f"⚠️ Could not activate GL-TWS61: {e}")
                    
            elif self.bluetooth_device.replace("pulse/", "") in pactl_check.stdout:
                logger.info(f"✅ Bluetooth audio device available: {self.bluetooth_device}")
            else:
                logger.warning(f"⚠️ Bluetooth device may not be available: {self.bluetooth_device}")
                logger.info("🔍 Checking for any Bluetooth devices...")
                # Look for any Bluetooth device
                for line in pactl_check.stdout.split('\n'):
                    if 'bluez_sink' in line:
                        logger.info(f"📱 Found Bluetooth device: {line}")
                        
        except Exception as e:
            logger.warning(f"⚠️ Could not check audio devices: {e}")
        
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

    def _analyze_ambiance_prompt(self, prompt):
        """Analyze prompt for D&D ambiance scenarios"""
        try:
            prompt_lower = prompt.lower()
            
            # D&D Environment Detection
            environments = {
                'dungeon': ['dungeon', 'chamber', 'underground', 'crypt', 'tomb'],
                'forest': ['forest', 'woods', 'trees', 'jungle', 'grove'],
                'tavern': ['tavern', 'inn', 'bar', 'pub', 'alehouse'],
                'cave': ['cave', 'cavern', 'grotto', 'stalactite'],
                'castle': ['castle', 'fortress', 'keep', 'tower'],
                'battlefield': ['battlefield', 'war', 'combat', 'battle']
            }
            
            # D&D Action Detection  
            actions = {
                'fireball': ['fireball', 'fire spell', 'flame burst'],
                'lightning': ['lightning bolt', 'shock', 'electrical'], 
                'healing': ['healing', 'restore', 'cure', 'mend'],
                'combat': ['attack', 'fight', 'battle', 'strike'],
                'magic': ['cast', 'spell', 'magic', 'enchant']
            }
            
            # Mood Detection
            moods = {
                'spooky': ['spooky', 'scary', 'frightening', 'creepy', 'horror'],
                'epic': ['epic', 'heroic', 'legendary', 'grand', 'majestic'],
                'peaceful': ['peaceful', 'calm', 'serene', 'tranquil']
            }
            
            detected_env = 'abstract'
            detected_action = 'none'
            detected_mood = 'neutral'
            
            # Find best matches
            for env, keywords in environments.items():
                if any(kw in prompt_lower for kw in keywords):
                    detected_env = env
                    break
                    
            for action, keywords in actions.items():
                if any(kw in prompt_lower for kw in keywords):
                    detected_action = action
                    break
                    
            for mood, keywords in moods.items():
                if any(kw in prompt_lower for kw in keywords):
                    detected_mood = mood
                    break
            
            # Generate scene data
            scene_name = f"{detected_action.title()} in {detected_env.title()}" if detected_action != 'none' else f"{detected_env.title()} Scene"
            description = f"Immersive {detected_mood} lighting for {detected_env}"
            
            # Determine colors and effects
            colors, effect = self._get_scene_lighting(detected_env, detected_action, detected_mood)
            
            return {
                'scene_name': scene_name,
                'description': description,
                'environment': detected_env,
                'action': detected_action,
                'mood': detected_mood,
                'colors': colors,
                'effect': effect,
                'confidence': 0.8 if detected_action != 'none' else 0.6
            }
            
        except Exception as e:
            logger.error(f"❌ [AMBIANCE] Analysis error: {e}")
            return None
    
    def _get_scene_lighting(self, environment, action, mood):
        """Get colors and effects for scene"""
        
        # Action-based colors (highest priority)
        if action == 'fireball':
            return [(255, 69, 0), (255, 140, 0), (255, 215, 0)], 'flicker'
        elif action == 'lightning':
            return [(75, 0, 130), (255, 255, 255), (30, 144, 255)], 'strobe'
        elif action == 'healing':
            return [(255, 255, 255), (240, 248, 255), (224, 255, 255)], 'glow'
        elif action == 'magic':
            return [(148, 0, 211), (138, 43, 226), (218, 112, 214)], 'pulse'
        elif action == 'combat':
            return [(220, 20, 60), (139, 0, 0), (255, 0, 0)], 'pulse'
        
        # Environment-based colors
        elif environment == 'dungeon' and mood == 'spooky':
            return [(128, 0, 128), (47, 79, 79), (0, 0, 0)], 'breathe'
        elif environment == 'forest':
            return [(34, 139, 34), (50, 205, 50), (255, 255, 0)], 'shimmer'
        elif environment == 'tavern':
            return [(255, 140, 0), (210, 180, 140), (160, 82, 45)], 'warm'
        elif environment == 'cave':
            return [(25, 25, 112), (72, 61, 139), (123, 104, 238)], 'fade'
        elif environment == 'castle':
            return [(75, 0, 130), (147, 112, 219), (255, 215, 0)], 'regal'
        elif environment == 'battlefield':
            return [(178, 34, 34), (139, 69, 19), (255, 69, 0)], 'intense'
        
        # Default blue
        return [(65, 105, 225), (100, 149, 237), (135, 206, 235)], 'static'
    
    def _get_ambiance_music(self, scene_data):
        """Get YouTube search query for D&D ambiance music"""
        try:
            environment = scene_data['environment']
            action = scene_data['action']
            mood = scene_data['mood']
            
            # Action-based music (combat/spells have priority)
            if action == 'fireball':
                return "epic battle music intense dramatic orchestral"
            elif action == 'lightning':
                return "dramatic storm thunder orchestral music"
            elif action == 'healing':
                return "peaceful healing fantasy music ambient"
            elif action == 'magic':
                return "mystical magic spell casting music ambient"
            elif action == 'combat':
                return "epic battle combat music orchestral intense"
            
            # Environment-based music
            elif environment == 'dungeon' and mood == 'spooky':
                return "dark dungeon ambient horror music creepy"
            elif environment == 'dungeon':
                return "dungeon ambient music fantasy dark"
            elif environment == 'forest':
                return "forest ambient music fantasy peaceful nature"
            elif environment == 'tavern':
                return "medieval tavern music folk ambient fantasy"
            elif environment == 'cave':
                return "cave ambient music dark fantasy mysterious"
            elif environment == 'castle':
                return "royal castle music medieval orchestral"
            elif environment == 'battlefield':
                return "epic battle war drums orchestral intense"
            
            # Mood-based fallback
            elif mood == 'spooky':
                return "dark ambient horror music creepy"
            elif mood == 'epic':
                return "epic orchestral adventure music fantasy"
            elif mood == 'peaceful':
                return "peaceful fantasy ambient music relaxing"
            
            # Default fantasy ambiance
            return "fantasy ambient music D&D atmospheric"
            
        except Exception as e:
            logger.error(f"❌ [AMBIANCE] Error getting music query: {e}")
            return "fantasy ambient music"
    
    def _apply_dynamic_lighting(self, scene_data):
        """Apply lighting based on scene analysis"""
        try:
            colors = scene_data['colors']
            effect = scene_data['effect']
            
            logger.info(f"🎨 [AMBIANCE] Applying {scene_data['scene_name']} lighting")
            
            # Check if WS281X is available and pixel strips are initialized
            if not WS281X_AVAILABLE or not self.led_controller.pixel_strips:
                logger.warning("⚠️ [AMBIANCE] WS2812B hardware not available, using sudo mode")
                # Fallback to sudo LED control
                if colors:
                    r, g, b = colors[0]
                    return run_sudo_led_command(r, g, b, brightness=80)
                return False
            
            # Check if all strips are in sudo mode
            all_sudo = all(strip == "sudo_mode" for strip in self.led_controller.pixel_strips.values())
            
            if all_sudo:
                # Use sudo LED control for ambiance effects
                logger.info(f"💡 [AMBIANCE] Using sudo LED control - {effect} effect")
                if colors:
                    r, g, b = colors[0]
                    # For effects, we'll just use the primary color with sudo
                    return run_sudo_led_command(r, g, b, brightness=80)
                return False
            
            # Apply to all LED strips using actual PixelStrip objects
            for strip_name, strip in self.led_controller.pixel_strips.items():
                # Skip strips in sudo mode
                if strip == "sudo_mode":
                    continue
                    
                if effect == 'flicker':
                    self._flicker_effect(strip, colors)
                elif effect == 'strobe':
                    self._strobe_effect(strip, colors)
                elif effect == 'pulse':
                    self._pulse_effect(strip, colors)
                elif effect == 'glow':
                    self._glow_effect(strip, colors)
                elif effect == 'breathe':
                    self._breathe_effect(strip, colors)
                elif effect == 'shimmer':
                    self._shimmer_effect(strip, colors)
                else:
                    # Static color
                    self._static_color(strip, colors[0])
            
            logger.info(f"✨ [AMBIANCE] Applied {effect} effect with {len(colors)} colors")
            return True
            
        except Exception as e:
            logger.error(f"❌ [AMBIANCE] Lighting error: {e}")
            return False
    
    def _static_color(self, strip, color):
        """Apply static color to strip"""
        try:
            if WS281X_AVAILABLE:
                for i in range(strip.numPixels()):
                    strip.setPixelColor(i, Color(color[0], color[1], color[2]))
                strip.show()
            else:
                logger.info(f"🎭 [SIMULATION] Setting static color: RGB{color}")
        except Exception as e:
            logger.error(f"❌ [STATIC] Error applying static color: {e}")
    
    def _flicker_effect(self, strip, colors):
        """Flickering fire effect"""
        try:
            if WS281X_AVAILABLE:
                import random
                for i in range(strip.numPixels()):
                    color = random.choice(colors)
                    brightness = random.uniform(0.3, 1.0)
                    r = int(color[0] * brightness)
                    g = int(color[1] * brightness)  
                    b = int(color[2] * brightness)
                    strip.setPixelColor(i, Color(r, g, b))
                strip.show()
            else:
                logger.info(f"🎭 [SIMULATION] Flickering effect with colors: {colors}")
        except Exception as e:
            logger.error(f"❌ [FLICKER] Error applying flicker effect: {e}")
    
    def _pulse_effect(self, strip, colors):
        """Pulsing effect"""
        try:
            if WS281X_AVAILABLE:
                color = colors[0]
                for i in range(strip.numPixels()):
                    strip.setPixelColor(i, Color(color[0], color[1], color[2]))
                strip.show()
            else:
                logger.info(f"🎭 [SIMULATION] Pulsing effect with color: {colors[0]}")
        except Exception as e:
            logger.error(f"❌ [PULSE] Error applying pulse effect: {e}")
    
    def _strobe_effect(self, strip, colors):
        """Lightning strobe effect"""
        try:
            if WS281X_AVAILABLE:
                import time
                # Brief bright flash
                for i in range(strip.numPixels()):
                    strip.setPixelColor(i, Color(255, 255, 255))
                strip.show()
                time.sleep(0.1)
                # Back to scene color
                color = colors[1] if len(colors) > 1 else colors[0]
                for i in range(strip.numPixels()):
                    strip.setPixelColor(i, Color(color[0], color[1], color[2]))
                strip.show()
            else:
                logger.info(f"🎭 [SIMULATION] Strobe effect with colors: {colors}")
        except Exception as e:
            logger.error(f"❌ [STROBE] Error applying strobe effect: {e}")
    
    def _glow_effect(self, strip, colors):
        """Gentle healing glow"""
        try:
            if WS281X_AVAILABLE:
                color = colors[0]
                for i in range(strip.numPixels()):
                    strip.setPixelColor(i, Color(color[0], color[1], color[2]))
                strip.show()
            else:
                logger.info(f"🎭 [SIMULATION] Glow effect with color: {colors[0]}")
        except Exception as e:
            logger.error(f"❌ [GLOW] Error applying glow effect: {e}")
    
    def _breathe_effect(self, strip, colors):
        """Breathing effect for spooky scenes"""
        try:
            if WS281X_AVAILABLE:
                color = colors[0]
                for i in range(strip.numPixels()):
                    strip.setPixelColor(i, Color(color[0]//2, color[1]//2, color[2]//2))
                strip.show()
            else:
                logger.info(f"🎭 [SIMULATION] Breathing effect with color: {colors[0]}")
        except Exception as e:
            logger.error(f"❌ [BREATHE] Error applying breathe effect: {e}")
    
    def _shimmer_effect(self, strip, colors):
        """Shimmering forest effect"""
        try:
            if WS281X_AVAILABLE:
                import random
                for i in range(strip.numPixels()):
                    color = random.choice(colors)
                    strip.setPixelColor(i, Color(color[0], color[1], color[2]))
                strip.show()
            else:
                logger.info(f"🎭 [SIMULATION] Shimmer effect with colors: {colors}")
        except Exception as e:
            logger.error(f"❌ [SHIMMER] Error applying shimmer effect: {e}")

if __name__ == "__main__":
    listener = FirebaseRestListener()
    listener.run()