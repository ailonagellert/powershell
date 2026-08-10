<#
.SYNOPSIS
    Verifies system health using DISM and configures repair sources.

.DESCRIPTION
    This script ensures the system can perform repairs by:
    1. Enabling Windows Update access in policy.
    2. Setting 'DownloadRepairContent' to 1.
    3. Running 'DISM /Online /Cleanup-Image /CheckHealth' to check for corruption.
    Returns exit code 0 if healthy, 1 if corruption is found.

.NOTES
#>

$regPath = "HKLM:\Software\Policies\Microsoft\Windows\WindowsUpdate"

if (-not (Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }

Set-ItemProperty -Path $regPath -Name "DisableWindowsUpdateAccess" -Value 0 -Type DWord
Set-ItemProperty -Path $regPath -Name "DownloadRepairContent" -Value 1 -Type DWord

Write-Host "Checking system health via DISM..."
$result = DISM /Online /Cleanup-Image /CheckHealth
$isHealthy = $result | Select-String "No component store corruption detected."

if ($isHealthy) {
    Write-Host "System is healthy." -ForegroundColor Green
    exit 0
} else {
    Write-Warning "Corruption detected or DISM check failed."
    exit 1
}
