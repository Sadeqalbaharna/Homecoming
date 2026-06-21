# GitHub Actions Automated Builds

## 🚀 Automated Building with Your API Keys

Your repository now has GitHub Actions workflows that automatically build APKs using your secure API keys stored in repository secrets.

## 🔧 Available Workflows

### 1. **Manual APK Builder** (`build-apk.yml`)
- **Trigger**: Manual (on-demand)
- **Purpose**: Build APK with your API keys when you need it
- **Location**: Actions tab → "Build APK with Secrets"

**How to Use:**
1. Go to your repository on GitHub
2. Click the "Actions" tab
3. Select "Build APK with Secrets" 
4. Click "Run workflow"
5. Choose build type (debug/release)
6. Click "Run workflow" button
7. Wait for build to complete
8. Download APK from "Artifacts" section

### 2. **Full Build & Release** (`build-and-release.yml`)
- **Trigger**: Automatic on push to main branch
- **Purpose**: Full CI/CD with releases
- **Builds**: Android APK + Web version
- **Creates**: GitHub release with downloadable APK

## 📱 How to Get Your APK

### Method 1: Manual Build (Recommended)
1. **Trigger Build**: Go to Actions → "Build APK with Secrets" → Run workflow
2. **Wait**: Build takes ~5-10 minutes
3. **Download**: Click on the workflow run → Artifacts → Download APK
4. **Install**: Transfer to phone and install

### Method 2: Automatic Releases
1. **Push Code**: Any push to main branch triggers build
2. **Check Releases**: Go to repository → Releases
3. **Download**: Latest release has APK attached
4. **Install**: Direct download to phone

## 🔑 Security Features

✅ **API keys stored securely in GitHub secrets**
✅ **Never exposed in logs or code**  
✅ **Automatically included in builds**
✅ **No manual key management needed**

## 🛠️ Build Details

**Your builds include:**
- OpenAI API key (from `secrets.OPENAI_API_KEY`)
- ElevenLabs API key (from `secrets.ELEVENLABS_API_KEY`)
- Full Flutter app with all features
- Cross-platform compatibility
- Optimized release build

## 📊 Build Status

Check build status in the Actions tab:
- ✅ **Green**: Build successful, APK ready
- 🟡 **Yellow**: Build in progress
- ❌ **Red**: Build failed, check logs

## 🔄 Workflow Triggers

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| Build APK | Manual | On-demand APK builds |
| Build & Release | Push to main | Automatic releases |

## 📲 Direct Phone Installation

Once you download the APK:
1. **Transfer**: USB, email, or cloud storage
2. **Enable**: "Install from unknown sources" 
3. **Install**: Tap APK file
4. **Enjoy**: Kai with your API keys built-in!

## 🔍 Troubleshooting

**Build Fails?**
- Check if API keys are set in repository secrets
- Verify key names: `OPENAI_API_KEY` and `ELEVENLABS_API_KEY`
- Check Actions logs for detailed error messages

**APK Won't Install?**
- Enable "Install unknown apps" for your file manager
- Try downloading APK again
- Check if device storage is sufficient

## ⚡ Quick Start

1. **Set Secrets**: Repository Settings → Secrets → Add API keys
2. **Run Build**: Actions → "Build APK with Secrets" → Run workflow  
3. **Download**: Wait for completion → Download from Artifacts
4. **Install**: Transfer to phone and install

Your app is now fully automated with secure API key management! 🎉