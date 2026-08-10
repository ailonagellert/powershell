#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Downloads and silently installs Lenovo System Interface Foundation.

.DESCRIPTION
    A deployment script for the Lenovo System Interface Foundation (SIF), 
    which is required for Lenovo Vantage and BIOS management features:
    1. Downloads the 'sif11ww203.exe' installer from Lenovo's servers.
    2. Executes it with '/verysilent /norestart' switches.

.NOTES
#>

[CmdletBinding()]
param(
    [string]$Url = "https://download.lenovo.com/pccbbs/mobiles/sif11ww203.exe",
    [string]$Destination = "C:\Windows\Temp\sif_installer.exe"
)

Write-Host "Downloading Lenovo SIF..." -ForegroundColor Cyan
Invoke-WebRequest -Uri $Url -OutFile $Destination

if (Test-Path $Destination) {
    Write-Host "Installing silently..." -ForegroundColor Green
    $process = Start-Process -FilePath $Destination -ArgumentList "/verysilent", "/norestart" -Wait -PassThru
    Remove-Item $Destination -Force
    exit $process.ExitCode
} else {
    Write-Error "Download failed."
    exit 1
}
