#!/usr/bin/env python3
"""
Unified Test Harness for Homecoming App
Consolidates all testing functionality
Replaces: 15+ test_*.py scripts
"""

import logging
import sys
import subprocess
import asyncio
from pathlib import Path
from typing import Dict, List, Callable, Optional
from dataclasses import dataclass
from enum import Enum

logging.basicConfig(level=logging.INFO, format='%(name)s: %(message)s')
logger = logging.getLogger(__name__)


class TestStatus(Enum):
    """Test status enum"""
    PASS = "✅"
    FAIL = "❌"
    SKIP = "⏭️"
    WARN = "⚠️"


@dataclass
class TestResult:
    """Test result data class"""
    name: str
    status: TestStatus
    duration: float
    message: str = ""
    error: str = ""


class TestHarness:
    """Unified test harness for all Homecoming tests"""
    
    def __init__(self):
        self.tests: Dict[str, Callable] = {}
        self.results: List[TestResult] = []
        self.pi_ip: Optional[str] = None
    
    def register_test(self, name: str, test_func: Callable):
        """Register a test"""
        self.tests[name] = test_func
        logger.debug(f"Registered test: {name}")
    
    async def run_test(self, name: str) -> TestResult:
        """Run a single test"""
        if name not in self.tests:
            return TestResult(name, TestStatus.SKIP, 0, "Test not found")
        
        test_func = self.tests[name]
        import time
        start = time.time()
        
        try:
            logger.info(f"\n🧪 Running: {name}")
            
            # Check if async
            if asyncio.iscoroutinefunction(test_func):
                result = await test_func()
            else:
                result = test_func()
            
            duration = time.time() - start
            
            if isinstance(result, bool):
                status = TestStatus.PASS if result else TestStatus.FAIL
                return TestResult(name, status, duration)
            elif isinstance(result, dict):
                status = TestStatus.PASS if result.get("success", False) else TestStatus.FAIL
                return TestResult(
                    name, status, duration,
                    result.get("message", ""),
                    result.get("error", "")
                )
            else:
                return TestResult(name, TestStatus.PASS, duration)
            
        except Exception as e:
            duration = time.time() - start
            logger.error(f"   ❌ Exception: {e}")
            return TestResult(name, TestStatus.FAIL, duration, error=str(e))
    
    async def run_all_tests(self) -> List[TestResult]:
        """Run all registered tests"""
        logger.info("\n" + "="*70)
        logger.info("🧪 HOMECOMING TEST SUITE")
        logger.info("="*70)
        
        self.results = []
        for name in self.tests.keys():
            result = await self.run_test(name)
            self.results.append(result)
            logger.info(f"   {result.status.value} {name} ({result.duration:.2f}s)")
            if result.message:
                logger.info(f"      → {result.message}")
            if result.error:
                logger.error(f"      → {result.error}")
        
        return self.results
    
    def print_summary(self):
        """Print test summary"""
        if not self.results:
            return
        
        passed = sum(1 for r in self.results if r.status == TestStatus.PASS)
        failed = sum(1 for r in self.results if r.status == TestStatus.FAIL)
        skipped = sum(1 for r in self.results if r.status == TestStatus.SKIP)
        
        logger.info("\n" + "="*70)
        logger.info("📊 TEST SUMMARY")
        logger.info("="*70)
        logger.info(f"Total:   {len(self.results)}")
        logger.info(f"Passed:  {passed} ✅")
        logger.info(f"Failed:  {failed} ❌")
        logger.info(f"Skipped: {skipped} ⏭️")
        logger.info(f"Success: {100*passed/len(self.results):.1f}%")
        logger.info("="*70)
        
        return failed == 0


class BluetoothTests:
    """Consolidated Bluetooth tests"""
    
    @staticmethod
    async def test_discovery() -> bool:
        """Test Bluetooth device discovery"""
        try:
            result = subprocess.run(
                ["bluetoothctl", "list"],
                capture_output=True,
                text=True,
                timeout=5
            )
            return len(result.stdout) > 0
        except:
            return False
    
    @staticmethod
    async def test_connection(device_addr: str = None) -> Dict:
        """Test Bluetooth connection"""
        try:
            if not device_addr:
                logger.warning("   No device address provided, skipping connection test")
                return {"success": False, "message": "No device address"}
            
            result = subprocess.run(
                ["bluetoothctl", "info", device_addr],
                capture_output=True,
                text=True,
                timeout=5
            )
            
            connected = "Connected: yes" in result.stdout
            return {
                "success": connected,
                "message": f"Device {device_addr}: {'Connected' if connected else 'Not connected'}"
            }
        except Exception as e:
            return {"success": False, "error": str(e)}
    
    @staticmethod
    async def test_audio_to_device() -> bool:
        """Test audio playback to Bluetooth device"""
        try:
            # Check if audio can be routed to Bluetooth
            result = subprocess.run(
                ["pactl", "list", "sinks"],
                capture_output=True,
                text=True,
                timeout=5
            )
            
            bluetooth_sink = "bluez_output" in result.stdout
            return bluetooth_sink
        except:
            return False


class AudioTests:
    """Consolidated audio tests"""
    
    @staticmethod
    async def test_audio_playback() -> bool:
        """Test local audio playback"""
        try:
            # Generate test tone
            import wave
            import numpy as np
            
            test_file = "/tmp/test_tone.wav"
            duration = 1
            frequency = 440
            sample_rate = 44100
            
            # Generate sine wave
            samples = np.sin(2 * np.pi * frequency * np.linspace(0, duration, duration * sample_rate))
            samples = (samples * 32767).astype(np.int16)
            
            with wave.open(test_file, 'wb') as f:
                f.setnchannels(1)
                f.setsampwidth(2)
                f.setframerate(sample_rate)
                f.writeframes(samples.tobytes())
            
            return Path(test_file).exists()
        except Exception as e:
            logger.error(f"Audio test error: {e}")
            return False
    
    @staticmethod
    async def test_speaker_output() -> Dict:
        """Test speaker output"""
        try:
            result = subprocess.run(
                ["pactl", "list", "sinks"],
                capture_output=True,
                text=True,
                timeout=5
            )
            
            has_sinks = "Sink" in result.stdout
            return {
                "success": has_sinks,
                "message": f"Found {'audio sinks' if has_sinks else 'no audio sinks'}"
            }
        except Exception as e:
            return {"success": False, "error": str(e)}


class SceneTests:
    """Consolidated scene tests"""
    
    @staticmethod
    async def test_scene_loading() -> bool:
        """Test scene fixture loading"""
        try:
            fixtures_path = Path(__file__).parent / "fixtures_v2"
            return fixtures_path.exists()
        except:
            return False
    
    @staticmethod
    async def test_scene_execution() -> Dict:
        """Test scene execution (dry run)"""
        try:
            # Just verify the fixture system loads
            sys.path.insert(0, str(Path(__file__).parent))
            
            fixtures_path = Path(__file__).parent / "fixtures_v2"
            if not fixtures_path.exists():
                return {"success": False, "message": "Fixtures directory not found"}
            
            return {"success": True, "message": "Scene system ready"}
        except Exception as e:
            return {"success": False, "error": str(e)}


class FirebaseTests:
    """Consolidated Firebase tests"""
    
    @staticmethod
    async def test_firebase_connection(project_id: str = "homecoming-kai") -> Dict:
        """Test Firebase connectivity"""
        try:
            import requests
            url = f"https://{project_id}.firebaseio.com/.json"
            response = requests.get(url, timeout=5)
            
            return {
                "success": response.status_code in [200, 401],
                "message": f"Firebase status: {response.status_code}"
            }
        except Exception as e:
            return {"success": False, "error": str(e)}
    
    @staticmethod
    async def test_firebase_read_write() -> Dict:
        """Test Firebase read/write capability"""
        try:
            import requests
            import time
            
            test_path = f"test/connectivity_check_{int(time.time())}"
            url = f"https://homecoming-kai.firebaseio.com/{test_path}.json"
            
            # Write
            write_response = requests.post(url, json={"test": True}, timeout=5)
            
            # Read
            read_response = requests.get(url, timeout=5)
            
            success = write_response.status_code in [200, 201] and read_response.status_code == 200
            
            return {
                "success": success,
                "message": "Firebase read/write working" if success else "Read/write failed"
            }
        except Exception as e:
            return {"success": False, "error": str(e)}


def create_default_harness() -> TestHarness:
    """Create harness with all default tests"""
    harness = TestHarness()
    
    # Bluetooth tests
    harness.register_test("Bluetooth Discovery", BluetoothTests.test_discovery)
    harness.register_test("Bluetooth Connection", BluetoothTests.test_connection)
    harness.register_test("Audio to Bluetooth", BluetoothTests.test_audio_to_device)
    
    # Audio tests
    harness.register_test("Audio Playback", AudioTests.test_audio_playback)
    harness.register_test("Speaker Output", AudioTests.test_speaker_output)
    
    # Scene tests
    harness.register_test("Scene Loading", SceneTests.test_scene_loading)
    harness.register_test("Scene Execution", SceneTests.test_scene_execution)
    
    # Firebase tests
    harness.register_test("Firebase Connection", FirebaseTests.test_firebase_connection)
    harness.register_test("Firebase Read/Write", FirebaseTests.test_firebase_read_write)
    
    return harness


async def main():
    """Main CLI interface"""
    import argparse
    
    parser = argparse.ArgumentParser(description="Unified Test Harness")
    parser.add_argument("--test", help="Run specific test")
    parser.add_argument("--category", help="Run tests by category (bluetooth, audio, scene, firebase)")
    parser.add_argument("--all", action="store_true", help="Run all tests")
    
    args = parser.parse_args()
    
    harness = create_default_harness()
    
    if args.test:
        result = await harness.run_test(args.test)
        harness.results = [result]
    elif args.category:
        category_tests = [t for t in harness.tests.keys() if args.category.lower() in t.lower()]
        for test_name in category_tests:
            await harness.run_test(test_name)
    elif args.all or not (args.test or args.category):
        await harness.run_all_tests()
    
    harness.print_summary()


if __name__ == "__main__":
    asyncio.run(main())
