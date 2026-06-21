#!/usr/bin/env python3
"""
Quick test to play audio on any available sink, no Bluetooth required
"""

import subprocess
import sys

# Try a simple YouTube stream
print("Testing audio playback with a simple internet radio stream...")
print("(Using HTTP instead of HLS to reduce complexity)")
print()

# Simple test stream
test_url = "https://icecast.streamlab.com/mellow-jazz"

try:
    print(f"Starting mpv with: {test_url}")
    print("Playing for 10 seconds...")
    print("You should hear jazz music now!")
    print()
    
    # Use subprocess.run so it blocks until done
    result = subprocess.run([
        'mpv',
        '--volume', '100',  # Max volume
        '--no-video',
        '--term-statusline=no',
        f'--stream-record=no',
        '--autoprofile=no',
        test_url
    ], timeout=15)
    
    if result.returncode == 0:
        print("\n✅ Audio played successfully!")
    else:
        print(f"\n❌ mpv exited with code {result.returncode}")
        
except subprocess.TimeoutExpired:
    print("\n⏱️ Timeout (expected after 15 seconds)")
except Exception as e:
    print(f"\n❌ Error: {e}")

print("\nIf you didn't hear anything:")
print("  1. Check the speaker is on and volume is up")
print("  2. Check the audio cable is connected")
print("  3. Run: pactl list short sinks")
print("  4. Make sure mpv can output to the default sink")
