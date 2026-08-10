<#
.SYNOPSIS
    Cleans up stale Entra ID (Azure AD) devices.

.DESCRIPTION
    Uses the Microsoft.Graph module to identify and delete devices that 
    haven't signed in for more than 200 days.
    Requires 'Directory.ReadWrite.All' or 'Device.ReadWrite.All' permissions.

.NOTES
#>

# Connect-MgGraph -Scopes "Device.ReadWrite.All"

$staleLimit = (Get-Date).AddDays(-200)
Write-Host "Searching for Entra ID devices stale since $staleLimit..." -ForegroundColor Cyan

$allDevices = Get-MgDevice -All
$staleDevices = $allDevices | Where-Object { $_.ApproximateLastSignInDateTime -lt $staleLimit }

if ($staleDevices) {
    foreach ($device in $staleDevices) {
        Write-Host "Deleting Stale Device: $($device.DisplayName) (Last Login: $($device.ApproximateLastSignInDateTime))" -ForegroundColor Yellow
        Remove-MgDevice -DeviceId $device.Id
    }
} else {
    Write-Host "No stale devices found." -ForegroundColor Green
}
