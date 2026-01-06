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
            
            # Check if it's a YouTube query (doesn't start with /)
            if not query.startswith('/') and not query.startswith('http'):
                # YouTube search
                self.logger.info(f"🔍 Searching YouTube for: {query}")
                audio_url = await self._search_youtube(query)
                if not audio_url:
                    self.logger.error(f"❌ No YouTube results found")
                    return False
            else:
                audio_url = query
            
            self.current_query = query
            
            # Build mpv command
            mpv_cmd = [self.mpv_path]
            
            # Add sink for Bluetooth if configured
            if self.sink_name:
                mpv_cmd.extend(['--audio-device', f'pulse/{self.sink_name}'])
                self.logger.info(f"🔊 Using audio device: {self.sink_name}")
            
            # Volume control
            mpv_cmd.extend(['--volume', str(int(volume * 100))])
            
            # Other options
            mpv_cmd.extend(['--no-video', '--really-quiet', audio_url])
            
            # Start playback
            self.logger.info(f"▶️ Starting playback with: {' '.join(mpv_cmd)}")
            self.current_process = subprocess.Popen(
                mpv_cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True
            )
            
            self._active = True
            self.logger.info(f"✅ Audio playback started")
            return True
            
        except Exception as e:
            self.logger.error(f"❌ Activation error: {e}")
            return False
    
    async def deactivate(self) -> bool:
        """Stop playback"""
        try:
            if self.current_process and self.current_process.poll() is None:
                self.current_process.terminate()
                await asyncio.sleep(0.2)
                
                if self.current_process.poll() is None:
                    self.current_process.kill()
                
                self._active = False
                self.logger.info("⏹️ Audio playback stopped")
            
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
    
    async def _search_youtube(self, query: str) -> Optional[str]:
        """Search YouTube using yt-dlp and return audio stream URL"""
        try:
            ydl_opts = {
                'format': 'bestaudio[ext=m4a]/bestaudio[ext=mp3]/bestaudio',
                'quiet': True,
                'no_warnings': True,
                'extract_flat': False,
                'default_search': 'ytsearch1',
            }
            
            # Try to use yt-dlp command line
            cmd = [self.yt_dlp_path, '-f', 'bestaudio', '-q', '-j', f'ytsearch1:{query}']
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
            
            if result.returncode == 0:
                import json
                data = json.loads(result.stdout)
                if 'url' in data:
                    self.logger.info(f"✅ Found: {data.get('title', 'Unknown')}")
                    return data['url']
            
            self.logger.error(f"❌ yt-dlp search failed: {result.stderr}")
            return None
            
        except Exception as e:
            self.logger.error(f"❌ YouTube search error: {e}")
            return None
