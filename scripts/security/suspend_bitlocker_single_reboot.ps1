#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Suspends BitLocker on the system drive for a single reboot.

.DESCRIPTION
    This script suspends BitLocker protection on the C: drive with a reboot count of 1.
    This is useful before BIOS updates or partition changes to avoid triggering recovery mode.

.NOTES
#>

if (Get-BitLockerVolume -MountPoint "C:" -ErrorAction SilentlyContinue) {
    Write-Host "Suspending BitLocker on C: for 1 reboot..."
    Suspend-BitLocker -MountPoint "C:" -RebootCount 1
} else {
    Write-Host "BitLocker not enabled on C: drive."
}
