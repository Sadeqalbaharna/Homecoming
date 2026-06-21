#!/usr/bin/env python3
"""
End-to-End Test: Homecoming App -> Fixture -> Audio Output
Tests the complete flow: Voice input -> Scene detection -> Music playback
"""

import asyncio
import sys
import logging
from pathlib import Path

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Fix imports for both Windows and Pi
sys.path.insert(0, str(Path(__file__).parent))

from fixtures_v2.fixtures.dining_table import DiningTableFixture
from fixtures_v2.core.fixture_base import FixtureConfig, FixtureType, InputEvent


async def test_end_to_end():
    """Test complete flow: input -> fixture -> audio output"""
    
    print("\n" + "="*80)
    print("END-TO-END TEST: Homecoming App Input -> Fixture -> Audio".center(80))
    print("="*80 + "\n")
    
    # Create the dining table fixture
    config = FixtureConfig(
        fixture_id="dining_table_1",
        fixture_type=FixtureType.DINING_TABLE,
        location="dining_room",
        enabled=True
    )
    
    fixture = DiningTableFixture(config)
    
    # Initialize
    print("🎭 Initializing dining table fixture...")
    if not await fixture.initialize():
        print("❌ Failed to initialize fixture")
        return False
    
    print("✅ Fixture initialized\n")
    
    # Simulate voice inputs from homecoming app
    test_inputs = [
        ("tavern music please", "🍺 Tavern Scene"),
        ("forest ambience", "🌲 Forest Scene"),
    ]
    
    for voice_text, scene_name in test_inputs:
        print(f"\n{'='*80}")
        print(f"📱 HOMECOMING APP SENDING: '{voice_text}'")
        print(f"{'='*80}\n")
        
        # Create an InputEvent from the homecoming app
        input_event = InputEvent(
            source="voice",
            event_type="command",
            data={"text": voice_text}
        )
        
        # Get the commands the fixture generates
        print(f"⏳ Processing voice input through fixture logic...")
        commands = await fixture.process_input(input_event)
        print(f"✅ Fixture generated {len(commands)} commands")
        
        # Execute the commands
        if commands:
            for cmd in commands:
                print(f"  - {cmd.driver_id}: {cmd.action}")
                await fixture.execute_output(cmd)
            
            print(f"\n🎵 Music should be playing on your speaker!")
            print(f"💡 LEDs should be lit with appropriate color for {scene_name}")
            
            # Listen for 10 seconds
            print(f"📻 Listening for 10 seconds...")
            await asyncio.sleep(10)
            
            # Stop playback
            print(f"⏹️  Stopping speaker...")
            if "speaker_1" in fixture.output_drivers:
                await fixture.output_drivers["speaker_1"].deactivate()
            await asyncio.sleep(1)
        else:
            print(f"⚠️  No commands generated (LED may not be available on this system)")
    
    print("\n" + "="*80)
    print("END-TO-END TEST COMPLETE".center(80))
    print("="*80)
    print("\n✅ If you saw LEDs light up and heard music, the fixture works!\n")
    
    return True


async def main():
    try:
        success = await test_end_to_end()
        sys.exit(0 if success else 1)
    except KeyboardInterrupt:
        print("\n\n⏹️  Test interrupted by user")
        sys.exit(0)
    except Exception as e:
        print(f"\n❌ Test failed with error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    asyncio.run(main())
