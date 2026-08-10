<#
.SYNOPSIS
    Downloads the Lenovo System Interface Foundation (SIF) installer.

.DESCRIPTION
    This script downloads the specific version (v203) of the Lenovo System Interface Foundation
    installer from the Lenovo support servers to a temporary local folder.

.NOTES
#>

# Define the URL and the destination path
$url = "https://download.lenovo.com/pccbbs/mobiles/sif11ww203.exe"
$destinationDir = "C:\temp"
$destinationPath = "$destinationDir\sif11ww203.exe"

# Ensure destination directory exists
if (-not (Test-Path $destinationDir)) {
    New-Item -ItemType Directory -Path $destinationDir
}

# Download the file
Write-Host "Downloading Lenovo SIF from $url..."
Invoke-WebRequest -Uri $url -OutFile $destinationPath

Write-Host "Download complete: $destinationPath"
