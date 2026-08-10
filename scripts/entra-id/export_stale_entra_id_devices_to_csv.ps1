<#
.SYNOPSIS
    Exports stale Entra ID devices to CSV for audit.

.DESCRIPTION
    Queries Microsoft Graph for devices that haven't signed in for more 
    than 400 days and exports the DisplayName and last login date to a 
    CSV file.

.NOTES
#>

$out = ".\EntraStaleAudit.csv"
$staleDate = (Get-Date).AddDays(-400)

Write-Host "Exporting devices stale since $staleDate..."
$stale = Get-MgDevice -All | Where-Object { $_.ApproximateLastSignInDateTime -lt $staleDate }

if ($stale) {
    $stale | Select-Object DisplayName, ApproximateLastSignInDateTime, AccountEnabled | 
             Export-Csv -Path $out -NoTypeInformation
    Write-Host "Audit saved to: $out" -ForegroundColor Green
} else {
    Write-Host "No stale devices found."
}
