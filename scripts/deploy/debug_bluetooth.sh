#!/bin/bash
# Debug Bluetooth speaker audio

echo "🔊 Debugging TG-129C Bluetooth Audio"
echo "====================================="
echo ""

echo "1️⃣  Checking audio sinks..."
pactl list short sinks
echo ""

echo "2️⃣  Checking default sink..."
DEFAULT=$(pactl get-default-sink)
echo "Default sink: $DEFAULT"
echo ""

echo "3️⃣  Checking if speaker is listed..."
if pactl list short sinks | grep -q "bluez_output.39_3E_58_14_40_4A.1"; then
    echo "✅ TG-129C speaker found"
else
    echo "❌ TG-129C speaker NOT found"
    echo "Trying to reconnect..."
    bluetoothctl connect 39:3E:58:14:40:4A
fi
echo ""

echo "4️⃣  Checking speaker state..."
pactl list sinks | grep -A 20 "bluez_output"
echo ""

echo "5️⃣  Testing mpv with a YouTube video..."
echo "🔍 Searching for tavern music..."
URL=$(yt-dlp -f bestaudio -q -j 'ytsearch1:medieval tavern music' | python3 -c 'import sys, json; d=json.load(sys.stdin); print(d[0]["url"])')

if [ -z "$URL" ]; then
    echo "❌ Failed to get URL from YouTube"
    exit 1
fi

echo "✅ Got URL"
echo ""
echo "🔊 Playing for 10 seconds with FULL volume (100%)..."
echo "   Check if you hear anything from the speaker!"
echo ""

mpv --audio-device=pulse/bluez_output.39_3E_58_14_40_4A.1 --volume=100 --no-video --really-quiet --duration=10 "$URL" 2>&1 | grep -E "^(A-V|Playing|paused|Exiting|ERROR)"

echo ""
echo "⏹️  Test complete"
echo ""
echo "Results:"
echo "  If you heard music: ✅ Speaker is working"
echo "  If silent: Check:"
echo "    1. Is speaker power on and charged?"
echo "    2. Is speaker Bluetooth volume at max?"
echo "    3. Run: pactl set-sink-volume bluez_output.39_3E_58_14_40_4A.1 100%"
echo "    4. Run: pactl set-sink-mute bluez_output.39_3E_58_14_40_4A.1 0"
