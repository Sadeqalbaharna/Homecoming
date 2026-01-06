#!/usr/bin/env python3
"""
Test Bluetooth speaker with a local beep (doesn't require YouTube)
"""

import subprocess
import logging
import sys
import os

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def generate_test_tone():
    """Generate a simple test tone using ffmpeg"""
    output_file = '/tmp/test_tone.wav'
    
    logger.info("1️⃣ Generating test tone...")
    
    # Generate 3-second tone at 440 Hz (A note)
    cmd = [
        'ffmpeg',
        '-f', 'lavfi',
        '-i', 'sine=frequency=440:duration=3',
        '-q:a', '9',
        '-acodec', 'libmp3lame',
        '-y',  # Overwrite
        output_file
    ]
    
    try:
        result = subprocess.run(cmd, capture_output=True, timeout=10)
        if result.returncode == 0 and os.path.exists(output_file):
            logger.info(f"✅ Test tone created: {output_file}")
            return output_file
        else:
            logger.error("❌ ffmpeg failed")
            return None
    except Exception as e:
        logger.error(f"❌ Failed: {e}")
        return None

def test_bluetooth_speaker(audio_file):
    """Test Bluetooth speaker with the audio file"""
    logger.info("")
    logger.info("2️⃣ Setting up PulseAudio...")
    
    # Wake up the sink
    subprocess.run(['pactl', 'set-sink-mute', 'bluez_output.39_3E_58_14_40_4A.1', '0'], 
                  timeout=2, capture_output=True)
    subprocess.run(['pactl', 'set-sink-volume', 'bluez_output.39_3E_58_14_40_4A.1', '100%'], 
                  timeout=2, capture_output=True)
    logger.info("✅ Audio sink configured")
    
    logger.info("")
    logger.info("3️⃣ Playing test tone for 3 seconds...")
    logger.info("   📢 LISTEN CAREFULLY TO YOUR SPEAKER!")
    logger.info("   You should hear a high-pitched beep...")
    logger.info("")
    
    cmd = [
        'mpv',
        '--audio-device=pulse/bluez_output.39_3E_58_14_40_4A.1',
        '--volume=120',  # Extra loud
        '--no-video',
        '--really-quiet',
        audio_file
    ]
    
    result = subprocess.run(cmd, capture_output=True)
    
    logger.info("⏹️  Done")
    logger.info("")
    logger.info("=" * 60)
    logger.info("RESULT:")
    logger.info("=" * 60)
    logger.info("")
    logger.info("Did you hear a beep from the TG-129C speaker?")
    logger.info("")
    logger.info("  ✅ YES  → Speaker is working!")
    logger.info("  ❌ NO   → Check:")
    logger.info("     1. Is the speaker powered on and charged?")
    logger.info("     2. Is Bluetooth connected? (check LED)")
    logger.info("     3. Is speaker volume turned up?")
    logger.info("     4. Check: pactl list sinks | grep bluez")
    logger.info("     5. If SUSPENDED, try: ")
    logger.info("        pactl set-sink-mute bluez_output.39_3E_58_14_40_4A.1 toggle")
    logger.info("")

if __name__ == '__main__':
    # Check if ffmpeg is available
    try:
        subprocess.run(['ffmpeg', '-version'], capture_output=True, timeout=2)
    except:
        logger.error("❌ ffmpeg not found - required for test tone")
        logger.info("Install with: sudo apt-get install ffmpeg")
        sys.exit(1)
    
    audio_file = generate_test_tone()
    if not audio_file:
        sys.exit(1)
    
    test_bluetooth_speaker(audio_file)
    
    # Cleanup
    os.remove(audio_file)
    logger.info("✅ Cleanup complete")
