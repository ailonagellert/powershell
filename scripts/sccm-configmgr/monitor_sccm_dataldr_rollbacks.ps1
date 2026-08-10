<#
.SYNOPSIS
    Monitors SCCM dataldr.log for rollback transactions.

.DESCRIPTION
    This script tails the SCCM 'dataldr.log' file and monitors it for "Rollback transaction" entries.
    It parses the custom SCCM log timestamp to ensure it only processes new entries since the script started.
    When a rollback is detected, it identifies the machine name from the log entry and outputs an alert.

.NOTES
#>

$logPath = "D:\Program Files\Microsoft Configuration Manager\Logs\dataldr.log"
$lastCheckTime = [DateTime]::Now

Write-Host "Monitoring $logPath for rollback transactions..."

while ($true) {
    Start-Sleep -Seconds 10

    $logContent = Get-Content -Path $logPath -Tail 100 | ForEach-Object {
        try {
            # Extract the timestamp string from the log entry <MM-DD-YYYY HH:MM:SS.mmm+OFFSET>
            if ($_ -match '<(\d{2}-\d{2}-\d{4} \d{2}:\d{2}:\d{2}.\d{3}\+\d{3})>') {
                $timestampString = $matches[1]

                # Convert the timezone offset from minutes to standard TimeSpan format '+HH:00'
                $timezoneOffset = [int]$timestampString.Split('+')[1]
                $hoursOffset = [Math]::Floor($timezoneOffset / 60)
                $standardTimezoneOffset = "{0:D2}:00" -f $hoursOffset

                # Reconstruct the timestamp with a standard timezone offset for parsing
                $standardTimestampString = $timestampString -replace '\+\d{3}', '+' + $standardTimezoneOffset

                # Parse the standard timestamp string to a DateTime object
                $lineTime = [DateTime]::ParseExact($standardTimestampString, "MM-dd-yyyy HH:mm:ss.fffzzz", $null)

                if ($lineTime -gt $lastCheckTime) {
                    $_
                }
            }
        } catch {
            # Silent fail for unparseable lines
        }
    }

    foreach ($line in $logContent) {
        if ($line -match "Rollback transaction: Machine=(\w+)\(GUID:.+\)") {
            $machineName = $matches[1]
            Write-Host "âš ï¸ [$(Get-Date)] Detected rollback transaction for machine: $machineName" -ForegroundColor Yellow
        }
    }

    $lastCheckTime = [DateTime]::Now
}
