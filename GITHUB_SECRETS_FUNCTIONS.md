# Using GitHub Secrets for Cloud Functions Deployment

## 🔐 Overview

Your OpenAI API key is stored securely in **GitHub Secrets** and is automatically injected into Cloud Functions during deployment via GitHub Actions.

## 📋 Current Setup

### GitHub Secrets (Already Configured)
- `OPEN_API_KEY` - Your OpenAI API key
- `FIREBASE_SERVICE_ACCOUNT_JSON` - Firebase service account for deployment
- `FIREBASE_APP_ID` - Firebase app ID

### How It Works

1. **GitHub Actions Workflow** (`.github/workflows/deploy-functions.yml`):
   - Triggers on push to `main` or when `functions/**` files change
   - Creates a `.env` file with your `OPEN_API_KEY` from GitHub Secrets
   - Deploys functions to Firebase with environment variable support
   - Cleans up `.env` file after deployment

2. **Cloud Functions Code** (`functions/index.js`):
   ```javascript
   require('dotenv').config();
   const openai = new OpenAI({
     apiKey: process.env.OPENAI_API_KEY
   });
   ```

3. **Security**:
   - `.env` file is in `.gitignore` (never committed)
   - Key only exists during GitHub Actions deployment
   - Local development requires manual `.env` file creation

## 🚀 Deployment Methods

### Method 1: Automatic (GitHub Actions) ✅ RECOMMENDED
Just push your code to GitHub:
```powershell
git add .
git commit -m "Update Cloud Functions"
git push origin main
```

The workflow automatically:
- Detects changes in `functions/**`
- Creates `.env` file with your secret
- Deploys to Firebase
- Cleans up secrets

### Method 2: Manual (Local Deployment)
For testing before pushing to GitHub:

1. **Get your OpenAI API key** from https://platform.openai.com/account/api-keys

2. **Create `.env` file** in `functions/` folder:
   ```bash
   OPENAI_API_KEY=sk-proj-YOUR_ACTUAL_KEY_HERE
   ```

3. **Deploy using the script**:
   ```powershell
   .\deploy-functions.ps1
   ```

   Or manually:
   ```powershell
   $env:OPENAI_API_KEY = "sk-proj-YOUR_KEY_HERE"
   firebase deploy --only functions
   ```

## 🔍 Verification

After deployment, test that the API key is working:

```powershell
# Send a test conversation
.\test-memory-simple.ps1

# Check function logs (should show SUCCESS, not 401 errors)
gcloud functions logs read onTurnWrite --limit=5 --project=homecoming-74f73

# Check if shard was created
firebase database:get /memory/shards/truekai
```

## ⚠️ Important Notes

### DO NOT:
- ❌ Hardcode API keys in `index.js` (security risk!)
- ❌ Commit `.env` files to Git (already in `.gitignore`)
- ❌ Use `firebase functions:config:set` (deprecated March 2026)

### DO:
- ✅ Use GitHub Secrets for production deployments
- ✅ Use `.env` file for local testing (not committed)
- ✅ Keep `.env.example` updated with required variables
- ✅ Test locally before pushing to GitHub

## 🔄 Updating Your API Key

### If Your OpenAI Key Changes:

1. **Update GitHub Secret**:
   - Go to: https://github.com/Sadeqalbaharna/Homecoming/settings/secrets/actions
   - Edit `OPEN_API_KEY`
   - Paste new key
   - Save

2. **Trigger Redeployment**:
   ```powershell
   # Make a small change to force redeployment
   git commit --allow-empty -m "Redeploy with updated API key"
   git push origin main
   ```

3. **Verify**:
   - Check GitHub Actions tab for successful deployment
   - Test memory system with `.\test-memory-simple.ps1`

## 📁 File Structure

```
functions/
├── index.js           # Main functions code (uses process.env.OPENAI_API_KEY)
├── package.json       # Includes dotenv dependency
├── .env              # Local only (gitignored, create manually)
├── .env.example      # Template for .env file
└── .gitignore        # Ensures .env is never committed

.github/workflows/
└── deploy-functions.yml  # Auto-deploys with GitHub Secrets
```

## 🐛 Troubleshooting

### "401 Incorrect API key" Error

**Problem**: Functions still using old/invalid key

**Solutions**:
1. Check GitHub Secret is correct (go to repo settings → Secrets)
2. Verify `.env` file exists locally (for manual deployment)
3. Delete and recreate function:
   ```powershell
   firebase functions:delete onTurnWrite --force
   firebase deploy --only functions:onTurnWrite
   ```

### ".env file not found" (Local Development)

**Problem**: No `.env` file in `functions/` folder

**Solution**: Copy template and add your key
```powershell
cp functions/.env.example functions/.env
# Edit functions/.env and add your actual key
```

### "OPENAI_API_KEY is not defined"

**Problem**: Environment variable not loaded

**Solutions**:
1. Ensure `dotenv` is installed: `cd functions; npm install`
2. Check `.env` file exists in `functions/` folder
3. Verify `.env` has correct format (no quotes around key):
   ```
   OPENAI_API_KEY=sk-proj-YOUR_KEY_HERE
   ```

## 📊 Cost Monitoring

With valid API key, monitor costs:
- **Firebase Console**: https://console.firebase.google.com/project/homecoming-74f73/usage
- **OpenAI Dashboard**: https://platform.openai.com/usage

Expected costs:
- **Cloud Functions**: $0-2/month (within free tier)
- **OpenAI API**: ~$0.10 per 1000 conversations
- **Total**: $0.10-2.00/month for typical usage

## ✅ Quick Start Checklist

- [ ] Verify `OPEN_API_KEY` exists in GitHub Secrets
- [ ] Create local `.env` file (for manual testing)
- [ ] Push code to GitHub to trigger auto-deployment
- [ ] Verify deployment in GitHub Actions tab
- [ ] Test with `.\test-memory-simple.ps1`
- [ ] Check function logs show no 401 errors
- [ ] Verify shards/embeddings/facts are created

## 🔗 Related Documentation

- [Accessing Kai Brain](ACCESSING_KAI_BRAIN.md) - Full memory system guide
- [Quick Start](QUICK_START_BRAIN.md) - Get started in 3 steps
- [Firebase Setup](FIREBASE_SETUP.md) - Initial Firebase configuration
- [GitHub Actions Setup](GITHUB_ACTIONS.md) - CI/CD pipeline details
