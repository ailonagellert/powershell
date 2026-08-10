#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Cleans up temporary Windows upgrade files.

.DESCRIPTION
    Safely checks for and deletes the 'C:\$WINDOWS.~BT' directory.
    This folder is used by Windows Setup to store logs and temporary files 
    during an OS upgrade and can often be safely removed after a successful 
    deployment to free up space.

.NOTES
#>

$upgradePath = 'C:\$WINDOWS.~BT'

if (Test-Path -Path $upgradePath) {
    try {
        Write-Host "Found upgrade temp folder at $upgradePath. Deleting..."
        Remove-Item -Path $upgradePath -Recurse -Force -ErrorAction Stop
        Write-Host "Cleanup successful." -ForegroundColor Green
    } catch {
        Write-Warning "Failed to delete $upgradePath. It may be in use. Error: $_"
    }
} else {
    Write-Host "No upgrade temp folder detected."
}
