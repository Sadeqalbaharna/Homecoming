# ─────────────────────────────────────────────────────────────────────────
#  Serve the console to your phone over the local WiFi.
#
#  The first version of this failed on exactly two things, both of which are
#  the normal state of a developer's laptop rather than anything unusual:
#
#    1. It took the FIRST private IP address it found. On a machine with WSL,
#       Hyper-V, Docker or a VPN, that is a virtual adapter that no phone can
#       reach. The URL looked perfectly reasonable and pointed nowhere.
#    2. Windows Firewall blocks inbound connections to a new listening port by
#       default, so even the right address times out.
#
#  So this one names every adapter, ranks the real WiFi first, opens the port
#  if it can, and tells you how to prove which half is broken.
# ─────────────────────────────────────────────────────────────────────────

$ErrorActionPreference = 'Stop'
$port = 8777
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

$file = 'tavern_console_blank.html'
if (-not (Test-Path (Join-Path $root $file))) {
  Write-Host "  Cannot find $file next to this script." -ForegroundColor Red
  Read-Host "  Press Enter to close"; exit 1
}

Write-Host ""
Write-Host "  Tavern console - phone test server" -ForegroundColor Cyan
Write-Host "  =================================="
Write-Host ""

# ── Am I elevated? Only an admin can open the firewall. ──
$admin = ([Security.Principal.WindowsPrincipal] `
  [Security.Principal.WindowsIdentity]::GetCurrent()
 ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if ($admin) {
  $ruleName = "Tavern console phone test ($port)"
  if (-not (Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -Action Allow `
      -Protocol TCP -LocalPort $port -Profile Private | Out-Null
    Write-Host "  Firewall opened on port $port for Private networks." -ForegroundColor Green
  } else {
    Write-Host "  Firewall rule already in place." -ForegroundColor Green
  }
} else {
  Write-Host "  NOT running as administrator, so the firewall was not opened." -ForegroundColor Yellow
  Write-Host "  If the phone times out, close this and right-click ->" -ForegroundColor Yellow
  Write-Host "  'Run as administrator'." -ForegroundColor Yellow
}
Write-Host ""

# ── Every usable address, real adapters first. ──
$virtual = 'WSL|Hyper-V|vEthernet|VirtualBox|VMware|Loopback|Bluetooth|Docker|TAP|Tailscale'
$addrs = Get-NetIPAddress -AddressFamily IPv4 |
  Where-Object { $_.IPAddress -ne '127.0.0.1' -and $_.InterfaceAlias -notmatch $virtual } |
  ForEach-Object {
    $up = (Get-NetAdapter -Name $_.InterfaceAlias -ErrorAction SilentlyContinue).Status -eq 'Up'
    [pscustomobject]@{
      IP    = $_.IPAddress
      Alias = $_.InterfaceAlias
      Up    = $up
      Rank  = $(if ($_.InterfaceAlias -match 'Wi-?Fi|Wireless|WLAN') { 0 }
                elseif ($_.InterfaceAlias -match 'Ethernet') { 1 } else { 2 })
    }
  } | Where-Object { $_.Up } | Sort-Object Rank

if (-not $addrs) {
  Write-Host "  No active network adapter found. Is WiFi on?" -ForegroundColor Red
  Read-Host "  Press Enter to close"; exit 1
}

Write-Host "  On your phone, open this:" -ForegroundColor Cyan
Write-Host ""
$first = $true
foreach ($a in $addrs) {
  $url = "http://$($a.IP):$port/$file"
  if ($first) {
    Write-Host "      $url" -ForegroundColor Green
    Write-Host "      (adapter: $($a.Alias))"
    $first = $false
  } else {
    Write-Host "      ...or, if that one times out: $url" -ForegroundColor DarkGray
    Write-Host "         (adapter: $($a.Alias))" -ForegroundColor DarkGray
  }
}
Write-Host ""
Write-Host "  FIRST, prove the server works: open this on THIS laptop -"
Write-Host "      http://localhost:$port/$file"
Write-Host "  If that loads but the phone does not, it is the network or the"
Write-Host "  firewall, not the console."
Write-Host ""
Write-Host "  The phone must be on the same WiFi. Guest networks and some"
Write-Host "  routers block devices from seeing each other - if nothing works,"
Write-Host "  turn on your phone's hotspot and connect the LAPTOP to it, then"
Write-Host "  run this again."
Write-Host ""
Write-Host "  Ctrl+C to stop." -ForegroundColor DarkGray
Write-Host ""

# ── Serve. Prefer Python, fall back to a tiny .NET listener. ──
$py = Get-Command python -ErrorAction SilentlyContinue
if (-not $py) { $py = Get-Command py -ErrorAction SilentlyContinue }
# The Microsoft Store stub is a zero-byte shim that opens the Store.
if ($py -and (Get-Item $py.Source).Length -lt 1024) { $py = $null }

if ($py) {
  & $py.Source -m http.server $port --bind 0.0.0.0
  exit
}

Write-Host "  Python not found - using the built-in server instead." -ForegroundColor DarkGray
$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add("http://+:$port/")
try { $listener.Start() }
catch {
  Write-Host ""
  Write-Host "  Could not listen on port $port. This usually means the script" -ForegroundColor Red
  Write-Host "  is not running as administrator. Right-click -> Run as administrator." -ForegroundColor Red
  Read-Host "  Press Enter to close"; exit 1
}
Write-Host "  Serving." -ForegroundColor Green
$types = @{ '.html'='text/html; charset=utf-8'; '.js'='text/javascript'; '.css'='text/css'
            '.json'='application/json'; '.png'='image/png'; '.pdf'='application/pdf' }
while ($listener.IsListening) {
  $ctx = $listener.GetContext()
  $rel = [Uri]::UnescapeDataString($ctx.Request.Url.AbsolutePath.TrimStart('/'))
  if ([string]::IsNullOrWhiteSpace($rel)) { $rel = $file }
  $path = Join-Path $root $rel
  # Never serve outside this folder.
  if ((-not $path.StartsWith($root)) -or (-not (Test-Path $path -PathType Leaf))) {
    $ctx.Response.StatusCode = 404; $ctx.Response.Close(); continue
  }
  $bytes = [IO.File]::ReadAllBytes($path)
  $ext = [IO.Path]::GetExtension($path).ToLower()
  $ctx.Response.ContentType = $(if ($types[$ext]) { $types[$ext] } else { 'application/octet-stream' })
  $ctx.Response.ContentLength64 = $bytes.Length
  $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
  $ctx.Response.Close()
  Write-Host "  -> $rel" -ForegroundColor DarkGray
}
