#!/usr/bin/env python3
"""
LED Test using gpiozero - more robust GPIO handling
"""
from gpiozero import LED
import time

print("=" * 70)
print("LED HARDWARE TEST (using gpiozero)")
print("=" * 70)
print("")

try:
    # Initialize LEDs
    print("Initializing GPIO pins...")
    blue_led = LED(17)
    yellow_led = LED(22)
    red_led = LED(27)
    
    # Turn all off
    blue_led.off()
    yellow_led.off()
    red_led.off()
    print("✅ GPIO initialized")
    print("")
    
    # Test GPIO 17 (BLUE)
    print("TEST 1: GPIO 17 (BLUE LED)")
    print("-" * 70)
    print("Turning ON...")
    blue_led.on()
    print("✅ BLUE LED should be ON - Check now!")
    time.sleep(3)
    print("Turning OFF...")
    blue_led.off()
    time.sleep(1)
    print("")
    
    # Test GPIO 22 (YELLOW)
    print("TEST 2: GPIO 22 (YELLOW LED)")
    print("-" * 70)
    print("Turning ON...")
    yellow_led.on()
    print("✅ YELLOW LED should be ON - Check now!")
    time.sleep(3)
    print("Turning OFF...")
    yellow_led.off()
    time.sleep(1)
    print("")
    
    # Test GPIO 27 (RED)
    print("TEST 3: GPIO 27 (RED LED)")
    print("-" * 70)
    print("Turning ON...")
    red_led.on()
    print("✅ RED LED should be ON - Check now!")
    time.sleep(3)
    print("Turning OFF...")
    red_led.off()
    time.sleep(1)
    print("")
    
    # Blink test
    print("TEST 4: Blink sequence (BLUE → YELLOW → RED)")
    print("-" * 70)
    for i in range(3):
        print(f"Sequence {i+1}...")
        
        # BLUE
        blue_led.on()
        time.sleep(0.5)
        blue_led.off()
        
        # YELLOW
        yellow_led.on()
        time.sleep(0.5)
        yellow_led.off()
        
        # RED
        red_led.on()
        time.sleep(0.5)
        red_led.off()
    
    print("")
    print("=" * 70)
    print("✅ ALL TESTS COMPLETE")
    print("=" * 70)
    print("")
    print("Summary:")
    print("  ✅ TEST 1: BLUE (GPIO 17)")
    print("  ✅ TEST 2: YELLOW (GPIO 22)")
    print("  ✅ TEST 3: RED (GPIO 27)")
    print("  ✅ TEST 4: Blink sequence")
    print("")
    print("If you observed all LEDs lighting up as described,")
    print("then the LED hardware is working correctly!")
    print("")
    
except Exception as e:
    print(f"❌ ERROR: {e}")
    import traceback
    traceback.print_exc()

finally:
    try:
        blue_led.close()
        yellow_led.close()
        red_led.close()
        print("GPIO cleaned up.")
    except:
        pass
