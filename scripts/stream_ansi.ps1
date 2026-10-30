# Runs a console tool that writes in a legacy code page and passes its output on, line by line as it
# comes, in UTF-8: what Setup's ExecAndLogOutput reads. pnputil writes in the system's ANSI code page;
# DISM in the system's OEM one (-Oem), whatever the console's is. Returns the tool's exit code.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File stream_ansi.ps1 <exe> "<arguments>" [-Oem]
param([Parameter(Mandatory)][string]$FilePath, [string]$Arguments, [switch]$Oem)
$toolEncoding = [Text.Encoding]::Default
if ($Oem) {
  $toolEncoding = [Text.Encoding]::GetEncoding([int](Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\CodePage').OEMCP)
}
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$info = New-Object Diagnostics.ProcessStartInfo $FilePath, $Arguments
$info.UseShellExecute = $false
$info.RedirectStandardOutput = $true
$info.StandardOutputEncoding = $toolEncoding
$tool = [Diagnostics.Process]::Start($info)
while ($null -ne ($line = $tool.StandardOutput.ReadLine())) { [Console]::WriteLine($line) }
$tool.WaitForExit()
exit $tool.ExitCode
