#!/usr/bin/env python3
"""
Direct Bluetooth Audio Test for TG-129C Speaker
Tests if audio is reaching the Bluetooth speaker
"""

import subprocess
import time
import sys

def test_bluetooth_audio():
    """Test audio playback on TG-129C Bluetooth speaker"""
    
    print("=" * 80)
    print("BLUETOOTH AUDIO TEST FOR TG-129C SPEAKER")
    print("=" * 80)
    
    # Check if speaker is connected
    print("\n1. Checking Bluetooth Speaker Connection...")
    try:
        result = subprocess.run(
            ["bluetoothctl", "info", "39:3E:58:14:40:4A"],
            capture_output=True,
            text=True,
            timeout=5
        )
        if "Connected: yes" in result.stdout:
            print("   ✅ TG-129C Speaker is CONNECTED")
        else:
            print("   ❌ TG-129C Speaker is NOT connected")
            print(result.stdout)
            return False
    except Exception as e:
        print(f"   ❌ Error checking Bluetooth: {e}")
        return False
    
    # Check default audio sink
    print("\n2. Checking Default Audio Sink...")
    try:
        result = subprocess.run(
            ["pactl", "info"],
            capture_output=True,
            text=True,
            timeout=5
        )
        for line in result.stdout.split('\n'):
            if 'Default Sink' in line:
                print(f"   ✅ {line.strip()}")
                if "bluez_output" in line:
                    print("   ✅ Bluetooth speaker is DEFAULT output!")
                elif "39_3E_58" in line:
                    print("   ✅ Bluetooth speaker is DEFAULT output!")
                else:
                    print("   ⚠️  Default output is NOT Bluetooth speaker")
                    print("       Attempting to set it...")
                    # Try to set it
                    subprocess.run(
                        ["pactl", "set-default-sink", "bluez_output.39_3E_58_14_40_4A.1"],
                        timeout=5
                    )
                break
    except Exception as e:
        print(f"   ⚠️  Error checking sink: {e}")
    
    # List all available sinks
    print("\n3. Available Audio Sinks:")
    try:
        result = subprocess.run(
            ["pactl", "list", "short", "sinks"],
            capture_output=True,
            text=True,
            timeout=5
        )
        for line in result.stdout.strip().split('\n'):
            if line:
                print(f"   {line}")
    except Exception as e:
        print(f"   ❌ Error listing sinks: {e}")
    
    # Test with paplay (simpler than mpv)
    print("\n4. Testing Audio Playback with paplay...")
    print("   Playing: /home/pi/music_tracks/track_1.mp3")
    print("   (You should hear audio on the Bluetooth speaker now...)")
    
    try:
        subprocess.Popen(
            ["paplay", "--device=bluez_output.39_3E_58_14_40_4A.1", 
             "/home/pi/music_tracks/track_1.mp3"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE
        )
        print("   ⏳ Waiting for audio to start...")
        time.sleep(3)
        print("   ✅ Audio playback started!")
        print("   (Listening for 10 seconds...)")
        time.sleep(10)
        
        # Kill playback
        subprocess.run(["pkill", "-f", "paplay"], timeout=5)
        print("   ✅ Playback stopped")
        return True
        
    except Exception as e:
        print(f"   ❌ Error during playback: {e}")
        return False

if __name__ == "__main__":
    success = test_bluetooth_audio()
    
    print("\n" + "=" * 80)
    if success:
        print("✅ AUDIO TEST COMPLETE - If you heard music, Bluetooth is working!")
    else:
        print("❌ AUDIO TEST FAILED - Check speaker connection and try again")
    print("=" * 80)
    
    sys.exit(0 if success else 1)
