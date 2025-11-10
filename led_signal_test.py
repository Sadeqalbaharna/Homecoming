#!/usr/bin/env python3
"""
Enhanced WS2812B Test with Signal Diagnostics
Helps identify and work around defective LEDs
"""
import time

try:
    from rpi_ws281x import PixelStrip, Color
    print("✅ WS2812B library found")
except ImportError:
    print("❌ WS2812B library not installed")
    exit(1)

# Configuration for testing more LEDs
LED_COUNT = 150       # Test your full strip length
LED_PIN = 18          # Working GPIO pin
LED_FREQ_HZ = 800000
LED_DMA = 10
LED_BRIGHTNESS = 80   # Slightly lower for signal integrity
LED_INVERT = False
LED_CHANNEL = 0

def test_signal_strength():
    """Test different signal parameters to improve reach"""
    print("🔍 Testing Signal Configurations...")
    
    # Try different frequencies
    frequencies = [400000, 800000, 1600000]  # Lower freq sometimes helps
    
    for freq in frequencies:
        print(f"\n📡 Testing frequency: {freq}Hz")
        try:
            strip = PixelStrip(LED_COUNT, LED_PIN, freq, LED_DMA, LED_INVERT, LED_BRIGHTNESS, LED_CHANNEL)
            strip.begin()
            
            # Clear all
            for i in range(LED_COUNT):
                strip.setPixelColor(i, Color(0, 0, 0))
            strip.show()
            
            # Test how far signal reaches
            working_leds = 0
            for i in range(0, min(50, LED_COUNT), 5):  # Test every 5th LED
                strip.setPixelColor(i, Color(255, 0, 0))  # Red
                strip.show()
                time.sleep(0.5)
                
                response = input(f"Did LED {i+1} light up? (y/n): ").lower()
                if response == 'y':
                    working_leds = i + 1
                    strip.setPixelColor(i, Color(0, 0, 0))  # Clear
                    strip.show()
                else:
                    print(f"Signal lost at LED {i+1}")
                    break
            
            print(f"✅ With {freq}Hz: {working_leds} LEDs working")
            
        except Exception as e:
            print(f"❌ Error with {freq}Hz: {e}")

def test_bypass_defective():
    """Test if we can work around defective LEDs"""
    print("\n🔄 Testing Defective LED Bypass...")
    
    strip = PixelStrip(LED_COUNT, LED_PIN, LED_FREQ_HZ, LED_DMA, LED_INVERT, LED_BRIGHTNESS, LED_CHANNEL)
    strip.begin()
    
    # Clear all
    for i in range(LED_COUNT):
        strip.setPixelColor(i, Color(0, 0, 0))
    strip.show()
    
    # Try lighting LEDs beyond the break point
    test_positions = [15, 20, 25, 30, 40, 50]
    
    for pos in test_positions:
        if pos < LED_COUNT:
            print(f"   Testing LED {pos}...")
            strip.setPixelColor(pos, Color(0, 255, 0))  # Green
            strip.show()
            time.sleep(1)
            strip.setPixelColor(pos, Color(0, 0, 0))
            strip.show()

def test_lower_brightness():
    """Test if lower brightness helps signal reach further"""
    print("\n💡 Testing Lower Brightness for Better Signal...")
    
    brightness_levels = [20, 40, 60, 80]
    
    for brightness in brightness_levels:
        print(f"   Testing brightness: {brightness}")
        
        strip = PixelStrip(LED_COUNT, LED_PIN, LED_FREQ_HZ, LED_DMA, LED_INVERT, brightness, LED_CHANNEL)
        strip.begin()
        
        # Test first 20 LEDs
        for i in range(20):
            strip.setPixelColor(i, Color(255, 255, 255))  # White
        strip.show()
        
        response = input(f"How many LEDs lit with brightness {brightness}? ")
        try:
            count = int(response)
            print(f"✅ Brightness {brightness}: {count} LEDs")
        except:
            print("Invalid input")
        
        # Clear
        for i in range(LED_COUNT):
            strip.setPixelColor(i, Color(0, 0, 0))
        strip.show()
        time.sleep(0.5)

def main():
    print("🧪 WS2812B Signal Diagnostics")
    print("=============================")
    print("Goal: Get all LEDs working!")
    print()
    
    print("Current status: 10 LEDs working, rest not responding")
    print("This usually means LED #11 is defective and breaking the chain")
    print()
    
    # Run tests
    test_signal_strength()
    test_bypass_defective()
    test_lower_brightness()
    
    print("\n🔧 SOLUTIONS TO TRY:")
    print("="*50)
    print("1. ADD 330Ω RESISTOR:")
    print("   - Connect between Pi GPIO 18 and LED data wire")
    print("   - Improves signal integrity")
    print()
    print("2. SHORTER WIRES:")
    print("   - Keep data wire under 1 meter if possible")
    print("   - Use good quality wire (not breadboard jumpers)")
    print()
    print("3. POWER INJECTION:")
    print("   - Add 5V power every 30-50 LEDs")
    print("   - Connect 5V+ and GND at multiple points")
    print()
    print("4. CUT AND RECONNECT:")
    print("   - Cut strip after LED 10")
    print("   - Reconnect data wire to LED 12 or 13")
    print("   - This bypasses the defective LED")
    print()
    print("5. LEVEL SHIFTER (Advanced):")
    print("   - Use 3.3V→5V level shifter chip")
    print("   - Converts Pi's 3.3V signals to 5V")
    print()
    
    print("Try adding the 330Ω resistor first - that fixes 80% of cases!")

if __name__ == "__main__":
    main()