"""
Base fixture class that all smart fixtures inherit from.
Handles input→processing→output lifecycle.
"""

from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Dict, List, Optional, Callable
import logging
from datetime import datetime

logger = logging.getLogger(__name__)


class FixtureType(Enum):
    """Types of fixtures in the restaurant"""
    DINING_TABLE = "dining_table"
    WALL = "wall"
    DOOR = "door"
    AMBIENT_LIGHT = "ambient_light"
    DECOR = "decor"


class FixtureState(Enum):
    """States a fixture can be in"""
    INITIALIZING = "initializing"
    READY = "ready"
    ACTIVE = "active"
    ERROR = "error"
    OFFLINE = "offline"


@dataclass
class InputEvent:
    """Input event from any source"""
    source: str  # "voice", "sensor", "app", "touch", etc.
    event_type: str  # "command", "state_change", "alert", etc.
    data: Dict[str, Any]
    timestamp: datetime = field(default_factory=datetime.now)
    
    def __str__(self):
        return f"InputEvent({self.source}/{self.event_type}: {self.data})"


@dataclass
class OutputCommand:
    """Command to activate an output"""
    driver_id: str  # Which driver to activate ("led_main", "speaker_1", etc.)
    action: str  # "activate", "deactivate", "update"
    params: Dict[str, Any] = field(default_factory=dict)
    duration_ms: Optional[int] = None  # How long to run
    
    def __str__(self):
        return f"OutputCommand({self.driver_id}/{self.action})"


@dataclass
class FixtureConfig:
    """Configuration for a fixture"""
    fixture_id: str  # Unique ID like "table_1", "wall_tavern", etc.
    fixture_type: FixtureType
    location: str  # "dining_area", "bar", "entryway", etc.
    
    # Hardware configuration
    input_drivers: List[Dict[str, Any]] = field(default_factory=list)  # Driver configs
    output_drivers: List[Dict[str, Any]] = field(default_factory=list)  # Driver configs
    
    # Behavior configuration
    personality: Optional[Dict[str, Any]] = None  # AI personality params
    enabled: bool = True


class BaseFixture(ABC):
    """
    Base class for all smart fixtures.
    
    Lifecycle:
    1. Create instance with config
    2. Call initialize() → loads and tests all drivers
    3. Start listening for input
    4. Input → analyze → activate outputs
    5. Call shutdown() → cleanup
    """
    
    def __init__(self, config: FixtureConfig):
        self.config = config
        self.logger = logging.getLogger(f"Fixture.{config.fixture_id}")
        
        self.state = FixtureState.INITIALIZING
        self.input_drivers: Dict[str, Any] = {}  # Will be populated by subclasses
        self.output_drivers: Dict[str, Any] = {}  # Will be populated by subclasses
        
        # Input handling
        self._input_callbacks: List[Callable] = []  # Process input handlers
        
        # State tracking
        self.last_input: Optional[InputEvent] = None
        self.last_output: Optional[OutputCommand] = None
        self.active_outputs: List[str] = []  # Which drivers are currently active
        
        self.logger.info(f"🎭 Fixture created: {config.fixture_id} ({config.fixture_type.value}) at {config.location}")
    
    @abstractmethod
    async def initialize(self) -> bool:
        """
        Initialize all drivers and prepare for operation.
        Subclasses should:
        1. Create input drivers
        2. Create output drivers
        3. Test all hardware
        4. Return True if all ready
        """
        pass
    
    @abstractmethod
    async def process_input(self, event: InputEvent) -> List[OutputCommand]:
        """
        Process input and decide what outputs to trigger.
        
        Args:
            event: The input event
            
        Returns:
            List of output commands to execute
            
        Example:
            If event = InputEvent(source="voice", data={"text": "play tavern music"}):
            Return [
                OutputCommand("led_main", "activate", {"color": (255,140,0), "effect": "warm"}),
                OutputCommand("speaker_1", "activate", {"query": "tavern music"})
            ]
        """
        pass
    
    async def receive_input(self, event: InputEvent) -> bool:
        """
        Receive input from any source and process it.
        
        Returns True if input was processed, False if ignored/error
        """
        try:
            self.logger.info(f"📥 Input received: {event}")
            self.last_input = event
            
            # Call any registered input callbacks
            for callback in self._input_callbacks:
                await callback(event)
            
            # Process input and get output commands
            commands = await self.process_input(event)
            
            # Execute output commands
            for command in commands:
                await self.execute_output(command)
            
            return True
            
        except Exception as e:
            self.logger.error(f"❌ Error processing input: {e}")
            return False
    
    async def execute_output(self, command: OutputCommand) -> bool:
        """
        Execute an output command using the specified driver.
        """
        try:
            driver_id = command.driver_id
            
            if driver_id not in self.output_drivers:
                self.logger.error(f"❌ Unknown output driver: {driver_id}")
                return False
            
            driver = self.output_drivers[driver_id]
            self.logger.info(f"🎬 Executing: {command}")
            
            if command.action == "activate":
                success = await driver.activate(command.params)
                if success:
                    self.active_outputs.append(driver_id)
                    self.last_output = command
                return success
                
            elif command.action == "deactivate":
                success = await driver.deactivate()
                if success and driver_id in self.active_outputs:
                    self.active_outputs.remove(driver_id)
                return success
            
            else:
                self.logger.error(f"❌ Unknown action: {command.action}")
                return False
                
        except Exception as e:
            self.logger.error(f"❌ Error executing output: {e}")
            return False
    
    async def shutdown(self):
        """Gracefully shut down all drivers"""
        self.logger.info(f"🛑 Shutting down fixture...")
        
        # Deactivate all outputs
        for output_id in list(self.active_outputs):
            try:
                await self.execute_output(OutputCommand(output_id, "deactivate"))
            except Exception as e:
                self.logger.error(f"Error deactivating {output_id}: {e}")
        
        # Stop all input drivers
        for driver_id, driver in self.input_drivers.items():
            try:
                await driver.stop()
            except Exception as e:
                self.logger.error(f"Error stopping input driver {driver_id}: {e}")
        
        self.state = FixtureState.OFFLINE
        self.logger.info("✅ Fixture shutdown complete")
    
    def register_input_callback(self, callback: Callable):
        """Register a callback to process input"""
        self._input_callbacks.append(callback)
    
    @property
    def is_ready(self) -> bool:
        return self.state == FixtureState.READY
    
    def __str__(self):
        return f"<{self.__class__.__name__} {self.config.fixture_id} ({self.state.value})>"
