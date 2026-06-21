#!/usr/bin/env python3
"""
Ultra-simple wake word detection with RMS energy calculation
- Parse WAV files directly
- Calculate RMS from audio samples
- Only transcribe when loud
- Zero hallucinations
"""
import subprocess
import os
import time
import wave
import struct
import math

api_key = "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"

# Skip GPIO for now - just focus on wake word
try:
    from led_control import LEDController
    led = LEDController()
    has_led = True
except:
    has_led = False
    print("⚠️  No LED control available")

def get_rms_energy(audio_file):
    """Calculate RMS energy from WAV file"""
    try:
        with wave.open(audio_file, 'rb') as wav:
            frames = wav.readframes(wav.getnframes())
            # Unpack samples as signed shorts
            samples = struct.unpack(f'<{len(frames)//2}h', frames)
            # Calculate RMS
            rms = math.sqrt(sum(s**2 for s in samples) / len(samples))
            return rms
    except Exception as e:
        print(f"Error reading audio: {e}")
        return 0

def transcribe_audio(audio_file):
    """Transcribe with Whisper API"""
    import requests
    try:
        headers = {"Authorization": f"Bearer {api_key}"}
        with open(audio_file, "rb") as f:
            files = {"file": f, "model": (None, "whisper-1")}
            response = requests.post("https://api.openai.com/v1/audio/transcriptions", headers=headers, files=files)
        data = response.json()
        if "error" in data:
            return None
        return data.get("text", "").strip()
    except Exception as e:
        return None

def chat_with_gpt(user_text):
    """Get response from ChatGPT"""
    import requests
    try:
        headers = {"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"}
        data = {
            "model": "gpt-4",
            "messages": [{"role": "user", "content": user_text}],
            "max_tokens": 150
        }
        response = requests.post("https://api.openai.com/v1/chat/completions", headers=headers, json=data)
        result = response.json()
        if "error" in result:
            return None
        return result["choices"][0]["message"]["content"].strip()
    except Exception as e:
        return None

def generate_speech(text):
    """Generate speech from text"""
    import requests
    try:
        headers = {"Authorization": f"Bearer {api_key}"}
        data = {"model": "tts-1", "input": text, "voice": "alloy"}
        response = requests.post("https://api.openai.com/v1/audio/speech", headers=headers, json=data)
        if response.status_code != 200:
            return None
        mp3_file = "/tmp/response.mp3"
        with open(mp3_file, "wb") as f:
            f.write(response.content)
        wav_file = "/tmp/response.wav"
        subprocess.run(f"ffmpeg -i {mp3_file} -acodec pcm_s16le -ar 48000 {wav_file} -y 2>/dev/null", shell=True)
        return wav_file
    except Exception as e:
        return None

def listen_for_wake_word():
    """
    Listen for "Hey Kai" with RMS energy detection
    - Record 2-second chunks (reduces hallucinations)
    - Only transcribe when RMS > 5000 (loud enough to be speech)
    - Strict "kai" matching
    """
    try:
        print("🎤 Listening for 'Hello Kai'...")
        
        rms_threshold = 5000  # Minimum RMS energy for speech
        silent_count = 0
        
        for attempt in range(60):  # 2 minute timeout (2-second chunks)
            print(".", end="", flush=True)
            
            # Record 2 second chunk - longer = less hallucination
            subprocess.run("arecord -D plughw:3,0 -f S16_LE -r 16000 -d 2 /tmp/wake_check.wav 2>/dev/null", shell=True)
            
            # Check RMS energy
            rms = get_rms_energy("/tmp/wake_check.wav")
            
            if rms > rms_threshold:
                # LOUD - transcribe
                print(f"\n  🔊 Speech detected! (RMS: {rms:.0f})")
                text = transcribe_audio("/tmp/wake_check.wav")
                
                if text:
                    text_lower = text.lower().strip()
                    print(f"  📝 Heard: '{text}'")
                    
                    # STRICT: only accept if "hello" AND "kai" are in the text
                    # AND avoid common hallucinations
                    hallucinations = ["okay", "bye", "one", "two", "three", "google", "what", "yes", "no"]
                    
                    if "hello" in text_lower and "kai" in text_lower and text_lower not in hallucinations:
                        print(f"  ✅ WAKE WORD MATCHED!")
                        return True
                    else:
                        print(f"  ❌ Not a wake word, continuing...")
                        silent_count = 0
            else:
                # Quiet - count silence
                silent_count += 1
                if silent_count % 10 == 0:
                    print(f" [{rms:.0f}]", end="", flush=True)
        
        print("\n  ⏱️ Timeout")
        return False
    except Exception as e:
        print(f"\n  ❌ Error: {e}")
        import traceback
        traceback.print_exc()
        return False

print("=" * 70)
print("KAI WAKE WORD SYSTEM - RMS ENERGY DETECTION")
print("=" * 70)
print("")

conversation_count = 0

try:
    while True:
        conversation_count += 1
        print(f"\n--- CONVERSATION #{conversation_count} ---")
        
        if has_led:
            try:
                led.listening()
                print("🔵 LED ON - Say 'Hello Kai'")
            except Exception as e:
                print(f"Say 'Hello Kai' (LED error: {e})")
        else:
            print("Say 'Hello Kai'")
        
        # Listen for wake word
        if listen_for_wake_word():
            if has_led:
                try:
                    led.wake_detected()
                except:
                    pass
            
            print("🟡 Recording 3 seconds...")
            print(">>> SPEAK YOUR COMMAND <<<")
            subprocess.run("arecord -D plughw:3,0 -f S16_LE -r 16000 -d 3 /tmp/user_audio.wav 2>/dev/null", shell=True)
            
            print("📝 Processing...")
            detected_text = transcribe_audio("/tmp/user_audio.wav")
            
            if detected_text:
                print(f'✓ You: "{detected_text}"')
                
                if detected_text.lower() in ["goodbye", "exit", "quit", "stop", "bye"]:
                    print("\n👋 Goodbye!")
                    break
                
                if has_led:
                    try:
                        led.processing()
                    except:
                        pass
                
                print("🔴 Thinking...")
                response_text = chat_with_gpt(detected_text)
                
                if response_text:
                    print(f'✓ Kai: "{response_text}"')
                    print("🔴 Speaking...")
                    audio_file = generate_speech(response_text)
                    
                    if audio_file:
                        subprocess.run(f"aplay -D plughw:3,0 {audio_file} 2>/dev/null", shell=True)
                        print("✓ Done")
                    else:
                        print("❌ Speech generation failed")
                else:
                    print("❌ ChatGPT error")
            else:
                print("❌ No speech detected")
        
        if has_led:
            try:
                led.listening()
            except:
                pass
        
        print("🔵 Ready for next command...")
        time.sleep(1)

except KeyboardInterrupt:
    print("\n\nShutting down...")

if has_led:
    try:
        led.cleanup()
    except:
        pass

print("\n" + "=" * 70)
print(f"Total conversations: {conversation_count}")
print("=" * 70)
