"""
Kai Home Automation Service
Runs on Raspberry Pi to control GPIO devices via Firebase commands
"""

import os
import sys
import time
import json
from datetime import datetime
from dotenv import load_dotenv
import firebase_admin
from firebase_admin import credentials, db
from gpiozero import LED, Button, OutputDevice
from signal import pause
import threading

# Load environment variables
load_dotenv()

# Configuration
FIREBASE_DATABASE_URL = os.getenv('FIREBASE_DATABASE_URL')
SERVICE_ACCOUNT_PATH = os.getenv('FIREBASE_SERVICE_ACCOUNT')
PERSONA_ID = os.getenv('PERSONA_ID', 'truekai')
DEVICE_ID = os.getenv('DEVICE_ID', 'raspberry_pi_home')
DEVICE_NAME = os.getenv('DEVICE_NAME', 'Home Pi')

# GPIO Pin Configuration
DEVICES = {
    'led_1': {'type': 'LED', 'pin': 17, 'name': 'Living Room Light'},
    'led_2': {'type': 'LED', 'pin': 27, 'name': 'Bedroom Light'},
    'led_3': {'type': 'LED', 'pin': 22, 'name': 'Kitchen Light'},
}

# Device instances
gpio_devices = {}

class KaiHomeService:
    def __init__(self):
        self.running = False
        self.command_ref = None
        self.status_ref = None
        
        print("🏠 [Kai Home] Initializing...")
        
        # Initialize Firebase
        self._init_firebase()
        
        # Initialize GPIO devices
        self._init_devices()
        
        # Start listening for commands
        self._start_listening()
        
        # Send initial status
        self._update_status()
        
        print("✅ [Kai Home] Service started successfully!")
        print(f"📡 [Kai Home] Listening for commands at: home_automation/{PERSONA_ID}/commands")
    
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
    
    def _init_devices(self):
        """Initialize GPIO devices"""
        global gpio_devices
        
        for device_id, config in DEVICES.items():
            try:
                if config['type'] == 'LED':
                    gpio_devices[device_id] = LED(config['pin'])
                elif config['type'] == 'OUTPUT':
                    gpio_devices[device_id] = OutputDevice(config['pin'])
                
                print(f"✅ [GPIO] Initialized {config['name']} (GPIO {config['pin']})")
                
            except Exception as e:
                print(f"❌ [GPIO] Failed to initialize {device_id}: {e}")
    
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
            device_target = command.get('target')
            action = command.get('action')
            device_name = command.get('device')
            
            # Verify command is for this device
            if device_name and device_name != DEVICE_ID:
                print(f"⚠️ [Command] Not for this device (for {device_name})")
                return
            
            # Verify device exists
            if device_target not in gpio_devices:
                print(f"❌ [Command] Unknown device: {device_target}")
                self._send_error(command_id, f"Unknown device: {device_target}")
                return
            
            device = gpio_devices[device_target]
            device_config = DEVICES[device_target]
            
            # Execute action
            if action == 'turn_on':
                device.on()
                print(f"💡 [Action] {device_config['name']} turned ON")
                
            elif action == 'turn_off':
                device.off()
                print(f"💡 [Action] {device_config['name']} turned OFF")
                
            elif action == 'toggle':
                device.toggle()
                state = 'ON' if device.is_lit else 'OFF'
                print(f"💡 [Action] {device_config['name']} toggled to {state}")
                
            elif action == 'blink':
                duration = command.get('duration', 3)
                print(f"💡 [Action] {device_config['name']} blinking for {duration}s")
                threading.Thread(target=self._blink_device, args=(device, duration)).start()
                
            elif action == 'pulse':
                duration = command.get('duration', 5)
                print(f"💡 [Action] {device_config['name']} pulsing for {duration}s")
                threading.Thread(target=self._pulse_device, args=(device, duration)).start()
                
            else:
                print(f"❌ [Command] Unknown action: {action}")
                self._send_error(command_id, f"Unknown action: {action}")
                return
            
            # Update status
            self._update_status()
            
            # Send success response
            self._send_success(command_id, f"{action} executed on {device_target}")
            
        except Exception as e:
            print(f"❌ [Command] Error processing: {e}")
            self._send_error(command_id, str(e))
    
    def _blink_device(self, device, duration):
        """Blink device for specified duration"""
        end_time = time.time() + duration
        while time.time() < end_time:
            device.toggle()
            time.sleep(0.5)
        device.off()
        self._update_status()
    
    def _pulse_device(self, device, duration):
        """Pulse device for specified duration"""
        # Note: pulse() requires PWM-capable pins
        try:
            device.pulse(fade_in_time=1, fade_out_time=1, n=int(duration/2), background=False)
        except:
            # Fallback to blink if pulse not supported
            self._blink_device(device, duration)
        self._update_status()
    
    def _update_status(self):
        """Update device status in Firebase"""
        try:
            status = {
                'device_id': DEVICE_ID,
                'device_name': DEVICE_NAME,
                'online': True,
                'last_updated': int(time.time() * 1000),
                'devices': {}
            }
            
            # Get state of each device
            for device_id, device in gpio_devices.items():
                try:
                    if hasattr(device, 'is_lit'):
                        status['devices'][device_id] = {
                            'state': 'on' if device.is_lit else 'off',
                            'name': DEVICES[device_id]['name']
                        }
                    else:
                        status['devices'][device_id] = {
                            'state': 'on' if device.is_active else 'off',
                            'name': DEVICES[device_id]['name']
                        }
                except:
                    status['devices'][device_id] = {
                        'state': 'unknown',
                        'name': DEVICES[device_id]['name']
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
                'device_id': DEVICE_ID,
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
                'device_id': DEVICE_ID,
                'timestamp': int(time.time() * 1000)
            })
        except Exception as e:
            print(f"❌ [Response] Failed to send error: {e}")
    
    def cleanup(self):
        """Cleanup GPIO and Firebase on exit"""
        print("\n🛑 [Kai Home] Shutting down...")
        
        # Turn off all devices
        for device_id, device in gpio_devices.items():
            try:
                device.off()
            except:
                pass
        
        # Update status to offline
        try:
            self.status_ref.update({'online': False})
        except:
            pass
        
        print("✅ [Kai Home] Cleanup complete")

def main():
    """Main entry point"""
    print("=" * 60)
    print("🏠 Kai Home Automation Service")
    print("=" * 60)
    print()
    
    # Verify configuration
    if not FIREBASE_DATABASE_URL:
        print("❌ Error: FIREBASE_DATABASE_URL not set in .env")
        sys.exit(1)
    
    if not SERVICE_ACCOUNT_PATH or not os.path.exists(SERVICE_ACCOUNT_PATH):
        print("❌ Error: FIREBASE_SERVICE_ACCOUNT not found")
        sys.exit(1)
    
    # Start service
    service = KaiHomeService()
    
    try:
        print("\n💚 Service running! Press Ctrl+C to stop.\n")
        
        # Keep-alive loop with heartbeat
        while True:
            time.sleep(60)  # Heartbeat every minute
            service._update_status()  # Update status
            
    except KeyboardInterrupt:
        print("\n⚠️ Interrupt received...")
    finally:
        service.cleanup()

if __name__ == '__main__':
    main()
