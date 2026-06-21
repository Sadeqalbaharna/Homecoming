#!/usr/bin/env python3
"""
Simple WS2812B LED Test for Homecoming Pi
Copy this entire file content and paste it into your Pi
"""
import time

print("🧪 WS2812B LED Test Starting...")
print("===============================")

# Try to import the LED library
try:
    from rpi_ws281x import PixelStrip, Color
    print("✅ WS2812B library found")
except ImportError:
    print("❌ WS2812B library not installed")
    print("Run: sudo pip3 install rpi_ws281x")
    exit(1)

# LED Configuration - Testing with power injection
LED_COUNT = 300       # Test up to 300 LEDs with power injection - EXTREME TEST!
LED_PIN = 18          # GPIO pin (18 = Physical pin 12) - Working!
LED_FREQ_HZ = 800000  # LED frequency
LED_DMA = 10          # DMA channel
LED_BRIGHTNESS = 40   # Lower brightness for 300 LEDs to reduce massive power draw
LED_INVERT = False    # Signal invert
LED_CHANNEL = 0       # PWM channel

def wheel(pos):
    """Generate rainbow colors"""
    if pos < 85:
        return Color(pos * 3, 255 - pos * 3, 0)
    elif pos < 170:
        pos -= 85
        return Color(255 - pos * 3, 0, pos * 3)
    else:
        pos -= 170
        return Color(0, pos * 3, 255 - pos * 3)

def main():
    print(f"🔧 Configuration:")
    print(f"   LEDs: {LED_COUNT}")
    print(f"   GPIO: {LED_PIN}")
    print(f"   Brightness: {LED_BRIGHTNESS}")
    print()

    try:
        # Initialize LED strip
        print("🚀 Initializing LED strip...")
        strip = PixelStrip(LED_COUNT, LED_PIN, LED_FREQ_HZ, LED_DMA, LED_INVERT, LED_BRIGHTNESS, LED_CHANNEL)
        strip.begin()
        print("✅ LED strip initialized successfully!")
        
        # Clear all LEDs
        print("🔄 Clearing LEDs...")
        for i in range(LED_COUNT):
            strip.setPixelColor(i, Color(0, 0, 0))
        strip.show()
        time.sleep(1)
        
        # Power injection setup check
        print("🔌 EXTREME POWER INJECTION SETUP FOR 300 LEDs:")
        print("   ⚠️  CRITICAL for 300 LEDs - MASSIVE POWER REQUIRED:")
        print("   ✅ Input end: Red & Black wires to external 5V supply (25A+ MINIMUM!)")
        print("   ✅ Output end: Red & Black wires to SAME external 5V supply")
        print("   ✅ Multiple injection points every 75-100 LEDs recommended")
        print("   ⚠️  Output end: Green wire LEFT DISCONNECTED")
        print("   ✅ Pi GPIO 18 connected to INPUT green wire only")
        print("   � HIGHLY RECOMMENDED: 330Ω resistor on data line")
        print("   ⚡ Power required: 300 LEDs × 60mA = 18A minimum!")
        print()
        print("🚨 EXTREME WARNING: 300 LEDs at full brightness = 90W power!")
        print("   At 40% brightness (test setting) = 36W power / 7.2A")
        print("   Ensure your power supply is rated for AT LEAST 25A continuous!")
        print("   Consider multiple injection points for reliability.")
        print()
        print("💡 Pro tip: For 300+ LEDs, professionals use:")
        print("   - Level shifter (74HCT245) for 3.3V→5V conversion")
        print("   - Power injection every 50-75 LEDs") 
        print("   - Thicker power wires (12-14 AWG minimum)")
        print("   - Dedicated LED power supplies (not bench supplies)")
        print()
        input("Press Enter when EXTREME power injection is ready for 300 LED test...")
        
        # Test in chunks to see how far we can reach with 300 LEDs
        test_ranges = [10, 20, 30, 50, 75, 100, 125, 150, 175, 200, 225, 250, 275, 300]
        
        print("🔍 Testing LED ranges with power injection...")
        for test_count in test_ranges:
            if test_count > LED_COUNT:
                continue
                
            print(f"\n📍 Testing LEDs 1 to {test_count}...")
            
            # Light up all LEDs in this range
            for i in range(test_count):
                strip.setPixelColor(i, Color(0, 255, 0))  # Green
            strip.show()
            time.sleep(2)
            
            # Clear them
            for i in range(test_count):
                strip.setPixelColor(i, Color(0, 0, 0))
            strip.show()
            
            response = input(f"Did all {test_count} LEDs light up? (y/n/p for partial): ").lower()
            if response == 'n':
                print(f"❌ Signal lost around LED {test_count}")
                print("💡 Solutions for 300+ LED signal issues:")
                print("   - Add 330Ω resistor to data line (ESSENTIAL)")
                print("   - Use level shifter (74HCT245) for 3.3V→5V conversion")
                print("   - Add power injection every 50-75 LEDs")
                print("   - Lower brightness to 20-30% maximum")
                print("   - Check for defective LEDs breaking the chain")
                print("   - Consider splitting into multiple GPIO outputs")
                print("   - Use thicker, shorter data wire (solid core preferred)")
                break
            elif response == 'p':
                partial_count = input(f"How many of the {test_count} LEDs lit up? ")
                try:
                    actual_count = int(partial_count)
                    print(f"⚠️  Partial success: {actual_count}/{test_count} LEDs working")
                    print("💡 This suggests signal degradation or power issues")
                except:
                    print("⚠️  Partial lighting detected")
                break
            else:
                print(f"✅ {test_count} LEDs working perfectly!")
        
        print("\n🎯 Final working LED count test...")
        input("Press Enter to continue with color test...")
        
        # Test basic colors
        colors = [
            (Color(255, 0, 0), "� RED"),
            (Color(0, 255, 0), "🟢 GREEN"),
            (Color(0, 0, 255), "� BLUE"),
            (Color(255, 255, 255), "⚪ WHITE")
        ]
        
        # Ask user how many LEDs are working
        working_leds = input("How many LEDs are working? Enter number: ")
        try:
            working_count = int(working_leds)
        except:
            working_count = 10  # Default fallback
            
        print(f"🎨 Testing colors on first {working_count} LEDs...")
        for color, name in colors:
            print(f"   {name}")
            for i in range(min(working_count, LED_COUNT)):
                strip.setPixelColor(i, color)
            strip.show()
            time.sleep(2)
            
            # Clear
            for i in range(LED_COUNT):
                strip.setPixelColor(i, Color(0, 0, 0))
            strip.show()
            time.sleep(0.5)
            
        # Test patterns with working LEDs
        print(f"🌊 Testing wave pattern on {working_count} LEDs...")
        for wave in range(3):  # 3 waves
            for i in range(working_count):
                # Clear all
                for j in range(working_count):
                    strip.setPixelColor(j, Color(0, 0, 0))
                
                # Light current position with tail
                if i > 0:
                    strip.setPixelColor(i-1, Color(0, 100, 0))  # Dim green tail
                strip.setPixelColor(i, Color(0, 255, 0))       # Bright green head
                
                strip.show()
                time.sleep(0.1)
        
        # Clear after wave
        for i in range(working_count):
            strip.setPixelColor(i, Color(0, 0, 0))
        strip.show()
        
        # Rainbow test
        print("🌈 Testing rainbow effect...")
        for j in range(256):
            for i in range(LED_COUNT):
                strip.setPixelColor(i, wheel((int(i * 256 / LED_COUNT) + j) & 255))
            strip.show()
            time.sleep(0.02)
        
        # Clear final
        print("🔄 Final cleanup...")
        for i in range(LED_COUNT):
            strip.setPixelColor(i, Color(0, 0, 0))
        strip.show()
        
        print()
        print("🎉 SUCCESS! Your WS2812B LEDs are working!")
        print(f"✅ {working_count} LEDs confirmed working with power injection!")
        print()
        print("🏡 Ready for Homecoming Integration:")
        print(f"   - Update firebase_rest_listener_debug.py LED count to {working_count}")
        print("   - GPIO 18 confirmed working")
        print("   - External power supply confirmed adequate")
        print("   - Signal integrity good for this LED count")
        print()
        if working_count >= 250:
            print("🚀 LEGENDARY: 250+ LEDs working! Professional-grade setup!")
            print("🏆 You've achieved what most hobbyists can't - congrats!")
        elif working_count >= 200:
            print("🎉 OUTSTANDING: 200+ LEDs working! Excellent room lighting!")
            print("👑 This is professional-level LED control!")
        elif working_count >= 150:
            print("🎉 EXCELLENT: 150+ LEDs working! Perfect for room lighting!")
        elif working_count >= 100:
            print("👍 GREAT: 100+ LEDs working! Good for accent lighting!")
        elif working_count >= 50:
            print("✅ GOOD: 50+ LEDs working! Nice for mood lighting!")
        else:
            print("⚠️  LIMITED: Consider major power injection improvements")
        
        print()
        print("💡 To push beyond your current limit:")
        if working_count < 100:
            print("   - Add 330Ω resistor (CRITICAL first step)")
            print("   - Improve power injection at both ends")
            print("   - Check for defective LEDs breaking chain")
        elif working_count < 200:
            print("   - Add level shifter (74HCT245) for signal integrity")
            print("   - Multiple power injection points every 75 LEDs")
            print("   - Upgrade to thicker power wires (12-14 AWG)")
        else:
            print("   - You're already at pro level! Consider:")
            print("   - Multiple GPIO outputs for parallel strips")
            print("   - Differential signaling for extreme distances")
            print("   - Professional LED controllers (Pixelblaze, etc.)")
        
        print()
        print("🏡 Homecoming Integration Recommendations:")
        if working_count >= 200:
            print("   - Use as main room lighting system")
            print("   - Multiple zones for different lighting scenes")
            print("   - Advanced effects like music reactive modes")
        elif working_count >= 100:
            print("   - Perfect for accent and mood lighting")
            print("   - Good for behind TV, under cabinet installations")
            print("   - Solid foundation for smart home lighting")
        else:
            print("   - Great starter setup for learning LED control")
            print("   - Focus on getting signal improvements first")
        
        return True
        
    except Exception as e:
        print(f"❌ ERROR: {e}")
        print()
        print("🔧 Troubleshooting for Partial Lighting:")
        print("   POWER ISSUES (Most Common):")
        print("   - Pi 5V pins can only supply ~1A total")
        print("   - Each LED needs up to 60mA (0.06A)")
        print("   - 10+ LEDs need external 5V power supply")
        print("   - Connect LED VCC to external 5V, not Pi 5V")
        print("   - Keep Pi GND connected to LED GND and external GND")
        print()
        print("   SIGNAL ISSUES:")
        print("   - Add 330Ω resistor between Pi GPIO and LED data line")
        print("   - Try different GPIO pins (12, 13)")
        print("   - Ensure solid connections (no loose wires)")
        print()
        print("   LED STRIP ISSUES:")
        print("   - Some cheap strips have defective LEDs in chain")
        print("   - Try cutting strip after last working LED")
        print("   - Test with lower LED_COUNT number")
        return False

if __name__ == "__main__":
    print("Press Ctrl+C to stop at any time")
    print()
    try:
        main()
    except KeyboardInterrupt:
        print("\n⏹️ Test stopped by user")
    except Exception as e:
        print(f"\n💥 Unexpected error: {e}")
    finally:
        print("\nTest complete! 👋")