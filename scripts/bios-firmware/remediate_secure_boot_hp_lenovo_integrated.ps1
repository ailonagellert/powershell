#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Integrated HP and Lenovo Secure Boot and Boot Order remediator.

.DESCRIPTION
    A unified BIOS remediation script for modern enterprise fleets:
    - Vendor Detection: Automatically handles HP or Lenovo specific WMI.
    - HP Remediation: Uses 'root/hp/instrumentedBIOS' to disable Legacy 
      support and enable Secure Boot.
    - Lenovo Remediation: Uses 'root\wmi' to enable Secure Boot and 
      optimize 'PrimaryBootSequence' (NVMe/M.2 priority).
    - BitLocker Integration: Suspends BitLocker for 1 reboot if changes 
      are applied to prevent recovery prompt.
    - ReportOnly mode: Supports compliance auditing without modification.

.NOTES
    Kept as variant: Lenovo DeviceGuard path + active BitLocker suspend. See also enable_secure_boot_hp_and_lenovo.ps1.
    Original Filename: AutoSaved_73af9c9d-e9f1-48d2-8827-5b64a818fb10_Untitled596.ps1
#>

param (
    [switch]$ReportOnly
)

# Function to get the computer manufacturer
function Get-ComputerManufacturer {
    $manufacturer = Get-WmiObject -Class Win32_ComputerSystem | Select-Object -ExpandProperty Manufacturer
    return $manufacturer
}

# Function to enable Secure Boot on HP systems
function Enable-HP-SecureBoot {
    param (
        [string]$SettingName,
        [string]$TargetValue
    )

    # Set the desired BIOS setting on HP
    $result = (Get-WmiObject -Namespace root/hp/instrumentedBIOS -Class HP_BIOSSettingInterface).SetBIOSSetting($SettingName, $TargetValue)

    # Check the result
    if ($result.Return -eq 0) {
        Write-Host "Success : $SettingName set to $TargetValue."
    } else {
        Write-Host "Failed to set $SettingName. Error code: $($result.Return)"
    }
}


# Function to check and enable Secure Boot on HP systems
function Test-HPSecureBoot {
    $settingUpdated = $false

    # Check for Secure Boot setting first
    $secureBootSetting = (Get-WmiObject -Namespace root/hp/instrumentedBIOS -Class HP_BIOSSetting | Where-Object {$_.Name -eq "Secure Boot"}).CurrentValue

    if ($secureBootSetting) {
       # Write-Host "HP Secure Boot: $secureBootSetting"

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
        #Write-Host "Secure Boot setting not found. Checking Legacy Boot Options..."

        # Check Legacy Boot Options as fallback
        $LegacyBootOptions = (Get-WmiObject -Namespace root/hp/instrumentedBIOS -Class HP_BIOSSetting | Where-Object {$_.Name -match "Legacy Boot Options"}).CurrentValue
        #"UEFI Boot Order

        Write-Host "Legacy Boot Options: $LegacyBootOptions"

        if (-not $ReportOnly) {
            if ($LegacyBootOptions -eq "Enable") {
               
                Enable-HP-SecureBoot "Legacy Boot Options" "Disable"
                $settingUpdated = $true
            } else {
                Write-Host "Legacy Boot Options are already disabled on HP."
            }
        }

        # Check Configure Legacy Support and Secure Boot setting
        $LegacySecureBootConfig = (Get-WmiObject -Namespace root/hp/instrumentedBIOS -Class HP_BIOSSetting | Where-Object {$_.Name -eq "Configure Legacy Support and Secure Boot"}).CurrentValue

       # Write-Host "Configure Legacy Support and Secure Boot: $LegacySecureBootConfig"

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

function Test-LenovoSecureBoot {
    $secureBootSetting = Get-WmiObject -Namespace root\wmi -Class Lenovo_BiosSetting | Where-Object { $_.CurrentSetting -match "SecureBoot" -or $_.CurrentSetting -match "Secure Boot"}
    $bootorder = (Get-WmiObject -Class Lenovo_BiosSetting -Namespace root\wmi | Where-Object { $_.CurrentSetting -imatch "BootOrder," -or $_.CurrentSetting -match "PrimaryBootSequence,"} ).CurrentSetting

    if ($secureBootSetting) {
        $settingname = $secureBootSetting.CurrentSetting.Split(",")[0]
        $currentValue = $secureBootSetting.CurrentSetting.Split(",")[1].Split(";")[0]
        $availableOptions = ($secureBootSetting.CurrentSetting -replace "^.*\[(.*)\].*$", '$1' -split ",")

        
        

        if (-not $ReportOnly -and $currentValue -match "Disabled|Disable" -and $availableOptions -match "Enabled|Disable") {
            Write-Host "Lenovo Secure Boot is set to: $currentValue"
           if ($bootorder) {
                Test-BootOrderCompliance -CurrentBootOrder $bootorder
            }
           if ($currentValue -eq "Disable") {
            Enable-Lenovo-SecureBoot "DeviceGuard,Enabled"
            
            $settingUpdated = $true
           } 
           if ($currentValue -eq "Disabled") {
             Enable-Lenovo-SecureBoot "$settingname,Enabled"
            
            $settingUpdated = $true
            }
            
             return $true
        } else {
            Write-Host "Secure Boot is already enabled"
             return $false
        }
    } else {
        Write-Host "Secure Boot setting not found for Lenovo."
         return $false
    }
}
# Function to enable Secure Boot on Lenovo systems
function Enable-Lenovo-SecureBoot {
    param (
        [string]$TargetValue
    )

    Write-Host "Attempting to set Secure Boot to $TargetValue on Lenovo system..."
    try {
    $result = (Get-WmiObject -Namespace root\wmi -Class Lenovo_SetBiosSetting).SetBiosSetting("$TargetValue")
    }
    catch {
    $result = (Get-WmiObject -Namespace root\wmi -Class Lenovo_SetBiosSetting).SetBiosSetting("SecureBoot,Enabled")
    }

    if ($result.Return -eq "Success") {
        $saveResult = (Get-WmiObject -Namespace root\wmi -Class Lenovo_SaveBiosSettings).SaveBiosSettings()
        if ($saveResult.Return -eq "Success") {
            Write-Host "Success: Secure Boot enabled and settings saved."
            $settingUpdated = $true

        } else {
            Write-Host "Failed to save BIOS settings. Error code: $($saveResult.Return)"
        }
    } else {
        Write-Host "Failed to set Secure Boot to $TargetValue on Lenovo. Error code: $($result.Return)"
    }
}


 function Set-PreferredBootOrder {
    param (
        [string]$CurrentBootOrder
    )

    # Extract devices from the BootOrder string
    $devices = ($BootOrder -split ",")[1], "" -split ":"
    
    # Remove duplicates and trim extra spaces
    $devices = $devices | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" } | Select-Object -Unique

    # Define prioritized devices
    $priorityDevices = $devices | Where-Object { $_ -imatch "^(NVMe|HDD|M\.2)" }
    $remainingDevices = $devices + ":" | Where-Object { $_ -notin $priorityDevices }

    # Combine prioritized and remaining devices
    $reorderedDevices = $priorityDevices + ":" + $remainingDevices
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
        Write-Host "Bootorder Compliant"
        return $CurrentBootOrder
    } else {
    
        Write-Host "Non-Compliant: $CurrentBootOrder"
        if (-not $ReportOnly) {
        Write-Host "Reordering boot order..."
        $reorderedBootOrder = Set-PreferredBootOrder -CurrentBootOrder $CurrentBootOrder
        Write-Host "Updated BootOrder: $reorderedBootOrder"
        return $true
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
    exit
}

# Suspend BitLocker and reboot if changes were made (only in non-report mode)
if (-not $ReportOnly -and $settingUpdated -eq $true) {
    Suspend-BitLocker -MountPoint "C:" -RebootCount 1 | Out-Null
    Write-Host "BL suspended"
    #Write-Host "Rebooting to apply changes..."
   # msg * "The system will restart in 1 minute to apply BIOS changes. Please save your work."
    #n
    #Start-Sleep -Seconds 60
   # & shutdown /r /f /t 60
    #exit-pssession
    exit 3010
}

