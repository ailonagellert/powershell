#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Ensures KB4023057 is installed to maintain Windows Update health.

.DESCRIPTION
    This script checks the update history for KB4023057.
    If missing, it:
    1. Restarts the 'wuauserv' service.
    2. Triggers an online scan and installation using 'UsoClient.exe'.
    3. Falls back to a direct 'DetectNow()' COM call if necessary.

.NOTES
#>

$Session = New-Object -ComObject Microsoft.Update.Session
$Searcher = $Session.CreateUpdateSearcher()
$historyCount = $Searcher.GetTotalHistoryCount()
$list = $Searcher.QueryHistory(0, $historyCount) | Select-Object -Property "Title"

$updateFound = $false
foreach ($update in $list) {
    if ($update.Title -match "KB4023057") {
        Write-Host "KB4023057 is already installed."
        $updateFound = $true
        break
    }
}

if (-not $updateFound) {
    Write-Host "KB4023057 not found. Triggering update scan..."
    
    Stop-Service wuauserv -Force -ErrorAction SilentlyContinue
    Start-Service wuauserv
    
    # Trigger Update Orchestrator Client
    Start-Process -NoNewWindow -FilePath "C:\Windows\System32\UsoClient.exe" -ArgumentList "StartScan"
    Start-Process -NoNewWindow -FilePath "C:\Windows\System32\UsoClient.exe" -ArgumentList "StartInstall"
    
    # Fallback
    (New-Object -ComObject Microsoft.Update.AutoUpdate).DetectNow()
}
