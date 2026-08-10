#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Configures Secure Boot settings on HP and Lenovo systems.

.DESCRIPTION
    This script detects the computer manufacturer (HP or Lenovo) and attempts to enable Secure Boot.
    It includes specific logic for handling BIOS settings via WMI for each vendor.
    If changes are made and not in ReportOnly mode, it suspends BitLocker and exits 3010
    (Intune soft-reboot) so the caller can schedule restart.

.PARAMETER ReportOnly
    If specified, the script will only report the current status without making any changes.

.EXAMPLE
    .\configure_secure_boot.ps1
    Runs the script and applies changes if necessary.

.EXAMPLE
    .\configure_secure_boot.ps1 -ReportOnly
    Runs the script in report mode without applying changes.

.NOTES
    Requires administrative privileges to modify BIOS settings and suspend BitLocker.
    Specific WMI namespaces are used for HP (root/hp/instrumentedBIOS) and Lenovo (root\wmi).
    Canonical for the near-duplicate remediate_bios_security_hp_lenovo.ps1 (wrapper).
    Related (kept intentionally — Lenovo boot-order / DeviceGuard variants differ):
      enable_secure_boot_hp_and_lenovo.ps1, remediate_secure_boot_hp_lenovo_integrated.ps1,
      configure_secure_boot_hp_lenovo.ps1
#>

param (
    [switch]$ReportOnly
)

# Function to get the computer manufacturer
function Get-ComputerManufacturer {
    # Retrieve manufacturer information from Win32_ComputerSystem WMI class
    $manufacturer = Get-WmiObject -Class Win32_ComputerSystem | Select-Object -ExpandProperty Manufacturer
    return $manufacturer
}

# Function to enable Secure Boot on HP systems
function Enable-HP-SecureBoot {
    param (
        [string]$SettingName,
        [string]$TargetValue
    )

    # Set the desired BIOS setting on HP using HP_BIOSSettingInterface
    $result = (Get-WmiObject -Namespace root/hp/instrumentedBIOS -Class HP_BIOSSettingInterface).SetBIOSSetting($SettingName, $TargetValue)

    # Check the result
    if ($result.Return -eq 0) {
        Write-Host "$SettingName has been successfully set to $TargetValue."
    } else {
        Write-Host "Failed to set $SettingName. Error code: $($result.Return)"
    }
}
#(Get-WmiObject -Namespace root\wmi -Class Lenovo_SetBiosSetting).SetBiosSetting("SecurityChip,Enable")
# Function to enable Secure Boot on Lenovo systems
function Enable-Lenovo-SecureBoot {
    param (
        [string]$TargetValue
    )

    Write-Host "Attempting to set Secure Boot to $TargetValue on Lenovo system..."
    try {
    Write-Host "trying targetvalue" $TargetValue
    # Attempt to set BIOS setting using the provided target value
    $result = (Get-WmiObject -Namespace root\wmi -Class Lenovo_SetBiosSetting).SetBiosSetting("$TargetValue")
    }
    catch {
    # Fallback attempt if the first method fails
    Write-Host "trying secureboot,enable"
    $result = (Get-WmiObject -Namespace root\wmi -Class Lenovo_SetBiosSetting).SetBiosSetting("SecureBoot,Enable")
    }

    if ($result.Return -eq "Success") {
        # Save BIOS settings if the set operation was successful
        $saveResult = (Get-WmiObject -Namespace root\wmi -Class Lenovo_SaveBiosSettings).SaveBiosSettings()
        if ($saveResult.Return -eq "Success") {
            Write-Host "Secure Boot has been successfully enabled and settings saved."
            $settingUpdated = $true

        } else {
            Write-Host "Failed to save BIOS settings. Error code: $($saveResult.Return)"
        }
    } else {
        Write-Host "Failed to set Secure Boot to $TargetValue on Lenovo. Error code: $($result.Return)"
    }
}

# Function to check and enable Secure Boot on HP systems
function Test-HPSecureBoot {
    $settingUpdated = $false

    # Check for Secure Boot setting first
    $secureBootSetting = (Get-WmiObject -Namespace root/hp/instrumentedBIOS -Class HP_BIOSSetting | Where-Object {$_.Name -eq "Secure Boot"}).CurrentValue

    if ($secureBootSetting) {
        Write-Host "HP Secure Boot: $secureBootSetting"

        if (-not $ReportOnly) {
            if ($secureBootSetting -eq "Disable") {
                Write-Host "Attempting to enable Secure Boot on HP..."
                Enable-HP-SecureBoot "Secure Boot" "Enable"
                $settingUpdated = $true
            } else {
                Write-Host "Secure Boot is already enabled on HP."
            }
        }
    } else {
        Write-Host "Secure Boot setting not found. Checking Legacy Boot Options..."

        # Check Legacy Boot Options as fallback
        $LegacyBootOptions = (Get-WmiObject -Namespace root/hp/instrumentedBIOS -Class HP_BIOSSetting | Where-Object {$_.Name -match "Legacy Boot Options"}).CurrentValue
        #"UEFI Boot Order

        Write-Host "Legacy Boot Options: $LegacyBootOptions"

        if (-not $ReportOnly) {
            if ($LegacyBootOptions -eq "Enable") {
                Write-Host "Disabling legacy boot and enabling Secure Boot on HP..."
                Enable-HP-SecureBoot "Legacy Boot Options" "Disable"
                $settingUpdated = $true
            } else {
                Write-Host "Legacy Boot Options are already disabled on HP."
            }
        }

        # Check Configure Legacy Support and Secure Boot setting
        $LegacySecureBootConfig = (Get-WmiObject -Namespace root/hp/instrumentedBIOS -Class HP_BIOSSetting | Where-Object {$_.Name -eq "Configure Legacy Support and Secure Boot"}).CurrentValue

        Write-Host "Configure Legacy Support and Secure Boot: $LegacySecureBootConfig"

        if (-not $ReportOnly) {
            if ($LegacySecureBootConfig -eq "Legacy Support Disable and Secure Boot Disable" -or $LegacySecureBootConfig -eq "Legacy Support Enable and Secure Boot Disable") {
                Write-Host "Attempting to enable Secure Boot on HP..."
                Enable-HP-SecureBoot "Configure Legacy Support and Secure Boot" "Legacy Support Disable and Secure Boot Enable"
                $settingUpdated = $true
            } else {
                Write-Host "Secure Boot is already configured properly on HP."
            }
        }
    }

    return $settingUpdated
}

# Function to check and enable Secure Boot on Lenovo systems
function Test-LenovoSecureBoot {
    # Retrieve Secure Boot setting from Lenovo_BiosSetting
    $secureBootSetting = Get-WmiObject -Namespace root\wmi -Class Lenovo_BiosSetting | Where-Object { $_.CurrentSetting -match "SecureBoot" -or $_.CurrentSetting -match "Secure Boot"}
    # Retrieve Boot Order setting
    $bootorder = (Get-WmiObject -Class Lenovo_BiosSetting -Namespace root\wmi | Where-Object { $_.CurrentSetting -imatch "BootOrder," -or $_.CurrentSetting -match "PrimaryBootSequence,"} ).CurrentSetting

    if ($secureBootSetting) {
        # Parse setting name and current value
        $settingname = $secureBootSetting.CurrentSetting.Split(",")[0]
        $currentValue = $secureBootSetting.CurrentSetting.Split(",")[1].Split(";")[0]
        # Extract available options from the setting string
        $availableOptions = ($secureBootSetting.CurrentSetting -replace "^.*\[(.*)\].*$", '$1' -split ",")

        Write-Host "Lenovo Secure Boot is set to: $currentValue"
        Write-Host "Available options: $($availableOptions -join ", ")"
         

        if (-not $ReportOnly -and $currentValue -match "Disabled|Disable" -and $availableOptions -match "Enabled|Disable") {
            
            if ($bootorder) {
                # Check boot order compliance before enabling Secure Boot
                Test-BootOrderCompliance -CurrentBootOrder $bootorder
            }
            if ($currentValue -eq "Disable") {
            Enable-Lenovo-SecureBoot "$settingname,Enable"
            
            $settingUpdated = $true
           } else {
             Enable-Lenovo-SecureBoot "$settingname,Enabled"
            
            $settingUpdated = $true
            }

             return $true
        } else {
            Write-Host "Secure Boot is already enabled or no changes needed."
             return $false
        }
    } else {
        Write-Host "Secure Boot setting not found for Lenovo."
         return $false
    }
}



 # Function to reorder boot devices to prioritize NVMe/HDD/M.2
function Set-PreferredBootOrder {
    param (
        [string]$CurrentBootOrder
    )

    # Extract devices from the BootOrder string
    $devices = ($CurrentBootOrder -split ",")[1], "" -split ":"

    # Remove duplicates and trim extra spaces
    $devices = $devices | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" } | Select-Object -Unique

    # Define prioritized devices
    $priorityDevices = $devices | Where-Object { $_ -imatch "^(NVMe|HDD|M\.2)" }
    $remainingDevices = ($devices | Where-Object { $_ -notin $priorityDevices })

    # Combine prioritized and remaining devices
    $reorderedDevices = $priorityDevices + $remainingDevices
    $newBootOrder = "BootOrder," + ($reorderedDevices -join ":")

    # Apply the new boot order
    $result = (Get-WmiObject -Class Lenovo_SetBiosSetting -Namespace root\wmi).SetBiosSetting($newBootOrder).Return

    if ($result -eq "Success") {
        Write-Host "Boot order successfully updated to: $newBootOrder"
        return $true
    } else {
        Write-Host "Failed to update boot order. Error: $result"
        return $false
    }
}

# Function to check compliance
function Test-BootOrderCompliance {
    param (
        [string]$CurrentBootOrder
    )

    # Extract devices from the BootOrder string
    $devices = ($CurrentBootOrder -split ",")[1], "" -split ":"

    # Check if the first device is NVMe, HDD, or M.2
    if ($devices[0] -match "^(NVMe|HDD|M\.2)") {
        Write-Host "Compliant: $CurrentBootOrder"
        return $CurrentBootOrder
    } else {

        Write-Host "Non-Compliant: $CurrentBootOrder"
        if (-not $ReportOnly) {
            Write-Host "Reordering boot order..."
            $reorderedBootOrder = Set-PreferredBootOrder -CurrentBootOrder $CurrentBootOrder
            Write-Host "Updated BootOrder: $reorderedBootOrder"
            return $reorderedBootOrder
        }
    }
}



# Main logic
$manufacturer = Get-ComputerManufacturer
$settingUpdated = $false

#Write-Host "Detected manufacturer: $manufacturer"

if ($manufacturer -match "HP" -or $manufacturer -match "Hewlett-Packard") {
    $settingUpdated = Test-HPSecureBoot
} elseif ($manufacturer -match "Lenovo") {
    $settingUpdated = Test-LenovoSecureBoot
} else {
    Write-Host "This script is only designed for HP and Lenovo systems."
    exit 0
}

# Suspend BitLocker; signal soft reboot needed (Intune 3010) when changes were made
if (-not $ReportOnly -and $settingUpdated -eq $true) {
    Suspend-BitLocker -MountPoint "C:" -RebootCount 1 | Out-Null
    Write-Host "BitLocker suspended on C: drive."
    Write-Host "BIOS changes applied; reboot required (exit 3010)."
    exit 3010
}
