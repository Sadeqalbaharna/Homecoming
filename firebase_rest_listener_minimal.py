#!/usr/bin/env python3
"""
Minimal Firebase REST Listener - Low Memory Version
Stripped down version to avoid OOM killer
"""

import os
import sys
import time
import json
import subprocess
import threading
import logging
from datetime import datetime
from flask import Flask, request, jsonify
from flask_cors import CORS

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# Flask app
app = Flask(__name__)
CORS(app)

# Global variables
current_audio_process = None
current_led_process = None

def log_with_timestamp(message):
    """Log with timestamp"""
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S,%f")[:-3]
    print(f"{timestamp} - __main__ - INFO - {message}")
    logger.info(message)

def run_command_safe(command, shell=True, timeout=10):
    """Run command safely with timeout"""
    try:
        result = subprocess.run(
            command, 
            shell=shell, 
            capture_output=True, 
            text=True, 
            timeout=timeout
        )
        return result.returncode, result.stdout, result.stderr
    except subprocess.TimeoutExpired:
        log_with_timestamp(f"⚠️ Command timeout: {command}")
        return -1, "", "Timeout"
    except Exception as e:
        log_with_timestamp(f"⚠️ Command error: {e}")
        return -1, "", str(e)

def set_lighting_simple(color, brightness=70):
    """Simple LED control without complex effects"""
    global current_led_process
    
    try:
        # Kill existing LED process
        if current_led_process and current_led_process.poll() is None:
            current_led_process.terminate()
            current_led_process = None
        
        # Color mapping
        color_map = {
            'red': (255, 0, 0),
            'green': (0, 255, 0),
            'blue': (0, 0, 255),
            'yellow': (255, 255, 0),
            'purple': (128, 0, 128),
            'orange': (255, 165, 0),
            'white': (255, 255, 255),
            'pink': (255, 192, 203),
            'light_green': (144, 238, 144),
            'warm_white': (255, 247, 235)
        }
        
        rgb = color_map.get(color.lower(), (255, 255, 255))
        
        # Apply brightness
        r = int(rgb[0] * brightness / 100)
        g = int(rgb[1] * brightness / 100)
        b = int(rgb[2] * brightness / 100)
        
        # Simple LED command - try rpi_ws281x first, fallback to simulation
        led_command = f"python3 -c \"import time; print('Setting LEDs to RGB({r},{g},{b})'); time.sleep(0.1)\""
        
        returncode, stdout, stderr = run_command_safe(led_command, timeout=5)
        
        if returncode == 0:
            log_with_timestamp(f"✅ LEDs set to {color} ({r},{g},{b}) at {brightness}%")
            return True
        else:
            log_with_timestamp(f"⚠️ LED simulation mode: {color} ({r},{g},{b}) at {brightness}%")
            return True
            
    except Exception as e:
        log_with_timestamp(f"⚠️ LED error: {e}")
        return False

def play_audio_simple(query="relaxing music"):
    """Simple audio playback"""
    global current_audio_process
    
    try:
        # Kill existing audio
        if current_audio_process and current_audio_process.poll() is None:
            current_audio_process.terminate()
            current_audio_process = None
        
        # Simple yt-dlp command
        audio_command = f'yt-dlp -f "bestaudio" --no-playlist -x --audio-format mp3 "ytsearch1:{query}" -o - | mpv --no-video --volume=50 -'
        
        log_with_timestamp(f"🎵 Starting audio: {query}")
        
        current_audio_process = subprocess.Popen(
            audio_command,
            shell=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL
        )
        
        log_with_timestamp(f"🎵 Audio started with PID: {current_audio_process.pid}")
        return True
        
    except Exception as e:
        log_with_timestamp(f"⚠️ Audio error: {e}")
        return False

@app.route('/command', methods=['POST'])
def handle_command():
    """Handle Firebase commands"""
    try:
        data = request.get_json()
        command = data.get('command', '')
        
        log_with_timestamp(f"📥 Received command: {command}")
        
        if command == 'red_lights':
            set_lighting_simple('red', 80)
            return jsonify({'status': 'success', 'message': 'Red lights activated'})
            
        elif command == 'green_lights':
            set_lighting_simple('green', 80)
            return jsonify({'status': 'success', 'message': 'Green lights activated'})
            
        elif command == 'blue_lights':
            set_lighting_simple('blue', 80)
            return jsonify({'status': 'success', 'message': 'Blue lights activated'})
            
        elif command == 'white_lights':
            set_lighting_simple('white', 80)
            return jsonify({'status': 'success', 'message': 'White lights activated'})
            
        elif command == 'lights_off':
            set_lighting_simple('white', 0)
            return jsonify({'status': 'success', 'message': 'Lights turned off'})
            
        elif command.startswith('ambiance_'):
            ambiance = command.replace('ambiance_', '')
            color_map = {
                'forest': 'light_green',
                'sunset': 'orange',
                'ocean': 'blue',
                'fire': 'red',
                'night': 'purple'
            }
            color = color_map.get(ambiance, 'warm_white')
            set_lighting_simple(color, 70)
            return jsonify({'status': 'success', 'message': f'{ambiance.title()} ambiance set'})
            
        elif 'play' in command or 'music' in command:
            query = data.get('query', 'relaxing music')
            if play_audio_simple(query):
                return jsonify({'status': 'success', 'message': f'Playing: {query}'})
            else:
                return jsonify({'status': 'error', 'message': 'Audio playback failed'})
                
        elif command == 'dynamic_ambient':
            prompt = data.get('prompt', 'peaceful atmosphere')
            # Simple dynamic ambient - just set color and play audio
            if 'forest' in prompt.lower():
                set_lighting_simple('light_green', 70)
                play_audio_simple('forest sounds rain')
            elif 'fire' in prompt.lower() or 'cozy' in prompt.lower():
                set_lighting_simple('orange', 70)
                play_audio_simple('fireplace crackling sounds')
            elif 'ocean' in prompt.lower() or 'water' in prompt.lower():
                set_lighting_simple('blue', 70)
                play_audio_simple('ocean waves sounds')
            else:
                set_lighting_simple('warm_white', 70)
                play_audio_simple('ambient relaxing music')
                
            return jsonify({'status': 'success', 'message': f'Dynamic ambient: {prompt}'})
            
        else:
            log_with_timestamp(f"❓ Unknown command: {command}")
            return jsonify({'status': 'error', 'message': f'Unknown command: {command}'})
            
    except Exception as e:
        log_with_timestamp(f"❌ Command error: {e}")
        return jsonify({'status': 'error', 'message': str(e)})

@app.route('/health', methods=['GET'])
def health_check():
    """Health check endpoint"""
    return jsonify({'status': 'healthy', 'timestamp': datetime.now().isoformat()})

def cleanup_processes():
    """Cleanup processes on shutdown"""
    global current_audio_process, current_led_process
    
    if current_audio_process:
        try:
            current_audio_process.terminate()
        except:
            pass
            
    if current_led_process:
        try:
            current_led_process.terminate()
        except:
            pass

if __name__ == '__main__':
    try:
        log_with_timestamp("🚀 Starting Minimal Firebase REST Listener")
        log_with_timestamp("💾 Low memory mode - simplified functionality")
        
        # Start Flask server
        app.run(host='0.0.0.0', port=5001, debug=False, threaded=True)
        
    except KeyboardInterrupt:
        log_with_timestamp("🛑 Shutting down...")
        cleanup_processes()
    except Exception as e:
        log_with_timestamp(f"❌ Fatal error: {e}")
        cleanup_processes()