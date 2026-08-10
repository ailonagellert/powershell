<#
.SYNOPSIS
    Determines the active running mode of Microsoft Defender.

.DESCRIPTION
    Checks if Defender is in 'Normal', 'Passive', or 'EDR Block' mode. 
    If the 'Get-MpComputerStatus' command returns no data, it performs 
    a secondary check by auditing the status of core Defender services 
    (WinDefend, WdFilter, etc.).

.NOTES
#>

$services = @("WinDefend", "WdBoot", "WdFilter", "WdNisSvc", "WdNisDrv")
$mpStatus = Get-MpComputerStatus -ErrorAction SilentlyContinue

if ($null -ne $mpStatus.AMRunningMode) {
    Write-Host "Defender Mode: $($mpStatus.AMRunningMode)" -ForegroundColor Green
} else {
    Write-Host "Querying service status as fallback..." -ForegroundColor Yellow
    $running = Get-Service -Name $services -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq "Running" }
    if ($running) {
        Write-Host "Defender appears ACTIVE (Running Services: $($running.Count))" -ForegroundColor Cyan
    } else {
        Write-Host "Defender appears DISABLED." -ForegroundColor Red
    }
}
