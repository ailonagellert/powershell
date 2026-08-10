<#
.SYNOPSIS
    Throttles the processing of SCCM MIF files to avoid server overload.

.DESCRIPTION
    A utility for SCCM administrators to manage high volumes of Management 
    Information Format (MIF) files in the inventory inbox.
    Instead of dumping thousands of files into 'dataldr.box' at once, which 
    can cause the Data Loader thread to hang or backlog, this script:
    1. Monitors a staging directory (D:\MIFS).
    2. Moves files in batches of 15 to the SCCM inbox.
    3. Pauses for 60 seconds between batches.
    
    This ensures a steady, manageable flow of inventory data.

.NOTES
#>

$source = "D:\MIFS"
$inbox = "D:\Program Files\Microsoft Configuration Manager\inboxes\auth\dataldr.box"
$batchSize = 15
$intervalSeconds = 60

if (-not (Test-Path $inbox)) {
    Write-Error "SCCM dataldr.box directory not found at $inbox"
    exit
}

do {
    $files = Get-ChildItem -Path $source -Filter *.mif | Select-Object -First $batchSize
    
    if ($files) {
        Write-Host "$(Get-Date -Format 'HH:mm:ss') - Moving batch of $($files.Count) files..." -ForegroundColor Cyan
        foreach ($file in $files) {
            Move-Item -Path $file.FullName -Destination $inbox -Force
        }
        Write-Host "Batch complete. Sleeping for $intervalSeconds seconds..."
        Start-Sleep -Seconds $intervalSeconds
    }
} while ($files.Count -gt 0)

Write-Host "All MIF files processed." -ForegroundColor Green
