# Firebase App Distribution Integration

## 🎯 Overview
Your Homecoming AI Avatar app now automatically distributes to Firebase App Distribution whenever you push code to the main branch!

## 🔧 What's Set Up

### Automated Workflow
- **Trigger**: Push to main branch or manual workflow dispatch
- **Builds**: Release APK with your secure API keys
- **Distributes**: Automatically uploads to Firebase App Distribution
- **Notifies**: Testers receive email notifications with download links

### Required Secrets
Your repository needs these GitHub secrets configured:

| Secret Name | Description | Where to Find |
|-------------|-------------|---------------|
| `FIREBASE_APP_ID` | Your Firebase app identifier | Firebase Console → Project Settings → General |
| `FIREBASE_SERVICE_ACCOUNT_JSON` | Authentication for GitHub Actions | Google Cloud Console → Service Accounts |
| `OPENAI_API_KEY` | Your OpenAI API key | OpenAI Platform → API Keys |
| `ELEVENLABS_API_KEY` | Your ElevenLabs API key | ElevenLabs → Speech Synthesis |

## 🚀 How to Use

### 1. Complete Firebase Setup
Follow the steps in [FIREBASE_SETUP.md](FIREBASE_SETUP.md) to:
- Create Firebase project
- Add Android app
- Enable App Distribution
- Create service account
- Add GitHub secrets

### 2. Add Testers
In Firebase Console → App Distribution:
1. Click "Add testers"
2. Enter email addresses
3. Assign to "testers" group
4. Save changes

### 3. Trigger Distribution

#### Automatic (Recommended)
- Push any code to main branch
- GitHub Actions automatically builds and distributes
- Testers receive email notifications

#### Manual
1. Go to GitHub repository → Actions
2. Select "Build and Deploy to Firebase App Distribution"
3. Click "Run workflow"
4. Add release notes (optional)
5. Click "Run workflow"

## 📱 Tester Experience

### First Time Setup
1. **Receive Email**: Testers get invitation email from Firebase
2. **Accept Invitation**: Click link in email
3. **Install Firebase CLI** (if on Android): Download from email link
4. **Enable Unknown Sources**: Android settings for APK installation

### Getting Updates
1. **Email Notification**: Automatic when new build is distributed
2. **Download Link**: Direct download from email or Firebase App Distribution
3. **Install**: Replace existing app with new version
4. **Test**: App includes latest features with your API keys

## 🔍 Monitoring

### GitHub Actions
- View build progress in repository Actions tab
- Check logs for any distribution failures
- Monitor build times and success rates

### Firebase Console
- App Distribution dashboard shows:
  - Number of releases
  - Tester engagement
  - Download statistics
  - Crash reports (if enabled)

### Release Management
- Each build gets automatic version number
- Release notes from commit messages or manual input
- Historical tracking of all distributions

## 🎁 Benefits

### For You (Developer)
- ✅ **Zero-touch deployment**: Push code, testers get updates
- ✅ **Secure key management**: API keys never exposed
- ✅ **Professional distribution**: No manual APK sharing
- ✅ **Version tracking**: Complete release history

### For Testers
- ✅ **Easy installation**: Direct download links via email
- ✅ **Automatic notifications**: Know when updates available
- ✅ **Professional experience**: Proper app distribution
- ✅ **Latest features**: Always get newest version with your keys

## 🔧 Customization

### Release Notes
Customize in workflow file or provide during manual trigger:
```yaml
releaseNotes: |
  🤖 Homecoming AI Avatar - Build #${{ github.run_number }}
  
  ✨ What's New:
  - Enhanced personality system
  - Improved voice synthesis
  - Bug fixes and performance improvements
  
  📱 Your API keys are securely embedded!
```

### Tester Groups
Create multiple tester groups in Firebase:
- `alpha-testers`: Internal team
- `beta-testers`: Trusted external users  
- `testers`: General testing group

### Build Triggers
Modify when distributions happen:
- Every push to main (current)
- Only on version tags
- Manual approval required
- Scheduled builds

## 🔄 Workflow Summary

1. **Code Changes**: You push updates to main branch
2. **Automated Build**: GitHub Actions builds APK with your API keys
3. **Firebase Upload**: APK automatically uploaded to App Distribution
4. **Tester Notification**: Emails sent to all testers in group
5. **Easy Installation**: Testers download and install new version
6. **Testing**: Fresh app with latest features and your secure API keys

Your Homecoming AI Avatar app now has professional-grade distribution! 🎉