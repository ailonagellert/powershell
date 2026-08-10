<#
.SYNOPSIS
    Queries SCCM Component Status Messages.

.DESCRIPTION
    Retrieves recent status messages for the 'SMS_INVENTORY_DATA_LOADER' 
    component. Specifically filters for Message ID 2722 (Inventory 
    processing status).

.NOTES
#>

param(
    [string]$ComponentName = "SMS_INVENTORY_DATA_LOADER",
    [string]$MessageID = "2722",
    [int]$LookbackMinutes = 10
)

$start = (Get-Date).AddMinutes(-$LookbackMinutes)

Write-Host "Querying SCCM status messages for $ComponentName (ID: $MessageID) since $start..."
$messages = Get-CMComponentStatusMessage -ComponentName $ComponentName -StartTime $start | 
            Where-Object { $_.MessageID -eq $MessageID }

if ($messages) {
    $messages | Select-Object Time, MachineName, ComponentName, MessageID, InsStr1, InsStr2 | 
                Format-Table -AutoSize
} else {
    Write-Host "No matching status messages found." -ForegroundColor Yellow
}
