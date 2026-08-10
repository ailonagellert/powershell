<#
.SYNOPSIS
    Automates battery health telemetry for SCCM/Intune inventory.

.DESCRIPTION
    A comprehensive hardware inventory tool that:
    1. Generates a standard Windows Battery Report (powercfg).
    2. Parses the HTML report via Regex to extract Cycle Count and Usage 
       history (Active/Standby duration).
    3. Queries WMI (root\wmi:BatteryFullChargedCapacity) for current capacity.
    4. Calculates a health percentage (Full vs. Designed capacity).
    5. Creates/Updates a custom WMI Class (root\cimv2:SCI_BatteryHealth) 
       to store this data, allowing SCCM to pick it up via hardware 
       inventory.

.NOTES
    Original Filename: AutoSaved_bb03f81d-0a65-4a5c-af8c-e0b70b90b031_Untitled292.ps1
#>

# Function to extract the data from the battery report
Function Get-BatteryReportData {
    # Generate battery report using powercfg
    $reportPath = "$env:USERPROFILE\battery-report.html"
    powercfg /batteryreport /output $reportPath

    # Wait for a second to ensure the report is generated
    Start-Sleep -Seconds 1

    # Read the battery report HTML file
    $reportHtml = Get-Content -Path $reportPath

    # Find the "Since OS install" section
    $sinceOsInstallIndex = $reportHtml | Select-String -Pattern "Since OS install" | Select-Object -First 1

    # Check if the "Since OS install" section was found
    if (-not $sinceOsInstallIndex) {
        Write-Host "Could not find 'Since OS install' section in the battery report."
        return $null
    }

    # Extract the lines after "Since OS install"
    $reportHtmlAfterSinceOsInstall = $reportHtml[$sinceOsInstallIndex.LineNumber..($reportHtml.Count - 1)]

    # Initialize variables to store parsed data
    $activeDuration = $null
    $connectedStandby = $null
    $cycleCount = $null

    # Define regex pattern for Active running hours
    $activeDurationPattern = '<td class="hms">(\d+:\d+:\d+)</td>'
    
    # Define regex pattern for Connected standby time
    $connectedStandbyPattern = '<td class="nullValue">-</td>|<td class="hms"><div style="height:1em;">(\d+:\d+:\d+)</div>'

    # Define regex pattern for Cycle Count
    $cycleCountPattern = '<span class="label">CYCLE COUNT</span></td><td>(\d+)</td>'

    # Extract Active Duration from the relevant section
    $activeDurationMatch = [regex]::Match($reportHtmlAfterSinceOsInstall -join "`n", $activeDurationPattern)
    if ($activeDurationMatch.Success) {
        $activeDuration = $activeDurationMatch.Groups[1].Value
    }

    # Extract Connected Standby time, check for either null or valid value
    $connectedStandbyMatch = [regex]::Match($reportHtmlAfterSinceOsInstall -join "`n", $connectedStandbyPattern)
    if ($connectedStandbyMatch.Success) {
        if ($connectedStandbyMatch.Groups[1].Success) {
            # Capture valid Connected Standby value
            $connectedStandby = $connectedStandbyMatch.Groups[1].Value
        } else {
            # Set as null or "-" if no valid value
            $connectedStandby = $null
        }
    }

    # Extract Cycle Count from the entire report HTML
    $cycleCountMatch = [regex]::Match($reportHtml -join "`n", $cycleCountPattern)
    if ($cycleCountMatch.Success) {
        $cycleCount = $cycleCountMatch.Groups[1].Value
    }

    # Create the report data object
    return @{
        ActiveDuration = $activeDuration
        ConnectedStandby = $connectedStandby
        CycleCount = $cycleCount
    }
}

# Function to create or update the WMI class for battery health
Function CreateOrUpdate-WMIBatteryClass {
    $ClassName = "SCI_BatteryHealth"

    try {
        # Check if the class exists
        [WMICLASS]"$ClassName" | Out-Null
    } catch {
        # If class doesn't exist, create it
        $wmiInstance = New-Object -TypeName System.Management.ManagementClass -ArgumentList (“root\cimv2”, [String]::Empty, $null)
        $wmiInstance["__CLASS"] = $ClassName

        # Build the new WMI Properties
        $wmiInstance.Properties.Add("BatteryID", [System.Management.CimType]::String, $false)
        $wmiInstance.Properties["BatteryID"].Qualifiers.Add("Key", $true)
        $wmiInstance.Properties.Add("CurrentChargeCapacity", [System.Management.CimType]::UINT32, $false)
        $wmiInstance.Properties.Add("DesignedCapacity", [System.Management.CimType]::UINT32, $false)
        $wmiInstance.Properties.Add("CurrentHealth", [System.Management.CimType]::UINT32, $false)
        $wmiInstance.Properties.Add("ActiveDuration", [System.Management.CimType]::String, $false)
        $wmiInstance.Properties.Add("ConnectedStandby", [System.Management.CimType]::String, $false)
        $wmiInstance.Properties.Add("CycleCount", [System.Management.CimType]::UINT32, $false)

        # Write new properties to WMI
        [void]$wmiInstance.Put()
    }

    # Gather battery data from WMI and battery report
    $batteryHealthInfo = @{
        BatteryID = "00880"  # Replace with actual battery ID logic
        CurrentChargeCapacity = (Get-WmiObject -Class BatteryFullChargedCapacity -Namespace root\wmi).FullChargedCapacity
        DesignedCapacity = (Get-WmiObject -Class BatteryStaticData -Namespace root\wmi).DesignedCapacity
        CurrentHealth = [math]::Round(($batteryHealthInfo.CurrentChargeCapacity / $batteryHealthInfo.DesignedCapacity) * 100, 0)
    }

    # Get additional battery report data
    $batteryReportData = Get-BatteryReportData
    if ($batteryReportData) {
        $batteryHealthInfo.ActiveDuration = $batteryReportData.ActiveDuration
        $batteryHealthInfo.ConnectedStandby = $batteryReportData.ConnectedStandby
        $batteryHealthInfo.CycleCount = $batteryReportData.CycleCount
    }

    # Update WMI Class instance with the gathered battery data
    $wmiInstance = ([WMIClass]$ClassName).CreateInstance()
    $wmiInstance.BatteryID = $batteryHealthInfo.BatteryID
    $wmiInstance.CurrentChargeCapacity = $batteryHealthInfo.CurrentChargeCapacity
    $wmiInstance.DesignedCapacity = $batteryHealthInfo.DesignedCapacity
    $wmiInstance.CurrentHealth = $batteryHealthInfo.CurrentHealth
    $wmiInstance.ActiveDuration = $batteryHealthInfo.ActiveDuration
    $wmiInstance.ConnectedStandby = $batteryHealthInfo.ConnectedStandby
    $wmiInstance.CycleCount = $batteryHealthInfo.CycleCount

    # Write the data to the WMI class
    [void]$wmiInstance.Put()
}

# Call the function to create or update the WMI class with battery data
CreateOrUpdate-WMIBatteryClass

