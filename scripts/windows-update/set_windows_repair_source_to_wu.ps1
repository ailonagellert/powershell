#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Configures Windows to use Windows Update for system file repair.

.DESCRIPTION
    This script modifies the registry to set 'RepairContentServerSource' to 2.
    This instructs Windows (DISM/SFC) to use Windows Update directly as a source
    for repairing corrupted system files or installing optional features, instead of
    relying on local images or WSUS.

.NOTES
#>

$regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Servicing"
$name = "RepairContentServerSource"

if (-not (Test-Path $regPath)) {
    New-Item -Path $regPath -Force | Out-Null
}

Write-Host "Setting Windows Repair Source to Windows Update (Value: 2)..."
Set-ItemProperty -Path $regPath -Name $name -Value 2 -Type DWord
