<#
.SYNOPSIS
    Monitors Windows Defender and security center services.

.DESCRIPTION
    Checks the current status (Running/Stopped) and Startup Type for all 
    Microsoft Defender and Windows Security Center related services:
    - WinDefend (Antivirus)
    - WdBoot, WdFilter, WdNisSvc, WdNisDrv (Protection Drivers/Services)
    - SecurityHealthService (Windows Security App)
    - wscsvc (Security Center)

.NOTES
#>

$services = @(
    "WinDefend", "WdBoot", "WdFilter", "WdNisSvc", 
    "WdNisDrv", "SecurityHealthService", "wscsvc"
)

Write-Host "Checking Security & Defender Services..." -ForegroundColor Cyan
Get-Service -Name $services -ErrorAction SilentlyContinue | 
Select-Object DisplayName, Name, StartType, Status | 
Sort-Object Status -Descending |
Format-Table -AutoSize
