#!/usr/bin/env python3
"""
Direct Bluetooth audio test - simplified debugging
"""

import subprocess
import logging
import sys
import time

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def test_sink_status():
    """Check if sink is active"""
    logger.info("1️⃣ Checking PulseAudio sink status...")
    result = subprocess.run(
        ['pactl', 'list', 'sinks'],
        capture_output=True, text=True
    )
    
    if 'bluez_output.39_3E_58_14_40_4A.1' in result.stdout:
        logger.info("✅ TG-129C speaker found")
        
        # Check if it's running
        if 'RUNNING' in result.stdout:
            logger.info("✅ Sink is RUNNING - audio should play")
        elif 'SUSPENDED' in result.stdout:
            logger.warning("⚠️ Sink is SUSPENDED - might not play audio")
            logger.info("   Trying to wake it up...")
            subprocess.run(['pactl', 'set-sink-mute', 'bluez_output.39_3E_58_14_40_4A.1', 'toggle'])
    else:
        logger.error("❌ TG-129C speaker not found")
        return False
    
    return True

def test_mpv_output():
    """Test mpv with audio"""
    logger.info("")
    logger.info("2️⃣ Testing mpv with YouTube audio...")
    logger.info("   (Searching for simple piano music)")
    
    # Get a simple, stable YouTube link
    cmd_search = [
        'yt-dlp',
        '-f', 'bestaudio',
        '-q',
        '--no-warnings',
        '-j',
        'ytsearch1:relaxing piano music 1 hour'
    ]
    
    try:
        result = subprocess.run(cmd_search, capture_output=True, text=True, timeout=30)
        
        if result.returncode != 0:
            logger.error(f"❌ yt-dlp failed: {result.stderr[:200]}")
            return False
        
        import json
        try:
            data = json.loads(result.stdout)
            url = data['url']
            title = data.get('title', 'Unknown')
            logger.info(f"✅ Found: {title}")
        except:
            logger.error("❌ Failed to parse yt-dlp output")
            return False
        
    except subprocess.TimeoutExpired:
        logger.error("❌ YouTube search timed out")
        return False
    
    logger.info("")
    logger.info("3️⃣ Playing audio for 15 seconds...")
    logger.info("   📢 Crank up the TG-129C speaker volume and listen!")
    logger.info("")
    
    cmd_play = [
        'mpv',
        '--audio-device=pulse/bluez_output.39_3E_58_14_40_4A.1',
        '--volume=120',  # Over 100% for extra loud
        '--no-video',
        '--really-quiet',
        '--duration=15',
        url
    ]
    
    logger.info(f"Running: mpv with audio-device={cmd_play[1]}")
    logger.info(f"         Volume: {cmd_play[3]}")
    logger.info("")
    
    result = subprocess.run(cmd_play, capture_output=True, text=True)
    
    logger.info("⏹️  Stopped")
    logger.info("")
    logger.info("=" * 60)
    logger.info("TROUBLESHOOTING:")
    logger.info("=" * 60)
    logger.info("If you didn't hear music:")
    logger.info("  1. Check if TG-129C speaker is ON and charged")
    logger.info("  2. Check if speaker Bluetooth is connected")
    logger.info("     Run: bluetoothctl info 39:3E:58:14:40:4A")
    logger.info("  3. Check if speaker volume is at MAX")
    logger.info("  4. Check if speaker is in correct mode")
    logger.info("  5. Run: pactl list sinks (check if RUNNING)")
    logger.info("")
    logger.info("If it said SUSPENDED:")
    logger.info("  Run: pactl set-sink-mute bluez_output.39_3E_58_14_40_4A.1 toggle")
    logger.info("")
    
    return True

if __name__ == '__main__':
    if not test_sink_status():
        sys.exit(1)
    
    if not test_mpv_output():
        sys.exit(1)
    
    logger.info("✅ Test complete!")
