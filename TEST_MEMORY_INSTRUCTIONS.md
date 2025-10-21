# Quick Memory Test - Instructions

## 🚨 Current Issue
The OpenAI API key in the functions is invalid (ends with CZYA).
Functions are deployed but failing with 401 errors.

## ✅ Solution (2 minutes)

### Step 1: Create .env file
Create a file called `.env` in the `functions/` folder:

```bash
OPENAI_API_KEY=YOUR_ACTUAL_KEY_HERE
```

Get your key from:
- https://platform.openai.com/account/api-keys
- OR use the same key from your GitHub Secret (OPEN_API_KEY)

### Step 2: Deploy
```powershell
firebase deploy --only functions --project homecoming-74f73
```

### Step 3: Test
```powershell
# Clear old data
firebase database:remove /conversations/truekai --project homecoming-74f73 --force
firebase database:remove /memory/buffers/truekai --project homecoming-74f73 --force

# Send test messages
.\test-memory-simple.ps1

# Wait 30 seconds
Start-Sleep -Seconds 30

# Check results
firebase database:get /memory/shards/truekai --project homecoming-74f73
```

## 📋 Expected Results

After deployment with valid key:

```powershell
# Buffer should show 10 turns
firebase database:get /memory/buffers/truekai

# Shards should exist with GPT summary
firebase database:get /memory/shards/truekai

# Embeddings should be generated
firebase database:get /memory/embeddings/truekai

# Facts should be extracted
firebase database:get /memory/facts/truekai
```

## 🔍 Verify Success

Check logs should show SUCCESS (not 401 errors):
```powershell
gcloud functions logs read onTurnWrite --limit=5 --project=homecoming-74f73
```

Look for:
- ✅ "Shard created successfully"
- ✅ "Embedding generated"
- ✅ "Facts extracted"

NOT:
- ❌ "401 Incorrect API key"

## 💡 Quick Command Sequence

```powershell
# 1. Create functions/.env with your key
"OPENAI_API_KEY=sk-proj-YOUR_KEY" | Out-File -FilePath functions\.env -Encoding utf8

# 2. Deploy
firebase deploy --only functions

# 3. Test
firebase database:remove /conversations/truekai --force; .\test-memory-simple.ps1

# 4. Wait and check
Start-Sleep 30; firebase database:get /memory/shards/truekai
```

## 🎯 The Key Thing

The key ending in "CZYA" is INVALID. You need to replace it with a working key:
- Either from https://platform.openai.com/account/api-keys
- Or copy from your GitHub Secrets (the one that works in your app)
