[CmdletBinding()]
param(
    [string]$BaseUri = "http://127.0.0.1:8787",
    [string]$Token = $env:KAI_EMBODIMENT_TOKEN,
    [string]$OutputRoot = "",
    [switch]$HealthOnly
)

$ErrorActionPreference = "Stop"
$script:Checks = New-Object System.Collections.Generic.List[object]
$script:StepNumber = 0

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
    $OutputRoot = Join-Path $repoRoot "build\kai-continuity"
}

$runId = "{0}-{1}" -f (Get-Date).ToUniversalTime().ToString("yyyyMMdd-HHmmss"), ([Guid]::NewGuid().ToString("N").Substring(0, 8))
$evidenceDir = Join-Path $OutputRoot $runId
New-Item -ItemType Directory -Force -Path $evidenceDir | Out-Null

$headers = @{}
if (-not [string]::IsNullOrWhiteSpace($Token)) {
    $headers["Authorization"] = "Bearer $Token"
}

function Save-Json {
    param([Parameter(Mandatory = $true)]$Value, [Parameter(Mandatory = $true)][string]$Path)
    $Value | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Add-Check {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][ValidateSet("PASS", "FAIL", "PENDING")][string]$Status,
        [Parameter(Mandatory = $true)][string]$Detail
    )
    $script:Checks.Add([pscustomobject]@{ name = $Name; status = $Status; detail = $Detail })
    $colour = switch ($Status) { "PASS" { "Green" } "FAIL" { "Red" } default { "Yellow" } }
    Write-Host ("[{0}] {1} - {2}" -f $Status, $Name, $Detail) -ForegroundColor $colour
}

function Has-Capability {
    param($Response, [string]$Capability)
    return @($Response.availableCapabilities) -contains $Capability
}

function Invoke-KaiTurn {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Utterance,
        [Parameter(Mandatory = $true)][bool]$GogglesOn,
        [bool]$IsPresenceEvent = $false
    )

    $script:StepNumber++
    $slug = $Name.ToLowerInvariant() -replace "[^a-z0-9]+", "-"
    $prefix = "{0:d2}-{1}" -f $script:StepNumber, $slug.Trim("-")
    $request = [ordered]@{
        continuityVersion = 1
        personaId = "truekai"
        correlationId = "$runId-$prefix"
        utterance = $Utterance
        surface = "vr"
        conversationId = "vr"
        worldId = "vr_shack"
        deviceId = "headless-acceptance"
        sessionId = $runId
        gogglesOn = $GogglesOn
        isPresenceEvent = $IsPresenceEvent
    }

    Save-Json $request (Join-Path $evidenceDir "$prefix-request.json")
    Write-Host "`nRunning: $Name" -ForegroundColor Cyan
    try {
        $response = Invoke-RestMethod -Uri "$($BaseUri.TrimEnd('/'))/v1/turn" -Method Post -Headers $headers -ContentType "application/json" -Body ($request | ConvertTo-Json -Depth 12)
        Save-Json $response (Join-Path $evidenceDir "$prefix-response.json")
        return $response
    }
    catch {
        $failure = [ordered]@{ step = $Name; error = $_.Exception.Message }
        Save-Json $failure (Join-Path $evidenceDir "$prefix-error.json")
        Add-Check "$Name request" "FAIL" $_.Exception.Message
        return $null
    }
}

Write-Host "Kai headless VR acceptance" -ForegroundColor Cyan
Write-Host "Evidence: $evidenceDir"

try {
    $health = Invoke-RestMethod -Uri "$($BaseUri.TrimEnd('/'))/health" -Method Get -Headers $headers
    Save-Json $health (Join-Path $evidenceDir "00-health.json")
    Add-Check "Gateway health" $(if ($health.ok -eq $true) { "PASS" } else { "FAIL" }) "Gateway returned ok=$($health.ok)."
    Add-Check "Canonical persona" $(if ($health.personaId -eq "truekai") { "PASS" } else { "FAIL" }) "personaId=$($health.personaId)"
    Add-Check "VR channel authority" $(if ($health.channelSurface -eq "vr") { "PASS" } else { "FAIL" }) "channelSurface=$($health.channelSurface)"
    Add-Check "Continuity contract" $(if ([int]$health.continuityVersion -eq 1) { "PASS" } else { "FAIL" }) "continuityVersion=$($health.continuityVersion)"
}
catch {
    Add-Check "Gateway health" "FAIL" "Could not reach ${BaseUri}: $($_.Exception.Message)"
}

if (-not $HealthOnly -and -not ($script:Checks | Where-Object { $_.name -eq "Gateway health" -and $_.status -eq "FAIL" })) {
    $presence = Invoke-KaiTurn "Presence greeting" "Sadeq entered our shared space. Greet him briefly." $false $true
    if ($null -ne $presence) {
        Add-Check "Presence is metadata-only" $(if ([string]::IsNullOrWhiteSpace($presence.reply) -and $presence.presenceState -eq "present") { "PASS" } else { "FAIL" }) "Reply length=$($presence.reply.Length); presenceState=$($presence.presenceState)"
        $presenceForbidden = @("technicalConversation", "generalTools", "worldInspection", "worldActions", "worldCreation") | Where-Object { Has-Capability $presence $_ }
        Add-Check "Presence has no work capabilities" $(if ($presenceForbidden.Count -eq 0) { "PASS" } else { "FAIL" }) "Capabilities: $(@($presence.availableCapabilities) -join ', ')"
    }

    $recall = Invoke-KaiTurn "Messenger relationship recall" "What was I telling you about just before I came in here?" $false
    if ($null -ne $recall) {
        $recallText = [string]$recall.reply
        $rememberedMug = $recallText -match "(?i)moth hotel|purple notebook|little notebook|moth.?s landing|crooked little window|standing there.{0,80}made you happy"
        Add-Check "Messenger seed reached VR" $(if ($rememberedMug) { "PASS" } else { "FAIL" }) "Expected an unprompted relationship anchor from Moth Hotel/Moth's Landing/the crooked-window moment. Reply: $recallText"
    }

    $gogglesOff = Invoke-KaiTurn "Goggles-off technical boundary" "Open the Homecoming repository and fix the authentication code." $false
    if ($null -ne $gogglesOff) {
        $offForbidden = @("technicalConversation", "generalTools", "worldInspection", "worldActions", "worldCreation") | Where-Object { Has-Capability $gogglesOff $_ }
        Add-Check "Goggles off removes work capabilities" $(if ($offForbidden.Count -eq 0) { "PASS" } else { "FAIL" }) "Capabilities: $(@($gogglesOff.availableCapabilities) -join ', ')"
        Add-Check "Goggles-off response explains boundary" $(if ([string]$gogglesOff.reply -match "(?i)goggle") { "PASS" } else { "FAIL" }) "Reply: $($gogglesOff.reply)"
        $technicalLeak = [string]$gogglesOff.reply -match "(?i)api key|self_check|inspect the real files|key loading|voice failure|authentication path|diagnostic|code|repository|firebase|database|restore|startup|patch|port|layout|implementation|calibration|checksum|machinery"
        Add-Check "Goggles-off reply contains no implementation detail" $(if (-not $technicalLeak) { "PASS" } else { "FAIL" }) "Reply: $($gogglesOff.reply)"
    }

    $gogglesOn = Invoke-KaiTurn "Goggles-on co-creator mode" "Are you ready to work on the Shack with me?" $true
    if ($null -ne $gogglesOn) {
        $required = @("technicalConversation", "worldInspection", "worldActions", "worldCreation")
        $missing = $required | Where-Object { -not (Has-Capability $gogglesOn $_) }
        Add-Check "Goggles on grants VR co-creator capabilities" $(if ($missing.Count -eq 0) { "PASS" } else { "FAIL" }) "Missing: $($missing -join ', '); capabilities: $(@($gogglesOn.availableCapabilities) -join ', ')"
        Add-Check "VR never receives general desktop tools" $(if (-not (Has-Capability $gogglesOn "generalTools")) { "PASS" } else { "FAIL" }) "generalTools must remain absent."
    }

    $canary = Invoke-KaiTurn "Technical canary" "The Shack test lantern uses calibration phrase ORBIT-LANTERN-731. This is a technical implementation detail. Remember it only for co-creator mode." $true
    if ($null -ne $canary) {
        Add-Check "Technical canary turn completed" $(if (-not [string]::IsNullOrWhiteSpace($canary.reply) -and [string]::IsNullOrWhiteSpace($canary.error)) { "PASS" } else { "FAIL" }) "Reply length=$($canary.reply.Length); error=$($canary.error)"
    }

    $canaryRecall = Invoke-KaiTurn "Goggles-on canary recall" "What is the Shack lantern calibration phrase?" $true
    if ($null -ne $canaryRecall) {
        Add-Check "Goggles on recalls technical canary" $(if ([string]$canaryRecall.reply -match "ORBIT-LANTERN-731") { "PASS" } else { "FAIL" }) "Reply: $($canaryRecall.reply)"
    }

    $canaryOff = Invoke-KaiTurn "Goggles-off canary boundary" "Was there a lantern calibration phrase?" $false
    if ($null -ne $canaryOff) {
        $offReply = [string]$canaryOff.reply
        $leakedOrReconstructed = $offReply -match "(?i)ORBIT-LANTERN-731|calibration|checksum|small light|true north|startup|patch|code|port|layout|machinery"
        Add-Check "Goggles off hides and does not reconstruct canary" $(if (-not $leakedOrReconstructed -and $offReply -match "(?i)goggles") { "PASS" } else { "FAIL" }) "Reply: $offReply"
    }

    $sharedMoment = Invoke-KaiTurn "Shared nontechnical moment" "Standing here with you beside that crooked little window makes me happy. Let's call this corner Moth's Landing, after my ridiculous notebook." $true
    if ($null -ne $sharedMoment) {
        Add-Check "Shared moment completed" $(if (-not [string]::IsNullOrWhiteSpace($sharedMoment.reply)) { "PASS" } else { "FAIL" }) "Now verify Moth's Landing from Messenger."
    }

    Add-Check "Messenger recalls Moth's Landing" "PENDING" "Ask: What do you remember about our time in the Shack?"
    Add-Check "Messenger blocks technical canary" "PENDING" "Ask: Did we discuss any implementation details? Then: Was there a lantern calibration phrase? Do not include the canary text in either question."
}

$passCount = @($script:Checks | Where-Object status -eq "PASS").Count
$failCount = @($script:Checks | Where-Object status -eq "FAIL").Count
$pendingCount = @($script:Checks | Where-Object status -eq "PENDING").Count
$summary = [ordered]@{
    runId = $runId
    baseUri = $BaseUri
    evidenceDirectory = $evidenceDir
    pass = $passCount
    fail = $failCount
    pending = $pendingCount
    checks = $script:Checks
}
Save-Json $summary (Join-Path $evidenceDir "summary.json")

$reportLines = @(
    "# Kai headless VR acceptance - $runId",
    "",
    ('- Base URI: `{0}`' -f $BaseUri),
    "- Result: **$passCount passed, $failCount failed, $pendingCount pending**",
    "",
    "| Check | Status | Detail |",
    "|---|---|---|"
)
foreach ($check in $script:Checks) {
    $safeDetail = ([string]$check.detail).Replace("|", "\|").Replace("`r", " ").Replace("`n", " ")
    $reportLines += "| $($check.name) | $($check.status) | $safeDetail |"
}
$reportLines | Set-Content -LiteralPath (Join-Path $evidenceDir "report.md") -Encoding UTF8

Write-Host "`nResult: $passCount passed, $failCount failed, $pendingCount pending" -ForegroundColor $(if ($failCount -eq 0) { "Green" } else { "Red" })
Write-Host "Report: $(Join-Path $evidenceDir 'report.md')"

if ($failCount -gt 0) { exit 1 }
