#!/bin/bash
# Start Firebase REST Listener with sudo privileges for LED control

echo "🚀 Starting Firebase REST Listener with sudo privileges..."

# Kill any existing listener processes
pkill -f firebase_rest_listener_debug.py

# Start the listener with sudo
cd /home/pi
sudo python3 firebase_rest_listener_debug.py > listener.log 2>&1 &

# Get the PID
PID=$!
echo "✅ Firebase listener started with PID: $PID (running as root)"
echo "📋 Logs: tail -f /home/pi/listener.log"

# Wait a moment and check if it's running
sleep 2
if ps -p $PID > /dev/null; then
    echo "✅ Listener confirmed running"
    tail -20 listener.log
else
    echo "❌ Listener failed to start"
    tail -50 listener.log
fi
