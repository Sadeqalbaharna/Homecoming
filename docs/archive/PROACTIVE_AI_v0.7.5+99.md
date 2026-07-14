# 🤖 Proactive AI - Kai Initiates Conversations!

**Version:** v0.7.5+99  
**Status:** ✅ Implemented & Deployed

---

## 🎯 **What Is Proactive AI?**

Previously, Kai only responded when you spoke to him. Now **Kai initiates conversations** on his own! He'll reach out throughout the day with:

- 🌅 Morning greetings
- 🍽️ Lunch reminders
- 🌙 Evening check-ins
- 💭 Idle check-ins when you've been quiet
- 💪 Break reminders
- 🤓 Curiosity facts and questions

---

## 🚀 **How It Works**

### **Background Monitoring**
- Checks every **5 minutes** for triggers
- Tracks your last interaction time
- Respects **minimum 1 hour** between proactive messages
- Won't interrupt if you're actively chatting

### **Smart Triggers**

| Trigger | When | Example Messages |
|---------|------|------------------|
| **Morning Greeting** | 7-9 AM (once per day) | "Good morning! ☀️ Ready to make today awesome?" |
| **Lunch Reminder** | 12-1 PM (once per day) | "Time for lunch! 🍽️ Want some restaurant suggestions?" |
| **Evening Recap** | 8-10 PM (once per day) | "How was your day? Want to chat about it? 🌙" |
| **Idle Check-In** | After 4+ hours inactive | "Hey! Haven't heard from you in a while. Everything okay? 😊" |
| **Break Reminder** | Every 2 hours | "You've been focused for a while! Time for a quick break? 💪" |
| **Curiosity Fact** | Random (once per day) | "Fun fact: I just learned something cool! Want to hear? 🤓" |

---

## 🎬 **User Experience**

When Kai reaches out:

1. **Message appears in chat** - Kai's message shows up as a new chat bubble
2. **Window auto-expands** - Chat window opens if it was minimized
3. **TTS plays** - You hear Kai speaking the message
4. **Animation changes** - Kai switches to "speaking" animation
5. **You respond** - Reply naturally like any conversation!

---

## 🧪 **Testing Proactive AI**

### **Quick Test (Immediate Trigger)**

To test quickly, modify the trigger conditions temporarily:

```dart
// In lib/services/proactive_service.dart

// Change from 1 hour to 10 seconds for testing
static const Duration minTimeBetweenProactive = Duration(seconds: 10);

// Change idle threshold from 4 hours to 30 seconds
static const Duration idleThreshold = Duration(seconds: 30);
```

Then:
1. Launch the app
2. Don't interact for 30 seconds
3. Kai should reach out with a check-in message!

### **Time-Based Testing**

To test time-based triggers:

```dart
// Temporarily change morning hours
bool _shouldGreetMorning() {
  final now = DateTime.now();
  final hour = now.hour;
  
  // Change to current hour for testing
  if (hour != DateTime.now().hour) return false; // Will always trigger!
  
  return !_wasTriggeredToday(ProactiveTrigger.morningGreeting);
}
```

### **Manual Trigger (Debug)**

Add a debug button to trigger manually:

```dart
// In main_overlay.dart
ElevatedButton(
  onPressed: () {
    _proactive.onProactiveMessage?.call(
      "Hey! This is a test message! 🧪",
      ProactiveTrigger.curiosityFact,
    );
  },
  child: Text('Test Proactive'),
)
```

---

## 📊 **Analytics**

The system tracks:
- **Total proactive messages** sent
- **Per-trigger counts** (how many mornings, lunches, etc.)
- **Last trigger time** for each type
- **User response rate** (TODO: coming soon!)

View in Settings Screen (coming soon) or check SharedPreferences:
```dart
proactive_morningGreeting_count: 5
proactive_lunchReminder_count: 3
proactive_last_morningGreeting: 2025-11-04T08:15:00
```

---

## ⚙️ **Configuration**

### **Enable/Disable**

```dart
// Turn off proactive AI
await ProactiveService().setEnabled(false);

// Turn back on
await ProactiveService().setEnabled(true);
```

### **Adjust Frequency**

Edit `lib/services/proactive_service.dart`:

```dart
// Check more/less often
static const Duration checkInterval = Duration(minutes: 5); // Default

// More space between messages
static const Duration minTimeBetweenProactive = Duration(hours: 2); // Default: 1 hour

// Trigger idle check-in sooner
static const Duration idleThreshold = Duration(hours: 2); // Default: 4 hours
```

### **Customize Messages**

Add your own messages to arrays:

```dart
static const _morningGreetings = [
  "Good morning! ☀️ Ready to make today awesome?",
  "Your custom message here!",
  // Add more...
];
```

---

## 🔮 **Future Enhancements**

### **Phase 1 - Context Awareness** (Next)
- 📍 Location-based triggers (home vs work)
- 🔋 Battery-based reminders (low battery)
- 📅 Calendar integration (meeting reminders)
- 🌤️ Weather-based suggestions

### **Phase 2 - Learning** (Later)
- 🧠 Learn your active hours
- 📈 Adjust frequency based on your responses
- 💬 Personalized message styles
- 🎯 Topic-based suggestions from past conversations

### **Phase 3 - Advanced** (Future)
- 🔔 Push notifications when app is closed
- 📱 Smart notification timing (not during meetings)
- 🎮 Gamification (daily check-in streaks)
- 🤝 Multi-user support (different schedules)

---

## 🐛 **Troubleshooting**

### **Kai Never Reaches Out**

1. Check if enabled:
```dart
final prefs = await SharedPreferences.getInstance();
print(prefs.getBool('proactive_enabled')); // Should be true
```

2. Check last trigger times:
```dart
print(prefs.getString('proactive_last_morningGreeting'));
```

3. Verify service is running:
```dart
print(_proactive._checkTimer?.isActive); // Should be true
```

### **Too Many Messages**

Increase the minimum time between messages:
```dart
static const Duration minTimeBetweenProactive = Duration(hours: 3);
```

### **Messages Don't Play TTS**

Check audio player initialization:
```dart
// In _initializeProactiveAI()
await _playTTS(message); // This should be called
```

---

## 📝 **Code Files**

| File | Purpose |
|------|---------|
| `lib/services/proactive_service.dart` | Core proactive AI logic |
| `lib/main_overlay.dart` | Integration & callbacks |
| `lib/screens/settings_screen.dart` | Settings UI (optional) |
| `PROACTIVE_AI_v0.7.5+99.md` | This documentation |

---

## 🎉 **Success Criteria**

✅ Kai initiates at least 1 conversation per day  
✅ Messages feel natural and timely  
✅ User can enable/disable feature  
✅ No interruptions during active chats  
✅ Analytics track trigger effectiveness  
✅ TTS plays for proactive messages  
✅ Chat window opens automatically  

---

## 💡 **Tips**

- **Morning person?** Adjust morning greeting hours to match your wake time
- **Night owl?** Shift evening recap to later hours
- **Focus mode?** Disable proactive during work hours (coming soon)
- **Chatty Kai?** Decrease `minTimeBetweenProactive` to 30 minutes
- **Quiet Kai?** Increase to 3+ hours

---

**Kai is now proactive, not just reactive! 🚀**

*"Hey! Just wanted to say hi. How are you feeling today?" - Kai*
