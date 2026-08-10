<#
.SYNOPSIS
    Removes all deployments for a specific SCCM application.

.DESCRIPTION
    This administrative script connects to the SCCM site and purges all active 
    deployments for the application "Microsoft RSAT | Feb 2023".
    This is useful when replacing or retiring a specific version of an app.

.NOTES
#>

# Load SCCM module
$modulePath = "$($ENV:SMS_ADMIN_UI_PATH)\..\ConfigurationManager.psd1"
if (Test-Path $modulePath) {
    Import-Module $modulePath
}

# Connect to Site (S21)
if (-not (Test-Path "S21:\")) {
    CD S21:
}

$applicationName = "Microsoft RSAT | Feb 2023"
$app = Get-CMApplication -Name $applicationName

if ($null -eq $app) {
    Write-Error "Application '$applicationName' not found."
    exit
}

$deployments = Get-CMApplicationDeployment -InputObject $app

if ($deployments.Count -eq 0) {
    Write-Host "No deployments found for '$applicationName'."
} else {
    Write-Host "Found $($deployments.Count) deployments. Deleting..."
    foreach ($deployment in $deployments) {
        try {
            Remove-CMApplicationDeployment -InputObject $deployment -Force
            Write-Host "Deleted deployment: $($deployment.AssignmentName)"
            Start-Sleep -Seconds 2 # Allow SCCM DB to update
        } catch {
            Write-Warning "Failed to delete deployment: $($deployment.AssignmentName). Error: $_"
        }
    }
}

Write-Host "Process complete."
