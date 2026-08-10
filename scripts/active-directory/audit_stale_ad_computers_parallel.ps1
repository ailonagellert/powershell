<#
.SYNOPSIS
    Audits stale Active Directory computers and tests connectivity in parallel.

.DESCRIPTION
    1. Identifies AD computer accounts where the password has not been reset in 90 days.
    2. Exports the list to 'c:\temp\InactiveMachines-90.csv'.
    3. Uses a PowerShell Workflow (Test-WFConnection) to ping all identified 
       machines in parallel to determine which are truly offline vs. just stale in AD.

.NOTES
    Requires the Active Directory module.
#>

# Parameters
$days = 90
$exportPath = "c:\temp\InactiveMachines-90.csv"
$staleDate = (Get-Date).AddDays(-$days)

# 1. Get Stale Computers
Import-Module ActiveDirectory
$inactiveWorkstations = Get-ADComputer -Filter { passwordLastSet -le $staleDate } -Properties Name, passwordLastSet, LastLogonDate, OperatingSystem
$inactiveWorkstations | Export-Csv $exportPath -NoTypeInformation

Write-Host "Found $($inactiveWorkstations.Count) stale computers. Exported to $exportPath"

# 2. Parallel Connectivity Test
workflow Test-WFConnection {
    param([string[]]$Computers)
    foreach -parallel ($computer in $Computers) {
        if (Test-Connection -ComputerName $computer -Count 1 -Quiet -ErrorAction SilentlyContinue) {
            $computer
        }
    }
}

Write-Host "Testing connectivity for stale machines..."
$onlineMachines = Test-WFConnection -Computers $inactiveWorkstations.Name
Write-Host "$($onlineMachines.Count) machines are currently online."
$onlineMachines
