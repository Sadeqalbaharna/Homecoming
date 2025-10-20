# Kai Brain - Quick Setup Script
# Run this to deploy the memory system to Firebase

Write-Host "🧠 Kai Brain Deployment" -ForegroundColor Cyan
Write-Host "======================" -ForegroundColor Cyan
Write-Host ""

# Check if Firebase CLI is installed
Write-Host "✓ Checking Firebase CLI..." -ForegroundColor Yellow
if (!(Get-Command firebase -ErrorAction SilentlyContinue)) {
    Write-Host "❌ Firebase CLI not found!" -ForegroundColor Red
    Write-Host "Install with: npm install -g firebase-tools" -ForegroundColor Yellow
    exit 1
}
Write-Host "✓ Firebase CLI found" -ForegroundColor Green
Write-Host ""

# Navigate to functions directory
Write-Host "📦 Installing dependencies..." -ForegroundColor Yellow
Set-Location functions
npm install
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ npm install failed!" -ForegroundColor Red
    exit 1
}
Write-Host "✓ Dependencies installed" -ForegroundColor Green
Set-Location ..
Write-Host ""

# Set Firebase project
Write-Host "🔧 Setting Firebase project..." -ForegroundColor Yellow
firebase use homecoming-74f73
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Failed to set project!" -ForegroundColor Red
    Write-Host "Run: firebase login" -ForegroundColor Yellow
    exit 1
}
Write-Host "✓ Project set to homecoming-74f73" -ForegroundColor Green
Write-Host ""

# Configure OpenAI API key
Write-Host "🔑 Configuring OpenAI API key..." -ForegroundColor Yellow
$openaiKey = Read-Host "Enter your OpenAI API key (or press Enter to skip)"
if ($openaiKey) {
    firebase functions:config:set openai.key="$openaiKey"
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✓ OpenAI key configured" -ForegroundColor Green
    } else {
        Write-Host "⚠️  Failed to set API key" -ForegroundColor Yellow
    }
} else {
    Write-Host "⚠️  Skipped API key configuration" -ForegroundColor Yellow
    Write-Host "   Run later: firebase functions:config:set openai.key='YOUR_KEY'" -ForegroundColor Gray
}
Write-Host ""

# Deploy database rules
Write-Host "🗄️  Deploying database rules..." -ForegroundColor Yellow
firebase deploy --only database
if ($LASTEXITCODE -eq 0) {
    Write-Host "✓ Database rules deployed" -ForegroundColor Green
} else {
    Write-Host "❌ Database deployment failed!" -ForegroundColor Red
    exit 1
}
Write-Host ""

# Deploy functions
Write-Host "⚡ Deploying Cloud Functions..." -ForegroundColor Yellow
Write-Host "   This may take 3-5 minutes..." -ForegroundColor Gray
firebase deploy --only functions
if ($LASTEXITCODE -eq 0) {
    Write-Host "✓ Functions deployed successfully!" -ForegroundColor Green
} else {
    Write-Host "❌ Function deployment failed!" -ForegroundColor Red
    exit 1
}
Write-Host ""

# Summary
Write-Host "🎉 Deployment Complete!" -ForegroundColor Green
Write-Host "======================" -ForegroundColor Green
Write-Host ""
Write-Host "Deployed Functions:" -ForegroundColor Cyan
Write-Host "  • onTurnWrite - Rolling buffer & sharding" -ForegroundColor White
Write-Host "  • onShardWrite - Embedding generation" -ForegroundColor White
Write-Host "  • extractFacts - Fact extraction" -ForegroundColor White
Write-Host "  • dailyCompactor - Daily summaries (2 AM UTC)" -ForegroundColor White
Write-Host "  • queryMemory - Semantic search (callable)" -ForegroundColor White
Write-Host "  • extractFactsManual - Manual fact extraction (callable)" -ForegroundColor White
Write-Host ""
Write-Host "Next Steps:" -ForegroundColor Cyan
Write-Host "  1. Send a test conversation to Firebase" -ForegroundColor White
Write-Host "  2. Check logs: firebase functions:log" -ForegroundColor White
Write-Host "  3. View memory in Firebase Console:" -ForegroundColor White
Write-Host "     https://console.firebase.google.com/project/homecoming-74f73/database" -ForegroundColor Gray
Write-Host ""
Write-Host "View logs: firebase functions:log" -ForegroundColor Yellow
Write-Host "Test functions: firebase emulators:start" -ForegroundColor Yellow
Write-Host ""
Write-Host "🧠 Kai now has long-term memory!" -ForegroundColor Magenta
