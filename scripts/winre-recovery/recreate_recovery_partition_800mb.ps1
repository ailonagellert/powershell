#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Resizes the system partition and recreates an 800MB Windows Recovery (WinRE) partition.

.DESCRIPTION
    This script is designed to resolve issues where the recovery partition is too small or missing.
    Actions:
    1. Shrinks the primary boot partition by ~850MB.
    2. Creates a new recovery partition in the freed space.
    3. Formats it as NTFS and labels it 'Recovery'.
    4. Sets the correct GPT Partition Type GUID for Recovery (DE94BBA4-06D1-4D40-A16A-BFD50179D6AC).
    5. Copies Winre.wim from the system recovery folder to the new partition.
    6. Registers and enables the new recovery image using reagentc.
    7. Hides the partition by removing its drive letter.

.NOTES
#>

# Ensure running as administrator
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "You need to run this script as an administrator."
    exit
}

# Suspend BitLocker for one reboot to prevent issues with partition changes
Suspend-BitLocker -MountPoint "c:" -RebootCount 1

# Define the size of the recovery partition in MB
$recoveryPartitionSizeMB = 800
$winreSourcePath = "C:\Windows\System32\Recovery\Winre.wim"

if (-not (Test-Path $winreSourcePath)) {
    Write-Error "Winre.wim not found at $winreSourcePath. Cannot continue."
    exit
}

# Get the system disk and the primary boot partition
$disk = Get-Disk | Where-Object IsSystem -eq $true
$partition = Get-Partition -DiskNumber $disk.Number | Where-Object IsBoot -eq $true

# Shrink the primary partition
Write-Output "Shrinking system partition..."
$shrinkSizeMB = $recoveryPartitionSizeMB + 50 
Resize-Partition -DiskNumber $disk.Number -PartitionNumber $partition.PartitionNumber -Size ($partition.Size - ($shrinkSizeMB * 1MB))

# Create the new recovery partition
Write-Output "Creating new recovery partition..."
$recoveryPartition = New-Partition -DiskNumber $disk.Number -Size ($recoveryPartitionSizeMB * 1MB) -AssignDriveLetter

# Format the new partition
$driveLetter = $recoveryPartition.DriveLetter
Format-Volume -DriveLetter $driveLetter -FileSystem NTFS -NewFileSystemLabel "Recovery"

# Set the partition ID to the Windows Recovery Environment GUID
Set-Partition -DiskNumber $disk.Number -PartitionNumber $recoveryPartition.PartitionNumber -NewDriveLetter $driveLetter
Set-Partition -DiskNumber $disk.Number -PartitionNumber $recoveryPartition.PartitionNumber -PartitionType "DE94BBA4-06D1-4D40-A16A-BFD50179D6AC"

# Copy the WinRE.wim file to the new recovery partition
$winreDestinationPath = "$($driveLetter):\Recovery\Winre.wim"
New-Item -Path "$($driveLetter):\Recovery" -ItemType Directory -Force
Copy-Item -Path $winreSourcePath -Destination $winreDestinationPath

# Get the GUID path of the new partition (assuming partition 4 based on typical layout)
$partitionGuidPath = (Get-Partition -DiskNumber $disk.Number -PartitionNumber $recoveryPartition.PartitionNumber).AccessPaths[0]

# Register the new WinRE location
Write-Output "Configuring Windows Recovery Environment..."
& reagentc /disable
& reagentc /setreimage /path $partitionGuidPath\Recovery\Winre.wim
& reagentc /enable

# Confirm the configuration
$reagentcInfo = & reagentc /info
Write-Output $reagentcInfo

# Hide the recovery partition
Remove-PartitionAccessPath -DiskNumber $disk.Number -PartitionNumber $recoveryPartition.PartitionNumber -AccessPath "$driveLetter`:"
Write-Output "The recovery partition has been hidden successfully."
