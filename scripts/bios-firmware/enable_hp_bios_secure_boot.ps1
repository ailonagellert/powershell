#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Enables Secure Boot on HP systems via WMI.

.DESCRIPTION
    This script specifically targets HP hardware to enable Secure Boot.
    It checks and modifies three BIOS settings if necessary:
    1. 'Secure Boot'
    2. 'Legacy Boot Options'
    3. 'Configure Legacy Support and Secure Boot'
    It suspends BitLocker for one reboot to prevent issues with BIOS state changes.

.NOTES
#>

# Suspend BitLocker for safety
if (Get-Command Suspend-BitLocker -ErrorAction SilentlyContinue) {
    Suspend-BitLocker -MountPoint "C:" -RebootCount 1
    Write-Host "BitLocker suspended."
}

# 1. Check Primary Secure Boot Setting
$sb = (Get-WmiObject -Namespace root/hp/instrumentedBIOS -Class HP_BIOSSetting | Where-Object {$_.Name -eq "Secure Boot"})
if ($sb.CurrentValue -eq "Disable") {
    Write-Host "Enabling Secure Boot..."
    (Get-WmiObject -Namespace root/hp/instrumentedBIOS -Class HP_BIOSSettingInterface).SetBIOSSetting("Secure Boot", "Enable")
}

# 2. Check Legacy Boot Options
$lbo = (Get-WmiObject -Namespace root/hp/instrumentedBIOS -Class HP_BIOSSetting | Where-Object {$_.Name -match "Legacy Boot Options"})
if ($lbo.CurrentValue -eq "Enable") {
    Write-Host "Disabling Legacy Boot Options..."
    (Get-WmiObject -Namespace root/hp/instrumentedBIOS -Class HP_BIOSSettingInterface).SetBIOSSetting("Legacy Boot Options", "Disable")
}

# 3. Check Legacy Support and Secure Boot Combo
$combo = (Get-WmiObject -Namespace root/hp/instrumentedBIOS -Class HP_BIOSSetting | Where-Object {$_.Name -eq "Configure Legacy Support and Secure Boot"})
if ($combo.CurrentValue -match "Secure Boot Disable") {
    Write-Host "Updating Legacy Support/Secure Boot configuration..."
    (Get-WmiObject -Namespace root/hp/instrumentedBIOS -Class HP_BIOSSettingInterface).SetBIOSSetting("Configure Legacy Support and Secure Boot", "Legacy Support Disable and Secure Boot Enable")
}

Write-Host "HP BIOS Remediation complete. A reboot may be required."
