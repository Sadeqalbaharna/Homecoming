#!/usr/bin/env python3
"""
WS2812B Multiple Strip Hardware Test Script
Quick hardware verification for Homecoming Pi LED setup
"""

import time
import sys
import logging

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

try:
    from rpi_ws281x import PixelStrip, Color
    WS281X_AVAILABLE = True
    logger.info("✅ rpi_ws281x library found")
except ImportError:
    WS281X_AVAILABLE = False
    logger.error("❌ rpi_ws281x library not installed")
    print("Install with: sudo pip3 install rpi_ws281x")
    sys.exit(1)

class LedTester:
    def __init__(self):
        # Test configuration - matches your firebase_rest_listener_debug.py
        self.strips = {
            "main": {
                "led_count": 150,
                "gpio_pin": 18,
                "led_freq_hz": 800000,
                "led_dma": 10,
                "led_brightness": 100,  # Start with lower brightness for testing
                "led_invert": False,
                "led_channel": 0,
            },
            "accent": {
                "led_count": 60,
                "gpio_pin": 13,
                "led_freq_hz": 800000,
                "led_dma": 11,
                "led_brightness": 80,
                "led_invert": False,
                "led_channel": 1,
            },
            "ambient": {
                "led_count": 30,
                "gpio_pin": 12,
                "led_freq_hz": 800000,
                "led_dma": 12,
                "led_brightness": 60,
                "led_invert": False,
                "led_channel": 0,
            }
        }
        
        self.pixel_strips = {}
        self.initialize_strips()
    
    def initialize_strips(self):
        """Initialize all LED strips for testing"""
        print("\n🔧 Initializing LED strips...")
        
        for strip_name, config in self.strips.items():
            try:
                print(f"   Initializing {strip_name} strip (GPIO {config['gpio_pin']})...")
                
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
                
                print(f"   ✅ {strip_name}: {config['led_count']} LEDs on GPIO {config['gpio_pin']}")
                
            except Exception as e:
                print(f"   ❌ Failed to initialize {strip_name}: {e}")
    
    def clear_all(self):
        """Turn off all LEDs"""
        print("\n🔄 Clearing all strips...")
        for strip_name, strip in self.pixel_strips.items():
            for i in range(strip.numPixels()):
                strip.setPixelColor(i, Color(0, 0, 0))
            strip.show()
        print("   All LEDs cleared")
    
    def test_individual_strips(self):
        """Test each strip individually"""
        print("\n🧪 Testing individual strips...")
        
        colors = [
            ("Red", Color(255, 0, 0)),
            ("Green", Color(0, 255, 0)),
            ("Blue", Color(0, 0, 255))
        ]
        
        for strip_name, strip in self.pixel_strips.items():
            print(f"\n   Testing {strip_name} strip:")
            
            for color_name, color in colors:
                print(f"      {color_name}... ", end="", flush=True)
                
                # Set all LEDs to color
                for i in range(strip.numPixels()):
                    strip.setPixelColor(i, color)
                strip.show()
                
                time.sleep(1)
                print("✓")
                
                # Clear
                for i in range(strip.numPixels()):
                    strip.setPixelColor(i, Color(0, 0, 0))
                strip.show()
                time.sleep(0.5)
    
    def test_running_light(self):
        """Test running light effect on all strips"""
        print("\n🏃 Testing running light effect...")
        
        colors = [Color(255, 0, 0), Color(0, 255, 0), Color(0, 0, 255)]
        
        for i in range(10):  # 10 cycles
            for strip_name, strip in self.pixel_strips.items():
                # Clear strip
                for j in range(strip.numPixels()):
                    strip.setPixelColor(j, Color(0, 0, 0))
                
                # Set moving pixel
                color_index = i % len(colors)
                pixel_pos = i % strip.numPixels()
                strip.setPixelColor(pixel_pos, colors[color_index])
                strip.show()
            
            time.sleep(0.1)
        
        self.clear_all()
    
    def test_synchronized_effects(self):
        """Test synchronized effects across all strips"""
        print("\n🎭 Testing synchronized effects...")
        
        # Synchronized color change
        colors = [
            ("Red", Color(255, 0, 0)),
            ("Green", Color(0, 255, 0)),
            ("Blue", Color(0, 0, 255)),
            ("White", Color(255, 255, 255)),
            ("Purple", Color(128, 0, 128)),
            ("Orange", Color(255, 165, 0))
        ]
        
        for color_name, color in colors:
            print(f"   All strips: {color_name}")
            
            for strip_name, strip in self.pixel_strips.items():
                for i in range(strip.numPixels()):
                    strip.setPixelColor(i, color)
                strip.show()
            
            time.sleep(1)
        
        self.clear_all()
    
    def test_brightness_levels(self):
        """Test different brightness levels"""
        print("\n💡 Testing brightness levels...")
        
        # Test with white color at different brightness
        brightness_levels = [25, 50, 75, 100]
        
        for brightness in brightness_levels:
            print(f"   Brightness: {brightness}%")
            
            # Calculate RGB values for brightness
            rgb_value = int(255 * brightness / 100)
            color = Color(rgb_value, rgb_value, rgb_value)
            
            for strip_name, strip in self.pixel_strips.items():
                for i in range(strip.numPixels()):
                    strip.setPixelColor(i, color)
                strip.show()
            
            time.sleep(2)
        
        self.clear_all()
    
    def run_full_test(self):
        """Run complete hardware test suite"""
        print("🚀 Starting WS2812B Hardware Test Suite")
        print("=" * 50)
        
        if not self.pixel_strips:
            print("❌ No strips initialized. Check connections and try again.")
            return False
        
        try:
            self.clear_all()
            time.sleep(1)
            
            self.test_individual_strips()
            time.sleep(1)
            
            self.test_running_light()
            time.sleep(1)
            
            self.test_synchronized_effects()
            time.sleep(1)
            
            self.test_brightness_levels()
            
            print("\n🎉 Hardware test completed successfully!")
            print("All strips are working correctly.")
            return True
            
        except KeyboardInterrupt:
            print("\n⏹️  Test interrupted by user")
            self.clear_all()
            return False
        except Exception as e:
            print(f"\n❌ Test failed: {e}")
            self.clear_all()
            return False

def main():
    print("WS2812B Multiple Strip Hardware Tester")
    print("For Homecoming Pi LED Setup")
    print("=" * 40)
    
    if not WS281X_AVAILABLE:
        return
    
    try:
        tester = LedTester()
        success = tester.run_full_test()
        
        if success:
            print("\n✅ All hardware tests passed!")
            print("Your LED setup is ready for Homecoming Kai!")
        else:
            print("\n⚠️  Some tests failed. Check connections.")
            
    except Exception as e:
        print(f"\n❌ Failed to run tests: {e}")
    
    finally:
        print("\nTest complete. Goodbye! 👋")

if __name__ == "__main__":
    main()