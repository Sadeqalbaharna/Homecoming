#!/usr/bin/env python3
"""
Diagnose audio/Bluetooth issues on the Pi
"""

import subprocess
import sys

def run_cmd(cmd, description):
    """Run a command and show the output"""
    print(f"\n{'='*60}")
    print(f"🔍 {description}")
    print(f"{'='*60}")
    print(f"Command: {' '.join(cmd)}")
    print("-" * 60)
    
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
        print(result.stdout)
        if result.stderr:
            print("STDERR:", result.stderr)
        return result.returncode == 0
    except subprocess.TimeoutExpired:
        print("❌ TIMEOUT")
        return False
    except Exception as e:
        print(f"❌ ERROR: {e}")
        return False

print("""
╔════════════════════════════════════════════════════════╗
║         AUDIO SYSTEM DIAGNOSTIC                       ║
║      Testing Bluetooth speaker connection             ║
╚════════════════════════════════════════════════════════╝
""")

# Check PulseAudio status
run_cmd(['pactl', 'info'], "PulseAudio Server Info")

# List all sinks
run_cmd(['pactl', 'list', 'short', 'sinks'], "Available Audio Sinks (Outputs)")

# Check Bluetooth sink specifically
sink_id = "bluez_output.39_3E_58_14_40_4A.1"
print(f"\n{'='*60}")
print(f"🔍 Checking Bluetooth Sink: {sink_id}")
print(f"{'='*60}")

# Check mute status
result = subprocess.run(
    ['pactl', 'get-sink-mute', sink_id],
    capture_output=True, text=True
)
if result.returncode == 0:
    print(f"Mute Status: {result.stdout.strip()}")
else:
    print(f"❌ Cannot query sink: {result.stderr}")

# Check volume
result = subprocess.run(
    ['pactl', 'get-sink-volume', sink_id],
    capture_output=True, text=True
)
if result.returncode == 0:
    print(f"Volume: {result.stdout.strip()}")
else:
    print(f"❌ Cannot query sink: {result.stderr}")

# List Bluetooth devices
run_cmd(['bluetoothctl', 'devices'], "Paired Bluetooth Devices")

# Check Bluetooth connection status
run_cmd(['bluetoothctl', 'info', '39:3E:58:14:40:4A'], "TG-129C Speaker Info")

# Test mpv directly
print(f"\n{'='*60}")
print(f"🔍 Testing mpv playback (will test HLS stream)")
print(f"{'='*60}")

test_url = "https://manifest.googlevideo.com/api/manifest/hls_playlist/expire/1767798424/ei/OCJeafPeMdzcp-oP6MXauQ8/ip/109.161.194.195/id/0d11479259cdf923/itag/234/source/youtube/requiressl/yes/ratebypass/yes/pfa/1/goi/133/sgoap/clen%3D58264265%3Bdur%3D3600.091%3Bgir%3Dyes%3Bitag%3D140%3Blmt%3D1726268535991482/rqh/1/hls_chunk_host/rr2---sn-15poc5-c5is.googlevideo.com/xpc/EgVo2aDSNQ%3D%3D/cps/20/met/1767776824,/mh/S0/mm/31,29/mn/sn-15poc5-c5is,sn-hju7enll/ms/au,rdu/mv/m/mvi/2/pl/24/rms/au,au/pcm2/no/initcwndbps/1355000/bui/AYUSA3AxQfo3uTRYFqTgqZth5pxZo3GJdJ5GBvwsexgzivEzOzX6O9ppwvyLFgPjG3XExfV_0L57pyws/spc/wH4Qq8wUw7vy0H9Rf_vjiPOdQv6-RS3EgaVaCGgtfGqbf1Imgzu_sOoUbG9XOMAx/vprv/1/playlist_type/DVR/dover/13/txp/5532434/mt/1767776472/fvip/5/short_key/1/keepalive/yes/fexp/51552689,51565116,51565682,51580968/sparams/expire,ei,ip,id,itag,source,requiressl,ratebypass,pfa,goi,sgoap,rqh,xpc,pcm2,bui,spc,vprv,playlist_type/sig/AJfQdSswRQIgdgBcNwN4SsgHw98GGIE2YnnTxvtpoZPFpefEA0mWd0YCIQCPKoP21E4Kp42lCYXU2yGMJdE3tQsBuvcRVtn9fDCsLQ%3D%3D/lsparams/hls_chunk_host,cps,met,mh,mm,mn,ms,mv,mvi,pl,rms,initcwndbps/lsig/APaTxxMwRAIgB0En2ymQxI5-8JY1FICjluWm2k63Km8BXQVGeEImtCICIEMY9RPjl7NK17ZOxCNHSRuQwUwDC6Ezu69YS6rUR-UM/playlist/index.m3u8"

print("Testing 5-second stream...")
print("You should hear music for 5 seconds on the TG-129C speaker")
print()

subprocess.run([
    'mpv',
    '--audio-device', f'pulse/{sink_id}',
    '--volume', '80',  # 80% volume for testing
    '--endof-file=quit',
    '--play-dir=forward',
    '--stream-record=no',
    '--no-video',
    f'--stop-playback-on-init-segment',
    f'{test_url}'
], timeout=6)

print("\n✅ Diagnostic complete!")
