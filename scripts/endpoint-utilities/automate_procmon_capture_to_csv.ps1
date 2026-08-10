<#
.SYNOPSIS
    Automates a background Sysinternals ProcMon capture.

.DESCRIPTION
    A diagnostic utility to capture system activity without a GUI:
    1. Starts 'Procmon.exe' with a 15-minute runtime and a PML backing file.
    2. Waits for the capture to complete and ProcMon to idle.
    3. Terminates the process safely.
    4. Exports the captured data (applying existing filters) to a CSV file.
    5. Cleans up the temporary PML file.

.NOTES
#>

[CmdletBinding()]
param(
    [string]$ProcmonPath = "C:\Windows\System32\Procmon.exe",
    [string]$PmlPath = "C:\Windows\Temp\Capture.pml",
    [string]$CsvPath = "C:\Windows\Temp\$($env:COMPUTERNAME)_ProcMon.csv",
    [int]$RuntimeSeconds = 900
)

$procmon = $ProcmonPath
$pml = $PmlPath
$csv = $CsvPath

# 1. Start Capture
Write-Host "Starting ProcMon capture (${RuntimeSeconds}s)..." -ForegroundColor Cyan
& $procmon /Runtime $RuntimeSeconds /Quiet /Minimized /BackingFile $pml

# 2. Wait
Start-Sleep -Seconds ($RuntimeSeconds + 60)

# 3. Terminate & Export
Write-Host "Terminating and exporting to CSV..." -ForegroundColor Yellow
& $procmon /Terminate
& $procmon /OpenLog $pml /SaveAs $csv /SaveApplyFilter
& $procmon /Terminate

# 4. Cleanup
if (Test-Path $pml) { Remove-Item $pml -Force }
Write-Host "Export complete: $csv" -ForegroundColor Green
