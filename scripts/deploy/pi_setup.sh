#!/bin/bash
# V1 Pi Setup Script - Run on Raspberry Pi
# Usage: curl https://raw.github.com/.../pi_setup.sh | bash

set -e

echo "=========================================="
echo "  KAI V1 - Raspberry Pi Setup"
echo "=========================================="
echo ""

# Session 1: Update & Install
echo "📦 Session 1: System setup..."
sudo apt update
sudo apt upgrade -y

sudo apt install -y \
  python3-dev \
  python3-pip \
  alsa-utils \
  espeak-ng \
  git \
  libopenjp2-7 \
  libtiff5 \
  libjasper1 \
  libjasper-dev

echo "✓ Packages installed"

# Session 2: Python packages
echo ""
echo "🐍 Installing Python packages..."
pip3 install --upgrade pip
pip3 install firebase-admin openai RPi.GPIO Adafruit-NeoPixel

echo "✓ Python packages installed"

# Session 3: Audio setup
echo ""
echo "🎤 Audio device setup..."
arecord -l
echo ""
read -p "Enter USB device number (e.g., 1): " USB_DEVICE

# Create ALSA config
echo "defaults.pcm.!card $USB_DEVICE
defaults.ctl.!card $USB_DEVICE" | sudo tee /etc/asound.conf

echo "✓ Audio device set to card $USB_DEVICE"

# Session 4: GPIO & LED
echo ""
echo "💡 Testing GPIO..."
python3 << 'EOF'
try:
    import RPi.GPIO as GPIO
    GPIO.setmode(GPIO.BCM)
    GPIO.setup(23, GPIO.OUT)
    GPIO.output(23, GPIO.HIGH)
    print("✓ GPIO 23 HIGH (button ready)")
    GPIO.output(23, GPIO.LOW)
    GPIO.cleanup()
except Exception as e:
    print(f"⚠️ GPIO test failed: {e}")
EOF

# Session 5: NFC & Systemd
echo ""
echo "📍 NFC reader check..."
lsusb | grep -i nfc || echo "⚠️ NFC reader not detected (not plugged in yet)"

echo ""
echo "=========================================="
echo "✓ Setup Complete!"
echo "=========================================="
echo ""
echo "Next steps:"
echo "  1. Deploy kai_table_v1_core.py to /home/pi/kai/"
echo "  2. Add Firebase service account JSON"
echo "  3. Set OPENAI_API_KEY environment variable"
echo "  4. Run: python3 /home/pi/kai/kai_table_v1_core.py"
echo ""
