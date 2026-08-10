<#
.SYNOPSIS
    Advanced WinRE repair with Network Source Fallback.

.DESCRIPTION
    The definitive version of the Windows Recovery Environment (WinRE) 
    remediator:
    1. Audits current WinRE status via reagentc.
    2. If Winre.wim is missing locally, it attempts to pull a clean copy 
       from a corporate DFS network share.
    3. Handles partition shrinking (800MB) to create a dedicated recovery 
       partition if none exists.
    4. Formats the partition as NTFS and sets the correct Recovery GUID.
    5. Registers and enables the new environment.

.NOTES
    Original Filename: AutoSaved_7bcd3f1b-fc5a-4630-a2a7-b46f18e3f9e4_Untitled307.ps1
#>

# Ensure running as administrator
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "You need to run this script as an administrator."
    exit 1
}

# Check if WinRE is already enabled
$winreStatus = (& reagentc /info) | Select-String -Pattern "Windows RE status" | ForEach-Object { $_.Line.Split(':')[1].Trim() }
if ($winreStatus -eq "Enabled") {
    Write-Output "Windows Recovery Environment is already enabled. No changes needed."
    #exit 0
}

# Suspend BitLocker to prevent issues
Suspend-BitLocker -MountPoint "C:" -RebootCount 1

# Define variables
$recoveryPartitionSizeMB = 800
$winreSourcePath = "C:\Windows\System32\Recovery\Winre.wim"
$networkWinreSource = "\\corp\dfs\Temp\DE\WinRe-Repair\winre.wim"

# Check if Winre.wim exists; if not, copy from network share
if (!(Test-Path $winreSourcePath)) {
    Write-host "Winre.wim not found in the system. Attempting to copy from network share..."
    if (Test-Path $networkWinreSource) {
        Copy-Item -Path $networkWinreSource -Destination $winreSourcePath -Force
        Write-Output "Winre.wim copied successfully from network share."
    } else {
        Write-Error "Winre.wim is missing, and network source is unavailable. Exiting..."
        #exit 1
    }
}

# Get the disk number and primary partition (assuming single disk system)
$disk = Get-Disk | Where-Object IsSystem -eq $true
$partition = Get-Partition -DiskNumber $disk.Number | Where-Object IsBoot -eq $true

# Check if a recovery partition already exists
$existingRecoveryPartition = Get-Partition -DiskNumber $disk.Number | Where-Object { $_.Type -eq "Recovery" }
if ($existingRecoveryPartition) {
    Write-Output "A recovery partition already exists. Proceeding to configure WinRE..."
} else {
    # Shrink primary partition to create space for the recovery partition
    $shrinkSizeMB = $recoveryPartitionSizeMB 
    Resize-Partition -DiskNumber $disk.Number -PartitionNumber $partition.PartitionNumber -Size ($partition.Size - ($shrinkSizeMB * 1MB))

    # Create new recovery partition
    $recoveryPartition = New-Partition -DiskNumber $disk.Number -Size ($recoveryPartitionSizeMB * 1MB) -AssignDriveLetter

    # Format the new partition
    $driveLetter = $recoveryPartition.DriveLetter
    Format-Volume -DriveLetter $driveLetter -FileSystem NTFS -NewFileSystemLabel "Recovery"

    # Set partition type to Windows Recovery
    Set-Partition -DiskNumber $disk.Number -PartitionNumber $recoveryPartition.PartitionNumber -NewDriveLetter $driveLetter
    Set-Partition -DiskNumber $disk.Number -PartitionNumber $recoveryPartition.PartitionNumber -PartitionType "DE94BBA4-06D1-4D40-A16A-BFD50179D6AC"

    Write-Output "Recovery partition created successfully."
}

# Copy WinRE.wim to the recovery partition
$winreDestinationPath = "$($driveLetter):\Recovery\Winre.wim"
New-Item -Path "$($driveLetter):\Recovery" -ItemType Directory -Force | Out-Null
Copy-Item -Path $winreSourcePath -Destination $winreDestinationPath -Force
Write-Output "WinRE.wim copied to recovery partition."

# Register new WinRE location
$partitionGuidPath = (Get-Partition -DiskNumber $disk.Number -PartitionNumber $recoveryPartition.PartitionNumber).AccessPaths[0]
Write-Output "Configuring Windows Recovery Environment..."
& reagentc /disable
& reagentc /setreimage /path $partitionGuidPath\Recovery\Winre.wim
& reagentc /enable

# Confirm configuration
$winreStatus = (& reagentc /info) | Select-String -Pattern "Windows RE status" | ForEach-Object { $_.Line.Split(':')[1].Trim() }
if ($winreStatus -eq "Enabled") {
    Write-Output "Windows Recovery Environment successfully enabled."
    Remove-PartitionAccessPath -DiskNumber $disk.Number -PartitionNumber $recoveryPartition.PartitionNumber -AccessPath "$driveLetter`:"
    Write-Output "The recovery partition has been hidden successfully."
    #exit 0
} else {
    Write-Error "Failed to enable Windows Recovery Environment."
    #exit 1
}

