"""
Kai Home Automation Service - WS2812B LED Strip Version
Runs on Raspberry Pi to control WS2812B RGB LED strips via Firebase commands
"""

import os
import sys
import time
import json
from datetime import datetime
from dotenv import load_dotenv
import firebase_admin
from firebase_admin import credentials, db
import threading
import colorsys

# Load environment variables
load_dotenv()

# Configuration
FIREBASE_DATABASE_URL = os.getenv('FIREBASE_DATABASE_URL')
SERVICE_ACCOUNT_PATH = os.getenv('FIREBASE_SERVICE_ACCOUNT')
PERSONA_ID = os.getenv('PERSONA_ID', 'truekai')
DEVICE_ID = os.getenv('DEVICE_ID', 'raspberry_pi_home')
DEVICE_NAME = os.getenv('DEVICE_NAME', 'Home Pi')

# WS2812B Configuration
LED_COUNT = 300        # Number of LED pixels
LED_PIN = 18          # GPIO pin connected to the pixels (must be PWM pin)
LED_FREQ_HZ = 800000  # LED signal frequency in hertz
LED_DMA = 10         # DMA channel to use for generating signal
LED_BRIGHTNESS = 255  # Set to 0 for darkest and 255 for brightest
LED_INVERT = False    # True to invert the signal
LED_CHANNEL = 0       # set to '1' for GPIOs 13, 19, 41, 45 or 53

# LED Strip Zones (customize these for your setup)
ZONES = {
    'living_room': {'start': 0, 'count': 100, 'name': 'Living Room'},
    'bedroom': {'start': 100, 'count': 100, 'name': 'Bedroom'}, 
    'kitchen': {'start': 200, 'count': 100, 'name': 'Kitchen'},
    'all': {'start': 0, 'count': 300, 'name': 'All Lights'},
}

# Try to import rpi_ws281x library
try:
    from rpi_ws281x import PixelStrip, Color
    WS2812B_AVAILABLE = True
except ImportError:
    print("⚠️ [WS2812B] rpi_ws281x not installed - using simulation mode")
    WS2812B_AVAILABLE = False
    
    # Mock PixelStrip for testing without hardware
    class PixelStrip:
        def __init__(self, *args, **kwargs):
            self.pixels = [0] * LED_COUNT
            
        def begin(self):
            pass
            
        def setPixelColor(self, i, color):
            if 0 <= i < len(self.pixels):
                self.pixels[i] = color
                
        def show(self):
            pass
            
        def numPixels(self):
            return len(self.pixels)
            
        def getPixelColor(self, i):
            return self.pixels[i] if 0 <= i < len(self.pixels) else 0
    
    def Color(r, g, b, w=0):
        return (w << 24) | (r << 16) | (g << 8) | b

class KaiWS2812BService:
    def __init__(self):
        self.running = False
        self.command_ref = None
        self.status_ref = None
        self.strip = None
        self.current_effects = {}
        
        print("🌈 [Kai WS2812B] Initializing...")
        
        # Initialize Firebase
        self._init_firebase()
        
        # Initialize WS2812B strip
        self._init_strip()
        
        # Start listening for commands
        self._start_listening()
        
        # Send initial status
        self._update_status()
        
        print("✅ [Kai WS2812B] Service started successfully!")
        print(f"📡 [Kai WS2812B] Listening for commands at: home_automation/{PERSONA_ID}/commands")

    def _init_firebase(self):
        """Initialize Firebase connection"""
        try:
            # Load service account credentials
            cred = credentials.Certificate(SERVICE_ACCOUNT_PATH)
            
            # Initialize Firebase app
            firebase_admin.initialize_app(cred, {
                'databaseURL': FIREBASE_DATABASE_URL
            })
            
            # References
            self.command_ref = db.reference(f'home_automation/{PERSONA_ID}/commands')
            self.status_ref = db.reference(f'home_automation/{PERSONA_ID}/status/{DEVICE_ID}')
            
            print("✅ [Firebase] Connected successfully")
            
        except Exception as e:
            print(f"❌ [Firebase] Connection failed: {e}")
            sys.exit(1)

    def _init_strip(self):
        """Initialize WS2812B LED strip"""
        try:
            self.strip = PixelStrip(LED_COUNT, LED_PIN, LED_FREQ_HZ, LED_DMA, LED_INVERT, LED_BRIGHTNESS, LED_CHANNEL)
            self.strip.begin()
            
            # Clear all LEDs
            self._clear_all()
            
            print(f"✅ [WS2812B] Strip initialized: {LED_COUNT} LEDs on GPIO {LED_PIN}")
            
        except Exception as e:
            print(f"❌ [WS2812B] Strip initialization failed: {e}")
            if WS2812B_AVAILABLE:
                print("💡 [WS2812B] Try running with sudo for GPIO access")

    def _start_listening(self):
        """Start listening for Firebase commands"""
        self.running = True
        
        def on_command_added(event):
            """Handle new command from Kai"""
            if event.data is None:
                return
            
            command_id = event.path.strip('/')
            command = event.data
            
            print(f"📥 [Command] Received: {command}")
            
            # Process command
            self._process_command(command_id, command)
            
            # Delete command after processing
            try:
                self.command_ref.child(command_id).delete()
            except:
                pass
        
        # Listen for child_added events (new commands)
        self.command_ref.listen(on_command_added)

    def _process_command(self, command_id, command):
        """Process a command from Kai"""
        try:
            zone_target = command.get('target', '').replace('led_1', 'living_room').replace('led_2', 'bedroom').replace('led_3', 'kitchen')
            action = command.get('action')
            device_name = command.get('device')
            
            # Verify command is for this device
            if device_name and device_name != DEVICE_ID:
                print(f"⚠️ [Command] Not for this device (for {device_name})")
                return
            
            # Verify zone exists
            if zone_target not in ZONES:
                print(f"❌ [Command] Unknown zone: {zone_target}")
                self._send_error(command_id, f"Unknown zone: {zone_target}")
                return
            
            zone_config = ZONES[zone_target]
            
            # Execute action
            if action == 'turn_on':
                color = command.get('color', 'white')
                self._set_zone_color(zone_target, color)
                print(f"🌈 [Action] {zone_config['name']} turned ON ({color})")
                
            elif action == 'turn_off':
                self._clear_zone(zone_target)
                print(f"🌈 [Action] {zone_config['name']} turned OFF")
                
            elif action == 'toggle':
                if self._is_zone_on(zone_target):
                    self._clear_zone(zone_target)
                    print(f"🌈 [Action] {zone_config['name']} toggled OFF")
                else:
                    self._set_zone_color(zone_target, 'white')
                    print(f"🌈 [Action] {zone_config['name']} toggled ON")
                    
            elif action == 'color':
                color = command.get('color', 'white')
                self._set_zone_color(zone_target, color)
                print(f"🌈 [Action] {zone_config['name']} set to {color}")
                
            elif action == 'rainbow':
                duration = command.get('duration', 10)
                self._rainbow_effect(zone_target, duration)
                print(f"🌈 [Action] {zone_config['name']} rainbow for {duration}s")
                
            elif action == 'pulse':
                color = command.get('color', 'blue')
                duration = command.get('duration', 5)
                self._pulse_effect(zone_target, color, duration)
                print(f"🌈 [Action] {zone_config['name']} pulsing {color} for {duration}s")
                
            else:
                print(f"❌ [Command] Unknown action: {action}")
                self._send_error(command_id, f"Unknown action: {action}")
                return
            
            # Update status and send success
            self._update_status()
            self._send_success(command_id, f"{action} completed on {zone_config['name']}")
            
        except Exception as e:
            print(f"❌ [Command] Processing failed: {e}")
            self._send_error(command_id, str(e))

    def _parse_color(self, color_name):
        """Convert color name to RGB values"""
        colors = {
            'white': (255, 255, 255),
            'red': (255, 0, 0),
            'green': (0, 255, 0),
            'blue': (0, 0, 255),
            'yellow': (255, 255, 0),
            'cyan': (0, 255, 255),
            'magenta': (255, 0, 255),
            'orange': (255, 165, 0),
            'purple': (128, 0, 128),
            'pink': (255, 192, 203),
            'warm_white': (255, 244, 229),
            'cool_white': (245, 245, 255),
        }
        return colors.get(color_name.lower(), (255, 255, 255))

    def _set_zone_color(self, zone_name, color_name):
        """Set all LEDs in a zone to specified color"""
        zone = ZONES[zone_name]
        r, g, b = self._parse_color(color_name)
        
        for i in range(zone['start'], zone['start'] + zone['count']):
            self.strip.setPixelColor(i, Color(r, g, b))
        
        self.strip.show()

    def _clear_zone(self, zone_name):
        """Turn off all LEDs in a zone"""
        zone = ZONES[zone_name]
        
        for i in range(zone['start'], zone['start'] + zone['count']):
            self.strip.setPixelColor(i, Color(0, 0, 0))
        
        self.strip.show()

    def _clear_all(self):
        """Turn off all LEDs"""
        for i in range(self.strip.numPixels()):
            self.strip.setPixelColor(i, Color(0, 0, 0))
        self.strip.show()

    def _is_zone_on(self, zone_name):
        """Check if any LED in zone is currently on"""
        zone = ZONES[zone_name]
        
        for i in range(zone['start'], zone['start'] + zone['count']):
            if self.strip.getPixelColor(i) != 0:
                return True
        return False

    def _rainbow_effect(self, zone_name, duration):
        """Rainbow effect for specified duration"""
        def rainbow_worker():
            zone = ZONES[zone_name]
            start_time = time.time()
            
            while time.time() - start_time < duration and self.running:
                for j in range(256):
                    if time.time() - start_time >= duration:
                        break
                        
                    for i in range(zone['count']):
                        pixel_index = zone['start'] + i
                        hue = (i * 256 // zone['count'] + j) % 256
                        r, g, b = colorsys.hsv_to_rgb(hue/256.0, 1.0, 1.0)
                        self.strip.setPixelColor(pixel_index, Color(int(r*255), int(g*255), int(b*255)))
                    
                    self.strip.show()
                    time.sleep(0.05)
        
        threading.Thread(target=rainbow_worker, daemon=True).start()

    def _pulse_effect(self, zone_name, color_name, duration):
        """Pulse effect for specified duration"""
        def pulse_worker():
            zone = ZONES[zone_name]
            r, g, b = self._parse_color(color_name)
            start_time = time.time()
            
            while time.time() - start_time < duration and self.running:
                # Fade in
                for brightness in range(0, 256, 5):
                    if time.time() - start_time >= duration:
                        break
                    for i in range(zone['start'], zone['start'] + zone['count']):
                        self.strip.setPixelColor(i, Color(r*brightness//255, g*brightness//255, b*brightness//255))
                    self.strip.show()
                    time.sleep(0.03)
                
                # Fade out
                for brightness in range(255, -1, -5):
                    if time.time() - start_time >= duration:
                        break
                    for i in range(zone['start'], zone['start'] + zone['count']):
                        self.strip.setPixelColor(i, Color(r*brightness//255, g*brightness//255, b*brightness//255))
                    self.strip.show()
                    time.sleep(0.03)
        
        threading.Thread(target=pulse_worker, daemon=True).start()

    def _update_status(self):
        """Update device status in Firebase"""
        try:
            status = {
                'device_id': DEVICE_ID,
                'device_name': DEVICE_NAME,
                'online': True,
                'last_updated': int(time.time() * 1000),
                'led_count': LED_COUNT,
                'zones': {}
            }
            
            # Check state of each zone
            for zone_name, zone_config in ZONES.items():
                status['zones'][zone_name] = {
                    'state': 'on' if self._is_zone_on(zone_name) else 'off',
                    'name': zone_config['name'],
                    'led_count': zone_config['count']
                }
            
            self.status_ref.set(status)
            
        except Exception as e:
            print(f"❌ [Status] Update failed: {e}")

    def _send_success(self, command_id, message):
        """Send success response"""
        try:
            response_ref = db.reference(f'home_automation/{PERSONA_ID}/responses/{command_id}')
            response_ref.set({
                'success': True,
                'message': message,
                'timestamp': int(time.time() * 1000)
            })
        except Exception as e:
            print(f"❌ [Response] Failed to send success: {e}")

    def _send_error(self, command_id, error):
        """Send error response"""
        try:
            response_ref = db.reference(f'home_automation/{PERSONA_ID}/responses/{command_id}')
            response_ref.set({
                'success': False,
                'error': error,
                'timestamp': int(time.time() * 1000)
            })
        except Exception as e:
            print(f"❌ [Response] Failed to send error: {e}")

    def cleanup(self):
        """Cleanup LEDs and Firebase on exit"""
        print("\n🛑 [Kai WS2812B] Shutting down...")
        
        # Turn off all LEDs
        self._clear_all()
        
        # Update status to offline
        try:
            self.status_ref.update({'online': False})
        except:
            pass
        
        print("✅ [Kai WS2812B] Cleanup complete")

def main():
    """Main entry point"""
    # Check required environment variables
    if not SERVICE_ACCOUNT_PATH:
        print("❌ Error: FIREBASE_SERVICE_ACCOUNT not found")
        print("📝 Set up your .env file with Firebase credentials")
        sys.exit(1)
    
    if not FIREBASE_DATABASE_URL:
        print("❌ Error: FIREBASE_DATABASE_URL not found") 
        print("📝 Set up your .env file with Firebase database URL")
        sys.exit(1)
    
    print("=" * 60)
    print("🌈 Kai WS2812B Home Automation Service")  
    print("=" * 60)
    print()
    
    try:
        service = KaiWS2812BService()
        
        print()
        print("💚 Service running! Press Ctrl+C to stop.")
        print()
        
        # Keep running until interrupted
        try:
            while service.running:
                time.sleep(1)
        except KeyboardInterrupt:
            print()
            service.cleanup()
            
    except Exception as e:
        print(f"💥 Fatal error: {e}")
        sys.exit(1)

if __name__ == '__main__':
    main()