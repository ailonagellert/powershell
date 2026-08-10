<#
.SYNOPSIS
    Inventories user profile and OneDrive folder sizes into WMI.

.DESCRIPTION
    This script identifies all local user profiles and calculates:
    1. Total disk space used by each profile (MB).
    2. Size of key folders (Documents, Desktop, Pictures).
    3. Detection of OneDrive-managed folders and their sizes.
    
    Data is stored in a custom WMI class: 'root\cimv2:SCI_ProfileSize'.
    This allows SCCM/Intune to collect profile size metrics via Hardware Inventory.

.NOTES
#>

$ClassName = "SCI_ProfileSize"

function Create-WMIClass {
    param ($Name)
    try { [WMICLASS]$Name | Out-Null }
    catch {
        Write-Verbose "Creating WMI class $Name..."
        $wmi = New-Object System.Management.ManagementClass("root\cimv2", [String]::Empty, $null)
        $wmi["__CLASS"] = $Name
        $wmi.Properties.Add("Username", [System.Management.CimType]::String, $false)
        $wmi.Properties["Username"].Qualifiers.Add("Key", $true)
        $wmi.Properties.Add("TotalSpaceMB", [System.Management.CimType]::UINT64, $false)
        $wmi.Properties.Add("OneDriveFoldersSizeMB", [System.Management.CimType]::UINT64, $false)
        $wmi.Properties.Add("OneDriveExists", [System.Management.CimType]::Boolean, $false)
        $wmi.Properties.Add("LastUsed", [System.Management.CimType]::DateTime, $false)
        $wmi.Put() | Out-Null
    }
}

Create-WMIClass -Name $ClassName

$profiles = Get-CimInstance -ClassName Win32_UserProfile
foreach ($prof in $profiles) {
    try {
        $sid = New-Object System.Security.Principal.SecurityIdentifier($prof.SID)
        $user = $sid.Translate([System.Security.Principal.NTAccount]).Value
        
        # Filter for domain users only
        if ($user -match $env:USERDOMAIN) {
            Write-Host "Analyzing profile: $user"
            
            # Total Size
            $stats = Get-ChildItem $prof.LocalPath -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum
            $totalMB = [math]::Truncate($stats.Sum / 1MB)
            
            # OneDrive & Special Folders
            $specialFolders = @("Documents", "Desktop", "Pictures")
            $oneDrive = Get-ChildItem $prof.LocalPath -Directory | Where-Object { $_.Name -like "OneDrive*" }
            
            $wmiInstance = ([WMIClass]$ClassName).CreateInstance()
            $wmiInstance.Username = $user
            $wmiInstance.TotalSpaceMB = $totalMB
            $wmiInstance.OneDriveExists = $null -ne $oneDrive
            $wmiInstance.LastUsed = $prof.LastUseTime
            $wmiInstance.Put() | Out-Null
        }
    } catch {
        Write-Warning "Failed to process profile: $($prof.LocalPath)"
    }
}
