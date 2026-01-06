#!/bin/bash
# Quick start script to test Bluetooth speaker on Pi

echo "🎵 Bluetooth Speaker Test Script"
echo "================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if running on Pi
if ! grep -q "Raspberry Pi" /proc/device-tree/model 2>/dev/null; then
    echo -e "${YELLOW}⚠️  Warning: Not running on a Raspberry Pi${NC}"
    echo "This script is designed for Pi. Some features may not work."
    echo ""
fi

# Check Bluetooth
echo "1️⃣  Checking Bluetooth connection..."
if pactl list short sinks | grep -q "bluez_output"; then
    echo -e "${GREEN}✅ Bluetooth device found${NC}"
    pactl list short sinks | grep bluez_output
else
    echo -e "${RED}❌ No Bluetooth device found${NC}"
    echo "Please pair your TG-129C speaker first:"
    echo "  bluetoothctl"
    echo "  pair 39:3E:58:14:40:4A"
    exit 1
fi

echo ""
echo "2️⃣  Checking required tools..."

# Check mpv
if ! command -v mpv &> /dev/null; then
    echo -e "${RED}❌ mpv not found${NC}"
    echo "Install with: sudo apt-get install mpv"
    exit 1
else
    echo -e "${GREEN}✅ mpv installed${NC}"
fi

# Check yt-dlp
if ! command -v yt-dlp &> /dev/null; then
    echo -e "${RED}❌ yt-dlp not found${NC}"
    echo "Install with: pip install yt-dlp"
    exit 1
else
    echo -e "${GREEN}✅ yt-dlp installed${NC}"
fi

echo ""
echo "3️⃣  Running STEP 1 initialization test..."
sudo python3 fixtures_v2/tests/test_step1_initialization.py

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ STEP 1 test failed${NC}"
    exit 1
fi

echo ""
echo "4️⃣  Running Bluetooth speaker test..."
echo "   (This will play music on your TG-129C speaker)"
echo ""

sudo python3 test_bluetooth_speaker.py --simple

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ All tests passed!${NC}"
    echo ""
    echo "Your Bluetooth speaker is working with the new modular system!"
else
    echo -e "${RED}❌ Audio tests failed${NC}"
    echo "Check your speaker connection and try again"
fi
