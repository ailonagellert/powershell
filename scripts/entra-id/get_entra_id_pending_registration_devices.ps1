<#
.SYNOPSIS
    Identifies devices in a 'Pending Registration' state in Entra ID.

.DESCRIPTION
    Queries Microsoft Graph for devices that have a 'TrustType' of 
    'ServerAd' but are not yet fully registered. This state is common in 
    Hybrid Join failures where the device has SCP info but hasn't 
    completed the registration handshake.

.NOTES
#>

# Ensure module is loaded
if (-not (Get-Module -Name Microsoft.Graph.Devices)) { Import-Module Microsoft.Graph.Devices }

Write-Host "Querying Entra ID for pending devices..." -ForegroundColor Cyan
$pending = Get-MgDevice -All | Where-Object {
    ($_.TrustType -eq 'ServerAd') -and ($_.ProfileType -ne 'RegisteredDevice')
}

if ($pending) {
    Write-Host "Found $($pending.Count) devices pending registration:" -ForegroundColor Yellow
    $pending | Select-Object DisplayName, Id, TrustType, ProfileType | Format-Table -AutoSize
} else {
    Write-Host "No pending registration devices found." -ForegroundColor Green
}
