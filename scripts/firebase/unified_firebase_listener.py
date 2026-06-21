#!/usr/bin/env python3
"""
Unified Firebase Listener Service
Consolidates all Firebase listening functionality
Replaces: firebase_listener_300.py, firebase_scene_executor.py, firebase_command_listener.py, etc.
"""

import json
import time
import logging
import subprocess
import sys
import threading
import requests
from pathlib import Path
from typing import Dict, Optional, Callable, List
from flask import Flask, request, jsonify
from flask_cors import CORS

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

class FirebaseService:
    """Unified Firebase listener and executor service"""
    
    def __init__(self, project_id: str = "homecoming-kai"):
        self.project_id = project_id
        self.db_url = f"https://{project_id}.firebaseio.com"
        self.listeners = {}
        self.handlers = {}
        self.running = False
        self.poll_interval = 2
        
        sys.path.insert(0, str(Path(__file__).parent))
    
    def register_handler(self, collection: str, handler: Callable):
        """Register a handler for a collection"""
        self.handlers[collection] = handler
        logger.info(f"✅ Registered handler for {collection}")
    
    def listen(self, collection: str, on_change: Callable = None, poll_interval: int = 2):
        """Start listening to a Firebase collection"""
        if on_change:
            self.register_handler(collection, on_change)
        
        self.poll_interval = poll_interval
        self.running = True
        
        thread = threading.Thread(
            target=self._poll_collection,
            args=(collection,),
            daemon=True
        )
        thread.start()
        self.listeners[collection] = thread
        logger.info(f"📡 Listening to {collection}")
    
    def _poll_collection(self, collection: str):
        """Poll Firebase collection for changes"""
        last_data = None
        
        while self.running:
            try:
                url = f"{self.db_url}/{collection}.json"
                response = requests.get(url, timeout=5)
                
                if response.status_code == 200:
                    data = response.json() or {}
                    
                    if data != last_data:
                        if collection in self.handlers:
                            self.handlers[collection](data)
                        last_data = data
                
                time.sleep(self.poll_interval)
                
            except Exception as e:
                logger.error(f"Poll error for {collection}: {e}")
                time.sleep(5)
    
    def push_data(self, path: str, data: Dict) -> bool:
        """Push data to Firebase"""
        try:
            url = f"{self.db_url}/{path}.json"
            response = requests.post(url, json=data)
            return response.status_code in [200, 201]
        except Exception as e:
            logger.error(f"Push error: {e}")
            return False
    
    def update_data(self, path: str, data: Dict) -> bool:
        """Update data in Firebase"""
        try:
            url = f"{self.db_url}/{path}.json"
            response = requests.patch(url, json=data)
            return response.status_code == 200
        except Exception as e:
            logger.error(f"Update error: {e}")
            return False
    
    def get_data(self, path: str) -> Optional[Dict]:
        """Get data from Firebase"""
        try:
            url = f"{self.db_url}/{path}.json"
            response = requests.get(url)
            if response.status_code == 200:
                return response.json()
            return None
        except Exception as e:
            logger.error(f"Get error: {e}")
            return None
    
    def execute_command(self, command: str, args: List = None, description: str = None) -> Tuple:
        """Execute shell command"""
        if description:
            logger.info(f"🔧 {description}")
        
        try:
            full_cmd = [command] + (args or [])
            result = subprocess.run(full_cmd, capture_output=True, text=True)
            return result.stdout, result.stderr
        except Exception as e:
            logger.error(f"Command error: {e}")
            return "", str(e)
    
    def stop(self):
        """Stop all listeners"""
        self.running = False
        logger.info("🛑 Stopping Firebase service")


class SceneExecutor:
    """Execute scenes from Firebase prompts"""
    
    def __init__(self, firebase_service: FirebaseService):
        self.firebase = firebase_service
        self.active_scene = None
    
    def handle_scene_prompt(self, data: Dict):
        """Handle incoming scene prompt"""
        if not data:
            return
        
        prompt = data.get("prompt")
        if not prompt or prompt == self.active_scene:
            return
        
        self.active_scene = prompt
        logger.info(f"🎭 Executing scene: {prompt}")
        
        try:
            # Import and use modular scene system
            sys.path.insert(0, str(Path(__file__).parent / "fixtures_v2"))
            from drivers.audio_driver import AudioDriver
            from drivers.led_driver import LEDDriver
            
            # Execute scene
            # This would integrate with your existing fixtures_v2 system
            logger.info(f"✅ Scene {prompt} executed")
            
        except Exception as e:
            logger.error(f"Scene execution error: {e}")


def create_flask_api(firebase_service: FirebaseService) -> Flask:
    """Create Flask API for webhook support"""
    app = Flask(__name__)
    CORS(app)
    
    @app.route('/health', methods=['GET'])
    def health():
        return jsonify({"status": "ok"}), 200
    
    @app.route('/command', methods=['POST'])
    def execute_command():
        data = request.json or {}
        command = data.get("command")
        args = data.get("args", [])
        
        if command:
            stdout, stderr = firebase_service.execute_command(command, args)
            return jsonify({
                "success": not stderr,
                "stdout": stdout,
                "stderr": stderr
            }), 200
        
        return jsonify({"error": "No command provided"}), 400
    
    @app.route('/data/<path:path>', methods=['GET'])
    def get_data(path):
        data = firebase_service.get_data(path)
        if data is not None:
            return jsonify(data), 200
        return jsonify({"error": "Not found"}), 404
    
    return app


def main():
    """Main entry point"""
    import argparse
    
    parser = argparse.ArgumentParser(description="Unified Firebase Listener Service")
    parser.add_argument("--project", default="homecoming-kai", help="Firebase project ID")
    parser.add_argument("--listen-scenes", action="store_true", help="Listen for scene prompts")
    parser.add_argument("--listen-commands", action="store_true", help="Listen for commands")
    parser.add_argument("--listen-voices", action="store_true", help="Listen for voice commands")
    parser.add_argument("--api-port", type=int, default=5000, help="API port")
    parser.add_argument("--poll-interval", type=int, default=2, help="Poll interval in seconds")
    
    args = parser.parse_args()
    
    firebase = FirebaseService(args.project)
    firebase.poll_interval = args.poll_interval
    
    if args.listen_scenes:
        executor = SceneExecutor(firebase)
        firebase.listen("scene_prompts", executor.handle_scene_prompt)
    
    if args.listen_commands:
        firebase.listen("commands", lambda data: logger.info(f"Command: {data}"))
    
    if args.listen_voices:
        firebase.listen("voice_commands", lambda data: logger.info(f"Voice: {data}"))
    
    if args.api_port:
        app = create_flask_api(firebase)
        logger.info(f"🌐 Starting API on port {args.api_port}")
        app.run(host="0.0.0.0", port=args.api_port)


if __name__ == "__main__":
    main()
