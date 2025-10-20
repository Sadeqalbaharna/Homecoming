"""
Generate simple beep sounds for recording start/stop indicators.
Uses numpy and scipy to create pure tone beeps.
"""
import numpy as np
from scipy.io import wavfile
import os

def generate_beep(filename, frequency=800, duration=0.15, sample_rate=44100):
    """
    Generate a simple beep tone.
    
    Args:
        filename: Output WAV file path
        frequency: Tone frequency in Hz (higher = higher pitch)
        duration: Duration in seconds
        sample_rate: Audio sample rate
    """
    # Generate time array
    t = np.linspace(0, duration, int(sample_rate * duration))
    
    # Generate sine wave
    audio = np.sin(2 * np.pi * frequency * t)
    
    # Apply fade in/out to avoid clicks
    fade_samples = int(0.01 * sample_rate)  # 10ms fade
    fade_in = np.linspace(0, 1, fade_samples)
    fade_out = np.linspace(1, 0, fade_samples)
    audio[:fade_samples] *= fade_in
    audio[-fade_samples:] *= fade_out
    
    # Normalize to 16-bit range
    audio = (audio * 32767).astype(np.int16)
    
    # Save as WAV
    wavfile.write(filename, sample_rate, audio)
    print(f"✅ Generated: {filename}")

# Create assets/audio directory if it doesn't exist
os.makedirs('assets/audio', exist_ok=True)

# Generate recording start beep (higher pitch, short)
generate_beep('assets/audio/record_start.wav', frequency=1000, duration=0.1)

# Generate recording stop beep (lower pitch, slightly longer)
generate_beep('assets/audio/record_stop.wav', frequency=600, duration=0.15)

print("\n🎵 Beep sounds generated successfully!")
print("📁 Location: assets/audio/")
print("   - record_start.wav (high beep)")
print("   - record_stop.wav (low beep)")
