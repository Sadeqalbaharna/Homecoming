# Process Existing Firebase Conversations
# This script triggers memory formation for all existing conversations

Write-Host "🧠 Kai Brain - Process Existing Conversations" -ForegroundColor Cyan
Write-Host "=============================================`n" -ForegroundColor Cyan

# Check if we're in the functions directory
if (-not (Test-Path "index.js")) {
    Write-Host "❌ Error: Must run from functions/ directory" -ForegroundColor Red
    Write-Host "Run: cd functions; .\process-existing.ps1" -ForegroundColor Yellow
    exit 1
}

# Check if service account key exists
if (-not (Test-Path "serviceAccountKey.json")) {
    Write-Host "⚠️  Service account key not found!" -ForegroundColor Yellow
    Write-Host "`nYou need to download your Firebase service account key:" -ForegroundColor White
    Write-Host "1. Go to Firebase Console → Project Settings → Service Accounts" -ForegroundColor White
    Write-Host "2. Click 'Generate new private key'" -ForegroundColor White
    Write-Host "3. Save as 'serviceAccountKey.json' in functions/ directory" -ForegroundColor White
    Write-Host "`nPress Enter after downloading the key..." -ForegroundColor Yellow
    Read-Host
    
    if (-not (Test-Path "serviceAccountKey.json")) {
        Write-Host "❌ Key still not found. Exiting." -ForegroundColor Red
        exit 1
    }
}

# Check if .env exists with OpenAI key
if (-not (Test-Path ".env")) {
    Write-Host "⚠️  .env file not found!" -ForegroundColor Yellow
    Write-Host "Creating .env file..." -ForegroundColor White
    
    $openaiKey = Read-Host "Enter your OpenAI API key"
    "OPENAI_API_KEY=$openaiKey" | Out-File -FilePath ".env" -Encoding UTF8
    
    Write-Host "✅ .env file created" -ForegroundColor Green
}

# Update database URL in script
Write-Host "`n📝 Updating script with your Firebase project..." -ForegroundColor Cyan

# Read service account to get project ID
$serviceAccount = Get-Content "serviceAccountKey.json" | ConvertFrom-Json
$projectId = $serviceAccount.project_id

Write-Host "Project ID: $projectId" -ForegroundColor White

# Update the script
$scriptContent = Get-Content "process-existing-data.js" -Raw
$scriptContent = $scriptContent -replace "databaseURL: 'https://your-project-id.firebaseio.com'", "databaseURL: 'https://$projectId-default-rtdb.firebaseio.com'"
$scriptContent | Out-File -FilePath "process-existing-data.js" -Encoding UTF8 -NoNewline

Write-Host "✅ Script updated" -ForegroundColor Green

# Run the script
Write-Host "`n🚀 Running memory formation script..." -ForegroundColor Cyan
Write-Host "This will:" -ForegroundColor White
Write-Host "  1. Fetch all conversations from /conversations/truekai/" -ForegroundColor White
Write-Host "  2. Group into shards of 10 conversations" -ForegroundColor White
Write-Host "  3. Generate summaries using GPT-4o-mini" -ForegroundColor White
Write-Host "  4. Create embeddings using OpenAI" -ForegroundColor White
Write-Host "  5. Save to /memory/shards/ and /memory/embeddings/" -ForegroundColor White
Write-Host ""

$continue = Read-Host "Continue? (y/n)"
if ($continue -ne "y") {
    Write-Host "❌ Cancelled" -ForegroundColor Red
    exit 0
}

Write-Host "`n⏳ Processing... This may take a few minutes...`n" -ForegroundColor Yellow

node process-existing-data.js

if ($LASTEXITCODE -eq 0) {
    Write-Host "`n✅ SUCCESS! Memory formation complete!" -ForegroundColor Green
    Write-Host "`nYour existing conversations have been processed." -ForegroundColor White
    Write-Host "Memory shards and embeddings are now available." -ForegroundColor White
    Write-Host "`nNext: Run your app and test with:" -ForegroundColor Cyan
    Write-Host "  'What do you know about me?'" -ForegroundColor Yellow
    Write-Host "  'What have we discussed?'" -ForegroundColor Yellow
    Write-Host "`nYou should see purple badges with memory recalls!" -ForegroundColor Magenta
} else {
    Write-Host "`n❌ Script failed. Check the error messages above." -ForegroundColor Red
    Write-Host "`nCommon issues:" -ForegroundColor Yellow
    Write-Host "  - OpenAI API key invalid" -ForegroundColor White
    Write-Host "  - Service account permissions insufficient" -ForegroundColor White
    Write-Host "  - Database URL incorrect" -ForegroundColor White
}
