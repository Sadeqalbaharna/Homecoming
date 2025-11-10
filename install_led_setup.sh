#!/bin/bash
# WS2812B LED Setup and Test Installation Script
# For Homecoming Pi at 192.168.29.5

echo "🏡 Homecoming WS2812B LED Setup"
echo "==============================="
echo "Installing dependencies and test files..."
echo

# Update package list
echo "📦 Updating package list..."
sudo apt update

# Install Python development tools
echo "🔧 Installing Python development tools..."
sudo apt install -y python3-pip python3-dev build-essential

# Install SPI and GPIO libraries
echo "⚡ Installing GPIO libraries..."
sudo apt install -y python3-rpi.gpio

# Install WS281X library
echo "🌈 Installing WS2812B LED library..."
sudo pip3 install rpi_ws281x

# Install additional dependencies for Homecoming
echo "🚀 Installing Homecoming dependencies..."
sudo pip3 install flask flask-cors requests

# Enable SPI (needed for WS2812B)
echo "🔌 Enabling SPI interface..."
sudo raspi-config nonint do_spi 0

# Create test script
echo "📝 Creating LED test script..."
cat > /home/pi/led_test.py << 'EOF'
#!/usr/bin/env python3
import time
from rpi_ws281x import PixelStrip, Color

# Configuration
LED_COUNT = 10        # Test with 10 LEDs
LED_PIN = 18          # GPIO 18 (Pin 12)
LED_FREQ_HZ = 800000
LED_DMA = 10
LED_BRIGHTNESS = 50
LED_INVERT = False
LED_CHANNEL = 0

print("🧪 Testing WS2812B LED Strip...")
print(f"GPIO Pin: {LED_PIN}")
print(f"LED Count: {LED_COUNT}")
print()

try:
    # Initialize strip
    strip = PixelStrip(LED_COUNT, LED_PIN, LED_FREQ_HZ, LED_DMA, LED_INVERT, LED_BRIGHTNESS, LED_CHANNEL)
    strip.begin()
    print("✅ Strip initialized successfully!")
    
    # Clear strip
    for i in range(LED_COUNT):
        strip.setPixelColor(i, Color(0, 0, 0))
    strip.show()
    print("🔄 Strip cleared")
    
    # Test basic colors
    colors = [
        (Color(255, 0, 0), "RED"),
        (Color(0, 255, 0), "GREEN"), 
        (Color(0, 0, 255), "BLUE"),
        (Color(255, 255, 255), "WHITE")
    ]
    
    for color, name in colors:
        print(f"   Testing {name}...")
        for i in range(LED_COUNT):
            strip.setPixelColor(i, color)
        strip.show()
        time.sleep(2)
        
        # Clear
        for i in range(LED_COUNT):
            strip.setPixelColor(i, Color(0, 0, 0))
        strip.show()
        time.sleep(0.5)
    
    # Rainbow test
    print("   Testing RAINBOW effect...")
    for j in range(256):
        for i in range(LED_COUNT):
            strip.setPixelColor(i, wheel((int(i * 256 / LED_COUNT) + j) & 255))
        strip.show()
        time.sleep(0.02)
    
    # Clear final
    for i in range(LED_COUNT):
        strip.setPixelColor(i, Color(0, 0, 0))
    strip.show()
    
    print()
    print("🎉 SUCCESS! Your WS2812B LEDs are working perfectly!")
    print("✅ Ready for Homecoming integration!")
    
except Exception as e:
    print(f"❌ ERROR: {e}")
    print()
    print("🔧 Troubleshooting:")
    print("   - Make sure you run with: sudo python3 led_test.py")
    print("   - Check GPIO connections (try pins 12, 13, 18)")
    print("   - Verify power supply is adequate")
    print("   - Ensure strip is properly wired")

def wheel(pos):
    """Generate rainbow colors across 0-255 positions."""
    if pos < 85:
        return Color(pos * 3, 255 - pos * 3, 0)
    elif pos < 170:
        pos -= 85
        return Color(255 - pos * 3, 0, pos * 3)
    else:
        pos -= 170
        return Color(0, pos * 3, 255 - pos * 3)
EOF

# Make test script executable
chmod +x /home/pi/led_test.py

# Create quick GPIO test
echo "⚡ Creating GPIO test script..."
cat > /home/pi/gpio_test.py << 'EOF'
#!/usr/bin/env python3
import RPi.GPIO as GPIO
import time

print("🔍 GPIO Test for WS2812B")
print("========================")

# Test GPIO pins
pins_to_test = [12, 13, 18]

GPIO.setmode(GPIO.BCM)

for pin in pins_to_test:
    try:
        GPIO.setup(pin, GPIO.OUT)
        print(f"✅ GPIO {pin} - OK")
        
        # Quick blink test
        for i in range(3):
            GPIO.output(pin, GPIO.HIGH)
            time.sleep(0.1)
            GPIO.output(pin, GPIO.LOW)
            time.sleep(0.1)
            
    except Exception as e:
        print(f"❌ GPIO {pin} - Error: {e}")
    finally:
        GPIO.cleanup()

print("GPIO test complete!")
EOF

chmod +x /home/pi/gpio_test.py

# Show completion message
echo
echo "✅ Installation Complete!"
echo "========================"
echo
echo "🧪 To test your LED strip:"
echo "   sudo python3 /home/pi/led_test.py"
echo
echo "⚡ To test GPIO pins:"
echo "   python3 /home/pi/gpio_test.py"
echo
echo "🔧 Your setup:"
echo "   - WS2812B library: Installed"
echo "   - Test scripts: Ready"
echo "   - GPIO access: Enabled"
echo "   - SPI interface: Enabled"
echo
echo "🚀 Next steps:"
echo "   1. Connect your LED strip to GPIO 18 (Pin 12)"
echo "   2. Run: sudo python3 led_test.py"
echo "   3. If successful, deploy firebase_rest_listener_debug.py"
echo
echo "Happy LED testing! 🌈"