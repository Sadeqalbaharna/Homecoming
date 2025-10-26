# Google Search Integration Setup

Kai now has Google Search capabilities for real-time information! This guide shows you how to set up the required API credentials.

## 🔑 Required Credentials

You need two things:
1. **Google API Key** - For accessing Google Custom Search API
2. **Custom Search Engine ID (CSE ID)** - Your search engine configuration

---

## 📋 Step 1: Get Google API Key

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create a new project or select existing project
3. Enable the **Custom Search JSON API**:
   - Go to "APIs & Services" → "Library"
   - Search for "Custom Search API"
   - Click "Enable"
4. Create credentials:
   - Go to "APIs & Services" → "Credentials"
   - Click "+ CREATE CREDENTIALS" → "API Key"
   - Copy your API key (looks like: `AIzaSyD...`)
5. (Optional) Restrict the API key:
   - Click on the key to edit
   - Under "API restrictions", select "Restrict key"
   - Choose "Custom Search API"
   - Save

---

## 🔍 Step 2: Create Custom Search Engine

1. Go to [Programmable Search Engine](https://programmablesearchengine.google.com/)
2. Click "Get Started" or "Add"
3. Configure your search engine:
   - **Name**: "Kai Search Engine" (or any name)
   - **What to search**: "Search the entire web"
   - Check "Search the entire web"
4. Click "Create"
5. Go to "Setup" → "Basic"
6. Copy your **Search Engine ID** (looks like: `55de057cd04434b4d`)
7. Make sure "Search the entire web" is ON

---

## 🔐 Step 3: Add to GitHub Secrets

### Option A: Using GitHub Web Interface

1. Go to your repository on GitHub
2. Click "Settings" → "Secrets and variables" → "Actions"
3. Click "New repository secret"
4. Add two secrets:

   **Secret 1:**
   - Name: `GOOGLE_API_KEY`
   - Value: Your Google API Key (from Step 1)
   
   **Secret 2:**
   - Name: `GOOGLE_CSE_ID`
   - Value: Your Search Engine ID (from Step 2)

### Option B: Using GitHub CLI

```bash
# Install GitHub CLI if needed
# https://cli.github.com/

# Set the secrets
gh secret set GOOGLE_API_KEY
# Paste your API key when prompted

gh secret set GOOGLE_CSE_ID
# Paste your CSE ID when prompted
```

---

## ✅ Step 4: Verify Setup

1. Push any commit to trigger a new build
2. Check the GitHub Actions logs
3. Look for:
   ```
   ✅ GOOGLE_API_KEY is set (length: 39 chars)
   ✅ GOOGLE_CSE_ID is set (length: 17 chars)
   ```

---

## 🧪 Step 5: Test on Device

After the build completes and you install the APK:

1. Open Kai and say:
   - "What's the latest news?"
   - "Bitcoin price"
   - "Who won the game today?"
   - "Weather in Tokyo"

2. Check the device logs:
   ```bash
   adb logcat | grep -i "GOOGLE SEARCH"
   ```

3. You should see:
   ```
   ✅ Google API Key loaded from dart-define
   ✅ Google CSE ID loaded from dart-define
   🔍 [GOOGLE SEARCH] Starting search...
   ✅ [GOOGLE SEARCH] Found X results
   ```

---

## 💰 API Costs

### Google Custom Search API Pricing

- **Free tier**: 100 queries per day
- **Paid tier**: $5 per 1,000 queries (after free tier)

### Cost Optimization

Kai automatically optimizes usage:
- Only triggers for news/time-sensitive queries
- Uses 5 results max (vs 10)
- Caches headlines for 1 hour
- 40% chance to skip if not needed

**Estimated usage**: ~10-30 queries per day = FREE ✅

---

## 🔧 Troubleshooting

### "Google API credentials not configured"

**Device logs show:**
```
⚠️ [AI_SERVICE] Google API credentials not configured
```

**Solution:**
1. Verify secrets are set in GitHub (see Step 3)
2. Trigger a new build
3. Wait for Firebase distribution
4. Install new APK

### "API Key not valid"

**Error in logs:**
```
❌ [GOOGLE SEARCH] Error: API key not valid
```

**Solution:**
1. Check API key is correct in GitHub secrets
2. Verify Custom Search API is enabled in Google Cloud
3. Check API key restrictions (should allow Custom Search API)

### "Invalid CSE ID"

**Error in logs:**
```
❌ [GOOGLE SEARCH] Error: Invalid Value
```

**Solution:**
1. Verify CSE ID is correct (17 characters)
2. Make sure "Search the entire web" is enabled
3. Wait a few minutes after creating CSE (can take time to activate)

### No search results

**Kai says:** "I couldn't find recent information"

**Possible causes:**
1. Query doesn't match news/time-sensitive patterns
2. Google returned 0 results
3. Network error

**Check logs:**
```bash
adb logcat | grep "GOOGLE SEARCH"
```

---

## 📊 Usage Tracking

Kai tracks Google Search usage in the Analytics tab:

- Total searches performed
- Cost estimate
- Most common query types
- Cache hit rate

Access: Settings → Analytics → Scroll to "Google Search Stats"

---

## 🎯 How It Works

### Auto-Trigger Logic

Kai automatically uses Google Search when you ask about:

1. **News queries**: "latest news", "breaking news", "what happened"
2. **Sports**: "who won", "game score", "match result"
3. **Stocks/Crypto**: "bitcoin price", "stock market", "ethereum"
4. **Time-sensitive**: "today", "now", "current", "latest"

### Search Modes

- **Headlines mode**: Fast, 5 results, news sites only
- **Web context mode**: Deep, 10 results, full web search

### Response Flow

```
User: "What's the latest news about AI?"
  ↓
Kai: (detects news query + time-sensitive)
  ↓
Google Search: "latest news about AI" (d1 = last 24h)
  ↓
Results: 5 headlines from major news sites
  ↓
Kai: "According to recent news, [summarizes findings]..."
```

---

## 🚀 What's Next

Once Google Search is working:

1. **Memory Integration**: Kai remembers your interests and searches accordingly
2. **Smart Caching**: Learns which topics you ask about frequently
3. **Cost Optimization**: Adjusts search frequency based on usage patterns
4. **Custom Sources**: Add your preferred news sites to the CSE

---

## 📝 Notes

- Secrets are **encrypted** in GitHub and never logged
- API keys are **never** stored in code or commits
- Keys are injected at build time via `--dart-define`
- If you change secrets, trigger a new build to apply

---

**Version**: v0.7.5+60+
**Last Updated**: October 26, 2025
**Status**: ✅ Ready for deployment
