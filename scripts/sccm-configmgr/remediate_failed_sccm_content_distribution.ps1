<#
.SYNOPSIS
    Automates remediation of failed SCCM content distribution.

.DESCRIPTION
    A server-side automation script:
    1. Queries WMI for package distribution failures (States 1, 2, 3, 8).
    2. Identifies specific Distribution Points where content failed.
    3. Triggers a 'Refresh' by setting the 'RefreshNow' property in WMI, 
       forcing the DP to redownload and validate the content.

.NOTES
#>

param(
    [string]$SiteCode = "S21",
    [string]$SiteServer = "dalpsccm21"
)

$namespace = "root\sms\site_$SiteCode"

# Find failed content summarizer entries
$failures = Get-CimInstance -Namespace $namespace `
    -Query "SELECT * FROM SMS_PackageStatusDistPointsSummarizer WHERE State IN (1, 2, 3, 8)"

if (-not $failures) { Write-Host "No distribution failures found."; exit }

foreach ($f in $failures) {
    Write-Host "Redistributing Package $($f.PackageID) to $($f.ServerNALPath)..." -ForegroundColor Yellow
    
    # Locate the actual DP object
    $dp = Get-CimInstance -Namespace $namespace `
        -Query "SELECT * FROM SMS_DistributionPoint WHERE PackageID='$($f.PackageID)'" |
        Where-Object { $_.ServerNALPath -eq $f.ServerNALPath }
        
    if ($dp) {
        Invoke-CimMethod -InputObject $dp -MethodName "Put" # Trigger update
        # RefreshNow is a property we set
        $dp.RefreshNow = $true
        Set-CimInstance -CimInstance $dp
        Write-Host "Successfully triggered refresh." -ForegroundColor Green
    }
}
