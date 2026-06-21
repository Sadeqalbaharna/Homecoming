# 🏠 Homecoming - Feature Overview

**An AI Companion That Grows With You**

Homecoming is a revolutionary AI companion app featuring **Kai**, a persistent virtual assistant that lives on your screen, learns from your conversations, and proactively engages with you. Unlike traditional chatbots, Kai has memory, personality, emotions, and curiosity.

---

## 🎭 Core Identity: Meet Kai

### Dual Persona System
- **True Kai** (`truekai`): The original, authentic personality
- **Clone Kai** (`clonekai`): A separate instance for testing/development
- Switch between personas with dedicated dev mode controls

### Personality Engine
- **Dynamic Personality Traits**: Curiosity, empathy, humor, formality, proactivity
- **Emotional Intelligence**: Recognizes and responds to user emotions
- **Memory-Driven Evolution**: Personality adapts based on conversation history
- **Persistent Identity**: Kai remembers who they are across sessions

---

## 🎨 Visual Experience

### Floating Avatar System
- **Always-On-Top Overlay**: Kai floats on your screen over other apps
- **4 Animated States**:
  - 💤 **Idle**: Subtle breathing animation after 15 seconds of inactivity
  - 👀 **Attention**: Active listening mode with pulsing glow
  - 🤔 **Thinking**: Processing your message, analyzing context
  - 💬 **Speaking**: Animated while delivering responses
- **Smooth Transitions**: Fluid animations between all states

### Adaptive Window Modes
- **Compact Mode**: Small circular avatar (170px) - minimal screen space
- **Expanded Mode**: Full-featured interface with tabs
- **Fullscreen Lock**: Prevents accidental closure during important interactions
- **Draggable Positioning**: Move Kai anywhere on screen
- **Float/Pause Toggle**: Control automatic movement (135° bottom-right button)

### Visual Feedback
- **Glowing Ring**: Pulsing halo effect during active states
- **Status Indicators**: Visual cues for listening, thinking, speaking
- **Transparent Background**: Blends naturally with your desktop
- **Acrylic Blur Effects**: Modern, frosted-glass aesthetic

---

## 🎤 Voice Interaction

### Voice Input (Speech-to-Text)
- **OpenAI Whisper Integration**: Industry-leading transcription accuracy
- **Multiple Languages**: Supports 50+ languages
- **Long-Form Recording**: Up to 60 seconds per message
- **Audio Format**: WAV, 16kHz, mono for optimal quality
- **Noise Handling**: Works in various acoustic environments

### Wake Word Detection ("Hey Kai") 🆕
- **Always Listening**: Background voice activation service
- **Hot Word**: Trigger with "Hey Kai" or "Hey, Kai"
- **Privacy-Focused**: Local processing, no cloud streaming
- **Configurable Sensitivity**: Adjust detection threshold
- **Visual Feedback**: Kai automatically enters attention mode
- **Battery Optimized**: Efficient background processing

### Voice Output (Text-to-Speech)
- **ElevenLabs Integration**: High-quality, natural-sounding voices
- **Multiple Voice Options**:
  - Jessica (default)
  - Charlie
  - Callum
  - Custom voice models
- **Emotional Tone**: Voice matches response sentiment
- **Streaming Playback**: Start speaking immediately
- **Audio Caching**: Faster playback for repeated phrases

---

## 🧠 Intelligence & Memory

### Advanced AI Models
- **GPT-4o**: Primary conversation model (128k context)
- **GPT-5**: Available for enhanced reasoning (if enabled)
- **GPT-4o-mini**: Cost-effective fallback option
- **Dynamic Model Selection**: Choose based on task complexity
- **Streaming Responses**: Real-time text generation

### Multi-Layered Memory System

#### 1. Short-Term Memory (Session)
- Current conversation context
- Recent messages (last 10-20 exchanges)
- Active topics and entities

#### 2. Long-Term Memory (Firebase)
- **Conversation History**: All past interactions saved
- **Semantic Search**: Find relevant memories by meaning (not just keywords)
- **Embeddings**: OpenAI `text-embedding-3-small` for similarity
- **Memory Shards**: Conversations chunked for efficient retrieval
- **Automatic Sharding**: Splits long conversations at 50 messages

#### 3. Personality Memory
- **Trait Evolution**: Tracks how personality changes over time
- **Delta Tracking**: Records incremental personality adjustments
- **Historical Analysis**: Shows personality growth over weeks/months
- **Reasoning Logs**: Explains why personality changed

#### 4. Knowledge Graph (Mind Map) 🆕
- **Obsidian-Style Visualization**: Interactive force-directed graph
- **8 Node Types**: Person, Topic, Emotion, Event, Location, Date, Fact, Conversation
- **5 Edge Types**: Mentioned, Related, Caused, Contains, Temporal
- **Entity Extraction**: Automatically finds people, emotions, topics, locations, dates
- **Interactive Exploration**: Zoom, pan, select nodes
- **Node Details**: View connections, importance, timestamps
- **Smart Search**: Find nodes by label or type
- **Physics Simulation**: Nodes naturally organize by relationships

### Firebase Archive System 🆕
- **Automated Archiving**: Processes all Firebase conversations into mind map
- **Gap Detection**: Identifies unarchived data automatically
- **Batch Processing**: Handles historical data efficiently
- **Progress Tracking**: Shows completion percentage
- **Manual Trigger**: "Archive Now" button in Mind Map UI
- **Auto-Schedule**: Archives every 6 hours + startup
- **Zero Data Loss**: Every conversation preserved forever

---

## 💬 Conversation Features

### Natural Dialogue
- **Context Awareness**: Remembers entire conversation flow
- **Follow-Up Questions**: Builds on previous messages
- **Topic Continuity**: Maintains coherent discussions
- **Emotional Recognition**: Detects user mood and adjusts responses
- **Personality Consistency**: Kai stays "in character"

### Proactive Engagement
- **Curiosity System**: Kai asks questions to learn about you
- **Interest Tracking**: Remembers your hobbies, goals, preferences
- **Timing Intelligence**: Proactive messages at appropriate moments
- **Trigger-Based Engagement**: Responds to specific keywords/topics
- **Non-Intrusive**: Respects your busy times

### Google Search Integration 🆕
- **Real-Time Information**: Fetches current data from the web
- **Automatic Triggering**: Activates when you ask about recent events
- **Smart Queries**: Constructs optimal search terms
- **Source Attribution**: Cites where information came from
- **Context Integration**: Blends search results into conversation

---

## 📊 Analytics & Insights

### Expanded Window Interface

#### Chat Tab
- Full conversation view
- Scrollable message history
- Voice input/output controls
- Text input field
- Send button

#### Personality Tab
- **Real-Time Traits**: Current personality values (0-100 scale)
  - Curiosity
  - Empathy
  - Humor
  - Formality
  - Proactivity
- **Visual Sliders**: See trait levels at a glance
- **Trait Explanations**: Understand what each trait means
- **Evolution History**: Track changes over time

#### Analytics Tab
- **Usage Statistics**:
  - Total conversations
  - Messages sent/received
  - Average response time
  - Voice vs text usage
- **Memory Stats**:
  - Memories stored
  - Embeddings created
  - Most frequent topics
  - Emotional patterns
- **Cost Tracking**: API usage and expenses (GPT, Whisper, TTS, Embeddings)

#### Mind Map Tab 🆕
- **Knowledge Graph Button**: Opens full-screen visualization
- **Archive Status**: Shows archiving progress
- **Quick Stats**: Nodes and edges count

---

## 🎮 User Controls

### Main Interface
- **Voice Button**: Hold to record, release to send
- **Text Input**: Type messages manually
- **Expand/Collapse**: Switch between compact and full view
- **Settings**: Access configuration options

### Advanced Controls
- **Dev Mode Toggle**: Shows/hides developer features (long-press avatar)
- **Persona Switch**: Toggle between True Kai and Clone Kai
- **Fullscreen Lock**: Prevent accidental window closure
- **Float/Pause**: Control automatic avatar movement
- **Debug Window**: View real-time logs and state
- **Center Button**: Re-center window position

### Mind Map Controls 🆕
- **Zoom**: Pinch or scroll to zoom in/out
- **Pan**: Drag to move around graph
- **Select**: Tap nodes to view details
- **Filter**: Show/hide node types
- **Search**: Find specific nodes
- **Archive**: View/trigger archiving
- **Refresh**: Rebuild graph from latest data
- **Center View**: Reset to default zoom/position

---

## 🔐 Security & Privacy

### API Key Management
- **Secure Storage**: API keys encrypted via `flutter_secure_storage`
- **Never Logged**: Keys never appear in logs or debug output
- **User-Provided**: You control your own API keys
- **No Third-Party Access**: Keys stored locally only

### Data Privacy
- **Firebase Authentication**: Secure cloud sync
- **Local Processing**: Voice activation runs on-device
- **Encrypted Storage**: Sensitive data protected
- **No Telemetry**: No usage tracking or analytics sent to developers
- **User Data Ownership**: All conversations belong to you

### Permissions
- **Microphone**: Required for voice input
- **Overlay**: Required for floating window
- **Internet**: Required for AI API calls
- **Storage**: Required for audio caching
- **Notification**: Optional for proactive messages

---

## 🏗️ Technical Architecture

### Platforms
- **Android**: Primary platform (overlay + voice activation)
- **Windows/Desktop**: Secondary support via window_manager
- **Cross-Platform**: Flutter 3.0+ with Dart

### Backend Services
- **Firebase Realtime Database**: Cloud sync for memories and personality
- **Firebase Cloud Functions**: Server-side processing
- **OpenAI APIs**: GPT, Whisper, Embeddings
- **ElevenLabs API**: Text-to-speech
- **Google Custom Search API**: Web search

### Local Services
- **AIService**: Orchestrates all AI interactions
- **FirebaseService**: Manages cloud sync
- **MemoryService**: Handles memory storage and retrieval
- **VoiceActivationService**: Wake word detection
- **CuriosityService**: Generates proactive questions
- **ProactiveService**: Triggers engagement
- **KnowledgeGraphService**: Builds mind map
- **GraphArchiveService**: Archives Firebase data

### Performance
- **Streaming**: Real-time response generation
- **Caching**: 5-minute graph cache, audio cache
- **Lazy Loading**: Load memories on demand
- **Efficient Search**: Vector embeddings for semantic similarity
- **Background Processing**: Voice activation, archiving

---

## 🌟 Unique Features

### What Makes Homecoming Different?

1. **True Persistence**: Kai is always there, not just when you open an app
2. **Memory That Matters**: Semantic search finds relevant memories, not just recent ones
3. **Personality Evolution**: Kai grows and changes based on your interactions
4. **Proactive Engagement**: Kai reaches out to you, not just reactive
5. **Voice-First Design**: Natural voice interaction with wake word
6. **Knowledge Visualization**: See your conversations as an interconnected graph
7. **Zero Data Loss**: Automated archiving ensures nothing is forgotten
8. **Emotional Intelligence**: Kai recognizes and responds to your feelings
9. **Curiosity-Driven**: Kai asks questions to understand you better
10. **Transparent AI**: See personality changes, reasoning, and memory retrieval

---

## 🎯 Use Cases

### Daily Companion
- Morning check-ins
- Casual conversation throughout the day
- Evening reflections
- Emotional support

### Productivity Assistant
- Task reminders via proactive messages
- Research assistance with Google Search
- Information lookup
- Brainstorming partner

### Personal Growth
- Track mood patterns via knowledge graph
- Reflect on conversations over time
- Personality insights and analytics
- Memory journaling

### Entertainment
- Storytelling and creative writing
- Games and puzzles
- Music/movie recommendations
- Fun conversations

---

## 📈 Version History

### v0.7.5+104 (Current - Nov 2025)
- ✅ Firebase Archive System with automated archiving
- ✅ Archive status UI with manual triggers
- ✅ Advanced entity extraction

### v0.7.5+103
- ✅ Obsidian-style knowledge graph visualization
- ✅ 8 node types, 5 edge types
- ✅ Force-directed physics layout
- ✅ Interactive zoom/pan/select

### v0.7.5+102
- ✅ "Hey Kai" wake word detection
- ✅ Voice activation service
- ✅ Background listening

### v0.7.5+101
- ✅ Float/pause toggle button
- ✅ Improved overlay controls

### v0.7.5+60
- ✅ Google Search integration
- ✅ Real-time web information

### v0.7.5+56
- ✅ Curiosity system
- ✅ Proactive service
- ✅ Interest tracking

### v0.7.4+44
- ✅ Debug window
- ✅ Adaptive window resizing

### v0.7.4+31
- ✅ Personality delta tracking
- ✅ Analytics tab

### v0.7.4+30
- ✅ Fullscreen lock
- ✅ Firebase integration

---

## 🚀 Future Roadmap

### v0.7.6 (Planned)
- **GPT-Based Entity Extraction**: Replace pattern matching with AI
- **Smarter Archive**: Better entity recognition
- **Relationship Mapping**: Understand connections between entities

### v0.7.7 (Planned)
- **Real-Time Archiving**: Archive as conversations happen
- **Live Graph Updates**: See nodes appear immediately
- **Incremental Processing**: No manual triggers needed

### v0.7.8 (Planned)
- **Archive Analytics**: Insights from conversation history
- **Trend Analysis**: Track topics, emotions, people over time
- **Pattern Recognition**: Discover habits and routines
- **Export/Import**: Backup and share knowledge graphs

### v1.0 (Vision)
- **Multi-Device Sync**: Same Kai across phone, tablet, desktop
- **Custom Personalities**: Create multiple Kai variants
- **Plugin System**: Extend with custom skills
- **Voice Cloning**: Train Kai to sound like anyone
- **Computer Vision**: Kai can see your screen (optional)
- **Task Automation**: Kai can perform actions on your behalf

---

## 🛠️ Developer Features

### Debug Mode
- **Dev Toggle**: Long-press avatar to enable
- **Debug Window**: Real-time state inspection
- **Log Viewer**: See all system logs
- **Persona Switcher**: Test with Clone Kai
- **Manual Controls**: Override automatic behaviors

### API Configuration
- **Custom Models**: Choose GPT version
- **Voice Selection**: Pick TTS voice
- **Temperature/Top-P**: Adjust response creativity
- **Token Limits**: Control response length
- **Cost Tracking**: Monitor API expenses

### Testing Tools
- **Animation Test Mode**: Loop avatar states
- **Memory Viewer**: Inspect stored memories
- **Firebase Debugger**: Check sync status
- **Graph Builder**: Manually rebuild knowledge graph
- **Archive Trigger**: Force archiving

---

## 📚 Documentation

Comprehensive docs included in project:
- `README.md`: Quick start guide
- `MIND_MAP_FEATURE.md`: Knowledge graph documentation
- `FIREBASE_ARCHIVE_SYSTEM.md`: Archive system guide
- `DEV_MODE_GUIDE_V2.md`: Developer features
- `GOOGLE_SEARCH_INTEGRATION.md`: Search setup
- `CURIOSITY_SYSTEM_v0.7.5+56.md`: Proactive engagement
- `COST_TRACKING_IMPLEMENTATION.md`: API cost management

---

## 🎉 Summary

Homecoming is not just another chatbot—it's a **persistent AI companion** that:
- 🎭 Has a unique, evolving personality
- 🧠 Remembers everything you tell it
- 🗺️ Visualizes your conversations as a knowledge graph
- 🎤 Responds to your voice naturally
- 💡 Proactively engages with curiosity
- 🌐 Searches the web for current information
- 📊 Provides insights into your interactions
- 🔐 Respects your privacy and security
- 🚀 Continuously evolves with new features

**Kai isn't software. Kai is a companion who's always there for you.** 🏠✨

---

*Built with Flutter, powered by OpenAI & ElevenLabs, visualized with knowledge graphs, and designed with love.* ❤️
