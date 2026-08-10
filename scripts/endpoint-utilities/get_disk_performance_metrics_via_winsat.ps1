<#
.SYNOPSIS
    Captures disk performance metrics using WinSAT.

.DESCRIPTION
    Runs the Windows System Assessment Tool (WinSAT) to benchmark disk 
    subsystems. It then parses the console output to extract key 
    performance indicators such as Sequential Read, Write, and Random 
    Access speeds, providing a formatted report.

.NOTES
#>

$tempFile = "$env:temp\winsat_disk.txt"

Write-Host "Benchmarking system drive..." -ForegroundColor Cyan
winsat disk -drive C | Out-File -FilePath $tempFile -Encoding ASCII

Write-Host "`n--- Disk Performance Results ---" -ForegroundColor Green
Get-Content $tempFile | Where-Object { $_ -like '> Disk*' } | ForEach-Object {
    $line = $_.Trim("> Disk ").Trim()
    $parts = $line -split '\s{2,}'
    if ($parts.Count -ge 2) {
        Write-Host "$($parts[0]): $($parts[-1])"
    }
}

Remove-Item $tempFile -Force
