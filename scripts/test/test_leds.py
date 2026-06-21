#!/usr/bin/env python3
"""
LED Test - Check GPIO pins 17, 22, 27
"""
import RPi.GPIO as GPIO
import time

print("=" * 70)
print("LED HARDWARE TEST")
print("=" * 70)

try:
    GPIO.setmode(GPIO.BCM)
    GPIO.setwarnings(False)
    
    # Setup pins
    GPIO.setup(17, GPIO.OUT)
    GPIO.setup(22, GPIO.OUT)
    GPIO.setup(27, GPIO.OUT)
    
    # Turn all off
    GPIO.output(17, 0)
    GPIO.output(22, 0)
    GPIO.output(27, 0)
    print("✅ GPIO initialized")
    print("")
    
    # Test GPIO 17 (BLUE)
    print("TEST 1: GPIO 17 (BLUE LED)")
    print("-" * 70)
    print("Turning ON...")
    GPIO.output(17, 1)
    time.sleep(2)
    print("✅ LED should be BLUE - Check now!")
    time.sleep(2)
    print("Turning OFF...")
    GPIO.output(17, 0)
    print("")
    
    # Test GPIO 22 (YELLOW)
    print("TEST 2: GPIO 22 (YELLOW LED)")
    print("-" * 70)
    print("Turning ON...")
    GPIO.output(22, 1)
    time.sleep(2)
    print("✅ LED should be YELLOW - Check now!")
    time.sleep(2)
    print("Turning OFF...")
    GPIO.output(22, 0)
    print("")
    
    # Test GPIO 27 (RED)
    print("TEST 3: GPIO 27 (RED LED)")
    print("-" * 70)
    print("Turning ON...")
    GPIO.output(27, 1)
    time.sleep(2)
    print("✅ LED should be RED - Check now!")
    time.sleep(2)
    print("Turning OFF...")
    GPIO.output(27, 0)
    print("")
    
    # Blink test
    print("TEST 4: Blink sequence")
    print("-" * 70)
    for i in range(3):
        print(f"Blink {i+1}...")
        GPIO.output(17, 1)
        GPIO.output(22, 0)
        GPIO.output(27, 0)
        time.sleep(0.5)
        
        GPIO.output(17, 0)
        GPIO.output(22, 1)
        GPIO.output(27, 0)
        time.sleep(0.5)
        
        GPIO.output(17, 0)
        GPIO.output(22, 0)
        GPIO.output(27, 1)
        time.sleep(0.5)
    
    # Turn all off
    GPIO.output(17, 0)
    GPIO.output(22, 0)
    GPIO.output(27, 0)
    
    print("")
    print("=" * 70)
    print("✅ ALL TESTS COMPLETE")
    print("=" * 70)
    print("")
    print("If you saw:")
    print("  - BLUE LED light up in TEST 1")
    print("  - YELLOW LED light up in TEST 2")
    print("  - RED LED light up in TEST 3")
    print("  - All three blinking in sequence in TEST 4")
    print("")
    print("Then LEDs are working correctly!")
    print("")
    
    GPIO.cleanup()
    
except Exception as e:
    print(f"❌ ERROR: {e}")
    import traceback
    traceback.print_exc()
    try:
        GPIO.cleanup()
    except:
        pass
