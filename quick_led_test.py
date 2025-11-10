#!/usr/bin/env python3
import time
from rpi_ws281x import PixelStrip, Color

# Configuration - adjust if needed
LED_COUNT = 10        # Test with just 10 LEDs first
LED_PIN = 18          # Your data pin (try 18, 12, or 13)
LED_FREQ_HZ = 800000
LED_DMA = 10
LED_BRIGHTNESS = 50   # Start with low brightness
LED_INVERT = False
LED_CHANNEL = 0

print("🧪 Testing WS2812B LED Strip...")

try:
    # Initialize strip
    strip = PixelStrip(LED_COUNT, LED_PIN, LED_FREQ_HZ, LED_DMA, LED_INVERT, LED_BRIGHTNESS, LED_CHANNEL)
    strip.begin()
    print("✅ Strip initialized on GPIO", LED_PIN)
    
    # Test colors
    colors = [Color(255, 0, 0), Color(0, 255, 0), Color(0, 0, 255)]  # Red, Green, Blue
    color_names = ["RED", "GREEN", "BLUE"]
    
    for i, (color, name) in enumerate(zip(colors, color_names)):
        print(f"Testing {name}...")
        for j in range(LED_COUNT):
            strip.setPixelColor(j, color)
        strip.show()
        time.sleep(2)
        
        # Clear
        for j in range(LED_COUNT):
            strip.setPixelColor(j, Color(0, 0, 0))
        strip.show()
        time.sleep(0.5)
    
    print("🎉 Test completed! Your LEDs are working!")
    
except Exception as e:
    print(f"❌ Error: {e}")
    print("💡 Try different GPIO pins: 12, 13, or run with sudo")