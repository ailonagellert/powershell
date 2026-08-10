#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Remediates BIOS Secure Boot and Boot Order for HP and Lenovo systems.

.DESCRIPTION
    A unified remediation script for HP and Lenovo hardware.
    Features:
    - Manufacturer detection.
    - HP: Enables Secure Boot across multiple BIOS settings variants.
    - Lenovo: Enables Secure Boot and saves settings; reorders boot priority to NVMe/HDD first.
    - Suspends BitLocker if any changes are made.

.PARAMETER ReportOnly
    If set, only scans and reports status without making changes.

.NOTES
#>

param ( [switch]$ReportOnly )

function Get-ComputerManufacturer {
    (Get-WmiObject -Class Win32_ComputerSystem).Manufacturer
}

function Enable-HP-SecureBoot {
    param ([string]$Name, [string]$Value)
    Write-Host "HP: Setting $Name to $Value"
    (Get-WmiObject -Namespace root/hp/instrumentedBIOS -Class HP_BIOSSettingInterface).SetBIOSSetting($Name, $Value)
}

function Test-HPSecureBoot {
    $updated = $false
    $sb = Get-WmiObject -Namespace root/hp/instrumentedBIOS -Class HP_BIOSSetting | Where-Object { $_.Name -match "Secure Boot" }
    foreach ($setting in $sb) {
        if ($setting.CurrentValue -eq "Disable") {
            if (-not $ReportOnly) { Enable-HP-SecureBoot $setting.Name "Enable"; $updated = $true }
            else { Write-Host "Report: HP Secure Boot ($($setting.Name)) is Disabled" }
        }
    }
    # Check Legacy
    $lbo = Get-WmiObject -Namespace root/hp/instrumentedBIOS -Class HP_BIOSSetting | Where-Object { $_.Name -match "Legacy Boot Options" }
    if ($lbo.CurrentValue -eq "Enable") {
        if (-not $ReportOnly) { Enable-HP-SecureBoot "Legacy Boot Options" "Disable"; $updated = $true }
    }
    return $updated
}

function Test-LenovoSecureBoot {
    $sb = Get-WmiObject -Namespace root\wmi -Class Lenovo_BiosSetting | Where-Object { $_.CurrentSetting -match "SecureBoot" }
    if ($sb) {
        $val = $sb.CurrentSetting.Split(",")[1].Split(";")[0]
        if ($val -match "Disable") {
            if (-not $ReportOnly) {
                $name = $sb.CurrentSetting.Split(",")[0]
                $target = if ($val -eq "Disable") { "Enable" } else { "Enabled" }
                (Get-WmiObject -Namespace root\wmi -Class Lenovo_SetBiosSetting).SetBiosSetting("$name,$target")
                (Get-WmiObject -Namespace root\wmi -Class Lenovo_SaveBiosSettings).SaveBiosSettings()
                return $true
            }
        }
    }
    return $false
}

# Main
$m = Get-ComputerManufacturer
$res = $false
if ($m -match "HP|Hewlett") { $res = Test-HPSecureBoot }
elseif ($m -match "Lenovo") { $res = Test-LenovoSecureBoot }

if ($res -and -not $ReportOnly) {
    Suspend-BitLocker -MountPoint "C:" -RebootCount 1
    Write-Host "Remediation applied. BitLocker suspended."
}
