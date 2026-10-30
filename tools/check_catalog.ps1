# Checks catalog_apps.csv: its own rules and, unless -SkipWinget, that every WinGet / Microsoft Store ID
# of the included apps still exists (read-only "winget show"; it takes a few minutes).
# Usage: powershell -ExecutionPolicy Bypass -File tools\check_catalog.ps1 [-SkipWinget]   (exits with 1 on errors)
param([switch]$SkipWinget)
$csv = Join-Path (Split-Path $PSScriptRoot) 'catalog_apps.csv'
$lines = [IO.File]::ReadAllLines($csv, [Text.Encoding]::GetEncoding(1252))
$cols = ($lines[0] -split ';').Count
$errors = 0
function Fail([string]$Text) { $script:errors++; "ERROR  $Text" }

if ([IO.File]::ReadAllText($csv, [Text.Encoding]::GetEncoding(1252)).Contains('Ã')) {
  Fail 'the file is saved as UTF-8: save it from Excel as "CSV (delimitado por comas)"'
}
$components = @{}; $closed = @{}; $section = ''; $ids = @()
for ($i = 1; $i -lt $lines.Count; $i++) {
  if (-not $lines[$i].Trim()) { continue }
  $f = $lines[$i] -split ';'
  $row = "row $($i + 1)"
  if ($f.Count -ne $cols) { Fail "$row has $($f.Count) columns instead of $cols"; continue }
  $name = $f[2]
  if ($f[1] -notmatch '^[a-z0-9]+\\[a-z0-9]+$') { Fail "$row ($name): Component '$($f[1])' must be group\name, lowercase, no spaces" }
  if ($components.ContainsKey($f[1])) { Fail "$row ($name): Component '$($f[1])' is repeated" }
  $components[$f[1]] = $true
  # The rows of a section must be together: once it is left, it cannot appear again
  if ($f[0] -ne $section) {
    if ($closed.ContainsKey($f[0])) { Fail "$row ($name): section '$($f[0])' appeared before; its rows must be together" }
    if ($section) { $closed[$section] = $true }
    $section = $f[0]
  }
  if ($f[5] -and $f[5] -notin 'winget', 'msstore') { Fail "$row ($name): Source must be winget or msstore" }
  if ($f[6] -notin 'Yes', 'No', 'Si', 'Sí', '') { Fail "$row ($name): Included must be Yes or No" }
  if ($f[7] -notin 'Yes', 'No', 'Si', 'Sí', '') { Fail "$row ($name): AsUser must be Yes or empty" }
  foreach ($p in ($f[19] -split ' ' | Where-Object { $_ })) {
    if ($p -notin 'basic', 'gaming', 'office', 'dev') { Fail "$row ($name): unknown profile '$p'" }
  }
  if ($f[6] -in 'Yes', 'Si', 'Sí') {
    if (-not $f[4]) { Fail "$row ($name): an included app needs a WingetID" }
    foreach ($id in $f[4], $f[13], $f[18] | Where-Object { $_ } | Sort-Object -Unique) {
      $ids += [pscustomobject]@{ Row = $row; Name = $name; ID = $id; Source = $(if ($f[5]) { $f[5] } else { 'winget' }) }
    }
    # OtherIDs: a Store ID has no dots (9N..., XP...)
    foreach ($id in ($f[20] -split ' ' | Where-Object { $_ })) {
      $ids += [pscustomobject]@{ Row = $row; Name = $name; ID = $id; Source = $(if ($id.Contains('.')) { 'winget' } else { 'msstore' }) }
    }
  }
}
"$($components.Count) apps, $($ids.Count) IDs to check"

if (-not $SkipWinget) {
  foreach ($x in $ids) {
    winget show --id $x.ID -e --source $x.Source --accept-source-agreements --disable-interactivity *> $null
    if ($LASTEXITCODE -ne 0) { Fail "$($x.Row) ($($x.Name)): '$($x.ID)' not found in $($x.Source) (winget code $LASTEXITCODE)" }
  }
}
"$errors errors"
exit [int]($errors -gt 0)
