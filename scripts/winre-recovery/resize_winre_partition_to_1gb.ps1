#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Resizes the Windows Recovery Partition to 1GB.

.DESCRIPTION
    Fixes Windows Update failures (like KB5034441) by expanding the 
    recovery partition:
    1. Identifies the system disk and the 'Recovery' partition (usually #1).
    2. Shrinks the C: partition to create 1GB of total space for recovery.
    3. Extends the Recovery partition to the 1GB target.
    4. Suspends BitLocker during the operation to ensure disk access.
    5. Verifies the final layout and 'reagentc /info' status.

.NOTES
#>

# 1. Verification
$disk = Get-Disk | Where-Object IsSystem -eq $true | Select-Object -First 1
$recovery = Get-Partition -DiskNumber $disk.Number | Where-Object { $_.Type -eq "Recovery" } | Select-Object -First 1
$main = Get-Partition -DiskNumber $disk.Number -DriveLetter C

if ($recovery.Size -ge 1GB) { Write-Host "Recovery partition already 1GB+."; exit 0 }

# 2. Preparation
$needed = 1GB - $recovery.Size
if ((Get-BitLockerVolume -MountPoint "C:").ProtectionStatus -eq "On") {
    Suspend-BitLocker -MountPoint "C:" -RebootCount 1
}

# 3. Execution
Write-Host "Shrinking C: to create space..." -ForegroundColor Cyan
Resize-Partition -DiskNumber $disk.Number -PartitionNumber $main.PartitionNumber -Size ($main.Size - $needed)

Write-Host "Extending Recovery..." -ForegroundColor Green
Resize-Partition -DiskNumber $disk.Number -PartitionNumber $recovery.PartitionNumber -Size 1GB

& reagentc /info
