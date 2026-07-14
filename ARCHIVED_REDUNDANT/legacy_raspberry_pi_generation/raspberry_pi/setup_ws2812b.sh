#!/bin/bash
# WS2812B Setup Script for Raspberry Pi

echo "🌈 Setting up WS2812B LED Strip Control"
echo "========================================"

# Update system
echo "📦 Updating system packages..."
sudo apt update

# Install required system packages
echo "🔧 Installing system dependencies..."
sudo apt install -y python3-dev python3-pip scons swig

# Install Python packages in virtual environment
echo "🐍 Installing Python packages..."
source ~/kai-home-venv/bin/activate

# Install rpi_ws281x library (the main WS2812B control library)
pip install rpi_ws281x

# Install additional useful packages
pip install colorsys

echo ""
echo "✅ WS2812B setup complete!"
echo ""
echo "🔌 Hardware Connection:"
echo "   WS2812B Data Pin → GPIO 18 (Physical Pin 12)"
echo "   WS2812B 5V Power → External 5V power supply"  
echo "   WS2812B Ground → Pi Ground (Physical Pin 6) + Power supply ground"
echo ""
echo "⚠️  IMPORTANT: WS2812B strips need 5V power supply!"
echo "   Don't power 300 LEDs from Pi's 5V pin - use external adapter"
echo ""
echo "🚀 Test with: python3 kai_home_ws2812b_service.py"