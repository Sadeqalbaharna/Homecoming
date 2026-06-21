#!/bin/bash
# Deploy Firebase listener to Pi
# Run this from your development machine

PI_IP="192.168.1.74"  # Update with your Pi's IP
PI_USER="pi"

echo "🚀 Deploying Firebase command listener to Pi..."

# Copy the Firebase listener script
scp raspberry_pi/firebase_command_listener.py $PI_USER@$PI_IP:/home/pi/raspberry_pi/

echo "✅ Firebase listener deployed!"
echo ""
echo "📋 On your Pi, run these commands:"
echo "   cd /home/pi/raspberry_pi"
echo "   pip3 install --user firebase-admin"  
echo "   python3 firebase_command_listener.py"
echo ""
echo "🔧 This will start listening for Firebase commands from your mobile app!"