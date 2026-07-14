# run.ps1 — filtered flutter run
# Shows only Kai app logs, filters all Android system noise.
# Usage:  .\run.ps1
#         .\run.ps1 --release
#         .\run.ps1 -d <device-id>

$args_passthrough = $args

# Tags from OUR code — matched as [IDVWEF]/Tag( to avoid substring collisions
# e.g. 'MainActivity' must NOT match 'VRI[MainActivity]' or 'BLASTBufferQueue...MainActivity'
$keepTags = @(
    'flutter',
    'KaiToolsPlugin',
    'OverlayService',
    'FlameNativeView',
    'KaiMicStream',
    'KaiNotification',
    'KaiAccessibility',
    'KaiProactiveWorker',
    'SherpaOnnx',
    'NativeAudioRecord',
    'MainActivity'
)

# Match tag only at the log-level prefix position: [IDVWEF]/TagName(
# This prevents 'MainActivity' matching inside 'VRI[MainActivity]@...'
$keepPattern = '^\s*[IDVWEF]/(' + (($keepTags | ForEach-Object { [regex]::Escape($_) }) -join '|') + ')\b'

& flutter run @args_passthrough 2>&1 | ForEach-Object {
    $line = $_

    # Always keep flutter CLI lines (no log-level prefix like I/ D/ E/)
    if ($line -notmatch '^\s*[VDIWEF]/') {
        Write-Host $line
        return
    }

    # Always keep errors and warnings — drop only known-harmless GPU/system noise
    if ($line -match '^\s*[EW]/') {
        if ($line -match 'gralloc4|Gralloc4|AHardwareBuffer|GraphicBufferAllocator|EGL_emulation') {
            return
        }
        Write-Host $line -ForegroundColor $(if ($line -match '^\s*E/') { 'Red' } else { 'Yellow' })
        return
    }

    # For I/ and D/ lines, only keep lines whose TAG is one of ours
    if ($line -match $keepPattern) {
        Write-Host $line
        return
    }

    # Drop everything else
}
