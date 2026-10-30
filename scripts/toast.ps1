# Shows a Windows notification in the installer's name, so what failed stays listed in the Notification
# Center even if nobody was watching. A program not installed from the Store needs its AppUserModelId
# registered under HKCU\Software\Classes\AppUserModelId: the DisplayName there is the name the
# notification shows. -Open makes a click on it open that file. -DryRun builds it without showing it.
# -Remove deletes that key and the two Windows adds itself the first time an app notifies, so nothing stays.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File toast.ps1 -App <name> -Title <text> [-Text <text>] [-Open <file>] [-DryRun]
#        powershell -NoProfile -ExecutionPolicy Bypass -File toast.ps1 -Remove [-DryRun]
param([string]$App, [string]$Title, [string]$Text, [string]$Open, [switch]$Remove, [switch]$DryRun)
$aumid = 'ReinstallKit'
$key = "HKCU:\Software\Classes\AppUserModelId\$aumid"
if ($Remove) {
  $keys = $key, "HKCU:\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings\$aumid",
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\PushNotifications\Backup\$aumid"
  if ($DryRun) { "Remove OK: $($keys -join ', ')"; exit 0 }
  Remove-Item $keys -Recurse -Force -ErrorAction SilentlyContinue
  exit 0
}
function Esc([string]$S) { [Security.SecurityElement]::Escape($S) }

$launch = ''
if ($Open) { $launch = ' activationType="protocol" launch="' + (Esc ([Uri]$Open).AbsoluteUri) + '"' }
$body = ''
if ($Text) { $body = '<text>' + (Esc $Text) + '</text>' }
$xmlText = "<toast$launch><visual><binding template=`"ToastGeneric`"><text>$(Esc $Title)</text>$body</binding></visual></toast>"

[void][Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
[void][Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]
$xml = New-Object Windows.Data.Xml.Dom.XmlDocument
$xml.LoadXml($xmlText)
$toast = New-Object Windows.UI.Notifications.ToastNotification $xml
if ($DryRun) { [Console]::OutputEncoding = [Text.Encoding]::UTF8; "Toast OK: $($xml.GetXml())"; exit 0 }

if (-not (Test-Path $key)) { New-Item $key -Force | Out-Null }
Set-ItemProperty $key -Name DisplayName -Value $App
[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($aumid).Show($toast)
