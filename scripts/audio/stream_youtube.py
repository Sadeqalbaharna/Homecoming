#!/usr/bin/env python3
"""
Stream YouTube music (pirate shanties, tavern music, etc) through 3.5mm jack.
Uses yt-dlp to fetch audio and pipes it through headphone jack.
"""

import paramiko
import logging
import sys
from pathlib import Path
import time

logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
logger = logging.getLogger(__name__)

PI_USER = "pi"
AUDIO_DEVICE = "hw:0,0"

# Popular pirate and tavern music on YouTube
PLAYLISTS = {
    "pirate_shanty": {
        "name": "Pirate Shanty",
        "search": "pirate shanty sea shanty",
        "url": "https://www.youtube.com/results?search_query=pirate+sea+shanty"
    },
    "tavern": {
        "name": "Tavern Music",
        "search": "medieval tavern music background",
        "url": "https://www.youtube.com/results?search_query=tavern+music"
    },
    "pirate_music": {
        "name": "Pirate Background Music",
        "search": "pirate ship background music",
        "url": "https://www.youtube.com/results?search_query=pirate+music"
    }
}

def stream_youtube_music(pi_ip, query_or_url, duration=None):
    """Stream YouTube audio through 3.5mm jack"""
    try:
        logger.info(f"\n🎵 STREAMING YOUTUBE MUSIC\n")
        logger.info(f"Query: {query_or_url}")
        
        client = paramiko.SSHClient()
        client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        client.connect(
            pi_ip,
            username=PI_USER,
            key_filename=str(Path.home() / ".ssh" / "id_rsa"),
            timeout=10
        )
        
        # Check if input is a URL or search query
        if query_or_url.startswith("http"):
            url = query_or_url
        else:
            # Search for the query and get the first result
            logger.info("🔍 Searching YouTube...")
            search_cmd = f"yt-dlp --default-search ytsearch1 --print url '{query_or_url}' 2>/dev/null"
            stdin, stdout, stderr = client.exec_command(search_cmd, timeout=15)
            url = stdout.read().decode('utf-8', errors='ignore').strip()
            
            if not url:
                logger.error("❌ No results found")
                client.close()
                return 1
            
            logger.info(f"✅ Found: {url}\n")
        
        # Stream the audio
        logger.info("🎧 Streaming to headphone jack...")
        logger.info("   (This may take 10-20 seconds to start)")
        
        # Command to download best audio and pipe to headphones
        # Using ffmpeg to normalize volume and convert to proper format
        cmd = f"""
yt-dlp -f bestaudio --no-warnings -q -o - '{url}' 2>/dev/null | \\
ffmpeg -i pipe: -f s16le -acodec pcm_s16le -ac 2 -ar 48000 -loglevel quiet pipe: 2>/dev/null | \\
aplay -D {AUDIO_DEVICE} --rate=48000 --channels=2 --format=S16_LE 2>&1
"""
        
        if duration:
            # If duration specified, timeout after that time
            stdin, stdout, stderr = client.exec_command(cmd, timeout=duration+30)
            time.sleep(duration + 2)
        else:
            # Otherwise run in background
            stdin, stdout, stderr = client.exec_command(f"({cmd}) > /dev/null 2>&1 &", timeout=5)
            logger.info("   🎶 Music streaming in background (30 seconds)")
            time.sleep(30)
        
        logger.info("✅ Stream sent to headphones!\n")
        
        client.close()
        return 0
        
    except Exception as e:
        logger.error(f"❌ Failed: {e}")
        return 1

if __name__ == "__main__":
    if len(sys.argv) < 2:
        logger.error("Usage: python stream_youtube.py <PI_IP> <QUERY_OR_URL> [DURATION]")
        logger.error("")
        logger.error("Examples:")
        logger.error("  python stream_youtube.py 192.168.131.5 'pirate sea shanty'")
        logger.error("  python stream_youtube.py 192.168.131.5 'tavern music'")
        logger.error("  python stream_youtube.py 192.168.131.5 'https://youtube.com/watch?v=...' 60")
        logger.error("")
        logger.error("Suggested searches:")
        for key, info in PLAYLISTS.items():
            logger.error(f"  • {info['name']}: {info['search']}")
        sys.exit(1)
    
    pi_ip = sys.argv[1]
    query = sys.argv[2] if len(sys.argv) > 2 else "pirate sea shanty"
    duration = int(sys.argv[3]) if len(sys.argv) > 3 else None
    
    sys.exit(stream_youtube_music(pi_ip, query, duration))
