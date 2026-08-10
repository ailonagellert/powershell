#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Restores public Windows Update connectivity by removing policy restrictions.

.DESCRIPTION
    This script removes registry keys often set by Group Policy or MDM that block 
    access to the public Windows Update service or disable the Windows Update UI.
    Keys removed:
    - DoNotConnectToWindowsUpdateInternetLocations
    - DisableWindowsUpdateAccess
    - NoAutoUpdate

.NOTES
#>

$wuPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
$auPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"

$policies = @(
    @{ Path = $wuPath; Name = "DoNotConnectToWindowsUpdateInternetLocations" },
    @{ Path = $wuPath; Name = "DisableWindowsUpdateAccess" },
    @{ Path = $auPath; Name = "NoAutoUpdate" }
)

foreach ($policy in $policies) {
    if (Get-ItemProperty -Path $policy.Path -Name $policy.Name -ErrorAction SilentlyContinue) {
        Write-Host "Removing policy restriction: $($policy.Name)..."
        Remove-ItemProperty -Path $policy.Path -Name $policy.Name -Force
    }
}

Write-Host "Windows Update connectivity policies restored."
