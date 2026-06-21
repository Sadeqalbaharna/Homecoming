# Quick Test: Send 10 Messages to Trigger Memory Formation
# This will create a conversation buffer and then a memory shard

Write-Host "🧪 Testing Kai Brain Memory System..." -ForegroundColor Cyan
Write-Host ""

$baseUrl = "https://homecoming-74f73-default-rtdb.europe-west1.firebasedatabase.app"
$personaId = "truekai"

# Test messages that will trigger fact extraction
$testMessages = @(
    @{ user = "Hi Kai! My name is Sadeq"; ai = "Nice to meet you, Sadeq! I'll remember your name." },
    @{ user = "I love coffee in the morning"; ai = "Coffee in the morning - got it! That's a great way to start the day." },
    @{ user = "I'm working on an AI project"; ai = "That sounds exciting! Tell me more about your AI project." },
    @{ user = "I want to learn more about machine learning"; ai = "Machine learning is fascinating! I can help you learn." },
    @{ user = "My goal is to build a conversational AI"; ai = "That's an ambitious goal! Building conversational AI is challenging but rewarding." },
    @{ user = "I prefer using Flutter for mobile development"; ai = "Flutter is a great choice! I'll remember you prefer Flutter." },
    @{ user = "I live in Bahrain"; ai = "Bahrain! Beautiful place. I'll remember that." },
    @{ user = "I enjoy coding late at night"; ai = "A night owl! Many developers are. I'll keep that in mind." },
    @{ user = "I want to integrate Firebase for backend"; ai = "Firebase is perfect for that! Good choice for backend." },
    @{ user = "Let's make Kai remember everything!"; ai = "Yes! I'm now storing all our conversations in my memory system." }
)

Write-Host "📤 Sending $($testMessages.Count) test conversations..." -ForegroundColor Yellow
Write-Host ""

for ($i = 0; $i -lt $testMessages.Count; $i++) {
    $msg = $testMessages[$i]
    $timestamp = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    
    $data = @{
        userMessage = $msg.user
        aiResponse = $msg.ai
        timestamp = $timestamp
        personalityDeltas = @{
            warmth = Get-Random -Minimum 1 -Maximum 3
            energy = Get-Random -Minimum 1 -Maximum 3
            curiosity = Get-Random -Minimum 1 -Maximum 2
        }
    } | ConvertTo-Json
    
    try {
        $conversationId = "conv_test_$(Get-Date -Format 'yyyyMMdd_HHmmss')_$i"
        $url = "$baseUrl/conversations/$personaId/$conversationId.json"
        
        $response = Invoke-RestMethod -Uri $url -Method Put -Body $data -ContentType "application/json" -ErrorAction Stop
        
        Write-Host "  ✅ Message $($i + 1)/$($testMessages.Count): " -NoNewline -ForegroundColor Green
        Write-Host "$($msg.user.Substring(0, [Math]::Min(40, $msg.user.Length)))..." -ForegroundColor White
        
        Start-Sleep -Milliseconds 800  # Slight delay between messages
    }
    catch {
        Write-Host "  ❌ Failed to send message $($i + 1): $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "🎉 Test complete! Sent $($testMessages.Count) conversations." -ForegroundColor Green
Write-Host ""
Write-Host "⏳ Memory shard should form in ~30-60 seconds..." -ForegroundColor Yellow
Write-Host ""
Write-Host "🔍 Check memory formation:" -ForegroundColor Cyan
Write-Host "  1. Firebase Console: https://console.firebase.google.com/project/homecoming-74f73/database" -ForegroundColor White
Write-Host "  2. View buffer: " -NoNewline -ForegroundColor White
Write-Host "/memory/buffers/$personaId" -ForegroundColor Yellow
Write-Host "  3. Wait for shard: " -NoNewline -ForegroundColor White
Write-Host "/memory/shards/$personaId" -ForegroundColor Yellow
Write-Host "  4. View facts: " -NoNewline -ForegroundColor White
Write-Host "/memory/facts/$personaId" -ForegroundColor Yellow
Write-Host ""
Write-Host "💡 Or use CLI:" -ForegroundColor Cyan
Write-Host "  firebase database:get /memory/buffers/$personaId" -ForegroundColor White
Write-Host "  firebase database:get /memory/shards/$personaId" -ForegroundColor White
Write-Host "  firebase database:get /memory/facts/$personaId" -ForegroundColor White
Write-Host ""

# Wait a moment then check buffer status
Write-Host "⏳ Checking buffer status in 5 seconds..." -ForegroundColor Yellow
Start-Sleep -Seconds 5

try {
    $bufferUrl = "$baseUrl/memory/buffers/$personaId.json"
    $buffer = Invoke-RestMethod -Uri $bufferUrl -Method Get -ErrorAction Stop
    
    if ($buffer) {
        Write-Host ""
        Write-Host "📊 Current Buffer Status:" -ForegroundColor Green
        Write-Host "  Turn Count: $($buffer.turnCount)" -ForegroundColor White
        Write-Host "  First Turn: $([DateTimeOffset]::FromUnixTimeMilliseconds($buffer.firstTurnTime).ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor White
        
        if ($buffer.turnCount -ge 10) {
            Write-Host ""
            Write-Host "🎉 Buffer has 10+ turns! Shard creation should trigger soon!" -ForegroundColor Green
        }
        else {
            Write-Host "  Remaining: $( 10 - $buffer.turnCount ) turns until shard creation" -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "⚠️  Buffer not found - functions may not be deployed yet." -ForegroundColor Yellow
        Write-Host "   Run: .\deploy-kai-brain.ps1" -ForegroundColor White
    }
}
catch {
    Write-Host "⚠️  Could not read buffer - functions may not be deployed yet." -ForegroundColor Yellow
    Write-Host "   Run: .\deploy-kai-brain.ps1" -ForegroundColor White
}

Write-Host ""
Write-Host "Done! Monitor the Firebase Console to see memory formation." -ForegroundColor Cyan
