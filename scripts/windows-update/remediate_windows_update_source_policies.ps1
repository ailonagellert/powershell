#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Remediates Windows Update policy source registry keys (wrapper).

.DESCRIPTION
    Thin wrapper that preserves this filename for existing Intune remediations.
    Canonical implementation: remediate_windows_update_policy_sources.ps1
#>

[CmdletBinding()]
param(
    [string]$RegistryPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
)

& "$PSScriptRoot\remediate_windows_update_policy_sources.ps1" @PSBoundParameters
exit $LASTEXITCODE
