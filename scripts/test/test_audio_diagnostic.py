#!/usr/bin/env python3
"""
Diagnostic Audio Test - Record and analyze microphone input
"""
import subprocess
import os
import struct
import math

print("=" * 70)
print("AUDIO DIAGNOSTIC TEST")
print("=" * 70)
print("")

# Record 5 seconds of audio
print("Recording 5 seconds of audio from USB microphone...")
print("(Speak or make noise into the microphone)")
print("")

audio_file = "/tmp/audio_test.wav"

try:
    # Record audio
    cmd = f"arecord -D plughw:3,0 -f S16_LE -r 16000 -d 5 {audio_file}"
    result = subprocess.run(cmd, shell=True, capture_output=True, timeout=10)
    
    if os.path.exists(audio_file):
        file_size = os.path.getsize(audio_file)
        print(f"✅ Recording complete!")
        print(f"   File size: {file_size} bytes")
        print("")
        
        # Analyze audio
        print("Analyzing audio levels...")
        print("-" * 70)
        
        with open(audio_file, 'rb') as f:
            # Skip WAV header (44 bytes)
            f.seek(44)
            
            # Read audio data in 1-second chunks
            chunk_size = 16000 * 2  # 16 bits per sample = 2 bytes
            chunk_num = 1
            
            while True:
                chunk = f.read(chunk_size)
                if not chunk:
                    break
                
                # Convert bytes to samples
                samples = struct.unpack('<' + 'h' * (len(chunk) // 2), chunk)
                
                # Calculate RMS energy
                if samples:
                    rms = math.sqrt(sum(s**2 for s in samples) / len(samples))
                    print(f"Chunk {chunk_num} (1 sec): RMS = {rms:.0f}")
                    chunk_num += 1
        
        print("-" * 70)
        print("")
        print("✅ AUDIO TEST RESULTS:")
        print("   • If RMS values > 500: Microphone is detecting sound properly")
        print("   • If RMS values < 500: Microphone is too quiet or sound is too soft")
        print("   • If RMS values ~ 10-50: Silence only")
        print("")
        
    else:
        print("❌ Error: Audio file not created")
        
except Exception as e:
    print(f"❌ Error during recording: {e}")
    import traceback
    traceback.print_exc()

finally:
    # Cleanup
    if os.path.exists(audio_file):
        try:
            os.remove(audio_file)
            print("Cleaned up temporary audio file.")
        except:
            pass
