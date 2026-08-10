<#
.SYNOPSIS
    Automates Windows Disk Cleanup (CleanMgr.exe).

.DESCRIPTION
    Triggers a non-interactive Disk Cleanup by pre-selecting specific 
    cleanup flags in the registry:
    1. Sets 'StateFlags0001' to 2 (Enabled) for 'Update Cleanup' and 
       'Temporary Files'.
    2. Runs 'cleanmgr.exe /sagerun:1' hidden to perform the cleanup 
       without user prompts.

.NOTES
#>

$reg = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches'
$flags = @("Update Cleanup", "Temporary Files", "Recycle Bin")

Write-Host "Configuring Disk Cleanup flags..." -ForegroundColor Cyan
foreach ($f in $flags) {
    $path = Join-Path $reg $f
    if (Test-Path $path) {
        Set-ItemProperty -Path $path -Name "StateFlags0001" -Value 2 -Type DWord
    }
}

Write-Host "Starting silent cleanup..." -ForegroundColor Green
Start-Process -FilePath 'cleanmgr.exe' -ArgumentList "/sagerun:1" -WindowStyle Hidden
