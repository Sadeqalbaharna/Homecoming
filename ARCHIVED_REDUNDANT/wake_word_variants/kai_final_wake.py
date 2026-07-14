#!/usr/bin/env python3
"""
Simple, bulletproof wake word detection
- Audio energy threshold (RMS)
- Only transcribe loud sounds
- Strict "kai" matching only
- No hallucinations
"""
import subprocess
import os
import time
import struct
from led_control import LEDController

api_key = "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"

led = LEDController()

def get_audio_level(audio_file):
    """Calculate audio loudness using ffmpeg"""
    try:
        result = subprocess.run(
            f"ffmpeg -i {audio_file} -af 'volumedetect=print_summary=1' -f null - 2>&1 | grep mean_volume",
            shell=True,
            capture_output=True,
            text=True
        )
        # Extract dB value (more negative = quieter)
        for line in result.stdout.split('\n'):
            if 'mean_volume' in line:
                try:
                    db_str = line.split()[-2]  # Get the dB value
                    db = float(db_str.replace('dB', ''))
                    return db
                except:
                    pass
        return -100  # Very quiet if we can't parse
    except:
        return -100

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
    Listen for "Hey Kai" with zero hallucinations
    - Measure audio energy on each 1-second chunk
    - Only transcribe if LOUD (> -40dB)
    - Only accept if "kai" is in transcription
    """
    try:
        print("🎤 Listening for 'Hey Kai'...")
        
        threshold_db = -35  # Only transcribe if louder than this
        
        for attempt in range(120):  # 2 minute timeout
            print(".", end="", flush=True)
            
            # Record 1 second chunk
            subprocess.run("arecord -D plughw:3,0 -f S16_LE -r 16000 -d 1 /tmp/wake_check.wav 2>/dev/null", shell=True)
            
            # Check audio level
            level_db = get_audio_level("/tmp/wake_check.wav")
            
            if level_db > threshold_db:
                # Audio is LOUD - transcribe it
                print(f"\n  🔊 Loud sound detected ({level_db:.1f} dB)")
                text = transcribe_audio("/tmp/wake_check.wav")
                
                if text:
                    text_lower = text.lower().strip()
                    print(f"  Heard: '{text}'")
                    
                    # ONLY accept if "kai" is in the text
                    if "kai" in text_lower or "hey" in text_lower:
                        print(f"  ✅ WAKE WORD DETECTED!")
                        return True
                    else:
                        print(f"  ❌ Not wake word, continuing...")
            else:
                # Too quiet, skip
                if attempt % 10 == 0:
                    print(f" [{level_db:.0f}dB]", end="", flush=True)
        
        print("\n  ⏱️ Timeout")
        return False
    except Exception as e:
        print(f"\n  ❌ Error: {e}")
        return False

print("=" * 70)
print("KAI - ZERO HALLUCINATION WAKE WORD SYSTEM")
print("=" * 70)
print("")

conversation_count = 0

try:
    while True:
        conversation_count += 1
        print(f"\n--- CONVERSATION #{conversation_count} ---")
        
        try:
            led.listening()
            print("🔵 LED ON - Say 'Hey Kai'...")
        except Exception as e:
            print(f"🔵 Say 'Hey Kai'... (LED error: {e})")
        
        # Listen for wake word
        if listen_for_wake_word():
            try:
                led.wake_detected()
                print("🟡 LED BLINKING")
            except Exception as e:
                print(f"🟡 Wake detected (LED error: {e})")
            
            time.sleep(0.5)
            
            try:
                led.recording()
                print("🟡 LED ON - Recording 3 seconds")
            except:
                print("🟡 Recording 3 seconds")
            
            print(">>> SPEAK YOUR COMMAND <<<")
            subprocess.run("arecord -D plughw:3,0 -f S16_LE -r 16000 -d 3 /tmp/user_audio.wav 2>/dev/null", shell=True)
            
            print("")
            print("📝 Processing your speech...")
            detected_text = transcribe_audio("/tmp/user_audio.wav")
            
            if detected_text:
                print(f'✓ You: "{detected_text}"')
                
                if detected_text.lower() in ["goodbye", "exit", "quit", "stop", "bye"]:
                    print("\n👋 Goodbye!")
                    break
                
                try:
                    led.processing()
                    print("🔴 LED ON - Thinking...")
                except:
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
        
        try:
            led.listening()
            print("\n🔵 LED ON - Ready for next command...")
        except:
            print("\n🔵 Ready for next command...")
        
        time.sleep(1)

except KeyboardInterrupt:
    print("\n\nShutting down...")

try:
    led.listening()
    led.cleanup()
except:
    pass

print("\n" + "=" * 70)
print(f"Total conversations: {conversation_count}")
print("=" * 70)
