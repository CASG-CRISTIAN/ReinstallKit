# Checks catalog_tweaks.csv: its own rules, that every Id is in scripts\*.json using only what
# apply_tweaks.ps1 knows how to apply, and that apply_tweaks.ps1 -DryRun goes through it (nothing is changed).
# Usage: powershell -ExecutionPolicy Bypass -File tools\check_tweaks.ps1   (exits with 1 on errors)
$root = Split-Path $PSScriptRoot
$lines = [IO.File]::ReadAllLines((Join-Path $root 'catalog_tweaks.csv'), [Text.Encoding]::GetEncoding(1252))
$cols = ($lines[0] -split ';').Count
$errors = 0
function Fail([string]$Text) { $script:errors++; "ERROR  $Text" }

$tweaks = @{}
foreach ($file in Get-ChildItem (Join-Path $root 'scripts') -Filter *.json) {
  (Get-Content $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $tweaks[$_.Name] = $_.Value }
}
$known = 'Content', 'Description', 'category', 'panel', 'Order', 'link', 'Type', 'DefaultState', 'Checked',
  'registry', 'service', 'ScheduledTask', 'InvokeScript', 'UndoScript'
$apply = Join-Path $root 'scripts\apply_tweaks.ps1'
# WinGet installs the Microsoft Store apps through the Store: no tweak may remove or switch off the Store or
# App Installer (WinGet itself), touch their files, disable the services they install with or WinGet's
# msstore source. Checked on what the tweak applies (with Undo=Yes, its original values and UndoScript).
$storeRule = 'Microsoft\.WindowsStore|Microsoft\.DesktopAppInstaller|Microsoft\.StorePurchaseApp|RemoveWindowsStore|' +
  'DisableStoreApps|winget(\.exe)?\s+source\s+(remove|disable|reset)|service (InstallService|AppXSvc|ClipSVC|DoSvc) = Disabled'
function Applied($tweak, [bool]$undo) {
  $value, $startup, $script = if ($undo) { 'OriginalValue', 'OriginalType', 'UndoScript' } else { 'Value', 'StartupType', 'InvokeScript' }
  (@($tweak.registry | ForEach-Object { "$($_.Path)\$($_.Name) = $($_.$value)" }) +
    @($tweak.service | ForEach-Object { "service $($_.Name) = $($_.$startup)" }) + @($tweak.$script)) -join "`n"
}
$seen = @{}; $closed = @{}; $section = ''
for ($i = 1; $i -lt $lines.Count; $i++) {
  if (-not $lines[$i].Trim()) { continue }
  $f = $lines[$i] -split ';'
  $row = "row $($i + 1) ($($f[1]))"
  if ($f.Count -ne $cols) { Fail "$row has $($f.Count) columns instead of $cols"; continue }
  if ($seen.ContainsKey($f[1])) { Fail "$row is repeated" }
  $seen[$f[1]] = $true
  # The rows of a section must be together: once it is left, it cannot appear again
  if ($f[0] -ne $section) {
    if ($closed.ContainsKey($f[0])) { Fail "${row}: section '$($f[0])' appeared before; its rows must be together" }
    if ($section) { $closed[$section] = $true }
    $section = $f[0]
  }
  foreach ($c in 2, 3, 4) { if ($f[$c] -notin 'Yes', 'No', '') { Fail "${row}: column $c must be Yes, No or empty" } }
  foreach ($c in 0, 5, 6, 7, 8, 9, 10, 11, 12) { if (-not $f[$c].Trim()) { Fail "${row}: column $c is empty" } }
  $tweak = $tweaks[$f[1]]
  if (-not $tweak) { Fail "${row}: not in scripts\*.json"; continue }
  $unknown = $tweak.PSObject.Properties.Name | Where-Object { $_ -notin $known }
  if ($unknown) { Fail "${row}: apply_tweaks.ps1 does not apply $($unknown -join ', ')" }
  $store = [regex]::Match((Applied $tweak ($f[2] -eq 'Yes')), $storeRule, 'IgnoreCase')
  if ($store.Success) { Fail "${row}: touches Microsoft Store or WinGet, which install the apps ($($store.Value))" }
  $undo = @(); if ($f[2] -eq 'Yes') { $undo = @('-Undo') }
  $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $apply -Id $f[1] @undo -DryRun
  if ($LASTEXITCODE -ne 0) { Fail "${row}: apply_tweaks.ps1 -DryRun failed: $out" }
  elseif (-not $out) { Fail "${row}: there is nothing to apply$(if ($undo) { ' with -Undo' })" }
}
"$($seen.Count) tweaks"
"$errors errors"
exit [int]($errors -gt 0)
