# Setup and Test Memory System
# This script helps you configure and test the Kai Brain memory system

Write-Host "🧠 Kai Brain Memory System - Setup & Test" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""

# Step 1: Check if .env exists
if (-not (Test-Path "functions\.env")) {
    Write-Host "⚠️  No .env file found in functions/ folder" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "To test the memory system locally, we need your OpenAI API key." -ForegroundColor White
    Write-Host ""
    Write-Host "📋 Options:" -ForegroundColor Cyan
    Write-Host "  1. Create functions/.env manually with:" -ForegroundColor Gray
    Write-Host "     OPENAI_API_KEY=sk-proj-YOUR_KEY_HERE" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  2. Or paste your key now and I'll create it for you" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Get your key from: https://platform.openai.com/account/api-keys" -ForegroundColor Yellow
    Write-Host ""
    
    $key = Read-Host "Enter your OpenAI API key (or press Enter to skip)"
    
    if ($key) {
        Write-Host ""
        Write-Host "✅ Creating .env file..." -ForegroundColor Green
        Set-Content -Path "functions\.env" -Value "OPENAI_API_KEY=$key"
        Write-Host "✅ .env file created!" -ForegroundColor Green
        Write-Host ""
    } else {
        Write-Host ""
        Write-Host "⏭️  Skipping .env creation. Please create it manually before deploying." -ForegroundColor Yellow
        Write-Host ""
        exit 0
    }
} else {
    Write-Host "✅ Found existing .env file" -ForegroundColor Green
    Write-Host ""
}

# Step 2: Deploy functions
Write-Host "🚀 Deploying Cloud Functions..." -ForegroundColor Cyan
firebase deploy --only functions --project homecoming-74f73

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "❌ Deployment failed!" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "✅ Functions deployed successfully!" -ForegroundColor Green
Write-Host ""

# Step 3: Clear old data
Write-Host "🧹 Clearing old test data..." -ForegroundColor Yellow
firebase database:remove /conversations/truekai --project homecoming-74f73 --force | Out-Null
firebase database:remove /memory/buffers/truekai --project homecoming-74f73 --force | Out-Null
firebase database:remove /memory/shards/truekai --project homecoming-74f73 --force | Out-Null
Write-Host "✅ Old data cleared!" -ForegroundColor Green
Write-Host ""

# Step 4: Send test conversations
Write-Host "📤 Sending 10 test conversations..." -ForegroundColor Cyan
Write-Host ""

$baseUrl = "https://homecoming-74f73-default-rtdb.europe-west1.firebasedatabase.app"
$messages = @(
    "My name is Sadeq and I'm working on an AI project",
    "I love coffee in the morning, especially cappuccino",
    "I live in Bahrain and work on Flutter apps",
    "My favorite programming language is Dart",
    "I'm building a memory system for my AI assistant named Kai",
    "I prefer dark mode in all my development tools",
    "I usually code late at night when it's quiet",
    "I want Kai to remember our conversations and learn from them",
    "I'm interested in AI embeddings and semantic search",
    "This is the 10th message to trigger memory shard creation"
)

for ($i = 0; $i -lt $messages.Count; $i++) {
    $convId = "test_conv_$i"
    $body = @{
        userMessage = $messages[$i]
        aiResponse = "I understand, I'll remember that about you."
        timestamp = [DateTimeOffset]::Now.ToUnixTimeMilliseconds()
        personalityDeltas = @{
            confident = 0.05
            analytical = 0.03
        }
    } | ConvertTo-Json -Compress
    
    Invoke-WebRequest -Uri "$baseUrl/conversations/truekai/$convId.json" `
        -Method PUT `
        -Body $body `
        -ContentType "application/json" `
        -UseBasicParsing | Out-Null
    
    Write-Host "  ✓ Message $($i+1)/10 sent" -ForegroundColor Gray
    Start-Sleep -Milliseconds 500
}

Write-Host ""
Write-Host "✅ All conversations sent!" -ForegroundColor Green
Write-Host ""

# Step 5: Wait for processing
Write-Host "Waiting 40 seconds for memory system to process..." -ForegroundColor Yellow
Write-Host ""
Write-Host "What's happening:" -ForegroundColor Cyan
Write-Host "  1. onTurnWrite: Building buffer and creating shard" -ForegroundColor Gray
Write-Host "  2. onShardWrite: Generating embeddings" -ForegroundColor Gray
Write-Host "  3. extractFacts: Extracting knowledge" -ForegroundColor Gray
Write-Host ""

for ($i = 40; $i -gt 0; $i--) {
    Write-Host "`r  ⏱️  $i seconds remaining..." -NoNewline -ForegroundColor Gray
    Start-Sleep -Seconds 1
}

Write-Host ""
Write-Host ""

# Step 6: Check results
Write-Host "🔍 Checking Results..." -ForegroundColor Cyan
Write-Host ""

Write-Host "1️⃣ Buffer Status:" -ForegroundColor Yellow
$bufferJson = firebase database:get /memory/buffers/truekai --project homecoming-74f73
$buffer = $bufferJson | ConvertFrom-Json
if ($buffer.turnCount) {
    Write-Host "   ✅ Buffer has $($buffer.turnCount) turns" -ForegroundColor Green
} else {
    Write-Host "   ❌ No buffer found" -ForegroundColor Red
}
Write-Host ""

Write-Host "2️⃣ Memory Shards:" -ForegroundColor Yellow
$shardsJson = firebase database:get /memory/shards/truekai --project homecoming-74f73
if ($shardsJson -ne "null" -and $shardsJson) {
    $shards = $shardsJson | ConvertFrom-Json
    $shardCount = ($shards | Get-Member -MemberType NoteProperty).Count
    Write-Host "   ✅ Found $shardCount memory shard(s)" -ForegroundColor Green
    
    # Show first shard summary
    $firstShard = ($shards | Get-Member -MemberType NoteProperty)[0].Name
    $summary = $shards.$firstShard.summary
    if ($summary.Length -gt 100) {
        $summary = $summary.Substring(0, 100) + "..."
    }
    Write-Host "   📝 Summary: $summary" -ForegroundColor Gray
} else {
    Write-Host "   ❌ No shards created yet" -ForegroundColor Red
}
Write-Host ""

Write-Host "3️⃣ Embeddings:" -ForegroundColor Yellow
$embeddingsJson = firebase database:get /memory/embeddings/truekai --project homecoming-74f73
if ($embeddingsJson -ne "null" -and $embeddingsJson) {
    Write-Host "   ✅ Embeddings generated" -ForegroundColor Green
} else {
    Write-Host "   ❌ No embeddings yet" -ForegroundColor Red
}
Write-Host ""

Write-Host "4️⃣ Extracted Facts:" -ForegroundColor Yellow
$factsJson = firebase database:get /memory/facts/truekai --project homecoming-74f73
if ($factsJson -ne "null" -and $factsJson) {
    $facts = $factsJson | ConvertFrom-Json
    $factCount = ($facts | Get-Member -MemberType NoteProperty).Count
    Write-Host "   ✅ Extracted $factCount fact(s)" -ForegroundColor Green
    
    # Show first few facts
    $factKeys = ($facts | Get-Member -MemberType NoteProperty | Select-Object -First 3).Name
    foreach ($key in $factKeys) {
        $fact = $facts.$key
        Write-Host "   • $($fact.type): $($fact.fact)" -ForegroundColor Gray
    }
} else {
    Write-Host "   ❌ No facts extracted yet" -ForegroundColor Red
}
Write-Host ""

# Step 7: Check function logs
Write-Host "5️⃣ Function Logs (last 5 entries):" -ForegroundColor Yellow
gcloud functions logs read onTurnWrite --limit=5 --project=homecoming-74f73
Write-Host ""

# Summary
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "🎯 Summary" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "✅ Memory System Test Complete!" -ForegroundColor Green
Write-Host ""
Write-Host "📊 View in Firebase Console:" -ForegroundColor Cyan
Write-Host "   https://console.firebase.google.com/project/homecoming-74f73/database" -ForegroundColor Gray
Write-Host ""
Write-Host "📚 Documentation:" -ForegroundColor Cyan
Write-Host "   • ACCESSING_KAI_BRAIN.md - Full guide" -ForegroundColor Gray
Write-Host "   • QUICK_START_BRAIN.md - Quick reference" -ForegroundColor Gray
Write-Host "   • GITHUB_SECRETS_FUNCTIONS.md - Deployment guide" -ForegroundColor Gray
Write-Host ""
