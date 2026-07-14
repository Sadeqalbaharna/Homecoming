#!/usr/bin/env python3
"""
KAI Wake Word System - Diagnostic Version
Tests audio capture and LED triggering
"""
import subprocess
import os
import time
import wave
import struct
import math

api_key = "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"

# Try LED control
try:
    import RPi.GPIO as GPIO
    GPIO.setmode(GPIO.BCM)
    GPIO.setwarnings(False)
    
    # Test GPIO pins
    GPIO.setup(17, GPIO.OUT)
    GPIO.setup(22, GPIO.OUT)
    GPIO.setup(27, GPIO.OUT)
    
    # Turn all OFF
    GPIO.output(17, 0)
    GPIO.output(22, 0)
    GPIO.output(27, 0)
    
    print("✅ GPIO initialized")
    print("  GPIO 17 (BLUE): OFF")
    print("  GPIO 22 (YELLOW): OFF")
    print("  GPIO 27 (RED): OFF")
    has_gpio = True
except Exception as e:
    print(f"❌ GPIO Error: {e}")
    has_gpio = False

def get_rms_energy(audio_file):
    """Calculate RMS energy from WAV file"""
    try:
        with wave.open(audio_file, 'rb') as wav:
            frames = wav.readframes(wav.getnframes())
            samples = struct.unpack(f'<{len(frames)//2}h', frames)
            rms = math.sqrt(sum(s**2 for s in samples) / len(samples)) if samples else 0
            return rms
    except:
        return 0

def transcribe_audio(audio_file):
    """Transcribe with Whisper API"""
    import requests
    try:
        headers = {"Authorization": f"Bearer {api_key}"}
        with open(audio_file, "rb") as f:
            files = {"file": f, "model": (None, "whisper-1")}
            response = requests.post("https://api.openai.com/v1/audio/transcriptions", headers=headers, files=files)
        data = response.json()
        if "error" in data:
            return None
        return data.get("text", "").strip()
    except Exception as e:
        return None

print("\n" + "="*70)
print("TEST 1: Record 3 seconds and check audio level")
print("="*70)
print("Recording...")
subprocess.run("arecord -D plughw:3,0 -f S16_LE -r 16000 -d 3 /tmp/test_audio.wav 2>/dev/null", shell=True)

if os.path.exists("/tmp/test_audio.wav"):
    size = os.path.getsize("/tmp/test_audio.wav")
    rms = get_rms_energy("/tmp/test_audio.wav")
    print(f"✅ Recording complete")
    print(f"  File size: {size} bytes")
    print(f"  RMS energy: {rms:.0f}")
    print(f"  Audio level: {'LOUD' if rms > 1500 else 'QUIET'}")
else:
    print("❌ Recording failed")

print("\n" + "="*70)
print("TEST 2: Test Yellow LED (GPIO 22)")
print("="*70)
if has_gpio:
    print("Turning ON GPIO 22 (YELLOW)...")
    GPIO.output(22, 1)
    print("✅ GPIO 22 ON - Check if YELLOW LED is lit")
    time.sleep(2)
    print("Turning OFF GPIO 22...")
    GPIO.output(22, 0)
    print("✅ GPIO 22 OFF")
else:
    print("❌ GPIO not available")

print("\n" + "="*70)
print("TEST 3: Test Red LED (GPIO 27)")
print("="*70)
if has_gpio:
    print("Turning ON GPIO 27 (RED)...")
    GPIO.output(27, 1)
    print("✅ GPIO 27 ON - Check if RED LED is lit")
    time.sleep(2)
    print("Turning OFF GPIO 27...")
    GPIO.output(27, 0)
    print("✅ GPIO 27 OFF")
else:
    print("❌ GPIO not available")

print("\n" + "="*70)
print("TEST 4: Test Blue LED (GPIO 17)")
print("="*70)
if has_gpio:
    print("Turning ON GPIO 17 (BLUE)...")
    GPIO.output(17, 1)
    print("✅ GPIO 17 ON - Check if BLUE LED is lit")
    time.sleep(2)
    print("Turning OFF GPIO 17...")
    GPIO.output(17, 0)
    print("✅ GPIO 17 OFF")
else:
    print("❌ GPIO not available")

print("\n" + "="*70)
print("TEST 5: Transcribe the recorded audio")
print("="*70)
print("Sending to Whisper API...")
text = transcribe_audio("/tmp/test_audio.wav")
if text:
    print(f"✅ Transcribed: '{text}'")
    print(f"   (If this is gibberish/hallucination on silence,")
    print(f"    then speaker is too far away or mic not capturing voice)")
else:
    print("❌ Transcription failed")

if has_gpio:
    GPIO.cleanup()
    print("\n✅ GPIO cleaned up")
