<#
.SYNOPSIS
    Audits stale Active Directory computers with connectivity validation.

.DESCRIPTION
    A hygiene utility for AD admins:
    1. Filters for computers with 'PasswordLastSet' older than 100 days.
    2. Performs a live ping test (Test-Connection) on each discovered 
       object.
    3. Categorizes and exports machines into 'Online' (stale password but 
       live) and 'Offline' (likely decommissioned) CSV reports.

.NOTES
#>

param(
    [int]$StaleDays = 100,
    [string]$OutDir = "C:\Temp"
)

Import-Module ActiveDirectory

$staleDate = (Get-Date).AddDays(-$StaleDays)
Write-Host "Finding computers with PasswordLastSet <= $staleDate..." -ForegroundColor Cyan

$stale = Get-ADComputer -Filter "PasswordLastSet -le '$staleDate'" -Properties PasswordLastSet, LastLogonDate |
         Select-Object Name, DistinguishedName, PasswordLastSet, LastLogonDate

$online = @(); $offline = @()

foreach ($c in $stale) {
    if (Test-Connection -ComputerName $c.Name -Count 1 -Quiet -ErrorAction SilentlyContinue) {
        $online += $c
    } else {
        $offline += $c
    }
}

$online | Export-Csv -Path "$OutDir\Stale_Online.csv" -NoTypeInformation
$offline | Export-Csv -Path "$OutDir\Stale_Offline.csv" -NoTypeInformation

Write-Host "Done. Online: $($online.Count), Offline: $($offline.Count)" -ForegroundColor Green
