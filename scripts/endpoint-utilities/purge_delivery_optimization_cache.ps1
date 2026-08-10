#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Purges the Delivery Optimization (DO) cache.

.DESCRIPTION
    Forcefully removes all cached update content and delivery 
    optimization jobs from the system. This is a common remediation for 
    stuck Windows Updates or excessive disk usage in 'ServiceProfiles'.

.NOTES
#>

Write-Host "Purging Delivery Optimization Cache..." -ForegroundColor Cyan
Get-DeliveryOptimizationStatus | ForEach-Object {
    $id = $_.FileId
    Write-Host "Removing: $id" -ForegroundColor Yellow
    Remove-DeliveryOptimizationFile -FileId $id -Force
}
Write-Host "DO Cache Cleared." -ForegroundColor Green
