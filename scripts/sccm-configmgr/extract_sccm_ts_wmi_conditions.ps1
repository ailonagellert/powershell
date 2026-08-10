<#
.SYNOPSIS
    Extracts WMI condition queries from an SCCM Task Sequence.

.DESCRIPTION
    Useful for auditing or troubleshooting complex Task Sequence logic. 
    It parses the underlying XML of a specific SCCM Task Sequence to find 
    all WMI queries used in step conditions.

.NOTES
#>

param(
    [string]$TSName = "mod Lenovo Drivers - wim"
)

$ts = Get-CMTaskSequence -Name $TSName
if (-not $ts) { Write-Error "Task Sequence not found."; exit }

[xml]$xml = $ts.Sequence
$nodes = $xml.SelectNodes("//expression[@type='SMS_TaskSequence_WMIConditionExpression']")

Write-Host "WMI Queries in TS: $TSName" -ForegroundColor Cyan
foreach ($node in $nodes) {
    $query = $node.variable | Where-Object { $_.name -eq 'Query' }
    if ($query) {
        Write-Host " - $($query.'#text')"
    }
}
