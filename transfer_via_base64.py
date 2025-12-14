#!/usr/bin/env python3
"""
Simple file transfer via base64 encoding
Use this to transfer the updated listener to the Pi
"""
import base64
import sys
import os

def encode_file_to_base64(file_path):
    """Encode a file to base64 for easy transfer"""
    with open(file_path, 'rb') as f:
        content = f.read()
    
    b64_content = base64.b64encode(content).decode('utf-8')
    
    # Split into chunks of 200 chars for easier pasting
    chunks = [b64_content[i:i+200] for i in range(0, len(b64_content), 200)]
    
    print(f"File: {file_path}")
    print(f"Size: {len(content):,} bytes")
    print(f"Base64 size: {len(b64_content):,} characters")
    print(f"Chunks: {len(chunks)}")
    print("\n" + "="*60)
    print("INSTRUCTIONS:")
    print("="*60)
    print("\n1. On Pi, run:")
    print("   python3 << 'ENDSCRIPT'")
    print("   import base64")
    print("   data = '''")
    print("   " + chunks[0])
    
    if len(chunks) > 1:
        for i, chunk in enumerate(chunks[1:], 1):
            print(f"   {chunk}")
    
    print("   '''")
    print("   # Remove newlines")
    print("   data = data.replace('\\n', '').replace(' ', '')")
    print("   with open('/home/pi/firebase_rest_listener_debug.py', 'wb') as f:")
    print("       f.write(base64.b64decode(data))")
    print("   ENDSCRIPT")
    print("\n2. Verify the file:")
    print("   wc -l /home/pi/firebase_rest_listener_debug.py")
    print("\n3. Restart listener:")
    print("   pkill -f firebase_rest_listener_debug")
    print("   sudo nohup python3 firebase_rest_listener_debug.py > listener.log 2>&1 &")
    
if __name__ == "__main__":
    file_path = r"c:\code\homecoming_app\firebase_rest_listener_debug.py"
    
    if os.path.exists(file_path):
        encode_file_to_base64(file_path)
    else:
        print(f"Error: File not found: {file_path}")
        sys.exit(1)
