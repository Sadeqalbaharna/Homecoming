"""
Test harness for modular fixtures
Provides utilities for testing individual components and end-to-end workflows
"""

import asyncio
import logging
from typing import List, Optional, Callable
from dataclasses import dataclass
from datetime import datetime

logger = logging.getLogger(__name__)


@dataclass
class TestResult:
    """Result of a single test"""
    test_name: str
    passed: bool
    message: str
    duration_ms: float
    timestamp: datetime = None
    
    def __post_init__(self):
        if self.timestamp is None:
            self.timestamp = datetime.now()


class FixtureTestHarness:
    """
    Test framework for fixtures.
    Allows you to test:
    1. Individual drivers (initialization, activation)
    2. Input handling (send input, verify outputs)
    3. End-to-end workflows
    """
    
    def __init__(self, fixture_instance):
        self.fixture = fixture_instance
        self.results: List[TestResult] = []
        self.logger = logging.getLogger(f"TestHarness.{fixture_instance.config.fixture_id}")
    
    async def test_initialization(self) -> bool:
        """Test that fixture initializes correctly"""
        test_name = "Fixture Initialization"
        start = asyncio.get_event_loop().time()
        
        try:
            success = await self.fixture.initialize()
            
            if not success:
                self._record_result(test_name, False, "Initialization returned False", start)
                return False
            
            if not self.fixture.is_ready:
                self._record_result(test_name, False, "Fixture not ready after init", start)
                return False
            
            self._record_result(test_name, True, "Fixture initialized successfully", start)
            return True
            
        except Exception as e:
            self._record_result(test_name, False, f"Exception: {e}", start)
            return False
    
    async def test_output_driver(self, driver_id: str) -> bool:
        """Test that an output driver can activate and deactivate"""
        test_name = f"Output Driver: {driver_id}"
        start = asyncio.get_event_loop().time()
        
        try:
            if driver_id not in self.fixture.output_drivers:
                self._record_result(test_name, False, f"Driver '{driver_id}' not found", start)
                return False
            
            driver = self.fixture.output_drivers[driver_id]
            
            # Test activation
            success = await driver.activate({})
            if not success:
                self._record_result(test_name, False, "Activation failed", start)
                return False
            
            # Test deactivation
            success = await driver.deactivate()
            if not success:
                self._record_result(test_name, False, "Deactivation failed", start)
                return False
            
            self._record_result(test_name, True, f"Driver {driver_id} working", start)
            return True
            
        except Exception as e:
            self._record_result(test_name, False, f"Exception: {e}", start)
            return False
    
    async def test_voice_input_to_output(
        self, 
        text_input: str,
        expected_outputs: List[str],
        timeout_s: float = 5.0
    ) -> bool:
        """
        Test end-to-end: voice input -> fixture processing -> output activation
        
        Args:
            text_input: Voice command text
            expected_outputs: List of driver IDs that should be activated
            timeout_s: How long to wait for outputs
        """
        test_name = f"Voice Input: '{text_input}'"
        start = asyncio.get_event_loop().time()
        
        try:
            from ..core.fixture_base import InputEvent
            
            # Send input
            event = InputEvent(
                source="voice",
                event_type="command",
                data={"text": text_input}
            )
            
            success = await self.fixture.receive_input(event)
            if not success:
                self._record_result(test_name, False, "receive_input returned False", start)
                return False
            
            # Wait for outputs to be activated
            async def check_outputs(timeout_s):
                elapsed = 0
                while elapsed < timeout_s:
                    activated = self.fixture.active_outputs
                    if all(driver_id in activated for driver_id in expected_outputs):
                        return True
                    await asyncio.sleep(0.1)
                    elapsed += 0.1
                return False
            
            if not await check_outputs(timeout_s):
                actual = self.fixture.active_outputs
                message = f"Expected {expected_outputs}, got {actual}"
                self._record_result(test_name, False, message, start)
                return False
            
            message = f"Input processed correctly, outputs: {self.fixture.active_outputs}"
            self._record_result(test_name, True, message, start)
            return True
            
        except Exception as e:
            self._record_result(test_name, False, f"Exception: {e}", start)
            return False
    
    def _record_result(self, test_name: str, passed: bool, message: str, start_time: float):
        """Record test result"""
        duration_ms = (asyncio.get_event_loop().time() - start_time) * 1000
        result = TestResult(test_name, passed, message, duration_ms)
        self.results.append(result)
        
        status = "✅ PASS" if passed else "❌ FAIL"
        self.logger.info(f"{status}: {test_name} ({duration_ms:.1f}ms) - {message}")
    
    def print_summary(self):
        """Print test summary"""
        if not self.results:
            print("\nNo tests run")
            return
        
        passed = sum(1 for r in self.results if r.passed)
        failed = sum(1 for r in self.results if not r.passed)
        total_time = sum(r.duration_ms for r in self.results)
        
        print("\n" + "="*80)
        print(f"TEST SUMMARY: {self.fixture.config.fixture_id}".center(80))
        print("="*80)
        
        for result in self.results:
            status = "✅" if result.passed else "❌"
            print(f"{status} {result.test_name:40} ({result.duration_ms:6.1f}ms)")
            if result.message:
                print(f"   └─ {result.message}")
        
        print("="*80)
        print(f"Results: {passed} passed, {failed} failed, {total_time:.1f}ms total")
        print("="*80 + "\n")
        
        return failed == 0


async def run_basic_test_suite(fixture_instance) -> bool:
    """
    Run a basic test suite on a fixture.
    Returns True if all tests pass.
    """
    harness = FixtureTestHarness(fixture_instance)
    
    # Test 1: Initialization
    await harness.test_initialization()
    
    # Test 2: Output drivers
    for driver_id in fixture_instance.output_drivers.keys():
        await harness.test_output_driver(driver_id)
    
    harness.print_summary()
    return all(r.passed for r in harness.results)
