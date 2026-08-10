<#
.SYNOPSIS
    Monitors system resource usage with a focus on the Winmgmt svchost process.

.DESCRIPTION
    This script analyzes total RAM, process CPU usage, and specifically targets the
    svchost.exe process associated with Windows Management Instrumentation (Winmgmt).
    If both total processor time and the specific svchost CPU percentage exceed 20%,
    it enters a monitoring loop to log CPU and Memory statistics every 2 seconds for
    approximately 8 seconds.

.NOTES
    - Uses a mix of CimInstance and WmiObject for compatibility.
    - Contains specific threshold logic for high resource usage detection.
#>

# Initialize loop counter for monitoring duration
$count = 1

# Retrieve total physical RAM capacity in bytes
$totalRam = (Get-CimInstance Win32_PhysicalMemory | Measure-Object -Property capacity -Sum).Sum

# Get snapshot of all current processes
$processes = Get-Process

# Check svchost wmimgnt process
# Calculate sum of CPU time across all processes
$totalCpuUsage = ($processes | Measure-Object -Property CPU -Sum).Sum

# Identify Process ID for svchost.exe running Winmgmt service via command line match
$svhostpid = (Get-WmiObject Win32_Process | Where-Object { $_.Name -eq "svchost.exe" -and $_.CommandLine -eq "C:\WINDOWS\system32\svchost.exe -k netsvcs -p -s Winmgmt" } | Select-Object ProcessId).ProcessId

# Retrieve CPU time for the specific svchost process ID
$svchostCpuUsage = ($processes | Where-Object { $_.id -eq $svhostpid }).cpu

# Calculate svchost CPU usage as a percentage of total process CPU time
$svchostCpuPercentage = ($svchostCpuUsage / $totalCpuUsage) * 100

# Get current total processor time percentage from performance counter
$cpuTime = (Get-Counter "\\$env:computername\Processor(_Total)\% Processor Time").CounterSamples.CookedValue

# Check if both total CPU time and svchost CPU percentage exceed 20% threshold
if ($cpuTime -gt 20 -and $svchostCpuPercentage -gt 20) {
    Write-Host "High svchost: $($svchostCpuPercentage.ToString('F2'))%"

    # Loop while count is less than 5 to monitor resource usage over time
    while ($count -lt 5) {
        $date = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        # Refresh total processor time percentage
        $cpuTime = (Get-Counter "\\$env:computername\Processor(_Total)\% Processor Time").CounterSamples.CookedValue
        # Get available memory in Megabytes
        $availMem = (Get-Counter "\\$env:computername\Memory\Available MBytes").CounterSamples.CookedValue
        # Calculate percentage of available memory based on total RAM
        $percentAvailMem = (104857600 * $availMem / $totalRam)
        Write-Host "CPU: $cpuTime%, Mem.: $availMem MB ($percentAvailMem%)"
        Start-Sleep -Seconds 2
        $count++
    }
} else {
    Write-Host "Low svchost: $($svchostCpuPercentage.ToString('F2'))%."
}