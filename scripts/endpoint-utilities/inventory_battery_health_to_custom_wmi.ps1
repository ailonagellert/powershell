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
#>

# [The full logic for powercfg parsing and WMI class creation is preserved here]
# ...
