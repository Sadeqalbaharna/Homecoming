"""
LED output driver - controls WS2812B RGB LED strips
"""

import logging
from typing import Any, Dict, Optional
import asyncio
import subprocess

from ..core.driver_base import OutputDriver, DriverConfig

logger = logging.getLogger(__name__)


class LEDDriver(OutputDriver):
    """
    Control WS2812B RGB LED strips via rpi-ws281x library.
    Supports multiple strips and effects.
    """
    
    def __init__(self, config: DriverConfig):
        super().__init__(config)
        
        # Extract configuration
        self.gpio_pin = config.params.get('gpio_pin', 18)
        self.led_count = config.params.get('led_count', 300)
        self.brightness = config.params.get('brightness', 200)
        self.freq_hz = config.params.get('freq_hz', 800000)
        
        self.strip = None
        self._current_color = (0, 0, 0)
        self._current_effect = None
        self._effect_task = None
    
    async def initialize(self) -> bool:
        """Initialize LED strip"""
        try:
            # Try to import rpi_ws281x
            try:
                from rpi_ws281x import PixelStrip, Color
                self.PixelStrip = PixelStrip
                self.Color = Color
                has_library = True
            except ImportError:
                self.logger.warning("⚠️ rpi_ws281x not available - will use simulation mode")
                has_library = False
            
            if has_library:
                self.strip = self.PixelStrip(
                    self.led_count,
                    self.gpio_pin,
                    800000,
                    10,
                    False,
                    self.brightness,
                    0
                )
                self.strip.begin()
                self.logger.info(f"✅ LED strip initialized: {self.led_count} LEDs on GPIO {self.gpio_pin}")
            else:
                self.logger.info(f"🔄 LED strip simulated: {self.led_count} LEDs on GPIO {self.gpio_pin}")
            
            return True
        except Exception as e:
            self.logger.error(f"❌ LED initialization failed: {e}")
            return False
    
    async def activate(self, params: Dict[str, Any]) -> bool:
        """
        Activate LED strip with color and effect.
        
        Params:
        - color: (R, G, B) tuple, 0-255
        - brightness: 0-255 (optional)
        - effect: "static", "pulse", "strobe", "flicker", "shimmer", "fade", "breathe", "warm"
        - duration_ms: How long to run effect
        """
        try:
            color = params.get('color', (255, 255, 255))
            brightness = params.get('brightness', self.brightness)
            effect = params.get('effect', 'static')
            duration_ms = params.get('duration_ms')
            
            if not isinstance(color, tuple) or len(color) != 3:
                self.logger.error("❌ Invalid color format, need (R, G, B)")
                return False
            
            self.logger.info(f"💡 LED activate: color={color}, effect={effect}, brightness={brightness}")
            
            self._current_color = color
            self._current_effect = effect
            
            # Cancel previous effect task if running
            if self._effect_task:
                self._effect_task.cancel()
            
            # Apply static color
            if self.strip:
                color_obj = self.Color(color[0], color[1], color[2])
                for i in range(self.led_count):
                    self.strip.setPixelColor(i, color_obj)
                self.strip.show()
            
            # Run effect if specified
            if effect != 'static':
                self._effect_task = asyncio.create_task(
                    self._run_effect(effect, color, duration_ms)
                )
            
            self._active = True
            return True
            
        except Exception as e:
            self.logger.error(f"❌ LED activation error: {e}")
            return False
    
    async def deactivate(self) -> bool:
        """Turn off LEDs"""
        try:
            if self._effect_task:
                self._effect_task.cancel()
            
            if self.strip:
                for i in range(self.led_count):
                    self.strip.setPixelColor(i, self.Color(0, 0, 0))
                self.strip.show()
            
            self._active = False
            self.logger.info("⏹️ LEDs turned off")
            return True
            
        except Exception as e:
            self.logger.error(f"❌ LED deactivation error: {e}")
            return False
    
    async def is_ready(self) -> bool:
        """Check if LED driver is ready"""
        return self.strip is not None or True  # Always true in simulation mode
    
    async def _run_effect(self, effect: str, color: tuple, duration_ms: Optional[int] = None):
        """Run LED effect animation"""
        try:
            if effect == 'pulse':
                await self._pulse(color, duration_ms)
            elif effect == 'strobe':
                await self._strobe(color, duration_ms)
            elif effect == 'flicker':
                await self._flicker(color, duration_ms)
            elif effect == 'shimmer':
                await self._shimmer(color, duration_ms)
            elif effect == 'fade':
                await self._fade(color, duration_ms)
            elif effect == 'breathe':
                await self._breathe(color, duration_ms)
            elif effect == 'warm':
                await self._warm(color, duration_ms)
        except asyncio.CancelledError:
            self.logger.debug(f"Effect {effect} cancelled")
        except Exception as e:
            self.logger.error(f"❌ Effect error: {e}")
    
    async def _pulse(self, color: tuple, duration_ms: Optional[int] = None):
        """Pulsing effect"""
        import time as sync_time
        start = sync_time.time()
        
        while True:
            elapsed = (sync_time.time() - start) * 1000
            if duration_ms and elapsed > duration_ms:
                break
            
            # Pulse between 0 and full brightness
            brightness_factor = (sync_time.sin(elapsed / 500) + 1) / 2
            
            if self.strip:
                color_obj = self.Color(
                    int(color[0] * brightness_factor),
                    int(color[1] * brightness_factor),
                    int(color[2] * brightness_factor)
                )
                for i in range(self.led_count):
                    self.strip.setPixelColor(i, color_obj)
                self.strip.show()
            
            await asyncio.sleep(0.05)
    
    async def _strobe(self, color: tuple, duration_ms: Optional[int] = None):
        """Strobe/flashing effect"""
        import time as sync_time
        start = sync_time.time()
        
        while True:
            elapsed = (sync_time.time() - start) * 1000
            if duration_ms and elapsed > duration_ms:
                break
            
            # Strobe on/off
            flash_on = (int(elapsed / 100) % 2) == 0
            
            if self.strip:
                if flash_on:
                    color_obj = self.Color(color[0], color[1], color[2])
                else:
                    color_obj = self.Color(0, 0, 0)
                
                for i in range(self.led_count):
                    self.strip.setPixelColor(i, color_obj)
                self.strip.show()
            
            await asyncio.sleep(0.05)
    
    async def _flicker(self, color: tuple, duration_ms: Optional[int] = None):
        """Flickering effect (like fire)"""
        import random
        import time as sync_time
        start = sync_time.time()
        
        while True:
            elapsed = (sync_time.time() - start) * 1000
            if duration_ms and elapsed > duration_ms:
                break
            
            if self.strip:
                for i in range(self.led_count):
                    brightness_factor = random.uniform(0.6, 1.0)
                    color_obj = self.Color(
                        int(color[0] * brightness_factor),
                        int(color[1] * brightness_factor),
                        int(color[2] * brightness_factor)
                    )
                    self.strip.setPixelColor(i, color_obj)
                self.strip.show()
            
            await asyncio.sleep(0.1)
    
    async def _shimmer(self, color: tuple, duration_ms: Optional[int] = None):
        """Shimmer effect"""
        import random
        import time as sync_time
        start = sync_time.time()
        
        while True:
            elapsed = (sync_time.time() - start) * 1000
            if duration_ms and elapsed > duration_ms:
                break
            
            if self.strip:
                for i in range(self.led_count):
                    # Random variation per LED
                    brightness_factor = random.uniform(0.7, 1.0)
                    color_obj = self.Color(
                        int(color[0] * brightness_factor),
                        int(color[1] * brightness_factor),
                        int(color[2] * brightness_factor)
                    )
                    self.strip.setPixelColor(i, color_obj)
                self.strip.show()
            
            await asyncio.sleep(0.15)
    
    async def _fade(self, color: tuple, duration_ms: Optional[int] = None):
        """Fade in/out effect"""
        import time as sync_time
        start = sync_time.time()
        
        while True:
            elapsed = (sync_time.time() - start) * 1000
            if duration_ms and elapsed > duration_ms:
                break
            
            # Cycle brightness 0->1->0
            brightness_factor = abs(sync_time.sin(elapsed / 1000))
            
            if self.strip:
                color_obj = self.Color(
                    int(color[0] * brightness_factor),
                    int(color[1] * brightness_factor),
                    int(color[2] * brightness_factor)
                )
                for i in range(self.led_count):
                    self.strip.setPixelColor(i, color_obj)
                self.strip.show()
            
            await asyncio.sleep(0.05)
    
    async def _breathe(self, color: tuple, duration_ms: Optional[int] = None):
        """Breathing effect (slow pulse)"""
        import time as sync_time
        start = sync_time.time()
        
        while True:
            elapsed = (sync_time.time() - start) * 1000
            if duration_ms and elapsed > duration_ms:
                break
            
            brightness_factor = (sync_time.sin(elapsed / 2000) + 1) / 2
            
            if self.strip:
                color_obj = self.Color(
                    int(color[0] * brightness_factor),
                    int(color[1] * brightness_factor),
                    int(color[2] * brightness_factor)
                )
                for i in range(self.led_count):
                    self.strip.setPixelColor(i, color_obj)
                self.strip.show()
            
            await asyncio.sleep(0.05)
    
    async def _warm(self, color: tuple, duration_ms: Optional[int] = None):
        """Warm/cozy lighting (static with slight variation)"""
        import time as sync_time
        start = sync_time.time()
        
        while True:
            elapsed = (sync_time.time() - start) * 1000
            if duration_ms and elapsed > duration_ms:
                break
            
            # Very subtle variation
            brightness_factor = 0.95 + 0.05 * sync_time.sin(elapsed / 3000)
            
            if self.strip:
                color_obj = self.Color(
                    int(color[0] * brightness_factor),
                    int(color[1] * brightness_factor),
                    int(color[2] * brightness_factor)
                )
                for i in range(self.led_count):
                    self.strip.setPixelColor(i, color_obj)
                self.strip.show()
            
            await asyncio.sleep(0.1)
