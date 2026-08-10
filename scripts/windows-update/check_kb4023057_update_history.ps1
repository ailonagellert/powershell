<#
.SYNOPSIS
    Checks if KB4023057 is present in Windows Update history.

.DESCRIPTION
    This script uses the Microsoft.Update.Session COM object to search the local update history
    for the title "4023057". This update is often used for Windows Update service health.
    Returns 1 if the update is found, 0 otherwise.

.NOTES
#>

$Session = New-Object -ComObject Microsoft.Update.Session
$Searcher = $Session.CreateUpdateSearcher()
$historyCount = $Searcher.GetTotalHistoryCount()

if ($historyCount -gt 0) {
    $list = $Searcher.QueryHistory(0, $historyCount) | Select-Object -Property "Title"
    foreach ($update in $list) {
        if ($update.Title.Contains("4023057")) {
            Write-Host "KB4023057 found in history."
            exit 1
        }
    }
}

Write-Host "KB4023057 not found in history."
exit 0
