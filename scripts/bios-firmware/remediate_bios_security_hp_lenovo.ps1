<#
.SYNOPSIS
    Definitive BIOS Security Remediator for HP and Lenovo.

.DESCRIPTION
    A multi-vendor BIOS remediation tool that:
    1. Detects system manufacturer (HP vs Lenovo).
    2. HP Logic: Enables Secure Boot by disabling 'Legacy Boot Options' 
       or configuring 'Legacy Support and Secure Boot' profiles.
    3. Lenovo Logic: Enables Secure Boot via 'Lenovo_SetBiosSetting'.
    4. Boot Order: Audits the primary boot sequence and re-prioritizes 
       NVMe/SSD/M.2 drives to the top of the list for compliance.
    5. Suspends BitLocker automatically if changes are applied to 
       prevent recovery prompts.

.NOTES
    Original Filename: AutoSaved_060319d1-7515-445b-ad05-2515fb3d80ac_Untitled578.ps1
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
    $result = (Get-WmiObject -Namespace root\wmi -Class Lenovo_SetBiosSetting).SetBiosSetting("$TargetValue")
    }
    catch {
    Write-Host "trying secureboot,enable"
    $result = (Get-WmiObject -Namespace root\wmi -Class Lenovo_SetBiosSetting).SetBiosSetting("SecureBoot,Enable")
    }

    if ($result.Return -eq "Success") {
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
function Check-HP-SecureBoot {
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

function Check-Lenovo-SecureBoot {
    $secureBootSetting = Get-WmiObject -Namespace root\wmi -Class Lenovo_BiosSetting | Where-Object { $_.CurrentSetting -match "SecureBoot" -or $_.CurrentSetting -match "Secure Boot"}
    $bootorder = (Get-WmiObject -Class Lenovo_BiosSetting -Namespace root\wmi | Where-Object { $_.CurrentSetting -imatch "BootOrder," -or $_.CurrentSetting -match "PrimaryBootSequence,"} ).CurrentSetting

    if ($secureBootSetting) {
        $settingname = $secureBootSetting.CurrentSetting.Split(",")[0]
        $currentValue = $secureBootSetting.CurrentSetting.Split(",")[1].Split(";")[0]
        $availableOptions = ($secureBootSetting.CurrentSetting -replace "^.*\[(.*)\].*$", '$1' -split ",")

        Write-Host "Lenovo Secure Boot is set to: $currentValue"
        Write-Host "Available options: $($availableOptions -join ", ")"
         

        if (-not $ReportOnly -and $currentValue -match "Disabled|Disable" -and $availableOptions -match "Enabled|Disable") {
            
            if ($bootorder) {
                Check-BootOrderCompliance -CurrentBootOrder $bootorder
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



 function Reorder-BootOrder {
    param (
        [string]$CurrentBootOrder
    )

    # Extract devices from the BootOrder string
    $devices = ($BootOrder -split ",")[1], "" -split ":"
   
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
function Check-BootOrderCompliance {
    param (
        [string]$CurrentBootOrder
    )

    # Extract devices from the BootOrder string
    $devices = ($CurrentBootOrder -split ",")[1], "" -split ":"

    # Check if the first device is NVMe, HDD, or M.2
    if ($devices[0] -match "^(NVMe|HDD||M\.2)") {
        Write-Host "Compliant: $CurrentBootOrder"
        return $CurrentBootOrder
    } else {
    
        Write-Host "Non-Compliant: $CurrentBootOrder"
        if (-not $ReportOnly) {
        Write-Host "Reordering boot order..."
        $reorderedBootOrder = Reorder-BootOrder -CurrentBootOrder $CurrentBootOrder
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
    $settingUpdated = Check-HP-SecureBoot
} elseif ($manufacturer -match "Lenovo") {
    $settingUpdated = Check-Lenovo-SecureBoot
} else {
    Write-Host "This script is only designed for HP and Lenovo systems."
    exit
}

# Suspend BitLocker and reboot if changes were made (only in non-report mode)
if (-not $ReportOnly -and $settingUpdated -eq $true) {
    Suspend-BitLocker -MountPoint "C:" -RebootCount 1 | Out-Null
    Write-Host "BitLocker suspended on C: drive."
    Write-Host "Rebooting to apply changes..."
    #msg * "The system will restart in 1 minute to apply BIOS changes. Please save your work."
    #exit-pssession
    #Start-Sleep -Seconds 60
    #& shutdown /r /f /t 60
    #exit 3010
}

