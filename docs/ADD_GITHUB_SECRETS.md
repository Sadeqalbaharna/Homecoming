# 🔐 Add GitHub Secrets for Google Search

## Quick Setup (2 minutes)

### 1. Get Your Credentials

**You need to obtain these from Google Cloud Console:**

1. **Google API Key**:
   - Go to: https://console.cloud.google.com/apis/credentials
   - Create API Key
   - Restrict to "Custom Search API"

2. **Google Custom Search Engine ID**:
   - Go to: https://programmablesearchengine.google.com/
   - Create new search engine
   - Copy the Search Engine ID

See `GOOGLE_SEARCH_SETUP.md` for detailed instructions.

---

### 2. Add to GitHub Secrets

**Go to**: https://github.com/Sadeqalbaharna/Homecoming/settings/secrets/actions

**Add these 2 secrets:**

1. Click "New repository secret"
2. Name: `GOOGLE_API_KEY`
3. Value: `YOUR_ACTUAL_API_KEY_HERE`
4. Click "Add secret"

5. Click "New repository secret" again
6. Name: `GOOGLE_CSE_ID`
7. Value: `YOUR_SEARCH_ENGINE_ID_HERE`
8. Click "Add secret"

---

### 3. Verify

Next GitHub Actions build will show:
```
✅ GOOGLE_API_KEY is set (length: XX chars)
✅ GOOGLE_CSE_ID is set (length: XX chars)
```

---

## ⚠️ Security Notes

- **NEVER** commit these credentials to the repository
- **NEVER** share them publicly
- **ALWAYS** use GitHub Secrets for CI/CD
- **ROTATE** keys if exposed

---

## 🧪 Testing

After adding secrets and rebuilding:

```bash
# Check device logs
adb logcat | grep "GOOGLE"

# Should see:
✅ Google API Key loaded from dart-define
✅ Google CSE ID loaded from dart-define
```

Ask Kai: "What's the latest tech news?"

---

**Status**: Ready to add credentials ⏳
