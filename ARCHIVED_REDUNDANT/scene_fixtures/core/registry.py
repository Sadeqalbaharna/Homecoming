"""
Central fixture registry - tracks all fixtures and their configuration
"""

from typing import Dict, Optional, List
from dataclasses import dataclass
import logging
import json

logger = logging.getLogger(__name__)


@dataclass
class FixtureRecord:
    """Server record of a fixture's configuration and state"""
    fixture_id: str
    fixture_type: str
    location: str
    pi_ip: str  # IP of Pi hosting this fixture
    
    # Hardware
    input_drivers: List[Dict] = None  # [{driver_id, driver_type, params}]
    output_drivers: List[Dict] = None  # [{driver_id, driver_type, params}]
    
    # State
    is_online: bool = False
    last_seen: Optional[str] = None
    error_message: Optional[str] = None
    
    def __post_init__(self):
        if self.input_drivers is None:
            self.input_drivers = []
        if self.output_drivers is None:
            self.output_drivers = []


class FixtureRegistry:
    """
    Central registry of all smart fixtures.
    In production, this would be a database or Firebase collection.
    For now, it's an in-memory dict with JSON persistence.
    """
    
    def __init__(self, config_file: Optional[str] = None):
        self.fixtures: Dict[str, FixtureRecord] = {}
        self.config_file = config_file
        self.logger = logging.getLogger("FixtureRegistry")
        
        if config_file:
            self.load_from_file(config_file)
    
    def register(self, record: FixtureRecord) -> bool:
        """Register a fixture in the registry"""
        try:
            self.fixtures[record.fixture_id] = record
            self.logger.info(f"✅ Registered fixture: {record.fixture_id}")
            return True
        except Exception as e:
            self.logger.error(f"❌ Failed to register fixture: {e}")
            return False
    
    def get(self, fixture_id: str) -> Optional[FixtureRecord]:
        """Get a fixture record by ID"""
        return self.fixtures.get(fixture_id)
    
    def list_by_location(self, location: str) -> List[FixtureRecord]:
        """Get all fixtures at a location"""
        return [f for f in self.fixtures.values() if f.location == location]
    
    def list_by_pi(self, pi_ip: str) -> List[FixtureRecord]:
        """Get all fixtures running on a specific Pi"""
        return [f for f in self.fixtures.values() if f.pi_ip == pi_ip]
    
    def list_all(self) -> List[FixtureRecord]:
        """Get all fixtures"""
        return list(self.fixtures.values())
    
    def update_status(self, fixture_id: str, is_online: bool, error: Optional[str] = None):
        """Update fixture status"""
        if fixture_id not in self.fixtures:
            self.logger.warning(f"⚠️  Fixture not found: {fixture_id}")
            return
        
        record = self.fixtures[fixture_id]
        record.is_online = is_online
        record.error_message = error
        
        if is_online:
            self.logger.info(f"✅ {fixture_id} is online")
        else:
            self.logger.warning(f"⚠️  {fixture_id} is offline: {error}")
    
    def save_to_file(self, filepath: str):
        """Save registry to JSON file"""
        try:
            data = {
                fixture_id: {
                    'fixture_id': record.fixture_id,
                    'fixture_type': record.fixture_type,
                    'location': record.location,
                    'pi_ip': record.pi_ip,
                    'input_drivers': record.input_drivers,
                    'output_drivers': record.output_drivers,
                }
                for fixture_id, record in self.fixtures.items()
            }
            
            with open(filepath, 'w') as f:
                json.dump(data, f, indent=2)
            
            self.logger.info(f"💾 Saved {len(self.fixtures)} fixtures to {filepath}")
        except Exception as e:
            self.logger.error(f"❌ Failed to save registry: {e}")
    
    def load_from_file(self, filepath: str):
        """Load registry from JSON file"""
        try:
            with open(filepath, 'r') as f:
                data = json.load(f)
            
            for fixture_id, fixture_data in data.items():
                record = FixtureRecord(
                    fixture_id=fixture_data['fixture_id'],
                    fixture_type=fixture_data['fixture_type'],
                    location=fixture_data['location'],
                    pi_ip=fixture_data['pi_ip'],
                    input_drivers=fixture_data.get('input_drivers', []),
                    output_drivers=fixture_data.get('output_drivers', []),
                )
                self.fixtures[fixture_id] = record
            
            self.logger.info(f"✅ Loaded {len(self.fixtures)} fixtures from {filepath}")
        except Exception as e:
            self.logger.error(f"❌ Failed to load registry: {e}")
