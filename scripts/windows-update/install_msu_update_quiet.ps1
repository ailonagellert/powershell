<#
.SYNOPSIS
    Installs a Windows Update MSU file quietly.

.DESCRIPTION
    Uses wusa.exe to install a specified .msu update package.
    Flags used: /quiet /norestart.
    Logs installation details to c:\temp\winupdate.log.

.PARAMETER MsuPath
    Full path to the .msu file to install.

.NOTES
#>

param (
    [string]$MsuPath = "c:\temp\windows11.0-kb5048685-x64.msu"
)

if (-Not (Test-Path $MsuPath)) {
    Write-Error "MSU file not found at: $MsuPath"
    exit 1
}

$logPath = "c:\temp\winupdate.log"

try {
    Write-Host "Installing update: $MsuPath" -ForegroundColor Green
    # Execute wusa.exe
    Start-Process -FilePath "wusa.exe" -ArgumentList "$MsuPath /quiet /norestart /log:`"$logPath`"" -Wait
    Write-Host "Installation initiated. Check $logPath for results."
} catch {
    Write-Error "Failed to install update: $_"
}
