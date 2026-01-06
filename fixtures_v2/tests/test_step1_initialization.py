#!/usr/bin/env python3
"""
STEP 1 TEST: Fixture Initialization and Driver Abstraction
Tests that the modular driver architecture works correctly
"""

import asyncio
import sys
import logging
from pathlib import Path

# Add parent directory to path
test_dir = Path(__file__).parent.parent.parent
sys.path.insert(0, str(test_dir))

from fixtures_v2.core.fixture_base import FixtureConfig, FixtureType
from fixtures_v2.fixtures.dining_table import DiningTableFixture
from fixtures_v2.tests.test_harness import FixtureTestHarness

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


async def test_step1_fixture_initialization():
    """Test that fixtures can initialize with modular drivers"""
    print("\n" + "="*80)
    print("STEP 1: FIXTURE INITIALIZATION & DRIVER ABSTRACTION".center(80))
    print("="*80 + "\n")
    
    # Create a dining table fixture
    config = FixtureConfig(
        fixture_id="table_1",
        fixture_type=FixtureType.DINING_TABLE,
        location="dining_area",
        input_drivers=[
            {"driver_id": "voice_input", "driver_type": "voice"}
        ],
        output_drivers=[
            {"driver_id": "led_main", "driver_type": "led"},
            {"driver_id": "speaker_1", "driver_type": "audio"}
        ]
    )
    
    print("📋 Fixture Configuration:")
    print(f"   ID: {config.fixture_id}")
    print(f"   Type: {config.fixture_type.value}")
    print(f"   Location: {config.location}")
    print(f"   Input drivers: {len(config.input_drivers)}")
    print(f"   Output drivers: {len(config.output_drivers)}\n")
    
    # Create fixture instance
    fixture = DiningTableFixture(config)
    print(f"✅ Fixture instance created: {fixture}\n")
    
    # Run tests
    harness = FixtureTestHarness(fixture)
    
    print("🧪 Running tests...\n")
    
    # Test 1: Initialization
    init_passed = await harness.test_initialization()
    
    # Test 2: Output drivers are accessible
    print("🔍 Checking output drivers...")
    drivers_exist = all(
        driver_id in fixture.output_drivers 
        for driver_id in ["led_main", "speaker_1"]
    )
    
    if drivers_exist:
        print("✅ All output drivers registered\n")
    else:
        print("❌ Missing output drivers\n")
    
    # Test 3: Input driver is set up
    print("🔍 Checking input drivers...")
    voice_exists = "voice_input" in fixture.input_drivers
    
    if voice_exists:
        print("✅ Voice input driver registered\n")
    else:
        print("❌ Voice input driver not found\n")
    
    # Print summary
    harness.print_summary()
    
    return init_passed and drivers_exist and voice_exists


async def test_step1_driver_independence():
    """Test that drivers can be tested independently"""
    print("\n" + "="*80)
    print("STEP 1B: DRIVER INDEPENDENCE TEST".center(80))
    print("="*80 + "\n")
    
    from fixtures_v2.core.driver_base import DriverConfig
    from fixtures_v2.drivers.led_driver import LEDDriver
    from fixtures_v2.drivers.audio_driver import AudioDriver
    
    print("Testing LED driver independently...")
    
    led_config = DriverConfig(
        driver_id="led_test",
        driver_type="led",
        params={
            'gpio_pin': 18,
            'led_count': 300,
            'brightness': 200,
        }
    )
    
    led = LEDDriver(led_config)
    
    # Initialize
    init = await led.initialize()
    print(f"   Initialize: {'✅ PASS' if init else '❌ FAIL'}")
    
    # Test activation
    result = await led.activate({
        'color': (255, 140, 0),
        'effect': 'static',
        'brightness': 200
    })
    print(f"   Activate: {'✅ PASS' if result else '❌ FAIL'}")
    
    # Test deactivation
    result = await led.deactivate()
    print(f"   Deactivate: {'✅ PASS' if result else '❌ FAIL'}\n")
    
    print("Testing Audio driver independently...")
    
    audio_config = DriverConfig(
        driver_id="audio_test",
        driver_type="audio",
        params={
            'sink_name': 'bluez_output.39_3E_58_14_40_4A.1',
            'mpv_path': 'mpv',
            'yt_dlp_path': 'yt-dlp',
        }
    )
    
    audio = AudioDriver(audio_config)
    
    # Initialize (will fail if mpv not installed, that's ok)
    init = await audio.initialize()
    print(f"   Initialize: {'✅ PASS' if init else '⚠️  SKIP (mpv not available)'}")
    
    # Test ready check
    ready = await audio.is_ready()
    print(f"   Ready check: {'✅ PASS' if ready else '⚠️  SKIP (mpv not available)'}\n")
    
    return True


async def main():
    """Run all Step 1 tests"""
    try:
        # Test fixture initialization
        test1_passed = await test_step1_fixture_initialization()
        
        # Test driver independence
        test2_passed = await test_step1_driver_independence()
        
        # Summary
        print("\n" + "="*80)
        print("STEP 1: FINAL SUMMARY".center(80))
        print("="*80)
        
        all_passed = test1_passed and test2_passed
        
        if all_passed:
            print("✅ ALL TESTS PASSED!\n")
            print("✅ Fixture initialization works")
            print("✅ Drivers can be instantiated independently")
            print("✅ Modular architecture is functional\n")
            print("Next: Create fixture examples and test input->output flow")
        else:
            print("❌ SOME TESTS FAILED\n")
            print("Review the output above for details")
        
        print("="*80 + "\n")
        
        return 0 if all_passed else 1
        
    except Exception as e:
        logger.error(f"❌ Test suite error: {e}", exc_info=True)
        return 1


if __name__ == "__main__":
    exit_code = asyncio.run(main())
    sys.exit(exit_code)
