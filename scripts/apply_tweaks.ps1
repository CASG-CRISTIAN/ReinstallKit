# Applies one Windows tweak written in WinUtil's format: registry values, services, scheduled tasks and
# scripts. winutil_tweaks.json is WinUtil's own file (github.com/ChrisTitusTech/winutil, MIT license, see
# LICENSE-winutil.txt) and custom_tweaks.json holds ours, in the same format; their scripts can use
# $SetupFolder, the folder of this script. -Undo applies the original values and UndoScript instead: it is
# how WinUtil turns a toggle off. -DryRun only lists the changes. Setup runs it elevated, once per tweak.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File apply_tweaks.ps1 -Id WPFTweaksTelemetry [-Undo] [-DryRun]
# Exit code: 1 if any change failed.
param([Parameter(Mandatory)][string]$Id, [switch]$Undo, [switch]$DryRun)
[Console]::OutputEncoding = [Text.Encoding]::UTF8   # what Setup reads
$SetupFolder = $PSScriptRoot

$tweak = $null
foreach ($file in Get-ChildItem $SetupFolder -Filter *.json) {
  $all = Get-Content $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
  if ($all.$Id) { $tweak = $all.$Id }
}
if (-not $tweak) { "Unknown tweak: $Id"; exit 1 }
if ($Undo) { $value, $state, $startup, $scriptKey = 'OriginalValue', 'OriginalState', 'OriginalType', 'UndoScript' }
else { $value, $state, $startup, $scriptKey = 'Value', 'State', 'StartupType', 'InvokeScript' }

# Setup is elevated: if the elevation used another account, HKCU is that account's. The settings are for
# whoever is signed in to this session, the owner of its Explorer (if WMI cannot tell, HKCU it is).
$userHive = 'HKCU:'
try {
  $explorer = Get-CimInstance Win32_Process -ErrorAction Stop -Filter "Name = 'explorer.exe' AND SessionId = $((Get-Process -Id $PID).SessionId)" |
    Select-Object -First 1
  $sid = (Invoke-CimMethod -InputObject $explorer -MethodName GetOwnerSid -ErrorAction Stop).Sid
  if ($sid -and $sid -ne [Security.Principal.WindowsIdentity]::GetCurrent().User.Value) { $userHive = "Registry::HKEY_USERS\$sid" }
} catch { }
function UserPath([string]$Path) { $Path -replace '^HKCU:', $userHive -replace '^HKU:', 'Registry::HKEY_USERS' }

# WinUtil functions some of its scripts call: they refresh or restart Explorer and recolor WinUtil's own
# window. Not needed here: the changes show after restarting, which Setup offers at the end.
function Invoke-WinUtilExplorerUpdate { param($action) }
function Invoke-WinutilThemeChange { param($theme) }
$sync = @{ ThemeButton = @{ Content = $null } }

# Each change is listed and, unless -DryRun, made; a failed one is counted and the rest still run
$failed = 0
function Change([string]$What, [scriptblock]$Do) {
  "  $What"
  if ($DryRun) { return }
  try { & $Do } catch { $script:failed++; "    ! $($_.Exception.Message)" }
}

foreach ($r in $tweak.registry) {
  $path = UserPath $r.Path
  $v = $r.$value
  if ($v -eq '<RemoveEntry>') {
    Change "Remove $($r.Path)\$($r.Name)" { Remove-ItemProperty -Path $path -Name $r.Name -ErrorAction SilentlyContinue }
  } else {
    Change "$($r.Path)\$($r.Name) = $v" {
      if (-not (Test-Path $path)) { New-Item -Path $path -Force -ErrorAction Stop | Out-Null }
      Set-ItemProperty -Path $path -Name $r.Name -Type $r.Type -Value $v -Force -ErrorAction Stop
    }
  }
}

# Like WinUtil, a service whose startup someone already changed is left as it is
foreach ($s in $tweak.service) {
  Change "Service $($s.Name): $($s.$startup)" {
    $service = Get-Service -Name $s.Name -ErrorAction SilentlyContinue
    if (-not $service) { '    (not on this PC)' }
    elseif (-not $Undo -and $service.StartType.ToString() -ne $s.OriginalType) { "    (left as $($service.StartType))" }
    elseif ($s.$startup -eq 'AutomaticDelayedStart') {
      sc.exe config $s.Name start= delayed-auto | Out-Null
      if ($LASTEXITCODE) { throw "sc.exe exit code $LASTEXITCODE" }
    }
    else { Set-Service -Name $s.Name -StartupType $s.$startup -ErrorAction Stop }
  }
}

foreach ($k in $tweak.ScheduledTask) {
  Change "Task $($k.Name): $($k.$state)" {
    schtasks.exe /Change /TN $k.Name $(if ($k.$state -eq 'Enabled') { '/Enable' } else { '/Disable' }) | Out-Null
    if ($LASTEXITCODE) { throw "schtasks exit code $LASTEXITCODE" }
  }
}

# Their errors are shown on one line each; one that stops the script, or a last program that ends with an
# error code, counts as a failure
foreach ($code in $tweak.$scriptKey) {
  $first = $code -split "`n" | ForEach-Object Trim | Where-Object { $_ -and -not $_.StartsWith('#') } | Select-Object -First 1
  Change "Script: $first" {
    $global:LASTEXITCODE = 0
    & ([scriptblock]::Create(($code -replace 'HKCU:', $userHive))) 2>&1 |
      ForEach-Object { if ($_ -is [Management.Automation.ErrorRecord]) { "    ! $($_.Exception.Message)" } else { "    $_" } }
    if ($LASTEXITCODE) { throw "exit code $LASTEXITCODE" }
  }
}
if ($failed) { exit 1 }
