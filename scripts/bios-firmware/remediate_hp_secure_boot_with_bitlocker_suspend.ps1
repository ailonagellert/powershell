<#
.SYNOPSIS
    Remediates HP Secure Boot and manages BitLocker suspension.

.DESCRIPTION
    A comprehensive BIOS remediation script for HP hardware:
    1. Checks multiple HP BIOS settings (Secure Boot, Legacy Boot, 
       Combined Support settings) via 'root/hp/instrumentedBIOS'.
    2. If changes are required, it suspends BitLocker for 1 reboot to 
       prevent a recovery prompt after the hardware configuration change.
    3. Applies settings using 'HP_BIOSSettingInterface'.

.NOTES
#>

param([switch]$ReportOnly)

function Set-HPBIOS {
    param($Name, $Value)
    Write-Host "Setting $Name to $Value..." -ForegroundColor Yellow
    $interface = Get-WmiObject -Namespace root/hp/instrumentedBIOS -Class HP_BIOSSettingInterface
    $result = $interface.SetBIOSSetting($Name, $Value)
    return ($result.ReturnValue -eq 0)
}

# [Complex selection logic for Secure Boot settings preserved]
# ...
