#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Remediates Windows Update policy sources to enable Microsoft Update.

.DESCRIPTION
    An Intune Remediation script that ensures the 'SetPolicyDrivenUpdateSource'
    registry keys are set to 0.
    This configuration forces the device to check for Quality, Driver, and
    Feature updates directly from Microsoft Update/WUfB rather than a
    local WSUS or SCCM endpoint.

    Actions:
    - Creates missing registry paths.
    - Sets values to 0 if they differ or are missing.
    - Restarts the 'wuauserv' service.
    - Triggers an immediate 'UsoClient StartScan'.

.NOTES
    Wrapper alias: remediate_windows_update_source_policies.ps1
#>

[CmdletBinding()]
param(
    [string]$RegistryPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
)

$registryValues = @(
    "SetPolicyDrivenUpdateSourceForQualityUpdates",
    "SetPolicyDrivenUpdateSourceForDriverUpdates",
    "SetPolicyDrivenUpdateSourceForOtherUpdates",
    "SetPolicyDrivenUpdateSourceForFeatureUpdates"
)

if (-not (Test-Path $RegistryPath)) { New-Item $RegistryPath -Force | Out-Null }

$remediated = $false

foreach ($value in $registryValues) {
    $current = Get-ItemProperty -Path $RegistryPath -Name $value -ErrorAction SilentlyContinue
    if ($null -eq $current -or $current.$value -ne 0) {
        Write-Output "Remediating $value to 0..."
        Set-ItemProperty -Path $RegistryPath -Name $value -Value 0 -Type DWord
        $remediated = $true
    }
}

if ($remediated) {
    Write-Output "Restarting Windows Update service and triggering scan..."
    Restart-Service wuauserv -Force
    Start-Process -FilePath "UsoClient.exe" -ArgumentList "StartScan"
    exit 0 # Remediated
} else {
    Write-Output "Compliance confirmed."
    exit 0 # Compliant
}
