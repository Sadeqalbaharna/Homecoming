# Load GitHub Secrets locally for V1 testing
# 
# Your secrets are stored on GitHub Actions. To run kai_table_v1_core.py locally,
# you need to add them to your local environment.

# Option 1: Manual (paste your keys here)
$env:OPENAI_API_KEY = ""           # sk-... from GitHub secrets: OPEN_API_KEY
$env:ELEVENLABS_API_KEY = ""       # From GitHub secrets
$env:GOOGLE_API_KEY = ""           # From GitHub secrets
$env:GOOGLE_CSE_ID = ""            # From GitHub secrets

# Option 2: Create a .env file and load it
# Copy your secrets to a file:
#   OPENAI_API_KEY=sk-...
#   ELEVENLABS_API_KEY=...
#   GOOGLE_API_KEY=...
#   GOOGLE_CSE_ID=...
# Then uncomment and run:
# if (Test-Path ".env") {
#     Get-Content ".env" | ForEach-Object {
#         if ($_ -match "^([^=]+)=(.*)$") {
#             [Environment]::SetEnvironmentVariable($matches[1], $matches[2])
#         }
#     }
# }

# Option 3: For Firebase, you need the service account JSON
# Download from: https://console.firebase.google.com/ → Project settings → Service accounts
# Save to: $HOME/.kai/firebase_service_account.json
# Or set the path:
# $env:FIREBASE_CREDENTIALS = "$HOME/.kai/firebase_service_account.json"

Write-Host "
===============================================
       GitHub Secrets Loader for V1 Testing
===============================================

Your GitHub secrets are set in the workflows:
  - OPEN_API_KEY (for OpenAI)
  - ELEVENLABS_API_KEY
  - GOOGLE_API_KEY
  - GOOGLE_CSE_ID
  - FIREBASE_SERVICE_ACCOUNT_JSON

To run kai_table_v1_core.py locally:

1. Go to: https://github.com/YOUR_REPO/settings/secrets/actions
2. Copy your OPEN_API_KEY value
3. Paste it above where it says: sk-...
4. Run this script
5. Then: python kai_table_v1_core.py

Or use Option 2 (.env file) for easier management.

===============================================
"

# Verify loaded
if ($env:OPENAI_API_KEY) {
    Write-Host "✓ OPENAI_API_KEY loaded" -ForegroundColor Green
} else {
    Write-Host "✗ OPENAI_API_KEY not set" -ForegroundColor Red
}

if ($env:FIREBASE_CREDENTIALS) {
    Write-Host "✓ FIREBASE_CREDENTIALS set" -ForegroundColor Green
} else {
    Write-Host "✗ FIREBASE_CREDENTIALS not set (optional for demo)" -ForegroundColor Yellow
}
