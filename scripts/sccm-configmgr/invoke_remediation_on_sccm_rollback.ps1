<#
.SYNOPSIS
    Monitors SCCM logs and triggers remediation on rollback detection.

.DESCRIPTION
    This script provides automated remediation for "Rollback transaction" errors 
    found in the SCCM 'dataldr.log'.
    Logic:
    1. Tails the last 100 lines of dataldr.log.
    2. Parses SCCM timestamps (converting minute-based offsets to standard ISO).
    3. Detects 'Rollback transaction' entries for specific machines.
    4. Triggers an SCCM Script (Guid: A0FCCE9A-9364-49C1-866F-49E1388288E5) 
       against the affected device to remediate the inventory issue.

.NOTES
#>

$logPath = "D:\Program Files\Microsoft Configuration Manager\Logs\dataldr.log"
$lastCheckTime = [DateTime]::Now

Write-Host "Monitoring $logPath for rollback transactions..."

$logLines = Get-Content -Path $logPath -Tail 100 

foreach ($line in $logLines) {
    try {
        # SCCM Log Timestamp Parsing: <MM-DD-YYYY HH:MM:SS.mmm+OFFSET>
        if ($line -match '<(\d{2}-\d{2}-\d{4} \d{2}:\d{2}:\d{2}.\d{3}\+(\d{3}))>') {
            $timestampRaw = $matches[1]
            $offsetMinutes = [int]$matches[2]
            
            # Convert offset to standard HH:mm
            $hours = [Math]::Floor($offsetMinutes / 60)
            $standardOffset = "{0:D2}:00" -f $hours
            $standardTimestamp = $timestampRaw -replace '\+\d{3}', "+$standardOffset"
            
            $lineTime = [DateTime]::ParseExact($standardTimestamp, "MM-dd-yyyy HH:mm:ss.fffzzz", $null)

            # Check if this is a new rollback entry
            if ($lineTime -gt $lastCheckTime -and $line -match "Rollback transaction: Machine=(\w+)") {
                $machineName = $matches[1]
                Write-Host "Detected rollback for $machineName. Triggering remediation script..." -ForegroundColor Yellow
                
                # Trigger the remediation script in SCCM
                $device = Get-CMDevice -Name $machineName
                if ($device) {
                    Invoke-CMScript -Device $device -ScriptGuid "A0FCCE9A-9364-49C1-866F-49E1388288E5" | Out-Null
                }
            }
        }
    } catch {
        # Skip lines that don't match or fail parsing
    }
}

$lastCheckTime = [DateTime]::Now
