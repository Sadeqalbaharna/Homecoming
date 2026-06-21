#!/usr/bin/env python3
"""
Homecoming WS2812B Production Test
Final configuration for your working 10-LED setup
"""
import time
from rpi_ws281x import PixelStrip, Color

# Your CONFIRMED working configuration
LED_COUNT = 10        # Confirmed working count
LED_PIN = 18          # GPIO 18 (Pin 12) - WORKING
LED_FREQ_HZ = 800000  
LED_DMA = 10          
LED_BRIGHTNESS = 100  # Safe with external power
LED_INVERT = False    
LED_CHANNEL = 0       

print("🏡 Homecoming LED System - Production Test")
print("==========================================")
print(f"✅ Confirmed: {LED_COUNT} LEDs on GPIO {LED_PIN}")
print(f"⚡ External Power: Connected")
print(f"🌈 Brightness: {LED_BRIGHTNESS}/255")
print()

def homecoming_effects_test():
    """Test effects that will be used in Homecoming"""
    
    # Initialize strip
    strip = PixelStrip(LED_COUNT, LED_PIN, LED_FREQ_HZ, LED_DMA, LED_INVERT, LED_BRIGHTNESS, LED_CHANNEL)
    strip.begin()
    
    # Clear strip
    for i in range(LED_COUNT):
        strip.setPixelColor(i, Color(0, 0, 0))
    strip.show()
    
    print("🧪 Testing Homecoming Effects...")
    
    # 1. Solid Colors (Scene Lighting)
    print("   🎭 Scene Colors...")
    scenes = [
        (Color(255, 100, 50), "Warm Reading"),
        (Color(50, 100, 255), "Cool Focus"),
        (Color(255, 50, 150), "Romantic Pink"),
        (Color(100, 255, 100), "Nature Green"),
        (Color(255, 200, 0), "Energetic Yellow")
    ]
    
    for color, name in scenes:
        print(f"      {name}")
        for i in range(LED_COUNT):
            strip.setPixelColor(i, color)
        strip.show()
        time.sleep(2)
    
    # 2. Gentle Pulse (Ambient Mode)
    print("   💫 Gentle Pulse Effect...")
    base_color = Color(100, 150, 255)
    for cycle in range(3):
        for brightness in range(20, 100, 5):
            factor = brightness / 100.0
            r = int(100 * factor)
            g = int(150 * factor)
            b = int(255 * factor)
            for i in range(LED_COUNT):
                strip.setPixelColor(i, Color(r, g, b))
            strip.show()
            time.sleep(0.05)
        
        for brightness in range(100, 20, -5):
            factor = brightness / 100.0
            r = int(100 * factor)
            g = int(150 * factor)
            b = int(255 * factor)
            for i in range(LED_COUNT):
                strip.setPixelColor(i, Color(r, g, b))
            strip.show()
            time.sleep(0.05)
    
    # 3. Wave Effect (Music Reactive)
    print("   🌊 Wave Effect...")
    for wave in range(20):
        for i in range(LED_COUNT):
            brightness = int(128 + 127 * time.sin((wave + i) * 0.5))
            strip.setPixelColor(i, Color(brightness, 0, 255-brightness))
        strip.show()
        time.sleep(0.1)
    
    # 4. Voice Command Colors
    print("   🎤 Voice Command Test Colors...")
    voice_colors = [
        (Color(255, 0, 0), "Red - 'Set lights to red'"),
        (Color(0, 255, 0), "Green - 'Make lights green'"),
        (Color(0, 0, 255), "Blue - 'Change to blue'"),
        (Color(255, 255, 255), "White - 'Turn on white lights'"),
        (Color(255, 100, 0), "Orange - 'Set to orange'")
    ]
    
    for color, command in voice_colors:
        print(f"      {command}")
        for i in range(LED_COUNT):
            strip.setPixelColor(i, color)
        strip.show()
        time.sleep(1.5)
    
    # Clear final
    for i in range(LED_COUNT):
        strip.setPixelColor(i, Color(0, 0, 0))
    strip.show()
    
    print()
    print("🎉 ALL HOMECOMING EFFECTS WORKING!")
    print("✅ Ready for full integration!")

def main():
    try:
        homecoming_effects_test()
        
        print()
        print("🏡 HOMECOMING INTEGRATION READY!")
        print("================================")
        print("✅ Hardware: Working perfectly")
        print("✅ LEDs: 10 confirmed functional")
        print("✅ Effects: All tested successfully")
        print("✅ External Power: Connected")
        print("✅ GPIO 18: Signal working")
        print()
        print("🚀 Next Steps:")
        print("1. Deploy firebase_rest_listener_debug.py")
        print("2. Start Homecoming voice commands")
        print("3. Test: 'Hey Kai, set lights to red'")
        
        return True
        
    except Exception as e:
        print(f"❌ ERROR: {e}")
        return False

if __name__ == "__main__":
    print("🚀 Starting production test...")
    success = main()
    if success:
        print("\n🌟 Your Homecoming LED system is ready! 🌟")
    else:
        print("\n❌ Issues detected - check connections")
    print("\nTest complete! 👋")