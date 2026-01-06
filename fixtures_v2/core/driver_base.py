"""
Base classes for input and output drivers
Provides pluggable abstraction for hardware and external inputs
"""

from abc import ABC, abstractmethod
from dataclasses import dataclass
from enum import Enum
from typing import Any, Dict, Optional
import logging

logger = logging.getLogger(__name__)


class DriverType(Enum):
    """Types of drivers"""
    INPUT = "input"
    OUTPUT = "output"


@dataclass
class DriverConfig:
    """Configuration for a driver"""
    driver_id: str  # Unique ID like "speaker_1", "led_strip_main", "motion_sensor"
    driver_type: str  # "audio", "led", "motor", "fog", "haptic", "voice", "motion", etc.
    enabled: bool = True
    params: Dict[str, Any] = None  # Driver-specific config (gpio_pin, sink_name, etc.)
    
    def __post_init__(self):
        if self.params is None:
            self.params = {}


class InputDriver(ABC):
    """
    Abstract base for input drivers.
    A fixture can have multiple input drivers (voice, sensors, app, touch, etc.)
    """
    
    def __init__(self, config: DriverConfig):
        self.config = config
        self.logger = logging.getLogger(f"InputDriver.{config.driver_id}")
        
    @abstractmethod
    async def start(self) -> bool:
        """Start listening for input. Return True if successful."""
        pass
    
    @abstractmethod
    async def stop(self):
        """Stop listening for input."""
        pass
    
    @abstractmethod
    async def is_ready(self) -> bool:
        """Check if driver is ready to receive/send input."""
        pass


class OutputDriver(ABC):
    """
    Abstract base for output drivers.
    A fixture can have multiple output drivers (LEDs, speakers, motors, fog, haptics, etc.)
    """
    
    def __init__(self, config: DriverConfig):
        self.config = config
        self.logger = logging.getLogger(f"OutputDriver.{config.driver_id}")
        self._active = False
        
    @abstractmethod
    async def initialize(self) -> bool:
        """Initialize hardware. Return True if successful."""
        pass
    
    @abstractmethod
    async def activate(self, params: Dict[str, Any]) -> bool:
        """
        Activate the output with given parameters.
        Return True if activation successful.
        
        Example params:
        - LED: {"color": (255, 0, 0), "brightness": 255, "effect": "pulse"}
        - Audio: {"query": "tavern music", "volume": 0.8}
        - Motor: {"speed": 100, "duration_ms": 5000}
        - Fog: {"duration_ms": 3000, "intensity": 0.8}
        """
        pass
    
    @abstractmethod
    async def deactivate(self) -> bool:
        """Deactivate the output. Return True if successful."""
        pass
    
    @abstractmethod
    async def is_ready(self) -> bool:
        """Check if driver is ready to activate."""
        pass
    
    @property
    def is_active(self) -> bool:
        """Check if output is currently active"""
        return self._active


# Common output activation parameters
class LEDParams:
    """LED output parameters"""
    color: tuple  # (R, G, B) 0-255
    brightness: int  # 0-255
    effect: str  # "static", "pulse", "strobe", "flicker", "shimmer", "fade", "breathe", "warm"
    duration_ms: Optional[int] = None  # How long to run effect, None = indefinite


class AudioParams:
    """Audio output parameters"""
    query: str  # YouTube search query or file path
    volume: float  # 0.0-1.0
    duration_ms: Optional[int] = None  # How long to play, None = full file


class MotorParams:
    """Motor/mechanical output parameters"""
    speed: int  # 0-255
    duration_ms: int  # How long to run


class FogParams:
    """Fog machine output parameters"""
    duration_ms: int  # How long to fog
    intensity: float  # 0.0-1.0
