#!/bin/bash

# Deploy Kai Consciousness System to Raspberry Pi
# Run this on your Pi to install Flask and start the consciousness server

echo "🤖 Deploying Kai Consciousness System..."

# Install Flask dependencies
echo "📦 Installing Flask dependencies..."
pip3 install flask flask-cors

# Check if the firebase listener file exists
if [ ! -f "firebase_rest_listener_debug.py" ]; then
    echo "❌ firebase_rest_listener_debug.py not found!"
    echo "Please copy the updated file to /home/pi/"
    exit 1
fi

# Kill any existing processes
echo "🛑 Stopping existing processes..."
pkill -f "firebase_rest_listener_debug.py" || echo "No existing processes found"

# Start the consciousness-enabled listener
echo "🚀 Starting Kai Consciousness System..."
echo "📡 Firebase polling + Flask API server on port 5001"
echo "🌐 Consciousness endpoint: http://$(hostname -I | awk '{print $1}'):5001/kai/context"
echo ""
echo "Press Ctrl+C to stop..."

python3 firebase_rest_listener_debug.py