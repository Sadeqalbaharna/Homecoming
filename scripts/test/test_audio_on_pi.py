#!/usr/bin/env python3
"""
Quick test - play audio directly on Pi
"""

import paramiko
import logging
from pathlib import Path
import time

logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
logger = logging.getLogger(__name__)

PI_IP = "192.168.48.5"
PI_USER = "pi"

def test_audio():
    try:
        logger.info("Connecting to Pi...")
        client = paramiko.SSHClient()
        client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        client.connect(PI_IP, username=PI_USER, key_filename=str(Path.home() / ".ssh" / "id_rsa"))
        logger.info("✅ Connected\n")
        
        # Check if Bluetooth is still connected
        logger.info("Checking Bluetooth status...")
        stdin, stdout, stderr = client.exec_command("bluetoothctl info 39:3E:58:14:40:4A | grep Connected")
        output = stdout.read().decode().strip()
        logger.info(output)
        
        if "yes" not in output:
            logger.error("❌ Bluetooth disconnected!")
            return
        
        # Check if mpv exists
        logger.info("\nChecking if mpv is installed...")
        stdin, stdout, stderr = client.exec_command("which mpv")
        mpv_path = stdout.read().decode().strip()
        if mpv_path:
            logger.info(f"✅ mpv found at: {mpv_path}")
        else:
            logger.warning("⚠️  mpv not found, installing...")
            stdin, stdout, stderr = client.exec_command("sudo apt-get update && sudo apt-get install -y mpv")
            output = stdout.read().decode()
            logger.info("Install output (last 500 chars):")
            logger.info(output[-500:])
        
        # Check if yt-dlp exists
        logger.info("\nChecking if yt-dlp is installed...")
        stdin, stdout, stderr = client.exec_command("which yt-dlp")
        ytdlp_path = stdout.read().decode().strip()
        if ytdlp_path:
            logger.info(f"✅ yt-dlp found at: {ytdlp_path}")
        else:
            logger.warning("⚠️  yt-dlp not found, installing...")
            stdin, stdout, stderr = client.exec_command("pip3 install yt-dlp")
            output = stdout.read().decode()
            logger.info("Install output (last 300 chars):")
            logger.info(output[-300:])
        
        # Check PulseAudio
        logger.info("\nChecking PulseAudio...")
        stdin, stdout, stderr = client.exec_command("pactl list short sinks")
        sinks = stdout.read().decode()
        logger.info(sinks)
        
        # Try to get YouTube URL for pirate music
        logger.info("\nGetting YouTube URL for pirate music...")
        stdin, stdout, stderr = client.exec_command(
            "yt-dlp -f bestaudio -g 'https://www.youtube.com/results?search_query=pirate+ship+sea+shanty+D%26D+ambiance+music' 2>/dev/null | head -1"
        )
        url = stdout.read().decode().strip()
        
        if url and url.startswith("http"):
            logger.info(f"✅ Got streaming URL: {url[:80]}...\n")
            
            # Try to play it
            logger.info("🎵 Playing audio for 10 seconds on Bluetooth speaker...")
            stdin, stdout, stderr = client.exec_command(
                f"timeout 10 mpv --no-video --volume=20 '{url}' 2>&1 | tail -10"
            )
            time.sleep(12)
            output = stdout.read().decode()
            
            if output:
                logger.info("mpv output:")
                logger.info(output)
            
            logger.info("\n✅ If you heard audio on the speaker, it's working!")
            
        else:
            logger.error(f"❌ Failed to get YouTube URL")
            logger.info(f"yt-dlp stderr: {stderr.read().decode()}")
        
        client.close()
        
    except Exception as e:
        logger.error(f"Error: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    test_audio()
