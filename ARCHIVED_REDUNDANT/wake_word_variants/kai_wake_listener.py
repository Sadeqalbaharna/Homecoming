#!/usr/bin/env python3
"""
Kai V1 Wake Word Listener
Continuously listens for "hey kai" or "kai" wake word, then triggers conversation
Uses pocketsphinx for local wake word detection (no internet required)
"""

import os
import subprocess
import sys
import time
from pathlib import Path

print("\n" + "="*60)
print("🎙️  KAI V1 WAKE WORD LISTENER")
print("   Listening for: 'hey kai' or 'kai'")
print("="*60 + "\n")

# First, check if pocketsphinx is installed
try:
    from pocketsphinx import LiveSpeech
    print("✓ pocketsphinx is installed\n")
except ImportError:
    print("❌ pocketsphinx not installed")
    print("\nInstalling required packages...")
    subprocess.run(["pip3", "install", "pocketsphinx", "pyaudio"], check=False)
    print("\nTrying again...")
    try:
        from pocketsphinx import LiveSpeech
        print("✓ pocketsphinx installed successfully\n")
    except ImportError:
        print("❌ Installation failed. Try manually:")
        print("  pip3 install pocketsphinx pyaudio")
        exit(1)

CONVERSATION_SCRIPT = Path("/home/pi/kai/session3_enhanced.py")
WAKE_WORDS = ["kai", "hey kai", "okay kai"]

def listen_for_wake_word():
    """Listen for wake word using pocketsphinx"""
    print("🎵 Listening for wake word...\n")
    
    try:
        speech = LiveSpeech(
            vocab=WAKE_WORDS,
            keyphrase='kai',
            logfn='/dev/null'  # Suppress debug output
        )
        
        for phrase in speech:
            detected = str(phrase).strip().lower()
            
            if any(wake in detected for wake in WAKE_WORDS):
                print(f"\n✓ Wake word detected: '{detected}'")
                print("🔄 Starting conversation...\n")
                
                # Trigger full conversation
                trigger_conversation()
                
                print("\n🎵 Listening for wake word...\n")
            
    except Exception as e:
        print(f"❌ Error in wake word detection: {e}")
        print("   Make sure USB audio device is connected")
        return False
    
    return True

def trigger_conversation():
    """Run the enhanced conversation script"""
    try:
        result = subprocess.run(
            ["python3", str(CONVERSATION_SCRIPT)],
            cwd="/home/pi/kai",
            timeout=60
        )
        return result.returncode == 0
    except subprocess.TimeoutExpired:
        print("⚠️  Conversation timeout")
        return False
    except Exception as e:
        print(f"❌ Failed to run conversation: {e}")
        return False

if __name__ == "__main__":
    try:
        print("Starting wake word listener...")
        print("Press Ctrl+C to stop\n")
        
        while True:
            success = listen_for_wake_word()
            if not success:
                print("⚠️  Restarting listener...")
                time.sleep(2)
    
    except KeyboardInterrupt:
        print("\n\n👋 Listener stopped")
        exit(0)
