#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Ensures critical Workplace Join scheduled tasks are enabled.

.DESCRIPTION
    Remediates Entra ID (Azure AD) registration issues by ensuring the 
    following tasks in '\Microsoft\Windows\Workplace Join\' are enabled:
    1. Automatic-Device-Join
    2. Device-Sync

.NOTES
#>

$taskPath = "\Microsoft\Windows\Workplace Join\"
$tasks = @("Automatic-Device-Join", "Device-Sync")

foreach ($name in $tasks) {
    $task = Get-ScheduledTask -TaskPath $taskPath -TaskName $name -ErrorAction SilentlyContinue
    if ($null -eq $task) {
        Write-Warning "Task $name not found."
        continue
    }

    if ($task.State -eq "Disabled") {
        Write-Host "Enabling task: $name..." -ForegroundColor Yellow
        Enable-ScheduledTask -TaskPath $taskPath -TaskName $name
    } else {
        Write-Host "Task $name is already $($task.State)." -ForegroundColor Green
    }
}
