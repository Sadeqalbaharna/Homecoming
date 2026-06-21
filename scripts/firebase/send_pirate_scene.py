#!/usr/bin/env python3
"""
Send a pirate ship scene JSON to Firebase and trigger Pi execution
Tests the full pipeline: JSON → Firebase → Pi audio/lighting
"""

import json
import time
import logging
from pathlib import Path
import requests
from datetime import datetime

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Firebase config
FIREBASE_PROJECT_ID = "homecoming-kai"
FIREBASE_DB_URL = f"https://{FIREBASE_PROJECT_ID}.firebaseio.com"

# Pi config
PI_IP = "192.168.48.5"
PI_PORT = 5000


def load_scene_json(filepath: str) -> dict:
    """Load scene JSON from file"""
    with open(filepath, 'r') as f:
        scene = json.load(f)
    logger.info(f"✅ Loaded scene: {scene['scene']['name']}")
    return scene


def send_to_firebase(scene: dict) -> bool:
    """Send scene to Firebase Firestore via REST API"""
    try:
        # Build Firestore REST endpoint
        scene_id = scene["id"]
        url = f"{FIREBASE_DB_URL}/scene_prompts/{scene_id}.json"
        
        logger.info(f"📤 Sending scene to Firebase: {url}")
        logger.info(f"   Scene: {scene['scene']['name']}")
        logger.info(f"   Audio: {scene['audio']['query']}")
        logger.info(f"   Lighting: {scene['lighting']['strips'][0]['animation']}")
        logger.info(f"   Volume: {scene['audio']['volume_percent']}%")
        
        response = requests.put(url, json=scene, timeout=10)
        
        if response.status_code == 200:
            logger.info(f"✅ Scene stored in Firebase")
            return True
        else:
            logger.error(f"❌ Firebase error: {response.status_code} - {response.text}")
            return False
            
    except Exception as e:
        logger.error(f"❌ Failed to send to Firebase: {e}")
        return False


def wait_for_execution(scene_id: str, timeout_seconds: int = 60) -> bool:
    """Poll Firebase to watch scene execution status"""
    try:
        url = f"{FIREBASE_DB_URL}/scene_prompts/{scene_id}.json"
        start_time = time.time()
        
        logger.info(f"\n⏳ Waiting for Pi to execute scene (timeout: {timeout_seconds}s)...")
        logger.info("=" * 70)
        
        while time.time() - start_time < timeout_seconds:
            response = requests.get(url, timeout=10)
            
            if response.status_code == 200:
                data = response.json()
                if data and "execution" in data:
                    status = data["execution"]["status"]
                    
                    if status == "pending":
                        print("⏳ Status: PENDING (waiting for Pi...)", end='\r')
                    elif status == "executing":
                        logger.info("✅ Status: EXECUTING - Scene is now running!")
                        logger.info(f"   🔊 Audio: {data['audio']['query']}")
                        logger.info(f"   💡 Lighting: {data['lighting']['strips'][0]['animation']}")
                        logger.info(f"   🎵 Volume: {data['audio']['volume_percent']}%")
                        return True
                    elif status == "completed":
                        logger.info("✅ Status: COMPLETED - Scene finished!")
                        return True
                    elif status == "error":
                        error_msg = data["execution"].get("error", "Unknown error")
                        logger.error(f"❌ Status: ERROR - {error_msg}")
                        return False
            
            time.sleep(1)
        
        logger.warning(f"⏱️  Timeout reached after {timeout_seconds}s")
        logger.info("   Pi may still be executing. Check manually with:")
        logger.info(f"   ssh pi@{PI_IP} 'ps aux | grep mpv'")
        return False
        
    except Exception as e:
        logger.error(f"❌ Failed to poll Firebase: {e}")
        return False


def main():
    """Main flow: Load scene → Send to Firebase → Wait for Pi execution"""
    
    logger.info("=" * 70)
    logger.info("🏴‍☠️  PIRATE SHIP SCENE ACTIVATION".center(70))
    logger.info("=" * 70)
    logger.info("")
    
    # Step 1: Load scene JSON
    scene_file = Path(__file__).parent / "pirate_ship_scene.json"
    if not scene_file.exists():
        logger.error(f"❌ Scene file not found: {scene_file}")
        return False
    
    scene = load_scene_json(str(scene_file))
    
    # Step 2: Send to Firebase
    logger.info("")
    if not send_to_firebase(scene):
        return False
    
    # Step 3: Wait for Pi to execute
    logger.info("")
    success = wait_for_execution(scene["id"])
    
    logger.info("")
    logger.info("=" * 70)
    if success:
        logger.info("🏴‍☠️  SCENE ACTIVATED! 🎵".center(70))
        logger.info("Listen for pirate ship ambiance on your Bluetooth speaker...".center(70))
    else:
        logger.warning("⚠️  Scene may not have executed. Check Pi connection.".center(70))
    logger.info("=" * 70)
    
    return success


if __name__ == "__main__":
    main()
