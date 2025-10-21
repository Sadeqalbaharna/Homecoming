# 🔧 Fix GitHub Actions IAM Permissions

**Date**: October 21, 2025  
**Issue**: Functions deployment failing - missing "Service Account User" role  
**Error**: `iam.serviceAccounts.ActAs` permission denied

---

## ❌ Current Error

```
Error: Missing permissions required for functions deploy. You must have permission 
iam.serviceAccounts.ActAs on service account 
homecoming-74f73@appspot.gserviceaccount.com.

To address this error, ask a project Owner to assign your account the 
"Service Account User" role from this URL:
https://console.cloud.google.com/iam-admin/iam?project=homecoming-74f73

Error: Process completed with exit code 1.
```

**Root Cause**: The service account used by GitHub Actions doesn't have permission to deploy Cloud Functions.

---

## ✅ Solution: Grant IAM Roles

### Option 1: Via Console (Recommended)

**I just opened the IAM console for you.** Follow these steps:

1. **Find the Service Account**:
   - Look for: `homecoming-74f73@appspot.gserviceaccount.com`
   - This is your App Engine default service account

2. **Click the Pencil Icon** (Edit) next to it

3. **Add These Roles**:
   - ✅ **Service Account User** (`roles/iam.serviceAccountUser`)
   - ✅ **Cloud Functions Developer** (`roles/cloudfunctions.developer`)
   - ✅ **Cloud Build Service Account** (`roles/cloudbuild.builds.builder`)

4. **Click "Save"**

5. **Wait 1-2 minutes** for permissions to propagate

---

### Option 2: Via Command Line

Run these commands in PowerShell:

```powershell
# Set your project
$PROJECT_ID = "homecoming-74f73"
$SERVICE_ACCOUNT = "$PROJECT_ID@appspot.gserviceaccount.com"

# Grant Service Account User role
gcloud projects add-iam-policy-binding $PROJECT_ID `
  --member="serviceAccount:$SERVICE_ACCOUNT" `
  --role="roles/iam.serviceAccountUser"

# Grant Cloud Functions Developer role
gcloud projects add-iam-policy-binding $PROJECT_ID `
  --member="serviceAccount:$SERVICE_ACCOUNT" `
  --role="roles/cloudfunctions.developer"

# Grant Cloud Build Service Account role
gcloud projects add-iam-policy-binding $PROJECT_ID `
  --member="serviceAccount:$SERVICE_ACCOUNT" `
  --role="roles/cloudbuild.builds.builder"

# Verify roles
gcloud projects get-iam-policy $PROJECT_ID `
  --flatten="bindings[].members" `
  --format="table(bindings.role)" `
  --filter="bindings.members:$SERVICE_ACCOUNT"
```

---

## 🔍 Why This Happened

GitHub Actions workflow tries to deploy Cloud Functions, which requires:
1. **Service Account User** - To act as the service account
2. **Cloud Functions Developer** - To deploy/update functions
3. **Cloud Build** - To build function containers

The default App Engine service account (`homecoming-74f73@appspot.gserviceaccount.com`) needs these roles.

---

## 📋 Verification Steps

### 1. Check Current Roles
```powershell
gcloud projects get-iam-policy homecoming-74f73 `
  --flatten="bindings[].members" `
  --filter="bindings.members:homecoming-74f73@appspot.gserviceaccount.com"
```

**Expected Output** (after fix):
```
ROLE: roles/cloudfunctions.developer
ROLE: roles/iam.serviceAccountUser
ROLE: roles/cloudbuild.builds.builder
ROLE: roles/editor (or similar)
```

### 2. Re-run GitHub Actions
After granting permissions:

**Option A - Via GitHub UI**:
1. Go to: https://github.com/Sadeqalbaharna/Homecoming/actions
2. Click on the failed workflow run
3. Click "Re-run all jobs"

**Option B - Push Empty Commit**:
```powershell
cd C:\code\homecoming_app
git commit --allow-empty -m "chore: Trigger build after IAM fix"
git push origin main
```

---

## 🚫 Alternative: Skip Functions Deployment in GitHub Actions

If you prefer to deploy functions manually and only use GitHub Actions for APK building:

### Modify `.github/workflows/build-and-distribute.yml`

Comment out or remove the functions deployment step:

```yaml
# - name: Deploy Cloud Functions
#   run: |
#     cd functions
#     npm ci
#     firebase deploy --only functions --project homecoming-74f73
```

This way:
- ✅ GitHub Actions builds APK
- ✅ APK uploaded to Firebase App Distribution
- ❌ Functions NOT deployed (deploy manually when needed)

---

## 🎯 Recommended Approach

### For Production Apps:

**Keep Functions Deployment Separate**:
1. **GitHub Actions**: Build and distribute APK only
2. **Manual Deployment**: Deploy functions when functions code changes

**Why?**
- Functions change less frequently than app code
- Faster CI/CD pipeline (no function deployment delay)
- Clearer separation of concerns
- Avoid unnecessary function redeployments

### Current Workflow Should Be:

```yaml
name: Build and Distribute

on:
  push:
    branches: [ main ]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
      - name: Setup Flutter
      - name: Build APK
      - name: Upload to Firebase App Distribution
      # Functions deployed separately when needed
```

---

## 📝 Quick Fix Commands

### Grant Permissions (Copy-Paste)
```powershell
# Grant all required roles at once
gcloud projects add-iam-policy-binding homecoming-74f73 --member="serviceAccount:homecoming-74f73@appspot.gserviceaccount.com" --role="roles/iam.serviceAccountUser"
gcloud projects add-iam-policy-binding homecoming-74f73 --member="serviceAccount:homecoming-74f73@appspot.gserviceaccount.com" --role="roles/cloudfunctions.developer"
gcloud projects add-iam-policy-binding homecoming-74f73 --member="serviceAccount:homecoming-74f73@appspot.gserviceaccount.com" --role="roles/cloudbuild.builds.builder"

Write-Host "✅ Permissions granted! Wait 1-2 minutes, then re-run GitHub Actions." -ForegroundColor Green
```

### Re-trigger Build
```powershell
cd C:\code\homecoming_app
git commit --allow-empty -m "chore: Retry after IAM fix"
git push origin main
```

---

## 🔗 Useful Links

- **IAM Console**: https://console.cloud.google.com/iam-admin/iam?project=homecoming-74f73
- **GitHub Actions**: https://github.com/Sadeqalbaharna/Homecoming/actions
- **Functions Logs**: https://console.cloud.google.com/logs/query?project=homecoming-74f73
- **Service Accounts**: https://console.cloud.google.com/iam-admin/serviceaccounts?project=homecoming-74f73

---

## ✅ What to Do Now

### Choice 1: Grant Permissions (Recommended)
1. I opened the IAM console for you
2. Find `homecoming-74f73@appspot.gserviceaccount.com`
3. Add the 3 roles mentioned above
4. Re-run GitHub Actions

### Choice 2: Skip Functions in CI/CD
1. Remove functions deployment from workflow
2. Deploy functions manually when needed
3. Keep CI/CD focused on APK building

### Choice 3: Local Build Only
1. Stop using GitHub Actions for now
2. Build locally: `flutter build apk --release`
3. Upload manually to Firebase App Distribution

**Which approach would you like?** 🤔

---

**Status**: Waiting for IAM permissions to be granted, then we can re-run the build!
