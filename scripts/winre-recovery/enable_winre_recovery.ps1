#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Checks and enables the Windows Recovery Environment (WinRE).

.DESCRIPTION
    This script ensures that the Windows Recovery Environment is enabled on the system.
    It performs the following:
    1. Verifies administrative privileges.
    2. Checks the current status of WinRE.
    3. Verifies the existence of Winre.wim.
    4. Suspends BitLocker on the C: drive for one reboot to prevent recovery key prompts.
    5. Sets the recovery image path and enables WinRE using reagentc.

.NOTES
#>

# Ensure running as administrator
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "You need to run this script as an administrator."
    exit 1
}

# Define path to WinRE.wim
$winreSourcePath = "C:\Windows\System32\Recovery\Winre.wim"

# Check if WinRE is already enabled
$winreStatus = (& reagentc /info) | Select-String -Pattern "Windows RE status" | ForEach-Object { $_.Line.Split(':')[1].Trim() }
if ($winreStatus -eq "Enabled") {
    Write-Output "Windows Recovery Environment is already enabled. No changes needed."
    exit 0
}

# Check if Winre.wim exists in the standard location
if (Test-Path $winreSourcePath) {
    Write-Output "Found WinRE.wim at $winreSourcePath."
} else {
    Write-Error "WinRE.wim not found at $winreSourcePath. Exiting..."
    exit 1
}

# Enable WinRE
Write-Output "Enabling Windows Recovery Environment..."
Suspend-BitLocker -MountPoint "C:" -RebootCount 1
Start-Sleep 2

# Display current info
& reagentc /info

# Configure image path and enable
# Note: Using the standard device path for disk 0 partition 3
& reagentc /setreimage /path \\?\GLOBALROOT\device\harddisk0\partition3\Windows\System32\Recovery
& reagentc /enable

# Confirm configuration
$winreStatus = (& reagentc /info) | Select-String -Pattern "Windows RE status" | ForEach-Object { $_.Line.Split(':')[1].Trim() }
if ($winreStatus -eq "Enabled") {
    Write-Output "Windows Recovery Environment successfully enabled."
} else {
    Write-Error "Failed to enable Windows Recovery Environment."
}
