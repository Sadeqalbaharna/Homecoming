# 🔍 Google Search Integration - Complete Guide

**Version**: v0.7.5+60  
**Status**: ✅ Fully Integrated  
**Migration**: Ported from Python backend to Flutter

---

## 📋 Overview

Kai now has **Google Custom Search** capabilities fully integrated into Flutter! This feature was previously in the Python backend (`server.py`) and has been completely migrated to pure Dart/Flutter with enhanced capabilities.

### **What's New:**
- ✅ Pure Flutter Google Search service
- ✅ Auto-trigger logic (smart detection)
- ✅ Two modes: Headlines & Context
- ✅ Cost tracking integration
- ✅ Debug information
- ✅ Graceful degradation
- ✅ Search result caching in ChatResponse

---

## 🎯 Key Features

### **1. Smart Auto-Trigger**
Kai automatically decides when to search based on query analysis:

**Triggers Search For:**
- 📰 News queries: "latest news", "breaking", "headlines"
- 📊 Time-sensitive: "today", "now", "recent", "this week"
- 🏆 Sports: "who won", "final score", "live score"
- 💰 Finance: "stock price", "crypto", "bitcoin", "exchange rate"
- 📅 Events: "release date", "when is", "schedule"
- 🗓️ Historical: Any year mention (1900-2059)
- 🔗 URLs: "search for...", explicit URLs
- ❓ Long questions: Questions with 10+ words

**Skips Search For:**
- ⏰ Time queries (handled natively by Kai)
- 🌤️ Weather queries (handled natively by Kai)
- 💬 General conversation

### **2. Two Search Modes**

#### **Headlines Mode** (Direct Results)
Triggered by: "news", "headlines", "breaking", "top stories", "latest"

**Behavior:**
- Searches within trusted news sites (Reuters, BBC, CNN, AP, etc.)
- Returns formatted headline list directly
- **Skips AI processing** for speed
- Limited to past 24 hours (`dateRestrict: d1`)

**Example:**
```
User: "What's the latest news?"

Kai: "Here are some current headlines:
1. Breaking: Major Event Happens — Reuters
2. Update on Global Situation — BBC
3. New Development Announced — AP News
4. Economic Report Released — Bloomberg
5. Technology Breakthrough — TechCrunch"
```

#### **Context Mode** (AI Integration)
Triggered by: Other search-worthy queries

**Behavior:**
- Performs Google Search
- Injects results as **WEB CONTEXT** into AI prompt
- Kai synthesizes information naturally
- Cites sources as [1], [2], [3]
- AI can choose to use or ignore context

**Example:**
```
User: "What happened in the Mars mission recently?"

Kai: "Recent updates show [1] the rover discovered new mineral deposits, 
and [2] NASA announced plans for sample return in 2028. This builds on 
earlier findings [3] from last year's analysis."
```

---

## 🛠️ Technical Implementation

### **Service Architecture**

```dart
// lib/services/google_search_service.dart

class GoogleSearchService {
  // Perform search
  Future<SearchResponse> search({
    required String apiKey,
    required String cseId,
    required String query,
    int num = 5,
    String dateRestrict = 'd1',
    String lang = 'en',
    String gl = 'us',
    bool newsBias = false,
  })
  
  // Decision logic
  static bool shouldSearch(String userText)
  
  // Format results
  static String buildWebContext(List<SearchResult> results)
  static String formatAsHeadlines(List<SearchResult> results)
}
```

### **Data Models**

```dart
class SearchResult {
  final String title;
  final String link;
  final String displayLink;
  final String snippet;
  final String publishedAt;
}

class SearchResponse {
  final List<SearchResult> results;
  final SearchDiagnostics diagnostics;
  
  bool get hasResults
  bool get isSuccess
  String? get error
}

class SearchDiagnostics {
  final bool ok;
  final int? statusCode;
  final String? error;
  final String? url;
}
```

### **AI Service Integration**

```dart
// lib/services/ai_service.dart

Future<ChatResponse> sendMessage({
  required String text,
  required String personaId,
  bool useWebSearch = true, // NEW parameter
  // ... other parameters
})

// Auto-triggers search
if (useWebSearch && GoogleSearchService.shouldSearch(text)) {
  // Headline mode or Context mode
  // Tracks usage
  // Handles errors gracefully
}

class ChatResponse {
  final bool webSearchUsed; // NEW
  final List<SearchResult> searchResults; // NEW
  // ... other fields
}
```

---

## 🔑 Setup Instructions

### **1. Get Google Custom Search Credentials**

#### **A. Create Custom Search Engine**
1. Go to: https://programmablesearchengine.google.com/
2. Click **"Add"**
3. Configure:
   - **Sites to search**: "Search the entire web"
   - **Name**: "Kai Search Engine"
   - **Language**: English
4. Click **"Create"**
5. Copy your **Search Engine ID (cx)** - looks like: `012345678901234567890:abcdefghij`

#### **B. Get API Key**
1. Go to: https://console.cloud.google.com/apis/credentials
2. Create Project (if needed): "Homecoming AI"
3. Enable APIs:
   - Click **"Enable APIs and Services"**
   - Search for **"Custom Search API"**
   - Click **"Enable"**
4. Create Credentials:
   - Click **"Create Credentials"** → **"API Key"**
   - Copy your key: `AIzaSy...`
   - (Optional) Restrict key to Custom Search API only

#### **C. Enable Billing** (Required!)
Google Custom Search requires billing enabled:
- **Free tier**: 100 queries/day
- **Paid**: $5.00 per 1,000 queries after free tier
- Link: https://console.cloud.google.com/billing

### **2. Configure in App**

#### **Option A: Setup Screen** (Easiest)
1. Open Homecoming app
2. Go to **Settings** (or initial setup if first launch)
3. Enter:
   - **Google API Key**: Your API key from step B
   - **Google CSE ID**: Your Search Engine ID from step A
4. Click **"Save"**

#### **Option B: Secure Storage Service**
```dart
final storage = SecureStorageService();
await storage.setGoogleKey('YOUR_API_KEY');
await storage.setGoogleCseId('YOUR_CSE_ID');
```

#### **Option C: Manual (encrypted storage)**
Keys are stored encrypted via `flutter_secure_storage`:
- Android: KeyStore
- iOS: Keychain
- Location: Device-specific secure storage

---

## 📊 Usage Tracking

### **Cost Tracking**
```dart
// Automatically tracked per query
await UsageTrackingService.trackGoogleSearch(queries: 1);

// $5.00 per 1,000 queries
// Free tier: 100/day
```

### **View Costs**
1. Open Analytics tab in expanded window
2. See **"Google Search API"** card
3. View:
   - Total queries
   - Total cost
   - Session usage

---

## 🧪 Testing the Integration

### **Test 1: Headlines Mode**
```
User: "What's the latest tech news?"
Expected: List of 5 recent tech headlines with sources
```

### **Test 2: Context Mode**
```
User: "Tell me about the recent AI developments"
Expected: Synthesized response with [1], [2], [3] citations
```

### **Test 3: Auto-Trigger Detection**
```
User: "What happened in 2023 with AI?"
Expected: Search triggered (year mention)
```

### **Test 4: Skip Search**
```
User: "How are you feeling today?"
Expected: No search (conversational)
```

### **Test 5: Time/Weather (Native)**
```
User: "What's the weather in Dubai?"
Expected: No search (would be handled natively in future)
```

---

## 🐛 Debugging

### **Enable Debug Logs**
Search logs automatically print to console:
```
🔍 [GOOGLE SEARCH] Starting search...
🔍 [GOOGLE SEARCH] Query: "latest news"
🔍 [GOOGLE SEARCH] Num results: 5
🔍 [GOOGLE SEARCH] Date restrict: d1
🔍 [GOOGLE SEARCH] News bias: true
🔍 [GOOGLE SEARCH] Making API request...
🔍 [GOOGLE SEARCH] Status: 200
✅ [GOOGLE SEARCH] Found 5 results
```

### **Check Debug Info**
```dart
final response = await aiService.sendMessage(
  text: "latest news",
  personaId: "truekai",
  useWebSearch: true,
);

print('Search used: ${response.webSearchUsed}');
print('Results: ${response.searchResults.length}');
print('Debug: ${response.debugInfo?['web_search']}');
```

### **Common Issues**

#### **1. "No results found"**
- Check CSE is configured to search **entire web**
- Verify CSE isn't restricted to specific sites
- Check billing is enabled

#### **2. "API Key error"**
- Verify key is correct (starts with `AIzaSy`)
- Check Custom Search API is enabled
- Ensure no referrer restrictions on key

#### **3. "Quota exceeded"**
- Free tier: 100 queries/day
- Check quota: https://console.cloud.google.com/apis/dashboard
- Enable billing for unlimited (paid)

#### **4. "Search not triggering"**
- Check `shouldSearch()` logic matches query
- Verify `useWebSearch: true` in `sendMessage()`
- Test with explicit triggers: "news", "latest", "search for"

---

## 📈 Performance

### **Response Times**
- Headlines mode: ~1-3 seconds
- Context mode: ~3-5 seconds (includes AI processing)
- Cached results: Instant (future enhancement)

### **Rate Limits**
- **Free tier**: 100 queries/day
- **Paid tier**: 10,000 queries/day default
- Request quota increase if needed

---

## 🔒 Security

### **API Key Protection**
- ✅ Stored encrypted via `flutter_secure_storage`
- ✅ Never logged or exposed in UI
- ✅ Not included in Git repository
- ✅ Separate from OpenAI keys

### **Best Practices**
- Use API key restrictions in Google Console
- Enable billing alerts
- Monitor quota usage
- Rotate keys periodically

---

## 🚀 Advanced Features

### **Date Restriction Options**
```dart
// Last 24 hours (default for news)
dateRestrict: 'd1'

// Last week
dateRestrict: 'w1'

// Last month
dateRestrict: 'm1'

// Last year
dateRestrict: 'y1'

// Last 7 days
dateRestrict: 'd7'
```

### **Custom Search Parameters**
```dart
final response = await searchService.search(
  apiKey: apiKey,
  cseId: cseId,
  query: "AI developments",
  num: 10, // Up to 10 results
  dateRestrict: 'w1', // Past week
  lang: 'en', // Language
  gl: 'us', // Geographic location
  newsBias: true, // News sites only
);
```

### **Manual Search Invocation**
```dart
// Force search regardless of auto-trigger
final searchService = GoogleSearchService();
final response = await searchService.search(
  apiKey: await AIConfig.getGoogleKey(),
  cseId: await AIConfig.getGoogleCseId(),
  query: "your query",
);

if (response.hasResults) {
  for (var result in response.results) {
    print('${result.title} - ${result.link}');
  }
}
```

---

## 📚 References

### **API Documentation**
- Google Custom Search JSON API: https://developers.google.com/custom-search/v1/overview
- Pricing: https://developers.google.com/custom-search/v1/overview#pricing
- CSE Setup: https://programmablesearchengine.google.com/

### **Related Files**
- `lib/services/google_search_service.dart` - Search service
- `lib/services/ai_service.dart` - AI integration
- `lib/services/usage_tracking_service.dart` - Cost tracking
- `lib/services/secure_storage_service.dart` - Key storage

---

## 🎉 Migration Complete!

**From**: Python backend (`server.py`)  
**To**: Pure Flutter/Dart  
**Status**: ✅ Fully functional with enhanced features

### **Improvements Over Python Version:**
1. ✅ No backend required
2. ✅ Better error handling
3. ✅ Integrated cost tracking
4. ✅ Debug information
5. ✅ Type-safe with Dart
6. ✅ Cached results in response
7. ✅ Mobile-friendly

---

**Ready to search the web!** 🔍🌐
