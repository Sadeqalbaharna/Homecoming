# 🔍 Accessing Kai's Brain - Complete Guide

**Version**: v0.7.4+33  
**Date**: October 21, 2025

This guide shows you how to access, monitor, and verify Kai's memory system.

---

## 🎯 Quick Access Methods

### 1. Firebase Console (Easiest)
View all memory data in real-time through the web interface.

### 2. Firebase CLI Commands
Query and monitor from your terminal.

### 3. Callable Functions
Query memories programmatically from the app.

### 4. Direct Database Access
Read/write directly to Firebase Realtime Database.

---

## 📊 Method 1: Firebase Console (Web Interface)

### Access URLs

**Main Database Console**:
```
https://console.firebase.google.com/project/homecoming-74f73/database
```

**Memory Paths**:

1. **Conversation Buffer** (Rolling window of recent turns):
   ```
   https://console.firebase.google.com/project/homecoming-74f73/database/data/~2Fmemory~2Fbuffers~2Ftruekai
   ```
   Shows: Current conversation buffer, turn count, timestamps

2. **Memory Shards** (Summarized conversation segments):
   ```
   https://console.firebase.google.com/project/homecoming-74f73/database/data/~2Fmemory~2Fshards~2Ftruekai
   ```
   Shows: GPT-generated summaries, turn count, time ranges

3. **Embeddings** (1536-dimensional vectors for semantic search):
   ```
   https://console.firebase.google.com/project/homecoming-74f73/database/data/~2Fmemory~2Fembeddings~2Ftruekai
   ```
   Shows: Vector arrays, associated summaries

4. **Extracted Facts** (Learned knowledge):
   ```
   https://console.firebase.google.com/project/homecoming-74f73/database/data/~2Fmemory~2Ffacts~2Ftruekai
   ```
   Shows: Preferences, personal info, goals

5. **Daily Summaries** (CRON-generated daily reports):
   ```
   https://console.firebase.google.com/project/homecoming-74f73/database/data/~2Fmemory~2Fdaily~2Ftruekai
   ```
   Shows: Daily conversation summaries, stats, personality changes

6. **Cloud Functions** (Monitor function execution):
   ```
   https://console.firebase.google.com/project/homecoming-74f73/functions
   ```
   Shows: Function status, invocation count, errors

7. **Function Logs** (Real-time logging):
   ```
   https://console.firebase.google.com/project/homecoming-74f73/logs
   ```
   Shows: All function execution logs, errors, debug info

---

## 💻 Method 2: Firebase CLI Commands

### Setup
```powershell
# Set active project
firebase use homecoming-74f73
```

### View Function Logs
```powershell
# Real-time logs (all functions)
firebase functions:log --tail

# Recent logs (last 50 lines)
firebase functions:log --limit 50

# Specific function logs
firebase functions:log --only onTurnWrite
firebase functions:log --only onShardWrite
firebase functions:log --only extractFacts
firebase functions:log --only dailyCompactor

# Filter by time
firebase functions:log --since 1h    # Last hour
firebase functions:log --since 30m   # Last 30 minutes
```

### Check Function Status
```powershell
# List all deployed functions
firebase functions:list

# Expected output:
# onTurnWrite (us-central1)
# onShardWrite (us-central1)
# extractFacts (us-central1)
# dailyCompactor (us-central1)
# queryMemory (us-central1)
# extractFactsManual (us-central1)
```

### Read Database Directly
```powershell
# View buffer
firebase database:get /memory/buffers/truekai

# View all shards
firebase database:get /memory/shards/truekai

# View all facts
firebase database:get /memory/facts/truekai

# View specific date's summary
firebase database:get /memory/daily/truekai/2025-10-21

# View all conversations
firebase database:get /conversations/truekai
```

---

## 🧪 Method 3: Test Memory System

### Step 1: Send Test Conversations

Run this PowerShell script to send 10 test conversations:

```powershell
# test-memory.ps1
$baseUrl = "https://homecoming-74f73-default-rtdb.europe-west1.firebasedatabase.app"

for ($i = 1; $i -le 10; $i++) {
    $data = @{
        userMessage = "Test message $i - I love coffee in the morning"
        aiResponse = "That's great! Coffee is wonderful. Let me remember that."
        timestamp = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
        personalityDeltas = @{
            warmth = 2
            energy = 1
        }
    } | ConvertTo-Json

    $response = Invoke-RestMethod -Uri "$baseUrl/conversations/truekai/conv_test_$i.json" -Method Put -Body $data -ContentType "application/json"
    Write-Host "✅ Sent message $i"
    Start-Sleep -Milliseconds 500
}

Write-Host "`n🎉 Sent 10 test messages! Check Firebase Console in 1 minute for memory shard."
```

### Step 2: Monitor Memory Formation

```powershell
# Watch for shard creation (wait ~1 minute after 10th message)
firebase database:get /memory/shards/truekai

# Check if facts were extracted
firebase database:get /memory/facts/truekai

# View embedding vectors
firebase database:get /memory/embeddings/truekai
```

### Step 3: Query Memories

Create a test query script:

```powershell
# query-memory.ps1
$url = "https://us-central1-homecoming-74f73.cloudfunctions.net/queryMemory"

$data = @{
    data = @{
        personaId = "truekai"
        query = "coffee morning drinks"
        limit = 3
    }
} | ConvertTo-Json -Depth 10

$response = Invoke-RestMethod -Uri $url -Method Post -Body $data -ContentType "application/json"
$response.result.results | ForEach-Object {
    Write-Host "`n📝 Memory:"
    Write-Host "Summary: $($_.summary)"
    Write-Host "Similarity: $($_.similarity)"
    Write-Host "Shard: $($_.shardId)"
}
```

---

## 🔧 Method 4: Deploy and Test Functions

### Deploy Cloud Functions

```powershell
# Quick deploy with script
.\deploy-kai-brain.ps1

# Or manual deploy
cd functions
npm install
cd ..
firebase deploy --only functions
```

### Verify Deployment

```powershell
# Check functions are live
firebase functions:list

# Test queryMemory function
firebase functions:shell
> queryMemory({personaId: 'truekai', query: 'coffee', limit: 3})

# Test extractFactsManual
> extractFactsManual({personaId: 'truekai', shardId: 'shard_xxx'})
```

---

## 📱 Method 5: In-App Monitoring

### Add Memory Dashboard to App

Create `lib/memory_dashboard_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:cloud_functions/cloud_functions.dart';

class MemoryDashboardScreen extends StatefulWidget {
  @override
  State<MemoryDashboardScreen> createState() => _MemoryDashboardScreenState();
}

class _MemoryDashboardScreenState extends State<MemoryDashboardScreen> {
  final _database = FirebaseDatabase.instance;
  final _functions = FirebaseFunctions.instance;
  
  Map<String, dynamic>? _bufferData;
  List<dynamic> _shards = [];
  List<dynamic> _facts = [];
  Map<String, dynamic>? _todaysSummary;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadMemoryData();
  }

  Future<void> _loadMemoryData() async {
    setState(() => _loading = true);
    
    try {
      // Load buffer
      final bufferSnap = await _database.ref('memory/buffers/truekai').get();
      _bufferData = bufferSnap.value as Map<String, dynamic>?;
      
      // Load shards
      final shardsSnap = await _database.ref('memory/shards/truekai').get();
      if (shardsSnap.value != null) {
        final shardsMap = shardsSnap.value as Map;
        _shards = shardsMap.values.toList();
      }
      
      // Load facts
      final factsSnap = await _database.ref('memory/facts/truekai').get();
      if (factsSnap.value != null) {
        final factsMap = factsSnap.value as Map;
        _facts = factsMap.values.toList();
      }
      
      // Load today's summary
      final today = DateTime.now();
      final dateKey = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      final summarySnap = await _database.ref('memory/daily/truekai/$dateKey').get();
      _todaysSummary = summarySnap.value as Map<String, dynamic>?;
      
    } catch (e) {
      print('Error loading memory: $e');
    }
    
    setState(() => _loading = false);
  }

  Future<void> _queryMemory(String query) async {
    try {
      final result = await _functions.httpsCallable('queryMemory').call({
        'personaId': 'truekai',
        'query': query,
        'limit': 5,
      });
      
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Memory Query Results'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final memory in result.data['results'])
                  Padding(
                    padding: EdgeInsets.only(bottom: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Similarity: ${memory['similarity'].toStringAsFixed(3)}',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                        SizedBox(height: 4),
                        Text(memory['summary']),
                        Divider(),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Query failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text('Kai\'s Brain')),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Kai\'s Brain Dashboard'),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _loadMemoryData,
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.all(16),
        children: [
          // Buffer Status
          Card(
            child: ListTile(
              leading: Icon(Icons.memory, color: Colors.blue),
              title: Text('Conversation Buffer'),
              subtitle: Text(_bufferData != null 
                ? '${_bufferData!['turnCount'] ?? 0} turns in buffer'
                : 'No active buffer'),
              trailing: _bufferData != null
                ? Text('${_bufferData!['turnCount'] ?? 0}/10', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))
                : null,
            ),
          ),
          
          SizedBox(height: 8),
          
          // Memory Shards
          Card(
            child: ListTile(
              leading: Icon(Icons.auto_awesome, color: Colors.purple),
              title: Text('Memory Shards'),
              subtitle: Text('${_shards.length} conversation segments stored'),
              onTap: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text('Memory Shards'),
                    content: SingleChildScrollView(
                      child: Column(
                        children: _shards.map((shard) => ListTile(
                          title: Text('${shard['turnCount']} turns'),
                          subtitle: Text(shard['summary'] ?? 'No summary'),
                        )).toList(),
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text('Close'),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          
          SizedBox(height: 8),
          
          // Extracted Facts
          Card(
            child: ListTile(
              leading: Icon(Icons.lightbulb, color: Colors.orange),
              title: Text('Learned Facts'),
              subtitle: Text('${_facts.length} facts extracted'),
              onTap: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text('Learned Facts'),
                    content: SingleChildScrollView(
                      child: Column(
                        children: _facts.map((fact) => ListTile(
                          leading: Icon(
                            fact['type'] == 'preference' ? Icons.favorite :
                            fact['type'] == 'personal' ? Icons.person :
                            Icons.flag,
                          ),
                          title: Text(fact['fact'] ?? 'Unknown'),
                          subtitle: Text(fact['type'] ?? 'unknown'),
                        )).toList(),
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text('Close'),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          
          SizedBox(height: 8),
          
          // Today's Summary
          Card(
            child: ListTile(
              leading: Icon(Icons.today, color: Colors.green),
              title: Text('Today\'s Summary'),
              subtitle: Text(_todaysSummary != null 
                ? '${_todaysSummary!['conversationCount'] ?? 0} conversations'
                : 'No summary yet'),
              onTap: _todaysSummary != null ? () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text('Today\'s Summary'),
                    content: SingleChildScrollView(
                      child: Text(_todaysSummary!['summary'] ?? 'No summary'),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text('Close'),
                      ),
                    ],
                  ),
                );
              } : null,
            ),
          ),
          
          SizedBox(height: 16),
          
          // Query Memory
          ElevatedButton.icon(
            icon: Icon(Icons.search),
            label: Text('Query Memory'),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) {
                  final controller = TextEditingController();
                  return AlertDialog(
                    title: Text('Search Memories'),
                    content: TextField(
                      controller: controller,
                      decoration: InputDecoration(
                        hintText: 'Enter search query...',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text('Cancel'),
                      ),
                      ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context);
                          _queryMemory(controller.text);
                        },
                        child: Text('Search'),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}
```

### Add to Your App

In `lib/main_mobile.dart` or `lib/main_overlay.dart`, add a button:

```dart
IconButton(
  icon: Icon(Icons.psychology),
  tooltip: 'Kai\'s Brain',
  onPressed: () {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => MemoryDashboardScreen()),
    );
  },
)
```

---

## 📋 What to Check

### After First 10 Conversations

1. **Buffer** → Should show 10 turns (or reset to 0 if shard created)
2. **Shards** → New shard with GPT summary
3. **Embeddings** → 1536-dimensional vector for the shard
4. **Facts** → Extracted preferences/personal info

### After 24 Hours

1. **Daily Summary** → Check `/memory/daily/truekai/YYYY-MM-DD`
2. **CRON Logs** → `firebase functions:log --only dailyCompactor`

### Ongoing Monitoring

1. **Function Invocations** → Firebase Console > Functions
2. **Error Logs** → Firebase Console > Logs
3. **Database Size** → Firebase Console > Database > Usage

---

## 🐛 Troubleshooting

### No Memory Data?

```powershell
# 1. Check if functions are deployed
firebase functions:list

# 2. Check function logs for errors
firebase functions:log --limit 50

# 3. Verify conversations are being saved
firebase database:get /conversations/truekai

# 4. Check OpenAI API key is set
firebase functions:config:get
```

### Functions Not Triggering?

```powershell
# Re-deploy functions
firebase deploy --only functions

# Check database rules
firebase deploy --only database

# Verify triggers in console
# https://console.firebase.google.com/project/homecoming-74f73/functions
```

### Semantic Search Not Working?

```powershell
# Test queryMemory directly
firebase functions:shell
> queryMemory({personaId: 'truekai', query: 'test', limit: 3})

# Check embeddings exist
firebase database:get /memory/embeddings/truekai

# Verify OpenAI API key
firebase functions:config:get openai.key
```

---

## 💡 Pro Tips

### 1. Monitor Costs

```powershell
# Check OpenAI API usage
# Visit: https://platform.openai.com/usage

# Check Firebase costs
# Visit: https://console.firebase.google.com/project/homecoming-74f73/usage
```

### 2. Export Memory Data

```powershell
# Backup all memory
firebase database:get /memory > kai-brain-backup.json

# Export specific persona
firebase database:get /memory/shards/truekai > kai-shards-backup.json
```

### 3. Clear Test Data

```powershell
# Delete test conversations
firebase database:remove /conversations/truekai

# Clear buffer
firebase database:remove /memory/buffers/truekai

# Keep shards/facts for testing
```

---

## 🎯 Next Steps

1. **Deploy Functions**: Run `.\deploy-kai-brain.ps1`
2. **Send Test Data**: Use test script above
3. **Monitor Formation**: Watch Firebase Console
4. **Query Memories**: Test semantic search
5. **Add Dashboard**: Integrate memory viewer in app

---

**Happy brain monitoring! 🧠✨**
