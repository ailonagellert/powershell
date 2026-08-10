<#
.SYNOPSIS
    Returns the computer manufacturer via WMI.

.DESCRIPTION
    Queries the Win32_ComputerSystem class to retrieve and output 
    the hardware manufacturer (e.g., HP, Lenovo, Dell).

.NOTES
#>

$manufacturer = (Get-WmiObject -Class Win32_ComputerSystem).Manufacturer
Write-Output $manufacturer
