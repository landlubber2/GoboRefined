<#
.SYNOPSIS
  Manage a weekly Windows Scheduled Task for tools/watch-upstream.js (P1).
.EXAMPLE
  .\tools\install-watch-task.ps1 -Install
  .\tools\install-watch-task.ps1 -Install -Notify -DayOfWeek Monday -Time "09:00"
  .\tools\install-watch-task.ps1 -Status
  .\tools\install-watch-task.ps1 -Uninstall
#>
param(
  [switch]$Install,
  [switch]$Uninstall,
  [switch]$Status,
  [switch]$Notify,
  [ValidateSet('Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday')]
  [string]$DayOfWeek = 'Monday',
  [string]$Time = '09:00'
)

$ErrorActionPreference = 'Stop'
$TaskName = 'GoboRefined-WatchUpstream'
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$ScriptPath = Join-Path $PSScriptRoot 'watch-upstream.js'

if ($Status) {
  $t = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
  if ($t) {
    $info = Get-ScheduledTaskInfo -TaskName $TaskName
    [pscustomobject]@{
      TaskName     = $t.TaskName
      State        = $t.State
      LastRunTime  = $info.LastRunTime
      NextRunTime  = $info.NextRunTime
      LastResult   = $info.LastTaskResult
      Action       = ($t.Actions | ForEach-Object { "$($_.Execute) $($_.Arguments)" }) -join '; '
    } | Format-List
  } else {
    Write-Host "Task '$TaskName' is not installed."
  }
  exit 0
}

if ($Uninstall) {
  if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Write-Host "Removed scheduled task '$TaskName'."
  } else {
    Write-Host "Task '$TaskName' was not installed."
  }
  exit 0
}

if ($Install) {
  $NodeExe = (Get-Command node.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source)
  if (-not $NodeExe -and (Test-Path 'C:\Program Files\nodejs\node.exe')) {
    $NodeExe = 'C:\Program Files\nodejs\node.exe'
  }
  if (-not $NodeExe) { throw 'node.exe not found in PATH or C:\Program Files\nodejs\node.exe' }

  $Args = "`"$ScriptPath`""
  if ($Notify) { $Args += ' --notify' }

  $Action = New-ScheduledTaskAction -Execute $NodeExe -Argument $Args -WorkingDirectory $RepoRoot
  $Trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek $DayOfWeek -At $Time
  $Settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries

  Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Settings $Settings `
    -Description 'Weekly upstream version & CVE watcher for GoboRefined (writes watch/YYYY-MM-DD.md)' -Force | Out-Null
  Write-Host "Installed scheduled task '$TaskName' (every $DayOfWeek at $Time): $NodeExe $Args"
  exit 0
}

Write-Host "Usage: .\tools\install-watch-task.ps1 -Install [-Notify] [-DayOfWeek Monday] [-Time 09:00] | -Status | -Uninstall"
