# Checks that every text the code uses exists in every language, with the same placeholders (%1, %2...).
# Usage: powershell -ExecutionPolicy Bypass -File lang\check_languages.ps1   (exits with 1 if something is wrong)
$root = Split-Path $PSScriptRoot
$langs = @{}
foreach ($f in Get-ChildItem $PSScriptRoot -Filter *.isl) {
  $keys = @{}; $inCustom = $false
  foreach ($line in [IO.File]::ReadAllLines($f.FullName, [Text.Encoding]::UTF8)) {
    if ($line -match '^\[(.+)\]') { $inCustom = $Matches[1] -eq 'CustomMessages'; continue }
    if ($inCustom -and $line -match '^([A-Za-z0-9_]+)=(.*)$') { $keys[$Matches[1]] = $Matches[2] }
  }
  $langs[$f.Name] = $keys
}
$code = (Get-ChildItem $root -Recurse -Filter *.iss | ForEach-Object { [IO.File]::ReadAllText($_.FullName) }) -join "`n"
# Keys appear as CustomMessage('X'), Msg('X', ...), {cm:X} or as the key argument of a few helpers
$pattern = "(?:CustomMessage|Msg|HeaderLabel|ShowStepStatus)\('([A-Za-z0-9_]+)'" +
  "|\{cm:([A-Za-z0-9_]+)\}|Recommend\('[^']*', '([A-Za-z0-9_]+)'\)|FinishStep\([^,]+,[^,]+, '([A-Za-z0-9_]+)'"
$used = [regex]::Matches($code, $pattern) |
  ForEach-Object { ($_.Groups[1..4] | Where-Object Success | Select-Object -First 1).Value } | Sort-Object -Unique
$errors = 0
foreach ($k in $used) {
  foreach ($l in $langs.Keys) { if (-not $langs[$l].ContainsKey($k)) { "Missing $k in $l"; $errors++ } }
}
$all = $langs.Values | ForEach-Object { $_.Keys } | Sort-Object -Unique
foreach ($k in $all) {
  $holes = $langs.Keys | ForEach-Object { if ($langs[$_].ContainsKey($k)) { (([regex]::Matches($langs[$_][$k], '%[1-9]') | ForEach-Object Value | Sort-Object -Unique) -join ',') } }
  if (($holes | Sort-Object -Unique).Count -gt 1) { "Different placeholders in $k : $($holes -join ' / ')"; $errors++ }
  if ($used -notcontains $k) { "Unused: $k" }
}
"$($used.Count) texts used, $($langs.Count) languages, $errors errors"
exit [int]($errors -gt 0)
