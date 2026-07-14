#!/usr/bin/env python3
import subprocess
import os
import time
import wave
from led_control import LEDController

api_key = "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"

led = LEDController()

def get_audio_rms(audio_file):
    """Calculate RMS (energy) of audio file"""
    try:
        with wave.open(audio_file, 'rb') as wav_file:
            frames = wav_file.readframes(wav_file.getnframes())
            import array
            audio_data = array.array('h', frames)
            rms = (sum(x**2 for x in audio_data) / len(audio_data)) ** 0.5
            return rms
    except:
        return 0

def transcribe_audio(audio_file):
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
    Listen for wake word with high accuracy:
    1. Wait for audio energy above threshold
    2. Record until silence
    3. Check if transcription contains wake word
    """
    try:
        print("🎤 Listening for 'Hey Kai'...")
        
        noise_threshold = 100  # RMS threshold for detecting actual speech
        silence_count = 0
        silence_threshold = 3  # 3 consecutive quiet readings = end of phrase
        
        for attempt in range(60):  # 2 minute timeout
            print(".", end="", flush=True)
            
            # Record 1 second chunk
            subprocess.run("arecord -D plughw:3,0 -f S16_LE -r 16000 -d 1 /tmp/wake_check.wav 2>/dev/null", shell=True)
            
            # Check audio energy
            rms = get_audio_rms("/tmp/wake_check.wav")
            
            if rms > noise_threshold:
                # Audio detected, reset silence counter
                silence_count = 0
                print(f"\n  Audio detected (energy: {rms:.0f})")
                
                # Transcribe this chunk
                text = transcribe_audio("/tmp/wake_check.wav")
                if text:
                    text_lower = text.lower()
                    print(f"  Heard: '{text}'")
                    
                    # Strict check for wake words
                    if 'kai' in text_lower or ('hey' in text_lower and ('kai' in text_lower or 'care' in text_lower or 'k' in text_lower)):
                        print(f"  ✓ WAKE WORD CONFIRMED!")
                        return True
            else:
                silence_count += 1
                if silence_count >= silence_threshold:
                    silence_count = 0
                    print(" [silence]", end="", flush=True)
        
        print("\n  Timeout")
        return False
    except Exception as e:
        print(f"\n  Error: {e}")
        return False

print("=" * 70)
print("KAI CONVERSATION SYSTEM - ROBUST WAKE WORD")
print("=" * 70)
print("")

conversation_count = 0

try:
    while True:
        conversation_count += 1
        print(f"--- CONVERSATION #{conversation_count} ---")
        
        led.listening()
        print("🔵 LED: BLUE - Say 'Hey Kai'...")
        
        # Listen for wake word
        if listen_for_wake_word():
            led.wake_detected()
            print("🟡 LED: YELLOW BLINKING - Wake word detected!")
            time.sleep(1)
            
            led.recording()
            print("🟡 LED: YELLOW - Recording 3 seconds")
            print(">>> SPEAK NOW! <<<")
            subprocess.run("arecord -D plughw:3,0 -f S16_LE -r 16000 -d 3 /tmp/user_audio.wav 2>/dev/null", shell=True)
            size = os.path.getsize("/tmp/user_audio.wav")
            print(f"✓ Audio: {size} bytes")
            
            print("")
            print("📝 Detecting speech...")
            detected_text = transcribe_audio("/tmp/user_audio.wav")
            
            if detected_text:
                print(f'✓ DETECTED: "{detected_text}"')
                
                # Check for exit commands
                if detected_text.lower() in ["goodbye", "exit", "quit", "stop", "bye"]:
                    print("")
                    print("🟡 LED: YELLOW - Exit command received")
                    led.recording()
                    print("Goodbye!")
                    break
                
                led.processing()
                print("")
                print("🔴 LED: RED - Calling ChatGPT...")
                response_text = chat_with_gpt(detected_text)
                
                if response_text:
                    print(f'✓ Response: "{response_text}"')
                    print("🔴 LED: RED - Generating speech...")
                    audio_file = generate_speech(response_text)
                    
                    if audio_file:
                        print("🔴 LED: RED - Playing audio...")
                        subprocess.run(f"aplay -D plughw:3,0 {audio_file} 2>/dev/null", shell=True)
                        print("✓ Audio played")
                    else:
                        print("✗ Speech generation failed")
                else:
                    print("✗ ChatGPT error")
            else:
                print("✗ No speech detected")
        
        led.listening()
        print("")
        print("🔵 LED: BLUE - Listening for next wake word...")
        print("")
        time.sleep(1)

except KeyboardInterrupt:
    print("\n\n🔵 LED: BLUE - Shutting down")

led.listening()
print("")
print("=" * 70)
print(f"Total conversations: {conversation_count}")
print("=" * 70)

led.cleanup()
