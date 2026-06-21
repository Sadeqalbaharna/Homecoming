# Firebase Real-Time Monitor
# Watches for new conversations being added to Firebase

Write-Host ""
Write-Host "🔍 Firebase Real-Time Monitor" -ForegroundColor Cyan
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
Write-Host ""
Write-Host "📡 Monitoring: /conversations/truekai" -ForegroundColor Yellow
Write-Host "📱 Send a message in the app now..." -ForegroundColor Green
Write-Host ""
Write-Host "Press Ctrl+C to stop" -ForegroundColor DarkGray
Write-Host ""

# Get initial state
$previousCount = 0
try {
    $initialData = firebase database:get /conversations/truekai --project homecoming-74f73 2>$null | ConvertFrom-Json
    if ($initialData) {
        $previousCount = ($initialData | Get-Member -MemberType NoteProperty).Count
        Write-Host "📊 Current conversations: $previousCount" -ForegroundColor Cyan
    }
} catch {
    Write-Host "⚠️ Could not read initial data" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "⏳ Watching for changes..." -ForegroundColor DarkGray
Write-Host ""

$iteration = 0
while ($true) {
    Start-Sleep -Seconds 3
    $iteration++
    
    try {
        $currentData = firebase database:get /conversations/truekai --project homecoming-74f73 2>$null | ConvertFrom-Json
        
        if ($currentData) {
            $currentCount = ($currentData | Get-Member -MemberType NoteProperty).Count
            
            if ($currentCount -gt $previousCount) {
                Write-Host ""
                Write-Host "✅ NEW CONVERSATION DETECTED!" -ForegroundColor Green
                Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Green
                Write-Host "Previous count: $previousCount" -ForegroundColor Gray
                Write-Host "Current count:  $currentCount" -ForegroundColor Green
                Write-Host "New entries:    $($currentCount - $previousCount)" -ForegroundColor Yellow
                Write-Host ""
                
                # Show latest entry
                $properties = $currentData | Get-Member -MemberType NoteProperty | Select-Object -Last 1
                if ($properties) {
                    $lastKey = $properties.Name
                    $lastEntry = $currentData.$lastKey
                    
                    Write-Host "📝 Latest conversation:" -ForegroundColor Cyan
                    Write-Host "  Key: $lastKey" -ForegroundColor Gray
                    Write-Host "  User: $($lastEntry.userMessage)" -ForegroundColor White
                    Write-Host "  AI: $($lastEntry.aiResponse)" -ForegroundColor White
                    Write-Host "  Time: $(Get-Date -UnixTimeMilliseconds $lastEntry.timestamp)" -ForegroundColor Gray
                }
                
                Write-Host ""
                Write-Host "✅ Firebase IS UPDATING! App is working correctly!" -ForegroundColor Green
                Write-Host ""
                
                $previousCount = $currentCount
            } else {
                Write-Host "⏳ [$iteration] Still waiting... ($currentCount conversations)" -ForegroundColor DarkGray
            }
        }
    } catch {
        Write-Host "⚠️ Error reading Firebase: $_" -ForegroundColor Red
    }
}
