# Quick Start Guide - Unified Expanded Window

## 🎯 What You'll See

### Opening the Interface

**Method 1: Chat Button**
1. Tap Kai avatar → Circular menu appears
2. Tap Chat button (top, 12 o'clock)
3. **Full-screen window opens** with **Chat tab active**
4. See your conversation history
5. Type and send messages

**Method 2: Personality Button**
1. Tap Kai avatar → Menu
2. Tap Personality button (right, 3 o'clock)
3. **Full-screen window opens** with **Personality tab active**
4. See your MBTI type, traits, mood

**Method 3: Analytics Button**
1. Tap Kai avatar → Menu
2. Tap Analytics button (bottom-left, ~7-8 o'clock)
3. **Full-screen window opens** with **Analytics tab active**
4. See usage stats, costs, activity

### The Interface

```
┌─────────────────────────────────────┐
│ 🌟 Kai AI Companion            [✕]  │ ← Header
├─────────────────────────────────────┤
│ [💬 Chat] [🧠 Personality] [📊 Analytics] │ ← Tab Bar
├─────────────────────────────────────┤
│                                     │
│                                     │
│          Tab Content                │ ← Active tab
│                                     │
│                                     │
└─────────────────────────────────────┘
```

## 📱 Tab-by-Tab Tour

### Chat Tab
```
┌─────────────────────────────────────┐
│ [💬 Chat] [Personality] [Analytics] │
├─────────────────────────────────────┤
│                                     │
│  ┌───────────────────────────┐     │
│  │ Your message here         │     │ ← Your messages
│  └───────────────────────────┘     │   (right-aligned)
│                                     │
│     ┌───────────────────────────┐  │
│     │ Kai's response            │  │ ← Kai's messages
│     └───────────────────────────┘  │   (left-aligned)
│     [💾 Used 3 memories]           │   + Memory badge
│                                     │
├─────────────────────────────────────┤
│ [Message Kai...]            [Send]  │ ← Input field
└─────────────────────────────────────┘
```

**Features:**
- Scroll through full history
- Timestamps on messages ("2m ago", "1h ago")
- Memory badges show when Kai used memories
- Loading indicator: "Kai is thinking..."
- Empty state if no messages yet

### Personality Tab
```
┌─────────────────────────────────────┐
│ [Chat] [🧠 Personality] [Analytics] │
├─────────────────────────────────────┤
│                                     │
│  ╔═════════════════════════════╗   │
│  ║         E N F P             ║   │ ← MBTI Card
│  ║  The Campaigner             ║   │   (gradient bg)
│  ╚═════════════════════════════╝   │
│                                     │
│  Core Traits                        │
│  ┌─────────────────────────────┐   │
│  │ Extraversion        [75] ━━  │   │ ← Trait bars
│  │ Intuition           [82] ━━  │   │   with values
│  │ Feeling             [68] ━━  │   │
│  │ Perceiving          [71] ━━  │   │
│  └─────────────────────────────┘   │
│                                     │
│  Current Mood                       │
│  ┌─────────────────────────────┐   │
│  │ Valence             [65] ━━  │   │
│  │ Energy              [70] ━━  │   │
│  │ Warmth              [80] ━━  │   │
│  │ ...                         │   │
│  └─────────────────────────────┘   │
│                                     │
│  [🔄 Refresh]                       │
└─────────────────────────────────────┘
```

**Features:**
- MBTI type with description
- Color-coded progress bars:
  - 🟢 Green (70-100): High
  - 🔵 Blue (50-69): Moderate
  - 🟠 Orange (30-49): Low
  - 🔴 Red (0-29): Very Low
- Real-time refresh button
- Scrollable if content is long

### Analytics Tab
```
┌─────────────────────────────────────┐
│ [Chat] [Personality] [📊 Analytics] │
├─────────────────────────────────────┤
│                                     │
│  Usage Statistics                   │
│                                     │
│  ┌─────────────────────────────┐   │
│  │ 💬  Total Messages          │   │
│  │     42                       │   │ ← Stat cards
│  └─────────────────────────────┘   │
│                                     │
│  ┌─────────────────────────────┐   │
│  │ 💵  OpenAI Cost             │   │
│  │     $0.0234                  │   │
│  └─────────────────────────────┘   │
│                                     │
│  ┌─────────────────────────────┐   │
│  │ 🎙️  ElevenLabs Characters    │   │
│  │     1,523                    │   │
│  └─────────────────────────────┘   │
│                                     │
│  Recent Activity                    │
│  ┌─────────────────────────────┐   │
│  │ ➤ Message sent  2 min ago   │   │
│  │ ➤ Personality   15 min ago  │   │
│  │ ➤ Voice gen     1 hour ago  │   │
│  └─────────────────────────────┘   │
│                                     │
│  [🔄 Refresh Stats]                 │
└─────────────────────────────────────┘
```

**Features:**
- Live usage statistics
- Cost tracking
- Activity timeline
- Refresh button for updates
- Icon-coded stat cards

## 🎮 How to Use

### Basic Navigation
1. **Switch tabs**: Tap any tab at top
2. **Close window**: Tap [✕] button (top-right)
3. **Return to Kai**: Close button shrinks back to compact Kai
4. **Scroll**: Swipe up/down in any tab
5. **Type**: Tap input field (Chat tab only)

### Pro Tips
- **Direct access**: Use different menu buttons to open specific tabs
- **Context retention**: Switch tabs without losing your place
- **Quick close**: Tap [✕] or tap outside (if enabled)
- **Refresh data**: Use refresh buttons in Personality/Analytics tabs
- **Scroll smoothly**: Window is locked, won't move accidentally

### Keyboard Shortcuts (future)
- Coming soon: Tab switching, quick close

## 🐛 Troubleshooting

**Window doesn't open:**
- Check if overlay permission is enabled
- Restart app
- Check logs with `adb logcat`

**Tabs won't switch:**
- Tap tab again
- Check for loading state
- Force close and reopen

**Data not loading:**
- Check internet connection
- Verify Firebase connection
- Use refresh buttons
- Check API keys in debug window

**Window is draggable (shouldn't be):**
- This is a bug - report it
- Expected: Locked in place
- Workaround: Reopen window

## 📏 Dimensions

**Full-Screen:**
- Width: Match parent (100%)
- Height: Match parent (100%)
- Status bar: Visible
- Navigation bar: Visible

**Locked:**
- Cannot drag
- Cannot resize
- Stable for scrolling/typing

## 🎨 Theme

**Dark Mode:**
- Background: Pure black (#000000)
- Cards: Dark gray (#212121)
- Accent: Purple (#9C27B0)
- Text: White / Gray gradient
- Borders: Subtle purple/gray

## ⚡ Performance

**Expectations:**
- Tab switch: Instant (<100ms)
- Data load: 1-2 seconds
- Scroll: Buttery smooth (60fps)
- Input lag: Minimal (<50ms)

**If slow:**
- Check device memory
- Close other apps
- Restart Kai
- Clear cache (future feature)

## 📱 Installation

```powershell
# Connect device
adb devices

# Install
adb install -r build/app/outputs/flutter-apk/app-debug.apk

# Or use Firebase App Distribution link
```

## 🎉 Enjoy!

You now have a professional, stable interface for extended interaction with Kai!

**Key Benefits:**
✅ No more closing/reopening windows
✅ Faster navigation between features
✅ Stable, locked interface
✅ Professional dark theme
✅ Context preservation
✅ Smooth performance

---

**Need help?** Check logs or create an issue on GitHub!
