<#
.SYNOPSIS
    Comprehensive Battery Diagnostic and Health Report.

.DESCRIPTION
    A deep-dive battery analysis tool that:
    1. Gathers hardware specifics (Manufacturer, Model, Chassis Type).
    2. Retrieves real-time battery telemetry (Chemistry, Voltage, Status).
    3. Calculates estimated run time and charge percentage.
    4. Automatically generates a Windows 'batteryreport' on Windows 8+.
    5. Outputs a summary of system load (CPU/Processes) alongside health.

.NOTES
    Original Filename: AutoSaved_7af274e2-377e-4f93-9d84-61cedc02ff10_Untitled156.ps1
#>

<#
Get-BatteryInfo.ps1
#>


$path = $env:temp
$computer = $env:COMPUTERNAME
$timestamp = Get-Date -UFormat "%Y%m%d"
$empty_line = ""

$batteries = Get-WmiObject Win32_Battery -ComputerName $computer
$compsys = Get-WmiObject -class Win32_ComputerSystem -ComputerName $computer
$compsysprod = Get-WMIObject -class Win32_ComputerSystemProduct -ComputerName $computer
$enclosure = Get-WmiObject -Class Win32_SystemEnclosure -ComputerName $computer
$number_of_batteries = ($batteries | Measure-Object).Count
$os = Get-WmiObject -Class Win32_OperatingSystem -ComputerName $computer 


$obj_battery = @()

    ForEach ($battery in $batteries) {


        Switch ($enclosure.ChassisTypes) {
            { $_ -lt 1 } { $chassis = "" }            
            { $_ -eq 1 } { $chassis = "Other" }
            { $_ -eq 2 } { $chassis = "Unknown" }
            { $_ -eq 3 } { $chassis = "Desktop " }
            { $_ -eq 4 } { $chassis = "Low Profile Desktop" }
            { $_ -eq 5 } { $chassis = "Pizza Box" }
            { $_ -eq 6 } { $chassis = "Mini Tower" }
            { $_ -eq 7 } { $chassis = "Tower" }
            { $_ -eq 8 } { $chassis = "Portable" }
            { $_ -eq 9 } { $chassis = "Laptop" }
            { $_ -eq 10 } { $chassis = "Notebook" }
            { $_ -eq 11 } { $chassis = "Hand Held" }
            { $_ -eq 12 } { $chassis = "Docking Station" }
            { $_ -eq 13 } { $chassis = "All in One" }
            { $_ -eq 14 } { $chassis = "Sub Notebook" }
            { $_ -eq 15 } { $chassis = "Space-Saving" }
            { $_ -eq 16 } { $chassis = "Lunch Box" }
            { $_ -eq 17 } { $chassis = "Main System Chassis" }
            { $_ -eq 18 } { $chassis = "Expansion Chassis" }
            { $_ -eq 19 } { $chassis = "SubChassis" }
            { $_ -eq 20 } { $chassis = "Bus Expansion Chassis" }
            { $_ -eq 21 } { $chassis = "Peripheral Chassis" }
            { $_ -eq 22 } { $chassis = "Storage Chassis" }
            { $_ -eq 23 } { $chassis = "Rack Mount Chassis" }
            { $_ -eq 24 } { $chassis = "Sealed-Case PC" }
            { $_ -gt 24 } { $chassis = "" }            
        } # switch chassistypes

            $is_a_laptop = $false

                If ($enclosure | Where-Object { $_.ChassisTypes -eq 9 -or $_.ChassisTypes -eq 10 -or $_.ChassisTypes -eq 14}) {
                    $is_a_laptop = $true
                } # if




        Switch ($compsys.DomainRole) {
            { $_ -lt 0 } { $domain_role = "" }             
            { $_ -eq 0 } { $domain_role = "Standalone Workstation" }            
            { $_ -eq 1 } { $domain_role = "Member Workstation" }
            { $_ -eq 2 } { $domain_role = "Standalone Server" }
            { $_ -eq 3 } { $domain_role = "Member Server" }
            { $_ -eq 4 } { $domain_role = "Backup Domain Controller" }
            { $_ -eq 5 } { $domain_role = "Primary Domain Controller" }
            { $_ -gt 5 } { $domain_role = "" }             
        } # switch domainrole




        Switch ($compsys.PCSystemType) {
            { $_ -lt 0 } { $pc_type = "" }             
            { $_ -eq 0 } { $pc_type = "Unspecified" }            
            { $_ -eq 1 } { $pc_type = "Desktop" }
            { $_ -eq 2 } { $pc_type = "Mobile" }
            { $_ -eq 3 } { $pc_type = "Workstation" }
            { $_ -eq 4 } { $pc_type = "Enterprise Server" }
            { $_ -eq 5 } { $pc_type = "Small Office and Home Office (SOHO) Server" }
            { $_ -eq 6 } { $pc_type = "Appliance PC" }
            { $_ -eq 7 } { $pc_type = "Performance Server" }
            { $_ -eq 8 } { $pc_type = "Maximum" }     
            { $_ -gt 8 } { $pc_type = "" }                                              
        } # switch pcsystemtype




        Switch ($os.ProductType) {   
            { $_ -lt 1 } { $product_type = "" }                  
            { $_ -eq 1 } { $product_type = "Work Station" }
            { $_ -eq 2 } { $product_type = "Domain Controller" }
            { $_ -eq 3 } { $product_type = "Server" }
            { $_ -gt 3 } { $product_type = "" }             
        } # switch producttype




        Switch ($battery.Availability) {
            { $_ -lt 1 } { $availability = "" }            
            { $_ -eq 1 } { $availability = "Other" }
            { $_ -eq 2 } { $availability = "Unknown" }
            { $_ -eq 3 } { $availability = "Running or Full Power" }
            { $_ -eq 4 } { $availability = "Warning" }
            { $_ -eq 5 } { $availability = "In Test" }
            { $_ -eq 6 } { $availability = "Not Applicable" }
            { $_ -eq 7 } { $availability = "Power Off" }
            { $_ -eq 8 } { $availability = "Off Line" }
            { $_ -eq 9 } { $availability = "Off Duty" }
            { $_ -eq 10 } { $availability = "Degraded" }
            { $_ -eq 11 } { $availability = "Not Installed" }
            { $_ -eq 12 } { $availability = "Install Error" }
            { $_ -eq 13 } { $availability = "Power Save - Unknown: The device is known to be in a power save mode, but its exact status is unknown." }
            { $_ -eq 14 } { $availability = "Power Save - Low Power Mode: The device is in a power save state but still functioning, and may exhibit degraded performance." }
            { $_ -eq 15 } { $availability = "Power Save - Standby: The device is not functioning, but could be brought to full power quickly." }
            { $_ -eq 16 } { $availability = "Power Cycle" }
            { $_ -eq 17 } { $availability = "Power Save - Warning: The device is in a warning state, though also in a power save mode." }
            { $_ -eq 18 } { $availability = "Paused: The device is paused." }
            { $_ -eq 19 } { $availability = "Not Ready: The device is not ready." }
            { $_ -eq 20 } { $availability = "Not Configured: The device is not configured." }
            { $_ -eq 21 } { $availability = "Quiesced: The device is quiet." }
            { $_ -gt 21 } { $availability = "" }             
        } # switch availability




        Switch ($battery.BatteryStatus) {
            { $_ -lt 1 } { $status = "" }            
            { $_ -eq 1 } { $status = "Other: The battery is discharging." }
            { $_ -eq 2 } { $status = "Unknown: The system has access to AC so no battery is being discharged. However, the battery is not necessarily charging." }
            { $_ -eq 3 } { $status = "Fully Charged" }
            { $_ -eq 4 } { $status = "Low" }
            { $_ -eq 5 } { $status = "Critical" }
            { $_ -eq 6 } { $status = "Charging" }
            { $_ -eq 7 } { $status = "Charging and High" }
            { $_ -eq 8 } { $status = "Charging and Low" }
            { $_ -eq 9 } { $status = "Charging and Critical" }
            { $_ -eq 10 } { $status = "Undefined" }
            { $_ -eq 11 } { $status = "Partially Charged" }
            { $_ -gt 11 } { $status = "" }             
        } # switch batterystatus




        Switch ($battery.Chemistry) {
            { $_ -lt 1 } { $chemistry = "" }            
            { $_ -eq 1 } { $chemistry = "Other" }
            { $_ -eq 2 } { $chemistry = "Unknown" }
            { $_ -eq 3 } { $chemistry = "Lead Acid" }
            { $_ -eq 4 } { $chemistry = "Nickel Cadmium" }
            { $_ -eq 5 } { $chemistry = "Nickel Metal Hydride" }
            { $_ -eq 6 } { $chemistry = "Lithium-ion" }
            { $_ -eq 7 } { $chemistry = "Zinc Air" }
            { $_ -eq 8 } { $chemistry = "Lithium Polymer" }
            { $_ -gt 8 } { $chemistry = "" }              
        } # switch chemistry




        Switch ($battery.PowerManagementCapabilities) {
            { $_ -lt 0 } { $power_management = "" }            
            { $_ -eq 0 } { $power_management = "Unknown" }
            { $_ -eq 1 } { $power_management = "Not Supported" }
            { $_ -eq 2 } { $power_management = "Disabled" }
            { $_ -eq 3 } { $power_management = "Enabled" }
            { $_ -eq 4 } { $power_management = "Power Saving Modes Entered Automatically" }
            { $_ -eq 5 } { $power_management = "Power State Settable" }
            { $_ -eq 6 } { $power_management = "Power Cycling Supported" }
            { $_ -eq 7 } { $power_management = "Timed Power On Supported" }
            { $_ -gt 7 } { $power_management = "" }              
        } # switch powermanagementcapabilities




        # Function used to calculate the Estimated Charge Remaining in a battery
        function Get-BatteryRunTime {
            param ()

            $charge_remaining = [timespan]::FromMinutes($battery.EstimatedRunTime)

            If ($charge_remaining.Days -ge 2) {
                $result = [string]$charge_remaining.Days + ' days ' + $charge_remaining.Hours + ' h ' + $charge_remaining.Minutes + ' min'
            } ElseIf ($charge_remaining.Days -gt 0) {
                $result = [string]$charge_remaining.Days + ' day ' + $charge_remaining.Hours + ' h ' + $charge_remaining.Minutes + ' min'
            } ElseIf ($charge_remaining.Hours -gt 0) {
                $result = [string]$charge_remaining.Hours + ' h ' + $charge_remaining.Minutes + ' min'
            } ElseIf ($charge_remaining.Minutes -gt 0) {
                $result = [string]$charge_remaining.Minutes + ' min ' + $charge_remaining.Seconds + ' sec'
            } ElseIf ($charge_remaining.Seconds -gt 0) {
                $result = [string]$charge_remaining.Seconds + ' sec'
            } Else {
                $result = [string]''
            } # else (if)

                If ($result.Contains(" 0 h")) {
                    $result = $result.Replace(" 0 h"," ")
                    } If ($result.Contains(" 0 min")) {
                        $result = $result.Replace(" 0 min"," ")
                        } If ($result.Contains(" 0 sec")) {
                        $result = $result.Replace(" 0 sec"," ")
                } # if ($result: first)

        $result

        } # function




        # Manufacturer
        $Manufacturer_data = $compsysprod.Vendor
        If ($Manufacturer_data.Contains("HP")) {
            $Manufacturer_data = $Manufacturer_data.Replace("HP","Hewlett-Packard")
        } # if




        $obj_battery += New-Object -TypeName PSCustomObject -Property @{


                'Battery Availability'              = $availability
                'Battery Chemistry'                 = $chemistry
                'Battery Class'                     = $battery.Description
                'Battery Name'                      = $battery.DeviceID
                'Battery Status'                    = $status
                'Battery Type'                      = $battery.Name
                'Battery Voltage'                   = [string](($battery.DesignVoltage) / 1000) + ' V'
                'Chassis'                           = $chassis
                'Computer'                          = $battery.SystemName
                'Computer Model'                    = $compsys.Model
                'Domain Role'                       = $domain_role               
                'Estimated Charge Remaining'        = [string]($battery.EstimatedChargeRemaining) + ' %'
                'Estimated Run Time'                = (Get-BatteryRunTime)
                'Is a Laptop?'                      = $is_a_laptop
                'Manufacturer'                      = $Manufacturer_data
                'PC Type'                           = $pc_type                
                'Power Management Capabilities'     = $power_management
                'Product Type'                      = $product_type
                'Status'                            = $battery.Status
                'System Type'                       = $compsys.SystemType
                'Total Number of Batteries'         = $number_of_batteries


                } # New-Object
            $obj_battery.PSObject.TypeNames.Insert(0,"Battery")
            $obj_battery_selection = $obj_battery | Select-Object 'Computer','Manufacturer','Computer Model','System Type','Domain Role','Product Type','Chassis','PC Type','Is a Laptop?','Total Number of Batteries','Battery Class','Battery Name','Battery Type','Estimated Charge Remaining','Estimated Run Time','Battery Voltage','Battery Availability','Battery Status','Battery Chemistry','Power Management Capabilities','Status'


    } # foreach $battery




# Write the battery results in console
Write-Output $empty_line
Write-Output $empty_line
Write-Output $obj_battery_selection | Format-List




# Gather some data for a summary table
$gps = Get-Process | Measure-Object -Property ProcessName
$average_load = Get-WmiObject -Class Win32_Processor -ComputerName $computer | Measure-Object -property LoadPercentage -Average




# Write the summary table in console
Write-Output $empty_line
Write-Output "Processes: $($gps.Count)      Average CPU Load: $($average_load.Average) %      Battery Level: $($obj_battery | Select-Object -ExpandProperty 'Estimated Charge Remaining')      Remaining Battery Time: $($obj_battery | Select-Object -ExpandProperty 'Estimated Run Time')"
Write-Output $empty_line
Write-Output $empty_line
Write-Output $empty_line
Write-Output $empty_line




# Write a battery report (and an adjacent xml-file) in $path on Windows 8+ machines
# Source: http://www.zdnet.com/article/windows-10-tip-check-the-performance-of-your-laptop-battery/
# Source: Windows version numbers: https://msdn.microsoft.com/en-us/library/windows/desktop/ms724833%28v=vs.85%29.aspx
# Credit: Richard: "How to find the Windows version from the PowerShell command line?"
If (([System.Environment]::OSVersion.Version) -ge (New-Object 'Version' 6.2)) {

    # Determine the current directory                                                         # Credit: JaredPar and Matthew Pirocchi: "What's the best way to determine the location of the current PowerShell script?"
    $script_path = "C:\Temp"

    cd $path
    Start-Process PowerCfg -ArgumentList batteryreport | Out-Null
    cd $script_path 

} Else {
    $continue = $true
} # else

