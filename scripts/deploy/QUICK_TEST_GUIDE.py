#!/usr/bin/env python3
"""
🚀 QUICK TEST GUIDE - AI Music Query Generator
Run this to validate the system is working
"""

print("""
╔════════════════════════════════════════════════════════════════════════════╗
║                                                                            ║
║          🧠 AI MUSIC QUERY GENERATOR - QUICK TEST GUIDE                   ║
║                                                                            ║
╚════════════════════════════════════════════════════════════════════════════╝

📋 DEPLOYMENT STEPS
═══════════════════════════════════════════════════════════════════════════

OPTION 1: Deploy via SSH (if you have SSH access to Pi)
───────────────────────────────────────────────────────

1. SSH to Pi:
   ssh pi@192.168.2.5

2. Backup current listener:
   cp /home/pi/firebase_rest_listener_debug.py \\
      /home/pi/firebase_rest_listener_debug.py.backup.$(date +%s)

3. Pull latest code:
   cd /home/pi && git pull origin main

4. Stop old listener:
   pkill -f firebase_rest_listener_debug

5. Start new listener:
   sudo nohup python3 firebase_rest_listener_debug.py > listener.log 2>&1 &

6. Verify it's running:
   ps aux | grep firebase_rest_listener_debug | grep -v grep


OPTION 2: Manual File Transfer
───────────────────────────────

If you don't have SSH, use these steps:

1. The latest code is at: c:\\code\\homecoming_app\\firebase_rest_listener_debug.py
2. Transfer it to Pi using your preferred method (SCP, GitHub Desktop, etc)
3. Replace: /home/pi/firebase_rest_listener_debug.py
4. Restart listener (steps 4-5 above)


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

✅ VERIFICATION STEPS
═════════════════════════════════════════════════════════════════════════════

1. Check Pi is online:
   ping 192.168.2.5

2. Check listener is running:
   curl http://192.168.2.5:5001/kai/status

   Expected response:
   {"system_online":true, "led_strips":6, ...}

3. Test tavern scene:
   
   Windows PowerShell:
   ───────────────────
   $body = @{
       prompt = "Warm cozy tavern with medieval folk music"
       include_music = $true
   } | ConvertTo-Json
   
   Invoke-WebRequest -Uri "http://192.168.2.5:5001/kai/ambiance" \\
     -Method POST -Body $body -ContentType "application/json"

   Linux/Mac:
   ──────────
   curl -X POST http://192.168.2.5:5001/kai/ambiance \\
     -H "Content-Type: application/json" \\
     -d '{"prompt": "Warm cozy tavern with medieval folk music", "include_music": true}'


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

🧪 FULL TEST SUITE
═══════════════════════════════════════════════════════════════════════════

Run the Python test suite to test all scenes:

Windows:
   python test_ai_music_http.py

Mac/Linux:
   python3 test_ai_music_http.py

This will test:
✅ Tavern Scene
✅ Haunted Mansion  
✅ Epic Battle
✅ Peaceful Healing
✅ Thunderstorm
✅ Forest Scene
✅ Market Square


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📊 WHAT TO EXPECT
═════════════════════════════════════════════════════════════════════════════

When testing with the tavern prompt:

✨ Response should include:
──────────────────────────
{
  "success": true,
  "scene_name": "Tavern Scene",
  "description": "Immersive peaceful lighting for tavern",
  "lighting_applied": true,
  "music_applied": true,
  "music_query": "tavern medieval music ambient",      ← AI-GENERATED!
  "confidence": 0.6
}

🎵 In the logs, you should see:
───────────────────────────────
🧠 [MUSIC AI] Generated query from action=none, env=tavern, mood=neutral: 'tavern medieval music ambient'
🎵 [AMBIANCE] Searching for music: tavern medieval music ambient
[YouTube search happening...]
▶️ [MUSIC] Playing: "[YouTube Video Title]"

🎨 LED Lighting:
────────────────
Warm orange/brown lights should turn on (tavern atmosphere)

🔊 Audio:
──────────
Medieval tavern music should start playing on the Bluetooth speaker


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

🔧 TROUBLESHOOTING
═════════════════════════════════════════════════════════════════════════════

❌ "Connection refused" error:
   → Listener is not running
   → SSH to Pi and check: ps aux | grep firebase_rest_listener_debug
   → Check logs: tail -20 /home/pi/listener.log

❌ Response shows "music_query": null:
   → Old listener code is still running
   → Verify file was updated: grep "action_music_map" /home/pi/firebase_rest_listener_debug.py
   → Restart listener

❌ Music not playing but lighting works:
   → YouTube search might be failing
   → Check logs: tail -f /home/pi/listener.log | grep "AMBIANCE"
   → Try a different prompt with more specific keywords

❌ LED lights not turning on:
   → LED hardware may not be initialized
   → Check logs: tail -20 /home/pi/listener.log | grep "WS2812B"
   → This is OK - music will still work

✅ "Audio device" warnings:
   → This is normal if Bluetooth is already connected
   → Audio will still route to the speaker


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📱 TESTING FROM HOMECOMING APP
════════════════════════════════════════════════════════════════════════════

Once Pi is deployed, test from your phone:

1. Open Homecoming app
2. Say: "Hey Kai, start the tavern scene"
3. Watch for:
   ✅ Kai's response in the app
   ✅ LED lights turning on
   ✅ Music playing on speaker

The system will:
- Analyze your voice command
- Send to Pi via Firebase
- Generate AI music query: "tavern medieval music ambient"
- Search YouTube for matching video
- Play on Bluetooth speaker with coordinated LED lighting


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

✅ SUCCESS CHECKLIST
═════════════════════════════════════════════════════════════════════════════

After deployment, you should see:

□ Listener running (pid in ps output)
□ Status endpoint responding (HTTP 200)
□ Tavern test returns music_query value
□ Logs show "🧠 [MUSIC AI]" entries
□ LED lights turn on for ambiance test
□ Audio plays on Bluetooth speaker
□ All 7 D&D scenes test successfully
□ App voice commands trigger ambiance


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Need help? Check these files:
  • AI_MUSIC_DEPLOYMENT_GUIDE.md
  • AI_MUSIC_HOMECOMING_INTEGRATION.md
  • test_ai_music_http.py
  • deploy_on_pi.sh

Questions? Review the commit:
  git show bb3be86


                        🎉 READY TO TEST! 🎉
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
""")
