<#
.SYNOPSIS
  Host → VM clipboard bridge for VirtualBox NAT guests.

.DESCRIPTION
  Serves this folder over HTTP (Python). From the GoboLinux VM browser open:
    http://10.0.2.2:8765/

  Edit payload.txt on the host (or use -WatchHostClipboard), Reload in the guest,
  Copy all, then paste in the guest terminal with Ctrl+Shift+V.
#>

param(
  [int]$Port = 8765,
  [switch]$WatchHostClipboard,
  [int]$ClipboardPollMs = 2000
)

$ErrorActionPreference = "Stop"
$Root = $PSScriptRoot
$Payload = Join-Path $Root "payload.txt"
$HostUrl = "http://127.0.0.1:$Port/"
$GuestUrl = "http://10.0.2.2:$Port/"

if (-not (Test-Path $Payload)) {
  Set-Content -Path $Payload -Value "Paste or edit text here on the host, then Reload in the VM browser." -Encoding UTF8
}

$python = Get-Command python -ErrorAction SilentlyContinue
if (-not $python) {
  throw "Python not found on PATH. Install Python or add it to PATH."
}

$clipJob = $null
if ($WatchHostClipboard) {
  Add-Type -AssemblyName System.Windows.Forms | Out-Null
  $clipJob = Start-Job -ArgumentList $Payload, $ClipboardPollMs -ScriptBlock {
    param($path, $poll)
    Add-Type -AssemblyName System.Windows.Forms | Out-Null
    $prev = $null
    while ($true) {
      try {
        if ([System.Windows.Forms.Clipboard]::ContainsText()) {
          $text = [System.Windows.Forms.Clipboard]::GetText()
          if ($text -and $text -ne $prev) {
            [System.IO.File]::WriteAllText($path, $text)
            $prev = $text
          }
        }
      } catch {}
      Start-Sleep -Milliseconds $poll
    }
  }
}

Write-Host ""
Write-Host "Clipboard bridge running."
Write-Host "  On this PC:     $HostUrl"
Write-Host "  In the VM:      $GuestUrl"
Write-Host "  Payload file:   $Payload"
if ($WatchHostClipboard) {
  Write-Host "  Watching Windows clipboard → payload.txt"
} else {
  Write-Host "  Tip: edit payload.txt, or re-run with -WatchHostClipboard"
}
Write-Host "  In guest terminal paste with: Ctrl+Shift+V"
Write-Host "  Ctrl+C to stop."
Write-Host ""

Start-Process $HostUrl | Out-Null

Push-Location $Root
try {
  & python -m http.server $Port --bind 0.0.0.0
} finally {
  Pop-Location
  if ($clipJob) {
    Stop-Job $clipJob -Force -ErrorAction SilentlyContinue
    Remove-Job $clipJob -Force -ErrorAction SilentlyContinue
  }
}
