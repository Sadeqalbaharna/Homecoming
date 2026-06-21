#!/usr/bin/env python3
"""
Test tones on Pi 3.5mm jack - direct local generation.
Run this script ON THE PI to test audio directly.
"""

import subprocess
import sys
import time
import logging

logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
log = logging.getLogger(__name__)

def test_tone(frequency=880, duration=3, volume=0.8):
    """Generate a test tone directly on the local Pi"""
    log.info(f"\n🎵 GENERATING TEST TONE: {frequency}Hz for {duration}s\n")
    
    # Ensure all audio is at max volume
    subprocess.run("amixer -c 0 sset Master 100% unmute 2>/dev/null", shell=True, capture_output=True)
    subprocess.run("amixer -c 0 sset PCM 100% 2>/dev/null", shell=True, capture_output=True)
    subprocess.run("amixer -c 0 sset Headphone unmute 2>/dev/null", shell=True, capture_output=True)
    
    log.info("1️⃣  Generating tone...")
    
    # Use sox to generate tone and pipe to aplay
    cmd = f"sox -n -t raw -r 48000 -b 16 -c 2 - synth {duration} sine {frequency} vol {volume} | aplay -D hw:0,0 --rate=48000 --channels=2 --format=S16_LE"
    
    log.info(f"   Command: {cmd}\n")
    
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=duration+5)
    
    if result.returncode == 0:
        log.info("✅ Tone generated successfully")
    else:
        if result.stderr:
            log.error(f"Error: {result.stderr}")
    
    log.info(f"\n🔊 You should hear a {frequency}Hz tone for {duration} seconds")
    log.info("   from the 3.5mm headphone jack on the Pi")

if __name__ == "__main__":
    # Test multiple tones
    tones = [
        (440, 2, "Low A note"),
        (880, 2, "High A note"),
        (1000, 2, "1000 Hz tone"),
    ]
    
    for freq, dur, desc in tones:
        log.info(f"\n{'='*50}")
        log.info(f"Testing: {desc} ({freq}Hz)")
        log.info('='*50)
        test_tone(freq, dur, 0.7)
        time.sleep(1)
    
    log.info("\n✅ All tones complete!")
