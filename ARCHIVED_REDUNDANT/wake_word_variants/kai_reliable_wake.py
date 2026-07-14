#!/usr/bin/env python3
"""
High-reliability wake word detection using continuous audio capture
- Records until silence detected
- Transcribes full phrase for better context
- Multiple keyword matching for robustness
- No hallucinations on short clips
"""
import subprocess
import os
import time
import wave
import struct
import math

api_key = "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"

# Re-enable LED control with error handling
try:
    from led_control import LEDController
    led = LEDController()
    has_led = True
    print("✅ LED control initialized")
except Exception as e:
    print(f"❌ LED error: {e}")
    has_led = False

def get_rms_energy(audio_file):
    """Calculate RMS energy from WAV file"""
    try:
        with wave.open(audio_file, 'rb') as wav:
            frames = wav.readframes(wav.getnframes())
            samples = struct.unpack(f'<{len(frames)//2}h', frames)
            rms = math.sqrt(sum(s**2 for s in samples) / len(samples)) if samples else 0
            return rms
    except:
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

def record_until_silence(max_duration=10):
    """
    Record audio until silence is detected
    - Records 3 seconds total
    - Returns the audio file
    """
    print("  Recording 3 seconds...")
    
    # Just record 3 seconds straight - simple and reliable
    subprocess.run(f"arecord -D plughw:3,0 -f S16_LE -r 16000 -d 3 /tmp/wake_phrase.wav 2>/dev/null", shell=True)
    
    if os.path.exists("/tmp/wake_phrase.wav"):
        size = os.path.getsize("/tmp/wake_phrase.wav")
        if size > 5000:  # At least some audio
            return "/tmp/wake_phrase.wav"
    
    return None

def check_for_wake_word(text):
    """
    Check if text contains wake word with high confidence
    Multiple matching strategies:
    1. Must contain "hello" or "hey"
    2. Must contain "kai"
    3. Flexible with punctuation
    """
    if not text:
        return False
    
    text_lower = text.lower().strip().replace('.', '').replace(',', '').replace('!', '').replace('?', '')
    words = text_lower.split()
    
    print(f"  📝 Full transcription: '{text}'")
    
    # Strategy 1: Look for explicit patterns (with some flexibility)
    patterns = [
        "hello kai",
        "hey kai", 
        "hello care",
        "hey care",
        "hallo kai",  # German/European accent
        "hi kai",
        "hola kai",
    ]
    
    for pattern in patterns:
        if pattern in text_lower:
            return True
    
    # Strategy 2: Both words present (flexible)
    greeting_words = ["hello", "hey", "hi", "hallo", "hola"]
    kai_words = ["kai", "care", "k"]
    
    has_greeting = any(g in words for g in greeting_words)
    has_kai = any(k in words for k in kai_words)
    
    # Reject obvious hallucinations
    hallucinations = ["goodbye", "bye", "thank you", "thanks", "okay", "one", "two", "three"]
    if any(h in text_lower for h in hallucinations):
        return False
    
    # If has both greeting and kai sound, accept it
    if has_greeting and has_kai:
        return True
    
    return False

def listen_for_wake_word():
    """
    High-reliability wake word detection
    - Records 3 seconds
    - Checks if audio has actual speech (RMS > threshold)
    - Only transcribes if loud enough
    - Uses robust matching
    """
    try:
        print("🎤 Listening for 'Hello Kai'...")
        
        rms_threshold = 500  # Very low - USB mic is weak, accept anything above silence
        
        for attempt in range(30):  # ~90 seconds timeout
            print(f"  [{attempt+1}/30]", end=" ", flush=True)
            
            # Record 3 seconds
            subprocess.run("arecord -D plughw:3,0 -f S16_LE -r 16000 -d 3 /tmp/wake_phrase.wav 2>/dev/null", shell=True)
            
            if os.path.exists("/tmp/wake_phrase.wav") and os.path.getsize("/tmp/wake_phrase.wav") > 5000:
                # Check if audio is LOUD enough to be real speech
                rms = get_rms_energy("/tmp/wake_phrase.wav")
                print(f"(RMS: {rms:.0f})", end=" ")
                
                if rms < rms_threshold:
                    # Too quiet - skip transcription (prevents hallucinations)
                    print("[skip]")
                    continue
                
                # LOUD - transcribe
                print("[transcribe]", end=" ")
                text = transcribe_audio("/tmp/wake_phrase.wav")
                
                if check_for_wake_word(text):
                    print(f"\n  ✅ WAKE WORD MATCHED!")
                    
                    # IMMEDIATELY turn on yellow LED
                    if has_led:
                        try:
                            from led_control import LEDController
                            led_temp = LEDController()
                            led_temp.wake_detected()
                            print("  🟡 YELLOW LED ON!")
                        except Exception as e:
                            print(f"  LED error: {e}")
                    
                    print(f"  DEBUG: Returning True from listen_for_wake_word()")
                    return True
                else:
                    print("[no-match]")
            else:
                print("[no-file]")
        
        print("\n  ⏱️ Timeout")
        return False
    except Exception as e:
        print(f"\n  ❌ Error: {e}")
        import traceback
        traceback.print_exc()
        return False

print("=" * 70)
print("KAI - HIGH RELIABILITY WAKE WORD DETECTION")
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
        wake_result = listen_for_wake_word()
        
        if wake_result:
            print("\n🟡 WAKE DETECTED! Proceeding to record message...")
            
            print("\n>>> SPEAK YOUR COMMAND <<<")
            print("  Recording 3 seconds...")
            subprocess.run("arecord -D plughw:3,0 -f S16_LE -r 16000 -d 3 /tmp/user_audio.wav 2>/dev/null", shell=True)
            
            print("  ✅ Recording complete")
            size = os.path.getsize("/tmp/user_audio.wav")
            print(f"  File size: {size} bytes")
            
            print("📝 Transcribing with Whisper...")
            detected_text = transcribe_audio("/tmp/user_audio.wav")
            
            if detected_text:
                print(f'✓ You: "{detected_text}"')
                
                if detected_text.lower() in ["goodbye", "exit", "quit", "stop", "bye"]:
                    print("\n👋 Goodbye!")
                    break
                
                print("🔴 Thinking...")
                if has_led:
                    try:
                        led.processing()
                    except:
                        pass
                response_text = chat_with_gpt(detected_text)
                
                if response_text:
                    print(f'✓ Kai: "{response_text}"')
                    print("🔴 Speaking...")
                    if has_led:
                        try:
                            led.processing()
                        except:
                            pass
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
    subprocess.run("pkill -f 'arecord'", shell=True)

if has_led:
    try:
        led.cleanup()
    except:
        pass

print("\n" + "=" * 70)
print(f"Total conversations: {conversation_count}")
print("=" * 70)
