<#
.SYNOPSIS
    Reports top 10 processes by CPU, Memory, and Disk usage.

.DESCRIPTION
    Diagnostic utility that identifies resource-heavy processes.
    Metrics:
    - CPU: Sorts by CPU usage property.
    - Memory: Sorts by WorkingSet (RAM) usage.
    - Disk: Uses '\Process(*)\IO Data Bytes/sec' performance counters.

.NOTES
#>

Write-Host "--- Resource Usage Diagnostic ---" -ForegroundColor Cyan

# 1. CPU
Write-Host "`nTop 10 Processes by CPU Usage:" -ForegroundColor Green
Get-Process | Sort-Object CPU -Descending | Select-Object -First 10 | 
    Format-Table -Property Id, ProcessName, @{Name="CPU(s)"; Expression={$_.CPU}} -AutoSize

# 2. Memory (RAM)
Write-Host "Top 10 Processes by Memory Usage:" -ForegroundColor Green
Get-Process | Sort-Object WorkingSet -Descending | Select-Object -First 10 | 
    Format-Table -Property Id, ProcessName, @{Name="RAM(MB)"; Expression={[Math]::Round($_.WorkingSet / 1MB, 2)}} -AutoSize

# 3. Disk I/O
Write-Host "Top 10 Processes by Disk I/O (Bytes/sec):" -ForegroundColor Green
try {
    $diskCounters = Get-Counter -Counter "\Process(*)\IO Data Bytes/sec" -ErrorAction Stop
    $diskCounters.CounterSamples | Sort-Object -Property CookedValue -Descending | Select-Object -First 10 | 
        Format-Table -Property InstanceName, @{Name="IO_Bytes_Sec"; Expression={$_.CookedValue}} -AutoSize
} catch {
    Write-Warning "Could not retrieve Disk I/O counters."
}
