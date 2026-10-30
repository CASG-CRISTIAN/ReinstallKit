# Installs several WinGet packages at once, for Setup's option of installing several apps at a time: at
# most -Max winget processes run together and the rest wait their turn, in order. -Jobs is a UTF-8 file
# with one job per line, "<number><TAB><winget arguments>". Everything goes to the output, which Setup
# reads as it comes:
#   <number>|<a line written by winget>
#   <number>|@@START <process id>       started (Setup cuts it with taskkill /PID /T when it is skipped)
#   <number>|@@RETRY <code> <seconds>   another installation in progress or WinGet not ready: tried later
#   <number>|@@EXIT <code>              winget ended with that exit code
#   <number>|@@NOSTART <code>           winget could not be started (Windows error code)
# Once the -Stop file exists no job starts any more, those waiting to be retried included; once
# "<Stop>_<number>" exists, that job is not retried (Setup skipped it while it waited): it ends with @@EXIT 1.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File install_parallel.ps1 -Jobs <file> -Max 3 -Stop <file>
#   [-Winget winget.exe] [-RetrySeconds 30]
param([Parameter(Mandatory)][string]$Jobs, [Parameter(Mandatory)][int]$Max, [Parameter(Mandatory)][string]$Stop,
  [string]$Winget = 'winget.exe', [int]$RetrySeconds = 30)
[Console]::OutputEncoding = [Text.Encoding]::UTF8   # what Setup reads
function Say([string]$Text) { [Console]::Out.WriteLine($Text); [Console]::Out.Flush() }

# Retried as Setup does one by one, three tries in all: another installation in progress (0x8A150102, two
# MSI installers cannot run at once) and WinGet's sources not ready yet (0x80071130)
$retryCodes = -1978334974, -2147020496

$waiting = New-Object Collections.Generic.List[object]
foreach ($line in [IO.File]::ReadAllLines($Jobs, [Text.Encoding]::UTF8)) {
  if (-not $line.Trim()) { continue }
  $id, $arguments = $line -split "`t", 2
  $waiting.Add([pscustomobject]@{ Id = $id; Arguments = $arguments; Tries = 0; NotBefore = [datetime]::MinValue })
}
$running = @{}

# One line read ahead per process, checked on each round: the order of its lines is kept (Process's
# OutputDataReceived events may come out of order). winget's errors go to its output too; anything on
# stderr reaches Setup as this script's own.
function Send-Output($id) {
  $run = $running[$id]
  while ($run.Line.IsCompleted) {
    $text = $run.Line.Result
    if ($null -eq $text) { return $true }   # its output has ended
    Say "$id|$text"
    $run.Line = $run.Process.StandardOutput.ReadLineAsync()
  }
  return $false
}

function Start-Winget($job) {
  $job.Tries++
  $info = New-Object Diagnostics.ProcessStartInfo $Winget, $job.Arguments
  $info.UseShellExecute = $false
  $info.CreateNoWindow = $true
  $info.RedirectStandardOutput = $true
  $info.StandardOutputEncoding = [Text.Encoding]::UTF8
  $process = New-Object Diagnostics.Process
  $process.StartInfo = $info
  try { [void]$process.Start() }
  catch {
    $code = 1359   # ERROR_INTERNAL_ERROR, unless Windows says why
    if ($_.Exception.InnerException -is [ComponentModel.Win32Exception]) { $code = $_.Exception.InnerException.NativeErrorCode }
    Say "$($job.Id)|$($_.Exception.InnerException.Message)"
    Say "$($job.Id)|@@NOSTART $code"
    return
  }
  Say "$($job.Id)|@@START $($process.Id)"
  $running[$job.Id] = @{ Process = $process; Job = $job; Line = $process.StandardOutput.ReadLineAsync() }
}

while ($waiting.Count -or $running.Count) {
  $stopped = Test-Path -LiteralPath $Stop
  if ($stopped) { $waiting.Clear() }
  foreach ($job in $waiting.ToArray()) {   # @() fails on a List in PowerShell 5.1
    if (Test-Path -LiteralPath "$($Stop)_$($job.Id)") { [void]$waiting.Remove($job); Say "$($job.Id)|@@EXIT 1" }
  }
  while (-not $stopped -and $running.Count -lt $Max) {
    $next = $waiting | Where-Object { $_.NotBefore -le [datetime]::Now } | Select-Object -First 1
    if (-not $next) { break }
    [void]$waiting.Remove($next)
    Start-Winget $next
  }
  Start-Sleep -Milliseconds 200
  foreach ($id in @($running.Keys)) {
    if (-not (Send-Output $id)) { continue }
    $process = $running[$id].Process
    $process.WaitForExit()
    $job = $running[$id].Job
    $running.Remove($id)
    $code = $process.ExitCode
    if (($retryCodes -contains $code) -and ($job.Tries -lt 3) -and -not (Test-Path -LiteralPath $Stop)) {
      Say "$id|@@RETRY $code $RetrySeconds"
      $job.NotBefore = [datetime]::Now.AddSeconds($RetrySeconds)
      $waiting.Insert(0, $job)
    }
    else { Say "$id|@@EXIT $code" }
  }
}