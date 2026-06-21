#!/bin/bash
# Deploy AI Music System to Pi
# Run this on the Pi to update the listener with new AI music queries

echo "🚀 Deploying AI Music Query Generator to Pi"
echo "==========================================="

# Change to home directory
cd /home/pi

# Check if git repo exists
if [ ! -d .git ]; then
    echo "❌ Not in git repository"
    exit 1
fi

# Step 1: Backup current listener
echo ""
echo "📋 Step 1: Backing up current listener..."
cp firebase_rest_listener_debug.py firebase_rest_listener_debug.py.backup.$(date +%Y%m%d_%H%M%S)
echo "✅ Backup created"

# Step 2: Pull latest code
echo ""
echo "📥 Step 2: Pulling latest code from Git..."
git pull origin main

if [ $? -ne 0 ]; then
    echo "❌ Git pull failed"
    exit 1
fi
echo "✅ Git pull successful"

# Step 3: Check if file has AI music changes
echo ""
echo "🔍 Step 3: Verifying AI music system..."
if grep -q "_get_ambiance_music" firebase_rest_listener_debug.py; then
    if grep -q "action_music_map" firebase_rest_listener_debug.py; then
        echo "✅ AI music system detected in code"
    else
        echo "❌ Old music system detected - file update may have failed"
        exit 1
    fi
else
    echo "❌ Music generation function not found"
    exit 1
fi

# Step 4: Stop old listener
echo ""
echo "🛑 Step 4: Stopping old listener..."
pkill -f firebase_rest_listener_debug
sleep 2
echo "✅ Listener stopped"

# Step 5: Start new listener
echo ""
echo "🚀 Step 5: Starting new listener with AI music system..."
sudo nohup python3 firebase_rest_listener_debug.py > listener.log 2>&1 &
LISTENER_PID=$!
sleep 3

# Step 6: Verify it started
echo ""
echo "🔍 Step 6: Verifying listener started..."
if ps -p $LISTENER_PID > /dev/null; then
    echo "✅ Listener process running (PID: $LISTENER_PID)"
else
    ps aux | grep firebase_rest_listener_debug | grep -v grep
fi

# Step 7: Check logs for AI music indicators
echo ""
echo "📊 Step 7: Checking logs for AI music system..."
sleep 2
MUSIC_LINES=$(grep -c "MUSIC AI" listener.log 2>/dev/null || echo 0)
if [ $MUSIC_LINES -gt 0 ]; then
    echo "✅ AI music system is active (found ${MUSIC_LINES} references)"
    echo ""
    echo "Recent AI music log entries:"
    tail -5 listener.log | grep "MUSIC AI" || tail -10 listener.log
else
    echo "ℹ️ No AI music entries in logs yet (will appear after first ambiance request)"
    echo "Last 10 log entries:"
    tail -10 listener.log
fi

# Step 8: Test status endpoint
echo ""
echo "🧪 Step 8: Testing listener status endpoint..."
RESPONSE=$(curl -s http://localhost:5001/kai/status)
if echo "$RESPONSE" | grep -q "system_online"; then
    echo "✅ Status endpoint responding"
    echo "Response: $RESPONSE"
else
    echo "⚠️ Status endpoint may not be responding"
fi

echo ""
echo "=========================================="
echo "✅ DEPLOYMENT COMPLETE!"
echo "=========================================="
echo ""
echo "📝 Next steps:"
echo "1. Test with HTTP request:"
echo "   curl -X POST http://localhost:5001/kai/ambiance \\"
echo "     -H 'Content-Type: application/json' \\"
echo "     -d '{\"prompt\": \"Warm cozy tavern\", \"include_music\": true}'"
echo ""
echo "2. Monitor logs for AI music:"
echo "   tail -f listener.log | grep 'MUSIC AI'"
echo ""
echo "3. Test from app:"
echo "   Say: 'Hey Kai, start the tavern scene'"
