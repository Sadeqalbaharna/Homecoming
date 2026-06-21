#!/bin/bash
# Firebase Listener Starter Script for Raspberry Pi
# Run this on your Pi to start the intelligent ambiance system

echo "🚀 Starting Firebase REST Listener with Intelligent Ambiance..."

# Navigate to home directory
cd /home/pi

# Stop any existing listener
echo "🛑 Stopping existing listeners..."
sudo pkill -f firebase_rest_listener_debug.py

# Start the enhanced listener in background
echo "🎯 Starting enhanced listener..."
nohup python3 firebase_rest_listener_debug.py > firebase_listener.log 2>&1 &

# Get the process ID
LISTENER_PID=$!
echo "✅ Firebase listener started with PID: $LISTENER_PID"

# Show log output
echo "📊 Monitoring logs (Press Ctrl+C to stop monitoring, listener will keep running):"
sleep 2
tail -f firebase_listener.log