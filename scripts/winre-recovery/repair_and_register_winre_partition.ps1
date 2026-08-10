#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Repairs or creates a dedicated Windows Recovery Partition.

.DESCRIPTION
    A robust remediation tool for broken or missing WinRE environments:
    1. Checks current WinRE status.
    2. Fetches 'Winre.wim' from a network share if missing locally.
    3. If no recovery partition exists, it shrinks the boot partition to
       create a new recovery partition (default 800MB).
    4. Formats and sets the partition to the correct 'Recovery' GUID.
    5. Registers the 'Winre.wim' image using 'reagentc /setreimage'.
    6. Enables WinRE and hides the recovery partition.

.PARAMETER RecoveryPartitionSizeMB
    Size in MB for a newly created recovery partition. Default: 800.

.PARAMETER WinreSourcePath
    Local path to Winre.wim. Default: C:\Windows\System32\Recovery\Winre.wim

.PARAMETER NetworkWinreSource
    UNC fallback if the local Winre.wim is missing.

.PARAMETER BitLockerMountPoint
    Volume to suspend BitLocker on before partition work. Default: C:

.NOTES
    Original Filename: AutoSaved_7bcd3f1b-fc5a-4630-a2a7-b46f18e3f9e4_Untitled307.ps1
    Wrapper alias: repair_winre_with_network_fallback.ps1
#>

[CmdletBinding()]
param(
    [int]$RecoveryPartitionSizeMB = 800,
    [string]$WinreSourcePath = "C:\Windows\System32\Recovery\Winre.wim",
    [string]$NetworkWinreSource = "\\corp\dfs\Temp\DE\WinRe-Repair\winre.wim",
    [string]$BitLockerMountPoint = "C:"
)

# Check if WinRE is already enabled
$winreStatus = (& reagentc /info) | Select-String -Pattern "Windows RE status" | ForEach-Object { $_.Line.Split(':')[1].Trim() }
if ($winreStatus -eq "Enabled") {
    Write-Output "Windows Recovery Environment is already enabled. No changes needed."
    exit 0
}

# Suspend BitLocker to prevent issues
if (Get-Command Suspend-BitLocker -ErrorAction SilentlyContinue) {
    Suspend-BitLocker -MountPoint $BitLockerMountPoint -RebootCount 1
}

# Check if Winre.wim exists; if not, copy from network share
if (!(Test-Path $WinreSourcePath)) {
    Write-Host "Winre.wim not found in the system. Attempting to copy from network share..."
    if (Test-Path $NetworkWinreSource) {
        Copy-Item -Path $NetworkWinreSource -Destination $WinreSourcePath -Force
        Write-Output "Winre.wim copied successfully from network share."
    } else {
        Write-Error "Winre.wim is missing, and network source is unavailable. Exiting..."
        exit 1
    }
}

# Get the disk number and primary partition (assuming single disk system)
$disk = Get-Disk | Where-Object IsSystem -eq $true
$partition = Get-Partition -DiskNumber $disk.Number | Where-Object IsBoot -eq $true

# Check if a recovery partition already exists
$existingRecoveryPartition = Get-Partition -DiskNumber $disk.Number | Where-Object { $_.Type -eq "Recovery" }
if ($existingRecoveryPartition) {
    Write-Output "A recovery partition already exists. Proceeding to configure WinRE..."
    $recoveryPartition = $existingRecoveryPartition | Select-Object -First 1
    if (-not $recoveryPartition.DriveLetter) {
        $recoveryPartition | Add-PartitionAccessPath -AssignDriveLetter
        $recoveryPartition = Get-Partition -DiskNumber $disk.Number -PartitionNumber $recoveryPartition.PartitionNumber
    }
    $driveLetter = $recoveryPartition.DriveLetter
} else {
    # Shrink primary partition to create space for the recovery partition
    Resize-Partition -DiskNumber $disk.Number -PartitionNumber $partition.PartitionNumber -Size ($partition.Size - ($RecoveryPartitionSizeMB * 1MB))

    # Create new recovery partition
    $recoveryPartition = New-Partition -DiskNumber $disk.Number -Size ($RecoveryPartitionSizeMB * 1MB) -AssignDriveLetter

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
Copy-Item -Path $WinreSourcePath -Destination $winreDestinationPath -Force
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
    exit 0
} else {
    Write-Error "Failed to enable Windows Recovery Environment."
    exit 1
}
