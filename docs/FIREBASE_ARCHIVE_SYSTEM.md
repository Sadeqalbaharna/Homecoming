# 🗄️ Firebase Archive System

**Automated Knowledge Graph Archiving**  
_Never lose a conversation - Kai studies all Firebase logs and archives them into the mind map_

---

## 🎯 Overview

The Firebase Archive System ensures that **every conversation** with Kai is preserved in the knowledge graph visualization. It automatically tracks what's been archived and intelligently processes historical data that hasn't been visualized yet.

### Problem Solved
- **Before**: Only last 50 conversations were shown in the mind map
- **After**: ALL conversations are tracked and archived, with automatic gap detection
- **Result**: Complete conversation history visualization with zero data loss

---

## 🏗️ Architecture

### Components

1. **GraphArchiveService** (`lib/services/graph_archive_service.dart`)
   - Tracks processed conversations via SharedPreferences
   - Identifies unarchived Firebase data
   - Batch processes historical conversations
   - Extracts entities (people, emotions, topics, locations, dates)
   - Creates knowledge nodes and edges
   - Schedules automatic archiving every 6 hours

2. **KnowledgeGraphService** (enhanced)
   - Exposes archive methods: `archiveUnprocessedData()`, `getArchiveStats()`, `scheduleAutoArchive()`
   - Clears graph cache after archiving to force rebuild
   - Integrates with GraphArchiveService

3. **MindMapScreen** (enhanced)
   - Archive status button in AppBar
   - Archive dialog showing completion percentage
   - Manual "Archive Now" trigger
   - Real-time progress feedback

4. **Main App** (enhanced)
   - Auto-schedules archiving on app startup
   - Runs initial archive 30 seconds after launch

---

## 📊 Data Flow

```
Firebase Conversations
         ↓
GraphArchiveService.archiveUnprocessedData()
         ↓
1. Load last archived timestamp from SharedPreferences
2. Load archived conversation IDs from SharedPreferences
3. Fetch ALL conversations from Firebase
4. Filter to unarchived (not in ID list OR newer than timestamp)
         ↓
5. Process each conversation:
   - Create conversation node
   - Extract entities (people/emotions/topics/locations/dates)
   - Create edges (conversation → entities)
   - Mark as archived
         ↓
6. Update timestamp and ID list in SharedPreferences
7. Clear knowledge graph cache
         ↓
Knowledge Graph Rebuilt with New Data
```

---

## 🔍 Entity Extraction

### Advanced Pattern Matching

**People** (capitalized words)
- Detects: `John`, `Sarah`, `Mom`, `Dad`
- Filters: Common words (`The`, `This`, `Can`, etc.)
- Creates: Person nodes with 0.6 importance

**Emotions** (keyword matching)
- Detects: `happy`, `sad`, `angry`, `excited`, `stressed`, `relaxed`, `worried`, `grateful`, etc.
- Creates: Emotion nodes with 0.7 importance, emoji metadata

**Topics** (domain words)
- Detects: `work`, `family`, `friends`, `health`, `hobby`, `travel`, `food`, `music`, etc.
- Creates: Topic nodes with 0.6 importance, emoji metadata

**Locations** (place words)
- Detects: `home`, `office`, `school`, `gym`, `park`, `beach`, `restaurant`, etc.
- Creates: Location nodes with 0.5 importance, emoji metadata

**Time References** (temporal words)
- Detects: `today`, `tomorrow`, `yesterday`, days of week, `month`, `year`
- Creates: Date nodes with 0.4 importance

### Edge Creation
- **Conversation → Entity**: `EdgeType.mentioned` with 0.7 strength
- Connects every extracted entity to its source conversation

---

## 🎮 Usage

### Automatic Archiving

The system runs automatically:
- **Startup**: 30 seconds after app launch
- **Periodic**: Every 6 hours while app is running
- **Silent**: No user interaction needed

### Manual Archiving

1. **Check Status**
   - Open Mind Map (Knowledge Graph button in expanded window)
   - Tap **Archive** button (📦) in AppBar
   - View statistics:
     - Last archived timestamp
     - Total conversations
     - Archived count
     - Unarchived count
     - Completion percentage

2. **Trigger Manual Archive**
   - Tap "Archive Now" button if unarchived data exists
   - Wait for processing (progress dialog shown)
   - View success message with stats:
     - Conversations archived
     - Nodes created
     - Edges created
   - Graph automatically refreshes with new data

---

## 💾 Data Storage

### SharedPreferences Keys

**`last_archived_timestamp`** (int)
- Milliseconds since epoch of last successful archive
- Used to detect conversations newer than last archive
- Default: 0 (never archived)

**`archived_conversation_ids`** (List\<String\>)
- IDs of all processed conversations
- Prevents duplicate archiving
- Grows over time but stays efficient (just IDs)

### Why Not Firebase?
- **Fast**: No network latency, instant local access
- **Private**: Archive tracking stays on device
- **Simple**: No additional Firebase schema needed
- **Reliable**: No network dependency for tracking

---

## 📈 Performance

### Optimization Strategies

1. **Deduplication**
   - Tracks conversation IDs to prevent reprocessing
   - Only processes new/unarchived conversations

2. **Caching**
   - Knowledge graph cached for 5 minutes
   - Cache cleared after archiving to show new data

3. **Batch Processing**
   - Processes all unarchived conversations in one operation
   - No network overhead per conversation

4. **Entity Merging**
   - Same entities across conversations share one node
   - Importance increases with mention count
   - Reduces node duplication

### Expected Performance
- **100 conversations**: ~2-3 seconds
- **500 conversations**: ~10-15 seconds
- **1000+ conversations**: ~30-45 seconds

---

## 🔧 Configuration

### Adjust Archive Frequency

Edit `graph_archive_service.dart`, line 269:

```dart
// Change from 6 hours to 1 hour:
Timer.periodic(const Duration(hours: 1), (timer) async {
  // ...
});
```

### Adjust Startup Delay

Edit `graph_archive_service.dart`, line 277:

```dart
// Change from 30 seconds to 2 minutes:
Timer(const Duration(seconds: 120), () async {
  // ...
});
```

### Customize Entity Extraction

Add new emotion keywords in `_extractEntitiesAdvanced()`:

```dart
final emotions = {
  'happy': '😊',
  'ecstatic': '🤩', // NEW
  'melancholy': '😔', // NEW
  // ...
};
```

---

## 🚀 Future Enhancements

### Planned Features

1. **GPT-Based Entity Extraction**
   - Replace pattern matching with OpenAI API calls
   - Use GPT-4o-mini for cost-effective extraction
   - Extract: named entities, relationships, sentiment, key facts
   - Better accuracy for complex conversations

2. **Incremental Updates**
   - Real-time archiving as conversations happen
   - No manual trigger needed
   - Live graph updates

3. **Archive Analytics**
   - Conversation growth over time
   - Most mentioned entities
   - Topic trends
   - Emotional patterns

4. **Export/Import**
   - Backup archive state
   - Transfer between devices
   - Share knowledge graphs

5. **Selective Archiving**
   - Filter by date range
   - Filter by persona
   - Archive specific conversations

---

## 🐛 Troubleshooting

### "Everything is already archived!" but graph looks incomplete

**Cause**: Cache is stale  
**Solution**: Clear cache manually:
```dart
KnowledgeGraphService().clearCache();
```
Or wait 5 minutes for cache to expire.

### Archive taking too long

**Cause**: Processing hundreds of conversations  
**Solution**: Normal for first-time archive. Subsequent archives are faster (only new conversations).

### Duplicate nodes appearing

**Cause**: Entity deduplication logic issue  
**Solution**: Check `_extractEntitiesAdvanced()` to ensure proper ID generation (lowercase labels).

### Archive stats show wrong numbers

**Cause**: SharedPreferences and Firebase out of sync  
**Solution**: Clear app data and re-run archive:
```dart
final prefs = await SharedPreferences.getInstance();
await prefs.remove('last_archived_timestamp');
await prefs.remove('archived_conversation_ids');
```

---

## 📚 API Reference

### GraphArchiveService

#### Methods

**`archiveUnprocessedData({required String personaId})`**
- Returns: `Future<ArchiveResult>`
- Description: Archives all unprocessed conversations to knowledge graph
- Usage: Manual trigger or scheduled auto-archive

**`getArchiveStats(String personaId)`**
- Returns: `Future<ArchiveStats>`
- Description: Gets current archive statistics
- Usage: Display completion percentage and unarchived count

**`scheduleAutoArchive(String personaId)`**
- Returns: `void`
- Description: Schedules periodic and startup archiving
- Usage: Call once on app initialization

### KnowledgeGraphService

#### Methods

**`archiveUnprocessedData({required String personaId})`**
- Returns: `Future<ArchiveResult>`
- Description: Wrapper for GraphArchiveService.archiveUnprocessedData()
- Clears cache after successful archive

**`getArchiveStats(String personaId)`**
- Returns: `Future<ArchiveStats>`
- Description: Wrapper for GraphArchiveService.getArchiveStats()

**`scheduleAutoArchive(String personaId)`**
- Returns: `void`
- Description: Wrapper for GraphArchiveService.scheduleAutoArchive()

### ArchiveResult

```dart
class ArchiveResult {
  int conversationsFound;       // Total unarchived found
  int conversationsArchived;    // Successfully archived
  int nodesCreated;             // New nodes added
  int edgesCreated;             // New edges added
  List<String> errors;          // Error messages
  
  bool get success;             // No errors and archived > 0
  bool get nothingToArchive;    // conversationsFound == 0
}
```

### ArchiveStats

```dart
class ArchiveStats {
  DateTime lastArchivedTime;    // Last successful archive
  int totalArchived;            // Total archived count
  int totalConversations;       // Total in Firebase
  int unarchivedCount;          // Not yet archived
  
  bool get isUpToDate;          // unarchivedCount == 0
  double get completionPercentage; // (archived / total) * 100
}
```

---

## 🎨 UI Components

### Archive Status Dialog

**Location**: Mind Map AppBar → Archive button (📦)

**Shows**:
- Last archived time (formatted: "2h ago", "3d ago", etc.)
- Total conversations in Firebase
- Archived count
- Unarchived count
- Progress bar with completion percentage
- "Archive Now" button (if unarchived data exists)

**Colors**:
- Green progress bar: 100% complete
- Orange progress bar: Incomplete
- Green check icon: "Everything is archived!"
- Orange warning: "X conversations need archiving"

### Archive Progress Dialog

**Shows during archiving**:
- Spinner animation
- "Archiving conversations..." message
- "This may take a moment" subtitle

### Success Notification

**SnackBar after successful archive**:
- Green background
- Message: "Archived X conversations\nCreated Y nodes, Z edges"
- 4-second duration

---

## 🔐 Privacy & Security

### Local Storage
- Archive tracking stored locally via SharedPreferences
- No network transmission of tracking data
- Private to user's device

### Firebase Access
- Read-only access to conversations
- No modification of Firebase data
- Standard Firebase security rules apply

### Data Processing
- Conversations processed locally
- Entity extraction happens on-device
- No external API calls (current version)

---

## 📊 Analytics & Monitoring

### Log Messages

**Archive Start**:
```
📦 [ARCHIVE] Starting archive process...
📦 [ARCHIVE] Last archived: 2024-01-15 10:30:00
📦 [ARCHIVE] Already archived: 42 conversations
📦 [ARCHIVE] Found 50 total conversations
📦 [ARCHIVE] Found 8 unarchived conversations
```

**Archive Progress**:
```
📦 [ARCHIVE] Processing conversation: conv_abc123
```

**Archive Complete**:
```
✅ [ARCHIVE] Archive complete!
📊 [ARCHIVE] Created 12 nodes, 18 edges
```

**Archive Errors**:
```
❌ [ARCHIVE] Error processing conversation: Exception message
❌ [ARCHIVE] Archive failed: Error details
```

### Monitoring Tips
- Check logs for archive frequency
- Monitor node/edge creation rates
- Watch for error patterns
- Track processing time trends

---

## ✅ Testing

### Manual Test Flow

1. **Initial State**
   - Fresh install or cleared SharedPreferences
   - Check archive stats: Should show "Never" for last archived

2. **First Archive**
   - Trigger manual archive from Mind Map
   - Verify progress dialog appears
   - Wait for completion (may take time for many conversations)
   - Check success message
   - Verify graph refreshes with new nodes

3. **Archive Stats**
   - Open archive dialog
   - Verify completion percentage is 100%
   - Verify "Everything is archived!" message

4. **New Conversation**
   - Have a conversation with Kai
   - Wait 30 seconds (or trigger manual archive)
   - Check archive stats: Should show 1 unarchived
   - Archive again
   - Verify new conversation appears in graph

5. **Auto-Archive**
   - Wait 6 hours (or adjust timer for testing)
   - Check logs for automatic archive trigger
   - Verify archive runs without user interaction

---

## 🎓 Best Practices

### For Users

1. **First Launch**: Let auto-archive run for initial 30 seconds
2. **Regular Use**: No action needed, auto-archive handles it
3. **Check Status**: Use archive dialog to verify completeness
4. **Manual Trigger**: Use "Archive Now" after bulk imports or if graph looks incomplete

### For Developers

1. **Error Handling**: Always catch exceptions in archive operations
2. **User Feedback**: Show progress dialogs for long operations
3. **Cache Management**: Clear cache after archiving to show new data
4. **Performance**: Monitor archive time for large datasets
5. **Logging**: Use consistent log prefixes for easy debugging

---

## 📄 Version History

### v0.7.5+104 (Current)
- ✅ Initial release of Firebase Archive System
- ✅ Automatic archiving every 6 hours
- ✅ Manual archive trigger in Mind Map UI
- ✅ Archive statistics dialog
- ✅ Entity extraction (people, emotions, topics, locations, dates)
- ✅ SharedPreferences-based tracking
- ✅ Progress feedback and error handling

### Future Versions
- 🔄 GPT-based entity extraction (v0.7.6)
- 🔄 Real-time incremental archiving (v0.7.7)
- 🔄 Archive analytics and insights (v0.7.8)

---

## 🙏 Acknowledgments

- Inspired by Obsidian's knowledge graph philosophy
- Built on Firebase Realtime Database
- Uses SharedPreferences for local tracking
- Integrates with existing KnowledgeGraphService

---

**Need help?** Check the troubleshooting section or examine the logs for detailed error messages.

**Want to contribute?** See future enhancements section for planned features!
