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
    Original Filename: AutoSaved_6f6c7047-542a-4566-811e-201212cadd68_Untitled576.ps1
#>

param (
    [switch]$ReportOnly = $true
)


# Function to enable Secure Boot via BIOSSettingInterface
function Enable-SecureBoot {
    param (
        [string]$SettingName,
        [string]$TargetValue
    )

    # Set the desired BIOS setting
    $result = (Get-WmiObject -Namespace root/hp/instrumentedBIOS -Class HP_BIOSSettingInterface).SetBIOSSetting($SettingName, $TargetValue)

    # Check the result
    if ($result.ReturnValue -eq 0) {
        Write-Host "$SettingName has been successfully set to $TargetValue."
        $settingupdate = $true
    } else {
        Write-Host "Failed to set $SettingName. Error code: $($result.ReturnValue)"
    }
}
$settingupdate = $false
# Check for Secure Boot setting first
$secureBootSetting = (Get-WmiObject -Namespace root/hp/instrumentedBIOS -Class HP_BIOSSetting | Where-Object {$_.Name -eq "Secure Boot"}).CurrentValue

if ($secureBootSetting) {
    Write-Host "Secure Boot is currently set to: $secureBootSetting"

    if (-not $ReportOnly) {
        if ($secureBootSetting -eq "Disable") {
            Write-Host "Secure Boot is disabled. Attempting to enable Secure Boot..."
            Enable-SecureBoot "Secure Boot" "Enable"
            
        } else {
            Write-Host "Secure Boot is enabled."
        }
    }
} else {
    Write-Host "Secure Boot  not found. Checking Legacy Boot Options..."

    # Check Legacy Boot Options as fallback
    $LegacyBootOptions = (Get-WmiObject -Namespace root/hp/instrumentedBIOS -Class HP_BIOSSetting | Where-Object {$_.Name -match "Legacy"}).CurrentValue

    Write-Host "Legacy Boot Options are currently set to: $LegacyBootOptions"

    if (-not $ReportOnly) {
        if ($LegacyBootOptions -eq "Enable") {
            Write-Host "Legacy Boot Options are enabled. Disabling legacy boot and enabling Secure Boot..."
            Enable-SecureBoot "Legacy Boot Options" "Disable"
           
        } else {
            Write-Host "Legacy Boot already disabled."
        }
    }

    # Check Configure Legacy Support and Secure Boot setting
    $LegacySecureBootConfig = (Get-WmiObject -Namespace root/hp/instrumentedBIOS -Class HP_BIOSSetting | Where-Object {$_.Name -eq "Configure Legacy Support and Secure Boot"}).CurrentValue

    Write-Host "Legacy Config: $LegacySecureBootConfig"

    if (-not $ReportOnly) {
        if ($LegacySecureBootConfig -eq "Legacy Support Disable and Secure Boot Disable") {
            Write-Host "Secure Boot is disabled in the legacy configuration. Attempting to enable Secure Boot..."
            Enable-SecureBoot "Configure Legacy Support and Secure Boot" "Legacy Support Disable and Secure Boot Enable"
            
        } else {
            Write-Host "Secure Boot is already configured properly."
        }
    }
}


# Suspend BitLocker (only if remediation is being performed)
if (-not $ReportOnly -and $settingupdate -eq $true) {
    Suspend-BitLocker -MountPoint "C:" -RebootCount 1
    Write-Host "BitLocker suspended on C: drive."
    Write-Host "Rebooting to apply changes..."
   # Restart-Computer -Force
}


