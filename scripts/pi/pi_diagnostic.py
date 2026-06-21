#!/usr/bin/env python3
"""
Quick diagnostic script to check Firebase listener version and functionality
Run this on the Pi to verify which version is running
"""

import os
import subprocess
import sys

def main():
    print("🔍 Firebase Listener Diagnostic")
    print("=" * 50)
    
    # Check if file exists
    listener_file = "/home/pi/firebase_rest_listener_debug.py"
    if not os.path.exists(listener_file):
        print("❌ firebase_rest_listener_debug.py not found!")
        print(f"   Expected location: {listener_file}")
        return
    
    print(f"✅ Firebase listener file found: {listener_file}")
    
    # Check file size and modification time
    stat = os.stat(listener_file)
    print(f"📊 File size: {stat.st_size} bytes")
    print(f"📅 Last modified: {stat.st_mtime}")
    
    # Check if set_scene functionality exists
    with open(listener_file, 'r') as f:
        content = f.read()
    
    # Look for key indicators
    has_set_scene = 'elif action == "set_scene" and target == "lights":' in content
    has_audio_detection = '_detect_audio_device' in content
    has_logging_fix = 'logging.basicConfig' in content and content.find('logging.basicConfig') < content.find('from rpi_ws281x')
    
    print("\n🔧 Feature Check:")
    print(f"   Scene Lighting Support: {'✅' if has_set_scene else '❌'}")
    print(f"   Audio Device Detection: {'✅' if has_audio_detection else '❌'}")
    print(f"   Logger Fix Applied: {'✅' if has_logging_fix else '❌'}")
    
    # Check total lines
    line_count = content.count('\n') + 1
    print(f"   Total lines: {line_count}")
    
    # Check for specific version indicators
    if line_count > 1280:
        print("✅ This appears to be the UPDATED version")
    else:
        print("⚠️ This appears to be an OLDER version")
    
    print("\n🎯 Recommended Action:")
    if has_set_scene and has_audio_detection:
        print("   Your file looks up to date! Scene lighting should work.")
        print("   If you're still getting 'Unknown action' errors, try restarting the listener.")
    else:
        print("   Your file needs updating. Please follow UPDATE_PI_LISTENER.md")
    
    # Check if listener is currently running
    try:
        result = subprocess.run(["pgrep", "-f", "firebase_rest_listener"], 
                              capture_output=True, text=True)
        if result.returncode == 0:
            pids = result.stdout.strip().split('\n')
            print(f"\n🔄 Currently running listener processes: {len(pids)}")
            for pid in pids:
                if pid.strip():
                    print(f"   PID: {pid.strip()}")
        else:
            print("\n💤 No firebase listener processes currently running")
    except Exception as e:
        print(f"\n⚠️ Could not check running processes: {e}")

if __name__ == "__main__":
    main()