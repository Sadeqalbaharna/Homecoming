"""
Audio output driver - plays music via YouTube or local files
"""

import subprocess
import logging
from typing import Any, Dict, Optional
import asyncio
import shutil

from ..core.driver_base import OutputDriver, DriverConfig

logger = logging.getLogger(__name__)


class AudioDriver(OutputDriver):
    """
    Play audio from YouTube or local files using mpv.
    Supports Bluetooth speaker routing.
    """
    
    def __init__(self, config: DriverConfig):
        super().__init__(config)
        self.current_process: Optional[subprocess.Popen] = None
        self.current_query: Optional[str] = None
        
        # Extract config
        self.sink_name = config.params.get('sink_name', None)  # PulseAudio sink (for Bluetooth)
        self.mpv_path = config.params.get('mpv_path', 'mpv')
        self.yt_dlp_path = config.params.get('yt_dlp_path', 'yt-dlp')
    
    async def initialize(self) -> bool:
        """Check if mpv is available"""
        try:
            result = subprocess.run([self.mpv_path, '--version'], 
                                  capture_output=True, timeout=2)
            if result.returncode == 0:
                self.logger.info(f"✅ mpv found: {self.mpv_path}")
                return True
            else:
                self.logger.error(f"❌ mpv not working")
                return False
        except Exception as e:
            self.logger.error(f"❌ mpv initialization failed: {e}")
            return False
    
    async def activate(self, params: Dict[str, Any]) -> bool:
        """
        Play audio from YouTube search query or file path.
        
        Params:
        - query: YouTube search query or file path
        - volume: 0.0-1.0 (default 0.8)
        - duration_ms: Optional, how long to play
        """
        try:
            query = params.get('query', '')
            volume = params.get('volume', 0.8)
            
            if not query:
                self.logger.error("❌ No query provided")
                return False
            
            self.logger.info(f"🎵 Audio request: '{query}' (volume={volume})")
            
            # Stop currently playing audio
            await self.deactivate()
            await asyncio.sleep(0.5)
            
            # Check if the configured sink actually exists
            sink_to_use = None
            if self.sink_name:
                # Verify sink exists via PulseAudio
                try:
                    result = subprocess.run(
                        ['pactl', 'get-sink-mute', self.sink_name],
                        timeout=2, capture_output=True
                    )
                    if result.returncode == 0:
                        sink_to_use = self.sink_name
                        self.logger.info(f"✅ Bluetooth sink found: {self.sink_name}")
                    else:
                        self.logger.warning(f"⚠️  Configured Bluetooth sink not available: {self.sink_name}")
                        self.logger.info(f"💡 Will use system audio output instead")
                except:
                    self.logger.warning(f"⚠️  Could not verify sink: {self.sink_name}")
            
            # If Bluetooth sink not available, try to find any available audio device
            if not sink_to_use:
                # Try to find available ALSA devices
                try:
                    result = subprocess.run(
                        ['aplay', '-l'],
                        timeout=2, capture_output=True, text=True
                    )
                    # Just log available devices - mpv will use default
                    if 'Headphones' in result.stdout:
                        self.logger.info(f"🎧 Found: Headphones output")
                    if 'hdmi' in result.stdout.lower():
                        self.logger.info(f"🎧 Found: HDMI audio output")
                except Exception as e:
                    self.logger.debug(f"Could not check ALSA devices: {e}")
            
            # Wake up the sink if found
            if sink_to_use:
                try:
                    self.logger.info(f"🔌 Waking up audio sink...")
                    subprocess.run(['pactl', 'set-sink-mute', sink_to_use, '0'], 
                                 timeout=2, capture_output=True)
                    subprocess.run(['pactl', 'set-sink-volume', sink_to_use, '100%'], 
                                 timeout=2, capture_output=True)
                    await asyncio.sleep(0.5)
                except Exception as e:
                    self.logger.warning(f"⚠️  Could not configure sink: {e}")
            
            # Check if it's a YouTube query (doesn't start with /)
            if not query.startswith('/') and not query.startswith('http'):
                # YouTube search - stream directly without downloading
                self.logger.info(f"🔍 Searching YouTube for: {query}")
                
                # Use yt-dlp to get stream URL (much faster than downloading)
                self.logger.info(f"⏱️  Getting stream URL for: {query}")
                stream_cmd = [
                    self.yt_dlp_path,
                    '-f', 'bestaudio',
                    '-g',  # Get URL only, don't download
                    f'ytsearch1:{query}'
                ]
                
                try:
                    result = subprocess.run(stream_cmd, timeout=30, capture_output=True, text=True)
                    if result.returncode != 0:
                        self.logger.error(f"❌ Failed to get stream URL: {result.stderr}")
                        return False
                    
                    audio_url = result.stdout.strip().split('\n')[0]  # Get first URL line
                    if not audio_url:
                        self.logger.error(f"❌ No stream URL returned")
                        return False
                    
                    self.logger.info(f"✅ Got stream URL (instant, no download needed)")
                except subprocess.TimeoutExpired:
                    self.logger.error(f"❌ Stream URL lookup timeout")
                    return False
            else:
                audio_url = query
            
            self.current_query = query
            
            # Build mpv command
            mpv_cmd = [self.mpv_path]
            
            # Add sink if we found one
            if sink_to_use:
                # sink_to_use is already the full name like "bluez_output.39_3E_58_14_40_4A.1"
                # mpv needs format: --audio-device=pulse/name (with equals sign!)
                if not sink_to_use.startswith('pulse/'):
                    mpv_cmd.extend([f'--audio-device=pulse/{sink_to_use}'])
                else:
                    mpv_cmd.extend([f'--audio-device={sink_to_use}'])
                self.logger.info(f"🔊 Using audio device: {sink_to_use}")
            else:
                # Use default sink
                self.logger.info(f"🔊 Using default audio device (no Bluetooth sink available)")
            
            # Volume control (convert 0-1 to 0-100)
            # SAFETY: Cap at 20% max for public use (prevent hearing damage & disturbing others)
            mpv_volume = int(volume * 100)
            # Enforce maximum 20% volume for safety in public spaces
            mpv_volume = min(mpv_volume, 20)
            # Ensure minimum 5 for audibility when requested
            mpv_volume = max(mpv_volume, 5)
            
            self.logger.info(f"🔊 Volume: {mpv_volume}% (capped at 20% max for public safety)")
            mpv_cmd.extend([f'--volume={mpv_volume}'])
            
            # Other options for reliable playback
            # Use --keep-open to prevent immediate exit
            # Use --cache=auto for stream buffering
            mpv_cmd.extend([
                '--no-video',
                '--keep-open=no',  # Close when done
                '--cache=auto',    # Buffer for smooth playback
                audio_url
            ])
            
            # Start playback
            self.logger.info(f"▶️ Starting mpv with volume={mpv_volume}%")
            self.logger.info(f"🔊 Command: {' '.join(mpv_cmd[:10])}...")  # Log first 10 args to avoid spam
            self.current_process = subprocess.Popen(
                mpv_cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True
            )
            
            # Give mpv a moment to start and check for immediate errors
            await asyncio.sleep(0.5)
            
            if self.current_process.poll() is not None:
                # Process exited immediately - something went wrong
                stdout_text, stderr_text = self.current_process.communicate()
                error_msg = stderr_text[:500] if stderr_text else stdout_text[:500]
                self.logger.error(f"❌ mpv failed to start")
                self.logger.error(f"   Error: {error_msg}")
                self.logger.error(f"   Command was: {' '.join(mpv_cmd[:8])}...")
                return False
            
            self._active = True
            self.logger.info(f"✅ Audio playback started (mpv process running)")
            
            # Start a task to monitor mpv output for errors
            asyncio.create_task(self._monitor_mpv_output())
            
            return True
            
        except Exception as e:
            self.logger.error(f"❌ Activation error: {e}")
            return False
    
    async def deactivate(self) -> bool:
        """Stop playback"""
        try:
            if self.current_process and self.current_process.poll() is None:
                self.logger.info("⏹️  Terminating audio playback...")
                self.current_process.terminate()
                await asyncio.sleep(0.3)
                
                if self.current_process.poll() is None:
                    self.logger.info("💥 Force killing mpv...")
                    self.current_process.kill()
                    await asyncio.sleep(0.2)
                
                self._active = False
                self.logger.info("✅ Audio playback stopped")
            
            return True
        except Exception as e:
            self.logger.error(f"❌ Deactivation error: {e}")
            return False
    
    async def is_ready(self) -> bool:
        """Check if audio driver is ready"""
        try:
            result = subprocess.run([self.mpv_path, '--version'], 
                                  capture_output=True, timeout=2)
            return result.returncode == 0
        except:
            return False
    
    async def _monitor_mpv_output(self):
        """Monitor mpv stderr for errors"""
        try:
            if not self.current_process:
                return
            
            while self.current_process.poll() is None:
                # Check stderr for important messages
                try:
                    line = self.current_process.stderr.readline()
                    if line:
                        line = line.strip()
                        if 'error' in line.lower() or 'failed' in line.lower():
                            self.logger.error(f"🎵 mpv: {line}")
                        elif 'cache' in line.lower() or 'playing' in line.lower():
                            self.logger.info(f"🎵 mpv: {line}")
                except:
                    pass
                
                await asyncio.sleep(0.1)
        except Exception as e:
            self.logger.debug(f"Monitor error: {e}")
    
    async def _search_youtube(self, query: str) -> Optional[str]:
        """Search YouTube using yt-dlp and return YouTube URL (mpv will handle playback)"""
        try:
            # Use yt-dlp to find the video ID, then return a YouTube URL that mpv can play
            cmd = [self.yt_dlp_path, '-f', 'bestaudio', '-q', '-j', f'ytsearch1:{query}']
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
            
            if result.returncode == 0:
                import json
                data = json.loads(result.stdout)
                video_id = data.get('id')
                title = data.get('title', 'Unknown')
                
                if video_id:
                    self.logger.info(f"✅ Found: {title}")
                    # Return YouTube URL that mpv can play with youtube-dl/yt-dlp
                    return f"https://www.youtube.com/watch?v={video_id}"
            
            self.logger.error(f"❌ yt-dlp search failed: {result.stderr[:200]}")
            return None
            
        except Exception as e:
            self.logger.error(f"❌ YouTube search error: {e}")
            return None
