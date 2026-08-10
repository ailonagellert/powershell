#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Definitive BIOS Security Remediator for HP and Lenovo (wrapper).

.DESCRIPTION
    Thin wrapper that preserves this filename for existing deployments.
    Canonical implementation: configure_secure_boot.ps1

.PARAMETER ReportOnly
    If specified, only report status without making changes.

.NOTES
    Original Filename: AutoSaved_060319d1-7515-445b-ad05-2515fb3d80ac_Untitled578.ps1
#>

param (
    [switch]$ReportOnly
)

& "$PSScriptRoot\configure_secure_boot.ps1" @PSBoundParameters
exit $LASTEXITCODE
