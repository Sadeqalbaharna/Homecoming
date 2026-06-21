#!/usr/bin/env python3
with open('firebase_rest_listener_debug.py', 'r', encoding='utf-8') as f:
    content = f.read()

# Add the smoke machine method before "if __name__"
smoke_method = '''    
    def _trigger_smoke_machine(self, scene_data):
        """Trigger smoke machine for dramatic effect (GPIO control)"""
        try:
            # TODO: Implement GPIO control for smoke machine relay
            # Example: GPIO pin 23 with 2-second burst
            logger.info(f"💨 [SMOKE] Smoke machine triggered for {scene_data['scene_name']}")
            logger.info(f"💨 [SMOKE] TODO: Implement GPIO relay control")
            return False  # Not implemented yet
        except Exception as e:
            logger.error(f"❌ [SMOKE] Error triggering smoke machine: {e}")
            return False

'''

# Find the last method before "if __name__" and add smoke method
content = content.replace('\nif __name__ == "__main__":', smoke_method + '\nif __name__ == "__main__":')

with open('firebase_rest_listener_debug.py', 'w', encoding='utf-8') as f:
    f.write(content)

print("✅ Added _trigger_smoke_machine method")
