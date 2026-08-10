<#
.SYNOPSIS
    Retrieves the status of Windows Recovery Environment (WinRE).

.DESCRIPTION
    Uses the native 'reagentc /info' command to determine if WinRE is 
    Enabled or Disabled. Useful for ensuring recovery partition 
    accessibility before OS upgrades or maintenance.

.NOTES
#>

Write-Host "Checking Windows Recovery Environment (WinRE) status..." -ForegroundColor Cyan
$info = & reagentc /info
$statusMatch = $info | Select-String "Windows RE status|WinRE"

if ($statusMatch) {
    $status = $statusMatch.ToString().Split(":")[1].Trim()
    if ($status -eq "Enabled") {
        Write-Host "WinRE is: ENABLED" -ForegroundColor Green
    } else {
        Write-Host "WinRE is: DISABLED" -ForegroundColor Red
    }
} else {
    Write-Warning "Could not parse reagentc output."
    $info
}
