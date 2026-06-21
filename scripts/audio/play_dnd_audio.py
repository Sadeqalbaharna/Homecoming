#!/usr/bin/env python3
"""
Homecoming D&D Audio Player - Master Script
Streams music/ambiance to Raspberry Pi 3.5mm jack
"""

import sys
import subprocess
import paramiko
from pathlib import Path
import time
import logging

logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
log = logging.getLogger(__name__)

PI_IP = "192.168.131.5"
PI_USER = "pi"
SSH_KEY = Path.home() / ".ssh" / "id_rsa"

def ssh_exec(cmd, timeout=30):
    """Execute command on Pi"""
    try:
        client = paramiko.SSHClient()
        client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        client.connect(PI_IP, username=PI_USER, key_filename=str(SSH_KEY), timeout=5)
        
        stdin, stdout, stderr = client.exec_command(cmd, timeout=timeout)
        output = stdout.read().decode('utf-8', errors='ignore')
        error = stderr.read().decode('utf-8', errors='ignore')
        
        client.close()
        return output, error
    except Exception as e:
        return "", str(e)

def play_audio(youtube_url, duration=60):
    """Stream audio from YouTube to 3.5mm jack"""
    log.info(f"\n🎵 STREAMING AUDIO for {duration} seconds\n")
    
    # Ensure volume is max
    ssh_exec("amixer -c 0 sset Master 100% unmute")
    ssh_exec("amixer -c 0 sset PCM 100%")
    
    # Stream command
    cmd = f"""
yt-dlp -f bestaudio --no-warnings -q -o - '{youtube_url}' 2>/dev/null | \\
ffmpeg -i pipe: -f s16le -acodec pcm_s16le -ac 2 -ar 48000 -loglevel quiet pipe: 2>/dev/null | \\
aplay -D hw:0,0 --rate=48000 --channels=2 --format=S16_LE 2>&1
"""
    
    log.info("🎧 Streaming to 3.5mm jack...")
    log.info(f"   URL: {youtube_url}\n")
    
    ssh_exec(f"({cmd}) > /dev/null 2>&1 &")
    
    log.info(f"⏱️  Playing for {duration} seconds...")
    time.sleep(duration)
    
    log.info("✅ Stream complete!\n")

MUSIC_LIBRARY = {
    "1": {
        "name": "Pirate Shanty",
        "url": "https://www.youtube.com/watch?v=ZN0tg3aPRnM",
        "duration": 120
    },
    "2": {
        "name": "Tavern Music",
        "url": "https://www.youtube.com/watch?v=qiBfT-Ts1K0",
        "duration": 180
    },
    "3": {
        "name": "Battle Music",
        "url": "https://www.youtube.com/watch?v=hg8K1w1X6fU",
        "duration": 120
    },
    "4": {
        "name": "Forest Ambience",
        "url": "https://www.youtube.com/watch?v=CZ0DnJlrnCM",
        "duration": 300
    },
}

if __name__ == "__main__":
    log.info("\n" + "="*60)
    log.info("🎭 HOMECOMING D&D AUDIO PLAYER")
    log.info("="*60 + "\n")
    
    log.info("Available Scenes:")
    for key, info in MUSIC_LIBRARY.items():
        log.info(f"  {key}. {info['name']} ({info['duration']}s)")
    
    log.info("\nOptions:")
    log.info("  custom <URL> - Stream custom YouTube URL")
    log.info("  test - Test audio with tones")
    
    if len(sys.argv) < 2:
        log.error("\nUsage: python play_dnd_audio.py <SCENE_NUMBER|custom|test> [URL|DURATION]")
        log.error("Examples:")
        log.error("  python play_dnd_audio.py 1")
        log.error("  python play_dnd_audio.py custom https://youtube.com/watch?v=... 120")
        log.error("  python play_dnd_audio.py test")
        sys.exit(1)
    
    cmd = sys.argv[1]
    
    if cmd == "test":
        # Test tones
        log.info("\n🎵 TESTING AUDIO TONES\n")
        for freq in [440, 880, 1000]:
            test_cmd = f"sox -n -t raw -r 48000 -b 16 -c 2 - synth 2 sine {freq} vol 0.7 | aplay -D hw:0,0 --rate=48000 --channels=2 --format=S16_LE"
            ssh_exec(f"({test_cmd}) > /dev/null 2>&1 &")
            time.sleep(3)
        log.info("✅ Test tones sent\n")
    
    elif cmd == "custom":
        if len(sys.argv) < 3:
            log.error("Usage: python play_dnd_audio.py custom <URL> [DURATION]")
            sys.exit(1)
        url = sys.argv[2]
        duration = int(sys.argv[3]) if len(sys.argv) > 3 else 60
        play_audio(url, duration)
    
    elif cmd in MUSIC_LIBRARY:
        scene = MUSIC_LIBRARY[cmd]
        log.info(f"Playing: {scene['name']}\n")
        play_audio(scene['url'], scene['duration'])
    
    else:
        log.error(f"Unknown scene: {cmd}")
        sys.exit(1)
    
    log.info("🎉 Done!\n")
