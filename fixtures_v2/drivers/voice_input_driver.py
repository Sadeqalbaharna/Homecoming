"""
Voice input driver - receives text input from Kai AI system
"""

import logging
from typing import Any, Dict, Optional
import asyncio
from queue import Queue

from ..core.driver_base import InputDriver, DriverConfig

logger = logging.getLogger(__name__)


class VoiceInputDriver(InputDriver):
    """
    Receive voice input as text from the Kai AI system.
    Acts as a queue that the fixture pulls from.
    """
    
    def __init__(self, config: DriverConfig):
        super().__init__(config)
        self.input_queue: asyncio.Queue = asyncio.Queue()
        self.is_listening = False
    
    async def start(self) -> bool:
        """Start listening for voice input"""
        self.is_listening = True
        self.logger.info("🎤 Voice input driver started")
        return True
    
    async def stop(self):
        """Stop listening"""
        self.is_listening = False
        self.logger.info("🎤 Voice input driver stopped")
    
    async def is_ready(self) -> bool:
        """Voice input is always ready"""
        return True
    
    async def send_input(self, text: str, metadata: Dict[str, Any] = None):
        """
        Called by the Kai AI system to send voice input to the fixture.
        This would be called via HTTP endpoint or Firebase.
        """
        try:
            event_data = {
                'text': text,
                'confidence': metadata.get('confidence', 1.0) if metadata else 1.0,
            }
            
            if metadata:
                event_data.update(metadata)
            
            await self.input_queue.put(event_data)
            self.logger.info(f"🎤 Voice input queued: {text}")
            
        except Exception as e:
            self.logger.error(f"❌ Error queuing input: {e}")
    
    async def get_input(self, timeout_ms: int = 5000) -> Optional[Dict[str, Any]]:
        """
        Get next input from queue.
        Fixture should call this in a loop to receive inputs.
        """
        try:
            timeout_s = timeout_ms / 1000.0
            data = await asyncio.wait_for(self.input_queue.get(), timeout=timeout_s)
            return data
        except asyncio.TimeoutError:
            return None
        except Exception as e:
            self.logger.error(f"❌ Error getting input: {e}")
            return None
