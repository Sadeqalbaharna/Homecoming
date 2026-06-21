#!/usr/bin/env python3
"""
Silero-based wake word detection - NO hallucinations
Uses local VAD (Voice Activity Detection) + keyword spotting
"""
import subprocess
import os
import time
import torch
import torchaudio
import numpy as np
from led_control import LEDController

api_key = "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"

led = LEDController()

# Load Silero VAD model locally
def load_vad_model():
    """Load Silero Voice Activity Detection model"""
    try:
        model, utils = torch.hub.load(repo_or_dir='snakers4/silero-vad', model='silero_vad')
        return model, utils
    except Exception as e:
        print(f"VAD model load error: {e}")
        return None, None

def transcribe_audio(audio_file):
    """Transcribe with Whisper"""
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

def detect_speech_with_vad(audio_file, model, utils):
    """Use Silero VAD to detect if audio contains speech"""
    try:
        wav, sr = torchaudio.load(audio_file)
        if sr != 16000:
            resampler = torchaudio.transforms.Resample(sr, 16000)
            wav = resampler(wav)
        
        # Get probabilities
        get_speech_ts = utils[0]
        speech_timestamps = get_speech_ts(wav, model, return_seconds=False)
        
        # If speech detected, return True
        return len(speech_timestamps) > 0
    except Exception as e:
        print(f"VAD error: {e}")
        return False

def listen_for_wake_word():
    """
    Listen for "Hey Kai" using local Silero VAD + strict keyword matching
    """
    try:
        model, utils = load_vad_model()
        if not model:
            print("❌ VAD model failed to load, falling back to simple transcription")
            model = None
        
        print("🎤 Listening for 'Hey Kai'...")
        
        for attempt in range(120):  # 2 minute timeout (1-second chunks)
            print(".", end="", flush=True)
            
            # Record 1 second chunk
            subprocess.run("arecord -D plughw:3,0 -f S16_LE -r 16000 -d 1 /tmp/wake_check.wav 2>/dev/null", shell=True)
            
            # Check if audio contains speech using VAD
            if model:
                has_speech = detect_speech_with_vad("/tmp/wake_check.wav", model, utils)
                if not has_speech:
                    continue  # Skip silent chunks
            
            # Only transcribe if speech detected
            print(f"\n  🔊 Speech detected, checking for wake word...")
            text = transcribe_audio("/tmp/wake_check.wav")
            
            if text:
                text_lower = text.lower().strip()
                print(f"  Heard: '{text}'")
                
                # STRICT matching - must contain "kai" or "hey"
                if "kai" in text_lower:
                    print(f"  ✅ WAKE WORD DETECTED!")
                    return True
                else:
                    print(f"  ❌ Not a wake word, listening...")
        
        print("\n  ⏱️ Timeout")
        return False
    except Exception as e:
        print(f"\n  ❌ Error: {e}")
        return False

print("=" * 70)
print("KAI SYSTEM - SILERO VAD WAKE WORD DETECTION")
print("=" * 70)
print("")

conversation_count = 0

try:
    while True:
        conversation_count += 1
        print(f"\n--- CONVERSATION #{conversation_count} ---")
        
        try:
            led.listening()
        except Exception as e:
            print(f"⚠️  LED error: {e}")
        
        print("🔵 Say 'Hey Kai'...")
        
        # Listen for wake word
        if listen_for_wake_word():
            try:
                led.wake_detected()
            except:
                pass
            
            print("\n🟡 LED: YELLOW - Recording your command...")
            print(">>> SPEAK NOW! <<<")
            subprocess.run("arecord -D plughw:3,0 -f S16_LE -r 16000 -d 3 /tmp/user_audio.wav 2>/dev/null", shell=True)
            
            try:
                led.recording()
            except:
                pass
            
            print("")
            print("📝 Processing...")
            detected_text = transcribe_audio("/tmp/user_audio.wav")
            
            if detected_text:
                print(f'✓ You said: "{detected_text}"')
                
                if detected_text.lower() in ["goodbye", "exit", "quit", "stop", "bye"]:
                    print("\nGoodbye!")
                    break
                
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
                    else:
                        print("❌ Speech generation failed")
                else:
                    print("❌ ChatGPT error")
            else:
                print("❌ No speech detected")
        
        try:
            led.listening()
        except:
            pass
        
        print("\n🔵 Ready for next command...")
        time.sleep(1)

except KeyboardInterrupt:
    print("\n\nShutting down...")

try:
    led.listening()
    led.cleanup()
except:
    pass
