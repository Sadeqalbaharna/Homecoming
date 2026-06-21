# 🔐 GitHub Secrets Configuration

Based on your Firebase project `homecoming-74f73`, here are the exact secrets you need to add to GitHub for Firebase App Distribution.

## 📋 Required GitHub Secrets

Go to: https://github.com/Sadeqalbaharna/Homecoming/settings/secrets/actions

### 1. Firebase App ID
```
Name: FIREBASE_APP_ID
Value: 1:632366966739:android:351bee9e47901e29ac3126
```

### 2. Firebase Service Account JSON
```
Name: FIREBASE_SERVICE_ACCOUNT_JSON
Value: [Get this from Firebase Console - see instructions below]
```

## 🔑 How to Get Service Account JSON

### Step 1: Go to Firebase Console
```
https://console.firebase.google.com/project/homecoming-74f73/settings/serviceaccounts/adminsdk
```

### Step 2: Generate New Private Key
1. Click "Generate new private key"
2. Click "Generate key" in the dialog
3. A JSON file will be downloaded

### Step 3: Copy JSON Content
Open the downloaded JSON file and copy the ENTIRE content. It should look like:
```json
{
  "type": "service_account",
  "project_id": "homecoming-74f73",
  "private_key_id": "...",
  "private_key": "-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n",
  "client_email": "firebase-adminsdk-...@homecoming-74f73.iam.gserviceaccount.com",
  "client_id": "...",
  "auth_uri": "https://accounts.google.com/o/oauth2/auth",
  "token_uri": "https://oauth2.googleapis.com/token",
  "auth_provider_x509_cert_url": "https://www.googleapis.com/oauth2/v1/certs",
  "client_x509_cert_url": "..."
}
```

### Step 4: Add to GitHub Secrets
1. Go to GitHub repository settings
2. Navigate to Secrets and variables → Actions
3. Click "New repository secret"
4. Name: `FIREBASE_SERVICE_ACCOUNT_JSON`
5. Value: Paste the ENTIRE JSON content
6. Click "Add secret"

## ✅ Verify Existing Secrets

Make sure these are already configured:
- ✅ `OPENAI_API_KEY` - Your OpenAI API key
- ✅ `ELEVENLABS_API_KEY` - Your ElevenLabs API key

## 🚀 Enable Firebase App Distribution

### Step 1: Enable App Distribution
```
https://console.firebase.google.com/project/homecoming-74f73/appdistribution
```
Click "Get started" if not already enabled.

### Step 2: Create Tester Group
1. Go to "Testers & Groups" tab
2. Click "Add group"
3. Group name: `testers`
4. Add email addresses of your testers

### Step 3: Set Database Rules
Go to: https://console.firebase.google.com/project/homecoming-74f73/database/homecoming-74f73-default-rtdb/rules

Replace the rules with:
```json
{
  "rules": {
    "personalities": {
      "$personaId": {
        ".read": true,
        ".write": true
      }
    },
    "conversations": {
      "$personaId": {
        ".read": true,
        ".write": true
      }
    },
    "analytics": {
      ".read": false,
      ".write": true
    }
  }
}
```

## 🎯 Ready to Deploy!

Once you've added the two GitHub secrets:
1. `FIREBASE_APP_ID` 
2. `FIREBASE_SERVICE_ACCOUNT_JSON`

You can deploy by simply pushing to main:
```bash
git push origin main
```

This will automatically:
- ✅ Build your APK with embedded API keys
- ✅ Upload to Firebase App Distribution  
- ✅ Notify your testers via email
- ✅ Make the app available for download

## 📱 For Testers

Your testers will:
1. Receive an email invitation from Firebase
2. Download the Firebase App Distribution app
3. Install Homecoming AI Avatar directly
4. Test the app with full functionality

## 🔍 Monitor Progress

After deployment, monitor:
- **GitHub Actions**: https://github.com/Sadeqalbaharna/Homecoming/actions
- **Firebase Console**: https://console.firebase.google.com/project/homecoming-74f73/appdistribution
- **Database Activity**: https://console.firebase.google.com/project/homecoming-74f73/database

Ready to launch! 🚀