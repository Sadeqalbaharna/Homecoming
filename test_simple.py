#!/usr/bin/env python3
"""
Simple WS2812B LED Strip Test
Quick test for your current hardware setup
"""

import time
import sys

print("🧪 WS2812B LED Strip Hardware Test")
print("=" * 40)

# Try to import the WS281X library
try:
    from rpi_ws281x import PixelStrip, Color
    print("✅ rpi_ws281x library found")
except ImportError:
    print("❌ rpi_ws281x library not installed")
    print("Install with: sudo pip3 install rpi_ws281x")
    sys.exit(1)

# LED strip configuration - adjust these based on your setup
LED_COUNT = 10        # Start with just 10 LEDs for testing
LED_PIN = 18          # GPIO pin (try 18 first, then 12, 13 if needed)
LED_FREQ_HZ = 800000  # LED signal frequency in hertz (800kHz)
LED_DMA = 10          # DMA channel to use for generating signal
LED_BRIGHTNESS = 50   # Set to 0 for darkest and 255 for brightest (start low!)
LED_INVERT = False    # True to invert the signal
LED_CHANNEL = 0       # PWM channel

def test_basic_connection():
    """Test basic LED strip connection"""
    print(f"\n🔧 Testing LED strip on GPIO {LED_PIN}...")
    
    try:
        # Create PixelStrip object
        strip = PixelStrip(LED_COUNT, LED_PIN, LED_FREQ_HZ, LED_DMA, LED_INVERT, LED_BRIGHTNESS, LED_CHANNEL)
        
        # Initialize the library
        strip.begin()
        print("✅ Strip initialized successfully")
        
        return strip
        
    except Exception as e:
        print(f"❌ Failed to initialize strip: {e}")
        print("💡 Try different GPIO pins: 12, 13, or 18")
        return None

def clear_strip(strip):
    """Turn off all LEDs"""
    for i in range(strip.numPixels()):
        strip.setPixelColor(i, Color(0, 0, 0))
    strip.show()

def test_colors(strip):
    """Test basic colors"""
    print("\n🌈 Testing basic colors...")
    
    colors = [
        ("Red", Color(255, 0, 0)),
        ("Green", Color(0, 255, 0)), 
        ("Blue", Color(0, 0, 255)),
        ("White", Color(255, 255, 255)),
        ("Yellow", Color(255, 255, 0)),
        ("Purple", Color(255, 0, 255)),
        ("Cyan", Color(0, 255, 255))
    ]
    
    for color_name, color in colors:
        print(f"   Testing {color_name}... ", end="", flush=True)
        
        # Set all LEDs to this color
        for i in range(strip.numPixels()):
            strip.setPixelColor(i, color)
        strip.show()
        
        time.sleep(1)
        print("✓")
        
        # Clear strip
        clear_strip(strip)
        time.sleep(0.3)

def test_individual_leds(strip):
    """Test each LED individually"""
    print(f"\n🔍 Testing individual LEDs (1 to {LED_COUNT})...")
    
    for i in range(strip.numPixels()):
        print(f"   LED {i+1}... ", end="", flush=True)
        
        # Light up only this LED
        strip.setPixelColor(i, Color(0, 255, 0))  # Green
        strip.show()
        time.sleep(0.5)
        
        # Turn it off
        strip.setPixelColor(i, Color(0, 0, 0))
        strip.show()
        time.sleep(0.2)
        print("✓")

def test_brightness_levels(strip):
    """Test different brightness levels"""
    print("\n💡 Testing brightness levels...")
    
    brightness_levels = [25, 50, 75, 100]
    
    for brightness in brightness_levels:
        print(f"   Brightness {brightness}%... ", end="", flush=True)
        
        # Calculate color intensity
        intensity = int(255 * brightness / 100)
        
        # Set all LEDs to white at this brightness
        for i in range(strip.numPixels()):
            strip.setPixelColor(i, Color(intensity, intensity, intensity))
        strip.show()
        
        time.sleep(1)
        print("✓")
        
        # Clear
        clear_strip(strip)
        time.sleep(0.3)

def test_running_light(strip):
    """Test running light effect"""
    print("\n🏃 Testing running light effect...")
    
    colors = [Color(255, 0, 0), Color(0, 255, 0), Color(0, 0, 255)]
    
    for cycle in range(3):  # 3 cycles
        for i in range(strip.numPixels()):
            # Clear strip
            clear_strip(strip)
            
            # Light up current position
            color_index = cycle % len(colors)
            strip.setPixelColor(i, colors[color_index])
            strip.show()
            
            time.sleep(0.1)
    
    clear_strip(strip)

def main():
    """Main test function"""
    
    # Test strip initialization
    strip = test_basic_connection()
    if not strip:
        print("\n❌ Cannot initialize LED strip")
        print("🔧 Troubleshooting tips:")
        print("   - Check if running with sudo: sudo python3 test_simple.py")
        print("   - Verify GPIO pin connection (try pins 12, 13, 18)")
        print("   - Check if strip is powered properly")
        print("   - Ensure rpi_ws281x library is installed")
        return False
    
    try:
        print(f"✅ Strip ready: {LED_COUNT} LEDs on GPIO {LED_PIN}")
        
        # Clear strip first
        clear_strip(strip)
        print("🔄 Strip cleared")
        
        # Run tests
        test_colors(strip)
        test_individual_leds(strip)
        test_brightness_levels(strip)
        test_running_light(strip)
        
        print("\n🎉 All tests completed successfully!")
        print("✅ Your LED strip is working correctly!")
        return True
        
    except KeyboardInterrupt:
        print("\n⏹️  Tests stopped by user")
        clear_strip(strip)
        return False
    except Exception as e:
        print(f"\n❌ Test error: {e}")
        clear_strip(strip)
        return False
    finally:
        # Always clear the strip when done
        if strip:
            clear_strip(strip)

if __name__ == "__main__":
    print("Starting LED test...")
    print("Press Ctrl+C to stop at any time")
    print()
    
    success = main()
    
    if success:
        print("\n✅ SUCCESS: Your WS2812B setup is working!")
        print("🚀 Ready for Homecoming integration!")
    else:
        print("\n⚠️  Some issues detected. Check connections.")
    
    print("\nTest complete. 👋")