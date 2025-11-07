#!/usr/bin/env python3
"""
Bluetooth Audio Manager for Homecoming Pi
Manages Bluetooth audio connections and provides audio output for voice responses
"""

import os
import sys
import time
import json
import logging
import subprocess
import threading
from pathlib import Path
from typing import Optional, Dict, Any

import pydbus
import gi
gi.require_version('Gst', '1.0')
from gi.repository import Gst, GLib

# Initialize GStreamer
Gst.init(None)

class BluetoothAudioManager:
    def __init__(self):
        self.logger = self._setup_logging()
        self.bus = pydbus.SystemBus()
        self.bluetooth = self.bus.get('org.bluez', '/')
        self.connected_device = None
        self.audio_sink = None
        self.pipeline = None
        
    def _setup_logging(self):
        """Setup logging for the audio manager"""
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
            handlers=[
                logging.FileHandler('/home/pi/homecoming_pi/logs/bluetooth_audio.log'),
                logging.StreamHandler(sys.stdout)
            ]
        )
        return logging.getLogger('BluetoothAudio')
    
    def get_paired_devices(self) -> Dict[str, Dict]:
        """Get all paired Bluetooth devices"""
        devices = {}
        try:
            adapter_path = '/org/bluez/hci0'
            adapter = self.bus.get('org.bluez', adapter_path)
            
            # Get managed objects
            manager = self.bus.get('org.bluez', '/')
            objects = manager.GetManagedObjects()
            
            for path, interfaces in objects.items():
                if 'org.bluez.Device1' in interfaces:
                    device = interfaces['org.bluez.Device1']
                    if device.get('Paired', False):
                        devices[path] = {
                            'name': device.get('Name', 'Unknown'),
                            'address': device.get('Address', ''),
                            'connected': device.get('Connected', False),
                            'audio_sink': 'org.bluez.AudioSink1' in interfaces,
                            'a2dp': 'A2DP' in device.get('UUIDs', [])
                        }
            
            return devices
        except Exception as e:
            self.logger.error(f"Failed to get paired devices: {e}")
            return {}
    
    def connect_audio_device(self, device_path: Optional[str] = None) -> bool:
        """Connect to a Bluetooth audio device"""
        try:
            devices = self.get_paired_devices()
            
            if not devices:
                self.logger.warning("No paired devices found")
                return False
            
            # If no specific device, connect to first audio-capable device
            if not device_path:
                for path, info in devices.items():
                    if info['audio_sink'] and not info['connected']:
                        device_path = path
                        break
            
            if not device_path:
                self.logger.warning("No audio-capable device to connect to")
                return False
            
            # Connect to device
            device = self.bus.get('org.bluez', device_path)
            device.Connect()
            
            # Wait for connection
            for _ in range(10):
                time.sleep(1)
                if device.Connected:
                    self.connected_device = device_path
                    self.logger.info(f"Connected to audio device: {devices[device_path]['name']}")
                    return True
            
            self.logger.error("Failed to connect to device")
            return False
            
        except Exception as e:
            self.logger.error(f"Error connecting audio device: {e}")
            return False
    
    def setup_audio_pipeline(self):
        """Setup GStreamer audio pipeline for Bluetooth output"""
        try:
            # Create pipeline for audio playback
            pipeline_str = (
                "filesrc name=source ! "
                "decodebin ! "
                "audioconvert ! "
                "audioresample ! "
                "pulsesink device='bluez_sink'"
            )
            
            self.pipeline = Gst.parse_launch(pipeline_str)
            
            # Get bus for messages
            bus = self.pipeline.get_bus()
            bus.add_signal_watch()
            bus.connect("message", self._on_pipeline_message)
            
            self.logger.info("Audio pipeline setup complete")
            return True
            
        except Exception as e:
            self.logger.error(f"Failed to setup audio pipeline: {e}")
            return False
    
    def _on_pipeline_message(self, bus, message):
        """Handle GStreamer pipeline messages"""
        if message.type == Gst.MessageType.ERROR:
            err, debug = message.parse_error()
            self.logger.error(f"Pipeline error: {err}, {debug}")
        elif message.type == Gst.MessageType.EOS:
            self.logger.info("Audio playback finished")
            self.pipeline.set_state(Gst.State.NULL)
    
    def play_text_to_speech(self, text: str, voice: str = "en") -> bool:
        """Generate TTS and play via Bluetooth"""
        try:
            # Generate TTS audio file
            tts_file = f"/tmp/homecoming_tts_{int(time.time())}.wav"
            
            # Use espeak for TTS
            cmd = [
                "espeak-ng",
                "-v", voice,
                "-s", "150",  # Speed
                "-p", "50",   # Pitch
                "-a", "100",  # Amplitude
                "-w", tts_file,
                text
            ]
            
            result = subprocess.run(cmd, capture_output=True, text=True)
            if result.returncode != 0:
                self.logger.error(f"TTS generation failed: {result.stderr}")
                return False
            
            # Play the audio file
            return self.play_audio_file(tts_file)
            
        except Exception as e:
            self.logger.error(f"TTS playback error: {e}")
            return False
    
    def play_audio_file(self, file_path: str) -> bool:
        """Play an audio file via Bluetooth"""
        try:
            if not self.pipeline:
                if not self.setup_audio_pipeline():
                    return False
            
            # Set file source
            source = self.pipeline.get_by_name("source")
            source.set_property("location", file_path)
            
            # Start playback
            self.pipeline.set_state(Gst.State.PLAYING)
            
            self.logger.info(f"Playing audio file: {file_path}")
            return True
            
        except Exception as e:
            self.logger.error(f"Audio playback error: {e}")
            return False
    
    def play_beep(self, frequency: int = 800, duration: float = 0.5) -> bool:
        """Play a beep sound via Bluetooth"""
        try:
            # Generate beep with sox
            beep_file = f"/tmp/homecoming_beep_{int(time.time())}.wav"
            cmd = [
                "sox", "-n", "-r", "44100", beep_file,
                "synth", str(duration), "sine", str(frequency),
                "vol", "0.5"
            ]
            
            result = subprocess.run(cmd, capture_output=True)
            if result.returncode == 0:
                return self.play_audio_file(beep_file)
            
            self.logger.error("Failed to generate beep")
            return False
            
        except Exception as e:
            self.logger.error(f"Beep generation error: {e}")
            return False
    
    def test_audio_output(self) -> bool:
        """Test Bluetooth audio output"""
        self.logger.info("Testing Bluetooth audio output...")
        
        # Test beep
        if self.play_beep(1000, 0.3):
            time.sleep(0.5)
            
            # Test TTS
            if self.play_text_to_speech("Hello from Homecoming Pi! Bluetooth audio is working."):
                self.logger.info("✅ Bluetooth audio test successful!")
                return True
        
        self.logger.error("❌ Bluetooth audio test failed")
        return False
    
    def run_service(self):
        """Run as a service - monitor connections and handle audio requests"""
        self.logger.info("Starting Bluetooth Audio Service...")
        
        # Try to connect to a paired device
        if not self.connect_audio_device():
            self.logger.warning("No audio device connected, waiting...")
        
        # Setup audio pipeline
        self.setup_audio_pipeline()
        
        # Create main loop
        loop = GLib.MainLoop()
        
        # Monitor for audio requests via file system
        self._setup_audio_request_monitor()
        
        try:
            loop.run()
        except KeyboardInterrupt:
            self.logger.info("Service stopped by user")
        except Exception as e:
            self.logger.error(f"Service error: {e}")
    
    def _setup_audio_request_monitor(self):
        """Monitor for audio requests from other services"""
        request_dir = Path("/tmp/homecoming_audio_requests")
        request_dir.mkdir(exist_ok=True)
        
        def monitor_requests():
            while True:
                try:
                    for request_file in request_dir.glob("*.json"):
                        with open(request_file, 'r') as f:
                            request = json.load(f)
                        
                        # Process request
                        if request['type'] == 'tts':
                            self.play_text_to_speech(request['text'], request.get('voice', 'en'))
                        elif request['type'] == 'beep':
                            self.play_beep(request.get('frequency', 800), request.get('duration', 0.5))
                        elif request['type'] == 'file':
                            self.play_audio_file(request['path'])
                        
                        # Remove processed request
                        request_file.unlink()
                        
                except Exception as e:
                    self.logger.error(f"Request monitoring error: {e}")
                
                time.sleep(0.1)
        
        # Start monitoring in background thread
        monitor_thread = threading.Thread(target=monitor_requests, daemon=True)
        monitor_thread.start()

def main():
    """Main entry point"""
    audio_manager = BluetoothAudioManager()
    
    if len(sys.argv) > 1:
        command = sys.argv[1]
        
        if command == "test":
            # Test audio
            if audio_manager.connect_audio_device():
                audio_manager.test_audio_output()
            else:
                print("❌ No Bluetooth audio device connected")
        
        elif command == "devices":
            # List paired devices
            devices = audio_manager.get_paired_devices()
            print("📱 Paired Bluetooth devices:")
            for path, info in devices.items():
                status = "🔊 Connected" if info['connected'] else "📱 Available"
                audio = "🎵 Audio" if info['audio_sink'] else "❌ No Audio"
                print(f"  {info['name']} ({info['address']}) - {status} - {audio}")
        
        elif command == "tts":
            # Text-to-speech test
            text = sys.argv[2] if len(sys.argv) > 2 else "Hello from Homecoming Pi"
            if audio_manager.connect_audio_device():
                audio_manager.play_text_to_speech(text)
        
        else:
            print("Usage: python3 bluetooth_audio_manager.py [test|devices|tts <text>]")
    
    else:
        # Run as service
        audio_manager.run_service()

if __name__ == "__main__":
    main()