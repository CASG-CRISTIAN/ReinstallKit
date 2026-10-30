# Puts the signed-in user's Documents, Downloads, Pictures, Videos and Music in <Drive>\<user name>, like
# "Location > Move" in each folder's Properties, but without moving what they already hold (right after
# formatting they are empty; the installer and the backup may be in Downloads). Folders that already exist
# there, from before formatting, are used as they are, files included. A new <Drive>\<user name> is
# private to the user, as their profile folder is. It shows after signing in again or restarting; each
# folder's Properties > Location > "Restore Default" undoes it. Setup runs it elevated, once.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File move_user_folders.ps1 -Drive D: [-DryRun]
# Exit code: 1 if a folder could not be changed.
param([Parameter(Mandatory)][string]$Drive, [switch]$DryRun)
[Console]::OutputEncoding = [Text.Encoding]::UTF8   # what Setup reads

# Setup is elevated: if the elevation used another account, HKCU is that account's. The folders are for
# whoever is signed in to this session, the owner of its Explorer (as in apply_tweaks.ps1).
$sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
try {
  $explorer = Get-CimInstance Win32_Process -ErrorAction Stop -Filter "Name = 'explorer.exe' AND SessionId = $((Get-Process -Id $PID).SessionId)" |
    Select-Object -First 1
  $owner = (Invoke-CimMethod -InputObject $explorer -MethodName GetOwnerSid -ErrorAction Stop).Sid
  if ($owner) { $sid = $owner }
} catch { }
$profileDir = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$sid").ProfileImagePath
$target = Join-Path "$($Drive.TrimEnd('\'))\" (Split-Path $profileDir -Leaf)
$shellFolders = "Registry::HKEY_USERS\$sid\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders"
$userShellFolders = "Registry::HKEY_USERS\$sid\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders"
"Folder: $target"

# Each folder's name there and its registry names: the classic one and the one newer Windows also reads
$folders = [ordered]@{
  Documents = 'Personal', '{F42EE2D3-909F-4907-8871-4C22FC0BF756}'
  Downloads = '{374DE290-123F-4565-9164-39C4925E467B}', '{7D83EE9B-2244-4E70-B1F5-5393042AF1E4}'
  Pictures  = 'My Pictures', '{0DDD015D-B06C-45D5-8C4C-F59713854639}'
  Videos    = 'My Video', '{35286A68-3C57-41A1-BBB1-0EAE73D76C95}'
  Music     = 'My Music', '{A0C69A99-21C8-4671-8703-7934162FCF1D}'
}

if (Test-Path $target) { "  It already exists: it is used as it is." }
elseif (-not $DryRun) {
  # Only the user, SYSTEM and the administrators, like C:\Users\<user> (a drive's root lets every user in)
  New-Item -ItemType Directory $target -ErrorAction Stop | Out-Null
  icacls $target /inheritance:r /grant:r "*${sid}:(OI)(CI)F" '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' | Out-Null
  icacls $target /setowner "*$sid" | Out-Null
}

$failed = 0
foreach ($name in $folders.Keys) {
  $new = Join-Path $target $name
  $old = [Environment]::ExpandEnvironmentVariables((Get-ItemProperty $userShellFolders -ErrorAction SilentlyContinue).($folders[$name][0]))
  if ($old -eq $new) { "$name`: already in $new"; continue }
  "$name`: $old -> $new"
  if ($DryRun) { continue }
  try {
    if (-not (Test-Path $new)) { New-Item -ItemType Directory $new -ErrorAction Stop | Out-Null }
    # Its desktop.ini gives it the name in the language of Windows ("Documentos"), as Explorer does
    $ini = Join-Path $old 'desktop.ini'
    if ((Test-Path -LiteralPath $ini) -and -not (Test-Path -LiteralPath (Join-Path $new 'desktop.ini'))) {
      Copy-Item -LiteralPath $ini $new -Force -ErrorAction Stop
      (Get-Item -LiteralPath (Join-Path $new 'desktop.ini') -Force).Attributes = 'Hidden, System, Archive'
      (Get-Item -LiteralPath $new -Force).Attributes = 'Directory, ReadOnly'
    }
    foreach ($value in $folders[$name]) {
      Set-ItemProperty $userShellFolders -Name $value -Value $new -Type ExpandString -ErrorAction Stop
    }
    Set-ItemProperty $shellFolders -Name $folders[$name][0] -Value $new -ErrorAction SilentlyContinue
    $left = @(Get-ChildItem -LiteralPath $old -Force -ErrorAction SilentlyContinue | Where-Object Name -ne 'desktop.ini').Count
    if ($left) { "  $left items stay in ${old}: move them by hand if you want them there." }
  } catch { $failed++; "  ! $($_.Exception.Message)" }
}
"It shows after signing in again or restarting."
if ($failed) { exit 1 }
